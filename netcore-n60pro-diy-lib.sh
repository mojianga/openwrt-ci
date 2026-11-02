#!/bin/bash
# ============================================================================
# Netcore N60 Pro (MT7986A) 硬改大分区固件 —— DIY 函数库（library，不是可执行脚本）
#
# 这里只有函数定义，本身不干活（直接执行会报错退出）。由下面两份 DIY 脚本 source：
#   netcore-n60-pro-immortal-506m.sh / netcore-n60-pro-immortal-490m.sh
# GitHub Actions 里做二次改分区时也会 source 它：
#   source "$(dirname "${BASH_SOURCE[0]}")/netcore-n60-pro-diy-lib.sh"
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

: "${MOMO_REPO:=nikkinikki-org/OpenWrt-momo}"
: "${MOMO_VERSION:=latest}"              # latest=自动取最新；也可写 1.2.2 / v1.2.2
: "${MOMO_ARCH:=aarch64_cortex-a53}"     # MT7986A = Cortex-A53
: "${MOMO_BRANCH:=SNAPSHOT}"             # apk 版固件用 SNAPSHOT；opkg 版用 openwrt-24.10 / openwrt-25.12
: "${MOMO_MIRROR:=}"                     # 留空=GitHub 直连；国内可填 https://ghfast.top/
: "${MOMO_KEY_URL:=https://momomomo.pages.dev/public-key.pem}"  # 官方仓库公钥

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
  # small-package 仓库很大，先用部分克隆 + sparse-checkout 只取 sing-box 目录；不支持时退回完整克隆
  if git clone --depth=1 --filter=blob:none --sparse "$SINGBOX_REPO" "$tmp/src" >/dev/null 2>&1 \
     && git -C "$tmp/src" sparse-checkout set sing-box >/dev/null 2>&1 \
     && [ -d "$tmp/src/sing-box" ]; then
    n60pro_log "已用 sparse-checkout 只取 sing-box 目录"
  else
    rm -rf "$tmp/src"
    git clone --depth=1 "$SINGBOX_REPO" "$tmp/src" >/dev/null 2>&1 \
      || { rm -rf "$tmp"; n60pro_die "克隆 small-package 失败: $SINGBOX_REPO"; }
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

  # 上游仓库结构（sbwml/packages_lang_golang）：
  #   根目录 = golang-package.mk / golang-values.mk 等公共 .mk + golang/ 子目录里的包 Makefile
  # 所以整仓 clone 到 feeds/packages/lang/golang 后，包 Makefile 在 golang/Makefile，不在根目录
  if [ ! -f "$dst/golang-package.mk" ] || [ ! -f "$dst/golang/Makefile" ]; then
    n60pro_err "golang feed 结构异常，期望 $dst/golang-package.mk 与 $dst/golang/Makefile，实际内容："
    ls -A "$dst" 2>/dev/null | sed 's/^/  /' >&2
    n60pro_die "上游结构可能已变更，请检查 $GOLANG_REPO"
  fi
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

# ============================================================================
# 下面是**可选函数**，默认不被任何 DIY 脚本调用：
#   n60pro_embed_momo_repo   只内置 momo 本地 apk 仓库（不预装）
# 需要时把函数加回 DIY 脚本即可（依赖见 configs/netcore-n60-pro-immortal.config）。
# ============================================================================

# ---- 5) momo：只内置"本地 apk 仓库"，不预装 ------------------------------
# momo 官方 release 的 momo_<arch>-<branch>.tar.gz 本身就是一个完整的 apk 仓库：
#   packages.adb（apk-tools 3 索引）+ momo / luci-app-momo / luci-i18n-momo-zh-cn 三个 apk
# 这里把它塞进固件 /usr/share/momo-apk/，并写一条本地仓库到 /etc/apk/repositories.d/，
# 设备启动后在 LuCI「软件包」或命令行 apk add momo 即可安装，不需要联网、不受自编译 ABI 影响。
# 依赖（kmod-*、sing-box 等）必须已经预装进固件，见 configs/netcore-n60-pro-immortal.config 的说明。
n60pro_assert_momo_deps() {
  local p missing=''

  [ -f "$PWD/.config" ] || { n60pro_log "跳过 momo 依赖检查（当前目录没有 .config）"; return 0; }
  for p in ca-bundle curl firewall4 ip-full \
           kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy sing-box; do
    grep -qE "^CONFIG_PACKAGE_${p}=y" "$PWD/.config" || missing="$missing $p"
  done
  if [ -n "$missing" ]; then
    n60pro_err "momo 依赖没有编进固件:$missing"
    n60pro_die "kmod 类依赖必须与内核同源，无法事后在线补装；请在 configs 里选中它们"
  fi
  n60pro_log "momo 依赖齐全（curl / ip-full / firewall4 / ca-bundle / kmod-* / sing-box）"
}

