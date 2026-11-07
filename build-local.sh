#!/usr/bin/env bash
# 本地编译脚本 —— 与 .github/workflows/build-firmware.yml 的步骤逐条对应
#
# 用法：
#   ./build-local.sh            从当前断点跑到出固件（每步成功打标记，可反复重跑）
#   ./build-local.sh setup      只跑某一步
#   ./build-local.sh clean      清掉所有标记（不清 build_dir）
#   ./build-local.sh distclean  彻底重来（删 build_dir/staging_dir/bin/.config）
#
# 与 CI 的差异（都是本地才需要处理的）：
#   - 不走 actions/cache，直接用本机 ccache + 持久 build_dir，天然增量
#   - nproc=8，内存 24G，不需要腾磁盘
#   - 每步落一个标记文件，失败后从失败那步重跑，不用从头再来

set -euo pipefail
cd "$(dirname "$0")"

STATE=.build-state
mkdir -p "$STATE" logs
export PATH="/usr/lib/ccache:$PATH"
export CCACHE_DIR="$HOME/.ccache"
export CCACHE_COMPRESS=1
export GIT_TERMINAL_PROMPT=0
JOBS="${JOBS:-$(nproc)}"
VANTAGE_SHA=9feb1e0d3be8a16bb22a3fc2f62b546676659d7d

log() { echo "[$(date +%H:%M:%S)] $*"; }
mark() { touch "$STATE/$1"; }
has() { [ -f "$STATE/$1" ]; }
need() { has "$1" || {
  log "前置步 $1 未完成"
  exit 1
}; }

# 把 make 的输出全部落盘，屏幕只留摘要 —— V=s 的几十 MB 输出会撑爆
# 后台任务的 20MB 输出上限，进程被直接杀掉（第一轮 toolchain 编到一半就没了）
# 网络类命令的重试：feeds 的 git pull 会偶发
# "gnutls_handshake() failed: The TLS connection was non-properly terminated"，
# 一次瞬断不该毁掉整轮编译
retry() {
  local n="$1"
  shift
  local i=1
  while [ "$i" -le "$n" ]; do
    if "$@"; then return 0; fi
    echo "  第 $i/$n 次失败，5 秒后重试"
    i=$((i + 1))
    [ "$i" -le "$n" ] && sleep 5
  done
  return 1
}

run_logged() {
  local logf="$1"
  shift
  local rc=0
  "$@" >"$logf" 2>&1 || rc=$?
  local nlines
  nlines=$(wc -l <"$logf")
  if [ "$rc" -ne 0 ]; then
    echo "  失败（退出码 $rc），日志 $logf 共 $nlines 行，末尾 30 行："
    tail -30 "$logf" | cut -c1-200
  else
    echo "  完成，日志 $logf 共 $nlines 行"
  fi
  return "$rc"
}

# ---------------------------------------------------------------- 1. setup
stage_setup() {
  log "== setup：执行位 / 换行 / off64_t / Vantage =="

  grep -v '^#' configs/exec-bits.txt | grep -v '^$' >"$STATE/exec-bits.txt"
  log "执行位清单 $(wc -l <"$STATE/exec-bits.txt") 条"
  xargs -a "$STATE/exec-bits.txt" -r chmod +x 2>/dev/null || true
  miss=0
  while IFS= read -r f; do
    if [ -e "$f" ] && [ ! -x "$f" ]; then
      echo "  仍缺执行位: $f"
      miss=$((miss + 1))
    fi
  done <"$STATE/exec-bits.txt"
  [ "$miss" -eq 0 ] || {
    echo "缺执行位 $miss 个"
    exit 1
  }
  log "执行位 OK"

  sh configs/normalize-lineendings.sh

  grep -q '_LARGEFILE64_SOURCE' toolchain/binutils/Makefile 2>/dev/null ||
    echo 'HOST_CFLAGS += -D_LARGEFILE64_SOURCE' >>toolchain/binutils/Makefile
  log "off64_t OK"

  if [ ! -d package/luci-theme-vantage ] || [ ! -d package/luci-app-vantage ]; then
    log "拉取 Vantage @ $VANTAGE_SHA"
    rm -rf /tmp/vantage
    git init -q /tmp/vantage
    git -C /tmp/vantage remote add origin https://github.com/anothaDev/luci-theme-vantage.git
    git -C /tmp/vantage fetch -q --depth 1 origin "$VANTAGE_SHA"
    git -C /tmp/vantage checkout -q FETCH_HEAD
    cp -r /tmp/vantage/luci-theme-vantage package/
    cp -r /tmp/vantage/luci-app-vantage package/
  fi
  test -d package/luci-theme-vantage
  test -d package/luci-app-vantage
  log "Vantage 两个包就位"

  mark setup
}

