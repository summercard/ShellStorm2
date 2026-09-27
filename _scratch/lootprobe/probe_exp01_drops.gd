extends Node
## 临时探针（只读）：实测「远征关卡01 当前口径」的每房 floor_level、刷怪盒波次编成与掉落池。
##
## 与旧 probe_expedition_monsters.gd 的区别：旧版读的是 `enemy_spawn_plan` 半钉死波次（已废弃路径），
## 本版直接调运行时真函数 `Dungeon3D._spawn_box_waves`，反映**触发器刷怪盒**这条现行路径。
## 判据全部取自运行时对象，不复刻公式（除打印用的 floor_level 对照）。
##
## 运行：
##   godot_console.exe --headless --path <project> res://_scratch/lootprobe/probe_exp01_drops.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const MONSTER := preload("res://src/map/MonsterInjector.gd")
const OUT_PATH := "res://_scratch/lootprobe/exp01_drops_out.txt"

const SEED := 77001199


func _ready() -> void:
	var lines: Array[String] = []
	var packed := load(EXPEDITION_SCENE) as PackedScene
	var tower: Node = packed.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _index in range(12):
		await get_tree().process_frame
		await get_tree().physics_frame

	var theme: Resource = tower.get("visual_theme")
	var gameplay: Resource = tower.get("gameplay_theme")
	var floor := maxi(1, int(theme.get("difficulty_rank")))
	var records: Array = tower.get("_records")
	var n := records.size()
	var by_id: Dictionary = {}
	for record_value in records:
		var record := record_value as Dictionary
		by_id[str(record.get("id", ""))] = record

	lines.append("LEVEL\texpedition_01\ttheme=%s\tseed=%d\tfloor=%d\trecords=%d" % [
		str(theme.get("theme_id")), SEED, floor, n,
	])
	lines.append("ENEMY_POOL\t%s" % str(gameplay.get_enemy_rule("enemy_pool", [])))

	lines.append("")
	lines.append("# 记录表（index / floor_level / 普通怪掉落池）")
	lines.append("REC\tidx\tid\ttype\trole\tfloor_level\tmonster_pool")
	for record_value in records:
		var record := record_value as Dictionary
		var idx := int(record.get("index", -1))
		var level := _floor_level(idx, n)
		lines.append("REC\t%d\t%s\t%s\t%s\t%d\t%s" % [
			idx, str(record.get("id", "")), str(record.get("type", "")),
			str(record.get("tower_role", "")), level,
			MONSTER.get_loot_table_for_level(level),
		])

	var rooms: Array = tower.get("_rooms")
	lines.append("")
	lines.append("# 房间实测（rooms=%d）" % rooms.size())
	lines.append("ROOM\troom_id\ttype\tsize_class\tindex\tfloor_level\tplacements\twaves\tenemies")
	var room_rows: Array = []
	for room_value in rooms:
		var room = room_value
		if room == null:
			continue
		var rid := str(room.get("room_id"))
		var record: Dictionary = by_id.get(rid, {})
		var idx := int(record.get("index", -1))
		var level := _floor_level(idx, n)
		var placements: Array = room.get("spawn_placements")
		var waves: Array = tower.call("_spawn_box_waves", room, floor, level)
		var total := 0
		for wave_value in waves:
			total += (wave_value as Array).size()
		lines.append("ROOM\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d" % [
			rid, str(room.get("room_type")), str(room.get("size_class")),
			idx, level, placements.size(), waves.size(), total,
		])
		room_rows.append({
			"id": rid, "idx": idx, "level": level,
			"type": str(room.get("room_type")),
			"waves": waves, "placements": placements,
		})
		for placement_value in placements:
			lines.append("PLACE\t%s\t%s" % [rid, JSON.stringify(placement_value)])

	lines.append("")
	lines.append("# 逐房逐波编成（WAVE 后附每只怪）")
	lines.append("WAVE\troom\troom_type\tfloor_level\twave\tbox\tbox_center\tenemy_type\tname\ttier\tloot_table\thp\tdamage\tmodifier\tspawn_pos_ok")
	for row in room_rows:
		var rid := str(row["id"])
		var waves: Array = row["waves"]
		var placements: Array = row["placements"]
		for wave_index in range(waves.size()):
			var wave: Array = waves[wave_index]
			for enemy_value in wave:
				var enemy := enemy_value as Dictionary
				var pos: Variant = enemy.get("spawn_position", null)
				var pos_ok := (pos is Vector3) and (pos as Vector3).is_finite()
				lines.append("WAVE\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s" % [
					rid, str(row["type"]), int(row["level"]), wave_index,
					str(enemy.get("spawn_box_id", "")),
					str(enemy.get("spawn_box_center", "")),
					str(enemy.get("enemy_type", "")), str(enemy.get("name", "")),
					_tier_of(enemy), str(enemy.get("loot_table", "")),
					int(enemy.get("hp", 0)), int(enemy.get("damage", 0)),
					str(enemy.get("modifier", "")), ("Y" if pos_ok else "N"),
				])

	lines.append("")
	lines.append("# 结构化掉落规格（MonsterInjector.drop_spec_for 运行时真值）")
	lines.append("SPEC\tmonster\ttier\tfloor_level\tpool\titem_chance\tammo_chance\tammo_range\tcurrency")
	var seen: Dictionary = {}
	for row in room_rows:
		for wave_value in (row["waves"] as Array):
			for enemy_value in wave_value:
				var enemy := enemy_value as Dictionary
				var type_id := str(enemy.get("enemy_type", ""))
				var tier := _tier_of(enemy)
				var level := int(row["level"])
				var key := "%s|%s|%d" % [type_id, tier, level]
				if seen.has(key):
					continue
				seen[key] = true
				var spec: Dictionary = MONSTER.drop_spec_for(type_id, tier, level, floor)
				var pool := ""
				var item_chance := 0.0
				var ammo_chance := 0.0
				var ammo_range := ""
				var currency := ""
				for entry_value in spec.get("entries", []):
					var entry := entry_value as Dictionary
					match str(entry.get("kind", "")):
						"pool":
							pool = str(entry.get("pool_id", ""))
							item_chance = float(entry.get("chance", 0.0))
						"item":
							ammo_chance = float(entry.get("chance", 0.0))
							var rng: Dictionary = entry.get("count", {})
							ammo_range = "%d-%d" % [int(rng.get("min", 0)), int(rng.get("max", 0))]
						"currency":
							var amount: Dictionary = entry.get("amount", {})
							currency = "%d+floor*%d" % [
								int(amount.get("base", 0)), int(amount.get("per_floor", 0)),
							]
				lines.append("SPEC\t%s\t%s\t%d\t%s\t%.2f\t%.2f\t%s\t%s" % [
					type_id, tier, level, pool, item_chance, ammo_chance, ammo_range, currency,
				])

	lines.append("")
	lines.append("# Boss 房身份")
	var boss_record: Dictionary = by_id.get("boss", {})
	lines.append("BOSS\tboss_content_id=%s\tarena=%s" % [
		str(boss_record.get("boss_content_id", "")), str(boss_record.get("arena_asset_id", "")),
	])

	var joined := "\n".join(lines)
	var handle := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if handle != null:
		handle.store_string(joined + "\n")
		handle.close()
	print(joined)
	get_tree().quit(0)


func _floor_level(index: int, record_count: int) -> int:
	return clampi(int(float(index) / maxf(1.0, float(record_count - 1)) * 3.0), 0, 3)


func _tier_of(enemy: Dictionary) -> String:
	if bool(enemy.get("is_boss", false)):
		return "boss"
	if bool(enemy.get("is_elite", false)):
		return "elite"
	return "normal"
