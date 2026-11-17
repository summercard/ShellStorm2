extends Node
## 仅由 run_fate_tutorial_qa.py 在 Autoload 前隔离的副本中运行；不访问真实用户档。
const REGISTRY := preload("res://src/base/ItemRegistry.gd")
const INSTANCE := preload("res://src/weapons/WeaponInstance.gd")
const GRADE := preload("res://src/weapons/WeaponDropGrade.gd")
const SERVICE := preload("res://src/rewards/RewardService.gd")
const EXPECTED_BONUS := {"blue": 0, "purple": 2, "gold": 4}
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user := OS.get_user_data_dir().replace("\\", "/").to_lower()
	if OS.get_environment("SHELLSTORM_FATE_TUTORIAL_ISOLATED") != "1" or appdata.is_empty() or not user.begins_with(appdata + "/"):
		_check(false, "缺少Autoload前隔离，拒绝运行")
		_finish(false)
		return
	_case_new_and_reward()
	_case_legacy()
	_case_missing_fields()
	_case_other_and_custom()
	_case_preserved_build()
	_finish(true)


func _check(condition: bool, label: String) -> void:
	_checks.append({"passed": condition, "label": label})
	if not condition:
		_failures.append(label)


func _finish(completed: bool) -> void:
	print("PISTOL_FATE_CAPACITY_RESULT ", JSON.stringify({
		"completed": completed, "passed": completed and _failures.is_empty(),
		"checks": _checks, "failures": _failures, "check_count": _checks.size(),
		"save_mode": "仅内存纯字典与字节序列化往返，无文件或用户档写入",
	}))
	get_tree().quit(0 if completed and _failures.is_empty() else 1)


func _case_new_and_reward() -> void:
	var registry := REGISTRY.get_instance()
	var base := registry.get_item("weapon_pistol")
	_check(int(base.get("fate_slot_capacity", -1)) == 4, "豌豆内容基线显式4")
	_roundtrip(base, 4, "新普通豌豆")
	var plain := INSTANCE.from_item(base)
	var projection := plain.get_presentation_snapshot()
	_check(int(projection.get("fate_slot_capacity", -1)) == 4, "只读UI投影显示4巢")
	_check(int(projection.get("fate_slot_used", -1)) == 0, "新枪投影无刻印")
	for grade in EXPECTED_BONUS:
		var bonus := int(EXPECTED_BONUS[grade])
		_check(GRADE.fate_slot_bonus(grade) == bonus, "品质增量未变：" + grade)
		for item_id in ["weapon_pistol", "weapon_rifle", "weapon_sprinkler", "weapon_starter_rifle"]:
			var expected := (8 if item_id == "weapon_rifle" else 4) + bonus
			# 必须走 prepare -> ensure -> apply 的真实奖励链，不能用raw直接apply遮住漏加成。
			var report := SERVICE.resolve({
				"spec_id": "pistol-capacity:" + item_id + ":" + grade,
				"entries": [{"kind": "item", "item_id": item_id, "count": 1,
					"forced_grade": grade, "bullet_module_id": "mod_bullet_sticky"}],
			}, {"seed": 20261117, "floor": 1})
			var grants: Array = report.get("grants", [])
			_check(bool(report.get("ok", false)) and grants.size() == 1, "真实奖励成功：" + item_id + grade)
			if grants.size() != 1:
				continue
			var item: Dictionary = grants[0].get("item", {})
			_check(str(item.get("drop_grade", "")) == grade, "奖励强制品质：" + item_id + grade)
			_check(int(item.get("fate_slot_capacity", -1)) == expected, "奖励首次加成一次：" + item_id + grade)
			_check(bool(item.get("bullet_module_locked", false)), "奖励弹种身份锁保留：" + item_id + grade)
			_check(str(item.get("bullet_module_id", "")) == "mod_bullet_sticky", "奖励指定弹种保留：" + item_id + grade)
			_roundtrip(item, expected, "真实奖励" + item_id + grade)
			var repeated := GRADE.apply_to_item(item, grade)
			_check(int(repeated.get("fate_slot_capacity", -1)) == expected, "同品质重复apply不加成：" + item_id + grade)
	# 主代理已验证的蓝色重入守卫：两枪型、三种请求品质，各断容量不变与入参不变。
	for item_id in ["weapon_pistol", "weapon_rifle"]:
		var blue_item := INSTANCE.ensure_weapon_item(registry.get_item(item_id))
		blue_item["drop_grade"] = GRADE.GRADE_BLUE
		blue_item["weapon_instance"]["drop_grade"] = GRADE.GRADE_BLUE
		var original := blue_item.duplicate(true)
		var original_capacity := int(blue_item.get("fate_slot_capacity", -1))
		for requested_grade in EXPECTED_BONUS:
			var reapplied := GRADE.apply_to_item(blue_item, requested_grade)
			_check(int(reapplied.get("fate_slot_capacity", -1)) == original_capacity,
				"蓝色重入容量不变：" + item_id + requested_grade)
			_check(blue_item == original, "蓝色重入不改原输入：" + item_id + requested_grade)
	_check(not base.has("drop_grade"), "奖励与水合不污染内容定义")