# --------------------------------------------------------------- 2. config
stage_config() {
  log "== config：生成 .config + 包清单校验 + 内置配置 =="

  grep -q 'ipaddr:-"192.168.6.1"' package/base-files/files/bin/config_generate || {
    echo '默认 LAN IP 不是 192.168.6.1'
    exit 1
  }

  cp defconfig/mt7981-ax3000.config .config
  # 一次编译出 TR3000 的三个硬件变体（依赖 CONFIG_TARGET_MULTI_PROFILE=y
  # + CONFIG_TARGET_PER_DEVICE_ROOTFS=y，两者已写在 defconfig 开头）：
  #   cudy_tr3000-v1        64 MiB  原厂 uboot（R47）
  #   cudy_tr3000-v1-ubootmod 112 MiB ubootmod（R47）← 当前在用的
  #   cudy_tr3000-v1-256mb  230 MiB 256MB 硬件版（R103）
  for d in cudy_tr3000-v1 cudy_tr3000-v1-ubootmod cudy_tr3000-v1-256mb; do
    echo "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${d}=y" >>.config
  done

  # 🚨 必须删旧 metadata：defconfig 改过（新增包/设备/依赖）之后，tmp 里的
  # .config-*.in 还是上一轮的符号表，新符号 kconfig 不认识 → 它会认为
  # 「需要人工确认」并调 scripts/config/mconf，后台无终端就挂死。
  # 实测 2026-11-06 就这样卡了 17 分钟、进程在但 CPU 0%。
  rm -f tmp/.config-package.in tmp/.config-feeds.in tmp/.config-target.in

  # 🚨 追加符号之后必须让 kconfig 重新解析一次，否则 .config 与内部符号表
  # 不一致，进入 kernel 阶段时 make 会去调 menuconfig（同上，挂死）。
  # 自愈循环：跑 defconfig → 检查必需符号 → 缺的补回 → 再跑，最多三轮。
  req="CONFIG_PACKAGE_adblock-fast"
  req="$req CONFIG_PACKAGE_luci-app-adblock-fast"
  req="$req CONFIG_PACKAGE_luci-theme-argon"
  req="$req CONFIG_PACKAGE_luci-theme-vantage"
  req="$req CONFIG_PACKAGE_luci-app-vantage"
  req="$req CONFIG_PACKAGE_kmod-tcp-bbr"
  req="$req CONFIG_PACKAGE_libwebsockets-full"
  req="$req CONFIG_PACKAGE_luci-theme-aurora"
  req="$req CONFIG_PACKAGE_luci-app-aurora-config"
  req="$req CONFIG_PACKAGE_luci-app-theme-switch"
  req="$req CONFIG_PACKAGE_luci-app-turboacc-mtk"
  req="$req CONFIG_PACKAGE_luci-i18n-turboacc-mtk-zh-cn"
  req="$req CONFIG_PACKAGE_kmod-bonding"
  req="$req CONFIG_PACKAGE_kmod-tls"
  req="$req CONFIG_PACKAGE_kmod-netlink-diag"
  req="$req CONFIG_PACKAGE_bash"
  req="$req CONFIG_PACKAGE_ip-full"
  req="$req CONFIG_PACKAGE_tcpdump"
  req="$req CONFIG_PACKAGE_tcping"
  req="$req CONFIG_PACKAGE_unzip"
  req="$req CONFIG_PACKAGE_mkf2fs"
  req="$req CONFIG_PACKAGE_f2fsck"
  req="$req CONFIG_PACKAGE_libf2fs"
  req="$req CONFIG_PACKAGE_kmod-usb-net-qmi-wwan"
  req="$req CONFIG_PACKAGE_kmod-usb-wdm"

  for attempt in 1 2 3; do
    make defconfig </dev/null >logs/defconfig.log 2>&1 || {
      echo "make defconfig 失败："
      tail -20 logs/defconfig.log | cut -c1-200
      exit 1
    }
    miss=0
    for s in $req; do
      if ! grep -q "^${s}=y" .config; then
        # 符号已在文件里（=m 或 is not set）就用 sed 就地改，不新增行，
        # 保持 .config 结构不变；完全没出现过的才追加到末尾。
        if grep -q "^# ${s} is not set" .config; then
          sed -i "s|^# ${s} is not set|${s}=y|" .config
        elif grep -q "^${s}=m" .config; then
          sed -i "s|^${s}=m|${s}=y|" .config
        else
          echo "${s}=y" >>.config
        fi
        echo "  第 $attempt 轮补回: $s"
        miss=$((miss + 1))
      fi
    done
    echo "第 $attempt 轮解析完成，补回 $miss 个符号"
    [ "$miss" -eq 0 ] && break
    if [ "$attempt" -eq 3 ]; then
      echo "三轮仍无法收敛："
      for s in $req; do grep -q "^${s}=y" .config || echo "  缺 $s"; done
      exit 1
    fi
  done

  # 🚨 收尾再跑一次 defconfig，确保 .config 是 kconfig 解析后的最终状态。
  # 之后不再追加任何符号——追加就会重新制造不一致，kernel 阶段又去开 menuconfig。
  make defconfig </dev/null >logs/defconfig-final.log 2>&1 || {
    echo "收尾 defconfig 失败"
    tail -20 logs/defconfig-final.log | cut -c1-200
    exit 1
  }
  final_miss=0
  for s in $req; do
    grep -q "^${s}=y" .config || {
      echo "  ⚠️ 收尾后丢失: $s"
      final_miss=$((final_miss + 1))
    }
  done
  [ "$final_miss" -eq 0 ] || {
    echo "收尾后仍有 $final_miss 个符号丢失，拒绝继续（继续会编出缺包的固件）"
    exit 1
  }
  log "OK  .config 已收敛（${#req} 项必需符号全部 =y）"

  fail=0
  for s in CONFIG_PACKAGE_adblock-fast \
    CONFIG_PACKAGE_luci-app-adblock-fast \
    CONFIG_PACKAGE_luci-theme-argon \
    CONFIG_PACKAGE_luci-theme-vantage \
    CONFIG_PACKAGE_luci-app-vantage \
    CONFIG_PACKAGE_kmod-tcp-bbr; do
    grep -q "^${s}=y" .config && echo "  OK   $s" || {
      echo "  MISS $s"
      fail=1
    }
  done
  for s in luci-app-openclash adguardhome luci-app-adguardhome \
    luci-app-upnp miniupnpd-nftables luci-app-homeproxy \
    mihomo dns2socks chinadns-ng ipt2socks microsocks; do
    grep -q "^CONFIG_PACKAGE_${s}=y" .config && {
      echo "  BAD  $s"
      fail=1
    } || echo "  OK   $s"
  done
  [ "$fail" -eq 0 ] || {
    echo "包清单校验失败"
    exit 1
  }

  mkdir -p files/etc/uci-defaults files/etc/opkg
  cp configs/tr3000-sysctl.conf files/etc/sysctl.conf
  cp configs/opkg-arch.conf files/etc/opkg/arch.conf
  cp configs/99_luci-theme-default files/etc/uci-defaults/99_luci-theme-default
  cp configs/99_opkg-no-signature files/etc/uci-defaults/99_opkg-no-signature
  chmod 755 files/etc/uci-defaults/99_*

  grep -q 'tcp_congestion_control=bbr' files/etc/sysctl.conf || {
    echo 'sysctl 未设置 bbr'
    exit 1
  }

  mark config
}

