"""把本事务追加进 2026-09-22 的 _INDEX.md。

该目录的 .md 一律 LF（不是项目 res:// 的 CRLF），所以这里只做 LF 读写。
索引按时间前缀降序，插到 `| 10:45 |` 那行之前。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = (next(p for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents] if (p / "project.godot").exists())).parent / ".workbuddy" / "memory" / "2026-09-22"
INDEX = ROOT / "_INDEX.md"

ROW = (
    "| 10:46 | [子界面手柄焦点锚点修复](1046_子界面手柄焦点锚点修复.md) | "
    "**Bug 修复（根因 + 12 文件接线 + 永久断言 + 窗口实证）** | "
    "主人报「手柄在其它子界面无效，比如远征情报室」。根因：8 个设施菜单由 "
    "`BaseWorld3D._open_menu()` 打开时**从不 grab_focus()**，而 Godot 4 的 "
    "`ui_up/down/left/right` 与 `ui_accept` **都必须先有 gui focus owner 才会被派发** —— "
    "鼠标不需要焦点，所以键鼠下完全看不见这个缺口。修法：新增 `src/ui/UiMenuFocus.gd`"
    "（纯 static，默认焦点取 **CloseButton/SkipButton** 返回类而非树序第一个，"
    "避免误触解锁/购买/传送；`find_child(..., owned=false)` 才能找到代码 new 出来的按钮），"
    "**12 个覆盖式菜单**在 _ready 末尾调 `UiMenuFocus.ensure_focus(self)`；"
    "`BaseVendingMenu`/`BaseRecoveryMenu`/`WardrobeMenu3D` 的关闭按钮原先无节点名，补 `CloseButton`。"
    "永久断言写进 `verify_gamepad_input_flow.gd::_verify_submenu_focus_anchor()`（8 条菜单必须有"
    "在菜单内的焦点持有者）——**负向对照**：停掉 grab_focus → 8 条全红 exit=1，还原后 "
    "`GAMEPAD_INPUT_FLOW_OK` exit=0。**关键口径**：headless 下 `grab_focus()` 有效但**合成事件走不到 "
    "按钮 `pressed`**（GUI 派发不被驱动）⇒ 激活链路只能带窗口验：`probe_menu_focus_activation` 实测 "
    "`ui_up: CloseButton → @Button@33 焦点移动=true`、手柄 A / 物理回车 `命中次数=1 菜单已销毁=true`。"
    "另钉：`ui_accept`/`ui_cancel` 绑的是 **`physical_keycode`**（导航键绑 `keycode`），"
    "合成 Key 只填 `keycode` 时 ui_accept **不命中**（keycode Enter 命中 0 / physical Enter 命中 1），"
    "**别两个字段一起填**。裸 Control+Button 对照 6 种注入方式全命中 ⇒ 引擎机制无问题，缺的只是焦点持有者。"
    "收尾：删 3 个一次性探针、还原被 headless 跑动的 `base_save.json`（revision 121→150）。**未提交**。 |"
)

ANCHOR = "| 10:45 | ["


def main() -> int:
    text = INDEX.read_text(encoding="utf-8")
    if "1046_子界面手柄焦点锚点修复" in text:
        print("SKIP 索引已含本事务")
        return 0
    if text.count(ANCHOR) != 1:
        print("FAIL 锚点命中 %d 次" % text.count(ANCHOR))
        return 1
    text = text.replace(ANCHOR, ROW + "\n" + ANCHOR, 1)
    # memory/README.md 是约定真源，要求 .md 一律 CRLF（前两天的 _INDEX.md 也都是 CRLF）。
    text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    INDEX.write_bytes(text.encode("utf-8"))
    print("OK 已插入索引行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
