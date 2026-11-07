# lab UEFI/ext4 实机验收清单

## 编译产物
- [ ] 仅 lab 工作流成功，输出只有一个 ext4-combined-efi.img.gz 镜像。
- [ ] SHA256、主/备 GPT、UEFI、ext4、软件包 manifest 静态校验通过。
- [ ] 初始根分区默认 2048 MiB；物理机自动扩容未开启。

## J4125 / I225-V 实机
- [ ] 使用没有重要数据的测试盘，验证 UEFI 启动。
- [ ] 四口 Intel I225-V 均正确识别，并核对实际 WAN/LAN 对应关系。
- [ ] PPPoE、DHCPv6/RA、WireGuard、DNS、Firewall4、LAN DHCP 工作正常。
- [ ] OpenClash/Mihomo、规则分流和 DNS/IPv6 无旁路。
- [ ] QoSmate 与 qosify 逐一验证拥塞、延迟和 DSCP，不要同时启用。
- [ ] Bandix Plus 不启用限速；比较 nlbwmon/collectd 的资源消耗。
- [ ] Internet Detector 不启用自动重启；微信推送密钥只在本地配置。
- [ ] 配置和磁盘有可用备份；独立管理链路和回滚计划可用。
- [ ] 不覆盖已有 SSD 的 sda4 数据分区。
