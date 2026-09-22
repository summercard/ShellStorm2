# -*- coding: utf-8 -*-
"""给 godot-verification-suite-triage 加 D 类：自己补丁把注释前缀丢了。"""

import sys

P = r"C:\Users\zhuangmenghong\.workbuddy\skills\godot-verification-suite-triage\SKILL.md"

ANCHOR = "> \u26d4 **\u901a\u7528\u6559\u8bad**\uff1a\u300c\u63a2\u9488/\u573a\u666f\u8dd1\u51e0\u5206\u949f\u751a\u81f3\u51e0\u5341\u5206\u949f\u4e0d\u7ed3\u675f\u300d"

SEC_D = """**D. 自己的补丁把**注释前缀**丢了（漏一个 `## `）** —— 往 `##` 文档注释块里插行时，漏写前缀，
那一行就**变成代码**（`（同一判据也给 … 用）` 这种以全角括号开头的行），整个脚本解析失败（2026-09-22 实测）。

**传染性症状（最能骗人的一条）**：报的不是「某一行语法错」，而是一串**类名**：

```text
SCRIPT ERROR: Parse Error: Could not parse global class "Dungeon3D" from "res://src/world3d/Dungeon3D.gd".
SCRIPT ERROR: Parse Error: Could not parse global class "TowerDescent3D" from "res://src/world3d/TowerDescent3D.gd".
ERROR: Failed to instantiate an autoload, script 'res://src/enemy3d/MonsterAIManager.gd' does not inherit from 'Node'.
ERROR: Failed to load script "res://tests/verification/verify_xxx.gd" with error "Parse error".
```

**基类挂了 ⇒ 子类也报「Could not parse global class」⇒ 引用它的 autoload 挂 ⇒ 探针压根没加载。**
此时探针**一条 `ok` 都不会打印**、`verify_*_OK` 行永远不出现、进程**空转不退**（本次空转 7m52s 才被手动杀）。
所以日志里「只有引擎噪音 + `Could not parse global class`」= 不是慢，是自己的脚本坏了。

**判据**：`grep -n "Could not parse global class" <日志>` → 拿到文件名 → 只看它**最近改过的那几行**：
`sed -n 'A,Bp' <文件> | cat -A`。**必须以 `cat -A` 看行首**（`^I` = tab，`^I## ` / `^I# ` 才是注释；
直接看内容看不出丢没丢前缀）。

**修法**：补齐注释前缀（`## ` / `# `）。**闸门**：改完必须 `cat -A` 复看整段；
再跑一次探针，确认 `grep -c "Parse Error"` 为 0 且结果行出现。

**预防**：任何「往注释块里插行」的补丁脚本，插入文本的每一行都要**自带注释前缀**，
别依赖「上一行的前缀会延续」——GDScript 没有块注释延续，Markdown 侧也没有。

"""


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "**D. \u81ea\u5df1\u7684\u8865\u4e01\u628a**\u6ce8\u91ca\u524d\u7f00**\u4e22\u4e86" in text:
        print("ALREADY PATCHED")
        return 0

    n = text.count(ANCHOR)
    if n != 1:
        print("ABORT: 锚点命中 %d" % n)
        return 3
    text = text.replace(ANCHOR, SEC_D + ANCHOR)

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
