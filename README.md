# Cudy TR3000 专属定制固件

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 源码编译，为 **Cudy TR3000 v1 (ubootmod)** 定制。

## 一键编译

```
Actions → Build TR3000 → Run workflow → 等 1.5~2h → Release 下载
```

首次全量编译，后续缓存命中 < 2 分钟。

## 预装包

| 类别 | 内容 |
|---|---|
| **代理** | OpenClash + dns2socks + chinadns-ng + ipt2socks |
| **去广告** | AdGuard Home |
| **加速** | BBR + Fullcone NAT + HNAT 硬件加速 + TCP Fastopen |
| **WiFi** | mtwifi 专有驱动 (HE160 待验证) |
| **NAS** | ksmbd SMB + wsdd2 + exFAT/NTFS/ext4 |
| **监控** | bandix 流量监控 |
| **网络** | iperf3 / mtr-json / tcpdump / tcping |
| **DDNS** | luci-app-ddns |
| **远程** | WOL 网络唤醒 |
| **工具** | bash / curl / htop / nano / wget-ssl |
| **界面** | Argon 主题 + Aurora 主题 |
| **其他** | UPnP / ttyd / conntrack |

## 自定义配置

刷机后自动生效（无需手动操作）：

| 配置 | 说明 |
|---|---|
| 默认 IP | 192.168.6.1 |
| sysctl | BBR + conntrack=65536 + keepalive=120s |
| 防火墙 | WAN REJECT + nat-fix 自启 |
| OpenClash 守护 | 每次重载后自动修复优化项 |
| AdGuard | safebrowsing 关 + overlay 持久化 |

## 产出格式

- `*ubootmod-squashfs-sysupgrade.itb` — ubootmod 分区
- `*v1-squashfs-sysupgrade.bin` — 原厂分区

## 相关项目

| 项目 | 说明 |
|---|---|
| [ImageBuilder](https://github.com/ccAzy/ImmortalWrt-ImageBuilder) | 快速打包（5min），但不能源码定制 |
| [U-Boot](https://github.com/ccAzy/bl-mt798x-dhcpd) | DHCP Web 救砖 |

## 更新日志

| 日期 | 内容 |
|---|---|
| 2026-07-10 | OpenClash+AdGuard+Fullcone+BBR自启+IPv6+DNS链路完整优化 |
| 2026-07-09 | 四层缓存+预编译toolchain+BBRv3种子加入 |
| 2026-07-08 | passwall→OpenClash 替换, 增强包加入 |
