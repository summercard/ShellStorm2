extends Node

## 卡面尺寸统一性探针（验收用，不参与游戏运行）
## 在三张卡位注入「最窄 / 典型 / 最宽」三种比例的卡，真实渲染出图，
## 用来判断「宽度不统一」在游戏内是否肉眼可辨。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const OUT_PATH := "res://outputs/verification/fate_card_size_audit.png"


func _ready() -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 10:
		await get_tree().process_frame

	# 注入固定三张：最窄(0.453) / 典型宽(0.633) / 最宽(0.661)
	# 注意 _door_fate_choices 是 Array[FateCard]，必须用同类型数组赋值（普通 Array 会被拒）。
	var picks: Array[FateCard] = [
		FateCardPresets.huge_scale(),               # 权杖·国王  0.453
		FateCardPresets.gun_on_gun(),               # 魔术师     0.633
		FateCardPresets.attachment_parasite(),      # 权杖·三    0.661
	]
	var labels := ["最窄 0.453", "典型 0.633", "最宽 0.661"]
	print("=== 卡面素材实测 ===")
	for i in range(picks.size()):
		var tex := FateCardView.art_for(picks[i])
		if tex != null:
			var r := float(tex.get_width()) / float(tex.get_height())
			print("  %-14s %s  素材 %dx%d  比例 %.3f" % [
				picks[i].card_name, labels[i], tex.get_width(), tex.get_height(), r])

	dungeon.set("_door_fate_choices", picks)
	dungeon.set("_pending_fate_currency_choice", -1)
	dungeon.set("_door_fate_active", true)
	dungeon.call("_build_door_fate_overlay")
	print("  注入后卡位数: %d" % (dungeon.get("_door_fate_choices") as Array).size())

	# 等翻转动画走完（0.10 + 2*0.08 stagger + 0.14 + 0.18 + 余量）
	await get_tree().create_timer(1.6).timeout
	for _frame in 5:
		await get_tree().process_frame

	# 量一张卡的实际渲染尺寸并打印
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	if overlay != null:
		var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
		print("=== 游戏内实际渲染 ===")
		print("  卡位数: %d" % cards.size())
		for card in cards:
			var ctrl := card as Control
			var art := ctrl.find_child("TarotArtFace", true, false) as TextureRect
			var sid := str(ctrl.get_meta("tarot_stable_card_id", "?"))
			if art != null and art.texture != null:
				var ar := float(art.texture.get_width()) / float(art.texture.get_height())
				var cw := ctrl.size.x
				var ch := ctrl.size.y
				var rc := cw / ch
				var rw := ch * ar if ar <= rc else cw
				var rh := ch if ar <= rc else cw / ar
				print("  %-24s 容器 %.1fx%.1f  渲染 %.1fx%.1f  占容器宽 %.0f%%" % [
					sid, cw, ch, rw, rh, rw / cw * 100.0])

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	print("SIZE_PROBE_SHOT err=%d -> %s" % [err, OUT_PATH])
	get_tree().quit()