func _case_legacy() -> void:
	for grade in EXPECTED_BONUS:
		var bonus := int(EXPECTED_BONUS[grade])
		var target := 4 + bonus
		for nested in [false, true]:
			for used in [0, 1, target]:
				var item := _legacy("weapon_pistol", grade, 8 + bonus, used)
				_roundtrip(_shape(item, nested), target, "安全旧枪%s嵌套%s占用%d" % [grade, nested, used])
			var overused := _legacy("weapon_pistol", grade, 8 + bonus, target + 1)
			# 单独钉数量门槛：槽序均未越界，但数组长度超过目标仍禁止降容。
			for entry in overused["fate_upgrades"]:
				entry["slot_index"] = 1
			_roundtrip(_shape(overused, nested), 8 + bonus, "占用超标保留%s嵌套%s" % [grade, nested])
			var sparse := _legacy("weapon_pistol", grade, 8 + bonus, 1)
			sparse["fate_upgrades"][0]["slot_index"] = target + 1
			_roundtrip(_shape(sparse, nested), 8 + bonus, "稀疏槽序超标保留%s嵌套%s" % [grade, nested])
	# 无品质旧蓝枪与不按顺序保存的刻印，不补排序。
	var ungraded := _legacy("weapon_pistol", "blue", 8, 2)
	ungraded.erase("drop_grade")
	ungraded["fate_upgrades"].reverse()
	_roundtrip(ungraded, 4, "旧8无品质且刻印顺序原样")


func _case_missing_fields() -> void:
	for item_id in ["weapon_pistol", "weapon_rifle", "weapon_sprinkler", "weapon_starter_rifle"]:
		var base_capacity := 8 if item_id == "weapon_rifle" else 4
		for grade in ["", "blue", "purple", "gold", "unknown"]:
			for nested in [false, true]:
				var item := _legacy(item_id, grade, 99, 1)
				item.erase("fate_slot_capacity")
				if grade.is_empty():
					item.erase("drop_grade")
				var expected := base_capacity + int(EXPECTED_BONUS.get(grade, 0))
				_roundtrip(_shape(item, nested), expected, "缺容量%s品质%s嵌套%s" % [item_id, grade, nested])
	# 最小content_id-only字典与新canonical的蓝色默认不能触发额外品质增量。
	_roundtrip({"weapon_content_id": "weapon_pistol"}, 4, "仅内容ID无容量无品质")
	_roundtrip({"weapon_instance": {"weapon_content_id": "weapon_pistol"}}, 4, "仅嵌套内容ID")
	var explicit_blue := REGISTRY.get_instance().get_item("weapon_pistol")
	explicit_blue["drop_grade"] = "blue"
	explicit_blue.erase("fate_slot_capacity")
	_roundtrip(explicit_blue, 4, "内容基线带blue但缺容量")
	# 顶层字段优先；只缺一侧时必须从另一侧读回而非重新加成。
	var mixed := _legacy("weapon_pistol", "purple", 10, 1)
	mixed["weapon_instance"] = {"fate_slot_capacity": 14, "drop_grade": "gold"}
	_roundtrip(mixed, 6, "顶层旧值优先嵌套冲突")
	mixed.erase("fate_slot_capacity")
	_roundtrip(mixed, 14, "顶层缺容量读取嵌套自定义")
	mixed["weapon_instance"] = {"drop_grade": "purple", "fate_slot_capacity": 10}
	mixed.erase("drop_grade")
	_roundtrip(mixed, 6, "顶层缺品质容量读取嵌套")


