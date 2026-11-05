#!/usr/bin/env bash
# 仅使用官方 OpenWrt 25.12.6 SDK 和固定提交的上游源码生成 APK
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?需指定 APK 输出目录}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
VERSION=25.12.6
SDK_NAME="openwrt-sdk-${VERSION}-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
SDK_SHA256=1864152619092e781fa36a401960c8e9ae42d6a364c44ee5f0b197ca5f3c0fcc
URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/$SDK_NAME"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
curl -fL --retry 3 -o "$SDK_NAME" "$URL"
printf '%s  %s\n' "$SDK_SHA256" "$SDK_NAME" | sha256sum -c -
tar --zstd -xf "$SDK_NAME"
SDK="$WORK/${SDK_NAME%.tar.zst}"
test -f "$SDK/Makefile" || { echo "SDK 目录丢失" >&2; exit 1; }
mkdir -p "$WORK/source"

clone_pinned() {
  local name="$1" url="$2" expected="$3"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo "源码未固定 commit：$name" >&2; return 1; }
  git init -q "$WORK/source/$name"
  git -C "$WORK/source/$name" remote add origin "$url"
  git -C "$WORK/source/$name" -c protocol.version=2 fetch -q --depth 1 origin "$expected"
  git -C "$WORK/source/$name" checkout -q --detach FETCH_HEAD
  test "$(git -C "$WORK/source/$name" rev-parse HEAD)" = "$expected" || { echo "源码 SHA 不匹配 $name" >&2; return 1; }
  echo "$name 固定提交 $expected"
}
clone_pinned qosmate https://github.com/hudra0/qosmate.git ad5ef37a6b38b651849eccb33670a5398e06c876
clone_pinned luci-app-qosmate https://github.com/hudra0/luci-app-qosmate.git f37bc15498f7cbe3cd2cb912d1133551c9a5a738
clone_pinned internet-detector https://github.com/gSpotx2f/luci-app-internet-detector.git e265fcc8a9d9fd359f29fd0188ab2da3ce1438fa

cd "$SDK"
# SDK 只准备本项目确实使用的 feed 定义。
# 不能 install -a：会激活整个 LuCI + packages 生态，触发 weechat
# 递归依赖及无关内核模块的编译（2026-11-05 CI #30 亲测）。
./scripts/feeds update luci packages
./scripts/feeds install -p packages lua luaposix || {
  echo "核心 Lua 定义无法安装到 SDK" >&2; exit 1;
}
./scripts/feeds install -p luci luci-base luci-lib-jsonc || {
  echo "核心 LuCI 定义无法安装到 SDK" >&2; exit 1;
}
# 只选构建目标；关闭 SDK 的「所有包 / 所有内核模块」模式。
# ImageBuilder 随后会从 OpenWrt 官方软件源解析完整运行时依赖。
# 官方预编译 SDK 可能不自带 .config。先创建初始文件，随后 make defconfig。
# 不得在不存在的 .config 上执行 sed（CI #42057021279 的直接失败原因）。
touch .config
touch .config
sed -i '/^CONFIG_ALL=y$/d; /^CONFIG_ALL_KMODS=y$/d; /^CONFIG_ALL_NONSHARED=y$/d' .config

mkdir -p package/qosmate package/luci-app-qosmate package/internet-detector package/luci-app-internet-detector
cp -a "$WORK/source/qosmate/." package/qosmate/
cp -a "$WORK/source/luci-app-qosmate/." package/luci-app-qosmate/
cp -a "$WORK/source/internet-detector/internet-detector/." package/internet-detector/
cp -a "$WORK/source/internet-detector/luci-app-internet-detector/." package/luci-app-internet-detector/
# 使用仓库已校对的简体中文 gettext 翻译，让 SDK 一并生成中文 APK。
mkdir -p package/luci-app-internet-detector/po/zh_Hans
cp "$ROOT/assets/i18n/internet-detector.zh_Hans.po" package/luci-app-internet-detector/po/zh_Hans/internet-detector.po

cat >> .config <<'EOF'
CONFIG_PACKAGE_qosmate=m
CONFIG_PACKAGE_luci-app-qosmate=m
CONFIG_PACKAGE_internet-detector=m
CONFIG_PACKAGE_luci-app-internet-detector=m
EOF
make defconfig
# SDK 不含 OpenWrt 主树的全部 package/libs 定义；从 25.12.6
# 官方 release 对应的固定 commit 引入单独 libjson-c Makefile。
# 这不是额外第三方源码，JSON-C 源码内容仍由上游 PKG_HASH 校验。
mkdir -p package/libs/libjson-c
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
  -o package/libs/libjson-c/Makefile \
  "https://raw.githubusercontent.com/openwrt/openwrt/64900e756efa667774214f9c6b17c113222e01f7/package/libs/libjson-c/Makefile"
grep -Fqx 'PKG_HASH:=602cdefc1d2aab8318fc0814b7ce7d59e72514d4276ca3eff92f35f86cf1c160' \
  package/libs/libjson-c/Makefile || { echo "libjson-c 官方源码哈希不符合预期" >&2; exit 1; }
# Runner 中的新版 CMake 已移除对低于 3.5 的兼容默认值，
# libjson-c 0.18 上游 apps/CMakeLists.txt 仍声明更早的最低版本。
# 仅为这一个 SDK 构建添加 CMake 兼容策略，不修改运行时二进制配置。
cat >> package/libs/libjson-c/Makefile <<'EOF'

CMAKE_OPTIONS += -DCMAKE_POLICY_VERSION_MINIMUM=3.5
EOF
make defconfig

# LuCI SDK 需要 libjson-c 的开发头文件。ImageBuilder 的运行时 APK
# 不会向 SDK staging_dir 提供头文件；必须先构建官方 json-c 开发依赖。
# 2026-11-05 CI #41981985431 失败于 json-c/json.h 缺失，修复根因。
echo "SDK 准备 libjson-c 开发头文件"
make -j2 package/libs/libjson-c/compile V=s
test -s staging_dir/target-x86_64_musl/usr/include/json-c/json.h || {
  echo "SDK 尚未安装 libjson-c 开发头文件，停止而不继续盲目编译" >&2
  exit 1
}
for name in qosmate luci-app-qosmate internet-detector luci-app-internet-detector; do
  echo "SDK 编译 $name"
  make -j2 "package/$name/compile" V=s 2>&1 | tee "$WORK/build-$name.log" || {
    grep -E '(^| )error:|^make.*\*\*\*|^.*fatal error:' "$WORK/build-$name.log" | tail -30 >&2 || true
    exit 1
  }
done

for name in qosmate luci-app-qosmate internet-detector luci-app-internet-detector; do
  mapfile -t found < <(find "$SDK/bin" -type f \( -name "$name-*.apk" -o -name "${name}_*.apk" \))
  (("${#found[@]}" == 1)) || { printf '无法唯一确认 %s 产物: %s\n' "$name" "${found[*]}" >&2; exit 1; }
  path="${found[0]}"
  file="$(basename "$path")"
  file="${file%.apk}"
  file="${file%_x86_64}"
  file="${file%_all}"
  cp -v "$path" "$OUT/$file.apk"
done

# 如果项目生成了简体中文包，则一起复制；最终必须在 ImageBuilder 中校验。
find "$SDK/bin" -type f \( -name 'luci-i18n-qosmate-zh-cn*.apk' -o -name 'luci-i18n-internet-detector-zh-cn*.apk' \) -exec cp -v '{}' "$OUT/" \;
echo "SDK 编译完毕："
find "$OUT" -maxdepth 1 -type f -name '*.apk' -printf '%f\n' | sort
