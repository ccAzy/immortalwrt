#!/bin/bash
# TR3000 aarch64 预置 OpenClash 内核 + GeoIP + Mihomo
set -e
echo "预置 Clash 内核 (aarch64)"
mkdir -p files/etc/openclash/core
CORE="files/etc/openclash/core"
GEO="files/etc/openclash"

CLASH_DEV_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz"
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
MIHOMO_BASE="https://github.com/MetaCubeX/mihomo/releases/latest/download"

# 注意: clash dev/meta 来自 OpenClash 上游，未提供 SHA256 校验文件。
# 仅依赖 HTTPS 传输安全。若上游提供校验，应及时添加。
wget -qO- $CLASH_DEV_URL 2>/dev/null | tar xOvz > $CORE/clash || echo "WARN: clash dev download failed"
wget -qO- $CLASH_META_URL 2>/dev/null | tar xOvz > $CORE/clash_meta || echo "WARN: clash meta download failed"

# 下载最新 Mihomo stable 作为 clash_tun (新版本 OpenClash 使用)
MIHOMO_FILE="mihomo-linux-arm64.gz"
wget -qO /tmp/mihomo.gz "${MIHOMO_BASE}/${MIHOMO_FILE}" 2>/dev/null && {
  # 尝试下载并校验 SHA256
  wget -qO /tmp/mihomo.sha256 "${MIHOMO_BASE}/${MIHOMO_FILE}.sha256" 2>/dev/null && {
    EXPECTED=$(awk 'NR==1{print $1}' /tmp/mihomo.sha256)
    ACTUAL=$(sha256sum /tmp/mihomo.gz | awk '{print $1}')
    if [ "$EXPECTED" = "$ACTUAL" ]; then
      gunzip -c /tmp/mihomo.gz > $CORE/clash_tun 2>/dev/null && echo "  mihomo stable core (verified)" || { echo "WARN: mihomo gunzip failed"; rm -f $CORE/clash_tun; }
    else
      echo "WARN: mihomo sha256 mismatch, skipping"
    fi
    rm -f /tmp/mihomo.sha256
  } || {
    # 无校验文件时拒绝安装，不引入未验证二进制
    echo "WARN: no sha256 for mihomo, skipping (unverified binary rejected)"
  }
  rm -f /tmp/mihomo.gz
} || echo "WARN: mihomo stable download failed"

wget -q -O $GEO/GeoIP.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat 2>/dev/null || echo "WARN: geoip failed"
wget -q -O $GEO/GeoSite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat 2>/dev/null || echo "WARN: geosite failed"
chmod +x $CORE/clash* 2>/dev/null || true
echo "Clash kernels prepared"