# ---------------------------------------------------------------- 3. feeds
stage_feeds() {
  need setup
  need config
  log "== feeds：更新与安装 =="
  retry 3 ./scripts/feeds update -a >logs/feeds-update.log 2>&1 || {
    echo 'feeds update 连续 3 次失败，末尾 20 行：'
    tail -20 logs/feeds-update.log | cut -c1-200
    exit 1
  }
  # 第三方 feeds 固定到 configs/feeds-pins 里的 commit。
  # scripts/feeds 只能按分支 clone，所以在 update 之后单独 fetch 再 checkout。
  if [ -f configs/feeds-pins ]; then
    while read -r name sha; do
      case "$name" in \#*|"") continue ;; esac
      [ -d "feeds/$name" ] || { echo "  feeds/$name 不存在，跳过 pin"; continue; }
      if ! git -C "feeds/$name" fetch -q --depth 1 origin "$sha"; then
        echo "  pin 失败: feeds/$name $sha"; exit 1
      fi
      git -C "feeds/$name" checkout -q FETCH_HEAD
      log "  pin feeds/$name -> $(git -C feeds/$name rev-parse --short HEAD)"
    done <configs/feeds-pins
  fi

  retry 3 ./scripts/feeds install -a >logs/feeds-install.log 2>&1 || {
    echo 'feeds install 连续 3 次失败，末尾 20 行：'
    tail -20 logs/feeds-install.log | cut -c1-200
    exit 1
  }
  rm -rf feeds/kenzok8_small/luci-app-fchomo

  # feeds 装完后冒出大量新包符号，.config 就过期了。此时 OpenWrt 认为
  # 需要人工确认，会去调 menuconfig —— 后台没有终端，就永远卡在那里
  # （实测卡了 11 分钟，进程还在但 0% CPU）。这里显式跑一次非交互的
  # defconfig 把符号解析干净，顺便把 "changes choice state" 一并解决。
  # feeds 装完后必须用完整包元数据重新解析 .config。
  # 但 make defconfig 在这套 feeds 组合下不稳定：实测会把
  # adblock-fast / luci-app-adblock-fast / luci-theme-argon
  # 三个原本 =y 的包打成 is not set（符号存在、无 depends）。
  # 所以不指望一次跑对，改成"跑完检查、缺了补回、再跑"，最多三轮。
  log "feeds 已装完，重新解析 .config（带自愈）"
  req="CONFIG_PACKAGE_adblock-fast"
  req="$req CONFIG_PACKAGE_luci-app-adblock-fast"
  req="$req CONFIG_PACKAGE_luci-theme-argon"
  req="$req CONFIG_PACKAGE_luci-theme-vantage"
  req="$req CONFIG_PACKAGE_luci-app-vantage"
  req="$req CONFIG_PACKAGE_kmod-tcp-bbr"
  req="$req CONFIG_PACKAGE_libwebsockets-full"
  # 本次新增的包也纳入自愈：tcpdump/tcping 早就在 defconfig 里却从未进过固件，
  # 就是被 make defconfig 丢掉的，不纳入自愈会重蹈覆辙。
  req="$req CONFIG_PACKAGE_luci-theme-aurora"
  req="$req CONFIG_PACKAGE_luci-app-aurora-config"
  req="$req CONFIG_PACKAGE_luci-app-theme-switch"
  req="$req CONFIG_PACKAGE_luci-app-turboacc-mtk"
  req="$req CONFIG_PACKAGE_kmod-bonding"
  req="$req CONFIG_PACKAGE_kmod-netlink-diag"
  req="$req CONFIG_PACKAGE_bash"
  req="$req CONFIG_PACKAGE_ip-full"
  req="$req CONFIG_PACKAGE_tcpdump"
  req="$req CONFIG_PACKAGE_tcping"
  req="$req CONFIG_PACKAGE_unzip"
  req="$req CONFIG_PACKAGE_mkf2fs"
  req="$req CONFIG_PACKAGE_f2fsck"
  req="$req CONFIG_PACKAGE_libf2fs"
  req="$req CONFIG_PACKAGE_kmod-usb-net-qmi-wwan"
  req="$req CONFIG_PACKAGE_kmod-usb-wdm"
  # 三个设备变体也纳入自愈：make defconfig 同样可能把设备符号打成 is not set
  req="$req CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cudy_tr3000-v1"
  req="$req CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cudy_tr3000-v1-ubootmod"
  req="$req CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cudy_tr3000-v1-256mb"

  for attempt in 1 2 3; do
    make defconfig </dev/null >logs/defconfig.log 2>&1 || {
      echo "make defconfig 失败："
      tail -20 logs/defconfig.log | cut -c1-200
      exit 1
    }
    # 以 defconfig 为准自愈：feeds 装完后所有包符号才都存在，
    # 这一步能把 make defconfig 丢掉的 feeds 包（stubby / knot-dig /
    # ksmbd-server / dufs / ddns-scripts …）全部补回来。
    if [ -x scripts/heal-config.sh ] || [ -f scripts/heal-config.sh ]; then
      out=$(sh scripts/heal-config.sh defconfig/mt7981-ax3000.config .config)
      echo "$out" | sed -n "s/^HEALED=/  自愈补回 /p"
    fi
    miss=0
    for s in $req; do
      if ! grep -q "^${s}=y" .config; then
        echo "${s}=y" >>.config
        echo "  第 $attempt 轮补回: $s"
        miss=$((miss + 1))
      fi
    done
    echo "第 $attempt 轮解析完成，补回 $miss 个符号"
    [ "$miss" -eq 0 ] && break
    if [ "$attempt" -eq 3 ]; then
      echo "三轮仍无法收敛："
      for s in $req; do grep -q "^${s}=y" .config || echo "  缺 $s"; done
      exit 1
    fi
  done

  fail=0
  for s in $req; do
    grep -q "^${s}=y" .config || {
      echo "  复核缺 $s"
      fail=1
    }
  done
  for s in kmod-sprd_pcie kmod-pcie_mhi_fb kmod-qmi_wwan_f kmod-qmi_wwan_m kmod-qmi_wwan_q kmod-gobinet kmod-usb-net-rtl8152-vendor; do
    grep -q "^CONFIG_PACKAGE_${s}=m" .config && {
      echo "  $s 又被 ALL_KMODS 打开了"
      fail=1
    }
  done
  [ "$fail" -eq 0 ] || exit 1
  log "包清单复核通过"

  mark feeds
}

