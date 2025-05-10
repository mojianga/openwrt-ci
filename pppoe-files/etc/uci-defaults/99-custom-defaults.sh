# <buildroot>/files/etc/uci-defaults/99-custom-defaults.sh
#!/bin/sh

# Your UCI commands or other shell commands here
uci set network.wan.proto=pppoe
uci set network.wan.username='clan2101243254'
uci set network.wan.password='123456'

# wifi
uci set wireless.radio0.cell_density='0'
uci set wireless.default_radio0.ssid='24G'
uci set wireless.default_radio0.encryption='sae-mixed'
uci set wireless.default_radio0.key='students'
uci set wireless.default_radio0.ocv='0'
uci set wireless.radio1.cell_density='0'
uci set wireless.default_radio1.ssid='58G'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio1.key='students'
uci set wireless.default_radio1.ocv='0'


uci commit network
/etc/init.d/network restart

# Remove this script after execution (optional but recommended)
rm -f /etc/uci-defaults/99-custom-defaults.sh
