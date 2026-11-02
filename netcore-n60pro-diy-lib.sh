#!/bin/bash
# ============================================================================
# Netcore N60 Pro (MT7986A) 硬改大分区固件 —— DIY 函数库（library，不是可执行脚本）
#
# 这里只有函数定义，本身不干活（直接执行会报错退出）。由下面两份 DIY 脚本 source：
#   netcore-n60pro-immortal-506m.sh / netcore-n60pro-immortal-490m.sh
# GitHub Actions 里做二次改分区时也会 source 它：
#   source "$(dirname "${BASH_SOURCE[0]}")/netcore-n60pro-diy-lib.sh"
# 注意与仓库里的 libwrt.sh / x86.sh 区别：那两个是可执行的 DIY 脚本，本文件是函数库。
#
# 约定：所有函数都假定当前工作目录是 OpenWrt 源码根目录（CI 里由 workflow
#       负责 cd，本地编译时请先 cd 到源码根目录）。
# 下面的默认值都可以用同名环境变量覆盖。
# ============================================================================

# 防止被误执行（只允许 source）
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "这是公共函数库，请用 source 引入，不要直接执行" >&2
  exit 1
fi

# ---- 可覆盖的默认参数 ------------------------------------------------------
: "${N60PRO_DTS:=target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts}"
# 上游 immortalwrt 的原始 ubi 分区定义，用来定位需要被替换的位置
: "${N60PRO_UBI_UPSTREAM:=0x0580000 0x7a80000}"
: "${N60PRO_LAN_IP:=192.168.12.1}"

: "${SINGBOX_REPO:=https://github.com/kenzok8/small-package.git}"
: "${GOLANG_REPO:=https://github.com/sbwml/packages_lang_golang.git}"
: "${GOLANG_REF:=}"                      # 留空=默认分支；需要可复现时填 tag/commit

: "${MEOW_REPO:=meow-rs/meow-rs}"
: "${MEOW_VERSION:=latest}"              # latest=自动取最新；也可写 0.27.0 / v0.27.0
: "${MEOW_MIRROR:=}"                     # 留空=GitHub 直连；国内可填 https://ghfast.top/
: "${MEOW_ARCH:=aarch64_cortex-a53}"     # MT7986A = Cortex-A53
: "${MEOW_REV_MAX:=9}"                   # 上游发布号 -rN 的探测上限

: "${EASYTIER_REPO:=EasyTier/luci-app-easytier}"
: "${EASYTIER_VERSION:=latest}"          # latest=自动取最新；也可写 2.6.4 / v2.6.4
: "${EASYTIER_MIRROR:=}"                 # 同 MEOW_MIRROR
: "${EASYTIER_ARCH:=aarch64_cortex-a53}" # 与 MEOW_ARCH 一致
: "${EASYTIER_FLAVOR:=noweb}"            # noweb=不带内置 Web 控制台(~8MB)；web=带(~15MB)

# ---- 日志 / 断言 -----------------------------------------------------------
n60pro_log() { printf '\033[1;32m[n60pro]\033[0m %s\n' "$*"; }
n60pro_err() { printf '\033[1;31m[n60pro][ERROR]\033[0m %s\n' "$*" >&2; }
n60pro_die() { n60pro_err "$*"; exit 1; }

n60pro_assert_openwrt() {
  { [ -d package/base-files ] && [ -d target/linux ]; } \
    || n60pro_die "当前目录不是 OpenWrt 源码根目录: $PWD"
}

_n60pro_curl() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 "$@"
}

# 解析 releases/latest：跟随 302 到 /releases/tag/<tag>，不消耗 GitHub API 额度
_n60pro_latest_tag() {
  local url
  url=$(_n60pro_curl -o /dev/null -w '%{url_effective}' \
          "https://github.com/$1/releases/latest" 2>/dev/null || true)
  case "$url" in
    */releases/tag/*) printf '%s' "${url##*/releases/tag/}" ;;
  esac
}

