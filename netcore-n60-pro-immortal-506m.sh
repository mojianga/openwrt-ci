#!/bin/bash
# ============================================================================
# Netcore N60 Pro / MT7986A / 2GB DDR4 / 512MB SPI NAND (W25N04KV)
# 分区：spi-nand-512MB-ubi-506.5MB
#   ubi offset = 0x0580000 (bl2 1M + u-boot-env 512K + factory 2M + fip 2M)
#   ubi size   = 0x1fa80000 (506.5 MiB)
#   0x580000 + 0x1fa80000 = 0x20000000 -> 顶满整片 512MB
#
# 本脚本做三件事：改默认 IP、把 DTS 的 ubi 分区改成 506.5MB、准备 sing-box 源。
# 固件不预装 momo / meow / easytier 等代理工具，只预装它们需要的依赖 + sing-box（momo 依赖它），
# 依赖清单见 configs/netcore-n60-pro-immortal.config。
# 可用函数见 netcore-n60-pro-diy-lib.sh（内嵌工具等为可选项，默认不调用）。
#
# 用法：cd <openwrt 源码根目录> && /path/to/netcore-n60-pro-immortal-506m.sh
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=netcore-n60-pro-diy-lib.sh
source "$SCRIPT_DIR/netcore-n60-pro-diy-lib.sh"

n60pro_assert_openwrt

UBI_506M="0x0580000 0x1fa80000"

n60pro_set_lan_ip

# sing-box：内置 golang 可能偏旧，先换 sbwml 的 golang feed，再用 kenzok8 的 sing-box 替换内置包
n60pro_replace_golang
n60pro_replace_singbox

n60pro_patch_ubi "$UBI_506M"

n60pro_log "DIY 完成：分区 506.5MB"
