#!/bin/sh
# 安全扩容：只对 Hyper-V 的新 ext4 虚拟磁盘有效。
# 使用：扩容前先制作 Hyper-V 检查点；执行 --apply；重启；再次执行 --apply。
set -eu
[ "${1:-}" = '--apply' ] || { echo '用法: expand-hyperv-root-safe --apply'; exit 2; }
vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
[ "$vendor" = 'Microsoft Corporation' ] || { echo "拒绝：非 Hyper-V 环境 DMI=$vendor" >&2; exit 1; }
majmin="$(awk '$5=="/" {print $3; exit}' /proc/self/mountinfo)"
[ -n "$majmin" ] || { echo '无法识别根文件系统设备' >&2; exit 1; }
root_sys="$(readlink -f "/sys/dev/block/$majmin")"
root="/dev/${root_sys##*/}"
[ -b "$root" ] || { echo "根设备不是块设备: $root" >&2; exit 1; }
partnum="$(lsblk -nrpo PARTN "$root" 2>/dev/null | head -n 1)"
[ "$partnum" = 2 ] || { echo "拒绝：根文件系统不在第 2 分区: $root" >&2; exit 1; }
parent="$(lsblk -nrpo PKNAME "$root" 2>/dev/null | head -n 1)"
case "$parent" in /dev/*) disk="$parent";; *) disk="/dev/$parent";; esac
[ -b "$disk" ] || { echo "无法识别父磁盘: $disk" >&2; exit 1; }
fstype="$(blkid -s TYPE -o value "$root" 2>/dev/null || true)"
[ "$fstype" = ext4 ] || { echo "拒绝：只支持 ext4，当前 $fstype" >&2; exit 1; }
parts="$(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part" {print $1}')"
count="$(printf '%s\n' "$parts" | grep -c . || true)"
[ "$count" = 2 ] || { echo "拒绝：检测到 $count 个分区（需要正好 2 个）" >&2; exit 1; }
printf '%s\n' "$parts" | grep -Fxq "$root" || { echo "根分区不在目标磁盘" >&2; exit 1; }
marker=/etc/.hyperv-root-grow-stage1
if [ -f "$marker" ]; then
  echo "第二阶段：调整 ext4 $root 的文件系统容量"
  resize2fs "$root"
  rm -f "$marker"
  df -h /
  echo '完成。'
  exit 0
fi
echo "只调整 $disk 上的 $root (第 2 分区尾部)，不会移动起始扇区"
parted -s "$disk" print
parted -f -s "$disk" resizepart 2 100%
touch "$marker"
sync
echo '第一阶段完成：请重启，然后再次运行此命令完成文件系统扩容。'
