# DNS 高可用架构配置指南

> OpenClash + AdGuardHome (Docker) + Dnsmasq 共存方案
> 更新: 2026-03 (基于深入研究优化)

## 设计原则

1. **Dnsmasq 必须保留** - DHCP 功能不可替代
2. **OpenClash 已内置 DNS 分流** - 不需要额外分流工具 (SmartDNS/MosDNS)
3. **AdGuardHome 专注广告过滤** - 与分流无关
4. **每层只做一件事** - 避免功能重复和冲突

## 架构设计

```
                    ┌──────────────────────────────────────────┐
                    │           高可用 DNS 架构                │
                    └──────────────────────────────────────────┘

客户端 DNS 请求 (端口 53)
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                       Dnsmasq (入口)                          │
│  端口: 53                                                     │
│  职责:                                                        │
│  - DHCP DNS 分发                                              │
│  - 本地域名解析 (*.lan, *.local)                              │
│  - DNS 转发到 AdGuardHome                                     │
│  - 故障兜底 (当 AdGuardHome/OpenClash 挂掉时)                 │
│  注意: 关闭缓存，由 OpenClash 统一处理                         │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                  AdGuardHome (过滤层)                         │
│  端口: 5353 (Docker 容器)                                     │
│  职责:                                                        │
│  - 广告过滤 (DNS sinkhole)                                    │
│  - 家长控制                                                   │
│  - 流量统计                                                   │
│  注意: 关闭缓存，上游指向 OpenClash                            │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                    OpenClash (分流层)                         │
│  端口: 7874 (DNS 监听)                                        │
│  模式: Fake-IP (推荐)                                         │
│  职责:                                                        │
│  - 国内外 DNS 分流 (nameserver + fallback)                    │
│  - Fake-IP 加速 (返回假 IP，无需等待真实解析)                  │
│  - DNS 缓存 (唯一缓存层)                                      │
│  - 与代理规则联动                                             │
└───────────────────────────────────────────────────────────────┘
        │
        ├─────────────────────────────┬─────────────────────────┤
        ▼                             ▼                         ▼
┌──────────────┐             ┌──────────────┐          ┌──────────────┐
│   国外 DNS    │             │   国内 DNS    │          │   代理节点    │
│  tls://8.8.4.4│            │ doh.pub      │          │   (转发DNS)   │
│  tls://1.1.1.1│            │ dns.alidns   │          │              │
└──────────────┘             └──────────────┘          └──────────────┘
```

## 为什么不需要 SmartDNS/MosDNS？

| 工具 | 核心功能 | 与 OpenClash 关系 |
|------|----------|-------------------|
| SmartDNS | DNS 测速优选 | OpenClash 已有 fallback 机制，同时使用会导致域名规则失效 |
| MosDNS | DNS 分流 | OpenClash 内置 nameserver-policy + fallback-filter |
| AdGuardHome | 广告过滤 | **需要保留**，这是唯一专注于广告过滤的层 |

## 故障回退机制

| 故障场景 | 回退策略 | 影响 |
|----------|----------|------|
| OpenClash 挂掉 | Dnsmasq 直连国内 DNS | 仅国内可访问 |
| AdGuardHome 挂掉 | Dnsmasq 绕过 → OpenClash | 无广告过滤 |
| Docker 挂掉 | 系统 Dnsmasq 完全接管 | 基础 DNS 可用 |
| 全部挂掉 | Dnsmasq 直连公共 DNS | 基本上网功能 |

## 配置步骤

### 1. Dnsmasq 配置

```bash
# /etc/dnsmasq.conf 或 /etc/config/dhcp

# 主 DNS 转发到 AdGuardHome
server=127.0.0.1#5353

# 本地域名直连
local=/lan/
domain=lan

# 关闭缓存 (由 OpenClash 统一处理)
cache-size=0

# 不读取 /etc/hosts
no-hosts

# DNSSEC (可选)
# dnssec
# trust-anchor=.,20326,5,1,2,B5A7D4E7B7E4F8A1C3D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B1C2
```

