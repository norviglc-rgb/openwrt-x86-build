# OpenWrt x86-64 自动化编译方案

> 基于 GitHub 优秀项目的最佳实践设计
> 目标平台: x86/64 | 基础版本: OpenWrt 23.05 / Lean's LEDE

---

## 📋 特性

- ✅ 支持 **OpenWrt / Lean's LEDE / ImmortalWrt** 三种源码
- ✅ **EFI 启动** 支持，适配现代硬件
- ✅ **Nginx** 替代 uhttpd，支持 HTTPS 和反向代理
- ✅ **IPv6** 完整支持
- ✅ **OpenClash + PassWall** 双代理共存
- ✅ **sqm-autorate** 智能 QoS
- ✅ **Docker** 容器支持
- ✅ **Argon** 主题
- ✅ 完善的监控和安全插件
- ✅ GitHub Actions 自动编译

---

## 🚀 快速开始

### 1. Fork 本仓库

点击页面右上角 `Fork` 按钮。

### 2. 启用 GitHub Actions

进入 `Settings` → `Actions` → `General`，选择 `Read and write permissions`。

### 3. 触发编译

**方式一：手动触发**
1. 进入 `Actions` 页面
2. 选择 `Build OpenWrt x86-64`
3. 点击 `Run workflow`
4. 选择参数后运行

**方式二：定时编译**
- 每周一凌晨 2 点自动编译

### 4. 下载固件

编译完成后在 `Actions` 页面或 `Releases` 页面下载。

---

## 📦 包含插件

### 代理 (共存)
| 插件 | 说明 |
|------|------|
| OpenClash | Clash 内核，规则丰富 |
| PassWall | 多协议支持 |

### QoS
| 插件 | 说明 |
|------|------|
| sqm-autorate | 智能 CAKE 队列，自动带宽检测 |

### 监控
| 插件 | 说明 |
|------|------|
| luci-app-netdata | 全面系统监控 |
| btop | 终端资源监控 |
| luci-app-nlbwmon | 流量统计 |
| luci-app-statistics | 图表统计 |

### 安全
| 插件 | 说明 |
|------|------|
| luci-app-banip | IP 黑名单 |
| luci-app-oaf | 应用过滤 (内核级) |

### 网络
| 插件 | 说明 |
|------|------|
| luci-app-mwan3 | 多 WAN 负载均衡 |
| luci-app-upnp | UPnP 端口映射 |
| luci-app-ddns | 动态 DNS |

### 系统
| 插件 | 说明 |
|------|------|
| luci-app-docker | Docker 管理 |
| luci-app-acme | 自动 HTTPS 证书 |
| luci-app-diskman | 磁盘管理 |
| luci-app-wechatpush | 微信推送 |
| luci-app-vlmcsd | KMS 激活 |
| luci-app-timewol | 网络唤醒 |

### 主题
| 插件 | 说明 |
|------|------|
| luci-theme-argon | 现代化主题 |
| luci-app-argon-config | 主题配置 |

---

## ⚙️ 配置说明

### 源码选择

| 源码 | 说明 | 推荐场景 |
|------|------|----------|
| `lede` | Lean's LEDE，插件丰富 | 日常使用 |
| `immortalwrt` | ImmortalWrt，中国优化 | 国内网络 |
| `openwrt` | 官方 OpenWrt | 稳定优先 |

### 文件系统

| 类型 | 特点 | 适用场景 |
|------|------|----------|
| `squashfs` | 只读压缩，支持还原 | 生产环境 |
| `ext4` | 可读写，灵活扩展 | 开发测试 |

---

## 📁 项目结构

```
openwrt-x86-build/
├── .github/workflows/
│   └── build-openwrt.yml    # GitHub Actions 工作流
├── config/
│   ├── x86-64.config        # 主配置文件
│   └── packages/            # 插件包列表
│       ├── proxy.list       # 代理插件
│       └── docker.list      # Docker 支持
├── scripts/
│   ├── diy-part1.sh         # 自定义脚本 (feeds 前)
│   └── diy-part2.sh         # 自定义脚本 (feeds 后)
├── files/                   # 自定义文件 (打包到固件)
├── feeds.conf               # 软件源配置
├── settings.ini             # 编译设置
└── README.md
```

---

## 🔧 自定义配置

### 修改默认 IP

编辑 `scripts/diy-part2.sh`:
```bash
sed -i 's/192\.168\.1\.1/你的IP/g' package/base-files/files/bin/config_generate
```

### 添加/移除插件

编辑 `config/x86-64.config` 或 `config/packages/*.list`。

### 修改快捷路径

编辑 `scripts/diy-part2.sh` 中的 `shortcuts.conf` 部分。

---

## 📥 安装方法

### 写入磁盘

```bash
# 解压
gunzip openwrt-*.img.gz

# 写入磁盘 (替换 /dev/sdX)
dd if=openwrt-*.img of=/dev/sdX bs=4M status=progress && sync
```

### 虚拟机安装

- **VMware**: 直接使用 img 文件创建虚拟机
- **Proxmox**: 导入 img 到 VM
- **VirtualBox**: 转换为 VDI 格式

---

## 🔑 默认配置

| 项目 | 值 |
|------|------|
| IP 地址 | 10.0.0.1 |
| 子网掩码 | 255.255.254.0 (/23) |
| 用户名 | root |
| 密码 | password |
| 主题 | Argon |

---

## 📚 参考项目

| 项目 | 说明 |
|------|------|
| [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) | Lean's LEDE 源码 |
| [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) | ImmortalWrt 源码 |
| [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) | GitHub Actions 模板 |
| [ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt) | Actions 最佳实践 |
| [kiddin9/Kwrt](https://github.com/kiddin9/Kwrt) | Kwrt 在线编译 |

---

## 📄 许可证

MIT License

---

## 🙏 致谢

感谢所有开源项目的作者和贡献者！
