extends Node

## 实拍：右下角「背包 / 钥匙 / 金币」读数 + 武器面板的位置与字号。
## 只在窗口模式下产出 PNG（`--headless` 下 `frame_post_draw` 不触发，截图会被静默跳过）。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 12:
		await get_tree().process_frame
	dungeon.force_enter_room_for_test("main_01")
	for _frame in 6:
		await get_tree().process_frame
	# 冻结世界更新：截图要的是确定的一帧。
	dungeon.set_process(false)

	# 弹药读数走真实接口（结构化字段 → 显示层自排）。
	dungeon.call("_on_ammo_changed", 30, 30)
	# 金币读数：取一个非零值做视觉取证；正式运行时由 _refresh_loot_label() 写入真实值。
	var loot := dungeon.get_node_or_null("HUD/ReferenceCombatHUD/RunLootReadout") as Label
	if loot != null:
		loot.text = "金币 60"

	for _frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var out_path := "res://outputs/verification/run_loot_readout_right_bottom.png"
	var err := image.save_png(out_path)
	if err == OK:
		print("CAPTURE_RUN_LOOT_READOUT_OK %s %dx%d" % [out_path, image.get_width(), image.get_height()])
	else:
		print("CAPTURE_RUN_LOOT_READOUT_FAIL err=%d" % err)
	get_tree().quit(0)
