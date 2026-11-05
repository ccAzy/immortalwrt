#!/bin/sh
# 把补丁/脚本从 CRLF 归一化成 LF。
#
# 背景：这个 fork 在 Windows 上提交过，部分 .patch 被存成 CRLF。
# 带 CR 的补丁打进内核源码时会把 CR 一起写进去，导致后续补丁的上下文
# 匹配失败。实测链条：
#   999-1716  79 行里 46 行含 CR  -> 打进去的 phy-c45.c 带 CR
#   999-1720  75 行里 38 行含 CR  -> 继续污染
#   999-1722  Hunk #4 FAILED at 1517  -> 内核编译中止
#
# 在 CI 的临时副本上跑，不影响仓库内容。

set -e

ROOT="${1:-.}"
CR=$(printf '\r')

count_cr() {
	grep -rlI -- "$CR" \
		"$ROOT/target" "$ROOT/package" "$ROOT/toolchain" 2>/dev/null | wc -l
}

echo "归一化前含 CR 的文件: $(count_cr)"

find "$ROOT/target" "$ROOT/package" "$ROOT/toolchain" -type f \
	\( -name '*.patch' -o -name '*.sh' -o -name '*.mk' \
	   -o -name '*.dts' -o -name '*.dtsi' -o -name 'Kconfig' \) \
	-exec sed -i "s/${CR}\$//" {} + 2>/dev/null || true

left=$(count_cr)
echo "归一化后含 CR 的文件: $left"

# 硬校验：还有 CR 就中止，避免再出现"补丁静默打偏"这种难查的失败
if [ "$left" -ne 0 ]; then
	echo "仍有 $left 个文件含 CR，构建中止"
	grep -rlI -- "$CR" \
		"$ROOT/target" "$ROOT/package" "$ROOT/toolchain" 2>/dev/null | head -20
	exit 1
fi

echo "OK 换行已归一化为 LF"
