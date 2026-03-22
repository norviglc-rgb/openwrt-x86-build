#!/bin/bash
# ============================================================
# DIY Part 1 - 在更新 feeds 之前执行
# 主要用于添加额外的 feeds 源
# ============================================================
set -e

echo "=========================================="
echo "执行 diy-part1.sh (feeds 更新前)"
echo "=========================================="

# -------------------------------------------
# 1. 添加第三方 feeds 源
# -------------------------------------------

echo "==> 添加第三方 feeds 源..."

# helloworld - 代理核心依赖
if ! grep -q "fw876/helloworld" feeds.conf.default; then
    echo 'src-git helloworld https://github.com/fw876/helloworld' >> feeds.conf.default
    echo "  - 已添加 helloworld"
fi

# PassWall
if ! grep -q "openwrt-passwall" feeds.conf.default; then
    echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >> feeds.conf.default
    echo "  - 已添加 passwall"
fi

# Argon 主题
if ! grep -q "luci-theme-argon" feeds.conf.default; then
    echo 'src-git argon https://github.com/jerrykuku/luci-theme-argon' >> feeds.conf.default
    echo "  - 已添加 argon 主题"
fi

# LuCI 应用扩展
if ! grep -q "openwrt-luci-applications" feeds.conf.default; then
    echo 'src-git luci_app https://github.com/xiaorouji/openwrt-luci-applications' >> feeds.conf.default
    echo "  - 已添加 luci 扩展"
fi

# OpenClash (可选)
if ! grep -q "OpenClash" feeds.conf.default; then
    echo 'src-git openclash https://github.com/vernesong/OpenClash' >> feeds.conf.default
    echo "  - 已添加 openclash"
fi

echo "=========================================="
echo "diy-part1.sh 执行完成"
echo "=========================================="
