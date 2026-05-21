# 修改默认IP
sed -i 's/192.168.1.1/192.168.12.1/g' package/base-files/files/bin/config_generate

# 替换sing-box
find . -type d -name "sing-box" -exec rm -rf {} +
git clone --depth=1 https://github.com/kenzok8/small-package.git /tmp/kenzok8
mv /tmp/kenzok8/sing-box/ feeds/packages/net/

# 替换golang
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang

# 如果是这个uboot, https://drive.wrt.moe/uboot/mediatek 
# 存在web升级的问题
# 来源: https://www.right.com.cn/forum/thread-8448669-1-2.html
