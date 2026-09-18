extends Node

const ZONE_PATH := "res://assets/art/environments/tower_zones/base/runtime/zone_base.tscn"

func _ready() -> void:
	var failures: Array[String] = []
	var scene := load(ZONE_PATH) as PackedScene
	_expect(scene != null, "zone_base.tscn 加载失败", failures)
	if scene != null:
		var zone := scene.instantiate()
		add_child(zone)
		await get_tree().process_frame
		var platform := zone.find_child("51_圆形全息设备平台_资产包", true, false) as BaseFacility3D
		_expect(platform != null, "中央圆形全息平台没有包装为BaseFacility3D", failures)
		if platform != null:
			_expect(platform.facility_id == "mission_operations", "中央平台facility_id不是mission_operations", failures)
			_expect(platform.display_name == "远征情报室", "中央平台名称不是远征情报室", failures)
			var interaction := platform.get_node_or_null("InteractionShape") as CollisionShape3D
			_expect(interaction != null, "中央平台缺少E键交互范围", failures)
			if interaction != null:
				_expect(interaction.position.is_equal_approx(Vector3(5, 1.5, -1.72)), "E键热区未对准圆盘", failures)
			_expect(platform.get_node_or_null("PromptLabel") != null, "中央平台缺少交互提示", failures)
			_expect(platform.get_node_or_null("ImportedModel") != null, "中央平台原有全息模型丢失", failures)
			_expect(zone.find_child("远征情报终端", true, false) == null, "旧墙边远征终端仍存在，产生重复入口", failures)
			platform.call("_on_body_entered", _make_probe_body())
			var candidate := platform.get_interaction_candidate(null)
			_expect(bool(candidate.get("available", false)), "中央平台靠近后未提供交互候选", failures)
			_expect((candidate.get("position", Vector3.ZERO) as Vector3).is_equal_approx(platform.to_global(Vector3(5, 0, -1.72))), "交互距离排序未使用圆盘中心", failures)
			_expect(str(candidate.get("prompt", "")).contains("远征情报室"), "中央平台提示未指向远征情报室", failures)
		zone.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("CENTRAL_EXPEDITION_HOLOGRAM_FACILITY_OK facility=mission_operations e_key=ready")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)

func _make_probe_body() -> Node3D:
	var body := CharacterBody3D.new()
	body.add_to_group("player_3d")
	add_child(body)
	return body

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
