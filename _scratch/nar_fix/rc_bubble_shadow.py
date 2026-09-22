# -*- coding: utf-8 -*-
"""反向对照：把气泡的 cast_shadow 关掉行摘掉 ⇒ 两条投影断言必须变红。幂等。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\ui\bubble\SpeechBubble3D.gd"

PANEL_LINE = "\t_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n"
LABEL_LINE = "\t_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n"


def load() -> str:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE: 行尾不纯")
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(text: str) -> None:
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n") and b"\r\r" not in data
    open(P, "wb").write(data)


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    t = load()
    present = (t.count(PANEL_LINE), t.count(LABEL_LINE))
    if action == "apply":
        if present == (0, 0):
            print("RC already applied")
            return 0
        if present != (1, 1):
            raise SystemExit("ABORT: 行数 %s" % str(present))
        save(t.replace(PANEL_LINE, "").replace(LABEL_LINE, ""))
        print("RC applied: 两行都摘掉（回到默认投影）")
        return 0
    if action == "restore":
        if present == (1, 1):
            print("already restored")
            return 0
        if present != (0, 0):
            raise SystemExit("ABORT: 行数 %s" % str(present))
        pa = "\t_panel.material_override = null\n"
        la = "\t_label.double_sided = true\n"
        if t.count(pa) != 1 or t.count(la) != 1:
            raise SystemExit("ABORT: 还原锚点异常")
        t = t.replace(pa, pa + PANEL_LINE).replace(la, la + LABEL_LINE)
        save(t)
        print("restored: 两行都装回")
        return 0
    raise SystemExit("usage: rc_bubble_shadow.py apply|restore")


if __name__ == "__main__":
    sys.exit(main())
