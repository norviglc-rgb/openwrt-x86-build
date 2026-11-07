# OpenWrt 25.12.6 x86-64 — lab / UEFI / ext4

本仓库基于官方 OpenWrt 25.12.6 ImageBuilder 和 SDK，**只构建 lab 完整配置并交付一个 UEFI/ext4 实体机镜像**：

`lab-openwrt-25.12.6-x86-64-generic-ext4-combined-efi.img.gz`

[编译工作流](https://github.com/norviglc-rgb/openwrt-x86-build/actions/workflows/build-openwrt.yml) · [Releases 下载](https://github.com/norviglc-rgb/openwrt-x86-build/releases) · [实机测试清单](docs/gateway-test-plan.md)

## 软件包

`config/gateway/base.packages` + `config/gateway/lab.packages`：中文 LuCI、Firewall4、dnsmasq-full、PPPoE、IPv6、WireGuard、OpenClash/Mihomo、Argon、banIP、QoSmate、qosify、nlbwmon、collectd、Bandix Plus、Internet Detector、微信推送等。

QoSmate 与 qosify 应分别测试、避免同时接管流量。代理订阅和密钥不内置。

## 输出与安全

- 只选 `ROOTFS_FILESYSTEM=ext4`、UEFI GRUB；不构建和发布 base、Legacy BIOS、SquashFS、Hyper-V Gen1/Gen2 VHDX。
- ImageBuilder 内部可能产生临时 rootfs 文件，但 GitHub Releases 只有一个完整固件镜像及校验/包清单文件。
- 可通过 workflow_dispatch 配置 `rootfs_mib`，默认 2048 MiB。
- 自动验证 SHA256、主/备 GPT、EFI 引导目录、ext4 根文件系统及包清单。
- 不进行物理磁盘自动扩容或自动写盘；**不要把镜像写到有重要数据分区的磁盘上**。
- 构建成功不能替代 J4125/I225-V 的 UEFI 引导和实际网络功能测试。

[与 2026 年 3 月旧版配置的功能差异](docs/feature-diff-2026-03.md)。