# ------------------------------------------------------------- 4. download
stage_download() {
  need feeds
  log "== download：预检 + 下载源码包（这一步最吃网络，失败可重跑续传）=="
  run_logged logs/prereq.log make prereq </dev/null || exit 1
  retry 2 run_logged logs/download.log make -j"$JOBS" download V=s </dev/null ||
    retry 2 run_logged logs/download.log make -j1 download V=s </dev/null
  mark download
}

# ---------------------------------------------------------------- 5. tools
stage_tools() {
  need download
  log "== tools：编主机工具 =="
  run_logged logs/tools.log make tools/compile -j"$JOBS" V=s </dev/null
  mark tools
}

# ------------------------------------------------------------ 6. toolchain
stage_toolchain() {
  need tools
  log "== toolchain：编交叉工具链 =="
  run_logged logs/toolchain.log make toolchain/compile -j"$JOBS" V=s </dev/null
  mark toolchain
}

# ---------------------------------------------------------------- 7. kprep
stage_kprep() {
  need toolchain
  log "== kprep：内核准备 + BBRv3 断言 =="
  mkdir -p /tmp/skipped-patches
  ok=0
  for round in 1 2 3 4 5; do
    echo "=== 内核准备第 $round 轮 ==="
    if make target/linux/prepare -j"$JOBS" V=s >logs/kprep.log 2>&1; then
      ok=1
      break
    fi
    if ! grep -qE 'Patch failed!|out of [0-9]+ hunks? FAILED' logs/kprep.log; then
      echo '不是补丁问题，最后 60 行：'
      tail -60 logs/kprep.log
      exit 1
    fi
    P=$(grep -o '/[^ ]*\.patch' logs/kprep.log | tail -1)
    if [ -z "$P" ] || [ ! -f "$P" ]; then
      echo '补丁失败但取不到路径：'
      tail -60 logs/kprep.log
      exit 1
    fi
    echo "打不上，跳过：$P"
    mv "$P" "/tmp/skipped-patches/$(basename "$P")"
    rm -rf build_dir/target-*/linux-*/linux-6.6.* || true
  done
  [ "$ok" -eq 1 ] || {
    echo '5 轮仍有补丁打不上'
    tail -60 logs/kprep.log
    exit 1
  }
  echo "跳过的补丁数: $(find /tmp/skipped-patches -maxdepth 1 -type f | wc -l)"
  find /tmp/skipped-patches -maxdepth 1 -type f || true

  KDIR=$(find build_dir -maxdepth 4 -type d -path '*target-*/linux-*/linux-6.6.*' | head -1)
  echo "目标内核树: $KDIR"
  [ -n "$KDIR" ] || {
    echo '找不到目标内核树'
    exit 1
  }
  BBR="$KDIR/net/ipv4/tcp_bbr.c"
  [ -f "$BBR" ] || {
    echo "找不到 $BBR"
    exit 1
  }
  grep -q 'ecn_alpha' "$BBR" || {
    echo 'BBRv3 补丁没打上'
    exit 1
  }
  log "OK  tcp_bbr.c 是 v3 版本"
  mark kprep
}

