extends Node

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const BEFORE_PATH := "res://_scratch/boss_hud_before_activation.png"
const AFTER_PATH := "res://_scratch/boss_hud_after_activation.png"


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	if room == null:
		_fail("room_missing")
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower._on_room_entered(room)
	await get_tree().physics_frame
	var boss: Enemy3D = null
	for value in tower._enemy_nodes_by_room.get(room.room_id, []) as Array:
		var enemy := value as Enemy3D
		if enemy != null and str(enemy.get_enemy_data().get("boss_content_id", "")) == "boss_monitor002":
			boss = enemy
			break
	if boss == null or boss.monitor_combat == null:
		_fail("boss_missing")
		return
	boss.set_physics_process(false)
	boss.monitor_combat.activation_started = false
	boss.monitor_combat.activation_elapsed = 0.0
	boss.monitor_combat.activation_completed = false
	tower._show_boss_hud(boss)
	tower.player.global_position = boss.global_position + Vector3(10.1, 0.0, 0.0)
	boss._physics_process(0.25)
	var before_hidden := tower._boss_panel != null and not tower._boss_panel.visible
	await _capture(BEFORE_PATH)
	tower.player.global_position = boss.global_position + Vector3(9.9, 0.0, 0.0)
	boss._physics_process(0.25)
	boss._physics_process(6.20)
	var after_visible := tower._boss_panel != null and tower._boss_panel.visible
	await _capture(AFTER_PATH)
	if not before_hidden or not after_visible:
		_fail("visibility before_hidden=%s after_visible=%s" % [before_hidden, after_visible])
		return
	print("BOSS_HUD_VISUAL_OK before_hidden=%s after_visible=%s before=%s after=%s" % [
		str(before_hidden), str(after_visible), ProjectSettings.globalize_path(BEFORE_PATH), ProjectSettings.globalize_path(AFTER_PATH),
	])
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _capture(path: String) -> void:
	for _index in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		_fail("save=%s error=%d" % [path, error])


func _fail(message: String) -> void:
	push_error("BOSS_HUD_VISUAL_FAIL " + message)
	get_tree().quit(1)
