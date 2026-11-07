#!/usr/bin/env python3
"""离线校验 OpenWrt 实际输出（静态检查，不声称实机/Hyper-V 已成功引导）。"""
import gzip
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import uuid
import zlib

CHUNK = 4 * 1024 * 1024
SNIFF = 20 * 1024 * 1024
VERSION = "25.12.6"


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def u64(data, offset):
    return struct.unpack_from("<Q", data, offset)[0]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unzip_gzip_header_and_verify(path):
    """流式解压到末尾，强制检查 gzip CRC，保留前 20 MiB 作分区检查。"""
    size = 0
    head = bytearray()
    with gzip.open(path, "rb") as stream:
        while True:
            chunk = stream.read(CHUNK)
            if not chunk:
                break
            size += len(chunk)
            if len(head) < SNIFF:
                head.extend(chunk[:SNIFF - len(head)])
    require(size > 0, f"空的 gzip: {path.name}")
    return bytes(head), size


def check_ext4(data, offset, label):
    require(len(data) >= offset + 1082, f"{label}: 读不到 ext4 超级块")
    require(data[offset + 1080:offset + 1082] == b"\x53\xef",
            f"{label}: ext4 魔数错误")


def partitions_mbr(data):
    require(data[510:512] == b"\x55\xaa", "BIOS: MBR 结束标记 55aa 缺失")
    items = []
    for i in range(4):
        entry = data[446 + i * 16:462 + i * 16]
        if entry[4]:
            items.append((entry[0], entry[4], u32(entry, 8), u32(entry, 12)))
    require(len(items) == 2, f"BIOS: 应为 2 个 MBR 分区，实际 {len(items)}")
    boot, root = items
    require(boot[0] == 0x80 and boot[1] == 0x83, "BIOS: 第 1 分区缺少活动标志或类型错误")
    require(root[1] == 0x83, "BIOS: 第 2 分区类型错误")
    require(boot[2] >= 2 and boot[3] >= 32768, "BIOS: /boot 分区缺失或过小")
    require(root[2] >= boot[2] + boot[3], "BIOS: 分区重叠")
    require(any(data[:440]), "BIOS: 主引导记录没有引导代码")
    embedding = data[512:boot[2] * 512]
    require(sum(bool(b) for b in embedding) > 1024,
            "BIOS: MBR 后的 GRUB 嵌入区域似乎为空")
    check_ext4(data, boot[2] * 512, "BIOS /boot")
    alignment_kib = boot[2] // 2
    require(alignment_kib >= 1024,
            f"BIOS: 第 1 分区仅按 {alignment_kib} KiB 对齐，GRUB 嵌入区仍偏小")
    print(f"  BIOS: 第 1 分区按 {alignment_kib} KiB 对齐，MBR 后 GRUB 嵌入数据存在")
    return root, boot[2] + boot[3]


