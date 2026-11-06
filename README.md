# ImmortalWrt for Cudy TR3000

基于 [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) 的 Cudy TR3000 v1 定制固件，适用于 MT7981 (Filogic 820) 平台。

## 特性

- **内核**：Linux 6.6 LTS，含 BBRv3 补丁（`target/linux/generic/hack-6.6/602-net-tcp_bbr-bbrv3.patch`）
- **WiFi 驱动**：MTK 闭源 `mt_wifi`(mx1e) + WARP v2；双频 WE40 / HE80，均隐藏 SSID
- **硬件加速**：有线 HNAT / 无线 WHNAT 全锥形 NAT（`luci-app-turboacc-mtk`，需 `kmod-tls=y` 才会进固件）
- **TCP 调优**：BBRv3 + `fq_codel`，conntrack 上限 65536，socket 缓冲区 6MB（`configs/tr3000-sysctl.conf`）
- **DNS**：`stubby` 提供 DNS-over-TLS（阿里 223.5.5.5 / 223.6.6.6 + 腾讯 `dot.pub`），`dnsmasq` 8k 缓存、不缓存否定应答
- **广告过滤**：`adblock-fast`（DNSMASQ 模式，A/AAAA 双族一并拦截）
- **文件共享**：ksmbd (SMB) + wsdd2 局域网发现 + dufs（Web 文件服务器）
- **主题**：Argon / Aurora / Vantage 三套 + 一键切换（系统 → 主题切换）
- **诊断工具**：`timeout`（busybox applet）、`kdig`、`tcping`、`tcpdump`、`iperf3`、`mtr`、`conntrack`

## 预置包

| 分类 | 包 |
| --- | --- |
| 加速 | luci-app-turboacc-mtk、tc-tiny、ip-full、ethtool |
| DNS / 过滤 | stubby、getdns、adblock-fast、luci-app-adblock-fast |
| 文件 | luci-app-ksmbd、wsdd2、dufs、luci-app-dufs |
| 网络 | luci-app-ddns、luci-app-wol、luci-app-eqos-mtk、luci-app-wrtbwmon、luci-app-mtwifi-cfg |
| 工具 | htop、nano、bash、coreutils、unzip、tcping、conntrack、iperf3、mtr-json、netcat、knot-dig |
| 主题 | luci-theme-argon、luci-app-argon-config、luci-theme-aurora、luci-app-aurora-config、luci-theme-vantage、luci-app-vantage、luci-app-theme-switch |
| 系统 | zram-swap、kmod-mtd-rw、zoneinfo-asia、luci-app-ttyd |

## 默认配置

- **IP**：`192.168.6.1`（源码层已改死 `config_generate`，不是刷机脚本改的）
- **用户**：`root`，LAN 侧 192.168.6.1，WAN 走 DHCP（光猫之后）
- **DNS**：首次启动由 `96_stubby-setup` 拉起 stubby，`97_dnsmasq-tuning` 调缓存；`rc.local` 里有两阶段兜底（180 秒等不到 DoT 就退回运营商 DNS，不会断网）
- **访客网络**：`95_guest-network` 建 `192.168.7.0/24` + 客户端隔离
- **主题**：默认 Vantage（`99_luci-theme-default`）
- **opkg 签名**：默认关闭（`99_opkg-no-signature`，便于装社区包）

> 固件里**没有** OpenClash、AdGuard Home、luci-app-upnp、bandix —— 上一版 README 写错了。
> 代理客户端按需自己装（`opkg install luci-app-openclash` 或 Nikki）；广告过滤统一走 adblock-fast，不装 AdGuard Home。

## 快速构建

### 环境要求

Debian 11+ / Ubuntu 20.04+，AMD64，≥4GB RAM，≥25GB 磁盘。

```bash
sudo apt update -y
sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib \
  gettext git libncurses-dev libssl-dev rsync unzip zlib1g-dev file wget \
  python3 zstd ccache
```

### 编译

```bash
# 本仓库本身就是完整源码树（不再 clone 上游覆盖定制）
git clone https://github.com/ccAzy/immortalwrt.git
cd immortalwrt

# 第三方 feeds 已 pin 到固定 commit（feeds.conf.default），保证可复现
./scripts/feeds update -a && ./scripts/feeds install -a

cp defconfig/mt7981-ax3000.config .config
make defconfig
make -j$(nproc) V=s
```

固件输出：`bin/targets/mediatek/filogic/`

> ⚠️ `make defconfig` 在这套环境里**不稳定**：会把已经进固件的包或设备变体关掉。
> `build-local.sh` 与 CI 都带「自愈」步骤（跑完 `make defconfig` 后逐条检查关键包与三个变体，缺了就补回来再跑一遍）。
> **这些包不能手写进自愈列表**：`luci-i18n-*` 这类符号由 `luci.mk` 自动生成、不在 metadata 里，写进去会让自愈永不收敛。

### 本地增量编译

```bash
./build-local.sh              # 从断点跑到出固件（每步打标记，可反复重跑）
./build-local.sh setup       # 只跑某一步
./build-local.sh clean       # 清标记（不动 build_dir）
./build-local.sh distclean   # 彻底重来
```

## CI 自动构建

GitHub Actions（`ubuntu-22.04`，超时 360 分钟）：

- ccache + `dl` + `toolchain` + `build_dir` 四层缓存，缓存 key 由 `feeds.conf.default` + `defconfig` + 内核 config + BBRv3 补丁内容哈希决定
- 冷启动约 3~5 小时；缓存命中约 77~110 分钟（实测）
- 产物上传 Artifact 并附到 Release

## 刷机

1. 下载对应变体：`*-cudy_tr3000-v1-{,,ubootmod-,256mb-}squashfs-sysupgrade.bin`
2. LuCI 系统 → 备份/升级，或 `sysupgrade -n`
3. 首次启动后访问 `http://192.168.6.1`

## 致谢

- [OpenWrt](https://openwrt.org)
- [ImmortalWrt](https://github.com/immortalwrt)
- [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)
- [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages)
- 主题：[sbwml/luci-theme-argon](https://github.com/sbwml/luci-theme-argon)、[eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)、[anothaDev/luci-theme-vantage](https://github.com/anothaDev/luci-theme-vantage)

## License

GPL-2.0-only，见 [LICENSES/GPL-2.0](LICENSES/GPL-2.0)。
