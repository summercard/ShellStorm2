extends Node
## 探针：基地各设施子界面（CanvasLayer 菜单）打开后，是否有控件持有焦点。
## 焦点为空 ⇒ 手柄十字键（ui_up/down/left/right）没有作用目标、A 键（ui_accept）
## 也没有可触发的按钮 ⇒ 手柄在整个子界面里完全无效。

const MENUS := [
	"res://scenes/RogueMapSelectMenu.tscn",
	"res://scenes/WorkshopMenu.tscn",
	"res://scenes/VaultMenu.tscn",
	"res://scenes/MonsterArchiveMenu.tscn",
	"res://scenes/FateCardCollectionMenu.tscn",
	"res://scenes/BaseVendingMenu.tscn",
	"res://scenes/BaseRecoveryMenu.tscn",
	"res://scenes/ui/WardrobeMenu3D.tscn",
]


func _ready() -> void:
	print("=== 子界面焦点探针 ===")
	for path in MENUS:
		await _probe(path)
	print("=== 探针结束 ===")
	get_tree().quit(0)


func _probe(path: String) -> void:
	if not ResourceLoader.exists(path, "PackedScene"):
		print("%-46s 场景不存在" % path.get_file())
		return
	var packed := load(path) as PackedScene
	var menu := packed.instantiate()
	if menu == null:
		print("%-46s 实例化失败" % path.get_file())
		return
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	var buttons: Array[Button] = []
	_collect(menu, buttons)
	var focusable := 0
	var focus_modes: Array[String] = []
	for button in buttons:
		var mode := button.focus_mode
		if mode != Control.FOCUS_NONE:
			focusable += 1
		focus_modes.append(_mode_name(mode))
	var owner := get_viewport().gui_get_focus_owner()
	print("%-40s 按钮=%2d  可聚焦=%2d  焦点持有=%s"
		% [path.get_file(), buttons.size(), focusable,
			"无" if owner == null else str(owner.name)])
	if not buttons.is_empty() and focusable == 0:
		print("      ⚠ 所有按钮都不可聚焦（focus_mode 全为 NONE）")
	if not focus_modes.is_empty():
		var counts := {}
		for m in focus_modes:
			counts[m] = int(counts.get(m, 0)) + 1
		print("      focus_mode 分布: %s" % str(counts))

	menu.queue_free()
	await get_tree().process_frame


func _collect(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child as Button)
		_collect(child, out)


func _mode_name(mode: int) -> String:
	match mode:
		Control.FOCUS_NONE: return "NONE"
		Control.FOCUS_CLICK: return "CLICK"
		Control.FOCUS_ALL: return "ALL"
	return "?"
