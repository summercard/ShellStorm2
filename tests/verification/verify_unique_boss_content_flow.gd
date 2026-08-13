extends Node
## 95/90/85层独立Boss：内容ID、正式模型、阶段技能袋、场地资产与掩体碰撞验收。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)


func _ready() -> void:
	var failures: Array[String] = []
	var injector := MonsterInjector.new()
	injector.set_seed(95009085)
	var content_ids: Array[String] = []
	var presentation_ids: Array[String] = []
	var arena_ids: Array[String] = []
	for floor_number in [95, 90, 85]:
		var profile := BossContentCatalog.get_for_floor(floor_number)
		_expect(not profile.is_empty(), "%d层缺少Boss内容档案" % floor_number, failures)
		for key in ["boss_content_id", "display_name", "presentation_asset_id", "presentation_scene", "arena_asset_id", "arena_scene", "phase_skill_bags"]:
			_expect(profile.has(key), "%d层Boss缺少字段%s" % [floor_number, key], failures)
		var content_id := str(profile.get("boss_content_id", ""))
		var presentation_id := str(profile.get("presentation_asset_id", ""))
		var arena_id := str(profile.get("arena_asset_id", ""))
		_expect(not content_id.is_empty() and content_id not in content_ids, "%d层Boss内容ID不唯一" % floor_number, failures)
		_expect(not presentation_id.is_empty() and presentation_id not in presentation_ids, "%d层Boss表现资产不唯一" % floor_number, failures)
		_expect(not arena_id.is_empty() and arena_id not in arena_ids, "%d层Boss场地资产不唯一" % floor_number, failures)
		content_ids.append(content_id)
		presentation_ids.append(presentation_id)
		arena_ids.append(arena_id)

		var boss_scene := load(str(profile.get("presentation_scene", ""))) as PackedScene
		var arena_scene := load(str(profile.get("arena_scene", ""))) as PackedScene
		_expect(boss_scene != null, "%d层Boss正式GLB无法加载" % floor_number, failures)
		_expect(arena_scene != null, "%d层Boss场地GLB无法加载" % floor_number, failures)
		if boss_scene != null:
			var asset := boss_scene.instantiate()
			_expect(not asset.find_children("*", "MeshInstance3D", true, false).is_empty(), "%d层Boss GLB没有网格" % floor_number, failures)
			asset.free()

		var generated := injector.generate_enemies({
			"type": "boss", "floor": 5, "floor_level": RoomData.FloorLevel.DEEP,
			"floor_number": floor_number,
		})
		_expect(generated.size() == 1, "%d层Boss生成数量不是1" % floor_number, failures)
		if generated.is_empty():
			continue
		var config := generated[0]
		_expect(str(config.get("boss_content_id", "")) == content_id, "%d层Boss生成器绑定了错误内容" % floor_number, failures)
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(enemy)
		enemy.configure_from_enemy_data(config)
		var avatar_snapshot := enemy.avatar.get_component_snapshot()
		_expect(bool(avatar_snapshot.get("formal_boss_asset", false)), "%d层Boss没有替换为正式模型" % floor_number, failures)
		var phase_bags := config.get("boss_phase_skill_bags", {}) as Dictionary
		for phase in [1, 2, 3]:
			enemy.boss_phase = phase
			enemy._boss_skill_bag.clear()
			enemy._boss_skill_index = 0
			var configured := phase_bags.get(phase, []) as Array
			var observed: Array[String] = []
			for _index in range(configured.size()):
				observed.append(enemy._next_boss_skill())
			for skill_id in configured:
				_expect(str(skill_id) in observed, "%d层Boss第%d阶段技能袋丢失%s" % [floor_number, phase, skill_id], failures)
		enemy.queue_free()

		var room := DungeonRoom3D.new()
		room.configure({
			"room_id": "verify_boss_%d" % floor_number,
			"room_type": "BOSS", "size_class": "arena", "seed": floor_number,
			"custom_dimensions": Vector2(90.0, 90.0),
		})
		room.set_meta("arena_asset_id", arena_id)
		room.set_meta("arena_scene", str(profile.get("arena_scene", "")))
		add_child(room)
		room.ensure_detail_built()
		var dressing := room.find_child("BossArenaDressing", true, false)
		_expect(dressing != null and str(dressing.get_meta("asset_id", "")) == arena_id, "%d层Boss场地未装配" % floor_number, failures)
		var cover_count := 0
		for body in room.find_children("*", "StaticBody3D", true, false):
			if body.has_meta("boss_arena_cover"):
				cover_count += 1
		var expected_cover_count := 8 if floor_number == 95 else 6 if floor_number == 90 else 5
		_expect(cover_count == expected_cover_count, "%d层Boss掩体碰撞数错误：%d/%d" % [floor_number, cover_count, expected_cover_count], failures)
		room.queue_free()

	await get_tree().process_frame
	if failures.is_empty():
		print("UNIQUE_BOSS_CONTENT_FLOW_OK: 95/90/85 unique models, arenas, phase skills and cover collisions pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
