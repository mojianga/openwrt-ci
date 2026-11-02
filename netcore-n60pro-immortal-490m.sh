#!/bin/bash
# ============================================================================
# Netcore N60 Pro / MT7986A / 2GB DDR4 / 512MB SPI NAND (W25N04KV)
# 分区：spi-nand-512MB-ubi-490MB（备用布局）
#   ubi offset = 0x0580000 (bl2 1M + u-boot-env 512K + factory 2M + fip 2M)
#   ubi size   = 0x1ea00000 (490 MiB)
#   0x580000 + 0x1ea00000 = 0x1ef80000 -> 尾部 0x1080000(16.5MB) 冗余
#
# 公共逻辑（换 sing-box / 换 golang / 装 meow / 装 easytier / 改 DTS）见 netcore-n60pro-diy-lib.sh
# 用法：cd <openwrt 源码根目录> && /path/to/netcore-n60pro-immortal-490m.sh
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=netcore-n60pro-diy-lib.sh
source "$SCRIPT_DIR/netcore-n60pro-diy-lib.sh"

n60pro_assert_openwrt

UBI_490M="0x0580000 0x1ea00000"

n60pro_set_lan_ip
n60pro_replace_singbox
n60pro_replace_golang
n60pro_patch_ubi "$UBI_490M"
n60pro_embed_meow
n60pro_embed_easytier

n60pro_log "DIY 完成：分区 490MB"
