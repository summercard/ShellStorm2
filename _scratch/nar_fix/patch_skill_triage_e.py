# -*- coding: utf-8 -*-
"""分诊 skill 加 E 类：自己写的源码守卫永远红 —— 先怀疑守卫自己（CRLF 跨行 contains）。"""

import sys

P = r"C:\Users\zhuangmenghong\.workbuddy\skills\godot-verification-suite-triage\SKILL.md"

ANCHOR = "> \u26d4 **\u901a\u7528\u6559\u8bad**\uff1a\u300c\u63a2\u9488/\u573a\u666f\u8dd1\u51e0\u5206\u949f\u751a\u81f3\u51e0\u5341\u5206\u949f\u4e0d\u7ed3\u675f\u300d"

SEC_E = '''**E. 自己写的「源码守卫」永久红 —— 先怀疑守卫自己**（2026-09-22 实测）

探针里用 `FileAccess.get_file_as_string("res://src/xxx.gd")` 再 `contains("A\\n\\t\\tB")` 搜**跨行片段**时：
本仓 `.gd` 是 **CRLF**，用 `\\n` 拼出来的多行模式**永远匹配不上** ⇒ 守卫**永久红**，
看起来像「代码真的坏了」，其实坏的是守卫。

**判据**：这条守卫红了、但它守的那段代码肉眼看着完全正常 ⇒ 立刻怀疑匹配串。
`print(片段长度)` 或改成**分别按单行片段**搜，一次就能确诊。
⚠️ 这类守卫**不能只跑一次就信**：它「红」可能与自己无关，它「绿」也可能是巧合 —— 所以
**必须做反向对照**（把被守的代码改坏 ⇒ 守卫要变红；还原 ⇒ 要变绿），否则等于没验。

**修法**：读源码后一律先归一 —— `.replace("\\r\\n", "\\n")`，再做跨行 `contains`。
单行片段不受影响，但统一归一最省心（也顺手把「脚本自己写死 CRLF」的隐患一起挡掉）。

'''

def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if "**E. \u81ea\u5df1\u5199\u7684\u300c\u6e90\u7801\u5b88\u536b\u300d\u6c38\u4e45\u7ea2" in text:
        print("ALREADY PATCHED")
        return 0
    n = text.count(ANCHOR)
    if n != 1:
        print("ABORT: 锚点命中 %d" % n)
        return 3
    text = text.replace(ANCHOR, SEC_E + ANCHOR)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
