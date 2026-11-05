# OpenWrt 25.12.6 x86-64 | J4125 + Hyper-V

[查看构建进度及下载镜像](https://github.com/norviglc-rgb/openwrt-x86-build/actions/workflows/build-openwrt.yml)

## 构建产物

每次同时构建两套配置：

| 配置 | 软件 |
|---|---|
| base | 官方 OpenWrt、中文 LuCI、PPPoE、IPv6、DHCP/DNS、Firewall4、WireGuard、驱动 |
| lab | base + OpenClash/Mihomo、Argon、QoSmate、qosify、banIP、nlbwmon、collectd、Bandix Plus、Internet Detector、微信推送 |

每套配置提供的镜像：

| 目标 | 文件名特征 | 启动 |
|---|---|---|
| 物理机 ext4 | `generic-ext4-combined.img.gz` | Legacy BIOS |
| 物理机 ext4 | `generic-ext4-combined-efi.img.gz` | UEFI |
| 物理机 SquashFS | `generic-squashfs-combined.img.gz` | Legacy BIOS |
| 物理机 SquashFS | `generic-squashfs-combined-efi.img.gz` | UEFI |
| Hyper-V Generation 1 | `*hyperv-gen1-ext4.vhdx` | BIOS |
| Hyper-V Generation 2 | `*hyperv-gen2-ext4.vhdx` | UEFI，**关闭安全启动 Secure Boot** |

产物会附带 SHA256SUMS、ImageBuilder manifest 和编译参数记录。构建成功仅证明镜像生成成功，尚不等于实际网络功能验收通过。

## 驱动

物理软路由 Intel J4125、四口 I225-V 使用 `kmod-igc`；SATA/AHCI 与 ext4 驱动分别为 `kmod-ata-ahci` 和 `kmod-fs-ext4`。官方 OpenWrt 25.12.6 x86/64 内核本身包含 Hyper-V VMBus、网络、存储驱动（`CONFIG_HYPERV_NET=y`、`CONFIG_HYPERV_STORAGE=y`），不需要另加第三方 Hyper-V 驱动。Hyper-V 虚拟接口名称应以虚拟机中的实际检测为准，不得直接套用物理软路由的 eth0-eth3 对应关系。

## 分区和自动扩容

- 物理机镜像采用官方 x86/64 combined 分区布局：引导分区 + 根分区。
- `ROOTFS_MIB=2048`，即根分区**初始 2 GiB**；参数可在工作流中修改。
- `HYPERV_DISK_GIB=16`，Hyper-V 输出为**动态 16 GiB VHDX**。VHDX 虚拟容量已经扩至 16 GiB，但第 2 分区仍是 2 GiB，空余空间不会自动变成可用根目录空间。
- base 和 lab 都内置 `/usr/sbin/expand-hyperv-root-safe`。每次启动都校验 Hyper-V DMI、ext4、第二分区、磁盘恰好只有两个分区及尾部可用空间。
- **新建 Hyper-V 虚拟机第一次开机时自动扩展分区并重启一次，第二次启动自动扩展 ext4 文件系统。** 不需要人工逐步执行。
- 安全拒绝条件：不是 Hyper-V、不是 ext4、磁盘多于两个分区、不能准确识别根设备、没有足够尾部空余空间时，不修改磁盘。
- 若用户后来扩大 VHDX 的虚拟容量，服务可再次检测剩余空间并执行同样流程。对于已有业务数据的虚拟机，建议先创建 Hyper-V 检查点。
- **现有物理机有 sda4 数据分区，绝不允许直接用 combined 镜像覆盖现网系统盘，也不能运行通用的「扩到全盘」脚本。**

## SDK 与插件

OpenClash 0.48.002、Argon 3.1.2、Bandix Plus 以及微信推送从固定发布包下载，逐个 SHA-256 校验；随固件附带 Mihomo v1.19.33 内核，存放于 `/etc/openclash/core/clash_meta`。

QoSmate 使用 v1.9.0 对应的固定 Git 提交（后端实际 APK 包版本可能不同于仓库发行标签），Internet Detector 使用固定的 1.7.4 源码，均通过 OpenWrt 25.12.6 官方 SDK 编译后端及 LuCI 界面。软件包构建脚本为 `scripts/build-sdk-packages.sh`。

**实验组件只保证纳入测试计划，不允许全部同时启用：** QoSmate 与 qosify 会冲突；Bandix Plus 的限速功能必须与 QoS 单独测试；Internet Detector 不可默认在断网时自动重启。所有真实帐号、VPN 密钥、订阅令牌和通知令牌只在部署后本机配置。

Internet Detector 上游当前没有简体中文翻译包。该 UI 的汉化仍属于测试和补全范围，不能因为系统默认显示中文就假称全插件已汉化。

## 交付门槛

详见 [实机验收计划](docs/gateway-test-plan.md)。GitHub Actions 成功、VHDX 转换无错误、软件包完整只是构建门槛；最终还要通过 Hyper-V 两代启动、DHCP、DNS、IPv6、OpenClash、QoS、监控及数据分区保护测试。
