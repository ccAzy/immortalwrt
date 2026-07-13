# ImmortalWrt for Cudy TR3000

基于 [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) 的 Cudy TR3000 v1 定制固件，适用于 MT7981 (Filogic 820) 平台。

## 特性

- **内核**: Linux 6.6 LTS
- **WiFi 驱动**: MTK 闭源 mt_wifi (mx1e), WARP v2
- **硬件加速**: 有线 HNAT / 无线 WHNAT 全锥形 NAT
- **Turbo ACC**: SFE 快速转发 + BBR 拥塞控制
- **OpenClash**: 预置 clash / clash_meta / Mihomo 三内核
- **AdGuard Home**: 内置 DNS 去广告
- **文件共享**: ksmbd (SMB) + WSDD2 局域网发现
- **主题**: Argon + Aurora 双主题
- **其他工具**: DDNS, Wake-on-LAN, UPnP, iPerf3, Dufs 文件服务器

## 预置包

| 分类 | 包名 |
|---|---|
| 代理 | luci-app-openclash, dns2socks, chinadns-ng, ipt2socks, microsocks |
| DNS | adguardhome, luci-app-adguardhome |
| 文件 | luci-app-ksmbd, wsdd2, dufs, luci-app-dufs |
| 网络 | luci-app-ddns, ddns-scripts, luci-app-upnp, miniupnpd-nftables |
| 工具 | luci-app-wol, iperf3, mtr-json, tcping, conntrack, bandix |
| 主题 | luci-theme-argon, luci-app-argon-config, luci-theme-aurora |
| 系统 | coreutils, kmod-mtd-rw, zram-swap, zoneinfo-asia |

## 默认配置

- **IP**: `192.168.6.1`
- **用户**: `root`
- **TCP 拥塞控制**: BBR
- **conntrack 最大连接数**: 65536

## 快速构建

### 环境要求

Debian 11+ / Ubuntu 20.04+，AMD64，≥4GB RAM，≥25GB 磁盘。

```bash
sudo apt update -y
sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib \
  gettext git libncurses-dev libssl-dev rsync unzip zlib1g-dev file wget \
  python3 zstd
```

### 编译

```bash
# 克隆上游仓库（padavanonly 维护的 mt798x 6.6 内核分支）
git clone -b openwrt-24.10-6.6 --single-branch --filter=blob:none \
  https://github.com/padavanonly/immortalwrt-mt798x-6.6.git immortalwrt-mt798x-24.10
cd immortalwrt-mt798x-24.10

# 应用本仓库的定制配置
# 方式一: 使用本仓库的 defconfig（推荐本地构建）
cp /path/to/this/repo/defconfig/mt7981-ax3000.config .config

# 方式二: 手动添加 TR3000 设备和增强包
cat /path/to/this/repo/defconfig/mt7981-ax3000.config >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-v1-ubootmod=y" >> .config

# 添加第三方 feeds（预置包依赖）
echo "src-git kenzok8 https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default
echo "src-git kenzok8_small https://github.com/kenzok8/small.git;master" >> feeds.conf.default

# 编译
./scripts/feeds update -a && ./scripts/feeds install -a
make defconfig
make -j$(nproc) V=s
```

固件输出路径: `bin/targets/mediatek/filogic/`

### 预置 Clash 内核（可选）

```bash
bash preset-clash-core.sh
```

这会将 clash / clash_meta / Mihomo 内核和 GeoIP 数据库预置到固件中，刷机后 OpenClash 开箱即用。

## CI 自动构建

本仓库的 GitHub Actions 在每次 push 时自动构建 TR3000 固件：

- 基于上游 [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)
- 自动注入 TR3000 设备配置和增强包
- 产物上传为 Artifact 和 Release

## 刷机

1. 下载 `*-cudy_tr3000-v1-ubootmod-squashfs-sysupgrade.bin`
2. 通过 LuCI 系统→备份/升级，或使用 `sysupgrade -n` 命令
3. 首次启动后访问 `http://192.168.6.1`

## 致谢

- [OpenWrt](https://openwrt.org) — 基础固件项目
- [ImmortalWrt](https://github.com/immortalwrt) — 中国大陆优化分支
- [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) — MT798x 6.6 内核适配
- [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages) — 社区包源
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash) — Clash 客户端
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — Clash Meta 内核

## License

本项目基于 ImmortalWrt / OpenWrt，采用 [GPL-2.0-only](LICENSES/GPL-2.0) 许可证。
