# 与 2026-03-22 旧版编译声明的对比

基线：LEDE/master 的 `config/x86-64.config`、`config/packages/*.list`、
`scripts/diy-part*.sh`、旧版 build workflow。
当前：官方 OpenWrt 25.12.6 ImageBuilder，`config/gateway/base.packages` + `lab.packages`。
**本对比仅表示声明配置的变化，不能证明旧固件实际编入所有列出的软件。**

## 移除或缩减
- Docker/dockerd/LuCI Docker、Btrfs、PassWall、Nginx/LuCI 快捷入口；
- Netdata、btop、SQM/autorate、OAF、AccessControl；
- DDNS、ACME、ttyd、OpenSSH Server、logrotate、watchcat；
- DiskMan、自动挂载、USB/NTFS/exFAT/F2FS/NVMe 等扩展；
- iperf3、mtr、nmap、UPnP、Wake-on-LAN 等；
- Intel e1000e/igb/ixgbe/i40e、Realtek r8169、VirtIO 等较广的驱动范围；
- 默认 IP/主机名/时区覆写，以及旧 iptables 防火墙脚本（没有迁移）。

## 保留或变化
- OpenClash + Mihomo、Argon、dnsmasq-full、Firewall4、banIP；
- WireGuard、IPv6、PPPoE、Intel I225-V (igc)、AHCI、ext4；
- QoSmate/qosify 代替旧 SQM/autorate 测试路线，避免同时启用；
- nlbwmon、collectd、Bandix Plus 替代部分旧监控；
- Internet Detector、微信推送及中文翻译为新配置增强。

## 建议恢复（本次只列建议，不自动更改软件包）
1. 优先：`iperf3`、`mtr`、`nmap`、`logrotate`，用于网络验收和诊断。
2. 按需：`luci-app-ddns`、`acme`（有域名或远程 HTTPS 时），以及特定硬盘管理工具；
   分区扩容应仅手动实施并做好备份。
3. 可选：`luci-app-ttyd`（限制可信 LAN/VPN 访问）、Wake-on-LAN；按实际硬件加驱动。
4. 不推荐直接恢复：PassWall（与 OpenClash 重叠）、OAF（需确认 nftables 兼容）、
   SQM/autorate（与现有流控候选冲突）、路由器内 Docker/AdGuardHome（优先在独立主机运行）、
   硬编码密码和自动开放防火墙规则。

旧版 DNS-HA 文档提到 AdGuardHome，但文档不等于它曾经随固件交付。
