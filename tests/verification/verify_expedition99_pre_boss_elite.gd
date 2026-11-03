extends Node
## 房间级「额外追加一只指定精英」契约：远征 99 boss 前置房 room_01 出夺械者“收租人”。
##
## 这条改动跨了 **5 个文件**（数据源 → 关卡计划白名单 → 关卡加载 → 房间装配 → 怪物生成），
## 是 AGENTS.md 点名的「跨文件隐形契约」，所以必须有会失败的断言盯着 ——
## 缺任何一环的表现都是「设计源写了，运行时房间里没有这只怪」，且**不打任何日志**。
##
## 本验收逐环验证，并对每一环给出**反证**（不满足时必须红）：
##   1. `FloorPlanGenerator.room_from_source` 出口白名单是否放行 `elite_id`
##   2. 设计源（`data/level_plans/99` 投影）里 room_01 声明了、其余房间没声明
##   3. 关卡校验器不把新字段当非法输入拒掉
##   4. `DungeonRoom3D.configure` 真的把 `elite_id` 落到房间上
##   5. **点名生成**能出这只（且绕过了楼层窗口）
##   6. **反证**：不点名时 100 层出不来的（证明窗口没被放宽，绕过是真的）
##   7. 普通战斗与房间身份未被改动（`room_type` / `content_type` 原样）

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")

const LEVEL := "99"
const ROOM_KEY := "room_01"
const ELITE_ID := "elite_arms_taker"
const ASSET_ID := "ENM-ELITE-ARMS-TAKER-3D"
const TEMP_SAVE := "user://verify_expedition99_pre_boss_elite.json"

## 远征关卡是单层：`floor_index = 0` ⇒ `floor_number = 100 - 0 = 100`
## （`TowerDescent3D._organize_existing_rooms_by_block`）。
## 而「收租人」的名册窗口是 94/93/92 ⇒ **不点名就永远出不来**。本常量是第 6 条反证的依据。
const EXPEDITION_FLOOR_NUMBER := 100


func _ready() -> void:
	var failures: Array[String] = []
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()

	_check_record_whitelist(failures)
	_check_design_source(failures)
	_check_validator(failures)
	_check_room_configure(failures)
	_check_named_spawn(failures)
	_check_window_untouched(failures)

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
	if failures.is_empty():
		print("EXP99_PRE_BOSS_ELITE_OK: room_01 declares elite_arms_taker, record whitelist/loader/room/ spawn chain verified, ordinary combat and roster window untouched")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 1. 出口白名单：`room_from_source` 不登记就会静默丢弃（本工程已踩过三次）。
func _check_record_whitelist(failures: Array[String]) -> void:
	var record := GENERATOR.room_from_source({
		"key": ROOM_KEY, "room_type": "COMMON_ROOM", "role": "main",
		"center_m": [0.0, 0.0], "size_m": [25.0, 25.0],
		"content_type": "COMBAT",
		"elite_id": ELITE_ID,
	})
	if str(record.get("elite_id", "")) != ELITE_ID:
		failures.append("FloorPlanGenerator.room_from_source dropped elite_id (output whitelist)")
	# 反证：不声明时必须为空串，不能凭空塞一个默认精英。
	var plain := GENERATOR.room_from_source({
		"key": ROOM_KEY, "room_type": "COMMON_ROOM", "role": "main",
		"center_m": [0.0, 0.0], "size_m": [25.0, 25.0],
	})
	if not str(plain.get("elite_id", "x")).is_empty():
		failures.append("room_from_source invented an elite_id for a room that declared none")


## 2. 设计源：room_01 声明了，其余房间没有。且投影目录已同步（--check 同口径）。
func _check_design_source(failures: Array[String]) -> void:
	if not LOADER.has_level_plan(LEVEL):
		failures.append("level plan 99 not found")
		return
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	var rooms := normalized.get("rooms", []) as Array
	if rooms.is_empty():
		failures.append("level plan 99 normalized to zero rooms")
		return
	var declared: Array[String] = []
	var target_found := false
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", room.get("room_id", "")))
		var elite := str(room.get("elite_id", ""))
		if not elite.is_empty():
			declared.append("%s=%s" % [key, elite])
		if key == ROOM_KEY:
			target_found = true
			if elite != ELITE_ID:
				failures.append("%s does not declare %s (got '%s')" % [ROOM_KEY, ELITE_ID, elite])
			# 7. 普通战斗与房间身份必须原样 —— 本改动是「追加」，不是「改成精英房」。
			if str(room.get("room_type", "")) != "COMMON_ROOM":
				failures.append("%s room_type changed to %s (must stay COMMON_ROOM)" % [ROOM_KEY, str(room.get("room_type", ""))])
			if str(room.get("content_type", "")) != "COMBAT":
				failures.append("%s content_type changed to %s (must stay COMBAT)" % [ROOM_KEY, str(room.get("content_type", ""))])
	if not target_found:
		failures.append("level plan 99 has no room keyed %s" % ROOM_KEY)
	# 只有 room_01 声明 —— 其他房间若也被写上，等于在无关房间凭空刷精英。
	if declared.size() != 1:
		failures.append("expected exactly one room declaring elite_id, got %s" % str(declared))


