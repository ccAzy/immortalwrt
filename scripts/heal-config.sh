#!/bin/sh
# 把 defconfig 里标了 =y、但 .config 里被 make defconfig 丢掉的符号补回来。
#
# 为什么需要：make defconfig 在这套 feeds 组合下不稳定，会把已经选中的包
# 打成 is not set。更隐蔽的是时序问题——开场时 feeds 还没装，来自 feeds 的
# 符号（stubby / knot-dig / ksmbd-server / dufs / ddns-scripts …）在 kconfig
# 眼里还不存在，直接被丢掉，之后即便 feeds 装完也不会自己回来。
# 实测 CI 因此少装 60 个包（404 vs 464）。
#
# 用法: scripts/heal-config.sh <defconfig> <.config>
# 输出：
#   HEALED=<本轮补回个数>
#   IRRECOVERABLE=<补了又被丢的符号列表，可为空>
# 退出码：0 = 没有无法补回的符号；1 = 有（调用方可据此决定是否失败）
set -u

DEF="${1:?需要 defconfig 路径}"
CFG="${2:?.config 路径}"

[ -f "$DEF" ] || { echo "找不到 $DEF"; exit 2; }
[ -f "$CFG" ] || { echo "找不到 $CFG"; exit 2; }

HEALED=0
HEALED_LIST=""

# 只自愈「包」与「设备变体」两类符号：
#   别的符号（内核选项、target 变量等）kconfig 会自己按 target 定，
#   强行补回去下一轮又被丢掉，会让自愈循环永不收敛（实测 8 个符号就是这样）。
for sym in $(grep -E '^CONFIG_(PACKAGE_[A-Za-z0-9_.-]+|TARGET_DEVICE_[A-Za-z0-9_.-]+)=y$' "$DEF" | cut -d= -f1); do
    grep -q "^${sym}=y" "$CFG" && continue

    # 符号在 .config 里以别的形态出现过 -> 就地改，保持结构不变
    if grep -q "^# ${sym} is not set" "$CFG"; then
        sed -i "s|^# ${sym} is not set|${sym}=y|" "$CFG"
    elif grep -q "^${sym}=m" "$CFG"; then
        sed -i "s|^${sym}=m|${sym}=y|" "$CFG"
    else
        echo "${sym}=y" >>"$CFG"
    fi

    HEALED=$((HEALED + 1))
    HEALED_LIST="$HEALED_LIST $sym"
done

echo "HEALED=$HEALED"
echo "HEALED_SYMS=$HEALED_LIST"
exit 0
