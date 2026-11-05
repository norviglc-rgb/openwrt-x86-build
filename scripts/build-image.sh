#!/usr/bin/env bash
# 官方 25.12.6 ImageBuilder + 25.12.6 SDK 包 + Hyper-V Gen1/Gen2 VHDX
set -Eeuo pipefail
PROFILE="${1:-lab}"
case "$PROFILE" in base|lab) ;; *) echo "不支持 profile: $PROFILE" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=25.12.6
URL="https://downloads.openwrt.org/releases/$VERSION/targets/x86/64"
ARCHIVE="openwrt-imagebuilder-$VERSION-x86-64.Linux-x86_64.tar.zst"
HASH=a792e29bd2233cda67a0823030bfb53c0b61fbb3836b2063e88adf89730d563b
ROOTFS_MIB="${ROOTFS_MIB:-2048}"
HYPERV_DISK_GIB="${HYPERV_DISK_GIB:-16}"
[[ "$ROOTFS_MIB" =~ ^[0-9]+$ ]] && (( ROOTFS_MIB>=512 && ROOTFS_MIB<=8192 )) || { echo 'ROOTFS_MIB 范围为 512-8192 MiB' >&2; exit 2; }
[[ "$HYPERV_DISK_GIB" =~ ^[0-9]+$ ]] && (( HYPERV_DISK_GIB>=8 && HYPERV_DISK_GIB<=64 )) || { echo 'HYPERV_DISK_GIB 范围为 8-64 GiB' >&2; exit 2; }
(( HYPERV_DISK_GIB*1024 > ROOTFS_MIB+64 )) || { echo 'Hyper-V 磁盘必须大于根分区' >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$ROOT/out/$PROFILE"
cd "$WORK"
curl -fL --retry 3 -o "$ARCHIVE" "$URL/$ARCHIVE"
printf '%s  %s\n' "$HASH" "$ARCHIVE" | sha256sum -c -
tar --zstd -xf "$ARCHIVE"
IB="$WORK/${ARCHIVE%.tar.zst}"
test -d "$IB"
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
  cp "$ROOT/scripts/expand-hyperv-root-safe.sh" "$IB/files/usr/sbin/expand-hyperv-root-safe"
  chmod 0755 "$IB/files/usr/sbin/expand-hyperv-root-safe"
fi

PACKAGES="$(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/config/gateway/base.packages" | tr '\n' ' ')"
DISABLED=''
if [ "$PROFILE" = lab ]; then
  PACKAGES="$PACKAGES $(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/config/gateway/lab.packages" | tr '\n' ' ')"
  DISABLED='openclash qosmate qosify banip bandix-plus internet-detector wechatpush'
fi

cd "$IB"
echo "构建 $PROFILE: x86/64, rootfs=$ROOTFS_MIB MiB, Hyper-V=$HYPERV_DISK_GIB GiB"
make image PROFILE=generic PACKAGES="$PACKAGES" ROOTFS_PARTSIZE="$ROOTFS_MIB" \
  FILES="$IB/files" DISABLED_SERVICES="$DISABLED"
SOURCE="$IB/bin/targets/x86/64"
test -d "$SOURCE"
find "$SOURCE" -maxdepth 1 -type f -name '*.img.gz' -exec cp -v '{}' "$ROOT/out/$PROFILE/" \;
find "$SOURCE" -maxdepth 1 -type f -name '*.manifest' -exec cp -v '{}' "$ROOT/out/$PROFILE/" \;
test -s "$SOURCE/openwrt-$VERSION-x86-64-generic-ext4-combined.img.gz"
test -s "$SOURCE/openwrt-$VERSION-x86-64-generic-ext4-combined-efi.img.gz"

# 基于官方 ext4-combined BIOS/EFI 分别转换 Hyper-V Gen1/Gen2 动态 VHDX。
for gen in gen1 gen2; do
  if [ "$gen" = gen1 ]; then input='ext4-combined.img.gz'; else input='ext4-combined-efi.img.gz'; fi
  in="$SOURCE/openwrt-$VERSION-x86-64-generic-$input"
  raw="$WORK/openwrt-$gen.raw"
  gzip -dc "$in" > "$raw"
  out="$ROOT/out/$PROFILE/openwrt-$VERSION-$PROFILE-hyperv-$gen-ext4.vhdx"
  # QEMU VHDX 驱动不支持 resize。先稀疏扩展 RAW，再转换动态 VHDX。
  truncate -s "${HYPERV_DISK_GIB}G" "$raw"
  qemu-img convert -f raw -O vhdx -o subformat=dynamic "$raw" "$out"
  qemu-img check -f vhdx "$out"
  qemu-img info -f vhdx "$out" > "$out.info.txt"
  rm -f "$raw"
done

printf '%s\n' "$PACKAGES" > "$ROOT/out/$PROFILE/requested-packages.txt"
cat > "$ROOT/out/$PROFILE/build-info.txt" <<EOF
OpenWrt: $VERSION
Architecture: x86_64; profile: $PROFILE
Real hardware: Intel I225-V via kmod-igc; SATA via AHCI
Hyper-V driver: built-in CONFIG_HYPERV_NET/CONFIG_HYPERV_STORAGE
Physical images: BIOS/UEFI, ext4/squashfs
Hyper-V images: Gen1(BIOS)/Gen2(UEFI), ext4 dynamic VHDX
Gen2 requires Secure Boot disabled
Root filesystem partition: $ROOTFS_MIB MiB
Virtual disk size: $HYPERV_DISK_GIB GiB
Unallocated capacity: safe grow helper included in lab, NOT enabled automatically
Auto-flash / secrets: none
Verification: build-only; real device/VM/network functionality remains untested
EOF
(
  cd "$ROOT/out/$PROFILE"
  sha256sum ./*.img.gz ./*.vhdx > SHA256SUMS
)
echo "构建完成：$ROOT/out/$PROFILE"
