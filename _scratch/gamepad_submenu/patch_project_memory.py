"""把本次事务沉淀的两条硬约定写进项目 MEMORY.md（CRLF）。

1) 输入与手柄：覆盖式菜单必须抓默认焦点（UiMenuFocus.ensure_focus）。
2) 验证与门禁：headless 验不到「确认键触发按钮」；ui_accept 绑 physical_keycode。
"""
from __future__ import annotations

import sys
from pathlib import Path

MEMORY = (next(p for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents] if (p / "project.godot").exists())).parent / ".workbuddy" / "memory" / "MEMORY.md"

ANCHOR_A = "写反会左右镜像且零报错。细节见 playbooks「输入与手柄」。\n"
ADD_A = (
    "- **覆盖式菜单必须抓默认焦点**：`UiMenuFocus.ensure_focus(self)`"
    "（`src/ui/UiMenuFocus.gd`，纯 static）。Godot 的 `ui_up/down/left/right` 与 `ui_accept` "
    "**都要先有 gui focus owner 才被派发** —— 鼠标不需要焦点，所以这个缺口在键鼠下完全看不见，"
    "手柄一进子界面就整体哑掉（12 个覆盖式菜单已全接）。默认焦点取 `CloseButton`/`SkipButton`，"
    "不用树序第一个（常是解锁/购买/传送这类有副作用的按钮）；`find_child(..., owned = false)` "
    "是必需的，这些按钮多是代码 `new()` 出来的。\n"
)

ANCHOR_B = "别进 `git add -A`。\n"
ADD_B = (
    "- **headless 验不到「确认键是否触发按钮」**：headless 下 `grab_focus()` 有效，所以"
    "「焦点锚点」可以 headless 断言（`verify_gamepad_input_flow.gd::_verify_submenu_focus_anchor()`，"
    "配 `negctl_focus.py` 做反向对照）；但**合成事件走不到按钮的 `pressed`**（GUI 输入派发不被驱动）"
    "⇒ 激活链路只能带窗口跑（`probe_menu_focus_activation`）。另：`ui_accept`/`ui_cancel` 绑的是 "
    "**`physical_keycode`**、导航键绑 `keycode`，合成 `InputEventKey` **别两个字段一起填** —— "
    "填错不会报错，只是静默不命中。\n"
)


def main() -> int:
    text = MEMORY.read_bytes().replace(b"\r\n", b"\n").decode("utf-8")
    if "UiMenuFocus" in text:
        print("SKIP MEMORY.md 已含本约定")
        return 0
    for name, anchor, add in (("A", ANCHOR_A, ADD_A), ("B", ANCHOR_B, ADD_B)):
        if text.count(anchor) != 1:
            print("FAIL 锚点 %s 命中 %d 次" % (name, text.count(anchor)))
            return 1
        text = text.replace(anchor, anchor + add, 1)
    MEMORY.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
    print("OK 已更新 MEMORY.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
