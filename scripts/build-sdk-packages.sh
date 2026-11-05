#!/usr/bin/env bash
# 仅使用官方 OpenWrt 25.12.6 SDK 和固定提交的上游源码生成 APK
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?需指定 APK 输出目录}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
VERSION=25.12.6
SDK_NAME="openwrt-sdk-${VERSION}-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
SDK_SHA256=1864152619092e781fa36a401960c8e9ae42d6a364c44ee5f0b197ca5f3c0fcc
URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/$SDK_NAME"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
curl -fL --retry 3 -o "$SDK_NAME" "$URL"
printf '%s  %s\n' "$SDK_SHA256" "$SDK_NAME" | sha256sum -c -
tar --zstd -xf "$SDK_NAME"
SDK="$WORK/${SDK_NAME%.tar.zst}"
test -f "$SDK/Makefile" || { echo "SDK 目录丢失" >&2; exit 1; }
mkdir -p "$WORK/source"

clone_pinned() {
  local name="$1" url="$2" expected="$3"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo "源码未固定 commit：$name" >&2; return 1; }
  git init -q "$WORK/source/$name"
  git -C "$WORK/source/$name" remote add origin "$url"
  git -C "$WORK/source/$name" -c protocol.version=2 fetch -q --depth 1 origin "$expected"
  git -C "$WORK/source/$name" checkout -q --detach FETCH_HEAD
  test "$(git -C "$WORK/source/$name" rev-parse HEAD)" = "$expected" || { echo "源码 SHA 不匹配 $name" >&2; return 1; }
  echo "$name 固定提交 $expected"
}
clone_pinned qosmate https://github.com/hudra0/qosmate.git ad5ef37a6b38b651849eccb33670a5398e06c876
clone_pinned luci-app-qosmate https://github.com/hudra0/luci-app-qosmate.git f37bc15498f7cbe3cd2cb912d1133551c9a5a738
clone_pinned internet-detector https://github.com/gSpotx2f/luci-app-internet-detector.git e265fcc8a9d9fd359f29fd0188ab2da3ce1438fa

cd "$SDK"
./scripts/feeds update luci packages
./scripts/feeds install -a -p luci
./scripts/feeds install -a -p packages

mkdir -p package/qosmate package/luci-app-qosmate package/internet-detector package/luci-app-internet-detector
cp -a "$WORK/source/qosmate/." package/qosmate/
cp -a "$WORK/source/luci-app-qosmate/." package/luci-app-qosmate/
cp -a "$WORK/source/internet-detector/internet-detector/." package/internet-detector/
cp -a "$WORK/source/internet-detector/luci-app-internet-detector/." package/luci-app-internet-detector/

cat >> .config <<'EOF'
CONFIG_PACKAGE_qosmate=m
CONFIG_PACKAGE_luci-app-qosmate=m
CONFIG_PACKAGE_internet-detector=m
CONFIG_PACKAGE_luci-app-internet-detector=m
EOF
make defconfig
for name in qosmate luci-app-qosmate internet-detector luci-app-internet-detector; do
  echo "SDK 编译 $name"
  make -j2 "package/$name/compile" V=s
done

for name in qosmate luci-app-qosmate internet-detector luci-app-internet-detector; do
  mapfile -t found < <(find "$SDK/bin" -type f \( -name "$name-*.apk" -o -name "${name}_*.apk" \))
  (("${#found[@]}" == 1)) || { printf '无法唯一确认 %s 产物: %s\n' "$name" "${found[*]}" >&2; exit 1; }
  path="${found[0]}"
  file="$(basename "$path")"
  file="${file%.apk}"
  file="${file%_x86_64}"
  file="${file%_all}"
  cp -v "$path" "$OUT/$file.apk"
done

# 如果项目生成了简体中文包，则一起复制；最终必须在 ImageBuilder 中校验。
find "$SDK/bin" -type f -name 'luci-i18n-qosmate-zh-cn*.apk' -exec cp -v '{}' "$OUT/" \;
echo "SDK 编译完毕："
find "$OUT" -maxdepth 1 -type f -name '*.apk' -printf '%f\n' | sort
