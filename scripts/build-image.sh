#!/usr/bin/env bash
# 官方 25.12.6 ImageBuilder + 25.12.6 SDK 包，唯一 lab ext4 UEFI 镜像
set -Eeuo pipefail
PROFILE="${1:-lab}"
case "$PROFILE" in lab) ;; *) echo "仅支持 lab ext4 UEFI: $PROFILE" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=25.12.6
URL="https://downloads.openwrt.org/releases/$VERSION/targets/x86/64"
ARCHIVE="openwrt-imagebuilder-$VERSION-x86-64.Linux-x86_64.tar.zst"
HASH=a792e29bd2233cda67a0823030bfb53c0b61fbb3836b2063e88adf89730d563b
ROOTFS_MIB="${ROOTFS_MIB:-2048}"
[[ "$ROOTFS_MIB" =~ ^[0-9]+$ ]] && (( ROOTFS_MIB>=512 && ROOTFS_MIB<=8192 )) || { echo 'ROOTFS_MIB 范围为 512-8192 MiB' >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$ROOT/out/$PROFILE"
cd "$WORK"
curl -fL --retry 3 -o "$ARCHIVE" "$URL/$ARCHIVE"
printf '%s  %s\n' "$HASH" "$ARCHIVE" | sha256sum -c -
tar --zstd -xf "$ARCHIVE"
IB="$WORK/${ARCHIVE%.tar.zst}"
test -d "$IB"

# OpenWrt x86 25.12.6 上游仍以 256 KiB 对齐生成 GRUB BIOS 嵌入区，
# grub-bios-setup 会警告 BIOS Boot Partition 小于 1 MiB。
# 仅将 x86 combined 镜像的对齐参数提高到 1024 KiB，不改变分区数量、文件系统或 rootfs 容量。
IMAGE_MAKEFILE="$IB/target/linux/x86/image/Makefile"
python3 - "$IMAGE_MAKEFILE" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
text = p.read_text()
pattern = r'(\$\(CONFIG_TARGET_ROOTFS_PARTSIZE\) \$\(IMAGE_ROOTFS\) \\\n\s*)256(\n)'
new, n = re.subn(pattern, r'\g<1>1024\g<2>', text, count=1)
if n != 1:
    raise SystemExit("无法唯一定位 x86 镜像 256 KiB 对齐参数")
p.write_text(new)
PY
mkdir -p "$IB/packages" "$IB/files"

if [ "$PROFILE" = lab ]; then
  while IFS='|' read -r name url digest; do
    [ -n "$name" ] || continue
    case "$name" in \#*) continue;; esac
    case "$name" in *[!a-zA-Z0-9._-]*) echo "非法文件名：$name" >&2; exit 1;; esac
    case "$url" in
      https://github.com/vernesong/OpenClash/releases/download/*|https://github.com/jerrykuku/luci-theme-argon/releases/download/*|https://github.com/timsaya/luci-app-bandix-plus/releases/download/*|https://github.com/timsaya/openwrt-bandix-plus/releases/download/*|https://github.com/tty228/luci-app-wechatpush/releases/download/*) ;;
      *) echo "非白名单来源：$url" >&2; exit 1;;
    esac
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo "SHA-256 格式错误：$name" >&2; exit 1; }
    curl -fL --retry 3 -o "$IB/packages/$name" "$url"
    printf '%s  %s\n' "$digest" "$IB/packages/$name" | sha256sum -c -
  done < "$ROOT/config/gateway/vendor.lock"

  # ImageBuilder 25.12.6 本地 APK 索引要求与内部包名和版本一致；
  # 此处调整的均为已经校验过 SHA-256 的本地文件名，不修改内容。
  for mapping in \
    'bandix-plus-0.1.3-r1_x86_64.apk|bandix-plus-0.1.3-r1.apk' \
    'luci-app-bandix-plus-0.1.3-r2_all.apk|luci-app-bandix-plus-0.1.3-r2.apk' \
    'luci-i18n-bandix-plus-zh-cn-26.294.39283.c4f002f_all.apk|luci-i18n-bandix-plus-zh-cn-26.294.39283~c4f002f.apk' \
    'luci-i18n-wechatpush-zh-cn-26.062.45206.f0af3d3.apk|luci-i18n-wechatpush-zh-cn-26.062.45206~f0af3d3.apk'
  do
    old="${mapping%%|*}"; new="${mapping#*|}"
    test -s "$IB/packages/$old" || { echo "缺少原始 APK：$old" >&2; exit 1; }
    test ! -e "$IB/packages/$new" || { echo "目标 APK 已存在：$new" >&2; exit 1; }
    mv "$IB/packages/$old" "$IB/packages/$new"
  done

  bash "$ROOT/scripts/build-sdk-packages.sh" "$IB/packages"

  # 将 Mihomo 稳定版直接放入 OpenClash 要求的 core/clash_meta，启动不依赖二次下载。
  CORE="$WORK/mihomo-linux-amd64-v1.19.33.gz"
  curl -fL --retry 3 -o "$CORE" \
    https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-amd64-v1.19.33.gz
  printf '%s  %s\n' 132f6f3edf9a65e62f04853aed3358472e0b2b7666daa8419edfa2ddf5bb6323 "$CORE" | sha256sum -c -
  mkdir -p "$IB/files/etc/openclash/core" "$IB/files/usr/sbin"
  gzip -dc "$CORE" > "$IB/files/etc/openclash/core/clash_meta"
  chmod 0755 "$IB/files/etc/openclash/core/clash_meta"
