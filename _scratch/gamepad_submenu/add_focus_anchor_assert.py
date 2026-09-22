"""给 verify_gamepad_input_flow.gd 加一条「设施子界面焦点锚点」回归断言。

背景：8 个设施 CanvasLayer 菜单原先打开时都不 grab_focus()，
导致手柄在子界面里「十字键导航 + A 键确认」都无处落脚（用户报的现象）。
修法是各菜单 _ready 末尾调 UiMenuFocus.ensure_focus(self)。
本脚本把「每条菜单打开后必须有焦点持有者」钉成会失败的断言，防止回归。

做法：先归一成 LF → 用 LF 锚点插入 → 整文件重写成 CRLF。
每个锚点必须恰好命中一次，否则整体中止（不留半成品）。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = next(p for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents] if (p / "project.godot").exists())
TARGET = ROOT / "tests" / "verification" / "verify_gamepad_input_flow.gd"
MARKER = "FACILITY_MENU_SCENES"

CONST_BLOCK = '''
## 设施子界面的焦点锚点：这些 CanvasLayer 菜单由 BaseWorld3D._open_menu() 打开，
## 打开时并不 grab_focus()。没有焦点持有者时，十字键/摇杆导航（ui_up/down/left/right）
## 与 A 键确认（ui_accept）都无处落脚 —— 手柄在这些子界面里会完全失灵。
## 清单与 BaseFacilityCatalog 里 action_kind == ACTION_MENU 的 action_path 一一对应。
const FACILITY_MENU_SCENES := [
	"res://scenes/RogueMapSelectMenu.tscn",
	"res://scenes/WorkshopMenu.tscn",
	"res://scenes/VaultMenu.tscn",
	"res://scenes/MonsterArchiveMenu.tscn",
	"res://scenes/FateCardCollectionMenu.tscn",
	"res://scenes/BaseVendingMenu.tscn",
	"res://scenes/BaseRecoveryMenu.tscn",
	"res://scenes/ui/WardrobeMenu3D.tscn",
]
'''

CALL_LINE = "\tawait _verify_submenu_focus_anchor(failures)\n"

FUNC_BLOCK = '''
## 每张设施菜单实例化后，必须已经有一个「在菜单内的焦点持有者」。
## 这是 headless 能验的最强口径：grab_focus() 不依赖 GUI 输入派发也会生效；
## 而「确认键真的触发按钮」必须带窗口跑（见 probe_menu_focus_activation.gd），
## headless 下合成事件不会走到按钮的 pressed。
func _verify_submenu_focus_anchor(failures: Array[String]) -> void:
	for path in FACILITY_MENU_SCENES:
		var scene := load(path) as PackedScene
		if scene == null:
			failures.append("设施菜单场景不存在：%s" % path)
			continue
		var menu := scene.instantiate()
		if not (menu is CanvasLayer):
			failures.append("设施菜单不是 CanvasLayer，_open_menu 会拒绝加载：%s" % path)
			menu.free()
			continue
		add_child(menu)
		# 等容器重排 + _ready 末尾的 grab_focus 生效。
		await get_tree().process_frame
		await get_tree().process_frame
		var owner := get_viewport().gui_get_focus_owner()
		if owner == null:
			failures.append(
				"设施菜单打开后没有焦点持有者，手柄在此界面失灵：%s" % path)
		elif not menu.is_ancestor_of(owner):
			failures.append(
				"设施菜单的焦点落到菜单之外：%s → %s" % [path, owner.get_path()])
		menu.queue_free()
		await get_tree().process_frame

'''

OK_OLD = "and virtual aim projects to the matching screen side\""
OK_NEW = (
    "virtual aim projects to the matching screen side, "
    "and every facility menu opens with a focus anchor for gamepad navigation\""
)


def main() -> int:
    raw = TARGET.read_bytes()
    text = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n").decode("utf-8")

    if MARKER in text:
        print("SKIP 已打过补丁（找到 %s）" % MARKER)
        return 0

    # 1) 常量块：插在 ACTION_CHANNEL_ACTIONS 数组收尾之后。
    anchor_const = '\t"use_quick_item_2",\n]\n'
    if text.count(anchor_const) != 1:
        print("FAIL 常量锚点命中 %d 次" % text.count(anchor_const))
        return 1
    text = text.replace(anchor_const, anchor_const + CONST_BLOCK, 1)

    # 2) 调用点：插在 _verify_menu_navigation 之后。
    anchor_call = "\t_verify_menu_navigation(failures)\n"
    if text.count(anchor_call) != 1:
        print("FAIL 调用锚点命中 %d 次" % text.count(anchor_call))
        return 1
    text = text.replace(anchor_call, anchor_call + CALL_LINE, 1)

    # 3) 函数体：插在 _finish 之前。
    anchor_func = "\nfunc _finish(failures: Array[String]) -> void:\n"
    if text.count(anchor_func) != 1:
        print("FAIL 函数锚点命中 %d 次" % text.count(anchor_func))
        return 1
    text = text.replace(anchor_func, FUNC_BLOCK + anchor_func.lstrip("\n"), 1)

    # 4) OK 文案：补上新增覆盖项。
    if text.count(OK_OLD) != 1:
        print("FAIL OK 文案锚点命中 %d 次" % text.count(OK_OLD))
        return 1
    text = text.replace(OK_OLD, OK_NEW, 1)

    TARGET.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
    print("OK 已写入 %s" % TARGET.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
