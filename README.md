# ImmortalWrt for Cudy TR3000

基于 [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) 的自编译定制固件，面向 **Cudy TR3000 v1（MT7981 / Filogic 820）**。

与上游不同，**本仓库内含完整源码树**，可以直接编译，不需要再 clone 上游再打补丁。

---

## 硬件平台

| 项目 | 参数 |
| --- | --- |
| 设备 | Cudy TR3000 v1（112 MB NAND） |
| SoC | MediaTek MT7981（Filogic 820），双核 Cortex-A53 @1.3 GHz |
| 内存 | 496 MB |
| 无线 | MTK 闭源驱动 `mt_wifi`（mx1e），2.4G + 5G 双频 |
| 变体 | `cudy_tr3000-v1-ubootmod`（需已刷 ubootmod 版 U-Boot） |

## 核心特性

- **内核**：Linux 6.6.133 LTS（MTK 官方 SDK 基线，闭源驱动匹配度最好）
- **BBRv3**：真·BBRv3 内核补丁（v1 里没有的 ECN 感知、`bbr_ecn_cut`），不是名字叫 bbr 的 v1
- **WiFi 驱动**：MTK 闭源 `mt_wifi` + WARP v2 + WED 硬件加速
- **硬件 NAT**：HNAT / WHNAT，有线千兆线速转发，CPU 占用接近 0
- **广告过滤**：[adblock-fast](https://github.com/openwrt/packages/tree/master/net/adblock-fast)，规则量可达 25 万条级别
- **主题**：Argon（默认）+ Vantage（可选切换）
- **内网穿透**：Tailscale 可装（固件内不预置，避免无谓占用）

## 与上游的差异

### 新增

| 项目 | 说明 |
| --- | --- |
| **BBRv3 补丁** | `target/linux/generic/hack-6.6/602-net-tcp_bbr-bbrv3.patch`，移植自 CachyOS 6.6 系列（3352 行，改 15 个文件）。实测在 6.6.133 + OpenWrt 670/671/680 补丁链之后零失败应用 |
| **Vantage 主题** | 固定 commit `9feb1e0d`，只取 `luci-theme-vantage` + `luci-app-vantage` 两个包目录（不整仓库当 feed，避免 `dev/` `tests/` 污染索引） |
| **adblock-fast** | 替代 AdGuard Home：143 KB 无常驻进程，比 AGH 省 34 MB 闪存 + 40~60 MB 内存 |
| **构建流水线** | 30 步 GitHub Actions，含缓存种子、包清单校验、BBRv3 三段断言 |
| **本地构建脚本** | `build-local.sh`，11 阶段可断点续跑 |

### 移除

OpenClash、AdGuard Home、UPnP、HomeProxy、mihomo、dns2socks、chinadns-ng、ipt2socks、microsocks —— 本固件定位是**路由器本职功能**，不做代理盒子和 DNS 全家桶。

### 排除的 kmod

`ALL_KMODS=y` 会拉入上千个驱动，其中 7 个在 6.6 上编译失败（驱动源码写给老内核，API 已变）：

```
kmod-sprd_pcie / kmod-pcie_mhi_fb / kmod-qmi_wwan_f / kmod-qmi_wwan_m
kmod-qmi_wwan_q / kmod-gobinet            ← MTK 厂商 5G 模组驱动（iommu_map 签名变了）
kmod-usb-net-rtl8152-vendor               ← 外置 Realtek 2.5G 网卡（netif_rx 相关）
```

处理方式是在各自 Makefile 里加 `DEFAULT:=n`。**只在 defconfig 里写 `# ... is not set` 是无效的** —— `scripts/package-metadata.pl:316` 会给所有 kmod 生成 `default m if ALL_KMODS`，把显式关闭项顶回来；而包自己定义了 `DEFAULT` 就不再套用该默认值。

## 包构成

| 指标 | 数值 |
| --- | --- |
| defconfig 显式包 | 181 个 |
| 固件内实际包数 | 约 432 个（含依赖自动带入） |
| 固件体积 | ~22 MB（rootfs 压缩比约 4.6:1） |
| 包仓库（单独打包） | 1052 个 ipk，其中 1014 个 kmod |

包仓库与固件内核 ABI 严格匹配（`kernel (= 6.6.133~<配置哈希>)`），刷机后可自由安装，不会出现跨版本 kmod 依赖冲突。

## 默认配置

```
IP           192.168.6.1
用户         root
TCP 拥塞控制  bbr（BBRv3）
队列算法     fq_codel
conntrack    65536（hashsize 同步 65536，1:1 最优配比）
DNS 缓存     10000 条
```

## 构建

### 方式一：GitHub Actions（推荐）

推送 `padavanonly-24.10-6.6` 分支即自动触发。4 vCPU / 16 GB runner，缓存命中时约 45 分钟，冷启动约 3~5 小时。

产出：

```
immortalwrt-...-squashfs-sysupgrade.bin    刷机用
immortalwrt-...-initramfs-kernel.bin       救砖 / 临时启动
packages.tar.zst                           包仓库
```

### 方式二：本地构建

```bash
git clone --depth 1 -b padavanonly-24.10-6.6 \
  https://github.com/ccAzy/immortalwrt.git iw-build
cd iw-build

# 依赖（Debian/Ubuntu）
sudo apt install -y build-essential ecj fastjar file g++ gawk gettext \
  git java-propose-classpath libelf-dev libncurses-dev libssl-dev python3 \
  python3-pyelftools rsync swig time unzip wget zlib1g-dev zstd ccache

# 11 阶段构建，可断点续跑
./build-local.sh            # 全流程
./build-local.sh kernel     # 只跑某一步
./build-local.sh distclean  # 彻底重来
```

Windows 用户建议放 WSL2 的 ext4 里构建（`/mnt/c` 下 IO 会慢数倍），并给足内存（`CONFIG_ALL_KMODS=y` 时建议 ≥16 GB）。

### BBRv3 快速验证

```bash
cat /proc/sys/net/ipv4/tcp_congestion_control   # 应输出 bbr
lsmod | grep tcp_bbr                            # 应看到 tcp_bbr
strings /lib/modules/*/tcp_bbr.ko | grep bbr_ecn  # v3 独有符号
```

## 踩过的坑（重要）

这些是实际编译失败后才定位到的，记录在此避免重复：

**1. 执行位全丢**

本仓库在 Windows 上创建，git 索引里 289 个文件本应是 `100755` 却存成了 `100644`。构建前必须按 `configs/exec-bits.txt` 逐条 chmod —— 那份清单是拿 OpenWrt 上游 `mode=100755` 列表逐条比对出来的，不是按目录猜的。

**2. 补丁 CRLF 污染**

Windows 编辑过的 `.patch` 会带 CR，打进去之后把 CR 写进内核源码，导致后续补丁上下文失配。构建前需归一化 `target/` 下 `.patch` / `.dts` / `.dtsi` / `Kconfig`。

**3. feeds 装完必须重新 defconfig**

`feeds install` 之前写进 `.config` 的、来自 feeds 的符号（如 `libwebsockets-full`）会被 kconfig 当未知项丢弃。必须在 feeds 装完之后再跑一次 `make defconfig`，且要自愈循环补回被误关的包。

**4. ttyd 需要带 libuv 的 libwebsockets**

ttyd 1.7.3 的 `CMakeLists.txt:73` 硬性要求 `-DLWS_WITH_LIBUV=ON`，默认解析到的 `libwebsockets-openssl` 没有 libuv，配置阶段直接 FATAL。显式选 `libwebsockets-full`（它 `PROVIDES libwebsockets`）即可。

**5. MTK 的 `mtkhqos` 会覆盖 sysctl**

`/sbin/mtkhqos`（START=19）在 `/etc/init.d/sysctl`（START=11）之后运行，把 `rmem_max` / `wmem_max` 改回 ~1 MB。需要在 START=99 的服务里再应用一次。注意 sysctl 实际路径是 `/sbin/sysctl`，写成 `/usr/sbin/sysctl` 会静默失败（退出码 127）。

**6. 硬件加速不走 fw4**

本固件的 `fw4.uc` 里 `resolve_offload_devices()` 被上游改成直接 `return []`，所以 LuCI 里「路由/NAT 卸载」开关**完全无效**，`nf_flow_table_hw` 也根本没编进内核。MTK 走的是自己的 `mtkhnat` + WARP/WED 路径。验证硬件加速是否工作：

```bash
grep -c 'state=BIND' /sys/kernel/debug/hnat/all_entry   # >0 即在用
```

**7. 内核树定位会撞到工具链副本**

`find build_dir -name 'linux-6.6.*'` 会先命中 `build_dir/toolchain-*/linux-6.6.133`（工具链的头文件副本，没有 BBR 选项）。要用 `-path '*target-*/linux-*/linux-6.6.*'` 精确定位。

## 已知限制

- **RAM 偏小**：496 MB 在 `ALL_KMODS` + Tailscale + collectd 场景下会用到 200 MB+，不适合再叠 Docker（本机也无 KVM）
- **闪存偏小**：overlay 仅 75.7 MB，装大量包需外接 U 盘
- **镜像源不完整**：默认镜像源只同步基础包，`aria2` / `transmission` / `sqm-scripts` 等需另配官方源
- **客户端在 5.8G 频段发射效率低**：远距离建议 2.4G，或直接有线

## 致谢

- [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) —— 底层源码与 MTK 闭源驱动适配
- [CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches) —— BBRv3 补丁源
- [anothaDev/luci-theme-vantage](https://github.com/anothaDev/luci-theme-vantage) —— Vantage 主题
- [openwrt/packages](https://github.com/openwrt/packages) —— adblock-fast

## License

继承上游 ImmortalWrt 的授权协议。