fi

PACKAGES="$(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/config/gateway/base.packages" | tr '\n' ' ')"
DISABLED=''
if [ "$PROFILE" = lab ]; then
  PACKAGES="$PACKAGES $(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/config/gateway/lab.packages" | tr '\n' ' ')"
  DISABLED='openclash qosmate qosify banip bandix-plus internet-detector wechatpush'
fi

cd "$IB"
echo "构建 $PROFILE: x86/64, UEFI/ext4, rootfs=$ROOTFS_MIB MiB"
# 只编译 ext4 根文件系统和 EFI 引导组合，不选择 BIOS 与 squashfs。
make image PROFILE=generic PACKAGES="$PACKAGES" ROOTFS_PARTSIZE="$ROOTFS_MIB" \
  ROOTFS_FILESYSTEM=ext4 CONFIG_GRUB_IMAGES=n CONFIG_GRUB_EFI_IMAGES=y \
  FILES="$IB/files" DISABLED_SERVICES="$DISABLED"
SOURCE="$IB/bin/targets/x86/64"
test -d "$SOURCE"

# 补全并重定位备份 GPT，仅保留 UEFI/ext4 完整磁盘镜像。
IMAGE_NAME="openwrt-$VERSION-x86-64-generic-ext4-combined-efi.img.gz"
IMAGE_GZ="$SOURCE/$IMAGE_NAME"
RAW="$WORK/$PROFILE-efi-ext4.raw"
test -s "$IMAGE_GZ"
gzip -dc "$IMAGE_GZ" > "$RAW"
sgdisk -e "$RAW" >/dev/null
sgdisk -v "$RAW"
gzip -n -9 < "$RAW" > "$ROOT/out/$PROFILE/$IMAGE_NAME"
rm -f "$RAW"

# 附带安装包清单，辅助静态校验及追溯。
MANIFEST="$(find "$SOURCE" -maxdepth 1 -type f -name '*.manifest' -print -quit)"
test -s "$MANIFEST"
cp "$MANIFEST" "$ROOT/out/$PROFILE/"
printf '%s\n' "$PACKAGES" > "$ROOT/out/$PROFILE/requested-packages.txt"
cat > "$ROOT/out/$PROFILE/build-info.txt" <<EOF
OpenWrt: $VERSION
Architecture: x86_64; profile: lab
Boot: UEFI only
Filesystem: ext4
Physical image: $IMAGE_NAME
Real hardware: Intel I225-V via kmod-igc; SATA via AHCI
Root filesystem partition: $ROOTFS_MIB MiB
Physical auto-grow: disabled (protect existing data partitions)
Auto-flash / secrets: none
Verification: build-only; real device/network functionality remains untested
EOF
(
  cd "$ROOT/out/$PROFILE"
  sha256sum ./*.img.gz > SHA256SUMS
)
echo "构建完成：$ROOT/out/$PROFILE"
