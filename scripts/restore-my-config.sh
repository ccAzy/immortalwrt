#!/bin/sh
# ============================================================
# restore-my-config.sh —— 刷完固件后恢复「个人配置」
#
# 固件里已经带了所有技术调优（sysctl / DoT / 访客网络骨架 /
# DNS 缓存 / 主题切换）。这个脚本只负责补「不该进固件的东西」：
# WiFi 密码、主机名、Tailscale、广告拦截规则。
#
# 用法（在电脑上，连得上路由器时）：
#   ssh root@192.168.6.1 'sh -s' < restore-my-config.sh
#
# 或者传到路由器再跑：
#   scp restore-my-config.sh root@192.168.6.1:/tmp/
#   ssh root@192.168.6.1 'sh /tmp/restore-my-config.sh'
#
# 幂等：可重复执行，改完立刻生效。
# ============================================================

set -u

WIFI_24_SSID='66'
WIFI_5G_SSID='88'
WIFI_KEY='cjq604240'
GUEST_SSID='7788'
GUEST_KEY='asdfghjkl'
HOSTNAME='Cudytr3000'

echo '══ 1. 主机名 ══'
uci set system.@system[0].hostname="$HOSTNAME"
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
echo "  → $HOSTNAME"

echo ''
echo '══ 2. WiFi ══'
# 找 2.4G / 5G 射频名（不同机型叫法不同）
DEV24=""; DEV5G=""
for d in $(uci show wireless | sed -n 's/^wireless\.\([^.]*\)=wifi-device$/\1/p'); do
    case "$(uci -q get wireless.$d.band)" in
        2g) DEV24="$d" ;;
        5g) DEV5G="$d" ;;
    esac
done

# 主 WiFi（默认 iface 挂在 lan 上）
for d in "$DEV24" "$DEV5G"; do
    [ -z "$d" ] && continue
    iface=$(uci show wireless | sed -n "s/^wireless\.\([^.]*\)=wifi-iface$/\1/p" | while read -r x; do
        [ "$(uci -q get wireless.$x.device)" = "$d" ] && [ "$(uci -q get wireless.$x.network)" = "lan" ] && echo "$x"
    done | head -1)
    [ -z "$iface" ] && continue
    if [ "$d" = "$DEV24" ]; then
        uci set wireless.$iface.ssid="$WIFI_24_SSID"
        uci set wireless.$d.channel='11'
        uci set wireless.$d.htmode='HE40'
    else
        uci set wireless.$iface.ssid="$WIFI_5G_SSID"
        uci set wireless.$d.channel='36'
        uci set wireless.$d.htmode='HE80'
    fi
    uci set wireless.$iface.encryption='sae-mixed'
    uci set wireless.$iface.key="$WIFI_KEY"
    uci set wireless.$iface.hidden='1'
    echo "  → $iface on $d"
done

# 访客 SSID（骨架由固件里的 95_guest-network 建好，这里只改名字和密码）
if [ -n "$(uci -q get wireless.guest_5g)" ]; then
    uci set wireless.guest_5g.ssid="$GUEST_SSID"
    uci set wireless.guest_5g.key="$GUEST_KEY"
    uci set wireless.guest_5g.hidden='1'
    uci set wireless.guest_5g.isolate='1'
    echo "  → guest_5g = $GUEST_SSID"
fi

uci commit wireless

echo ''
echo '══ 3. 广告拦截规则 ══'
# 1.3MB 源文件不进固件（可重新下载/传），这里只负责生成 hosts 并挂上
SRC='/etc/adblock-fast/hagezi-multipro.txt'
OUT='/etc/dnsmasq.d/adblock-hosts.conf'
if [ -f "$SRC" ]; then
    mkdir -p /etc/dnsmasq.d
    grep -vE '^\s*#|^\s*$' "$SRC" | awk '{print "0.0.0.0 " $1}' > "$OUT"
    echo "  生成 $OUT ($(wc -l < "$OUT") 条)"
    uci -q delete dhcp.@dnsmasq[0].addnhosts
    uci add_list dhcp.@dnsmasq[0].addnhosts="$OUT"
    uci commit dhcp
else
    echo "  跳过：$SRC 不存在（先传规则文件，或用 LuCI 里的 adblock-fast）"
fi

echo ''
echo '══ 4. Tailscale（需手动登录）══'
if opkg list-installed 2>/dev/null | grep -q '^tailscale '; then
    /etc/init.d/tailscale enable >/dev/null 2>&1
    /etc/init.d/tailscale start >/dev/null 2>&1
    sleep 3
    if tailscale status 2>/dev/null | grep -q 'Logged out\|^#'; then
        echo '  需要登录，运行下面这条并打开给出的链接：'
        echo "    tailscale up --hostname=tr3000 --accept-routes=false --advertise-routes=192.168.6.0/24 --accept-dns=false"
    else
        echo "  已登录: $(tailscale ip -4 2>/dev/null)"
    fi
else
    echo '  未安装。装：opkg update && opkg install tailscale'
fi

echo ''
echo '══ 5. 应用 ══'
/etc/init.d/dnsmasq restart >/dev/null 2>&1
wifi reload >/dev/null 2>&1 &
sleep 2
uci commit
echo '  完成。'

echo ''
echo '══ 验证 ══'
echo "  主机名: $(cat /proc/sys/kernel/hostname 2>/dev/null)"
echo "  BBR:    $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
echo "  DNS:    $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null) conntrack"
echo "  DoT:    $(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null || echo 未切换)"
echo "  访客:   $(uci -q get wireless.guest_5g.ssid 2>/dev/null || echo 未配置)"
exit 0