func _case_other_and_custom() -> void:
	for grade in EXPECTED_BONUS:
		for capacity in [0, 4, 5, 9, 14]:
			for nested in [false, true]:
				_roundtrip(_shape(_legacy("weapon_pistol", grade, capacity, 1), nested), capacity,
					"自定义豌豆%s容量%d嵌套%s" % [grade, capacity, nested])
		for capacity in [8, 10, 12]:
			if capacity != 8 + int(EXPECTED_BONUS[grade]):
				_roundtrip(_legacy("weapon_pistol", grade, capacity, 1), capacity,
					"容量与旧品质不匹配不得迁移%s容量%d" % [grade, capacity])
		for item_id in ["weapon_rifle", "weapon_shotgun", "weapon_machinegun", "weapon_sniper", "weapon_launcher", "weapon_charge", "weapon_baseball_bat", "weapon_greatblade", "weapon_waraxe", "weapon_sprinkler", "weapon_starter_rifle"]:
			var capacity := 8 + int(EXPECTED_BONUS[grade])
			for nested in [false, true]:
				_roundtrip(_shape(_legacy(item_id, grade, capacity, 1), nested), capacity,
					"非豌豆旧容量%s品质%s嵌套%s" % [item_id, grade, nested])


func _case_preserved_build() -> void:
	var tree := BlueprintRegistry.build_weapon_tree("bp_pistol", "mod_bullet_sticky")
	var bare_magazine := tree.magazine_size
	var attachment := BlueprintRegistry.create_assembly_node("attach_big_mag")
	var mounted := tree.mount(tree.get_root(), AssemblyNode.SlotType.MAGAZINE, attachment)
	_check(mounted, "真实弹匣配件可挂载")
	if not mounted:
		attachment.free()
	_check(tree.magazine_size > bare_magazine, "真实弹匣配件效果有效")
	tree.current_ammo = 3
	var base := _legacy("weapon_pistol", "purple", 10, 2)
	var captured := INSTANCE.from_item(base, tree).to_item_dictionary()
	captured["fate_slot_capacity"] = 10
	captured["weapon_instance"]["fate_slot_capacity"] = 10
	# 参考实例只用自定义容量绕过迁移；运行属性与本次容量变化必须完全正交。
	var reference_item := captured.duplicate(true)
	reference_item["fate_slot_capacity"] = 14
	var reference := INSTANCE.from_item(reference_item)
	var before := reference.get_presentation_snapshot()
	var after_instance := INSTANCE.from_item(captured)
	var after := after_instance.get_presentation_snapshot()
	_check(after_instance.fate_slot_capacity == 6, "带真实装配的旧紫豌豆安全降至6")
	for key in ["weapon_instance_id", "weapon_content_id", "assembly_id", "rarity", "drop_grade", "bullet_module_locked", "fate_upgrades", "attachment_slots", "attachment_layout", "bullet_module", "computed_stats", "current_ammo"]:
		_check(before.get(key) == after.get(key), "降容不改变投影属性：" + key)
	_check(str((after.get("bullet_module", {}) as Dictionary).get("item_id", "")) == "mod_bullet_sticky", "降容不改变真实黏黏弹")
	var stats: Dictionary = after.get("computed_stats", {})
	_check(int(stats.get("magazine_size", 0)) > 10 and int(after.get("current_ammo", -1)) == 3, "弹匣效果与剩余弹量保留")
	_check(is_equal_approx(float(after.get("grade_damage_multiplier", 0.0)), 1.10), "紫色伤害倍率仍为1.10")
	_roundtrip(captured, 6, "真实装配刻印四次存读")
	var saved := captured
	var expected_stats: Variant = JSON.parse_string(JSON.stringify(stats))
	for index in range(4):
		var decoded: Dictionary = bytes_to_var(var_to_bytes(saved))
		var reloaded := INSTANCE.from_item(decoded)
		var projection := reloaded.get_presentation_snapshot()
		_check(JSON.parse_string(JSON.stringify(projection.get("computed_stats", {}))) == expected_stats,
			"真实运行属性四次存读不复利%d" % index)
		_check(projection.get("bullet_module") == after.get("bullet_module"), "四次存读不换弹种%d" % index)
		saved = reloaded.to_item_dictionary()
	tree.free()


