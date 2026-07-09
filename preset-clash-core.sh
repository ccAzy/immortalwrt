#!/bin/bash
# TR3000 aarch64 预置 OpenClash 内核 + GeoIP
echo "预置 Clash 内核 (aarch64)"
mkdir -p files/etc/openclash/core
CORE="files/etc/openclash/core"
GEO="files/etc/openclash"

CLASH_DEV_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz"
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

wget -qO- $CLASH_DEV_URL | tar xOvz > $CORE/clash
wget -qO- $CLASH_META_URL | tar xOvz > $CORE/clash_meta
wget -qO- $GEOIP_URL > $GEO/GeoIP.dat
wget -qO- $GEOSITE_URL > $GEO/GeoSite.dat
chmod +x $CORE/clash*

echo "Clash 内核预置完成"