def partitions_gpt(data):
    require(data[510:512] == b"\\x55\\xaa", "UEFI: 保护 MBR 损坏")
    require(data[512:520] == b"EFI PART", "UEFI: GPT 主表签名缺失")
    hdrsize = u32(data, 512 + 12)
    require(92 <= hdrsize <= 512, "UEFI: GPT Header 长度异常")
    header = bytearray(data[512:512 + hdrsize])
    actual_crc = u32(header, 16)
    header[16:20] = b"\\0" * 4
    require((zlib.crc32(header) & 0xffffffff) == actual_crc,
            "UEFI: GPT Header CRC 错误")
    table_lba = u64(data, 512 + 72)
    num = u32(data, 512 + 80)
    ent_size = u32(data, 512 + 84)
    require(2 <= num <= 128 and ent_size == 128, "UEFI: GPT 分区项规格异常")
    table = data[table_lba * 512:table_lba * 512 + num * ent_size]
    require(len(table) == num * ent_size, "UEFI: GPT 表项截断")
    require((zlib.crc32(table) & 0xffffffff) == u32(data, 512 + 88),
            "UEFI: GPT 分区表 CRC 错误")
    parts = {}
    for i in range(num):
        entry = table[i * ent_size:(i + 1) * ent_size]
        if any(entry[:16]):
            first, last = u64(entry, 32), u64(entry, 40)
            require(last >= first, "UEFI: GPT 分区边界错误")
            parts[i + 1] = {
                "type": str(uuid.UUID(bytes_le=entry[:16])).lower(),
                "first": first,
                "sectors": last - first + 1,
            }
    require(set(parts) == {1, 2, 128},
            f"UEFI: 应为分区 1/2 + BIOS Boot #128，实际 {sorted(parts)}")
    boot, root, bios = parts[1], parts[2], parts[128]
    require(bios["type"] == "21686148-6449-6e6f-744e-656564454649",
            f"UEFI: #128 不是 BIOS Boot GUID: {bios['type']}")
    require(bios["first"] >= 34 and bios["first"] + bios["sectors"] <= boot["first"],
            "UEFI: BIOS Boot 分区位置异常或与第 1 分区重叠")
    require(boot["first"] >= 2048,
            f"UEFI: 第 1 分区起始 LBA={boot['first']}，未达到 1 MiB 对齐")
    require(root["first"] >= boot["first"] + boot["sectors"], "UEFI: 分区重叠")
    require(boot["sectors"] >= 32768, "UEFI: 引导分区小于 16 MiB")
    bios_start = bios["first"] * 512
    bios_end = (bios["first"] + bios["sectors"]) * 512
    bios_data = data[bios_start:bios_end]
    require(len(bios_data) == bios["sectors"] * 512 and
            sum(bool(b) for b in bios_data) > 1024,
            "UEFI: BIOS Boot 分区为空或 GRUB 嵌入数据缺失")
    esp_start = boot["first"] * 512
    esp_end = (boot["first"] + boot["sectors"]) * 512
    require(b"FAT16" in data[esp_start:esp_start + 100] or
            b"FAT32" in data[esp_start:esp_start + 100], "UEFI: 引导分区不是 FAT")
    require(b"BOOTX64 EFI" in data[esp_start:esp_end],
            "UEFI: 引导分区缺失 BOOTX64.EFI 目录项")
    print(f"  UEFI: BIOS Boot #128={bios['sectors'] * 512 // 1024} KiB；"
          f"FAT 引导分区起始 LBA={boot['first']}")
    return (0, 0, root["first"], root["sectors"]), boot["first"] + boot["sectors"]


def validate_image(path, kind, efi, root_mib):
    data, total = unzip_gzip_header_and_verify(path)
    if efi:
        root, _ = partitions_gpt(data)
    else:
        root, _ = partitions_mbr(data)
    start_sector, sectors = root[2], root[3]
    require(sectors == root_mib * 2048,
            f"{path.name}: 根分区大小 {sectors // 2048} MiB，不符合 {root_mib} MiB")
    require(total >= (start_sector + sectors) * 512,
            f"{path.name}: 镜像比最后一个分区短")
    off = start_sector * 512
    if kind == "ext4":
        check_ext4(data, off, path.name + " rootfs")
    else:
        require(data[off:off + 4] == b"hsqs",
                f"{path.name}: SquashFS 魔数错误")
    print(f"  OK {path.name}: {total} 字节；"
          f"{'GPT/UEFI' if efi else 'MBR/BIOS'}；{kind}；根分区 {root_mib} MiB")