# --------------------------------------------------------------- 8. kernel
stage_kernel() {
  need kprep
  log "== kernel：编内核与全部模块 =="
  run_logged logs/kernel.log make target/linux/compile -j"$JOBS" V=s </dev/null

  KDIR=$(find build_dir -maxdepth 4 -type d -path '*target-*/linux-*/linux-6.6.*' | head -1)
  KC="$KDIR/.config"
  if grep -qE '^CONFIG_TCP_CONG_BBR=[ym]' "$KC" 2>/dev/null; then
    log "OK  $(grep -E '^CONFIG_TCP_CONG_BBR=' "$KC")"
  else
    echo 'BBR 未启用'
    grep -E 'TCP_CONG_BBR|DEFAULT_TCP_CONG' "$KC" 2>/dev/null || true
    exit 1
  fi
  KO=$(find "$KDIR" -name 'tcp_bbr.ko' 2>/dev/null | head -1)
  if [ -n "$KO" ]; then
    log "OK  tcp_bbr.ko $(stat -c%s "$KO") 字节"
  elif grep -qE '^CONFIG_TCP_CONG_BBR=y' "$KC"; then
    log 'OK  BBR 内建进内核'
  else
    echo '找不到 tcp_bbr.ko 且非内建'
    exit 1
  fi
  mark kernel
}

