# <buildroot>/files/etc/uci-defaults/99-custom-defaults.sh
#!/bin/sh

# Your UCI commands or other shell commands here
uci set network.wan.proto=pppoe
uci set network.wan.username='clan2101243254'
uci set network.wan.password='123456'

# wifi
uci set wireless.radio0.cell_density='0'
uci set wireless.default_radio0.ssid='24G'
uci set wireless.default_radio0.encryption='psk-mixed'
uci set wireless.default_radio0.key='students'
# uci set wireless.default_radio0.ocv='0'
uci set wireless.default_radio0.country='US'
uci set wireless.default_radio0.channel='1'
uci set wireless.default_radio0.htmode='HE40'
uci set wireless.radio0.htmode='HE40'
uci set wireless.radio0.country='US'

uci set wireless.radio1.cell_density='0'
uci set wireless.default_radio1.ssid='58G'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio1.key='students'
uci set wireless.default_radio1.ocv='0'
uci set wireless.default_radio1.country='US'
uci set wireless.default_radio1.channel='36'
uci set wireless.default_radio0.htmode='HE160'
uci set wireless.radio1.htmode='HE160'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.country='US'

uci commit network
/etc/init.d/network restart

# Remove this script after execution (optional but recommended)
rm -f /etc/uci-defaults/99-custom-defaults.sh
