extends Node
## 实拍：兔子闸门的三个关键帧（关闸眼睛发红 / 开闸露产物 / 收完）。
##
## 只在窗口模式下产出 PNG —— `--headless` 下 `frame_post_draw` 不触发，截图会被静默跳过。
## 时间用**手动驱动** `_process`，不真等 3.6 秒：动画的全部时间来源都是 `_time`。

const PANEL := preload("res://src/ui/WorkbenchPanel.gd")
const INVENTORY := preload("res://src/game/InventoryModule.gd")
const FORGE := preload("res://src/weapons/WeaponForge.gd")
const STEP := 0.05
const OUT_DIR := "res://outputs/verification"


class _StubRef:
	extends Node
	var inventory: InventoryModule = null
	func get_inventory_module() -> InventoryModule:
		return inventory


func _ready() -> void:
	# 面板的 Dim 是半透明的，底下纯黑会让整张图读不出层次。
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.10, 0.16, 0.20)
	add_child(backdrop)

	var stub := _StubRef.new()
	stub.inventory = INVENTORY.new(40)
	add_child(stub)
	for item_id in ["mod_bullet_standard", "item_battery_l", "item_health_potion"]:
		stub.inventory.add_item(_item(item_id), 1)
	GameManager.currency = 2000

	var panel = PANEL.new()
	panel.set_workbench_ref(stub)
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	# 盘面：2 个豌豆手枪碎片 + 4 个标准弹 ⇒ R0 定向合成。
	panel.call("_tray_append", _item("bp_pistol"), 2, 0, 0)
	panel.call("_tray_append", _item("mod_bullet_standard"), 4, 2, 0)
	panel.call("_refresh_all")
	await get_tree().process_frame

	var veil := panel.find_child("SynthesisGateVeil", true, false) as SynthesisGateVeil
	if veil == null:
		print("CAPTURE_SYNTHESIS_GATE_FAIL 闸门不存在")
		get_tree().quit(1)
		return

	var plan := FORGE.classify(panel.call("_tray_probe_items"))
	panel.call("_execute_forge", plan)
	await get_tree().process_frame
	# 手动接管时间轴，取帧才是确定性的。
	veil.set_process(false)

	# ① 关闸落底 + 眼睛全红（1.0s）
	_advance(veil, 1.0)
	await _capture("synthesis_gate_closed")
	# ② 开闸中（3.45s，闸门已升起约六成，台上那把枪露出来）
	# 取 3.45 而不是 3.3：闸门的下沿在 h×闭合度 处，闭合度要掉到 0.5 以下
	# 才轮到台面（居中）露头。3.45s 时闭合度 0.44，产物正好露出上半身。
	_advance(veil, 2.45)
	await _capture("synthesis_gate_revealing")
	# ③ 停留段（4.3s，闸门已收起，台面完整展示产物 —— 这是给玩家看清的 1.4 秒）
	_advance(veil, 0.85)
	await _capture("synthesis_gate_revealed")
	# ④ 播完（5.2s，台面淡出，盘面清空、产物已入包）
	_advance(veil, 0.9)
	await _capture("synthesis_gate_done")

	get_tree().quit(0)


func _capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)
	if err == OK:
		print("CAPTURE_SYNTHESIS_GATE_OK %s %dx%d" % [path, image.get_width(), image.get_height()])
	else:
		print("CAPTURE_SYNTHESIS_GATE_FAIL %s err=%d" % [path, err])


func _advance(veil: Node, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0001:
		var step := minf(STEP, remaining)
		veil.call("_process", step)
		remaining -= step


func _item(item_id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	item["count"] = 1
	return item
