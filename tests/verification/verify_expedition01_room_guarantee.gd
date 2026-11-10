extends Node
## 远征01「第一或第二个房间的宝箱必掉一把蓝品霰弹枪/步枪 + 100 发通用弹药」专项。
##
## 业主要求（2026-11-09）：那把枪**要么在第一个房间、要么在第二个房间**，随机一间掉；
## 一起掉的还有一组 100 发普通弹药。
##
## 本用例只验**纯服务层**（配置解析 → 选房 → 箱子配置 → 宝箱奖励解析），
## 不建世界、不刷怪、不真开箱。判据分五组：
##   A  结构：`clear_drops.room_guarantees` 存在且能被 `ClearDropService.configure()` 接受；
##   A2 ID 口径（2026-11-10 新增）：候选房 id 必须出现在**运行时**房间 id 集合里；
##   B  选址：每个 seed 恰好命中候选房之一，且同 seed 多次调用结果不变；
##   C  内容：命中房里是「1 把 {散射喷壶, 步枪} 中的一把 + grade=blue」和「item_ammo_pack ×100」；
##   D  落地：`ChestRewardService.resolve()` 真产出蓝品枪 grant 与 100 发弹药 grant（防 `_unit_grants` 把 100 拍成 1）。
## 另加反向对照：抹掉 `room_guarantees` 后必须什么都不保底，证明上面的绿不是恒真。
##
## ⚠ **A2 组是一次实测事故的补丁（2026-11-10）**：原用例把候选房硬编码成
## `["f00_room_01","f00_room_02"]`，直接拿**配置里的字串**去问服务 —— 自己跟自己对答案。
## 而运行时房间 id 由 `FloorPlanGenerator.room_from_source()` 决定，**优先取
## `legacy_room_id`**（远征01 是 `room_01` / `room_02`），两个串永远不相等 ⇒
## `guaranteed_items_for_room()` 恒返回空、两个清房箱都不带保底，
## 用例却一直全绿（实测 13 间房 RUNTIME_HITS=0）。所以本用例现在必须：
##   1. 跑一次 `generate_from_level_plan()` 取**真实运行时 id**；
##   2. 用真实 id 跑 B/C/D 三组；
##   3. 显式断言「配置里的候选房 ∈ 运行时 id 集合」。

const CLEAR_DROP_SCRIPT := preload("res://src/game/ClearDropService.gd")
const CHEST_REWARD_SERVICE := preload("res://src/rewards/ChestRewardService.gd")
const FLOOR_PLAN_GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const PLAN_PATH := "res://data/level_plans/expedition_01/level_plan.json"
const LEVEL_ID := "expedition_01"
const GUARANTEE_ID := "exp01_opening_weapon_or_ammo"
const CANDIDATE_GUNS: Array[String] = ["weapon_shotgun", "weapon_rifle"]
const AMMO_ITEM_ID := "item_ammo_pack"
const AMMO_COUNT := 100
const SAMPLE_SEEDS: Array[int] = [1, 7, 2026, 991217, 20261109, 42, 808, 123456789]
## 只用来把楼层计划生成一次拿 room id；房间 id 与 seed 无关，固定下来即可。
const RUNTIME_PROBE_SEED := 2026
## 远征01 新局用北向（180°）。房间 id 与旋转无关，这里只是让计划校验走真实分支。
const EXPEDITION_ROTATION_DEG := 180

var _failures: Array[String] = []
var _probe_completed := false
## 配置里写的候选房（原样）。
var _candidate_rooms: Array[String] = []
## `generate_from_level_plan()` 产出的**运行时**房间 id（这才是 `room.room_id`）。
var _runtime_room_ids: Array[String] = []


