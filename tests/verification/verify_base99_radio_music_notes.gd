extends Node
## 真实Tower、原生玩家相机与输入派发；截图不更改相机参数。
const OUT := "res://outputs/base99_radio_music_notes"
const RADIO := "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"
var failures: Array[String] = []
var evidence: Dictionary = {"samples": [], "checks": []}
var radio: Base99Radio3D
var tower: TowerDescent3D

func _ready() -> void:
	await _isolated_checks()
	tower = (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	radio = tower.find_child("99F床边桌独立收音机", true, false) as Base99Radio3D
	if radio == null:
		_check(false, "正式场景收音机存在")
		_finish()
		return
	var player := tower.player
	player.global_position = radio.global_position + Vector3(0.0, -0.90, 1.1)
	player.velocity = Vector3.ZERO
	player.set_input_locked(false)
	player.set_combat_enabled(false)
	tower.call("_refresh_physical_location_authority", true)
	await get_tree().create_timer(0.75).timeout
	var camera := player.camera
	camera.current = true
	_check(absf(radio.global_position.y) > 0.5, "真实radio世界Y非零")
	evidence["radio_world_position"] = _vec(radio.global_position)
	evidence["camera"] = {"position": _vec(camera.global_position), "rotation": _vec(camera.global_rotation), "fov": camera.fov, "projection": camera.projection}
	_check(_live() == 0 and not radio.music_notes.visible, "初始off隐藏且零活音符")
	await _capture("off_initial_player.png")
	var screen := camera.unproject_position(radio.get_interaction_dot_anchor())
	_check(radio.call("_mouse_hits_radio", screen, player), "附件不遮挡点击射线")
	await _click(screen)
	_check(radio.radio_state == "a" and radio.audio_player.playing, "真鼠标派发播放A")
	await get_tree().create_timer(0.65).timeout
	var first := radio.music_notes.get_presentation_snapshot()
	_check(_live() > 0 and _live() <= 5, "播放A后固定预算内有音符")
	await _capture("a_player_frame_01.png")
	await get_tree().create_timer(0.25).timeout
	var second := radio.music_notes.get_presentation_snapshot()
	_check(_has_risen(first, second), "跨帧同一活音符世界位置升高")
	await _capture("a_player_frame_02.png")
	await get_tree().create_timer(0.25).timeout
	await _capture("a_player_frame_03.png")
	var before_b := radio.music_notes.get_presentation_snapshot()
	await _key_e()
	_check(radio.radio_state == "b" and radio.audio_player.playing, "真E派发播放B")
	_check(_continues(before_b, radio.music_notes.get_presentation_snapshot()), "A到B不重置活音符")
	await _capture("b_player_continuous.png")
	await _click(screen)
	_check(radio.radio_state == "off" and _live() == 0 and not radio.music_notes.visible, "鼠标关闭立即清零")
	await _capture("off_after_play_player.png")
	await _key_e()
	await get_tree().create_timer(0.45).timeout
	_check(radio.radio_state == "a" and _live() > 0, "关闭后重启再次发射")
	player.global_position = TowerDescent3D.ROOFTOP_LOGOUT_SPAWN
	tower.call("_refresh_physical_location_authority", true)
	_check(radio.radio_state == "off" and _live() == 0 and not radio.music_notes.visible, "离开99层同步停止并清空")
	await get_tree().process_frame
	_check(not radio.audio_player.playing, "离层真实音频停止")
	tower.free()
	await get_tree().process_frame
	_finish()

func _isolated_checks() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(8.0, -1176.0, 12.0)
	add_child(holder)
	var instance := (load(RADIO) as PackedScene).instantiate() as Base99Radio3D
	holder.add_child(instance)
	await get_tree().process_frame
	var fx := instance.music_notes
	_check(fx.get_parent() == instance and fx.get_meta("asset_id") == "VFX-RADIO-MUSIC-NOTES-3D", "独立Prefab是radio child且AssetID正确")
	_check(fx.lifetime == 0.0 and fx.get_child_count() == 5, "附件单宿主且固定五槽位")
	_check(_collision_count(fx) == 0, "附件零CollisionObject/CollisionShape")
	for child in fx.get_children():
		var note := child as MeshInstance3D
		var mat := note.material_override as StandardMaterial3D
		_check(note.mesh is QuadMesh and mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and mat.albedo_texture != null and not mat.emission_enabled, "预制音符billboard有纹理且无发光过曝")
	# 固定步进测包络、预算与升高，避免用被测常量自印证。
	fx.set_emitting(true)
	fx.set_process(false)
	fx._process(0.01)
	var born := fx.get_presentation_snapshot()
	_check(int(born.live_count) == 1 and float(born.live[0].alpha) == 0.0, "出生从透明开始")
	fx._process(0.15)
	var faded_in := fx.get_presentation_snapshot()
	_check(float(faded_in.live[0].alpha) > 0.8, "0.15秒淡入可见")
	fx._process(1.4)
	var tail := fx.get_presentation_snapshot()
	_check(float(tail.live[0].alpha) < 0.6 and float(tail.live[0].y) - float(born.live[0].y) > 0.8, "尾端淡出并上飘超过0.8米")
	fx.set_emitting(false)
	fx.set_emitting(true)
	fx.set_process(false)
	var peak := 0
	for step in 600:
		fx._process(1.0 / 60.0)
		peak = maxi(peak, int(fx.get_presentation_snapshot().live_count))
	_check(peak == 5 and fx.get_child_count() == 5, "10秒固定步进稳态上限五枚不增长节点")
	fx.set_emitting(false)
	instance.set_radio_state("a")
	await get_tree().create_timer(0.6).timeout
	var snap := fx.get_presentation_snapshot()
	_check(int(snap.live_count) > 0 and absf(fx.global_position.y + 1174.58) < 0.01, "负1176米楼层附件挂点正确")
	for item in snap.live:
		_check(absf(float(item.y)) > 1000.0, "活音符留在深层不飞往原点")
	var old_position := fx.global_position
	holder.position += Vector3(3.0, 2.5, -1.0)
	_check(fx.global_position.is_equal_approx(old_position + Vector3(3.0, 2.5, -1.0)), "平移radio后附件随父节点同步")
	instance.audio_player.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(fx.get_presentation_snapshot().live_count) == 0 and not fx.visible, "反向用例真实音频停但状态A也清空")
	instance.set_radio_state("b")
	await get_tree().create_timer(0.5).timeout
	_check(int(fx.get_presentation_snapshot().live_count) > 0, "独立附件可重启")
	instance.set_floor_active(false)
	_check(int(fx.get_presentation_snapshot().live_count) == 0, "floor off当帧清空")
	holder.remove_child(instance)
	_check(not fx.visible and int(fx.get_presentation_snapshot().live_count) == 0, "exit_tree即时清空")
	instance.free()
	holder.free()

