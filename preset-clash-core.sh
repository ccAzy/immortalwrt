#!/bin/bash
# TR3000 aarch64 预置 OpenClash 内核 + GeoIP
set -e
echo "预置 Clash 内核 (aarch64)"
mkdir -p files/etc/openclash/core
CORE="files/etc/openclash/core"
GEO="files/etc/openclash"

CLASH_DEV_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz"
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"

wget -qO- $CLASH_DEV_URL 2>/dev/null | tar xOvz > $CORE/clash || echo "WARN: clash dev download failed"
wget -qO- $CLASH_META_URL 2>/dev/null | tar xOvz > $CORE/clash_meta || echo "WARN: clash meta download failed"
wget -qO- https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O $GEO/GeoIP.dat 2>/dev/null || echo "WARN: geoip failed"
wget -qO- https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O $GEO/GeoSite.dat 2>/dev/null || echo "WARN: geosite failed"
chmod +x $CORE/clash* 2>/dev/null || true
echo "Clash kernels prepared"
