# 修改默认IP
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

git clone --depth=1 https://github.com/EasyTier/luci-app-easytier.git package/easytier

printf "\nsrc-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main\n" >> "feeds.conf.default"