func _collision_count(node: Node) -> int:
	var total := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		total += _collision_count(child)
	return total

func _live() -> int:
	return int(radio.music_notes.get_presentation_snapshot().live_count)

func _has_risen(a: Dictionary, b: Dictionary) -> bool:
	for first in a.live:
		for second in b.live:
			if first.serial == second.serial and float(second.y) - float(first.y) > 0.08:
				return true
	return false

func _continues(a: Dictionary, b: Dictionary) -> bool:
	for first in a.live:
		for second in b.live:
			if first.serial == second.serial and float(second.age) >= float(first.age):
				return true
	return false

func _click(screen: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = screen
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _key_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "真实窗口PNG非空:" + filename)
	if image != null:
		_check(image.save_png(OUT + "/" + filename) == OK, "PNG保存:" + filename)
	var snapshot := radio.music_notes.get_presentation_snapshot()
	snapshot["png"] = filename
	snapshot["state"] = radio.radio_state
	evidence.samples.append(snapshot)

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _check(condition: bool, label: String) -> void:
	evidence.checks.append({"label": label, "passed": condition})
	if not condition:
		failures.append(label)

func _finish() -> void:
	evidence["passed"] = failures.is_empty()
	evidence["failures"] = failures
	FileAccess.open(OUT + "/runtime_acceptance.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	if failures.is_empty():
		print("BASE99_RADIO_MUSIC_NOTES_OK: checks=%d screenshots=%d" % [evidence.checks.size(), evidence.samples.size()])
	else:
		for failure in failures:
			push_error("BASE99_RADIO_MUSIC_NOTES_FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
