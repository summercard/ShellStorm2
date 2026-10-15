extends Node

## 探针：本局「背包 / 钥匙 / 金币」读数是否已从左上血条挪到右下角，且字号对齐弹药读数。
## 判据（相对量，抗 canvas 尺寸变化）：右缘间隙 / 下缘间隙 / 字号相等 / 父节点不再是 PlayerStatusBlock。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 10:
		await get_tree().process_frame

	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD") as Control
	if hud == null:
		print("PROBE_FAIL hud_missing")
		get_tree().quit(1)
		return

	var canvas := hud.size
	print("PROBE_CANVAS w=%d h=%d" % [int(canvas.x), int(canvas.y)])

	var loot := hud.find_child("RunLootReadout", true, false) as Label
	if loot == null:
		print("PROBE_FAIL loot_readout_missing")
		get_tree().quit(1)
		return
	var loot_rect := loot.get_global_rect()
	print("PROBE_LOOT text=%s visible=%s font=%d rect=(%.1f,%.1f,%.1f,%.1f) right_gap=%.1f bottom_gap=%.1f parent=%s" % [
		loot.text,
		str(loot.visible),
		loot.get_theme_font_size("font_size"),
		loot_rect.position.x, loot_rect.position.y, loot_rect.size.x, loot_rect.size.y,
		canvas.x - loot_rect.end.x,
		canvas.y - loot_rect.end.y,
		str(loot.get_parent().name),
	])
	print("PROBE_LOOT color=%s h_align=%d" % [
		str(loot.get_theme_color("font_color")),
		loot.horizontal_alignment,
	])

	var weapon := hud.find_child("CurrentWeaponPanel", true, false) as Control
	if weapon != null:
		var wr := weapon.get_global_rect()
		print("PROBE_WEAPON_PANEL rect=(%.1f,%.1f,%.1f,%.1f) w=%.1f h=%.1f right_gap=%.1f bottom_gap=%.1f top_gap_to_loot=%.1f" % [
			wr.position.x, wr.position.y, wr.size.x, wr.size.y, wr.size.x, wr.size.y,
			canvas.x - wr.end.x, canvas.y - wr.end.y, wr.position.y - loot_rect.end.y,
		])

	var ammo := hud.find_child("CurrentWeaponPanel", true, false)
	if ammo != null:
		for child in ammo.find_children("*", "Label", true, false):
			var label := child as Label
			if label.name == "RunLootReadout":
				continue
			var lr := label.get_global_rect()
			print("PROBE_WEAPON_LABEL name=%s text=%s font=%d visible=%s rect=(%.1f,%.1f,%.1f,%.1f) right_gap=%.1f" % [
				label.name, label.text, label.get_theme_font_size("font_size"), str(label.visible),
				lr.position.x, lr.position.y, lr.size.x, lr.size.y, canvas.x - lr.end.x
			])

	var status_block := hud.find_child("PlayerStatusBlock", true, false) as Control
	if status_block != null:
		var sr := status_block.get_global_rect()
		print("PROBE_PLAYER_STATUS rect=(%.1f,%.1f,%.1f,%.1f) size_x=%.1f" % [
			sr.position.x, sr.position.y, sr.size.x, sr.size.y, sr.size.x
		])
		var loot_inside := status_block.find_child("RunLootReadout", true, false) != null
		print("PROBE_LOOT_IN_STATUS_BLOCK %s" % str(loot_inside))

	print("PROBE_RUN_LOOT_READOUT_OK")
	get_tree().quit(0)