**UCI 配置方式**:
```bash
# /etc/config/dhcp
config dnsmasq
    option server '127.0.0.1#5353'
    option cachesize '0'
    option nohosts '1'
```

### 2. AdGuardHome 配置 (Docker)

```yaml
# docker-compose.yml
version: '3'
services:
  adguardhome:
    image: adguard/adguardhome
    container_name: adguardhome
    ports:
      - "5353:53/udp"
      - "5353:53/tcp"
      - "3000:3000"  # 管理界面
    volumes:
      - ./adguardhome/work:/opt/adguardhome/work
      - ./adguardhome/conf:/opt/adguardhome/conf
    restart: unless-stopped
    networks:
      - dns-network

networks:
  dns-network:
    driver: bridge
```

**AdGuardHome 上游 DNS 配置**:

```yaml
# /etc/AdGuardHome.yaml (容器内路径可能不同)

dns:
  port: 53
  bind_hosts:
    - 0.0.0.0

  # 上游 DNS：只指向 OpenClash
  upstream_dns:
    - 127.0.0.1:7874

  # 关闭缓存 (由 OpenClash 统一处理)
  cache_size: 0
  cache_ttl_min: 0
  cache_ttl_max: 0

  # 过滤设置
  filtering:
    protection_enabled: true
    blocking_mode: default
    blocked_response_ttl: 10

# 推荐的过滤规则
filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard DNS filter
  - enabled: true
    url: https://anti-ad.net/easylist.txt
    name: Anti-AD
  - enabled: true
    url: https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_2_English/filter.txt
    name: AdGuard Base
```

### 3. OpenClash 配置

**基本设置 (LuCI 界面)**:
- 运行模式: **Fake-IP (增强模式)**
- DNS 监听端口: 7874
- 本地 DNS 劫持: **关闭** (重要！)
- 自定义上游 DNS: **开启**

**DNS 配置 (覆写设置)**:

```yaml
dns:
  enable: true
  listen: 0.0.0.0:7874
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter-mode: blacklist

  # 解析 DoH/DoT 服务器域名 (必须是 IP)
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29

  # 代理节点域名解析 (防止"鸡蛋问题")
  proxy-server-nameserver:
    - https://doh.pub/dns-query

  # 国内域名
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query

  # 国外域名
  fallback:
    - tls://8.8.4.4
    - tls://1.1.1.1

  # 直连域名重新解析
  direct-nameserver:
    - system

  # 分流过滤
  fallback-filter:
    geoip: true
    geoip-code: CN
    geosite:
      - gfw
    ipcidr:
      - 240.0.0.0/4
      - 0.0.0.0/32

  # Fake-IP 过滤列表
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '*.localhost'
    - '*.home'
    - '+.stun.*.*'
    - '+.stun.*.*.*'
    - '+.stun.*.*.*.*'
    - 'stun.l.google.com'
    - 'lens.l.google.com'
    - '+.ntp.org.cn'
    - '+.bank'
    - '+.pay'
```

**Fake-IP 模式优势**:
- 响应速度快 (本地返回假 IP，无需等待 DNS 解析)
- 避免 DNS 污染
- 减少DNS泄露风险
- 基于域名匹配规则，不受 DNS 劫持干扰

### 4. 防火墙规则

```bash
# /etc/firewall.user

# DNS 劫持 (确保 DNS 请求走正确路径)
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53

# IPv6 DNS 劫持
ip6tables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53
ip6tables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53

# Docker 网络放行
iptables -I INPUT -i docker0 -j ACCEPT
iptables -I FORWARD -i docker0 -j ACCEPT
iptables -I FORWARD -o docker0 -j ACCEPT
```

## 健康检查脚本

