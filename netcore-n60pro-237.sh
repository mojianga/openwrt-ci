# 修改默认IP
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.6.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 取消以下硬件的编译
sed -i '/glinet_gl-mt6000\|tplink_tl-xdr6086\|tplink_tl-xdr6088\|xiaomi_redmi-router-ax6000\|xiaomi_redmi-router-ax6000-stock/d' .config

# 去掉以下插件
sed -i '/argon/d' .config

# 升级编译时使用的golang版本
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# 如果是这个uboot, https://drive.wrt.moe/uboot/mediatek 
# 存在web升级的问题
# 来源: https://www.right.com.cn/forum/thread-8448669-1-2.html
