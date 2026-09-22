extends Node
## 临时探针：实测远征关卡01 运行时每间房的怪物掉落表与搜索容器掉落表。
## 只读，不改任何运行内容。判据直接取自运行时对象，不复刻公式到探针里（除打印用对照）。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const MONSTER := preload("res://src/map/MonsterInjector.gd")
const ROOM_DATA := preload("res://src/map/RoomData.gd")

var _tower: Node = null


func _ready() -> void:
	var packed := load(EXPEDITION_SCENE) as PackedScene
	_tower = packed.instantiate()
	_tower.set("test_mode", true)
	_tower.set("run_seed_override", 77001199)
	add_child(_tower)
	for _index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame

	var theme: Resource = _tower.get("visual_theme")
	print("visual_theme=%s difficulty_rank=%d" % [
		str(theme.get("theme_id")), int(theme.get("difficulty_rank")),
	])

	var records: Array = _tower.get("_records")
	var record_count := records.size()
	print("records=%d   (floor_level 分母 = records.size()-1 = %d)" % [
		record_count, record_count - 1,
	])

	var by_id: Dictionary = {}
	for value in records:
		var rec := value as Dictionary
		var idx := int(rec.get("index", 0))
		var floor_level := clampi(int(float(idx) / maxf(1.0, float(record_count - 1)) * 3.0), 0, 3)
		var table_name: String = MONSTER.new().call("_get_loot_table", floor_level)
		by_id[str(rec.get("id", ""))] = floor_level
		print("  idx=%d  id=%-12s type=%-10s role=%-12s floor_level=%d -> monster_table=%s" % [
			idx, str(rec.get("id", "")), str(rec.get("type", "")),
			str(rec.get("tower_role", "")), floor_level, table_name,
		])

	print("")
	print("=== 按房型汇总（远征01 内容房类型由种子洗牌）===")
	var plan: Dictionary = (_tower.get("_floor_plan_snapshots") as Dictionary).get(0, {})
	print("layout_id=%s floor_number=%s" % [
		str(plan.get("layout_id", "")), str(plan.get("floor_number", "")),
	])
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		var rid := str(spec.get("id", ""))
		print("  %-12s key=%-10s type=%-10s role=%-12s floor_level=%s" % [
			rid, str(spec.get("key", "")), str(spec.get("type", "")),
			str(spec.get("role", "")), str(by_id.get(rid, "-")),
		])

	print("")
	print("=== 采样：普通怪 loot_table（MonsterInjector 实出）===")
	for floor_level in range(0, 4):
		var enemies: Array = MONSTER.new().generate_enemies({
			"type": "random", "floor": maxi(1, int(theme.get("difficulty_rank"))),
			"floor_level": floor_level,
		})
		var tables: Dictionary = {}
		for e in enemies:
			tables[str((e as Dictionary).get("loot_table", "?"))] = true
		print("  floor_level=%d -> %s" % [floor_level, str(tables.keys())])

	print("")
	print("=== 搜索容器表（Dungeon3D 传入 floor = maxi(1, difficulty_rank)）===")
	var container_floor := maxi(1, int(theme.get("difficulty_rank")))
	print("  container table_name = scavenge_floor_%d" % mini(5, container_floor))

	get_tree().quit(0)
