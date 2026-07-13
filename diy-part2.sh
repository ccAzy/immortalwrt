#!/bin/bash
# TR3000 定制: 默认IP + Argon主题
set -e
echo "diy-part2: 定制中..."

# 默认IP 192.168.6.1 (不上报失败)
if [ -f package/base-files/files/bin/config_generate ]; then
  sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate 2>/dev/null || true
  echo "  IP set to 192.168.6.1"
else
  echo "  WARN: config_generate not found, IP unchanged"
fi

# Argon主题 (网络失败不阻塞)
if git clone --depth=1 https://github.com/sbwml/luci-theme-argon.git /tmp/argon 2>/dev/null; then
  rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null
  cp -r /tmp/argon/luci-theme-argon feeds/luci/themes/ 2>/dev/null || true
  rm -rf /tmp/argon
  echo "  Argon theme updated"
else
  echo "  Argon theme skipped (network)"
fi

echo "diy-part2: done"