def main():
    require(len(sys.argv) == 2, "用法：verify-artifacts.py out/base|out/lab")
    output = Path(sys.argv[1])
    profile = output.name
    require(profile in ("base", "lab") and output.is_dir(), "构建输出路径错误")
    info = (output / "build-info.txt").read_text(encoding="utf-8")
    root_match = re.search(r"Root filesystem partition:\s*(\d+)\s*MiB", info)
    disk_match = re.search(r"Virtual disk size:\s*(\d+)\s*GiB", info)
    require(root_match and disk_match, "build-info 缺少分区或磁盘容量")
    root_mib = int(root_match.group(1))
    disk_gib = int(disk_match.group(1))
    expected = set()
    physical = []
    for kind in ("ext4", "squashfs"):
        for suffix, efi in (("combined", False), ("combined-efi", True)):
            name = f"openwrt-{VERSION}-x86-64-generic-{kind}-{suffix}.img.gz"
            physical.append((output / name, kind, efi))
            expected.add(name)
        expected.add(f"openwrt-{VERSION}-x86-64-generic-{kind}-rootfs.img.gz")
    vhdxs = []
    for gen in ("gen1", "gen2"):
        name = f"openwrt-{VERSION}-{profile}-hyperv-{gen}-ext4.vhdx"
        expected.add(name)
        vhdxs.append(output / name)
    lines = (output / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
    checksums = {}
    for line in lines:
        digest, name = line.split()
        name = name.removeprefix("./")
        require(re.fullmatch("[a-f0-9]{64}", digest), "SHA256SUMS 格式错误")
        require(name not in checksums, "SHA256SUMS 存在重复文件")
        checksums[name] = digest
    require(set(checksums) == expected,
            f"SHA256SUMS 文件不匹配：缺少 {expected - set(checksums)}，多出 {set(checksums) - expected}")
    for name in sorted(expected):
        path = output / name
        require(path.is_file() and path.stat().st_size > 0, f"缺少产物: {name}")
        require(sha256(path) == checksums[name], f"SHA-256 不匹配：{name}")
    print(f"OK {profile}: 8 个镜像/VHDX 的 SHA-256 全部吻合")
    for path, kind, efi in physical:
        validate_image(path, kind, efi, root_mib)
    for kind in ("ext4", "squashfs"):
        name = f"openwrt-{VERSION}-x86-64-generic-{kind}-rootfs.img.gz"
        data, _ = unzip_gzip_header_and_verify(output / name)
        if kind == "ext4":
            check_ext4(data, 0, name)
        else:
            require(data[:4] == b"hsqs", f"{name}: 文件系统魔数错误")
        print(f"  OK {name}: gzip 流完整，文件系统魔数正确")
    for path in vhdxs:
        result = subprocess.run(["qemu-img", "info", "-f", "vhdx", "--output=json", str(path)],
                                check=True, capture_output=True, text=True)
        details = json.loads(result.stdout)
        require(details["format"] == "vhdx" and details["virtual-size"] == disk_gib * (1024 ** 3),
                f"{path.name}: VHDX 类型或虚拟容量错误")
        subprocess.run(["qemu-img", "check", "-f", "vhdx", str(path)], check=True,
                       capture_output=True, text=True)
        print(f"  OK {path.name}: VHDX 格式、容量、结构检查通过")
    manifests = list(output.glob("*.manifest"))
    require(len(manifests) == 1, "缺少或存在多个包清单")
    packages = {line.split(" - ", 1)[0] for line in manifests[0].read_text().splitlines()}
    must = {"kmod-igc", "kmod-ata-ahci", "kmod-fs-ext4", "parted",
            "resize2fs", "lsblk", "blkid", "luci-i18n-base-zh-cn"}
    if profile == "lab":
        must |= {"luci-app-openclash", "luci-theme-argon", "qosmate", "qosify",
                 "banip", "bandix-plus", "internet-detector", "luci-app-wechatpush",
                 "luci-i18n-internet-detector-zh-cn"}
    require(not (must - packages), f"manifest 缺少软件包: {sorted(must - packages)}")
    require((output / "requested-packages.txt").is_file(), "缺少 requested-packages.txt")
    print("OK 包清单检查通过；静态校验完成。BIOS/UEFI 实际引导和网络功能仍需虚拟机/实机测试。")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
