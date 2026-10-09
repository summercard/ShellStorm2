extends Node
## 99F收音机空间声场专项：只检查真实单声源参数、可量化增益与楼层启停，不播放第二声源。

const RADIO_SCENE_PATH := "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"
const OUT := "res://outputs/base99_radio_sound_v001"

var failures: Array[String] = []
var evidence: Dictionary = {"checks": [], "measurements": []}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var radio := (load(RADIO_SCENE_PATH) as PackedScene).instantiate() as Base99Radio3D
	if radio == null:
		_fail("radio prefab 无法实例化")
		_finish()
		return
	add_child(radio)
	await get_tree().process_frame
	var player := radio.audio_player
	_check(player != null, "唯一AudioStreamPlayer3D存在")
	if player == null:
		_finish()
		return
	_check(radio.get_node("AudioStreamPlayer3D") == player, "实际声源只有prefab内唯一AudioStreamPlayer3D")
	_check(not player.playing and player.stream == null, "off无声且无stream")
	_check(is_equal_approx(player.unit_size, 18.0), "unit_size=18.0m")
	_check(is_equal_approx(player.max_distance, 78.0), "max_distance=78.0m")
	_check(player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE, "attenuation_model=inverse_square")
	_check(radio.get_meta("audio_spatial_contract", "") != "", "runtime prefab metadata声明空间声音契约")

	var source := radio.global_position
	var near := source + Vector3(2.0, 0.0, 0.0)
	var far := Vector3(49.0, source.y, source.z)
	var edge_out := Vector3(51.0, source.y, source.z)
	var far_out := Vector3(56.0, source.y, source.z)
	var near_sample := radio.get_spatial_audio_snapshot(near)
	var far_sample := radio.get_spatial_audio_snapshot(far)
	var edge_sample := radio.get_spatial_audio_snapshot(edge_out)
	var far_out_sample := radio.get_spatial_audio_snapshot(far_out)
	_measure("near_inside", near_sample)
	_measure("far_inside", far_sample)
	_measure("edge_outside", edge_sample)
	_measure("far_outside", far_out_sample)
	_check(bool(near_sample.inside_base99) and bool(far_sample.inside_base99), "99F内近处/远端均在正式基地边界内")
	_check(float(far_sample.effective_gain) < float(near_sample.effective_gain), "99F内远端受距离衰减且低于近处")
	_check(float(edge_sample.effective_gain) < float(far_sample.effective_gain) * 0.2, "基地外边界同距离声级明显更低")
	_check(float(far_out_sample.effective_gain) < float(edge_sample.effective_gain), "继续离开基地后继续更强衰减")
	_check(float(edge_sample.source_volume_db) <= -18.0 and float(edge_sample.source_volume_db) > -23.0, "基地外1m额外衰减约-22dB")
	_check(float(far_out_sample.source_volume_db) <= -38.0, "基地外5m额外衰减至少-38dB")

	radio.set_radio_state("a")
	await get_tree().process_frame
	_check(player.playing and player.stream != null, "开启A后唯一声源有效播放")
	var live_count := int(get_tree().get_nodes_in_group("base99_radio_3d").size())
	_check(live_count == 1, "测试场景仅有一个收音机声源宿主")
	radio.set_floor_active(false)
	_check(radio.radio_state == "off" and not player.playing and player.stream == null, "离开99F立即停播且off无声")
	radio.set_floor_active(true)
	_check(radio.radio_state == "off" and not player.playing, "返回99F可播但不自动恢复")
	radio.set_radio_state("b")
	_check(radio.radio_state == "b" and player.playing, "返回99F后手动开启可播")
	radio.set_floor_active(false)
	_check(radio.radio_state == "off" and not player.playing, "再次离开99F停播")
	radio.free()
	_finish()

func _measure(label: String, sample: Dictionary) -> void:
	evidence.measurements.append({"label": label, "snapshot": sample})

func _check(condition: bool, label: String) -> void:
	evidence.checks.append({"label": label, "passed": condition})
	if not condition:
		_fail(label)

func _fail(label: String) -> void:
	failures.append(label)

func _finish() -> void:
	evidence["passed"] = failures.is_empty()
	evidence["failures"] = failures
	var file := FileAccess.open(OUT + "/sound_acceptance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "  "))
	file.close()
	if failures.is_empty():
		print("BASE99_RADIO_SOUND_OK: checks=%d measurements=%d" % [evidence.checks.size(), evidence.measurements.size()])
	else:
		for failure in failures:
			push_error("BASE99_RADIO_SOUND_FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
