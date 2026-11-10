extends Node
## 实拍：业主截图里那个场景 —— 3 把枪 + 一堆材料、判为融合、FEE 432、COINS 0。
##
## 目的只有一个：证明**灰按钮旁边有话说**。改动之前这一帧的状态栏是
## 「任意物品可作材料…」那句默认速记，玩家只能自己反推为什么点不动。

const PANEL := preload("res://src/ui/WorkbenchPanel.gd")
const INVENTORY := preload("res://src/game/InventoryModule.gd")
const FORGE := preload("res://src/weapons/WeaponForge.gd")
const OUT_DIR := "res://outputs/verification"


class _StubRef:
	extends Node
	var inventory: InventoryModule = null
	func get_inventory_module() -> InventoryModule:
		return inventory


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.10, 0.16, 0.20)
	add_child(backdrop)

	var stub := _StubRef.new()
	stub.inventory = INVENTORY.new(40)
	add_child(stub)
	# 背包里放几件和截图一致的备货，让右侧不空着。
	for item_id in ["item_health_potion", "item_battery_l", "item_canister"]:
		var probe := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
		if not probe.is_empty():
			probe["count"] = 1
			stub.inventory.add_item(probe, 1)

	# **关键**：金币 0 —— 就是截图里的 COINS 0。
	GameManager.currency = 0

	var panel = PANEL.new()
	panel.set_workbench_ref(stub)
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	# 3 把枪 + 若干材料 ⇒ 融合（与截图同一分支）。
	panel.call("_tray_append", _item("weapon_pistol"), 1, 0, 0)
	panel.call("_tray_append", _item("weapon_pistol"), 1, 2, 0)
	panel.call("_tray_append", _item("weapon_pistol"), 1, 10, 0)
	panel.call("_tray_append", _item("mod_bullet_standard"), 4, 4, 0)
	panel.call("_tray_append", _item("attach_scope"), 1, 4, 2)
	panel.call("_refresh_all")
	await get_tree().process_frame

	var plan := FORGE.classify(panel.call("_tray_probe_items"))
	print("UNPAID_CASE recipe=%s fee=%d coins=%d status=%s" % [
		str(plan["recipe"]), int(plan.get("coin_cost", 0)), int(GameManager.currency),
		str((panel.get("_status") as Label).text),
	])
	await _capture("forge_unpaid_reason")

	get_tree().quit(0)


func _capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)
	print("CAPTURE %s err=%d %dx%d" % [path, err, image.get_width(), image.get_height()])


func _item(item_id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	item["count"] = 1
	return item