# 统一解析版本号：latest 取最新 tag，否则补 v 前缀
_n60pro_resolve_tag() {
  local repo="$1" ver="$2" tag
  if [ "$ver" = "latest" ]; then
    tag=$(_n60pro_latest_tag "$repo")
  else
    case "$ver" in
      v*) tag="$ver" ;;
      *)  tag="v${ver}" ;;
    esac
  fi
  printf '%s' "$tag"
}

# ---- 1) 默认管理 IP --------------------------------------------------------
n60pro_set_lan_ip() {
  local ip="${1:-$N60PRO_LAN_IP}"
  local f="package/base-files/files/bin/config_generate"

  [ -f "$f" ] || n60pro_die "未找到 $f"
  sed -i "s/192\.168\.1\.1/${ip//./\\.}/g" "$f"
  grep -qF "$ip" "$f" || n60pro_die "默认管理 IP 写入失败: $ip"
  n60pro_log "默认管理 IP -> $ip"
}

# ---- 2) 替换 sing-box ------------------------------------------------------
n60pro_replace_singbox() {
  local tmp

  tmp=$(mktemp -d)

  n60pro_log "移除旧 sing-box 包目录"
  find . -type d -name sing-box -prune -exec rm -rf {} + 2>/dev/null || true

  n60pro_log "克隆 sing-box 源: $SINGBOX_REPO"
  if ! git clone --depth=1 "$SINGBOX_REPO" "$tmp/src" >/dev/null 2>&1; then
    rm -rf "$tmp"
    n60pro_die "克隆 small-package 失败: $SINGBOX_REPO"
  fi
  if [ ! -d "$tmp/src/sing-box" ]; then
    rm -rf "$tmp"
    n60pro_die "small-package 中未找到 sing-box 目录"
  fi

  mkdir -p feeds/packages/net
  rm -rf feeds/packages/net/sing-box
  mv "$tmp/src/sing-box" feeds/packages/net/
  rm -rf "$tmp"
  n60pro_log "sing-box 已替换"
}

# ---- 3) 替换 golang --------------------------------------------------------
n60pro_replace_golang() {
  local dst="feeds/packages/lang/golang"

  n60pro_log "替换 golang feed: $GOLANG_REPO ${GOLANG_REF:-<默认分支>}"
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"

  if [ -n "$GOLANG_REF" ]; then
    git clone --depth=1 -b "$GOLANG_REF" "$GOLANG_REPO" "$dst" >/dev/null 2>&1 \
      || n60pro_die "克隆 golang feed 失败: $GOLANG_REPO @ $GOLANG_REF"
  else
    git clone --depth=1 "$GOLANG_REPO" "$dst" >/dev/null 2>&1 \
      || n60pro_die "克隆 golang feed 失败: $GOLANG_REPO"
  fi

  [ -f "$dst/Makefile" ] || n60pro_die "golang feed 结构异常: $dst/Makefile 不存在"
  n60pro_log "golang 已替换，commit = $(git -C "$dst" rev-parse --short HEAD 2>/dev/null || echo unknown)"
}

# ---- 4) 大分区 DTS 补丁 ----------------------------------------------------
# 用法: n60pro_patch_ubi "<新分区定义>" ["<原分区定义>"] ["<dts 路径>"]
#   幂等：如果目标定义已存在则直接跳过，方便 workflow 里二次改分区时复用。
n60pro_patch_ubi() {
  local new="$1"
  local old="${2:-$N60PRO_UBI_UPSTREAM}"
  local dts="${3:-$N60PRO_DTS}"

  [ -n "$new" ] || n60pro_die '用法: n60pro_patch_ubi "<新分区定义>" ["<原分区定义>"] ["<dts>"]'
  [ -f "$dts" ] || n60pro_die "DTS 不存在: $dts"

  if grep -qF "$new" "$dts"; then
    n60pro_log "DTS 已经是目标分区 [$new]，跳过替换"
  else
    if ! grep -qF "$old" "$dts"; then
      n60pro_err "未找到上游原始分区定义 [$old]，上游可能已变更，当前内容："
      grep -n -A3 'label = "ubi"' "$dts" || true
      exit 1
    fi
    sed -i "s/$old/$new/" "$dts"
    grep -qF "$new" "$dts" || n60pro_die "DTS 补丁写入失败"
    n60pro_log "DTS ubi 分区 -> $new"
  fi

  grep -n -A3 'label = "ubi"' "$dts" || true
}

