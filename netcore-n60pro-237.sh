# 修改默认IP
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.6.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 去掉编译这些硬件
sed -i '/glinet_gl-mt6000\|tplink_tl-xdr6086\|tplink_tl-xdr6088\|xiaomi_redmi-router-ax6000\|xiaomi_redmi-router-ax6000-stock\|argon/d' .config

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# git clone --depth=1 https://github.com/EasyTier/luci-app-easytier.git package/easytier

# nikki
# printf "\nsrc-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main\n" >> "feeds.conf.default"
# sed '1i src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' feeds.conf.default
# git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki.git package/nikki

# passwall
# printf "\nsrc-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main\n" >> "feeds.conf.default"
# printf "\nsrc-git passwall_luci https://github.com/xiaorouji/openwrt-passwall.git;main\n" >> "feeds.conf.default"
# sed '1i src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main' feeds.conf.default
# sed '1i src-git passwall_luci https://github.com/xiaorouji/openwrt-passwall.git;main' feeds.conf.default
# 移除 openwrt feeds 自带的核心库
# rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages package/passwall-packages
# 移除 openwrt feeds 过时的luci版本
# rm -rf feeds/luci/applications/luci-app-passwall
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall package/passwall-luci
