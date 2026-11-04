# OpenWrt x86/64 网关构建（2026-11 重新整理）

[![构建 OpenWrt 25.12.6](https://github.com/norviglc-rgb/openwrt-x86-build/actions/workflows/build-openwrt.yml/badge.svg)](https://github.com/norviglc-rgb/openwrt-x86-build/actions/workflows/build-openwrt.yml)

**目标设备**：Intel J4125 / 四口 I225-V，Legacy BIOS，PPPoE，IPv6，OpenClash，CAKE，中文 LuCI。  
**固件**：官方 OpenWrt 25.12.6 x86/64；使用 ImageBuilder + apk v3，不使用 Kwrt、LEDE 或未固定的第三方 feed。

## 快速操作

进入 [GitHub Actions](https://github.com/norviglc-rgb/openwrt-x86-build/actions/workflows/build-openwrt.yml)，点击“运行工作流”。流水线分别生成：
- **base**：官方基础包，验证系统可构建，包含中文 LuCI、驱动、PPPoE、IPv6、DHCP/DNS、Firewall4、WireGuard、CAKE 支持。
- **lab**：在 base 基础上添加 OpenClash 0.48.002、Argon 3.1.2、banIP、qosify、nlbwmon、collectd、Bandix Plus 前端和后端等实验包。版本和 SHA-256 固定于 `config/gateway/vendor.lock`。

构建产物位于 Actions → 对应任务 → Artifacts，保存 14 天。**本项目不会自动发布正式 Release，也不会刷写路由器。**

## 明确的安全边界

1. 这是 **ImageBuilder 镜像构建验证**，不是实机启动、透明代理、IPv6 或 QoS 兼容性测试。
2. 不注入 PPPoE、WireGuard 私钥、订阅 URL、SSH 密钥或管理口令。
3. 实验插件默认禁用。QoSmate、qosify 不得同时管理同一出口的队列。
4. **QoSmate 1.9.0 尚未加入镜像**：上游发行版没有可直接用于此版本的 APK，必须用 25.12.6 SDK 构建并通过依赖测试。Internet Detector / WeChatPush 也仍在候选清单，不宣称已经安装。
5. 历史 LEDE、PassWall、Docker、默认密码和 Nginx 自定义配置已经从当前代码树删除，可在 Git 历史中审计；新工作流只读取 `config/gateway/*` 与 `scripts/build-image.sh`。
6. 当前盘存在数据分区 sda4。**任何 combined 镜像整盘写入都会破坏现有分区表。请先离线备份并演练恢复，禁止直接执行 dd。**
7. 本流水线仅设置 Legacy BIOS 目标。不要向当前设备刷写带 `-efi` 后缀的镜像。
8. 第三方发布 APK 通过 SHA-256 校验来源完整性，但并不等于已做源码审计。

## 下一步验收

参见 [实机测试计划](docs/gateway-test-plan.md)。请先通过 base 镜像的基本引导、四网口、PPPoE、IPv6 测试，再检验 lab。最终通过后才裁剪出 release 固件。

## 与旧版相比

新的工作流不会每周自动编译、不会自动清理旧 Releases、不会对工作流默认给予 `contents: write`、不会执行未审核的 `diy-part*.sh`。旧构建日志保留在 GitHub 历史，便于定位问题。
