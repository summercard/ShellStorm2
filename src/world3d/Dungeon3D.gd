class_name Dungeon3D
extends Node3D
## 四主题关卡共用的 3D 运行时。MapThemeProfile 保留原玩法配方，DungeonTheme3D 负责空间美术；
## 随机地图、房间内容、敌人、撤离和结算只有这一套实现。

signal generation_completed(snapshot: Dictionary)
signal run_completed(success: bool, summary: Dictionary)

const ROOM_SCENE: PackedScene = preload("res://assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d_v001.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const EXTRACTION_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_extraction_beacon_root_top3d_v001.tscn")

@export var gameplay_theme: MapThemeProfile
@export var visual_theme: DungeonTheme3D
@export var run_seed_override := -1
@export var test_mode := false

@onready var player: Player3D = $Player3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var title_label: Label = $HUD/TopBar/Margin/HBox/TitleLabel
@onready var seed_label: Label = $HUD/TopBar/Margin/HBox/SeedLabel
@onready var hp_label: Label = $HUD/TopBar/Margin/HBox/HPLabel
@onready var ammo_label: Label = $HUD/TopBar/Margin/HBox/AmmoLabel
@onready var room_label: Label = $HUD/TopBar/Margin/HBox/RoomLabel
@onready var loot_label: Label = $HUD/TopBar/Margin/HBox/LootLabel
@onready var status_label: Label = $HUD/StatusPanel/Margin/StatusLabel
@onready var extraction_bar: ProgressBar = $HUD/ExtractionPanel/Margin/VBox/ExtractionBar
@onready var extraction_panel: PanelContainer = $HUD/ExtractionPanel

var run_seed := 1
var _rng := RandomNumberGenerator.new()
var _rooms: Array[DungeonRoom3D] = []
var _room_by_id: Dictionary = {}
var _records: Array[Dictionary] = []
var _alive_by_room: Dictionary = {}
var _spawned_rooms: Dictionary = {}
var _run_loot: Array[Dictionary] = []
var _run_value := 0
var _kills := 0
var _completed := false
var _extraction: ExtractionBeacon3D = null
var _current_room_id := ""


