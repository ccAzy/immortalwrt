#!/usr/bin/env python3
"""本地/CI 预检：把 workflow 里每个 run: 块的 shell 语法先验一遍。

为什么需要：workflow 的 run 块是字符串，YAML 校验通过不代表 shell 语法
正确。实测踩过两次——改一个 for 循环时把循环体删掉了，YAML 合法、CI 照
跑，9~30 分钟后才在 build 步骤报 `syntax error near unexpected token 'done'`。
这个脚本几秒钟就能把同类问题挡在前面。

用法：
    python3 scripts/check-workflow-shell.py .github/workflows/build-firmware.yml
环境变量：
    BASH_BIN  指定 bash 可执行文件（Windows 上要写 git-bash 的绝对路径，
              因为 PATH 里的 bash 可能是 WSL 的，认不了 C:/ 路径）
"""
import os
import re
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("缺少 PyYAML：pip install pyyaml（CI 上 apt install python3-yaml）\n")
    sys.exit(2)

BASH = os.environ.get("BASH_BIN", "bash")
# 模板表达式在 shell 里没有意义，替换成无害字面量只看语法
STUB = "cudy_tr3000-v1-ubootmod"


def check(path):
    doc = yaml.safe_load(open(path, encoding="utf-8"))
    bad = 0
    checked = 0
    for job_name, job in doc.get("jobs", {}).items():
        for idx, step in enumerate(job.get("steps", [])):
            script = step.get("run")
            if not script:
                continue
            checked += 1
            name = step.get("name", "step#%d" % idx)
            body = re.sub(r"\$\{\{[^}]*\}\}", STUB, script)
            with tempfile.NamedTemporaryFile(
                "w", suffix=".sh", delete=False, encoding="utf-8"
            ) as fh:
                fh.write(body)
                tmp = fh.name
            try:
                r = subprocess.run(
                    [BASH, "-n", tmp], capture_output=True, text=True
                )
            finally:
                os.unlink(tmp)
            if r.returncode != 0:
                bad += 1
                print("[语法错] %s / %s" % (job_name, name))
                print(r.stderr.strip()[:500])
    if bad == 0:
        print("OK  %d 个 run 块 shell 语法全部通过" % checked)
        return 0
    print("共 %d / %d 个 run 块有语法错" % (bad, checked))
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("用法: check-workflow-shell.py <workflow.yml>\n")
        sys.exit(2)
    sys.exit(check(sys.argv[1]))
