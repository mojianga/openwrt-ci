# 修改默认IP
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 如果是这个uboot, https://drive.wrt.moe/uboot/mediatek 
# 存在web升级的问题
# 来源: https://www.right.com.cn/forum/thread-8448669-1-2.html