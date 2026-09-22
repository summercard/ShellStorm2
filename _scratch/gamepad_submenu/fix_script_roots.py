"""修掉搬迁后失效的路径解析：脚本从工作区根 _scratch/ 搬进了仓库内
ShellStorm2/_scratch/gamepad_submenu/，`parents[2]` 因此指深了一层。

改成从 __file__ 向上找 `project.godot`，位置无关，以后再搬也不会坏。
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

FIND = (
    "next(p for p in [Path(__file__).resolve().parent, "
    "*Path(__file__).resolve().parent.parents] "
    "if (p / \"project.godot\").exists())"
)
FIND_HERE = "next(p for p in [HERE, *HERE.parents] if (p / \"project.godot\").exists())"

EDITS: list[tuple[str, str, str]] = [
    ("patch_menu_focus.py",
     'ROOT = Path(__file__).resolve().parents[2] / "ShellStorm2"',
     "ROOT = %s" % FIND),
    ("add_focus_anchor_assert.py",
     'ROOT = Path(__file__).resolve().parents[2] / "ShellStorm2"',
     "ROOT = %s" % FIND),
    ("to_crlf.py",
     'ROOT = Path(__file__).resolve().parents[2] / "ShellStorm2"',
     "ROOT = %s" % FIND),
    ("negctl_focus.py",
     'ROOT = HERE.parents[1] / "ShellStorm2"',
     "ROOT = %s" % FIND_HERE),
    ("add_memory_index_row.py",
     'ROOT = Path(__file__).resolve().parents[2] / ".workbuddy" / "memory" / "2026-09-22"',
     'ROOT = (%s).parent / ".workbuddy" / "memory" / "2026-09-22"' % FIND),
    ("patch_project_memory.py",
     'MEMORY = Path(__file__).resolve().parents[2] / ".workbuddy" / "memory" / "MEMORY.md"',
     'MEMORY = (%s).parent / ".workbuddy" / "memory" / "MEMORY.md"' % FIND),
    ("write_aim_convention_note.py",
     'ROOT = Path(__file__).resolve().parents[2] / ".workbuddy" / "memory" / "2026-09-22"',
     'ROOT = (%s).parent / ".workbuddy" / "memory" / "2026-09-22"' % FIND),
]


def main() -> int:
    failed = 0
    for name, old, new in EDITS:
        path = HERE / name
        if not path.exists():
            print("MISS %s" % name)
            failed += 1
            continue
        text = path.read_text(encoding="utf-8")
        if text.count(old) != 1:
            if new.split("next(")[0] in text and "project.godot" in text:
                print("SKIP %s 已修" % name)
                continue
            print("FAIL %s 锚点命中 %d 次" % (name, text.count(old)))
            failed += 1
            continue
        path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
        print("OK   %s" % name)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
