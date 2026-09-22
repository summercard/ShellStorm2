# -*- coding: utf-8 -*-
"""角色头顶气泡不再投影：面板与文字两件都关掉 cast_shadow。

`Label3D` 也是 `GeometryInstance3D`（默认会投影），所以只关 MeshInstance3D 是不够的。
"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\ui\bubble\SpeechBubble3D.gd"

PANEL_OLD = (
    "\t_panel.material_override = null\n"
    "\tadd_child(_panel)\n"
)
PANEL_NEW = (
    "\t_panel.material_override = null\n"
    "\t# 气泡是**贴在角色头上的 UI**，不该在世界里落投影（2026-09-22 主人要求）。\n"
    "\t# ⚠️ 面板与文字**两件都要关**：`Label3D` 也是 `GeometryInstance3D`，默认同样投影 ——\n"
    "\t# 只关 MeshInstance3D 的话，地上仍会留着文字的影子。\n"
    "\t_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n"
    "\tadd_child(_panel)\n"
)

LABEL_OLD = (
    "\t_label.double_sided = true\n"
    "\tadd_child(_label)\n"
)
LABEL_NEW = (
    "\t_label.double_sided = true\n"
    "\t_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n"
    "\tadd_child(_label)\n"
)


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if "SHADOW_CASTING_SETTING_OFF" in text:
        print("ALREADY PATCHED")
        return 0
    for old, new, label in ((PANEL_OLD, PANEL_NEW, "panel"), (LABEL_OLD, LABEL_NEW, "label")):
        n = text.count(old)
        if n != 1:
            print("ABORT %s: 锚点命中 %d" % (label, n))
            return 3
        text = text.replace(old, new)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
