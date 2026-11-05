#!/bin/sh
# Hyper-V 安全根分区扩容，支持自动两阶段执行。
# --auto 在 Microsoft Hyper-V 首次启动时使用；--apply 为人工执行。
# 检测到第三个分区、非 ext4、非 Hyper-V 或分区不连续时不修改磁盘。
set -eu
mode="${1:-}"
case "$mode" in
  --auto|--apply) ;;
  *) echo '用法：expand-hyperv-root-safe --auto | --apply' >&2; exit 2 ;;
esac
fail() {
  echo "自动扩容拒绝：$*" >&2
  if [ "$mode" = '--auto' ]; then exit 0; else exit 1; fi
}
vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
[ "$vendor" = 'Microsoft Corporation' ] || fail "DMI 厂商为 $vendor（不属于 Hyper-V）"

majmin="$(awk '$5=="/" {print $3; exit}' /proc/self/mountinfo)"
[ -n "$majmin" ] || fail '不能确定根文件系统挂载设备'
root_sys="$(readlink -f "/sys/dev/block/$majmin")"
root="/dev/${root_sys##*/}"
[ -b "$root" ] || fail "根设备不可用: $root"
partnum="$(lsblk -nrpo PARTN "$root" 2>/dev/null | head -n 1 || true)"
[ "$partnum" = '2' ] || fail "根分区不是第二分区: $root"
parent="$(lsblk -nrpo PKNAME "$root" 2>/dev/null | head -n 1 || true)"
case "$parent" in /dev/*) disk="$parent";; '') fail '不能确定父磁盘';; *) disk="/dev/$parent";; esac
[ -b "$disk" ] || fail "父磁盘不可用: $disk"
fstype="$(blkid -s TYPE -o value "$root" 2>/dev/null || true)"
[ "$fstype" = 'ext4' ] || fail "不是 ext4: $fstype"
parts="$(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part" {print $1}')"
count="$(printf '%s\n' "$parts" | grep -c . || true)"
[ "$count" -eq 2 ] || fail "检测到 $count 个分区，需要恰好两个"
printf '%s\n' "$parts" | grep -Fxq "$root" || fail "根分区不在 $disk 中"
# 只允许根分区的尾部向后扩张，禁止移动分区起始扇区。
base="${disk##*/}"
root_name="${root##*/}"
disk_sectors="$(cat "/sys/class/block/$base/size" 2>/dev/null || true)"
part_start="$(cat "/sys/class/block/$root_name/start" 2>/dev/null || true)"
part_size="$(cat "/sys/class/block/$root_name/size" 2>/dev/null || true)"
case "$disk_sectors:$part_start:$part_size" in
  *[!0-9:]*|::*|:) fail '无法读取分区扇区数';;
esac
[ -n "$disk_sectors" ] && [ -n "$part_start" ] && [ -n "$part_size" ] || fail '扇区数据缺失'
[ "$disk_sectors" -ge "$((part_start+part_size))" ] || fail '分区超过磁盘边界'
remaining="$((disk_sectors-part_start-part_size))"
marker=/etc/.hyperv-root-grow-stage1
if [ -f "$marker" ]; then
  echo "第二阶段：重启后在线扩容 ext4：$root"
  resize2fs "$root"
  rm -f "$marker"
  sync
  df -h /
  exit 0
fi
# 预留 32 MiB，防止 GPT 尾部保留扇区、分区表对齐导致重复尝试。
if [ "$remaining" -le 65536 ]; then
  echo "根分区已覆盖可用空间，剩余扇区：$remaining，无需扩容"
  exit 0
fi
echo "第一阶段：$disk 分区2剩余 $remaining 扇区，扩张到磁盘尾部"
parted -f -s "$disk" resizepart 2 100%
touch "$marker"
sync
if [ "$mode" = '--auto' ]; then
  echo '分区已扩大，自动重启一次，下一次启动扩容 ext4 文件系统'
  /sbin/reboot
fi
echo '首次调整完成。请重启后再次执行 --apply 来完成 ext4 扩容。'
