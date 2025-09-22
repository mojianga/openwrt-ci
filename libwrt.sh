rm -rf package/emortal/luci-app-athena-led
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# 修改默认IP
sed -i 's/192.168.1.1/192.168.22.1/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

git clone --depth=1 https://github.com/EasyTier/luci-app-easytier.git package/easytier

# nikki
# printf "\nsrc-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main\n" >> "feeds.conf.default"
sed '1i src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' feeds.conf.default

# passwall
# printf "\nsrc-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main\n" >> "feeds.conf.default"
# printf "\nsrc-git passwall_luci https://github.com/xiaorouji/openwrt-passwall.git;main\n" >> "feeds.conf.default"
sed '1i src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main' feeds.conf.default
sed '1i src-git passwall_luci https://github.com/xiaorouji/openwrt-passwall.git;main' feeds.conf.default