func _ready() -> void:
	var plan := _load_plan()
	if plan.is_empty():
		_finish()
		return
	var clear_drops := plan.get("clear_drops", {}) as Dictionary
	var service := CLEAR_DROP_SCRIPT.new()
	var report: Dictionary = service.configure(clear_drops)
	_check(
		bool(report.get("ok", false)),
		"clear_drops 配置被拒绝：%s" % str(report.get("errors", []))
	)
	if not bool(report.get("ok", false)):
		_finish()
		return

	_resolve_ids(clear_drops)
	_check_structure(clear_drops)
	_check_runtime_id_alignment()
	_check_room_pick(service)
	_check_contents(service)
	_check_chest_grants(service)
	_check_room_overrides(service)
	_check_reverse_control(clear_drops)
	_finish()


func _load_plan() -> Dictionary:
	var text := FileAccess.get_file_as_string(PLAN_PATH)
	if text.is_empty():
		_failures.append("读不到关卡计划 %s" % PLAN_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_failures.append("关卡计划不是合法 JSON 对象")
		return {}
	return parsed as Dictionary


## 收集两套 id：配置里写的、以及运行时真正会用的。
func _resolve_ids(clear_drops: Dictionary) -> void:
	for raw in clear_drops.get("room_guarantees", []):
		var entry := raw as Dictionary
		if str(entry.get("id", "")) != GUARANTEE_ID:
			continue
		for value in entry.get("candidate_rooms", []):
			_candidate_rooms.append(str(value))
	var plan: Dictionary = FLOOR_PLAN_GENERATOR.generate_from_level_plan(
		LEVEL_ID, 0, RUNTIME_PROBE_SEED, EXPEDITION_ROTATION_DEG
	)
	_check(not plan.is_empty(), "generate_from_level_plan 返回空，拿不到运行时房间 id")
	if plan.is_empty():
		return
	_check(
		bool(plan.get("valid", false)),
		"远征01 楼层计划校验失败：%s" % str(plan.get("validation_errors", []))
	)
	for value in plan.get("rooms", []):
		var room := value as Dictionary
		var runtime_id := str(room.get("id", ""))
		if not runtime_id.is_empty():
			_runtime_room_ids.append(runtime_id)


## A 组：配置段必须显式存在，且参数与业主口径一致。
func _check_structure(clear_drops: Dictionary) -> void:
	var guarantees := clear_drops.get("room_guarantees", []) as Array
	_check(not guarantees.is_empty(), "clear_drops.room_guarantees 缺失")
	if guarantees.is_empty():
		return
	var entry := {}
	for raw in guarantees:
		if str((raw as Dictionary).get("id", "")) == GUARANTEE_ID:
			entry = raw as Dictionary
			break
	_check(not entry.is_empty(), "没有找到保底条目 %s" % GUARANTEE_ID)
	if entry.is_empty():
		return
	var rooms := entry.get("candidate_rooms", []) as Array
	_check(rooms.size() == 2, "候选房必须是 2 间（实际 %d）：%s" % [rooms.size(), str(rooms)])
	var guns := entry.get("weapon_choices", []) as Array
	_check(
		guns.size() == 2 and str(guns[0]) in CANDIDATE_GUNS and str(guns[1]) in CANDIDATE_GUNS,
		"候选枪必须是 %s（实际 %s）" % [str(CANDIDATE_GUNS), str(guns)]
	)
	_check(
		str(entry.get("weapon_grade", "")) == "blue",
		"枪品质下限必须是 blue（最低品质），实际 %s" % str(entry.get("weapon_grade", ""))
	)
	_check(str(entry.get("bullet_module_id", "")) == "mod_bullet_standard", "教学保底必须声明标准弹")
	var items := entry.get("items", []) as Array
	var ammo_ok := false
	for raw in items:
		var item := raw as Dictionary
		if str(item.get("item_id", "")) == AMMO_ITEM_ID and int(item.get("count", 0)) == AMMO_COUNT:
			ammo_ok = true
	_check(ammo_ok, "保底条目里没有 %s × %d" % [AMMO_ITEM_ID, AMMO_COUNT])


## A2 组（事故补丁）：候选房 id 必须与运行时房间 id **同一套口径**。
##
## 判据是「配置里的每个候选房都出现在 generate_from_level_plan() 的 rooms[].id 里」。
## 写成设计源初值 `f00_room_0N` 会在这里红 —— 这正是 2026-11-10 之前漏掉的那条。
func _check_runtime_id_alignment() -> void:
	_check(
		_candidate_rooms.size() == 2,
		"从配置里读到 %d 个候选房（应为 2）：%s" % [_candidate_rooms.size(), str(_candidate_rooms)]
	)
	_check(
		not _runtime_room_ids.is_empty(),
		"运行时房间 id 集合为空，无法校验候选房口径"
	)
	if _runtime_room_ids.is_empty():
		return
	for room_id in _candidate_rooms:
		_check(
			_runtime_room_ids.has(room_id),
			(
				"候选房「%s」不在运行时房间 id 集合里 %s —— 配置写成了设计源初值"
				+ "而不是 legacy_room_id，guaranteed_items_for_room() 会恒不命中"
			) % [room_id, str(_runtime_room_ids)]
		)
	_check(
		_candidate_rooms.size() < 2 or _candidate_rooms[0] != _candidate_rooms[1],
		"候选房重复：%s" % str(_candidate_rooms)
	)


## B 组：每局恰好命中一间，同 seed 恒定，且两间都会被抽到（哈希不能退化成永远同一间）。
func _check_room_pick(service: RefCounted) -> void:
	var picked_rooms: Dictionary = {}
	for seed_value in SAMPLE_SEEDS:
		var hits: Array[String] = []
		for room_id in _candidate_rooms:
			if not (service.guaranteed_items_for_room(room_id, seed_value) as Array).is_empty():
				hits.append(room_id)
		_check(
			hits.size() == 1,
			"seed %d 命中 %d 间房（必须恰好 1 间）：%s" % [seed_value, hits.size(), str(hits)]
		)
		if hits.size() != 1:
			continue
		picked_rooms[seed_value] = hits[0]
		# 同 seed 再问一次，必须给同一个答案（读档 / 流送重建不能换房）。
		var again: Array[String] = []
		for room_id in _candidate_rooms:
			if not (service.guaranteed_items_for_room(room_id, seed_value) as Array).is_empty():
				again.append(room_id)
		_check(
			again == hits,
			"seed %d 两次调用结果不一致：%s vs %s" % [seed_value, str(hits), str(again)]
		)
	# 分布检查：样本里两间房都出现过，否则等于「只掉了第一间」。
	var distinct := {}
	for room_id in picked_rooms.values():
		distinct[room_id] = true
	_check(
		distinct.size() == 2,
		"抽样 %d 个 seed 只命中 %s，随机选房退化成固定房" % [SAMPLE_SEEDS.size(), str(distinct.keys())]
	)


## C 组：命中房里必须是「一把蓝品候选枪 + 100 发弹药」，不多不少。
func _check_contents(service: RefCounted) -> void:
	for seed_value in SAMPLE_SEEDS:
		for room_id in _candidate_rooms:
			var items := service.guaranteed_items_for_room(room_id, seed_value) as Array
			if items.is_empty():
				continue
			var guns: Array = []
			var ammo: Array = []
			for raw in items:
				var item := raw as Dictionary
				if str(item.get("item_id", "")) in CANDIDATE_GUNS:
					guns.append(item)
				elif str(item.get("item_id", "")) == AMMO_ITEM_ID:
					ammo.append(item)
			_check(
				guns.size() == 1,
				"seed %d / %s 保底枪数量 %d（必须 1）" % [seed_value, room_id, guns.size()]
			)
			if guns.size() == 1:
				var gun := guns[0] as Dictionary
				_check(
					str(gun.get("grade", "")) == "blue",
					"seed %d / %s 保底枪品质 %s（必须 blue）" % [seed_value, room_id, str(gun.get("grade", ""))]
				)
				_check(
					int(gun.get("count", 0)) == 1,
					"seed %d / %s 保底枪数量应为 1" % [seed_value, room_id]
				)
			_check(
				ammo.size() == 1 and int((ammo[0] as Dictionary).get("count", 0)) == AMMO_COUNT,
				"seed %d / %s 保底弹药应为 %s × %d（实际 %s）"
				% [seed_value, room_id, AMMO_ITEM_ID, AMMO_COUNT, str(ammo)]
			)


## D 组：真的解析进宝箱。这里同时盯住一个已知陷阱 ——
## `ChestRewardService._unit_grants()` 会把每个 grant 的 count 拍成 1，
## 保底条目必须接在它**之后**，否则 100 发变 1 发。
func _check_chest_grants(service: RefCounted) -> void:
	var gun_found := 0
	var ammo_found := 0
	var tier_seen := {}
	for seed_value in SAMPLE_SEEDS:
		for room_id in _candidate_rooms:
			var guaranteed := service.guaranteed_items_for_room(room_id, seed_value) as Array
			if guaranteed.is_empty():
				continue
			var drop := service.roll_room_drop(room_id, "content", seed_value) as Dictionary
			var chest_config := drop.get("chest", {}) as Dictionary
			_check(
				not (chest_config.get("guaranteed_items", []) as Array).is_empty(),
				"seed %d / %s 的宝箱配置里没带 guaranteed_items" % [seed_value, room_id]
			)
			if chest_config.is_empty():
				continue
			var resolved := ChestRewardService.resolve(chest_config, seed_value, room_id, 1)
			_check(
				bool(resolved.get("ok", false)),
				"seed %d / %s 宝箱奖励解析失败：%s"
				% [seed_value, room_id, str(resolved.get("errors", []))]
			)
			tier_seen[str(resolved.get("tier", ""))] = true
			var has_gun := false
			var has_ammo := false
			for raw in resolved.get("grants", []):
				var grant := raw as Dictionary
				var item := grant.get("item", {}) as Dictionary
				var item_id := str(grant.get("item_id", item.get("id", "")))
				if item_id in CANDIDATE_GUNS:
					_check(str(item.get("bullet_module_id", "")) == "mod_bullet_standard", "教学保底枪实际弹种必须为标准弹")
					_check(bool(item.get("bullet_module_locked", false)), "教学保底枪弹种必须锁定")
					has_gun = true
					gun_found += 1
					_check(
						str(item.get("drop_grade", "")) == "blue",
						"seed %d / %s 宝箱里的保底枪品质是 %s（必须 blue）"
						% [seed_value, room_id, str(item.get("drop_grade", ""))]
					)
				elif item_id == AMMO_ITEM_ID and int(grant.get("count", 0)) == AMMO_COUNT:
					has_ammo = true
					ammo_found += 1
			_check(has_gun, "seed %d / %s 宝箱奖励里没有保底枪" % [seed_value, room_id])
			_check(
				has_ammo,
				"seed %d / %s 宝箱奖励里没有 %d 发保底弹药（可能被 _unit_grants 拍成 1 发）"
				% [seed_value, room_id, AMMO_COUNT]
			)
	_check(gun_found > 0 and ammo_found > 0, "整轮没有产出任何保底枪或弹药")
	# 清房箱必须仍是普通档：保底不能把它偷偷升成高级箱。
	_check(
		tier_seen.keys() == ["normal"] or (tier_seen.has("normal") and tier_seen.size() == 1),
		"清房箱档位被改动：%s" % str(tier_seen.keys())
	)


func _check_room_overrides(service: RefCounted) -> void:
	var room_02: Dictionary = service.roll_room_drop("room_02", "content", 2026)
	_check(str(room_02.get("kind", "")) == "chest", "room_02 应产生普通宝箱")
	var room_02_chest := room_02.get("chest", {}) as Dictionary
	_check(is_equal_approx(float(room_02_chest.get("fate_card_chance", 0.0)), 1.0), "room_02 命运机会必须冻结为1.0")
	_check(bool(room_02_chest.get("fate_common_offer", false)), "room_02 必须冻结 fate_common_offer")
	_check(not bool(room_02_chest.get("mimic", false)), "room_02 关键箱不得拟态")
	_check((room_02.get("grants", []) as Array).size() == 1, "room_02 应分账输出1个清房小包")
	var room_07: Dictionary = service.roll_room_drop("room_07", "content", 2026)
	var room_07_chest := room_07.get("chest", {}) as Dictionary
	var additional := room_07.get("additional_weapon", {}) as Dictionary
	_check(not room_07_chest.has("additional_weapon"), "追加武器不得进入宝箱分账")
	_check(str(additional.get("weapon_id", "")) == "weapon_rifle", "room_07 追加武器必须是步枪")
	_check(str(additional.get("grade", "")) == "purple", "room_07 追加武器必须是紫品")
	_check(str(additional.get("bullet_module_id", "")) == "mod_bullet_standard", "room_07 追加武器必须绑定标准弹")
	_check((room_07.get("grants", []) as Array).size() == 2, "room_07 应分账输出血包与弹药小包")
	var room_07_result := CHEST_REWARD_SERVICE.resolve_additional_weapon(room_07, 2026, "room_07", "clear_drop:room_07", 1)
	var room_07_weapon_found := false
	for grant in room_07_result.get("grants", []) as Array:
		var item := (grant as Dictionary).get("item", {}) as Dictionary
		if str((grant as Dictionary).get("item_id", "")) == "weapon_rifle":
			room_07_weapon_found = true
			_check(str(item.get("drop_grade", "")) == "purple", "room_07 追加武器必须落地为紫品")
			_check(str(item.get("bullet_module_id", "")) == "mod_bullet_standard", "room_07 追加武器必须绑定标准弹")
	_check(room_07_weapon_found, "room_07 独立追加出口必须产出步枪")
	var normal := CHEST_REWARD_SERVICE.resolve(room_02_chest, 2026, "room_02", 1)
	var fate_count := 0
	for grant in normal.get("grants", []) as Array:
		if str((grant as Dictionary).get("item_id", "")) == "item_fate_card_drop":
			fate_count += 1
	_check(fate_count == 1, "room_02 fate_card_chance=1 必须只生成一次命运凭据")


## 反向对照：把 `room_guarantees` 抹掉，必须**什么都不保底**。
## 若这里也绿，说明上面的绿来自别处（比如默认掉落里本来就有枪），是假绿。
func _check_reverse_control(clear_drops: Dictionary) -> void:
	var stripped := clear_drops.duplicate(true)
	stripped.erase("room_guarantees")
	var service := CLEAR_DROP_SCRIPT.new()
	var report: Dictionary = service.configure(stripped)
	_check(bool(report.get("ok", false)), "去掉 room_guarantees 后配置反而失败")
	var any_hit := false
	for seed_value in SAMPLE_SEEDS:
		for room_id in _candidate_rooms:
			if not (service.guaranteed_items_for_room(room_id, seed_value) as Array).is_empty():
				any_hit = true
	_check(not any_hit, "反向对照失败：去掉 room_guarantees 后仍有保底命中")


func _check(condition: bool, detail: String) -> void:
	if not condition:
		_failures.append(detail)


func _finish() -> void:
	_probe_completed = true
	if _failures.is_empty():
		print(
			"EXPEDITION01_ROOM_GUARANTEE_OK: 候选房 %s 与运行时 id 对齐；恰好随机一间必掉蓝品霰弹枪或步枪 + %d 发通用弹药；同 seed 恒定；清房箱档位未变"
			% [str(_candidate_rooms), AMMO_COUNT]
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
