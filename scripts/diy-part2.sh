#!/bin/bash
# ============================================================
# DIY Part 2 - 在更新 feeds 之后执行
# 主要用于修改默认配置
# ============================================================
set -e

echo "=========================================="
echo "执行 diy-part2.sh (feeds 更新后)"
echo "=========================================="

# -------------------------------------------
# 1. 修改默认 IP 地址
# -------------------------------------------
echo "==> 设置默认 IP 地址: 10.0.0.1"
sed -i 's/192\.168\.1\.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# -------------------------------------------
# 2. 修改默认主题为 Argon
# -------------------------------------------
echo "==> 设置默认主题: argon"
if [ -f feeds/luci/collections/luci/Makefile ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
fi

# -------------------------------------------
# 3. 修改主机名
# -------------------------------------------
echo "==> 设置主机名: OpenWrt-x86"
sed -i 's/OpenWrt/OpenWrt-x86/g' package/base-files/files/bin/config_generate

# -------------------------------------------
# 4. 设置时区
# -------------------------------------------
echo "==> 设置时区: CST-8"
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate 2>/dev/null || true

# -------------------------------------------
# 5. 修改版本说明
# -------------------------------------------
echo "==> 更新版本信息..."
if [ -f package/base-files/files/etc/openwrt_release ]; then
    BUILD_DATE=$(date +%Y.%m.%d)
    sed -i "s/DISTRIB_DESCRIPTION.*/DISTRIB_DESCRIPTION='OpenWrt-x86 ${BUILD_DATE}'/g" package/base-files/files/etc/openwrt_release 2>/dev/null || true
fi

# -------------------------------------------
# 6. 添加自定义快捷路径 (Nginx)
# -------------------------------------------
echo "==> 配置 Nginx 快捷路径..."
mkdir -p files/etc/nginx/conf.d 2>/dev/null || true

cat > files/etc/nginx/conf.d/shortcuts.conf << 'EOF'
# OpenWrt 快捷访问路径配置
# 访问方式: http://router_ip/路径/

# 后台管理
location /op/ {
    alias /www/;
}

# 软件包管理
location /pk/ {
    rewrite ^/pk/(.*)$ /cgi-bin/luci/admin/system/opkg/$1 last;
}

# Bypass 插件
location /by/ {
    rewrite ^/by/(.*)$ /cgi-bin/luci/admin/services/bypass/$1 last;
}

# AdGuardHome
location /adg/ {
    proxy_pass http://127.0.0.1:3000/;
}

# 青龙面板
location /ql/ {
    proxy_pass http://127.0.0.1:5700/;
}

# OpenClash
location /oc/ {
    rewrite ^/oc/(.*)$ /cgi-bin/luci/admin/services/openclash/$1 last;
}

# PassWall
location /pw/ {
    rewrite ^/pw/(.*)$ /cgi-bin/luci/admin/services/passwall/$1 last;
}

# Aria2
location /ag/ {
    alias /www/ariang/;
}

# 固件更新
location /ug/ {
    rewrite ^/ug/(.*)$ /cgi-bin/luci/admin/services/gpsysupgrade/$1 last;
}
EOF

# -------------------------------------------
# 7. 配置默认防火墙规则
# -------------------------------------------
echo "==> 配置防火墙规则..."
mkdir -p files/etc/config 2>/dev/null || true

# 添加 IPv6 放行规则
cat > files/etc/firewall.user << 'EOF'
# 自定义防火墙规则
# IPv6 ICMP 放行
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
ip6tables -A OUTPUT -p ipv6-icmp -j ACCEPT

# Docker 网络放行
iptables -I INPUT -i docker0 -j ACCEPT
iptables -I FORWARD -i docker0 -j ACCEPT
iptables -I FORWARD -o docker0 -j ACCEPT
iptables -t nat -I POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
EOF

# -------------------------------------------
# 8. 配置启动脚本
# -------------------------------------------
echo "==> 配置启动脚本..."
cat > files/etc/rc.local << 'EOF'
# 开机自启动脚本
# 在这里添加需要在启动时执行的命令

# 等待网络就绪
sleep 5

# 输出启动完成日志
echo "OpenWrt-x86 启动完成: $(date)" >> /tmp/boot.log

exit 0
EOF

echo "=========================================="
echo "diy-part2.sh 执行完成"
echo "=========================================="
