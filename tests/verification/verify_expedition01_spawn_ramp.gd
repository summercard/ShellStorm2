extends Node
## 远征01首关13房小改运行数据门禁。
## 读取运行投影，不改任何源文件；Python 门禁另行核对基线拓扑与 SHA。

const LEVEL_PATH := "res://data/level_plans/expedition_01/level_plan.json"
const FLOOR_PATH := "res://data/level_plans/expedition_01/floors/floor_00.json"

var failures: Array[String] = []

func _ready() -> void:
	var level := _load_json(LEVEL_PATH)
	var floor := _load_json(FLOOR_PATH)
	if level.is_empty() or floor.is_empty():
		_fail("运行投影 JSON 无法读取")
	else:
		_verify_floor(level, floor)
		_verify_rewards(level)
		_verify_boss(floor)
	if failures.is_empty():
		print("EXPEDITION01_SPAWN_RAMP_RUNTIME_DATA_OK rooms=13 ammo=2200 potions=5")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("EXPEDITION01_SPAWN_RAMP_RUNTIME_DATA_FAIL " + failure)
	get_tree().quit(1)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("缺少运行文件: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_fail("JSON 根不是对象: %s" % path)
		return {}
	return parsed as Dictionary

func _verify_floor(level: Dictionary, floor: Dictionary) -> void:
	var rooms := floor.get("rooms", []) as Array
	_check(rooms.size() == 13, "房间数不是13")
	var by_key := {}
	for room_value in rooms:
		var room := room_value as Dictionary
		by_key[str(room.get("key", ""))] = room
	for key in ["entry", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06", "room_07", "room_08", "room_09", "room_10", "boss", "extraction"]:
		_check(by_key.has(key), "缺少房间 %s" % key)
	for key in ["room_03", "room_04", "room_06", "room_09", "room_10"]:
		var encounter := (by_key.get(key, {}) as Dictionary).get("encounter", {}) as Dictionary
		_check(float(encounter.get("duration_sec", -1.0)) == 0.0, "%s duration_sec 不是0" % key)
		_check(str(encounter.get("completion", "")) == "clear", "%s completion 不是clear" % key)
		_check(str(encounter.get("stage_advance", "")) == "clear", "%s stage_advance 不是clear" % key)
		_check(is_equal_approx(float(encounter.get("min_player_distance_m", -1.0)), 6.0), "%s 最小距离不是6" % key)
	_check(float(((by_key["room_03"] as Dictionary).get("encounter", {}) as Dictionary).get("stages", [])[0].get("monsters", [])[0].get("min_player_distance_m", -1.0)) == 8.0, "03首只胖子距离不是8")
	_check(float((((by_key["room_02"] as Dictionary).get("encounter", {}) as Dictionary).get("monster_ai", {}) as Dictionary).get("alert_share_radius_m", -1.0)) == 10.0, "02警戒共享半径不是10")
	_check((level.get("generation_policy", {}) as Dictionary).get("runtime_enabled", false), "runtime_enabled 未开启")

func _verify_rewards(level: Dictionary) -> void:
	var clear_drops := level.get("clear_drops", {}) as Dictionary
	var overrides := clear_drops.get("room_overrides", {}) as Dictionary
	var ammo := 100
	var potions := 0
	for room_value in overrides.values():
		var room_override := room_value as Dictionary
		for grant_value in room_override.get("grants", []) as Array:
			var grant := grant_value as Dictionary
			if str(grant.get("item_id", "")) == "item_ammo_pack":
				ammo += int(grant.get("count", 0))
			elif str(grant.get("item_id", "")) == "item_health_potion":
				potions += int(grant.get("count", 0))
	_check(ammo == 2200, "普通弹药总量不是2200: %d" % ammo)
	_check(potions == 5, "药水总量不是5: %d" % potions)
	var guarantee := (clear_drops.get("room_guarantees", []) as Array)[0] as Dictionary
	_check(str(guarantee.get("bullet_module_id", "")) == "mod_bullet_standard", "首枪保底不是标准弹")
	var room_overrides := overrides
	for room_id in ["room_01", "room_02", "room_07", "room_09", "room_10"]:
		_check(float((room_overrides.get(room_id, {}) as Dictionary).get("mimic_chance", -1.0)) == 0.0, "%s 未禁拟态" % room_id)
	var purple := (room_overrides.get("room_07", {}) as Dictionary).get("additional_weapon", {}) as Dictionary
	_check(str(purple.get("grade", "")) == "purple", "07追加武器品质不是purple")
	_check(str(purple.get("bullet_module_id", "")) == "mod_bullet_standard", "07追加武器不是标准弹")

func _verify_boss(floor: Dictionary) -> void:
	var boss := {}
	for value in floor.get("rooms", []) as Array:
		var room := value as Dictionary
		if str(room.get("key", "")) == "boss":
			boss = room.get("boss_reinforcement_plan", {}) as Dictionary
	_check(float(boss.get("activation_delay_sec", -1.0)) == 12.0, "Boss首轮延迟不是12")
	_check(float(boss.get("initial_interval_sec", -1.0)) == 9.0, "Boss援军间隔不是9")
	_check(int(boss.get("initial_count", -1)) == 3 and int(boss.get("max_count_per_round", -1)) == 3, "Boss援军不是固定3")
	_check(int(boss.get("max_reinforcement_alive", -1)) == 6, "Boss动态上限不是6")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_fail(message)

func _fail(message: String) -> void:
	failures.append(message)
