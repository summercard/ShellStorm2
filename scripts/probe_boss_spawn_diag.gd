extends Node
## 定点诊断：远征01 的 boss 房**为什么不刷首领**。
##
## 逐环打印：房表 spawn_placements → 盒解析 → 波次 → 提交 → 存活账 / 首领检索。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 20260919


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	print("=== DYNAG boss room ===")
	print("  room_type=%s  spawn_boxes_only=%s  cleared=%s" % [
		room.room_type, str(room.spawn_boxes_only), str(room.cleared),
	])
	print("  boss_content_id(meta)=%s" % str(room.get_meta("boss_content_id", "<无>")))
	print("  authored_layout_peaceful=%s" % str(room.authored_layout_peaceful))
	print("  boss_reinforcement_plan=%s" % str(room.boss_reinforcement_plan))
	print("  spawn_placements(%d)=" % room.spawn_placements.size())
	for index in range(room.spawn_placements.size()):
		var placement := room.spawn_placements[index] as Dictionary
		print("     [%d] %s" % [index, str(placement)])
	var dims := room.get_dimensions()
	print("  dims=(%.1f,%.1f) pos=%s" % [dims.x, dims.y, str(room.global_position)])
	var floor_rank := maxi(1, tower.visual_theme.difficulty_rank)
	var floor_level := clampi(int(float(tower._record_index("boss")) / maxf(1.0, float(tower._records.size() - 1)) * 3.0), 0, 3)
	print("  floor=%d floor_level=%d" % [floor_rank, floor_level])
	var waves: Array = tower._spawn_box_waves(room, floor_rank, floor_level)
	print("  _spawn_box_waves 波数=%d" % waves.size())
	for index in range(waves.size()):
		var batch := waves[index] as Array
		print("     波%d 条数=%d" % [index, batch.size()])
		for entry in batch:
			var cfg := entry as Dictionary
			print("        type=%s count=%s delay=%s boss_content_id=%s spawn=%s" % [
				str(cfg.get("type", "")), str(cfg.get("count", "")),
				str(cfg.get("spawn_delay_sec", "")), str(cfg.get("boss_content_id", "")),
				str(cfg.get("spawn_position", "<无>")),
			])
	# 盒内落点
	var placement0 := (room.spawn_placements[0] as Dictionary) if not room.spawn_placements.is_empty() else {}
	if not placement0.is_empty():
		var center := placement0.get("box_center", Vector2.ZERO) as Vector2
		var size := placement0.get("box_size", Vector2.ZERO) as Vector2
		print("  box0 center=%s size=%s rotation=%s" % [
			str(center), str(size), str(placement0.get("box_rotation", 0.0)),
		])
		var pts := room.spawn_points_in_box(
			center, size, 4, float(placement0.get("box_rotation", 0.0)), 2.8, 1
		)
		print("  盒内落点(%d)=" % pts.size())
		for point in pts:
			print("     %s finite=%s" % [str(point), str((point as Vector3).is_finite())])
	var spawned := tower._prepare_revealed_hostile_room(room)
	print("  _prepare_revealed_hostile_room → %s" % str(spawned))
	await get_tree().physics_frame
	print("  _alive_by_room[boss]=%s" % str(tower._alive_by_room.get("boss", "<无>")))
	print("  _enemy_nodes_by_room[boss] 数=%d" % (tower._enemy_nodes_by_room.get("boss", []) as Array).size())
	print("  _boss_reinforcement_boss(boss)=%s" % str(tower._boss_reinforcement_boss("boss")))
	print("  room.cleared=%s" % str(room.cleared))
	print("DYNAG_DONE")
	get_tree().quit(0)