## 3. 关卡校验器不得把新字段当非法输入。
func _check_validator(failures: Array[String]) -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var errors := VALIDATOR.validate_floor(LEVEL, 0, policy, templates)
	if not errors.is_empty():
		failures.append("LevelPlanValidator rejected level plan 99 after adding elite_id: %s" % str(errors))


## 4. 房间装配：configure 必须把字段落到房间上（否则消费端读到空串）。
func _check_room_configure(failures: Array[String]) -> void:
	var room := DungeonRoom3D.new()
	room.configure({"room_id": ROOM_KEY, "room_type": "COMMON_ROOM", "elite_id": ELITE_ID})
	if room.elite_id != ELITE_ID:
		failures.append("DungeonRoom3D.configure did not apply elite_id (got '%s')" % room.elite_id)
	var plain := DungeonRoom3D.new()
	plain.configure({"room_id": ROOM_KEY, "room_type": "COMMON_ROOM"})
	if not plain.elite_id.is_empty():
		failures.append("DungeonRoom3D.configure invented an elite_id when none was declared")
	room.free()
	plain.free()


## 5. 点名生成：能出这只，且身份/表现资产正确。
func _check_named_spawn(failures: Array[String]) -> void:
	var injector := MonsterInjector.new()
	var generated := injector.generate_enemies({
		"type": "elite",
		"floor": 1,
		"floor_level": RoomData.FloorLevel.SHALLOW,
		"floor_number": EXPEDITION_FLOOR_NUMBER,
		"encounter_id": "verify_exp99:room_01:elite",
		"seed": 99001,
		"elite_id": ELITE_ID,
	})
	if generated.size() != 1:
		failures.append("named elite spawn produced %d enemies (expected 1)" % generated.size())
		return
	var config := generated[0]
	if not bool(config.get("is_elite", false)):
		failures.append("named spawn did not mark the enemy as elite")
	if str(config.get("elite_id", "")) != ELITE_ID:
		failures.append("named spawn resolved the wrong elite: '%s'" % str(config.get("elite_id", "")))
	if str(config.get("presentation_asset_id", "")) != ASSET_ID:
		failures.append("named spawn lost the presentation AssetID: '%s'" % str(config.get("presentation_asset_id", "")))
	var scene := str(config.get("presentation_scene", ""))
	if not scene.contains("enm_elite_arms_taker"):
		failures.append("named spawn lost the presentation scene: '%s'" % scene)
	# 只出这一只：不能顺带把兄弟精英也带出来。
	if generated.size() != 1:
		failures.append("named spawn produced extra enemies")


## 6. 反证 + 名册未被污染：
##    - 不点名时 100 层出不来（证明窗口没被放宽）；
##    - `get_deployable_for_floor(100)` 仍为空（证明没往窗口里塞 100）。
func _check_window_untouched(failures: Array[String]) -> void:
	EliteRosterService.reset_roster_for_test()
	if not EliteContentCatalog.get_deployable_for_floor(EXPEDITION_FLOOR_NUMBER).is_empty():
		failures.append(
			"roster window was polluted: floor %d now deploys an elite without being named"
			% EXPEDITION_FLOOR_NUMBER
		)
	var injector := MonsterInjector.new()
	var unnamed := injector.generate_enemies({
		"type": "elite",
		"floor": 1,
		"floor_level": RoomData.FloorLevel.SHALLOW,
		"floor_number": EXPEDITION_FLOOR_NUMBER,
		"encounter_id": "verify_exp99:unnamed",
		"seed": 99002,
	})
	if not unnamed.is_empty():
		failures.append(
			"unnamed elite spawn on floor %d produced an enemy (window must still block it)"
			% EXPEDITION_FLOOR_NUMBER
		)
	# 收租人自己的窗口必须原样保留。
	for floor_number in [94, 93, 92]:
		var eligible := EliteContentCatalog.get_deployable_for_floor(floor_number)
		var ids: Array[String] = []
		for definition in eligible:
			ids.append(str(definition.get("elite_id", "")))
		if ids != [ELITE_ID]:
			failures.append("floor %d roster drifted: %s" % [floor_number, str(ids)])