# ---- 5) 内嵌 meow（预编译 apk -> files/ -> 首次启动安装）------------------
# OpenWrt master 的 apk 是 apk-tools 3 的 ADB 容器，buildroot 阶段无法解包，
# 所以只能把整包放进 rootfs，由 uci-defaults 在设备首次启动时安装。
n60pro_embed_meow() {
  local files_dir="$PWD/files"
  local tag ver_num official fetch

  # 1) 解析版本（latest 走 releases/latest 的 302，不消耗 API 额度）
  tag=$(_n60pro_resolve_tag "$MEOW_REPO" "$MEOW_VERSION")
  [ -n "$tag" ] || n60pro_die "解析 meow 版本失败: $MEOW_VERSION"
  ver_num="${tag#v}"
  n60pro_log "meow version -> ${tag}"

  official="https://github.com/${MEOW_REPO}/releases/download/${tag}"
  fetch="${MEOW_MIRROR}${official}"

  # 2) 探测实际包名（上游的 -rN 发布号会变）
  _n60pro_meow_pick_pkg() {
    local name="$1" arch="$2" r f
    for ((r = 1; r <= MEOW_REV_MAX; r++)); do
      f="${name}_${ver_num}-r${r}_${arch}.apk"
      if _n60pro_curl -I -o /dev/null --max-time 20 "${fetch}/${f}" 2>/dev/null; then
        printf '%s' "$f"
        return 0
      fi
    done
    return 1
  }

  local core_pkg luci_pkg
  core_pkg=$(_n60pro_meow_pick_pkg meow "$MEOW_ARCH") \
    || n60pro_die "未找到 meow core 的 ${MEOW_ARCH} 包（${tag}）"
  luci_pkg=$(_n60pro_meow_pick_pkg luci-app-meow all) \
    || n60pro_die "未找到 luci-app-meow 包（${tag}）"
  n60pro_log "core: ${core_pkg}"
  n60pro_log "luci: ${luci_pkg}"

  # 3) 下载：哈希只从 GitHub 官方取，二进制可以走镜像
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$files_dir/usr/share/meow" "$files_dir/etc/uci-defaults"
  _n60pro_curl -o "$tmp/core.apk.sha256" "${official}/${core_pkg}.sha256" || n60pro_die "下载 core sha256 失败"
  _n60pro_curl -o "$tmp/luci.apk.sha256" "${official}/${luci_pkg}.sha256" || n60pro_die "下载 luci sha256 失败"
  _n60pro_curl -o "$tmp/core.apk"        "${fetch}/${core_pkg}"          || n60pro_die "下载 meow core 失败"
  _n60pro_curl -o "$tmp/luci.apk"        "${fetch}/${luci_pkg}"          || n60pro_die "下载 luci-app-meow 失败"

  local n sum
  for n in core luci; do
    sum=$(grep -oE '[0-9a-fA-F]{64}' "$tmp/${n}.apk.sha256" | head -1 | tr 'A-F' 'a-f')
    [ -n "$sum" ] || n60pro_die "${n} 的 sha256 文件解析失败"
    printf '%s  %s\n' "$sum" "$tmp/${n}.apk" | sha256sum -c - >/dev/null \
      || n60pro_die "${n} 校验失败"
  done
  n60pro_log "sha256 校验通过"

  cp -f "$tmp/core.apk" "$files_dir/usr/share/meow/meow.apk"
  cp -f "$tmp/luci.apk" "$files_dir/usr/share/meow/luci-app-meow.apk"
  rm -rf "$tmp"

  cat > "$files_dir/etc/uci-defaults/99-install-meow" <<'EOS'
#!/bin/sh
# 首次启动安装内嵌的 meow 包（apk-tools 3 的 ADB 包，只能在设备上装）
# 说明：纯本地 apk add，不联网、不 reboot，失败最坏结果就是多花几秒 + 下次启动重试
APKDIR=/usr/share/meow
LOG=/tmp/meow-install.log
VER="__MEOW_VER__"
CNT="/etc/meow-install.retry.$VER"
MAX=3
APK=$(command -v apk || echo /usr/bin/apk)

[ -x "$APK" ] || exit 0
[ -f "$APKDIR/meow.apk" ] || exit 0

tries=0
[ -f "$CNT" ] && tries=$(cat "$CNT" 2>/dev/null || echo 0)
if [ "$tries" -ge "$MAX" ]; then
  # 连续失败 MAX 次后放弃，避免每次启动都重试；apk 仍留在 $APKDIR 可手动安装
  logger -t meow-install "give up after $MAX tries, install manually: apk add --allow-untrusted $APKDIR/*.apk"
  exit 0
fi

echo "=== meow install start (try $((tries + 1))/$MAX) ===" > "$LOG"
rc=0
for p in meow luci-app-meow; do
  f="$APKDIR/$p.apk"
  [ -f "$f" ] || continue
  out=$("$APK" add --upgrade --allow-untrusted "$f" 2>&1)
  rc_pkg=$?
  echo "$out" >> "$LOG"
  if [ "$rc_pkg" -ne 0 ]; then
    case "$out" in
      *"already installed"*) ;;
      *) echo "install $p FAILED" >> "$LOG"; rc=1 ;;
    esac
  fi
