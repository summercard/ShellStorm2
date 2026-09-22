extends Node
## 临时探针（只读）：dump 远征关卡01 的「怪物配置 + 对应掉落」全表。
## 判据取运行时真值：房间实例来自 Dungeon3D._rooms，敌人由 MonsterInjector 真实生成。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const MONSTER := preload("res://src/map/MonsterInjector.gd")
const DESIGN := preload("res://src/framework/GameDesignConfig.gd")

var _tower: Node = null


func _ready() -> void:
	var packed := load(EXPEDITION_SCENE) as PackedScene
	_tower = packed.instantiate()
	_tower.set("test_mode", true)
	_tower.set("run_seed_override", 77001199)
	add_child(_tower)
	for _index in range(10):
		await get_tree().process_frame
		await get_tree().physics_frame

	var theme: Resource = _tower.get("visual_theme")
	var profile: Resource = _tower.get("gameplay_theme")
	var floor := maxi(1, int(theme.get("difficulty_rank")))
	print("LEVEL=expedition_01  theme=%s  difficulty_rank=%d  => floor=%d" % [
		str(theme.get("theme_id")), int(theme.get("difficulty_rank")), floor,
	])
	print("enemy_pool=%s" % str(profile.get_enemy_rule("enemy_pool", [])))
	print("hp_mult=%s  damage_mult=%s  speed_mult=%s" % [
		str(profile.get_enemy_rule("hp_multiplier", 1.0)),
		str(profile.get_enemy_rule("damage_multiplier", 1.0)),
		str(profile.get_enemy_rule("speed_multiplier", 1.0)),
	])
	print("name_prefix=%s  boss_name=%s" % [
		str(profile.get_enemy_rule("name_prefix", "")),
		str(profile.get_enemy_rule("boss_name", "")),
	])
	print("HOSTILE_TYPES=%s" % str(DESIGN.ROOM_TYPES_WITH_HOSTILES))

	var injector: RefCounted = MONSTER.new()
	injector.call("set_theme_profile", profile)

	var rooms: Array = _tower.get("_rooms")
	print("")
	print("=== 运行时房间 → 怪物池 / 数量 / 掉落池（rooms=%d）===" % rooms.size())
	print("%-3s %-14s %-11s %-10s %-8s %-6s %-12s %-8s %-6s" % [
		"idx", "room_id", "room_type", "size_class", "floor_lv",
		"刷怪", "怪物掉落池", "数量", "波次",
	])
	var summary: Array = []
	for room in rooms:
		if room == null:
			continue
		var rid := str(room.get("room_id"))
		var rtype := str(room.get("room_type"))
		var sclass := str(room.get("size_class"))
		var idx := int(_tower.call("_record_index", rid))
		var record_count := (_tower.get("_records") as Array).size()
		var floor_level := clampi(int(float(idx) / maxf(1.0, float(record_count - 1)) * 3.0), 0, 3)
		var hostile: bool = DESIGN.ROOM_TYPES_WITH_HOSTILES.has(rtype)
		var peaceful := bool(room.get("authored_layout_peaceful"))
		if peaceful:
			hostile = false
		var table := str(injector.call("_get_loot_table", floor_level)) if hostile else "-"
		var bonus := 0
		if sclass == "large":
			bonus = 2
		elif sclass == "arena":
			bonus = 4
		var desired := (4 + floor * 2 + bonus) if hostile else 0
		var waves := 1
		if hostile and rtype == "COMBAT":
			waves = [1, 2, 2, 3][floor_level]
		print("%-3d %-14s %-11s %-10s %-8d %-6s %-12s %-8d %-6d" % [
			idx, rid, rtype, sclass, floor_level,
			("是" if hostile else "否"), table, desired, waves,
		])
		summary.append({
			"idx": idx, "id": rid, "type": rtype, "hostile": hostile,
			"floor_level": floor_level, "table": table, "count": desired,
		})

	print("")
	print("=== 刷怪房实际敌人组成（每房按各自 floor_level 真出一次）===")
	for entry in summary:
		if not bool(entry["hostile"]):
			continue
		var batch: Array = injector.call("generate_enemies", {
			"type": "random", "floor": floor, "floor_level": int(entry["floor_level"]),
		})
		var names: Array[String] = []
		for e in batch:
			var d := e as Dictionary
			names.append("%s(%s hp=%s dmg=%s)" % [
				str(d.get("name", "?")), str(d.get("enemy_type", "?")),
				str(d.get("hp", "?")), str(d.get("damage", "?")),
			])
		print("  idx=%d %-14s lv=%d table=%s" % [
			int(entry["idx"]), str(entry["id"]), int(entry["floor_level"]), str(entry["table"]),
		])
		for n in names:
			print("      %s" % n)

	print("")
	print("=== 各 floor_level 的类型分布（每档采样 40 只，池为 4 项含重复权重）===")
	for floor_level in range(0, 4):
		var counts: Dictionary = {}
		for _i in range(40):
			var batch: Array = injector.call("generate_enemies", {
				"type": "random", "floor": floor, "floor_level": floor_level,
			})
			for e in batch:
				var t := str((e as Dictionary).get("enemy_type", "?"))
				counts[t] = int(counts.get(t, 0)) + 1
		var parts: Array[String] = []
		for k in counts.keys():
			parts.append("%s=%d" % [str(k), int(counts[k])])
		parts.sort()
		print("  lv=%d  %s" % [floor_level, ", ".join(parts)])

	print("")
	print("=== 搜索容器掉落 ===")
	print("  scavenge_floor_%d  (= min(5, maxi(1, difficulty_rank)))" % mini(5, floor))
	print("  魂兜底 = 2 + floor = %d" % [2 + floor])

	print("")
	print("=== 关卡设计源在怪物/掉落上的命中情况 ===")
	var plan: Dictionary = (_tower.get("_floor_plan_snapshots") as Dictionary).get(0, {})
	print("  layout_id=%s" % str(plan.get("layout_id", "")))
	var spec_rooms: Array = plan.get("rooms", [])
	var hit_spawn := 0
	var hit_boss := 0
	var hit_reward := 0
	for value in spec_rooms:
		var spec := value as Dictionary
		if not (spec.get("enemy_spawn_plan", {}) as Dictionary).is_empty():
			hit_spawn += 1
		if str(spec.get("boss_content_id", "")) != "":
			hit_boss += 1
		if not (spec.get("reward_plan", {}) as Dictionary).is_empty():
			hit_reward += 1
	print("  rooms=%d  enemy_spawn_plan=%d  boss_content_id=%d  reward_plan=%d" % [
		spec_rooms.size(), hit_spawn, hit_boss, hit_reward,
	])

	get_tree().quit(0)
