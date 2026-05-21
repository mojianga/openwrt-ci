# 修改默认IP
sed -i 's/192.168.1.1/192.168.11.1/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 替换sing-box
find . -type d -name "sing-box" -exec rm -rf {} +
git clone --depth=1 https://github.com/kenzok8/small-package.git /tmp/kenzok8
mv /tmp/kenzok8/sing-box/ feeds/packages/net/
