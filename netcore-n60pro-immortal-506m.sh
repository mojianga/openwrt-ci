#!/bin/bash
set -e

# ============================================================
# Netcore N60 Pro / MT7986A / 2GB DDR4 / 512MB SPI NAND (W25N04KV)
# U-Boot 布局: spi-nand-512MB-ubi-506.5MB（备用）
# ============================================================

# 默认管理 IP: 192.168.12.1
sed -i 's/192.168.1.1/192.168.12.1/g' package/base-files/files/bin/config_generate

# 替换 sing-box
find . -type d -name "sing-box" -exec rm -rf {} +
git clone --depth=1 https://github.com/kenzok8/small-package.git /tmp/kenzok8
mv /tmp/kenzok8/sing-box/ feeds/packages/net/

# 替换 golang
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang

# ============================================================
# 512MB 大分区适配
#   ubi offset = 0x580000
#   ubi size   = 0x1fa80000 (506.5 MiB)
#   0x580000 + 0x1fa80000 = 0x20000000 -> 顶满整片 512MB
# ============================================================
DTS=target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts
OLD="0x0580000 0x7a80000"
NEW="0x0580000 0x1fa80000"

[ -f "$DTS" ] || { echo "ERROR: DTS 不存在: $DTS"; exit 1; }

if ! grep -qF "$OLD" "$DTS"; then
  echo "ERROR: 未找到上游原始分区定义 [$OLD]，上游可能已变更，当前内容："
  grep -n -A3 'label = "ubi"' "$DTS" || true
  exit 1
fi

sed -i "s/$OLD/$NEW/" "$DTS"
grep -qF "$NEW" "$DTS" || { echo "ERROR: DTS 补丁写入失败"; exit 1; }

echo "==================== DTS 已打补丁 ===================="
grep -n -A3 'label = "ubi"' "$DTS"
echo "======================================================"

# ============================================================
# 内嵌 meow（预编译 apk -> files/ -> 首次启动安装）
#   平台: MT7986A = Cortex-A53 -> aarch64_cortex-a53
#   版本: MEOW_VER=latest 自动取最新；想固定就改成 0.27.0
#   下载: MEOW_MIRROR 留空=GitHub 直连；国内本地编译可填 https://ghfast.top/
#   安全: 哈希只从 GitHub 官方 .sha256 取，镜像仅承担二进制传输
# ============================================================
FILES_DIR="$PWD/files"
MEOW_REPO="meow-rs/meow-rs"
MEOW_VER="${MEOW_VER:-latest}"
MEOW_MIRROR="${MEOW_MIRROR:-}"
MEOW_ARCH="aarch64_cortex-a53"

# 1) 解析版本：走 releases/latest 的 302 重定向，不消耗 GitHub API 额度
if [ "$MEOW_VER" = "latest" ]; then
  MEOW_TAG=$(curl -fsSI -o /dev/null -w '%{redirect_url}' \
      "https://github.com/${MEOW_REPO}/releases/latest" | sed 's#.*/tag/##')
  [ -n "$MEOW_TAG" ] || { echo "ERROR: 解析 meow 最新版本失败"; exit 1; }
else
  case "$MEOW_VER" in
    v*) MEOW_TAG="$MEOW_VER" ;;
    *)  MEOW_TAG="v${MEOW_VER}" ;;
  esac
fi
MEOW_VER_NUM="${MEOW_TAG#v}"
echo "meow version -> ${MEOW_TAG}"

OFFICIAL_URL="https://github.com/${MEOW_REPO}/releases/download/${MEOW_TAG}"
FETCH_URL="${MEOW_MIRROR}${OFFICIAL_URL}"

# 2) 探测实际包名（上游的 -rN 发布号可能变）
pick_pkg() {
  for _r in 1 2 3 4 5; do
    _f="${1}_${MEOW_VER_NUM}-r${_r}_${2}.apk"
    curl -fsIL -o /dev/null --max-time 20 "${FETCH_URL}/${_f}" && { echo "$_f"; return 0; }
  done
  return 1
}
CORE_PKG=$(pick_pkg meow "$MEOW_ARCH") || { echo "ERROR: 未找到 meow core 的 ${MEOW_ARCH} 包"; exit 1; }
LUCI_PKG=$(pick_pkg luci-app-meow all) || { echo "ERROR: 未找到 luci-app-meow 包"; exit 1; }
echo "core: ${CORE_PKG}"
echo "luci: ${LUCI_PKG}"

# 3) 下载：哈希走官方 GitHub，二进制可走镜像
mkdir -p /tmp/meow "$FILES_DIR/usr/share/meow" "$FILES_DIR/etc/uci-defaults"
curl -fsSL -o /tmp/meow/core.apk.sha256 "${OFFICIAL_URL}/${CORE_PKG}.sha256"
curl -fsSL -o /tmp/meow/luci.apk.sha256 "${OFFICIAL_URL}/${LUCI_PKG}.sha256"
curl -fsSL -o /tmp/meow/core.apk        "${FETCH_URL}/${CORE_PKG}"
curl -fsSL -o /tmp/meow/luci.apk        "${FETCH_URL}/${LUCI_PKG}"

for _n in core luci; do
  _sum=$(grep -oE '[0-9a-fA-F]{64}' "/tmp/meow/${_n}.apk.sha256" | head -1 | tr 'A-F' 'a-f')
  [ -n "$_sum" ] || { echo "ERROR: ${_n} 的 sha256 文件解析失败"; exit 1; }
  echo "${_sum}  /tmp/meow/${_n}.apk" | sha256sum -c - || { echo "ERROR: ${_n} 校验失败"; exit 1; }
done

cp /tmp/meow/core.apk "$FILES_DIR/usr/share/meow/meow.apk"
cp /tmp/meow/luci.apk "$FILES_DIR/usr/share/meow/luci-app-meow.apk"

cat > "$FILES_DIR/etc/uci-defaults/99-install-meow" <<'EOS'
#!/bin/sh
# 首次启动安装内嵌的 meow 包（apk-tools 3 的 ADB 包，只能在设备上装）
APKDIR=/usr/share/meow
LOG=/tmp/meow-install.log
APK=$(command -v apk || echo /usr/bin/apk)

[ -x "$APK" ] || exit 0
[ -f "$APKDIR/meow.apk" ] || exit 0

echo "=== meow install start ===" > "$LOG"
"$APK" add --allow-untrusted "$APKDIR/meow.apk" >> "$LOG" 2>&1
"$APK" add --allow-untrusted "$APKDIR/luci-app-meow.apk" >> "$LOG" 2>&1

# 清 LuCI 缓存，让菜单立刻出现
rm -rf /tmp/luci-* 2>/dev/null

logger -t meow-install "done, see $LOG"
exit 0
EOS
chmod +x "$FILES_DIR/etc/uci-defaults/99-install-meow"

echo "==================== meow 已内嵌 ===================="
ls -l "$FILES_DIR/usr/share/meow/"
echo "===================================================="
