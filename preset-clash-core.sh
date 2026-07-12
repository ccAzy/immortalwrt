#!/bin/bash
# TR3000 aarch64 预置 OpenClash 内核 + GeoIP + Mihomo
set -e
echo "预置 Clash 内核 (aarch64)"
mkdir -p files/etc/openclash/core
CORE="files/etc/openclash/core"
GEO="files/etc/openclash"

CLASH_DEV_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz"
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"

wget -qO- $CLASH_DEV_URL 2>/dev/null | tar xOvz > $CORE/clash || echo "WARN: clash dev download failed"
wget -qO- $CLASH_META_URL 2>/dev/null | tar xOvz > $CORE/clash_meta || echo "WARN: clash meta download failed"
# 额外下载最新 Mihomo 作为 clash_tun (新版本 OpenClash 使用)
wget -qO- https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-arm64-alpha.gz -O /tmp/mihomo.gz 2>/dev/null && {
  gunzip -c /tmp/mihomo.gz > $CORE/clash_tun 2>/dev/null && echo "  mihomo alpha core downloaded" || echo "WARN: mihomo gunzip failed"
  rm -f /tmp/mihomo.gz
} || echo "WARN: mihomo alpha download failed"

wget -qO- https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O $GEO/GeoIP.dat 2>/dev/null || echo "WARN: geoip failed"
wget -qO- https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O $GEO/GeoSite.dat 2>/dev/null || echo "WARN: geosite failed"
chmod +x $CORE/clash* 2>/dev/null || true
echo "Clash kernels prepared"