n60pro_embed_momo_repo() {
  local files_dir="$PWD/files"
  local repo_dir="$files_dir/usr/share/momo-apk"
  local tag asset url tmp n

  n60pro_assert_momo_deps
  tag=$(_n60pro_resolve_tag "$MOMO_REPO" "$MOMO_VERSION")
  [ -n "$tag" ] || n60pro_die "解析 momo 版本失败: $MOMO_VERSION"
  asset="momo_${MOMO_ARCH}-${MOMO_BRANCH}.tar.gz"
  url="${MOMO_MIRROR}https://github.com/${MOMO_REPO}/releases/download/${tag}/${asset}"
  n60pro_log "momo repo -> ${tag}/${asset}"

  tmp=$(mktemp -d)
  if ! _n60pro_curl -o "$tmp/momo.tar.gz" "$url"; then
    rm -rf "$tmp"
    n60pro_die "下载 momo 仓库失败: $url（检查 MOMO_ARCH=${MOMO_ARCH} / MOMO_BRANCH=${MOMO_BRANCH} 组合是否存在）"
  fi

  mkdir -p "$tmp/x"
  tar -xzf "$tmp/momo.tar.gz" -C "$tmp/x" || { rm -rf "$tmp"; n60pro_die "解压 momo 仓库失败"; }

  [ -f "$tmp/x/packages.adb" ] || { rm -rf "$tmp"; n60pro_die "momo 包里没有 packages.adb，不是 apk 仓库"; }
  if [ -f "$tmp/x/index.json" ] && ! grep -q "$MOMO_ARCH" "$tmp/x/index.json"; then
    n60pro_err "index.json 里的架构不是 $MOMO_ARCH："
    head -5 "$tmp/x/index.json" >&2
    rm -rf "$tmp"
    n60pro_die "下载到了错误架构的 momo 仓库"
  fi
  n=$(ls -1 "$tmp/x"/*.apk 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || { rm -rf "$tmp"; n60pro_die "momo 仓库里没有 apk 包"; }

  # 1) 仓库文件落到 rootfs（本地仓库，离线可用）
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir" "$files_dir/etc/apk/keys" "$files_dir/etc/apk/repositories.d"
  cp -f "$tmp/x"/*.apk "$repo_dir"/
  cp -f "$tmp/x/packages.adb" "$repo_dir"/
  [ -f "$tmp/x/index.json" ] && cp -f "$tmp/x/index.json" "$repo_dir"/
  rm -rf "$tmp"

  # 2) 上游签名公钥（官方 feed 用的是 /etc/apk/keys/momo.pem 这个文件名）
  if ! _n60pro_curl -o "$files_dir/etc/apk/keys/momo.pem" "${MOMO_KEY_URL}"; then
    n60pro_die "下载 momo 公钥失败: ${MOMO_KEY_URL}"
  fi
  grep -q "BEGIN PUBLIC KEY" "$files_dir/etc/apk/keys/momo.pem" \
    || n60pro_die "momo 公钥格式异常（不是 PEM 公钥）"

  # 3) 本地仓库声明：索引名以 .adb 结尾，apk 会按 ndx(v3) 解析
  cat > "$files_dir/etc/apk/repositories.d/momo.list" <<'EOS'
# momo 本地 apk 仓库（随固件内置，离线可用）
# 安装：apk add momo luci-app-momo luci-i18n-momo-zh-cn
# 若提示 UNTRUSTED signature，可临时用 apk --allow-untrusted add momo
/usr/share/momo-apk/packages.adb
EOS

  n60pro_log "momo 仓库已内置：$n 个包，$(du -sk "$repo_dir" | awk '{print $1}') KB"
}
