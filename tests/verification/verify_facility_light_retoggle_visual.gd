extends Node3D

const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const INITIAL_OUTPUT := "res://outputs/verification/facility_light_initial.png"
const OFF_OUTPUT := "res://outputs/verification/facility_light_off.png"
const REOPEN_OUTPUT := "res://outputs/verification/facility_light_reopened.png"
const FLOOR_SAMPLE_OFFSETS := [
	Vector3(-10.0, 0.06, -10.0), Vector3(0.0, 0.06, -10.0),
	Vector3(10.0, 0.06, -10.0), Vector3(-10.0, 0.06, 0.0),
	Vector3.ZERO, Vector3(10.0, 0.06, 0.0),
	Vector3(-10.0, 0.06, 10.0), Vector3(0.0, 0.06, 10.0),
	Vector3(10.0, 0.06, 10.0),
]

var _inspection_camera: Camera3D


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	if tower == null:
		_finish(["无法实例化正式塔楼场景"])
		return
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle(10)

	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		_finish(["99F基地房间不存在"])
		return
	facility.ensure_detail_built()
	tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
	tower.force_enter_room_for_test("facility")
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D")
	if flashlight != null and flashlight.has_method("set_light_enabled"):
		flashlight.call("set_light_enabled", false)
	tower.player.visible = false
	for layer in tower.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false

	_inspection_camera = Camera3D.new()
	_inspection_camera.name = "FacilitySingleLightInspectionCamera"
	_inspection_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_inspection_camera.size = 31.5
	tower.add_child(_inspection_camera)
	_inspection_camera.global_position = facility.to_global(Vector3(0.0, 7.55, 0.0))
	_inspection_camera.look_at(facility.to_global(Vector3.ZERO), Vector3.FORWARD)
	_inspection_camera.current = true
	await _settle()

	var room_snapshot := facility.get_room_snapshot()
	if (
		int(room_snapshot.get("controlled_light_count", 0)) != 1
		or int(room_snapshot.get("light_count", 0)) != 1
		or int(room_snapshot.get("active_shadow_light_count", 0)) != 1
	):
		failures.append("99F基地没有收敛为一盏可控、可投影中央灯：%s" % room_snapshot)
	var active_initial := _count_active_base_omni_lights(tower, facility)
	if active_initial != 1:
		failures.append("99F基地开灯时实际活动OmniLight不是1盏：%d" % active_initial)
	var main_light := facility.find_child("FacilityCeilingLight_Main", true, false) as WastelandLight3D
	if main_light == null:
		failures.append("99F基地中央主灯节点不存在")
	else:
		var light_snapshot := main_light.get_snapshot()
		if float(light_snapshot.get("range", 0.0)) < 28.0:
			failures.append("99F基地中央主灯范围不足28m：%s" % light_snapshot)

	var light_switch := facility.get_node_or_null("RuntimeDetail/RoomLightSwitch3D") as RoomLightSwitch3D
	if light_switch == null:
		light_switch = facility.find_child("RoomLightSwitch3D", true, false) as RoomLightSwitch3D
	if light_switch == null:
		_finish(["99F基地灯光开关不存在"])
		return

	var initial := get_viewport().get_texture().get_image()
	var initial_samples := _sample_floor_luminances(initial, facility)
	var initial_luminance := _average(initial_samples)
	_save_image(initial, INITIAL_OUTPUT, failures)

	light_switch.toggle_light()
	await _settle()
	var off := get_viewport().get_texture().get_image()
	var off_samples := _sample_floor_luminances(off, facility)
	var off_luminance := _average(off_samples)
	_save_image(off, OFF_OUTPUT, failures)
	if _count_active_base_omni_lights(tower, facility) != 0:
		failures.append("基地关灯后仍有活动OmniLight照射99F地板")

	light_switch.toggle_light()
	await _settle()
	var reopened := get_viewport().get_texture().get_image()
	var reopened_samples := _sample_floor_luminances(reopened, facility)
	var reopened_luminance := _average(reopened_samples)
	_save_image(reopened, REOPEN_OUTPUT, failures)
	if _count_active_base_omni_lights(tower, facility) != 1:
		failures.append("基地重开后没有恢复且仅恢复一盏OmniLight")

	if initial_luminance < off_luminance + 0.035:
		failures.append(
			"单灯对基地九点地板的基础增亮不足：initial=%.4f off=%.4f"
			% [initial_luminance, off_luminance]
		)
	if reopened_luminance < off_luminance + 0.035:
		failures.append(
			"基地关后再开没有恢复九点地板照明：off=%.4f reopened=%.4f"
			% [off_luminance, reopened_luminance]
		)
	if absf(reopened_luminance - initial_luminance) > 0.025:
		failures.append(
			"基地重开亮度没有恢复初始值：initial=%.4f reopened=%.4f"
			% [initial_luminance, reopened_luminance]
		)
	var covered_sample_count := 0
	for sample_index in mini(initial_samples.size(), off_samples.size()):
		if initial_samples[sample_index] >= off_samples[sample_index] + 0.02:
			covered_sample_count += 1
	if covered_sample_count < 8:
		failures.append(
			"中央单灯只明显照亮九点中的%d点，未覆盖基地大部分范围"
			% covered_sample_count
		)

	if failures.is_empty():
		print(
			(
				"FACILITY_LIGHT_RETOGGLE_VISUAL_OK: active_omni=1 range>=28m coverage=%d/9 "
				+ "nine_point_initial=%.4f off=%.4f reopened=%.4f"
			)
			% [covered_sample_count, initial_luminance, off_luminance, reopened_luminance]
		)
		get_tree().quit(0)
		return
	_finish(failures)


func _count_active_base_omni_lights(tower: TowerDescent3D, facility: DungeonRoom3D) -> int:
	var dimensions := facility.get_dimensions()
	var count := 0
	for value in tower.find_children("*", "OmniLight3D", true, false):
		var light := value as OmniLight3D
		if light == null or not light.visible or light.light_energy <= 0.001:
			continue
		var local_position := facility.to_local(light.global_position)
		if (
			absf(local_position.x) <= dimensions.x * 0.5 + 0.5
			and absf(local_position.z) <= dimensions.y * 0.5 + 0.5
			and local_position.y >= -0.5
			and local_position.y <= 9.5
		):
			count += 1
	return count


func _sample_floor_luminances(image: Image, facility: DungeonRoom3D) -> Array[float]:
	if image == null or image.is_empty() or _inspection_camera == null:
		return []
	var result: Array[float] = []
	for offset in FLOOR_SAMPLE_OFFSETS:
		var total := 0.0
		var sample_count := 0
		var screen_position := _inspection_camera.unproject_position(
			facility.to_global(offset as Vector3)
		)
		var center := Vector2i(roundi(screen_position.x), roundi(screen_position.y))
		for y in range(center.y - 5, center.y + 6):
			if y < 0 or y >= image.get_height():
				continue
			for x in range(center.x - 5, center.x + 6):
				if x < 0 or x >= image.get_width():
					continue
				total += image.get_pixel(x, y).get_luminance()
				sample_count += 1
		result.append(total / float(maxi(1, sample_count)))
	return result


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return -1.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _settle(frame_count := 5) -> void:
	for _frame in range(frame_count):
		await get_tree().process_frame
	await get_tree().create_timer(0.08).timeout


func _save_image(image: Image, path: String, failures: Array[String]) -> void:
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append("无法保存灯光回归图：%s" % path)


func _finish(failures: Array[String]) -> void:
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
