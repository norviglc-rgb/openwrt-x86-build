# 物理机和 Hyper-V 验收清单

## 构建
- [ ] base/lab 两组工作流全部 success；生成 BIOS、UEFI 的 ext4/SquashFS combined 及 Gen1/Gen2 动态 VHDX。
- [ ] 官方 OpenWrt ImageBuilder/SDK SHA-256 校验通过。
- [ ] lab 的 APK 清单具有 QoSmate 后端+LuCI、qosify、OpenClash、Mihomo、Argon、banIP、Bandix Plus 前后端、nlbwmon、collectd、Internet Detector 前后端、微信推送+中文包。
- [ ] qemu-img check/info 通过，Hyper-V VHDX 容量 16 GiB，rootfs 初始 2048 MiB。

## Hyper-V
- [ ] Gen1 使用 BIOS VHDX 引导成功。
- [ ] Gen2 使用 UEFI VHDX 并关闭 Secure Boot 引导成功。
- [ ] Hyper-V 网络/存储驱动可用，LuCI、SSH、DHCP、DNS、IPv4/IPv6 可用；不要直接套用物理 eth0-eth3。
- [ ] 在新测试盘上执行两阶段安全扩容；附加第三个分区后必须拒绝扩容，原盘数据保持不变。

## J4125 实机
- [ ] I225-V 四口均识别；PPPoE 拨号、DHCPv6/RA、WireGuard、DNS/防火墙正常。
- [ ] OpenClash 内核、规则细分、节点订阅、IPv6 与 DNS 分流无绕行。
- [ ] QoSmate 与 qosify 分别测吞吐/拥塞延迟/DSCP；同一时间只能启用一个。
- [ ] Bandix Plus 不开限速，比较 nlbwmon 与 collectd 的统计、CPU。
- [ ] Internet Detector 不开启自动重启；微信推送只在本机填写密钥。
- [ ] 网络故障可通过本地/独立管理链路恢复。
- [ ] 保留原 SSD sda4 数据分区完整性并完成回滚演练后，才考虑生产部署。
