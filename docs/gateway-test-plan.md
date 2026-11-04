# J4125 网关实机验收清单

> 勘察来源：2026-11-05 四份报告。当前是 Legacy BIOS / ext4 / 四口 I225-V / PPPoE；sda4 数据区不可直接覆盖。

## 0. 不得提前执行

- 禁止自动刷写生产入口；不得把含密钥的 sysupgrade 备份提交到 GitHub。
- 下载镜像后，校验 SHA256SUMS。测试时先用独立磁盘或经过验证的恢复介质。
- 实验镜像包含多个可能修改 nftables / tc / eBPF 的组件，未经确认不得全体启用。

## 1. base 实机基线

- BIOS 镜像实际可启动；igc 正确识别 eth0、eth1、eth2、eth3。
- PPPoE、IPv4、WAN6、DHCPv6 前缀委派、RA、ICMPv6、IPv6 防火墙正常。
- DNS / DHCP、中文 LuCI、SSH 公钥、WireGuard 具备功能；管理接口不暴露 WAN。
- 验证 eth2 PCIe 实际吞吐上限，不以 2.5GbE 协商速率代替实际测试。
- 断开 fnOS/Agent 后，基础网络能持续提供服务。

## 2. lab 功能

- 先启用 OpenClash，确认配置 UCI 路径与真实 -f 文件一致，节点订阅、Fake-IP、规则、DNS、IPv6 不绕行。
- banIP 更新允许列表、防火墙默认拒绝、隔离网络不能访问 9090 / LuCI / SSH。
- QoS：一次只测试 QoSmate **或** qosify，测满速吞吐、上下行排队延迟、DSCP 与 CPU 消耗。
- Bandix Plus、nlbwmon、collectd：对比总流量、代理流量、IPv6、内网流量与 CPU 消耗；Bandix 限速关闭。
- 故意注入错误配置，验证离线备份与管理口能够恢复。

## 3. 生产准入

- 所有关键业务已验证；错误配置有明确回退路径。
- GitHub Artifacts 只标记为实验固件，不自动创建 Release。
- 尚未覆盖的 QoSmate SDK 构建、通知与新监控工具必须先通过独立依赖检查。
