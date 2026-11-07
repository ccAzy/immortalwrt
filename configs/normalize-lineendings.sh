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
# 处理范围只限「文本型、且会被构建过程读取」的文件：
#   *.patch *.sh *.mk *.dts *.dtsi Kconfig
# 其余一律不碰。package/mtk 下的 *.dat / *.bin 是二进制，sed 会把它们
# 改坏；MTK 驱动自带的 *.txt/*.readme/*.h 是厂商原样，C 编译器也接受
# CRLF，不需要动。
#
# 检测不用 grep：MSYS / git-bash 的 grep 会按文本模式吞掉 CR，
# 本地测和 CI 测结果不一致。这里改用字节数对比：
#   tr -d '\r' 后的字节数 < 原字节数  =>  含 CR
# 这个方法在 Windows 和 Linux 上行为一致。

set -e

ROOT="${1:-.}"
WORK=$(mktemp -d)

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# 只处理 target/ 下的补丁与设备树：它们每次构建都要重新打/重新编。
# 不碰 package/ 与 toolchain/ 下的 .sh/.mk —— sed 会刷新 mtime，
# 那会让 staging_dir 里缓存好的工具链与主机工具判定为过期而全量重编
# （实测过一次：主机工具因此重编 931 个对象，白费 16 分钟）。
find "$ROOT/target" -type f \
	\( -name '*.patch' -o -name '*.dts' -o -name '*.dtsi' \
	-o -name 'Kconfig' \) \
	-print0 >"$WORK/all" 2>/dev/null || true

echo "纳入处理范围的文件: $(tr -cd '\0' <"$WORK/all" | wc -c)"

# 逐文件：含 CR 就就地删掉行尾 CR
: >"$WORK/before"
xargs -0 -r sh -c '
	work=$1; shift
	for f in "$@"; do
		size=$(wc -c < "$f")
		clean=$(tr -d "\r" < "$f" | wc -c)
		if [ "$size" -ne "$clean" ]; then
			printf "%s\n" "$f" >> "$work/before"
			sed -i "s/\r\$//" "$f"
		fi
	done
' _ "$WORK" <"$WORK/all"

echo "归一化前含 CR: $(wc -l <"$WORK/before")"

# 复查同一批文件
: >"$WORK/left"
xargs -0 -r sh -c '
	work=$1; shift
	for f in "$@"; do
		size=$(wc -c < "$f")
		clean=$(tr -d "\r" < "$f" | wc -c)
		if [ "$size" -ne "$clean" ]; then
			printf "%s\n" "$f" >> "$work/left"
		fi
	done
' _ "$WORK" <"$WORK/all"

after=$(wc -l <"$WORK/left")
echo "归一化后含 CR: $after"

if [ "$after" -ne 0 ]; then
	echo "以下文件仍有 CR，构建中止："
	head -20 "$WORK/left"
	exit 1
fi

echo "OK 补丁与脚本的换行已归一化为 LF"