done

# 清 LuCI 缓存，让菜单立刻出现
rm -rf /tmp/luci-* 2>/dev/null

if [ "$rc" -ne 0 ]; then
  # 返回非 0 时 uci-defaults 会保留本脚本，下次启动继续重试
  echo $((tries + 1)) > "$CNT"
  logger -t meow-install "install failed (try $((tries + 1))/$MAX), see $LOG"
  exit 1
fi

rm -f /etc/meow-install.retry.*

# apk add <文件> 会把 "包名><哈希" 写进 /etc/apk/world，等于把包钉死在这份 apk 上；
# 换固件后哈希无解会让后续 apk 操作报错，这里改回纯包名。
for p in meow luci-app-meow; do
  if grep -q "^$p[><=~]" /etc/apk/world 2>/dev/null; then
    sed -i "/^$p[><=~]/d" /etc/apk/world
    echo "$p" >> /etc/apk/world
  fi
done

logger -t meow-install "done, see $LOG"
exit 0
EOS
  # 把版本号写进设备端脚本：计数文件按版本区分，换固件/换版本后自动重置重试次数
  sed -i "s/__MEOW_VER__/${ver_num}/" "$files_dir/etc/uci-defaults/99-install-meow"
  chmod +x "$files_dir/etc/uci-defaults/99-install-meow"

  n60pro_log "meow 已内嵌：$(ls -1 "$files_dir/usr/share/meow/" | tr '\n' ' ')"
}

