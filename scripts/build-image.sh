#!/usr/bin/env bash
# GitHub Actions 使用官方 25.12.6 ImageBuilder 构建，不执行不可信一键脚本。
set -Eeuo pipefail
PROFILE="${1:-base}"
case "$PROFILE" in base|lab) ;; *) echo "不支持的构建方案: $PROFILE" >&2; exit 2;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="25.12.6"
BASE_URL="https://downloads.openwrt.org/releases/$VERSION/targets/x86/64"
ARCHIVE="openwrt-imagebuilder-$VERSION-x86-64.Linux-x86_64.tar.zst"
EXPECTED_SHA="a792e29bd2233cda67a0823030bfb53c0b61fbb3836b2063e88adf89730d563b"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$ROOT/out/$PROFILE"
cd "$WORK"

echo "下载官方 ImageBuilder，版本 $VERSION"
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 -o "$ARCHIVE" "$BASE_URL/$ARCHIVE"
printf '%s  %s\n' "$EXPECTED_SHA" "$ARCHIVE" | sha256sum --check --status || {
  echo "官方 ImageBuilder SHA-256 不匹配，终止" >&2; exit 1;
}
tar --zstd -xf "$ARCHIVE"
IB="$WORK/${ARCHIVE%.tar.zst}"
test -d "$IB" || { echo "ImageBuilder 解包目录未找到" >&2; exit 1; }
mkdir -p "$IB/packages"

if [ "$PROFILE" = "lab" ]; then
  echo "下载经版本与 SHA-256 固定的第三方 APK"
  while IFS='|' read -r name url digest; do
    [ -n "$name" ] || continue
    case "$name" in \#*) continue;; esac
    case "$name" in
      *[!a-zA-Z0-9._-]*) echo "非法文件名 $name" >&2; exit 1 ;;
    esac
    case "$url" in
      https://github.com/vernesong/OpenClash/releases/download/*|https://github.com/jerrykuku/luci-theme-argon/releases/download/*|https://github.com/timsaya/luci-app-bandix-plus/releases/download/*) ;;
      *) echo "第三方来源不在白名单内: $url" >&2; exit 1 ;;
    esac
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo "非法 SHA: $name" >&2; exit 1; }
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 -o "$IB/packages/$name" "$url"
    printf '%s  %s\n' "$digest" "$IB/packages/$name" | sha256sum --check --status || {
      echo "校验失败: $name" >&2; exit 1;
    }
  done < "$ROOT/config/gateway/vendor.lock"
fi

PACKAGES="$(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/config/gateway/base.packages" | tr '\n' ' ')"
DISABLED_SERVICES=""
if [ "$PROFILE" = "lab" ]; then
  PACKAGES="$PACKAGES $(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/config/gateway/lab.packages" | tr '\n' ' ')"
  # 实验插件默认不启动。未通过实机兼容测试前，不允许接管真实流量。
  DISABLED_SERVICES="openclash qosify banip bandix bandix-plus"
fi

cd "$IB"
echo "构建 profile=$PROFILE，target=x86/64，BIOS Legacy；不写入凭据/真实网络配置"
make image PROFILE="generic" PACKAGES="$PACKAGES" ROOTFS_PARTSIZE="2048" DISABLED_SERVICES="$DISABLED_SERVICES"

SOURCE="$IB/bin/targets/x86/64"
test -d "$SOURCE"
find "$SOURCE" -maxdepth 1 -type f -name '*.img.gz' -exec cp -v {} "$ROOT/out/$PROFILE/" \;
test "$(find "$ROOT/out/$PROFILE" -name '*.img.gz' | wc -l)" -gt 0 || {
  echo "没有找到镜像产物，终止" >&2; exit 1;
}
printf '%s\n' "$PACKAGES" > "$ROOT/out/$PROFILE/requested-packages.txt"
cat > "$ROOT/out/$PROFILE/build-info.txt" <<EOF
OpenWrt: $VERSION
Target: x86/64 generic
Boot: BIOS/Legacy (use generic-*-combined.img.gz, not -efi)
Profile: $PROFILE
Rootfs partition size: 2048 MiB
Sources: official downloads.openwrt.org; pinned GitHub release assets for lab
Autoflash: disabled
Secrets embedded: none
Validation: ImageBuilder succeeded; no physical router tests performed
EOF
(
  cd "$ROOT/out/$PROFILE"
  sha256sum ./*.img.gz > SHA256SUMS
)
echo "完成：$ROOT/out/$PROFILE"
