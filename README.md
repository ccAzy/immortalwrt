# Cudy TR3000 专属定制固件

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)，为 **Cudy TR3000 v1 (ubootmod)** 定制的固件。

## 特性

| 类别 | 内容 |
|------|------|
| **代理** | daed (XDP/eBPF 透明代理) |
| **加速** | TurboACC + MediaTek HNAT + Fullcone NAT + BBRv3 |
| **WiFi** | MT7981 驱动 + 硬件加速 |
| **NAS** | ksmbd SMB 共享 + F2FS/exFAT/ext4/NTFS 支持 |
| **工具** | bash / curl / tcpdump / tcping / htop / nano |
| **监控** | wrtbwmon / bandix 流量监控 |
| **DNS** | dnsmasq-full |
| **其他** | UPnP / TTYD / Conntrack / Argon + Aurora 双主题 |

## 内核

```
CONFIG_XDP_SOCKETS=y
CONFIG_XDP_SOCKETS_DIAG=y
CONFIG_NET_SCH_BPF=y
CONFIG_BPF_JIT_ALWAYS_ON=y
CONFIG_DEBUG_INFO_BTF=y
```

## 编译

GitHub Actions 自动编译，push 即触发。

## 下载

前往 [Actions](https://github.com/ccAzy/immortalwrt/actions) → 选最新的成功运行 → 下载 `tr3000-firmware` artifact。

## 刷入

LuCI → 系统 → 备份/升级 → 刷写固件 → **不保留配置**。

## 来源

合并自两个社区固件，取长补短：
- 恩山237大佬（内核 XDP + ksmbd + argon 主题）
- 旧大佬固件（bash/curl/UPnP/wrtbwmon/conntrack 等完整工具链）
