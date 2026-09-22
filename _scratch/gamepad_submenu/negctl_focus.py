"""负向对照开关：临时把 UiMenuFocus.ensure_focus() 的 grab_focus() 停掉，
复现「菜单不抓焦点」的原始 bug，用来证明新断言真的会红。

用法：
  python negctl_focus.py off   # 停掉 grab_focus（先备份原文件）
  python negctl_focus.py on    # 从备份恢复
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in [HERE, *HERE.parents] if (p / "project.godot").exists())
TARGET = ROOT / "src" / "ui" / "UiMenuFocus.gd"
BACKUP = HERE / "UiMenuFocus.gd.bak"

ON_BYTES = b"\ttarget.grab_focus()\r\n"
OFF_BYTES = b"\t# NEGATIVE CONTROL: grab_focus() disabled\r\n"


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in ("off", "on"):
        print("用法: negctl_focus.py off|on")
        return 2
    mode = argv[1]
    if mode == "off":
        raw = TARGET.read_bytes()
        if raw.count(ON_BYTES) != 1:
            print("FAIL grab_focus 锚点命中 %d 次" % raw.count(ON_BYTES))
            return 1
        BACKUP.write_bytes(raw)
        TARGET.write_bytes(raw.replace(ON_BYTES, OFF_BYTES, 1))
        print("off 已停用 grab_focus（备份 %s）" % BACKUP.name)
    else:
        TARGET.write_bytes(BACKUP.read_bytes())
        print("on 已从备份恢复")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