# ---- 6) 内嵌 EasyTier（release zip -> 解压出 apk -> 首启安装）-------------
# 上游发布形态：EasyTier-<tag>-<arch>-SNAPSHOT.zip（SNAPSHOT=apk 包，22.03.7=ipk 包）
# 包内：easytier-<ver>.apk(带 Web 控制台) / easytier-noweb-<ver>.apk /
#       luci-app-easytier-<ver>-r1.apk / luci-i18n-easytier-zh-cn-<ver>.apk
# 上游没有提供 .sha256，这里用 unzip -t 完整性校验 + apk 魔数(ADBd) 双重检查
n60pro_embed_easytier() {
  local files_dir="$PWD/files"
  local dstdir="$files_dir/usr/share/easytier"
  local tag official fetch asset tmp core luci i18n

  tag=$(_n60pro_resolve_tag "$EASYTIER_REPO" "$EASYTIER_VERSION")
  [ -n "$tag" ] || n60pro_die "解析 easytier 版本失败: $EASYTIER_VERSION"
  n60pro_log "easytier version -> ${tag}"

  official="https://github.com/${EASYTIER_REPO}/releases/download/${tag}"
  fetch="${EASYTIER_MIRROR}${official}"
  asset="EasyTier-${tag}-${EASYTIER_ARCH}-SNAPSHOT.zip"

  # 1) 下载 zip 并校验完整性
  tmp=$(mktemp -d)
  n60pro_log "下载 ${fetch}/${asset}"
  if ! _n60pro_curl -o "$tmp/et.zip" "${fetch}/${asset}"; then
    rm -rf "$tmp"
    n60pro_die "下载 easytier 安装包失败: ${fetch}/${asset}"
  fi
  if ! unzip -tq "$tmp/et.zip" >/dev/null; then
    rm -rf "$tmp"
    n60pro_die "easytier zip 完整性校验失败"
  fi
  unzip -oq "$tmp/et.zip" -d "$tmp/x" || { rm -rf "$tmp"; n60pro_die "解压 easytier zip 失败"; }

  # 2) 从解压结果中挑包（文件名带版本号，用通配匹配）
  _n60pro_et_pick() {
    local f
    f=$(find "$tmp/x" -maxdepth 1 -type f -name "$1" | sort | head -1)
    [ -n "$f" ] || return 1
    [ "$(head -c 4 "$f")" = "ADBd" ] || n60pro_die "不是 apk-tools 3 包: $f"
    printf '%s' "$f"
  }

  case "$EASYTIER_FLAVOR" in
    noweb) core=$(_n60pro_et_pick 'easytier-noweb-*.apk') || core='' ;;
    web)   core=$(_n60pro_et_pick 'easytier-[0-9]*.apk') || core='' ;;
    *)     rm -rf "$tmp"; n60pro_die "EASYTIER_FLAVOR 只能是 noweb 或 web: $EASYTIER_FLAVOR" ;;
  esac
  [ -n "$core" ] || { rm -rf "$tmp"; n60pro_die "zip 中未找到 easytier 核心包（${EASYTIER_FLAVOR}）"; }

  luci=$(_n60pro_et_pick 'luci-app-easytier-*.apk') || luci=''
  [ -n "$luci" ] || { rm -rf "$tmp"; n60pro_die "zip 中未找到 luci-app-easytier 包"; }
  i18n=$(_n60pro_et_pick 'luci-i18n-easytier-zh-cn-*.apk') || i18n=''

  n60pro_log "core: $(basename "$core")"
  n60pro_log "luci: $(basename "$luci")"
  if [ -n "$i18n" ]; then
    n60pro_log "i18n: $(basename "$i18n")"
  fi

  # 3) 落到 files/，由 uci-defaults 在设备首次启动时 apk add
  mkdir -p "$dstdir" "$files_dir/etc/uci-defaults"
  cp -f "$core" "$dstdir/easytier.apk"
  cp -f "$luci" "$dstdir/luci-app-easytier.apk"
  if [ -n "$i18n" ]; then
    cp -f "$i18n" "$dstdir/luci-i18n-easytier-zh-cn.apk"
  else
    rm -f "$dstdir/luci-i18n-easytier-zh-cn.apk"
  fi
  rm -rf "$tmp"

  cat > "$files_dir/etc/uci-defaults/99-install-easytier" <<'EOS'
