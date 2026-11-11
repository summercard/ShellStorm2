extends Node
## 纯数据专项：不实例化 Dungeon/Room，不读写 user://，不推进真实关卡。
const CATALOG = preload("res://src/map/SpawnBoxCatalog.gd")
const VALIDATOR = preload("res://src/map/LevelPlanValidator.gd")
const LOADER = preload("res://src/map/LevelPlanLoader.gd")
const GENERATOR = preload("res://src/map/FloorPlanGenerator.gd")
var failures: Array[String] = []
var samples := 0


func _check(ok: bool, message: String) -> void:
	samples += 1
	if not ok:
		failures.append(message)


func _placement_errors(placement: Dictionary) -> Array[String]:
	return VALIDATOR._validate_spawn_boxes(
		[{"key": "probe", "content_type": "COMBAT", "spawn_placements": [placement]}],
		{"probe": Vector2.ZERO}, {"probe": Vector2(80, 80)},
		{"geometry_authoritative": false}
	)


func _ready() -> void:
	var placement := {
		"box": "box_center_elite", "center_m": [2.5, 2.5], "count_bonus": 2,
		"count_multiplier": 3, "delay_sec": 4.0,
		"spawn_overrides": [
			{"type": "melee_chaser", "count": {"min": 1, "max": 2}},
			{"type": "melee_chaser_strong", "count": 1, "delay_sec": 0.5},
		],
	}
	var original := placement.duplicate(true)
	var shared := CATALOG.load_box("box_center_elite")
	var resolved := CATALOG.resolve_placement_box(placement)
	_check(not resolved.is_empty() and resolved["spawns"].size() == 2, "覆盖未完整替换清单")
	_check(resolved["spawns"][0] == {"type": "melee_chaser", "count_min": 1, "count_max": 2, "delay_sec": 0.0}, "区间归一、顺序或数量被提前放大")
	_check(resolved["spawns"][1] == {"type": "melee_chaser_strong", "count_min": 1, "count_max": 1, "delay_sec": 0.5}, "强化条目归一错误或提前吃bonus/额外延迟")
	for key in shared:
		if key != "spawns":
			_check(resolved[key] == shared[key], "覆盖导致盒几何/落点策略漂移：%s" % key)
	_check(placement == original, "解析修改了placement输入")
	_check(_placement_errors(placement).is_empty(), "Validator拒绝合法覆盖")
	resolved["spawns"][0]["count_min"] = 999
	resolved["spawns"].clear()
	_check(CATALOG.load_box("box_center_elite") == shared, "修改解析结果污染共享缓存")
	_check(CATALOG.resolve_placement_box(placement)["spawns"].size() == 2, "修改解析结果污染覆盖输入或下次解析")
	var json_placement: Variant = JSON.parse_string(JSON.stringify(placement))
	_check(CATALOG.resolve_placement_box(json_placement as Dictionary) == CATALOG.resolve_placement_box(placement), "JSON往返后覆盖行为漂移")
	for invalid in [[], null, {}, "spawns", [null], [{"type": "elite_typo", "count": 1}], [{"type": "egt_unknown", "count": 1}]]:
		var probe := placement.duplicate(true)
		probe["spawn_overrides"] = invalid
		_check(CATALOG.resolve_placement_box(probe).is_empty(), "非法/空覆盖回退共享盒：%s" % str(invalid))
		_check(not _placement_errors(probe).is_empty(), "Validator漏拒非法覆盖：%s" % str(invalid))
	for count in [0, -1, 1.5, 1.000001, false, true, "2", null, INF, NAN, {"min": 2}, {"min": 2, "max": 1}, {"min": 1, "max": 2.1}, {"min": 1, "max": 2, "typo": 1}]:
		var entry := {"type": "melee_chaser", "count": count}
		var probe := placement.duplicate(true)
		probe["spawn_overrides"] = [entry]
		_check(CATALOG.resolve_placement_box(probe).is_empty(), "count被截断或非法范围放行：%s" % str(count))
		_check(not CATALOG.validate_spawn_entries([entry]).is_empty(), "共用count校验漏拒：%s" % str(count))
	for delay in [-1, "0", false, null, INF, NAN]:
		var entry := {"type": "melee_chaser", "count": 1, "delay_sec": delay}
		_check(not CATALOG.validate_spawn_entries([entry]).is_empty(), "非法delay放行：%s" % str(delay))
	_check(CATALOG.resolve_placement_box({}).is_empty(), "缺少盒引用未拒绝")
	_check(CATALOG.resolve_placement_box({"box": "unknown_box"}).is_empty(), "未登记盒引用未拒绝")
	for valid_count in [2, 2.0, {"min": 1.0, "max": 2.0}, 16777217]:
		var probe := placement.duplicate(true)
		probe["spawn_overrides"] = [{"type": "melee_chaser", "count": valid_count}]
		var result := CATALOG.resolve_placement_box(probe)
		_check(not result.is_empty(), "合法整数count被拒绝：%s" % str(valid_count))
		if valid_count is int:
			_check(result["spawns"][0]["count_min"] == valid_count, "整数count归一被浮点精度篡改：%s" % str(valid_count))
	var forged := placement.duplicate(true)
	forged["spawn_overrides"] = [{"type": "melee_chaser", "count": 1, "count_min": 99}]
	_check(CATALOG.resolve_placement_box(forged).is_empty(), "伪造归一count字段放行")
	var typo := placement.duplicate(true)
	typo["spawn_override"] = []
	_check(_placement_errors(typo).has("spawn_placement_unknown_field:probe[0]:spawn_override"), "placement未知键未严格拒绝")
	var identities := placement.duplicate(true)
	identities["spawn_overrides"] = [{"type": "elite", "count": 1}, {"type": "boss", "count": 2}]
	var identity_box := CATALOG.resolve_placement_box(identities)
	_check(identity_box["spawns"][0]["count_min"] == 1 and identity_box["spawns"][1]["count_min"] == 2, "身份条目被解析器预乘或加bonus")
	var mixed_identities := identities.duplicate(true)
	mixed_identities["spawn_overrides"].append({"type": "melee_chaser", "count": 2})
	var mixed_box := CATALOG.resolve_placement_box(mixed_identities)
	_check(mixed_box["spawns"][0]["count_min"] == 1 and mixed_box["spawns"][1]["count_min"] == 2 and mixed_box["spawns"][2]["count_min"] == 2, "混合身份清单被提前应用倍率/bonus")
	_check(_placement_errors(mixed_identities).is_empty(), "身份条目之后有普通怪仍误判bonus无作用")
	var identity_errors := _placement_errors(identities)
	_check(identity_errors.has("spawn_placement_count_bonus_never_applies:probe[0]:box_center_elite"), "全身份覆盖未保留bonus不生效门禁")
	_check(identity_errors.has("spawn_placement_count_multiplier_never_applies:probe[0]:box_center_elite"), "全身份覆盖未保留倍率不生效门禁")
	for box_id in CATALOG.all_ids():
		var legacy := CATALOG.load_box(str(box_id))
		_check(not legacy.is_empty() and CATALOG.resolve_placement_box({"box": box_id}) == legacy, "旧共享盒行为变化：%s" % box_id)
		var raw := LOADER.read_json(CATALOG.path_for(str(box_id)))
		_check(CATALOG.validate_box(raw).is_empty(), "旧共享盒严格校验回归：%s" % box_id)
		var poisoned := raw.duplicate(true)
		poisoned["spawns"][0]["count"] = 1.5
		_check(not CATALOG.validate_box(poisoned).is_empty(), "共享盒未复用严格count校验：%s" % box_id)
	_verify_projection()
	if failures.is_empty():
		print("SPAWN_PLACEMENT_OVERRIDES_OK samples=%d" % samples)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_projection() -> void:
	var overrides := 0
	for level_id in ["expedition_01", "expedition_02", "expedition_03"]:
		var source := LOADER.load_floor_plan(level_id, 0)
		var normalized := LOADER.normalize_floor(level_id, 0)
		_check(not source.is_empty() and not normalized.get("rooms", []).is_empty(), "归一测试源缺失：%s" % level_id)
		for raw_value in source.get("rooms", []):
			var raw := raw_value as Dictionary
			for value in normalized.get("rooms", []):
				var room := value as Dictionary
				if room.get("key") != raw.get("key"):
					continue
				var expected := raw.get("spawn_placements", []) as Array
				_check(room["spawn_placements"] == expected, "Loader丢失placement字段：%s/%s" % [level_id, str(room.get("key"))])
				var record := GENERATOR.room_from_source(room)
				_check(record["spawn_placements"] == expected, "Generator丢失placement字段")
				_check(record["position"] == room["center"] and record["dimensions"] == room["size"], "Generator地形归一漂移")
				for placement_value in expected:
					var placement := placement_value as Dictionary
					if placement.has("spawn_overrides"):
						overrides += 1
						_check(not CATALOG.resolve_placement_box(placement).is_empty(), "生产覆盖无法解析：%s/%s" % [level_id, str(room.get("key"))])
				if not expected.is_empty():
					(record["spawn_placements"][0] as Dictionary)["box"] = "mutated"
					_check(room["spawn_placements"] == expected, "Generator修改结果污染Loader源")
	_check(overrides == 4, "本关四个override未完整透传：%d" % overrides)
	print("SPAWN_PLACEMENT_PROJECTION overrides=%d" % overrides)