```bash
#!/bin/sh
# /usr/bin/dns-health-check.sh

# 检查 OpenClash
check_openclash() {
    if ! pgrep -f "clash" > /dev/null; then
        logger "DNS-HA: OpenClash 进程异常，尝试重启..."
        /etc/init.d/openclash restart
    fi
}

# 检查 AdGuardHome (Docker)
check_adguard() {
    if ! docker ps | grep -q adguardhome; then
        logger "DNS-HA: AdGuardHome 容器异常，尝试重启..."
        docker restart adguardhome
    fi
}

# 检查 Dnsmasq
check_dnsmasq() {
    if ! pgrep -f "dnsmasq" > /dev/null; then
        logger "DNS-HA: Dnsmasq 进程异常，尝试重启..."
        /etc/init.d/dnsmasq restart
    fi
}

# 执行检查
check_openclash
check_adguard
check_dnsmasq

# DNS 解析测试
if ! nslookup baidu.com > /dev/null 2>&1; then
    logger "DNS-HA: DNS 解析异常！"
    # 可以添加告警通知
fi
```

**定时任务**:
```bash
# 添加到 crontab
*/5 * * * * /usr/bin/dns-health-check.sh
```

## 快捷路径

| 路径 | 服务 | 端口 |
|------|------|------|
| `/op/` | OpenWrt 后台 | 80 |
| `/adg/` | AdGuardHome | 3000 |
| `/oc/` | OpenClash | 80 |
| `/pk/` | 软件包 | 80 |

## 常见问题

### Q1: OpenClash 和 AdGuardHome 谁是上游？
**A**: AdGuardHome 是 OpenClash 的上游，但实际解析由 OpenClash 完成。
```
客户端 → Dnsmasq:53 → AdGuardHome:5353 (去广告) → OpenClash:7874 (分流) → 实际 DNS
```

### Q2: 为什么选择 Fake-IP 模式？
**A**:
- 响应速度快 (本地返回假 IP，无需等待 DNS 解析)
- 避免 DNS 污染
- 减少DNS泄露风险
- 基于域名匹配规则，不受 DNS 劫持干扰

### Q3: 为什么不需要 SmartDNS/MosDNS？
**A**:
- OpenClash 内置 `nameserver-policy` + `fallback-filter` 实现分流
- 同时使用 SmartDNS 会导致域名被缓存成 IP，OpenClash 域名规则失效
- 增加复杂度和延迟

### Q4: 缓存应该在哪里开启？
**A**: **只在 OpenClash 开启**。多层缓存会导致：
- 缓存不一致
- 重复查询
- 排查困难

### Q5: 如何验证配置正确？
```bash
# 测试 DNS 解析
nslookup baidu.com      # 应返回真实 IP
nslookup google.com     # Fake-IP 模式下应返回 198.18.x.x

# 检查各层连通性
nslookup baidu.com 127.0.0.1#53      # Dnsmasq
nslookup baidu.com 127.0.0.1#5353    # AdGuardHome
nslookup baidu.com 127.0.0.1#7874    # OpenClash

# 测试广告过滤
nslookup ad.baidu.com 127.0.0.1#5353  # 应返回 0.0.0.0
```

### Q6: AdGuardHome 用 Docker 还是原生安装？
**A**:
| 方式 | 优点 | 缺点 |
|------|------|------|
| Docker | 隔离性好，更新方便 | 需要额外 10-20MB 内存 |
| 原生 | 内存占用少 | 与系统耦合 |

**建议**: 内存 ≥512MB 用 Docker，<512MB 用原生

## 参考资料

- [OpenClash + AdGuardHome 配置讨论](https://github.com/vernesong/OpenClash/discussions/1420)
- [SmartDNS 分流配置](https://pymumu.github.io/smartdns/config/domain-forwarding/)
- [OpenWrt DNS 最佳实践](https://openwrt.org/docs/guide-user/services/dns/overview)