#!/bin/sh
# 首次启动安装内嵌的 EasyTier（apk-tools 3 的 ADB 包，只能在设备上装）
# 说明：纯本地 apk add，不联网、不 reboot，失败最坏结果就是多花几秒 + 下次启动重试
APKDIR=/usr/share/easytier
LOG=/tmp/easytier-install.log
VER="__ET_VER__"
CNT="/etc/easytier-install.retry.$VER"
MAX=3
APK=$(command -v apk || echo /usr/bin/apk)

[ -x "$APK" ] || exit 0
[ -f "$APKDIR/easytier.apk" ] || exit 0

tries=0
[ -f "$CNT" ] && tries=$(cat "$CNT" 2>/dev/null || echo 0)
if [ "$tries" -ge "$MAX" ]; then
  # 连续失败 MAX 次后放弃，避免每次启动都重试；apk 仍留在 $APKDIR 可手动安装
  logger -t easytier-install "give up after $MAX tries, install manually: apk add --allow-untrusted $APKDIR/*.apk"
  exit 0
fi

echo "=== easytier install start (try $((tries + 1))/$MAX) ===" > "$LOG"
rc=0
# 顺序：核心 -> LuCI -> 中文语言包
for p in easytier luci-app-easytier luci-i18n-easytier-zh-cn; do
  f="$APKDIR/$p.apk"
  [ -f "$f" ] || continue
  out=$("$APK" add --upgrade --allow-untrusted "$f" 2>&1)
  rc_pkg=$?
  echo "$out" >> "$LOG"
  if [ "$rc_pkg" -ne 0 ]; then
    case "$out" in
      # 已安装同版本时 apk 会报这个，不算失败
      *"already installed"*) ;;
      *) echo "install $p FAILED" >> "$LOG"; rc=1 ;;
    esac
  fi
done

# 清 LuCI 缓存，让菜单立刻出现
rm -rf /tmp/luci-* 2>/dev/null

if [ "$rc" -ne 0 ]; then
  # 返回非 0 时 uci-defaults 会保留本脚本，下次启动继续重试
  echo $((tries + 1)) > "$CNT"
  logger -t easytier-install "install failed (try $((tries + 1))/$MAX), see $LOG"
  exit 1
fi

rm -f /etc/easytier-install.retry.*

# apk add <文件> 会把 "包名><哈希" 写进 /etc/apk/world，等于把包钉死在这份 apk 上；
# 换固件后哈希无解会让后续 apk 操作报错，这里改回纯包名。
for p in easytier luci-app-easytier luci-i18n-easytier-zh-cn; do
  if grep -q "^$p[><=~]" /etc/apk/world 2>/dev/null; then
    sed -i "/^$p[><=~]/d" /etc/apk/world
    echo "$p" >> /etc/apk/world
  fi
done

logger -t easytier-install "done, see $LOG"
exit 0
EOS
  # 把版本号写进设备端脚本：计数文件按版本区分，换固件/换版本后自动重置重试次数
  sed -i "s/__ET_VER__/${tag#v}/" "$files_dir/etc/uci-defaults/99-install-easytier"
  chmod +x "$files_dir/etc/uci-defaults/99-install-easytier"

  # config 里若已从 feed 编译了同名包，这里是“覆盖安装”，会造成镜像内重复打包
  if grep -qs '^CONFIG_PACKAGE_easytier=y' "$PWD/.config"; then
    n60pro_log "提示: .config 已启用 CONFIG_PACKAGE_easytier（源码编译），内嵌 apk 会在首启覆盖同名包；"
    n60pro_log "      如果只想保留预编译版，请从 configs 里删掉 CONFIG_PACKAGE_easytier / luci-app-easytier / luci-i18n-easytier-zh-cn"
  fi

  n60pro_log "easytier 已内嵌：$(ls -1 "$dstdir" | tr '\n' ' ')"
}