# ------------------------------------------------------------- 9. firmware
stage_firmware() {
  need kernel
  log "== firmware：全量编译 =="
  free -h | head -2
  echo "jobs=$JOBS"
  df -h . | tail -1
  set -o pipefail
  if run_logged logs/firmware.log make -j"$JOBS" V=s </dev/null; then
    log 'OK  一次编过'
  else
    echo '--- 首次失败涉及的包 ---'
    grep -aE '^ERROR: package/' logs/firmware.log | tail -20 || true
    echo '--- 改用 -k 继续（只跳过失败的包）---'
    run_logged logs/firmware-k.log make -k -j"$JOBS" V=s || true
    echo '--- -k 之后仍失败的包 ---'
    grep -aE '^ERROR: package/' logs/firmware-k.log | tail -20 || true
  fi
  mark firmware
}

# --------------------------------------------------------------- 10. verify
stage_verify() {
  need firmware
  log "== verify：校验产物 =="
  MDIR=bin/targets/mediatek/filogic

  # 多设备变体：每个变体各自一个 .manifest，逐个校验。
  # 先前只取 head -1 检查，MULTI_PROFILE 下只能碰到三份中的一份，
  # 若某个变体丢包或根本没出镜像都不会被发现。
  MS=$(find "$MDIR" -maxdepth 1 -name '*.manifest' | sort)
  [ -n "$MS" ] || {
    echo '没有 manifest'
    exit 1
  }
  COUNT=$(printf '%s
' "$MS" | wc -l)
  echo "发现 $COUNT 个 manifest:"
  echo "$MS"

  for M in $MS; do
    grep -q '^adblock-fast ' "$M" || {
      echo "固件里没有 adblock-fast: $(basename "$M")"
      exit 1
    }
    for bad in luci-app-openclash adguardhome luci-app-homeproxy mihomo; do
      grep -qiE "^${bad} " "$M" && {
        echo "固件里混进了 $bad: $(basename "$M")"
        exit 1
      }
    done
  done
  log 'OK  所有变体的包清单符合预期'

  # 三个硬件变体的 sysupgrade 镜像必须都在
  for v in cudy_tr3000-v1 cudy_tr3000-v1-ubootmod cudy_tr3000-v1-256mb; do
    f=$(find "$MDIR" -maxdepth 1 -name "*${v}-squashfs-sysupgrade.bin" | head -1)
    [ -n "$f" ] || {
      echo "缺变体镜像: $v"
      ls "$MDIR"/*.bin 2>/dev/null | sed 's/^/  /'
      exit 1
    }
    log "  $(basename "$f")  $(du -h "$f" | cut -f1)"
  done
  log 'OK  三个变体镜像齐全'

  PKG="$MDIR/packages"
  [ -d "$PKG" ] || {
    echo '没有 packages 目录'
    exit 1
  }
  KMOD=$(find "$PKG" -maxdepth 1 -name 'kmod-*.ipk' | wc -l)
  ALL=$(find "$PKG" -maxdepth 1 -name '*.ipk' | wc -l)
  log "包仓库: kmod=$KMOD, 总计=$ALL"
  [ "$KMOD" -ge 300 ] || {
    echo "ALL_KMODS 似乎没生效（kmod 只有 $KMOD）"
    exit 1
  }
  log 'OK  ALL_KMODS 生效'
  mark verify
}

# -------------------------------------------------------------- 11. collect
stage_collect() {
  need verify
  log "== collect：打包产物到 dist/ =="
  mkdir -p dist
  MDIR=bin/targets/mediatek/filogic
  cp "$MDIR"/*cudy* dist/ || {
    echo '没有固件产物'
    exit 1
  }
  tar -C "$MDIR" -I 'zstd -9 -T0' -cf dist/packages.tar.zst packages
  ls -lh dist/
  log "固件 $(find dist -maxdepth 1 -name '*cudy*' | wc -l) 个 / 包仓库 $(find "$MDIR/packages" -name '*.ipk' | wc -l) 个 ipk"
  mark collect
}

# ------------------------------------------------------------------ runner
ALL="setup config feeds download tools toolchain kprep kernel firmware verify collect"

run_all() {
  for s in $ALL; do
    if has "$s"; then log "-- $s 已完成，跳过"; else "stage_$s"; fi
  done
  log "全部完成"
}

case "${1:-all}" in
all) run_all ;;
clean)
  rm -rf "$STATE"
  log "标记已清（build_dir 保留，下次从 setup 重跑但会增量）"
  ;;
distclean)
  rm -rf "$STATE" build_dir staging_dir bin tmp .config
  log "已彻底清理"
  ;;
setup | config | feeds | download | tools | toolchain | kprep | kernel | firmware | verify | collect)
  "stage_$1"
  ;;
*)
  echo "未知步骤: $1"
  echo "可用: all clean distclean $ALL"
  exit 1
  ;;
esac