func _legacy(item_id: String, grade: String, capacity: int, used: int) -> Dictionary:
	var upgrades: Array[Dictionary] = []
	for index in range(used):
		upgrades.append({
			"slot_index": index + 1, "stable_card_id": "fate_scale_node",
			"tarot_name": "测试刻印", "orientation": "REVERSED",
			"orientation_roll": 0.875, "effect_version": 2,
			"effect_params_snapshot": {"scale": 0.75, "frozen": {"seed": 42}},
			"applied_transaction_id": "fate:capacity:%d" % index,
		})
	return {
		"type": "weapon", "weapon_content_id": item_id,
		"weapon_instance_id": "wpn_capacity_" + item_id + grade,
		"created_transaction_id": "create:capacity:" + item_id + grade,
		"drop_grade": grade, "rarity": "rare", "fate_slot_capacity": capacity,
		"fate_upgrades": upgrades, "current_ammo": 3,
		"bullet_module_id": "mod_bullet_sticky", "bullet_module_locked": true,
	}


func _shape(item: Dictionary, nested: bool) -> Dictionary:
	if not nested:
		return item
	var inner := item.duplicate(true)
	inner.erase("type")
	inner.erase("bullet_module_id")
	return {"type": "weapon", "bullet_module_id": item.get("bullet_module_id", ""), "weapon_instance": inner}


func _roundtrip(source: Dictionary, expected: int, label: String) -> void:
	var untouched := source.duplicate(true)
	var instance := INSTANCE.from_item(source)
	_check(instance != null, label + "：实例可水合")
	if instance == null:
		return
	_check(instance.fate_slot_capacity == expected, label + "：容量%d" % expected)
	_check(source == untouched, label + "：不原地改输入")
	var nested: Dictionary = source.get("weapon_instance", {})
	var upgrades: Array = source.get("fate_upgrades", nested.get("fate_upgrades", []))
	_check(instance.fate_upgrades == upgrades, label + "：全部逆位刻印顺序与冻结效果保留")
	for key in ["weapon_instance_id", "created_transaction_id", "current_ammo", "bullet_module_locked", "assembly_snapshot"]:
		var value: Variant = source.get(key, nested.get(key))
		if value != null:
			_check(instance.get(key) == value, label + "：原始字段保留" + key)
	var baseline := instance.to_item_dictionary()
	_check(_pure_data(baseline), label + "：存档为纯数据字典")
	_check(int((baseline["weapon_instance"] as Dictionary).get("schema_version", -1)) == 2, label + "：schema不变")
	var saved := baseline.duplicate(true)
	_check(INSTANCE.from_item(saved).to_item_dictionary() == baseline, label + "：直接字典往返幂等")
	var json_baseline: Variant = JSON.parse_string(JSON.stringify(baseline))
	for index in range(4):
		var decoded: Variant = bytes_to_var(var_to_bytes(saved))
		_check(decoded is Dictionary, label + "：纯字典保存恢复%d" % index)
		if not decoded is Dictionary:
			return
		instance = INSTANCE.from_item(decoded as Dictionary)
		saved = instance.to_item_dictionary()
		_check(instance.fate_slot_capacity == expected, label + "：往返容量稳定%d" % index)
		_check(saved == baseline, label + "：完整字典幂等%d" % index)
		_check(JSON.parse_string(JSON.stringify(saved)) == json_baseline, label + "：完整JSON字典幂等%d" % index)
		_check(int(saved["fate_slot_capacity"]) == int(saved["weapon_instance"]["fate_slot_capacity"]), label + "：两层容量同步%d" % index)


func _pure_data(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not key is String or not _pure_data(value[key]):
				return false
		return true
	if value is Array:
		for entry in value:
			if not _pure_data(entry):
				return false
		return true
	return value == null or value is String or value is bool or value is int or value is float