func _ready() -> void:
	if gameplay_theme == null:
		gameplay_theme = load("res://data/map_themes/iron_frontier.tres") as MapThemeProfile
	if visual_theme == null:
		visual_theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres") as DungeonTheme3D
	run_seed = run_seed_override
	if run_seed < 0:
		run_seed = LevelSelect.selected_seed if LevelSelect != null and LevelSelect.selected_seed >= 0 else int(Time.get_unix_time_from_system()) ^ randi()
	_rng.seed = run_seed
	_configure_environment()
	_generate_layout()
	player.set_combat_enabled(true)
	player.hp_changed.connect(_on_player_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.presentation_state_changed.connect(_on_player_state_changed)
	player.global_position = Vector3(0, 0.05, 0)
	_on_player_hp_changed(player.current_hp, player.max_hp)
	var weapon_snapshot := player.get_weapon_snapshot()
	_on_ammo_changed(int(weapon_snapshot.get("current_ammo", 0)), int(weapon_snapshot.get("magazine_size", 0)))
	title_label.text = "%s · 3D行动区" % gameplay_theme.display_name
	seed_label.text = "SEED %d" % run_seed
	status_label.text = gameplay_theme.fantasy
	generation_completed.emit(get_generation_snapshot())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _completed:
		get_tree().paused = not get_tree().paused


func _configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = visual_theme.fog_color.darkened(0.32)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = visual_theme.ambient_color
	environment.ambient_light_energy = visual_theme.ambient_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.08
	environment.fog_enabled = true
	environment.fog_light_color = visual_theme.fog_color.lightened(0.13)
	environment.fog_light_energy = 0.78
	environment.fog_density = visual_theme.fog_density
	environment.fog_height = 0.0
	environment.fog_height_density = 0.12
	world_environment.environment = environment
	key_light.light_color = visual_theme.key_light_color.lerp(Color(1.0, 0.54, 0.24), 0.18)
	key_light.light_energy = 0.52


func _generate_layout() -> void:
	_build_records()
	for record in _records:
		var room := ROOM_SCENE.instantiate() as DungeonRoom3D
		room.configure({
			"room_id": record["id"], "room_type": record["type"], "size_class": record["size"],
			"doors": record["doors"], "theme": visual_theme,
			"seed": run_seed + int(record["index"]) * 104729, "is_main_path": record["main"],
		})
		room.position = record["position"]
		$GeneratedRooms.add_child(room)
		_rooms.append(room)
		_room_by_id[room.room_id] = room
		room.player_entered.connect(_on_room_entered)
		room.prop_searched.connect(_on_prop_searched)
		room.service_activated.connect(_on_service_activated)
	for record in _records:
		if str(record.get("parent", "")).is_empty():
			continue
		var parent: DungeonRoom3D = _room_by_id.get(str(record["parent"])) as DungeonRoom3D
		var child: DungeonRoom3D = _room_by_id.get(str(record["id"])) as DungeonRoom3D
		if parent != null and child != null:
			_build_corridor(parent.global_position, child.global_position, int(record["index"]))
	_create_extraction()


func _build_records() -> void:
	_records.clear()
	var path_length := int(gameplay_theme.get_layout_rule("path_length", 6))
	var sequence: Array = gameplay_theme.get_layout_rule("path_sequence", ["COMBAT", "SCAVENGE", "EVENT"])
	var spacing := 25.0
	_records.append(_record("start", "START", "medium", Vector3.ZERO, ["east"], true, "", 0))
	for index in range(1, path_length + 1):
		var room_type := str(sequence[(index - 1) % sequence.size()])
		var size := _room_size_for(room_type, index)
		var doors: Array[String] = ["west", "east"]
		_records.append(_record("main_%02d" % index, room_type, size, Vector3(index * spacing, 0, 0), doors, true, "main_%02d" % (index - 1) if index > 1 else "start", index))
	var boss_index := path_length + 1
	_records.append(_record("boss", "BOSS", "large", Vector3(boss_index * spacing, 0, 0), ["west", "east"], true, "main_%02d" % path_length, boss_index))
	_records.append(_record("extraction", "EXTRACTION", "medium", Vector3((boss_index + 1) * spacing, 0, 0), ["west"], true, "boss", boss_index + 1))

	var branch_types: Array[String] = gameplay_theme.required_branch_types.duplicate()
	var chance := float(gameplay_theme.get_layout_rule("branch_chance", 0.5))
	var optional_types := ["SCAVENGE", "STORAGE", "EVENT", "TRAP"]
	for optional in optional_types:
		if _rng.randf() <= chance * 0.42:
			branch_types.append(optional)
	var used_parents: Dictionary = {}
	for branch_index in range(branch_types.size()):
		var parent_index := 1 + ((branch_index * 2 + _rng.randi_range(0, maxi(1, path_length - 2))) % path_length)
		while used_parents.has(parent_index) and used_parents.size() < path_length:
			parent_index = 1 + parent_index % path_length
		used_parents[parent_index] = true
		var sign_z := -1.0 if branch_index % 2 == 0 else 1.0
		var parent_id := "main_%02d" % parent_index
		var parent_record: Dictionary = _find_record(parent_id)
		var parent_doors: Array = parent_record["doors"]
		parent_doors.append("north" if sign_z < 0.0 else "south")
		var branch_id := "branch_%02d" % (branch_index + 1)
		var branch_position := Vector3(parent_index * spacing, 0, sign_z * 22.0)
		var branch_doors: Array[String] = ["south" if sign_z < 0.0 else "north"]
		_records.append(_record(branch_id, branch_types[branch_index], _room_size_for(branch_types[branch_index], branch_index), branch_position, branch_doors, false, parent_id, boss_index + 2 + branch_index))


func _record(id: String, type_id: String, size: String, position: Vector3, doors: Array[String], main: bool, parent: String, index: int) -> Dictionary:
	return {"id": id, "type": type_id, "size": size, "position": position, "doors": doors, "main": main, "parent": parent, "index": index}


func _find_record(id: String) -> Dictionary:
	for record in _records:
		if record["id"] == id:
			return record
	return {}


func _room_size_for(type_id: String, index: int) -> String:
	if type_id in ["BOSS", "ELITE", "STORAGE"]:
		return "large"
	if type_id in ["MERCHANT", "UPGRADE", "EVENT"]:
		return "small" if index % 2 == 0 else "medium"
	return ["small", "medium", "medium", "large"][index % 4]


func _build_corridor(from: Vector3, to: Vector3, index: int) -> void:
	var center := (from + to) * 0.5
	var delta := to - from
	var horizontal := absf(delta.x) > absf(delta.z)
	var length := absf(delta.x) if horizontal else absf(delta.z)
	var size := Vector3(length, 0.26, 3.8) if horizontal else Vector3(3.8, 0.26, length)
	var body := StaticBody3D.new()
	body.name = "Corridor_%02d" % index
	body.position = center + Vector3(0, -0.12, 0)
	body.collision_layer = 1
	body.collision_mask = 0
	$GeneratedCorridors.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = visual_theme.floor_color.lightened(0.025)
	material.metallic = 0.46
	material.roughness = 0.74
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _create_extraction() -> void:
	var room: DungeonRoom3D = _room_by_id.get("extraction") as DungeonRoom3D
	if room == null:
		return
	_extraction = EXTRACTION_SCENE.instantiate() as ExtractionBeacon3D
	_extraction.configure(visual_theme.accent_color, 4.0)
	room.add_child(_extraction)
	_extraction.extraction_started.connect(_on_extraction_started)
	_extraction.extraction_progress.connect(_on_extraction_progress)
	_extraction.extraction_cancelled.connect(_on_extraction_cancelled)
	_extraction.extraction_completed.connect(_on_extraction_completed)


func _on_room_entered(room: DungeonRoom3D) -> void:
	_current_room_id = room.room_id
	room_label.text = "%s · %s/%s" % [room.room_id, room.room_type, room.size_class.to_upper()]
	if _spawned_rooms.has(room.room_id):
		return
	_spawned_rooms[room.room_id] = true
	if room.room_type in ["COMBAT", "ELITE", "BOSS", "TRAP"]:
		_spawn_room_enemies(room)
	else:
		room.cleared = true
		status_label.text = _room_status(room.room_type)


func _spawn_room_enemies(room: DungeonRoom3D) -> void:
	var count := 1 if room.room_type == "BOSS" else 2 + visual_theme.difficulty_rank / 2
	if room.size_class == "large" and room.room_type != "BOSS":
		count += 1
	_alive_by_room[room.room_id] = count
	for index in range(count):
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		enemy.room_id = room.room_id
		var kind := "boss" if room.room_type == "BOSS" else visual_theme.enemy_pool[_rng.randi_range(0, visual_theme.enemy_pool.size() - 1)]
		enemy.enemy_kind = kind
		$ActiveEnemies.add_child(enemy)
		var points := room.enemy_spawn_points
		enemy.global_position = points[index % points.size()] if not points.is_empty() else room.global_position
		enemy.killed.connect(_on_enemy_killed)
		enemy.summon_requested.connect(_on_summon_requested)
	status_label.text = "区域警戒：%d 个敌对信号" % count


func _on_summon_requested(source: Enemy3D, count: int) -> void:
	if source.ai_state == "dead" or not _alive_by_room.has(source.room_id):
		return
	for index in range(mini(3, count)):
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		enemy.room_id = source.room_id
		enemy.enemy_kind = "melee_chaser"
		$ActiveEnemies.add_child(enemy)
		enemy.global_position = source.global_position + Vector3(cos(index * TAU / maxf(1.0, count)) * 1.8, 0, sin(index * TAU / maxf(1.0, count)) * 1.8)
		enemy.killed.connect(_on_enemy_killed)
		enemy.summon_requested.connect(_on_summon_requested)
		_alive_by_room[source.room_id] = int(_alive_by_room[source.room_id]) + 1


func _on_enemy_killed(enemy: Enemy3D, loot: Dictionary) -> void:
	_kills += 1
	_run_value += int(loot.get("scrap", 0))
	if not _alive_by_room.has(enemy.room_id):
		return
	_alive_by_room[enemy.room_id] = maxi(0, int(_alive_by_room[enemy.room_id]) - 1)
	if int(_alive_by_room[enemy.room_id]) > 0:
		status_label.text = "残余敌对信号：%d" % int(_alive_by_room[enemy.room_id])
		return
	var room: DungeonRoom3D = _room_by_id.get(enemy.room_id) as DungeonRoom3D
	if room != null:
		room.cleared = true
	status_label.text = "房间肃清 · 可继续搜索或推进"
	if enemy.room_id == "boss" and _extraction != null:
		_extraction.set_locked(false)
		status_label.text = "Boss 已清除 · 撤离信标已解锁"
	_refresh_loot_label()


func _on_prop_searched(_room: DungeonRoom3D, loot: Dictionary) -> void:
	_run_loot.append(loot.duplicate(true))
	_run_value += int(loot.get("value", 0))
	status_label.text = "取得 %s · 价值 %d" % [loot.get("name", "未知物资"), loot.get("value", 0)]
	_refresh_loot_label()


func _on_service_activated(_room: DungeonRoom3D, station: ServiceStation3D) -> void:
	match station.station_type:
		"merchant":
			if _run_value >= 8 and player.current_hp < player.max_hp:
				_run_value -= 8
				player.heal(28)
				status_label.text = "拾荒商：消耗 8 价值，修复 28 生命"
			else:
				status_label.text = "拾荒商：需要 8 价值或当前无需修复"
		"upgrade":
			var bullets := BlueprintRegistry.get_available_bullets(99)
			if not bullets.is_empty():
				var next_index: int = (absi(player.weapon.bullet_id.hash()) + 1) % bullets.size()
				player.equip_weapon(player.weapon.gun_id, str(bullets[next_index]["item_id"]))
				status_label.text = "改造完成：弹药模块切换为 %s" % bullets[next_index]["display_name"]
		"event":
			if _rng.randf() < 0.5:
				player.heal(18)
				status_label.text = "异常信号稳定：恢复 18 生命"
			else:
				_run_value += 12
				status_label.text = "异常信号解码：获得 12 价值"
	_refresh_loot_label()


func _on_extraction_started(_duration: float) -> void:
	extraction_panel.visible = true
	extraction_bar.value = 0.0
	status_label.text = "撤离同步开始 · 保持在信标范围内"


func _on_extraction_progress(progress: float) -> void:
	extraction_bar.value = progress * 100.0


func _on_extraction_cancelled() -> void:
	extraction_panel.visible = false
	status_label.text = "撤离中断"


func _on_extraction_completed() -> void:
	_finish_run(true)


func _on_player_hp_changed(current: int, maximum: int) -> void:
	hp_label.text = "HP %d/%d" % [current, maximum]
	if current <= 0:
		_finish_run(false)


func _on_ammo_changed(current: int, maximum: int) -> void:
	ammo_label.text = "AMMO %d/%d" % [current, maximum]


func _on_player_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == "dead":
		status_label.text = "行动失败 · 防护体失去响应"


func _finish_run(success: bool) -> void:
	if _completed:
		return
	_completed = true
	player.set_input_locked(true)
	extraction_panel.visible = false
	var summary := {"success": success, "kills": _kills, "value": _run_value, "loot": _run_loot.duplicate(true), "seed": run_seed, "theme_id": gameplay_theme.theme_id}
	if not test_mode:
		BaseManager.record_run(success, _kills)
		if success:
			BaseManager.add_extraction_points(_run_value)
			BaseManager.add_extraction_loot_items(_run_loot)
	status_label.text = "撤离成功 · %d 击杀 · %d 价值" % [_kills, _run_value] if success else "行动失败 · 本局物资遗失"
	run_completed.emit(success, summary)
	if not test_mode:
		await get_tree().create_timer(1.6).timeout
		get_tree().change_scene_to_file("res://scenes/BaseWorld3D.tscn")


func _refresh_loot_label() -> void:
	loot_label.text = "LOOT %d件 / %d价值" % [_run_loot.size(), _run_value]


func _room_status(type_id: String) -> String:
	return {
		"START": "废土入口已建立定位", "SCAVENGE": "搜索区：检查带提示的容器",
		"STORAGE": "大型库存区：注意占地与退路", "MERCHANT": "安全补给终端",
		"UPGRADE": "武器改造终端", "EVENT": "检测到可交互异常信号",
		"EXTRACTION": "撤离区：信标仍受 Boss 干扰",
	}.get(type_id, "区域暂时安全")


func get_generation_snapshot() -> Dictionary:
	var branch_types: Array[String] = []
	var size_counts := {"small": 0, "medium": 0, "large": 0}
	var record_summary: Array[Dictionary] = []
	for record in _records:
		if not bool(record["main"]):
			branch_types.append(str(record["type"]))
		size_counts[record["size"]] = int(size_counts.get(record["size"], 0)) + 1
		record_summary.append({"id": record["id"], "type": record["type"], "size": record["size"], "position": record["position"], "main": record["main"], "parent": record["parent"]})
	return {
		"theme_id": gameplay_theme.theme_id, "visual_theme_id": visual_theme.theme_id, "seed": run_seed,
		"room_count": _records.size(), "branch_count": branch_types.size(), "branch_types": branch_types,
		"required_branch_types": gameplay_theme.required_branch_types.duplicate(), "size_counts": size_counts,
		"records": record_summary, "has_extraction": _extraction != null, "is_3d": true,
	}


func force_enter_room_for_test(room_id: String) -> void:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room != null:
		_on_room_entered(room)


func force_unlock_extraction_for_test() -> void:
	if _extraction != null:
		_extraction.set_locked(false)


func force_extract_for_test() -> void:
	force_unlock_extraction_for_test()
	if _extraction != null:
		_extraction.force_complete_for_test()
