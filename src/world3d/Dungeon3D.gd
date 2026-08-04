class_name Dungeon3D
extends Node3D
## 四主题关卡共用的 3D 运行时。MapThemeProfile 保留原玩法配方，DungeonTheme3D 负责空间美术；
## 随机地图、房间内容、敌人、撤离和结算只有这一套实现。

signal generation_completed(snapshot: Dictionary)
signal run_completed(success: bool, summary: Dictionary)
signal kill_recorded()
signal room_cleared(room_data)
signal room_entered(room_data)

const ROOM_SCENE: PackedScene = preload("res://assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d_v001.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const EXTRACTION_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_extraction_beacon_root_top3d_v001.tscn")
const KEY_SCRIPT := preload("res://src/world3d/RoomKeyPickup3D.gd")
const GROUND_LOOT_SCRIPT := preload("res://src/world3d/GroundLootPickup3D.gd")
const WORKBENCH_SCENE: PackedScene = preload("res://scenes/WorkbenchPanel.tscn")
const CORRIDOR_FLOOR_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_floor_segment.tscn")
const CORRIDOR_WALL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_wall_segment.tscn")
const CORRIDOR_CEILING_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_ceiling_segment.tscn")
const CORRIDOR_STAIR_TREAD_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_stair_tread.tscn")
const EXTRACTION_MID_PROGRESS := 0.36
const EXTRACTION_FINAL_PROGRESS := 0.70
const HOSTILE_ROOM_TYPES: Array[String] = GameDesignConfig.ROOM_TYPES_WITH_HOSTILES
const ENEMY_FILL_ATTEMPT_LIMIT := 4

@export var gameplay_theme: MapThemeProfile
@export var visual_theme: DungeonTheme3D
@export var run_seed_override := -1
@export var test_mode := false
@export_file("*.tscn") var return_scene_path := GameDesignConfig.BASE_SCENE_3D

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
@onready var minimap: DungeonMinimap3D = $HUD/DungeonMinimap3D
@onready var low_health_vignette: ColorRect = $HUD/LowHealthVignette

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
var _standard_extraction: ExtractionBeacon3D = null
var _emergency_extraction: ExtractionBeacon3D = null
var _conditional_extractions: Dictionary = {}
var _active_extraction_beacon: ExtractionBeacon3D = null
var _extraction_defense_active := false
var _extraction_mid_wave_spawned := false
var _extraction_wave_2_spawned := false
var _extraction_wave_3_spawned := false
var _extraction_final_wave_spawned := false
var _last_player_hp := -1
var _current_room_id := ""
var _room_neighbors: Dictionary = {}
var _open_edges: Dictionary = {}
var _corridor_by_edge: Dictionary = {}
var _spawned_key_rooms: Dictionary = {}
var _room_key_count := 1
var _enemy_nodes_by_room: Dictionary = {}
var _room_wave_queues: Dictionary = {}
var _room_wave_numbers: Dictionary = {}
var _room_wave_totals: Dictionary = {}
var _wave_spawn_pending: Dictionary = {}
var _loot_module: LootModule
var _monster_injector: MonsterInjector
var _inventory: InventoryModule
var _insurance: InsuranceModule
var _death_settlement: DeathSettlementModule
var _inventory_ui: InventoryUI
var _workbench_panel: WorkbenchPanel
var _merchant_ui: MerchantUI
var _trade_extraction_unlocked := false
var _door_prompt_accumulator := 0.0
var _door_fate_active := false
var _door_fate_choices: Array[FateCard] = []
var _fate_overlay: Control
var _map_fate_triggers: MapFateTriggers
var last_killed_enemy_data: Dictionary = {}
var _resolved_event_rooms: Dictionary = {}
var _next_chest_quality_boost := 0
var _extra_loot_next_chest := false
var _bless_dead_active := false
var _bless_dead_threshold := 0.30
var _bless_dead_remaining := 0.0
var _bless_dead_bonus := 0.10
var _bless_dead_triggered := false
var _starter_cache_opened := false
var _boss_panel: PanelContainer = null
var _boss_label: Label = null
var _boss_bar: ProgressBar = null
var _active_boss: Enemy3D = null


func _ready() -> void:
	add_to_group("room_game_mode")
	if gameplay_theme == null:
		gameplay_theme = load("res://data/map_themes/iron_frontier.tres") as MapThemeProfile
	if visual_theme == null:
		visual_theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres") as DungeonTheme3D
	run_seed = run_seed_override
	if run_seed < 0:
		run_seed = LevelSelect.selected_seed if LevelSelect != null and LevelSelect.selected_seed >= 0 else int(Time.get_unix_time_from_system()) ^ randi()
	_rng.seed = run_seed
	_setup_run_modules()
	_map_fate_triggers = MapFateTriggers.new()
	_map_fate_triggers.name = "MapFateTriggers3D"
	add_child(_map_fate_triggers)
	_install_holographic_hud_style()
	_configure_environment()
	_generate_layout()
	player.set_combat_enabled(true)
	FateCardGameBridge.set_player(player)
	player.hp_changed.connect(_on_player_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.presentation_state_changed.connect(_on_player_state_changed)
	player.global_position = Vector3(0, 0.05, 0)
	_on_room_entered(_room_by_id.get("start") as DungeonRoom3D)
	_on_player_hp_changed(player.current_hp, player.max_hp)
	var weapon_snapshot := player.get_weapon_snapshot()
	_on_ammo_changed(int(weapon_snapshot.get("current_ammo", 0)), int(weapon_snapshot.get("magazine_size", 0)))
	title_label.text = "%s · 3D行动区" % gameplay_theme.display_name
	seed_label.text = "SEED %d" % run_seed
	status_label.text = "%s · 初始钥匙 1，把战利品安全带到撤离点" % gameplay_theme.fantasy
	_refresh_loot_label()
	generation_completed.emit(get_generation_snapshot())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not _completed:
		var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
		if room != null:
			var door_info := room.get_nearest_door(player.global_position)
			if not door_info.is_empty() and not bool(door_info.get("is_open", false)):
				get_viewport().set_input_as_handled()
				_try_open_room_door(str(door_info.get("target_room_id", "")))


func _process(delta: float) -> void:
	_tick_bless_dead(delta)
	if minimap != null and player != null:
		minimap.set_player_state(
			player.global_position,
			player.aim_direction
		)
	_door_prompt_accumulator += delta
	if _door_prompt_accumulator < 0.08:
		return
	_door_prompt_accumulator = 0.0
	for room in _rooms:
		if room.room_id != _current_room_id:
			room.hide_door_prompts()
	var current := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if current != null and player != null:
		current.get_nearest_door(player.global_position)


func _setup_run_modules() -> void:
	GameManager.currency = 0
	GameManager.currency_changed.emit(0)
	_inventory = InventoryModule.new(12)
	_insurance = InsuranceModule.new(2)
	_death_settlement = DeathSettlementModule.new()
	_loot_module = LootModule.new()
	_loot_module.set_seed(run_seed ^ 0x4C4F4F54)
	_monster_injector = MonsterInjector.new()
	_monster_injector.set_seed(run_seed ^ 0x454E454D)
	_monster_injector.set_theme_profile(gameplay_theme)
	if not test_mode and BaseManager != null:
		for staged in BaseManager.consume_pending_loadout():
			if not staged is Dictionary:
				continue
			var item := (staged as Dictionary).duplicate(true)
			var requested := int(item.get("count", 1))
			var added := _inventory.add_item(item, requested)
			if added < requested:
				item["count"] = requested - added
				BaseManager.add_vault_item(item)
	_inventory.inventory_changed.connect(_refresh_loot_label)
	GameManager.currency_changed.connect(_on_run_currency_changed)
	_inventory_ui = InventoryUI.new()
	_inventory_ui.name = "InventoryUI3D"
	_inventory_ui.accept_tab_shortcut = true
	$HUD.add_child(_inventory_ui)
	_inventory_ui.set_inventory_module(_inventory)
	_inventory_ui.set_insurance_module(_insurance)
	_inventory_ui.set_weapon_tree(player.get_weapon_tree())
	_inventory_ui.item_to_insurance_requested.connect(_on_insure_item_requested)
	_inventory_ui.item_extraction_requested.connect(_on_claim_insurance_requested)
	_inventory_ui.item_clicked.connect(_on_inventory_item_clicked)
	_inventory_ui.inventory_open_changed.connect(_on_inventory_open_changed)


func _install_holographic_hud_style() -> void:
	var top_bar := $HUD/TopBar as PanelContainer
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.008, 0.025, 0.038, 0.92)
	top_style.border_color = Color(0.14, 0.74, 0.86, 0.82)
	top_style.border_width_left = 2
	top_style.border_width_top = 1
	top_style.border_width_right = 2
	top_style.border_width_bottom = 3
	top_style.corner_radius_top_left = 5
	top_style.corner_radius_top_right = 5
	top_style.corner_radius_bottom_left = 5
	top_style.corner_radius_bottom_right = 5
	top_style.shadow_color = Color(0.0, 0.28, 0.38, 0.38)
	top_style.shadow_size = 8
	top_bar.add_theme_stylebox_override("panel", top_style)

	var status_panel := $HUD/StatusPanel as PanelContainer
	var status_style := top_style.duplicate() as StyleBoxFlat
	status_style.bg_color = Color(0.018, 0.030, 0.038, 0.88)
	status_style.border_color = Color(0.92, 0.55, 0.18, 0.72)
	status_style.border_width_left = 4
	status_style.border_width_bottom = 1
	status_style.shadow_color = Color(0.40, 0.16, 0.02, 0.24)
	status_panel.add_theme_stylebox_override("panel", status_style)

	var extraction_style := top_style.duplicate() as StyleBoxFlat
	extraction_style.bg_color = Color(0.008, 0.044, 0.046, 0.94)
	extraction_style.border_color = Color(0.22, 1.0, 0.66, 0.88)
	extraction_panel.add_theme_stylebox_override("panel", extraction_style)

	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.46, 0.96, 1.0))
	seed_label.add_theme_color_override("font_color", Color(0.46, 0.62, 0.70))
	hp_label.add_theme_color_override("font_color", Color(0.36, 1.0, 0.62))
	ammo_label.add_theme_color_override("font_color", Color(0.40, 0.84, 1.0))
	room_label.add_theme_color_override("font_color", Color(0.72, 0.88, 0.94))
	loot_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
	status_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.84))
	for label in [seed_label, hp_label, ammo_label, room_label, loot_label]:
		(label as Label).add_theme_font_size_override("font_size", 14)

	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color = Color(0.012, 0.08, 0.075, 0.92)
	progress_background.set_corner_radius_all(3)
	extraction_bar.add_theme_stylebox_override("background", progress_background)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color(0.18, 0.96, 0.62)
	progress_fill.set_corner_radius_all(3)
	progress_fill.shadow_color = Color(0.10, 0.88, 0.54, 0.45)
	progress_fill.shadow_size = 5
	extraction_bar.add_theme_stylebox_override("fill", progress_fill)

	var control_hint := $HUD/ControlHint as Label
	var vision_hint := $HUD/VisionHint as Label
	control_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.08, 0.92))
	control_hint.add_theme_constant_override("outline_size", 4)
	vision_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.08, 0.92))
	vision_hint.add_theme_constant_override("outline_size", 4)


func _on_inventory_open_changed(opened: bool) -> void:
	if opened and _has_exclusive_modal():
		_inventory_ui.set_inventory_panel_open(false)
		status_label.text = "先完成当前交互，再打开背包"
		return
	_sync_player_input_lock()
	if opened:
		status_label.text = "背包已打开 · 左键使用/装备，右键存入保险格"
	else:
		status_label.text = "背包已关闭 · 继续搜索、战斗或撤离"


func _has_exclusive_modal() -> bool:
	# 撤离不再锁定输入：玩家可以自由移动/开枪/翻滚；
	# _extraction_defense_active 仅作为“撤离进行中”标记存在。
	return (
		_completed
		or _door_fate_active
		or (_workbench_panel != null and is_instance_valid(_workbench_panel))
		or (_merchant_ui != null and is_instance_valid(_merchant_ui) and _merchant_ui.visible)
	)


func _sync_player_input_lock() -> void:
	if player == null:
		return
	var inventory_open := _inventory_ui != null and _inventory_ui.is_inventory_open()
	player.set_input_locked(_has_exclusive_modal() or inventory_open)


func _close_inventory_for_modal() -> void:
	if _inventory_ui != null and _inventory_ui.is_inventory_open():
		_inventory_ui.set_inventory_panel_open(false)


func try_close_modal_for_pause() -> bool:
	if _inventory_ui != null and _inventory_ui.is_inventory_open():
		_inventory_ui.set_inventory_panel_open(false)
		return true
	if _workbench_panel != null and is_instance_valid(_workbench_panel):
		handle_esc()
		return true
	if _merchant_ui != null and is_instance_valid(_merchant_ui) and _merchant_ui.visible:
		_merchant_ui.hide_merchant()
		return true
	if _door_fate_active:
		status_label.text = "必须先选择一张门后命运卡片"
		return true
	return false


func _configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = visual_theme.fog_color.darkened(0.32)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = visual_theme.ambient_color
	# 暗室保留低照度层次而非纯黑；玩家真实灯光只影响材质，玩法显隐仍完全独立。
	environment.ambient_light_energy = clampf(visual_theme.ambient_energy * 0.32, 0.16, 0.22)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.18
	environment.fog_enabled = true
	environment.fog_light_color = visual_theme.fog_color.lightened(0.13)
	environment.fog_light_energy = 0.36
	environment.fog_density = visual_theme.fog_density
	environment.fog_height = 0.0
	environment.fog_height_density = 0.0  # 纯距离雾，关闭高度差异
	world_environment.environment = environment
	key_light.light_color = visual_theme.key_light_color.lerp(Color(1.0, 0.54, 0.24), 0.18)
	key_light.light_energy = 0.10
	key_light.shadow_enabled = true
	key_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	key_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER


func _generate_layout() -> void:
	_build_records()
	_build_topology()
	minimap.configure(_records, _open_edges)
	minimap.reveal_room("start")
	for record in _records:
		var room := ROOM_SCENE.instantiate() as DungeonRoom3D
		room.configure({
			"room_id": record["id"], "room_type": record["type"], "size_class": record["size"],
			"doors": record["doors"], "door_targets": record.get("door_targets", {}), "theme": visual_theme,
			"door_policies": _door_policies_for_record(record),
			"seed": run_seed + int(record["index"]) * 104729, "is_main_path": record["main"],
			"custom_dimensions": record.get("custom_dimensions", Vector2.ZERO),
			"tower_module_shell": bool(record.get("tower_module_shell", false)),
			"open_wall_directions": record.get("open_wall_directions", []),
		})
		room.position = record["position"]
		$GeneratedRooms.add_child(room)
		_rooms.append(room)
		_room_by_id[room.room_id] = room
		room.player_entered.connect(_on_room_entered)
		room.prop_searched.connect(_on_prop_searched)
		room.service_activated.connect(_on_service_activated)
	_plan_room_layout()
	for record in _records:
		if str(record.get("parent", "")).is_empty():
			continue
		var parent: DungeonRoom3D = _room_by_id.get(str(record["parent"])) as DungeonRoom3D
		var child: DungeonRoom3D = _room_by_id.get(str(record["id"])) as DungeonRoom3D
		if parent != null and child != null:
			_build_corridor(parent, child, int(record["index"]))
	_create_extraction()


func _build_records() -> void:
	_records.clear()
	var path_length := int(gameplay_theme.get_layout_rule("path_length", 6))
	var sequence: Array = gameplay_theme.get_layout_rule("path_sequence", ["COMBAT", "SCAVENGE", "EVENT"])
	# 最大 ARENA 仍保留 6m 以上门外缓冲，避免房间扩大后互相穿插。
	var spacing := 62.0
	_records.append(_record("start", "START", "medium", Vector3.ZERO, ["east"], true, "", 0))
	for index in range(1, path_length + 1):
		var room_type := str(sequence[(index - 1) % sequence.size()])
		var size := _room_size_for(room_type, index)
		var doors: Array[String] = ["west", "east"]
		_records.append(_record("main_%02d" % index, room_type, size, Vector3(index * spacing, 0, 0), doors, true, "main_%02d" % (index - 1) if index > 1 else "start", index))
	var boss_index := path_length + 1
	_records.append(_record("boss", "BOSS", "arena", Vector3(boss_index * spacing, 0, 0), ["west", "east"], true, "main_%02d" % path_length, boss_index))
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
		var branch_position := Vector3(parent_index * spacing, 0, sign_z * 50.0)
		var branch_doors: Array[String] = ["south" if sign_z < 0.0 else "north"]
		_records.append(_record(branch_id, branch_types[branch_index], _room_size_for(branch_types[branch_index], branch_index), branch_position, branch_doors, false, parent_id, boss_index + 2 + branch_index))

	var basement_created := false
	if _rng.randf() < float(gameplay_theme.get_layout_rule("basement_chance", 0.30)):
		basement_created = _try_add_vertical_branch("basement", "STAIRS_DOWN", -1, 2, path_length)
	if _rng.randf() < float(gameplay_theme.get_layout_rule("upper_chance", 0.20)):
		var access_type := "ELEVATOR" if visual_theme.difficulty_rank >= 3 else "STAIRS_UP"
		_try_add_vertical_branch("upper", access_type, 1, 1, path_length)
	# 深层主题至少展示一次原 2D 的垂直探索结构；普通主题仍完全遵循概率。
	if not basement_created and visual_theme.difficulty_rank >= 3:
		_try_add_vertical_branch("basement", "STAIRS_DOWN", -1, 2, path_length)


func _record(id: String, type_id: String, size: String, position: Vector3, doors: Array[String], main: bool, parent: String, index: int, vertical_level := 0) -> Dictionary:
	return {
		"id": id, "type": type_id, "size": size, "position": position,
		"doors": doors, "door_targets": {}, "main": main, "parent": parent,
		"index": index, "vertical_level": vertical_level,
	}


func _try_add_vertical_branch(prefix: String, access_type: String, target_level: int, room_count: int, path_length: int) -> bool:
	var parent_indices: Array[int] = []
	for index in range(2, maxi(3, path_length)):
		parent_indices.append(index)
	for shuffle_index in range(parent_indices.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, shuffle_index)
		var held := parent_indices[shuffle_index]
		parent_indices[shuffle_index] = parent_indices[swap_index]
		parent_indices[swap_index] = held
	for parent_index in parent_indices:
		var parent_id := "main_%02d" % parent_index
		var parent_record := _find_record(parent_id)
		if parent_record.is_empty():
			continue
		var parent_doors := parent_record["doors"] as Array
		var outward := "south" if "south" not in parent_doors else "north" if "north" not in parent_doors else ""
		if outward.is_empty():
			continue
		parent_doors.append(outward)
		var sign_z := 1.0 if outward == "south" else -1.0
		var parent_position := parent_record["position"] as Vector3
		var access_id := "%s_access" % prefix
		var access_position := parent_position + Vector3(0, 0, sign_z * 52.0)
		var back := "north" if outward == "south" else "south"
		_records.append(_record(
			access_id, access_type, "small", access_position, [back, outward], false,
			parent_id, _records.size(), 0
		))
		var previous_id := access_id
		for room_index in range(maxi(1, room_count)):
			var room_id := "%s_%02d" % [prefix, room_index + 1]
			var type_id := "BASEMENT" if target_level < 0 and room_index == 0 else _choose_vertical_room_type()
			var room_position := Vector3(
				parent_position.x + (54.0 * room_index), target_level * 7.5,
				parent_position.z + sign_z * 104.0
			)
			var room_doors: Array[String] = []
			room_doors.append(back if room_index == 0 else "west")
			if room_index < room_count - 1:
				room_doors.append("east")
			_records.append(_record(
				room_id, type_id, _room_size_for(type_id, room_index + 2), room_position,
				room_doors, false, previous_id, _records.size(), target_level
			))
			previous_id = room_id
		return true
	return false


func _choose_vertical_room_type() -> String:
	var weights := gameplay_theme.get_layout_rule("vertical_room_weights", {}) as Dictionary
	if weights.is_empty():
		return ["SCAVENGE", "COMBAT", "ELITE", "STORAGE", "EVENT"][_rng.randi_range(0, 4)]
	var total := 0.0
	for value in weights.values():
		total += maxf(0.0, float(value))
	var roll := _rng.randf() * maxf(0.001, total)
	for key in weights.keys():
		roll -= maxf(0.0, float(weights[key]))
		if roll <= 0.0:
			return str(key)
	return "SCAVENGE"


func _build_topology() -> void:
	_room_neighbors.clear()
	_open_edges.clear()
	for record in _records:
		_room_neighbors[str(record["id"])] = []
	for record in _records:
		var child_id := str(record["id"])
		var parent_id := str(record.get("parent", ""))
		if parent_id.is_empty():
			continue
		(_room_neighbors[parent_id] as Array).append(child_id)
		(_room_neighbors[child_id] as Array).append(parent_id)
		_open_edges[_edge_key(parent_id, child_id)] = false
		var child_pos := record["position"] as Vector3
		var parent_record := _find_record(parent_id)
		var parent_pos := parent_record["position"] as Vector3
		var parent_direction := _direction_between(parent_pos, child_pos)
		var child_direction := _opposite_direction(parent_direction)
		(parent_record["door_targets"] as Dictionary)[parent_direction] = child_id
		(record["door_targets"] as Dictionary)[child_direction] = parent_id


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _door_policy_for_edge(_from_room_id: String, _target_room_id: String) -> Dictionary:
	return {
		"requires_clear": true,
		"requires_key": true,
		"triggers_fate": true,
	}


func _door_policies_for_record(record: Dictionary) -> Dictionary:
	var policies := {}
	var room_id := str(record.get("id", ""))
	var targets := record.get("door_targets", {}) as Dictionary
	for direction in targets.keys():
		policies[str(direction)] = _door_policy_for_edge(
			room_id,
			str(targets[direction])
		)
	return policies


func _direction_between(from: Vector3, to: Vector3) -> String:
	var delta := to - from
	if absf(delta.x) >= absf(delta.z):
		return "east" if delta.x >= 0.0 else "west"
	return "south" if delta.z >= 0.0 else "north"


func _opposite_direction(direction: String) -> String:
	return {"north": "south", "south": "north", "west": "east", "east": "west"}.get(direction, "east")


func _find_record(id: String) -> Dictionary:
	for record in _records:
		if record["id"] == id:
			return record
	return {}


func _room_size_for(type_id: String, index: int) -> String:
	if type_id == "BOSS":
		return "arena"
	if type_id in ["ELITE", "BASEMENT"]:
		return "large"
	if type_id in ["STORAGE", "TRAP", "STAIRS_DOWN", "STAIRS_UP", "ELEVATOR"]:
		return "small"
	if type_id in ["MERCHANT", "UPGRADE", "EVENT"]:
		return "small" if index % 2 == 0 else "medium"
	return ["small", "medium", "medium", "large"][index % 4]


func _build_corridor(from_room: DungeonRoom3D, to_room: DungeonRoom3D, index: int) -> void:
	var from := from_room.global_position
	var to := to_room.global_position
	var delta := to - from
	var horizontal := absf(delta.x) > absf(delta.z)
	var planar_delta := Vector3(delta.x, 0, delta.z)
	var direction := planar_delta.normalized()
	var from_dimensions := from_room.get_dimensions()
	var to_dimensions := to_room.get_dimensions()
	var from_half := from_dimensions.x * 0.5 if horizontal else from_dimensions.y * 0.5
	var to_half := to_dimensions.x * 0.5 if horizontal else to_dimensions.y * 0.5
	var start := from + direction * (from_half - 0.18)
	var end := to - direction * (to_half - 0.18)
	var center := (start + end) * 0.5
	var length := maxf(0.6, start.distance_to(end))
	var body := StaticBody3D.new()
	body.name = "Corridor_%02d" % index
	body.position = center + Vector3(0, -0.12, 0)
	var is_vertical_connector := absf(end.y - start.y) > 0.01
	if horizontal and is_vertical_connector:
		var dx := end.x - start.x
		body.rotation.z = atan((end.y - start.y) / dx) if absf(dx) > 0.01 else 0.0
	elif not horizontal and is_vertical_connector:
		var dz := end.z - start.z
		body.rotation.x = -atan((end.y - start.y) / dz) if absf(dz) > 0.01 else 0.0
	body.set_meta("is_vertical_connector", is_vertical_connector)
	body.set_meta("from_room_id", from_room.room_id)
	body.set_meta("to_room_id", to_room.room_id)
	body.set_meta("height_delta", to.y - from.y)
	body.collision_layer = 1
	body.collision_mask = 0
	$GeneratedCorridors.add_child(body)
	var edge := _edge_key(from_room.room_id, to_room.room_id)
	_corridor_by_edge[edge] = body
	body.visible = false
	body.process_mode = Node.PROCESS_MODE_DISABLED
	var floor_size := Vector3(length, 0.26, 3.8) if horizontal else Vector3(3.8, 0.26, length)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = visual_theme.floor_color.lightened(0.055)
	floor_material.metallic = 0.08
	floor_material.roughness = 0.90
	_spawn_corridor_piece(body, "CorridorFloor_%02d" % index, CORRIDOR_FLOOR_PREFAB, floor_size, Vector3.ZERO, floor_material)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = visual_theme.wall_color.darkened(0.08)
	wall_material.metallic = 0.62
	wall_material.roughness = 0.58
	for side in [-1.0, 1.0]:
		var wall_size := Vector3(length, 2.25, 0.25) if horizontal else Vector3(0.25, 2.25, length)
		var wall_offset := Vector3(0, 1.25, side * 1.92) if horizontal else Vector3(side * 1.92, 1.25, 0)
		var side_index := 0 if side < 0.0 else 1
		_spawn_corridor_piece(body, "CorridorWall_%02d_%d" % [index, side_index], CORRIDOR_WALL_PREFAB, wall_size, wall_offset, wall_material)
	if is_vertical_connector:
		# 封闭楼梯间顶部与墙共同阻挡视线；台阶只做可读表现，连续斜坡承担移动碰撞。
		var ceiling_size := Vector3(length, 0.22, 3.8) if horizontal else Vector3(3.8, 0.22, length)
		_spawn_corridor_piece(body, "StairwellCeiling_%02d" % index, CORRIDOR_CEILING_PREFAB, ceiling_size, Vector3(0, 2.38, 0), wall_material)
		var step_count := maxi(5, int(length / 0.85))
		for step_index in range(step_count):
			var ratio := (float(step_index) + 0.5) / float(step_count)
			var tread_size := Vector3(length / float(step_count) * 0.82, 0.07, 3.46) if horizontal else Vector3(3.46, 0.07, length / float(step_count) * 0.82)
			var tread_offset := Vector3(
				lerpf(-length * 0.5, length * 0.5, ratio) if horizontal else 0.0,
				0.075,
				0.0 if horizontal else lerpf(-length * 0.5, length * 0.5, ratio)
			)
			_spawn_corridor_piece(body, "StairTread_%02d_%02d" % [index, step_index], CORRIDOR_STAIR_TREAD_PREFAB, tread_size, tread_offset, wall_material)


func _spawn_corridor_piece(parent: Node3D, node_name: String, prefab: PackedScene, scale_vec: Vector3, local_position: Vector3, material: StandardMaterial3D) -> void:
	if prefab == null:
		push_error("Dungeon3D: missing corridor prefab for %s" % node_name)
		return
	var instance := prefab.instantiate() as Node3D
	if instance == null:
		return
	instance.name = node_name
	instance.position = local_position
	instance.scale = scale_vec
	_apply_corridor_material_override(instance, material)
	_set_corridor_collisions_disabled(instance, true)
	parent.add_child(instance)


func _apply_corridor_material_override(root: Node, material: StandardMaterial3D) -> void:
	if material == null:
		return
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_corridor_material_override(child, material)


func _set_corridor_collisions_disabled(root: Node, disabled: bool) -> void:
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = disabled
	for child in root.get_children():
		_set_corridor_collisions_disabled(child, disabled)


## v0.1 v2 房间布局规划阶段
## 遍历所有房与门，根据门 world pos 预存 “room_door_world_<dir>” meta。
## 拼墙阶段 (_build_corner_aware_wall_run) 读这个 meta 以门 world pos 作锥点拼门洞。
func _plan_room_layout() -> void:
	for room in _rooms:
		if room == null:
			continue
		var dimensions := room.get_dimensions()
		# 1. 为每扇门算 door_offset_along（距 0 最近的 5m 段中心点），写 meta
		for direction in room.doors:
			var horizontal := direction in ["north", "south"]
			var length := dimensions.x if horizontal else dimensions.y
			if length <= 0.0:
				continue
			var module_count := maxi(1, int(round(length / 5.0)))
			# 默认门位于沿墙中心：选距 0 最近的 5m 段。
			var best_module := -1
			var best_dist := 1e9
			for module_index in range(module_count):
				var segment_center := -length * 0.5 + 5.0 * (float(module_index) + 0.5)
				var d := absf(segment_center)
				if d < best_dist:
					best_dist = d
					best_module = module_index
			var door_offset_along := -length * 0.5 + 5.0 * (float(best_module) + 0.5)
			room.set_meta("tower_wall_door_offset_%s" % direction, door_offset_along)
		# 2. meta 写完后，门 world pos 重新算（读完刚写入的 meta）→ 存 room_door_world_<dir>
		for direction in room.doors:
			var door_world: Vector3 = _room_door_world_position(room, direction)
			room.set_meta("room_door_world_%s" % direction, door_world)


## 房间门 world 位置（基类实现，默认门位于房间中心偏门所在墙中点）。
## TowerDescent3D 会重写以支持楼梯特殊情况。
func _room_door_world_position(room: DungeonRoom3D, side: String) -> Vector3:
	var outward := {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0),
	}.get(side, Vector3(-1, 0, 0)) as Vector3
	var dimensions := room.get_dimensions()
	var half_extent := dimensions.y * 0.5 if side in ["north", "south"] else dimensions.x * 0.5
	var along_axis := Vector3(1, 0, 0) if side in ["north", "south"] else Vector3(0, 0, 1)
	# 默认门距 0：门位于沿墙中心位置 (0 + 0)
	var door_offset_along := 0.0
	return room.global_position + outward * half_extent + along_axis * door_offset_along


func _create_extraction() -> void:
	var room: DungeonRoom3D = _room_by_id.get("extraction") as DungeonRoom3D
	if room == null:
		return
	_extraction = _create_extraction_beacon(room, "BOSS_KILL", 30.0, true, Vector3.ZERO)
	_conditional_extractions["BOSS_KILL"] = _extraction
	var fixed_candidates: Array[String] = []
	for record in _records:
		var candidate_id := str(record.get("id", ""))
		var candidate_role := str(record.get("role", ""))
		# TowerDescent3D 把战斗房 id 写成 floor_NN_main_XX，
		# 早期手写关卡才是 main_XX；两种 id 格式都要兼容。
		if (candidate_id.begins_with("main_") or candidate_role == "main") and int(record.get("index", 0)) >= 2:
			fixed_candidates.append(candidate_id)
	# 1. facility（99 层基地）：玩家随时撤离的兑底点，locally 始终存在。
	var facility_room := _room_by_id.get("facility") as DungeonRoom3D
	if facility_room != null:
		_standard_extraction = _create_extraction_beacon(facility_room, "STANDARD", 30.0, false, Vector3(-4.2, 0.0, 3.2))
		_conditional_extractions["STANDARD"] = _standard_extraction
	# 2. 随机战斗房：随机放置一个额外的 STANDARD 撤离点。
	if not fixed_candidates.is_empty():
		var fixed_id := fixed_candidates[_rng.randi_range(0, fixed_candidates.size() - 1)]
		var fixed_room := _room_by_id.get(fixed_id) as DungeonRoom3D
		if fixed_room != null:
			var extra := _create_extraction_beacon(fixed_room, "STANDARD", 30.0, false, Vector3(-4.2, 0.0, 3.2))
			# 非塔楼行动区没有 facility：此时随机战斗房就是唯一 STANDARD，
			# 仍需写入标准键并保存主引用，不能只登记成 BONUS 后失去测试/交互入口。
			if _standard_extraction == null:
				_standard_extraction = extra
				_conditional_extractions["STANDARD"] = extra
			else:
				_conditional_extractions["STANDARD_BONUS"] = extra


func _create_extraction_beacon(room: DungeonRoom3D, type_id: String, countdown: float, locked: bool, local_position: Vector3) -> ExtractionBeacon3D:
	if room == null:
		return null
	var beacon := EXTRACTION_SCENE.instantiate() as ExtractionBeacon3D
	beacon.configure(visual_theme.accent_color, countdown, type_id)
	room.add_child(beacon)
	beacon.position = local_position
	beacon.set_locked(locked)
	beacon.extraction_started.connect(_on_extraction_started.bind(beacon))
	beacon.extraction_progress.connect(_on_extraction_progress.bind(beacon))
	beacon.extraction_cancelled.connect(_on_extraction_cancelled.bind(beacon))
	beacon.extraction_completed.connect(_on_extraction_completed.bind(beacon))
	return beacon


func _on_room_entered(room: DungeonRoom3D) -> void:
	if room == null:
		return
	_current_room_id = room.room_id
	room_entered.emit(room)
	minimap.set_current_room(room.room_id)
	_update_room_streaming(room.room_id)
	room_label.text = "%s · %s/%s" % [room.room_id, room.room_type, room.size_class.to_upper()]
	if _spawned_rooms.has(room.room_id):
		_ensure_room_key_reward(room)
		_repair_hostile_room_progress(room)
		status_label.text = "返回已探索房间 · %s" % ("已肃清" if room.cleared else "战斗未结束")
		return
	_spawned_rooms[room.room_id] = true
	if room.room_type == "START":
		call_deferred("_spawn_starter_weapon_pickup", room)
	if room.room_type in HOSTILE_ROOM_TYPES:
		_spawn_room_enemies(room)
	elif room.room_type == "EVENT":
		room.cleared = false
		status_label.text = "事件房：使用异常信号终端决定本房命运"
	else:
		status_label.text = _room_status(room.room_type)
		_mark_room_cleared(room, room.room_type not in ["START", "EXTRACTION", "ELEVATOR"])


func _spawn_room_enemies(room: DungeonRoom3D) -> bool:
	if room == null:
		return false
	var floor := maxi(1, visual_theme.difficulty_rank)
	var floor_level := clampi(int(float(_record_index(room.room_id)) / maxf(1.0, float(_records.size() - 1)) * 3.0), 0, 3)
	var enemy_configs: Array[Dictionary] = []
	match room.room_type:
		"BOSS":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "boss", "floor": floor, "floor_level": floor_level}))
			enemy_configs.append_array(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level}))
		"ELITE":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level}))
		"TRAP":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "ambush", "count": 3 + floor / 2, "floor": floor, "floor_level": floor_level}))
		"BASEMENT":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": maxi(RoomData.FloorLevel.MEDIUM, floor_level)}))
			enemy_configs.append_array(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": maxi(RoomData.FloorLevel.MEDIUM, floor_level)}))
		_:
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": floor_level}))
			var desired := 4 + floor * 2 + (2 if room.size_class == "large" else 4 if room.size_class == "arena" else 0)
			var attempts := 0
			while enemy_configs.size() < desired and attempts < ENEMY_FILL_ATTEMPT_LIMIT:
				attempts += 1
				var generated := _monster_injector.generate_enemies({
					"type": "random", "floor": floor, "floor_level": floor_level,
				})
				if generated.is_empty():
					continue
				enemy_configs.append_array(generated)
			# 主题怪物池损坏时也不能无限循环或留下未清空的锁房。
			while enemy_configs.size() < desired:
				var fallback := _monster_injector.generate_enemies({
					"type": "safe_fallback", "floor": floor, "floor_level": floor_level,
				})
				if fallback.is_empty():
					break
				enemy_configs.append(fallback[0])
	if enemy_configs.is_empty():
		push_error("Hostile room %s generated no enemies; unlocking room to prevent a soft lock" % room.room_id)
		_alive_by_room[room.room_id] = 0
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, true)
		status_label.text = "敌群生成失败，房间已安全解锁"
		return false
	var wave_count := 1
	if room.room_type == "COMBAT":
		wave_count = [1, 2, 2, 3][floor_level]
	wave_count = clampi(wave_count, 1, maxi(1, enemy_configs.size()))
	var waves: Array = []
	var cursor := 0
	for wave_index in range(wave_count):
		var remaining := enemy_configs.size() - cursor
		var batch_size := int(ceil(float(remaining) / float(wave_count - wave_index)))
		var batch: Array[Dictionary] = []
		for _index in range(batch_size):
			batch.append(enemy_configs[cursor])
			cursor += 1
		waves.append(batch)
	var first_wave: Array[Dictionary] = waves.pop_front() as Array[Dictionary]
	_room_wave_queues[room.room_id] = waves
	_room_wave_numbers[room.room_id] = 1
	_room_wave_totals[room.room_id] = wave_count
	_enemy_nodes_by_room[room.room_id] = []
	var spawned := _spawn_enemy_batch(room, first_wave, false)
	if spawned <= 0:
		push_error("Hostile room %s failed to instantiate its first wave; unlocking room" % room.room_id)
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, true)
		status_label.text = "敌群载入失败，房间已安全解锁"
		return false
	status_label.text = "区域警戒：波次 1/%d · %d 个敌对信号" % [wave_count, spawned]
	return true


func _prepare_revealed_hostile_room(room: DungeonRoom3D) -> bool:
	if (
		room == null
		or room.room_type not in HOSTILE_ROOM_TYPES
		or _spawned_rooms.has(room.room_id)
	):
		return false
	# 房门开启后目标房间已经进入可见流送状态；首波必须在这一刻存在，
	# 不能等角色靠近触发 RoomArea 后才突然生成。AI 是否运行仍由当前房控制。
	_spawned_rooms[room.room_id] = true
	room.cleared = false
	return _spawn_room_enemies(room)


func _spawn_starter_weapon_pickup(room: DungeonRoom3D) -> void:
	if room == null or _starter_cache_opened:
		return
	_starter_cache_opened = true
	var starter := ItemRegistry.get_instance().get_item("weapon_shotgun")
	if starter.is_empty():
		return
	_spawn_loot_items(room, [starter], room.global_position + Vector3(2.1, 0.08, -1.4))
	status_label.text = "起始补给：拾取霰弹枪后按 I 打开背包并点击装备 · 墙边 E 可开中央灯"


func _spawn_enemy_batch(room: DungeonRoom3D, enemy_configs: Array[Dictionary], additive: bool, count_reserved := false) -> int:
	if room == null or enemy_configs.is_empty():
		return 0
	if not _enemy_nodes_by_room.has(room.room_id):
		_enemy_nodes_by_room[room.room_id] = []
	var spawned_count := 0
	for index in range(enemy_configs.size()):
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		if enemy == null:
			continue
		enemy.room_id = room.room_id
		$ActiveEnemies.add_child(enemy)
		enemy.configure_from_enemy_data(enemy_configs[index])
		var points := room.enemy_spawn_points
		enemy.global_position = points[index % points.size()] if not points.is_empty() else room.global_position
		enemy.killed.connect(_on_enemy_killed)
		enemy.summon_requested.connect(_on_summon_requested)
		enemy.boss_phase_changed.connect(_on_boss_phase_changed)
		enemy.health_changed.connect(_on_enemy_health_changed)
		(_enemy_nodes_by_room[room.room_id] as Array).append(enemy)
		spawned_count += 1
		var room_visible := int(room.get_room_snapshot().get("stream_state", 0)) > 0
		enemy.set_runtime_active(room.room_id == _current_room_id, room_visible)
		if enemy.enemy_kind == "boss":
			_show_boss_hud(enemy)
	if not count_reserved:
		_alive_by_room[room.room_id] = (
			int(_alive_by_room.get(room.room_id, 0)) + spawned_count
			if additive
			else spawned_count
		)
	elif spawned_count < enemy_configs.size():
		_alive_by_room[room.room_id] = maxi(
			0,
			int(_alive_by_room.get(room.room_id, 0))
			- (enemy_configs.size() - spawned_count)
		)
	return spawned_count


func _repair_hostile_room_progress(room: DungeonRoom3D) -> void:
	if room == null or room.cleared or room.room_type not in HOSTILE_ROOM_TYPES:
		return
	var live_count := 0
	var live_references: Array = []
	for value in _enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy == null or not is_instance_valid(enemy) or enemy.ai_state == "dead":
			continue
		live_references.append(enemy)
		live_count += 1
	_enemy_nodes_by_room[room.room_id] = live_references
	if live_count > 0:
		_alive_by_room[room.room_id] = live_count
		return
	_alive_by_room[room.room_id] = 0
	if _wave_spawn_pending.has(room.room_id):
		return
	var pending_waves := _room_wave_queues.get(room.room_id, []) as Array
	if not pending_waves.is_empty():
		_spawn_next_room_wave(room.room_id)
		return
	# 已记录“访问过”但没有任何活体/待刷波次时，重新建立该房战斗；
	# 若配置仍然失败，_spawn_room_enemies 会主动清房，绝不永久锁门。
	_spawn_room_enemies(room)


func _spawn_next_room_wave(room_id: String) -> void:
	_wave_spawn_pending.erase(room_id)
	if _completed or not _room_wave_queues.has(room_id):
		return
	var queue := _room_wave_queues[room_id] as Array
	if queue.is_empty():
		return
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	var batch: Array[Dictionary] = queue.pop_front() as Array[Dictionary]
	_room_wave_numbers[room_id] = int(_room_wave_numbers.get(room_id, 1)) + 1
	var spawned := _spawn_enemy_batch(room, batch, false)
	if spawned <= 0:
		push_error("Hostile room %s failed to instantiate a later wave; unlocking room" % room_id)
		_room_wave_queues[room_id] = []
		_alive_by_room[room_id] = 0
		if room != null:
			_mark_room_cleared(room, true)
		status_label.text = "增援载入失败，房间已安全解锁"
		return
	status_label.text = "增援抵达：波次 %d/%d · %d 个敌对信号" % [
		int(_room_wave_numbers[room_id]), int(_room_wave_totals.get(room_id, 1)), spawned,
	]


func _record_index(room_id: String) -> int:
	var record := _find_record(room_id)
	return int(record.get("index", 0))


func _on_summon_requested(source: Enemy3D, count: int) -> void:
	if not _alive_by_room.has(source.room_id):
		return
	if source.ai_state == "dead" and source.elite_modifier_id != "Elite.SpawnOnDeath":
		return
	var reserved_count := mini(3, count)
	_alive_by_room[source.room_id] = int(_alive_by_room[source.room_id]) + reserved_count
	call_deferred("_spawn_summoned_minions", source.room_id, source.global_position, reserved_count)


func _spawn_summoned_minions(room_id: String, origin: Vector3, count: int) -> void:
	if _completed or not _alive_by_room.has(room_id):
		return
	for index in range(count):
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		enemy.room_id = room_id
		$ActiveEnemies.add_child(enemy)
		var minion_data: Array[Dictionary] = _monster_injector.generate_enemies({"type": "minion", "floor": maxi(1, visual_theme.difficulty_rank), "floor_level": 1})
		if not minion_data.is_empty():
			enemy.configure_from_enemy_data(minion_data[index % minion_data.size()])
		enemy.global_position = origin + Vector3(cos(index * TAU / maxf(1.0, count)) * 1.8, 0, sin(index * TAU / maxf(1.0, count)) * 1.8)
		enemy.killed.connect(_on_enemy_killed)
		enemy.summon_requested.connect(_on_summon_requested)
		enemy.boss_phase_changed.connect(_on_boss_phase_changed)
		enemy.health_changed.connect(_on_enemy_health_changed)
		if not _enemy_nodes_by_room.has(room_id):
			_enemy_nodes_by_room[room_id] = []
		(_enemy_nodes_by_room[room_id] as Array).append(enemy)
		enemy.set_runtime_active(room_id == _current_room_id)


func _on_enemy_killed(enemy: Enemy3D, enemy_data: Dictionary) -> void:
	_kills += 1
	var weapon_tree := player.get_weapon_tree() if player != null else null
	if weapon_tree != null:
		weapon_tree.add_crit_on_kill_stack(1)
	if _enemy_nodes_by_room.has(enemy.room_id):
		(_enemy_nodes_by_room[enemy.room_id] as Array).erase(enemy)
	last_killed_enemy_data = enemy_data.duplicate(true)
	kill_recorded.emit()
	var drops := _loot_module.generate_enemy_loot(enemy_data)
	var has_currency := false
	for item in drops:
		if bool(item.get("is_currency", false)):
			has_currency = true
	if not has_currency:
		drops.append({"id": "__currency__", "name": "魂", "type": "currency", "count": 2 + int(enemy_data.get("floor", 1)), "is_currency": true})
	var loot_room := _room_by_id.get(enemy.room_id) as DungeonRoom3D
	if loot_room != null:
		call_deferred("_spawn_loot_items", loot_room, drops, enemy.global_position)
	if not _alive_by_room.has(enemy.room_id):
		return
	_alive_by_room[enemy.room_id] = maxi(0, int(_alive_by_room[enemy.room_id]) - 1)
	if int(_alive_by_room[enemy.room_id]) > 0:
		status_label.text = "残余敌对信号：%d" % int(_alive_by_room[enemy.room_id])
		return
	var pending_waves := _room_wave_queues.get(enemy.room_id, []) as Array
	if not pending_waves.is_empty():
		if not _wave_spawn_pending.has(enemy.room_id):
			_wave_spawn_pending[enemy.room_id] = true
			status_label.text = "本波肃清 · 1.2 秒后敌方增援抵达"
			get_tree().create_timer(1.2).timeout.connect(_spawn_next_room_wave.bind(enemy.room_id))
		return
	var room: DungeonRoom3D = _room_by_id.get(enemy.room_id) as DungeonRoom3D
	if _extraction_defense_active and enemy.room_id == _current_room_id:
		status_label.text = "撤离拦截波已压制 · 信号仍在同步"
		return
	_mark_room_cleared(room, true)
	status_label.text = "房间肃清 · 钥匙已掉落，可继续搜索或推进"
	if (
		_extraction != null
		and (
			enemy.room_id == "boss"
			or (
				room != null
				and room.room_type == "BOSS"
			)
		)
	):
		_extraction.set_locked(false)
		_hide_boss_hud()
		status_label.text = "Boss 已清除 · 撤离信标已解锁"
	if bool(enemy_data.get("is_elite", false)) and room != null:
		call_deferred("_ensure_conditional_extraction", "ELITE_KILL", room, Vector3(4.0, 0.0, 3.0))
	_refresh_loot_label()


func _on_boss_phase_changed(enemy: Enemy3D, phase: int) -> void:
	if enemy == _active_boss and _boss_label != null:
		_boss_label.text = "%s · 阶段 %d" % [enemy.get_enemy_data().get("name", "废土首领"), phase]
	status_label.text = "Boss 阶段 %d · 攻击节奏与增援强度提升" % phase


func _on_enemy_health_changed(enemy: Enemy3D, current: int, maximum: int) -> void:
	if enemy != _active_boss or _boss_bar == null:
		return
	_boss_bar.max_value = maxi(1, maximum)
	_boss_bar.value = current


func _show_boss_hud(enemy: Enemy3D) -> void:
	_active_boss = enemy
	if _boss_panel == null:
		_boss_panel = PanelContainer.new()
		_boss_panel.name = "BossHUD3D"
		_boss_panel.anchor_left = 0.5
		_boss_panel.anchor_right = 0.5
		_boss_panel.offset_left = -270
		_boss_panel.offset_right = 270
		_boss_panel.offset_top = 82
		_boss_panel.offset_bottom = 142
		_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$HUD.add_child(_boss_panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 8)
		_boss_panel.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		margin.add_child(box)
		_boss_label = Label.new()
		_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boss_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.28))
		box.add_child(_boss_label)
		_boss_bar = ProgressBar.new()
		_boss_bar.show_percentage = false
		_boss_bar.custom_minimum_size.y = 14
		box.add_child(_boss_bar)
	_boss_panel.visible = true
	_boss_label.text = "%s · 阶段 %d" % [enemy.get_enemy_data().get("name", "废土首领"), enemy.boss_phase]
	_on_enemy_health_changed(enemy, enemy.current_hp, enemy.max_hp)


func _hide_boss_hud() -> void:
	_active_boss = null
	if _boss_panel != null:
		_boss_panel.visible = false


func _ensure_conditional_extraction(type_id: String, room: DungeonRoom3D, local_position: Vector3) -> ExtractionBeacon3D:
	var existing := _conditional_extractions.get(type_id) as ExtractionBeacon3D
	if existing != null and is_instance_valid(existing):
		existing.set_locked(false)
		return existing
	var duration := 30.0 if type_id == "ELITE_KILL" else 30.0
	var beacon := _create_extraction_beacon(room, type_id, duration, false, local_position)
	_conditional_extractions[type_id] = beacon
	minimap.reveal_room(room.room_id)
	return beacon


func _on_prop_searched(room: DungeonRoom3D, loot_hint: Dictionary) -> void:
	if _map_fate_triggers != null:
		_map_fate_triggers.on_container_opened(str(loot_hint.get("size_class", "crate")))
	var size_class := str(loot_hint.get("size_class", "medium"))
	var container_type := "crate" if size_class == "small" else "locker" if size_class == "medium" else "hidden_cache"
	var drops := _loot_module.generate_container_loot(container_type, maxi(1, visual_theme.difficulty_rank))
	if _next_chest_quality_boost > 0:
		var boosted := _loot_module.generate_container_loot("hidden_cache", maxi(1, visual_theme.difficulty_rank + _next_chest_quality_boost))
		if not boosted.is_empty():
			drops.append(boosted[0])
		_next_chest_quality_boost = 0
	if _extra_loot_next_chest:
		var extra := _loot_module.generate_container_loot(container_type, maxi(1, visual_theme.difficulty_rank))
		if not extra.is_empty():
			drops.append(extra[0])
		_extra_loot_next_chest = false
	if drops.is_empty():
		status_label.text = "容器为空"
		return
	_spawn_loot_items(room, drops, player.global_position + player.aim_direction * 1.2)
	status_label.text = "容器已打开 · %d 件物资落地" % drops.size()


func _spawn_loot_items(room: DungeonRoom3D, items: Array[Dictionary], world_position: Vector3) -> void:
	for index in range(items.size()):
		var item := items[index].duplicate(true)
		var pickup := GROUND_LOOT_SCRIPT.new() as GroundLootPickup3D
		var color := Color(1.0, 0.76, 0.22) if bool(item.get("is_currency", false)) else Color(0.38, 0.88, 0.72)
		pickup.configure(item, color)
		room.add_child(pickup)
		var angle := float(index) * 2.1 + 0.45
		var requested_position := (
			world_position
			+ Vector3(cos(angle), 0.0, sin(angle)) * (0.7 + index * 0.18)
		)
		pickup.global_position = _find_supported_spawn_position(
			requested_position,
			room.global_position
		)
		pickup.pickup_requested.connect(_on_ground_loot_requested)


func _on_ground_loot_requested(pickup: GroundLootPickup3D, item: Dictionary) -> void:
	if bool(item.get("is_currency", false)) or str(item.get("id", "")) == "__currency__":
		GameManager.add_currency(int(item.get("count", 1)))
		if _map_fate_triggers != null:
			_map_fate_triggers.on_currency_collected(int(item.get("count", 1)))
		pickup.accept_pickup()
		status_label.text = "取得 %d 魂" % int(item.get("count", 1))
		_refresh_loot_label()
		return
	var requested := maxi(1, int(item.get("count", 1)))
	var added := _inventory.add_item(item, requested)
	if added <= 0:
		status_label.text = "背包已满 · %s 留在地面" % item.get("name", "物资")
		return
	if added >= requested:
		pickup.accept_pickup()
	else:
		pickup.item_data["count"] = requested - added
	status_label.text = "拾取 %s x%d%s" % [
		item.get("name", item.get("id", "物资")),
		added,
		" · 按 I 打开背包，左键装备" if str(item.get("type", "")) == "weapon" else "",
	]
	_refresh_loot_label()


func _on_service_activated(_room: DungeonRoom3D, station: ServiceStation3D) -> void:
	match station.station_type:
		"merchant":
			_open_merchant()
		"upgrade":
			_open_workbench()
		"event":
			_resolve_event_room(_room)
	_refresh_loot_label()


func _open_workbench() -> void:
	if _workbench_panel != null and is_instance_valid(_workbench_panel):
		return
	_workbench_panel = WORKBENCH_SCENE.instantiate() as WorkbenchPanel
	_workbench_panel.set_player(player)
	_workbench_panel.set_workbench_ref(self)
	$HUD.add_child(_workbench_panel)
	_close_inventory_for_modal()
	_sync_player_input_lock()
	status_label.text = "改造台：7 枪身 × 8 弹药，使用同一装配树"


func _open_merchant() -> void:
	if _merchant_ui != null and is_instance_valid(_merchant_ui):
		return
	_merchant_ui = MerchantUI.new()
	_merchant_ui.name = "MerchantUI3D"
	_merchant_ui.set_anchors_preset(Control.PRESET_CENTER)
	_merchant_ui.offset_left = -300
	_merchant_ui.offset_top = -220
	_merchant_ui.offset_right = 300
	_merchant_ui.offset_bottom = 220
	_merchant_ui.set_inventory(_inventory)
	_merchant_ui.set_tier(maxi(1, visual_theme.difficulty_rank))
	_merchant_ui.set_shop_name("%s · 废土拾荒商" % gameplay_theme.display_name)
	$HUD.add_child(_merchant_ui)
	_merchant_ui.purchase_requested.connect(_on_merchant_purchase)
	_merchant_ui.merchant_closed.connect(_on_merchant_closed)
	var goods := _loot_module.generate_merchant_goods(maxi(1, visual_theme.difficulty_rank), 6)
	_merchant_ui.show_merchant(goods)
	_close_inventory_for_modal()
	_sync_player_input_lock()
	status_label.text = "拾荒商已接入 · 购买会占用真实背包格"


func _on_merchant_purchase(item: Dictionary, _slot_index: int) -> void:
	_trade_extraction_unlocked = true
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	_ensure_conditional_extraction("TRADE", room, Vector3(-4.0, 0.0, 3.0))
	status_label.text = "购入 %s · 交易撤离条件已解锁" % item.get("name", "物品")


func _on_merchant_closed() -> void:
	if _merchant_ui != null and is_instance_valid(_merchant_ui):
		var closing := _merchant_ui
		get_tree().create_timer(0.3).timeout.connect(closing.queue_free)
	_merchant_ui = null
	_sync_player_input_lock()


func _on_run_currency_changed(amount: int) -> void:
	_run_value = amount
	_refresh_loot_label()


func _resolve_event_room(room: DungeonRoom3D) -> void:
	if room == null or _resolved_event_rooms.has(room.room_id):
		status_label.text = "本房事件已经结算"
		return
	_resolved_event_rooms[room.room_id] = true
	var event_id: String = ["CURSE", "BLESSING", "TRADE", "GAMBLE", "REVEAL", "SUMMON"][_rng.randi_range(0, 5)]
	match event_id:
		"CURSE":
			room.cleared = false
			_spawn_room_enemies(room)
			for value in _enemy_nodes_by_room.get(room.room_id, []):
				if is_instance_valid(value) and value is Enemy3D:
					(value as Enemy3D).contact_damage = int((value as Enemy3D).contact_damage * 1.15)
			status_label.text = "诅咒降临：额外敌群伤害 +15%，清除后结算"
			return
		"BLESSING":
			player.apply_damage_buff("event_blessing", 0.10)
			get_tree().create_timer(60.0).timeout.connect(player.remove_damage_buff.bind("event_blessing"))
			status_label.text = "祝福降临：武器伤害 +10%，持续 60 秒"
		"TRADE":
			if FateCardGameBridge.get_card_count() > 0:
				var reward := _rng.randi_range(30, 80)
				GameManager.add_currency(reward)
				status_label.text = "命运交易完成：获得 %d 魂" % reward
			else:
				status_label.text = "命运交易取消：尚无已应用卡片"
		"GAMBLE":
			if GameManager.currency < 20:
				status_label.text = "赌局取消：至少需要 20 魂"
			else:
				var bet := clampi(GameManager.currency / 2, 20, 100)
				GameManager.spend_currency(bet)
				if _rng.randf() < 0.5:
					var multiplier := _rng.randi_range(2, 5)
					GameManager.add_currency(bet * multiplier)
					status_label.text = "赌局胜利：投入 %d，倍率 ×%d" % [bet, multiplier]
				else:
					status_label.text = "赌局失败：损失 %d 魂" % bet
		"REVEAL":
			_reveal_nearby_rooms(room.room_id, 2)
			status_label.text = "地图揭示：周围房间类型已标记"
		"SUMMON":
			room.cleared = false
			_spawn_room_enemies(room)
			status_label.text = "亡者召唤：额外敌群出现，击杀后获得掉落"
			return
	_mark_room_cleared(room, true)


func _reveal_nearby_rooms(origin_id: String, depth: int) -> void:
	var frontier: Array[String] = [origin_id]
	var visited := {origin_id: true}
	for _step in range(maxi(1, depth)):
		var next: Array[String] = []
		for room_id in frontier:
			for neighbor in _room_neighbors.get(room_id, []):
				var neighbor_id := str(neighbor)
				if visited.has(neighbor_id):
					continue
				visited[neighbor_id] = true
				next.append(neighbor_id)
				minimap.reveal_room(neighbor_id)
		frontier = next


func trigger_extra_wave() -> void:
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null or room.room_type in ["START", "MERCHANT", "UPGRADE"]:
		return
	var configs: Array[Dictionary] = _monster_injector.generate_enemies({
		"type": "ambush", "count": 3, "floor": maxi(1, visual_theme.difficulty_rank),
		"floor_level": clampi(_record_index(room.room_id) / 3, 0, 3),
	})
	room.cleared = false
	_alive_by_room[room.room_id] = int(_alive_by_room.get(room.room_id, 0)) + configs.size()
	call_deferred("_spawn_enemy_batch", room, configs, true, true)
	status_label.text = "命运增援：波次外出现 %d 个敌对信号" % configs.size()


func set_next_chest_quality_boost(boost: int) -> void:
	_next_chest_quality_boost = maxi(_next_chest_quality_boost, boost)


func set_extra_loot_next_chest(enabled: bool) -> void:
	_extra_loot_next_chest = enabled


func apply_curse_to_current_room(damage_multiplier: float) -> void:
	for value in _enemy_nodes_by_room.get(_current_room_id, []):
		if not is_instance_valid(value):
			continue
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and enemy.ai_state != "dead":
			enemy.contact_damage = maxi(1, int(enemy.contact_damage * damage_multiplier))
	status_label.text = "房间诅咒：敌人伤害提高 %.0f%%" % [(damage_multiplier - 1.0) * 100.0]


func apply_bless_dead(hp_threshold: float, survive_duration: float, damage_bonus: float) -> void:
	_bless_dead_active = true
	_bless_dead_threshold = clampf(hp_threshold, 0.05, 0.95)
	_bless_dead_remaining = maxf(0.1, survive_duration)
	_bless_dead_bonus = maxf(0.0, damage_bonus)
	_bless_dead_triggered = false


func _tick_bless_dead(delta: float) -> void:
	if not _bless_dead_active or _bless_dead_triggered or player == null or player.current_hp <= 0:
		return
	if float(player.current_hp) / float(maxi(1, player.max_hp)) > _bless_dead_threshold:
		return
	_bless_dead_remaining = maxf(0.0, _bless_dead_remaining - delta)
	if _bless_dead_remaining > 0.0:
		return
	_bless_dead_triggered = true
	player.apply_damage_buff("bless_dead", _bless_dead_bonus)
	status_label.text = "亡者祝福生效：武器伤害 +%.0f%%" % [_bless_dead_bonus * 100.0]


func handle_esc() -> void:
	if _workbench_panel != null and is_instance_valid(_workbench_panel):
		_workbench_panel.queue_free()
	_workbench_panel = null
	_sync_player_input_lock()


func _mark_room_cleared(room: DungeonRoom3D, spawn_key: bool) -> void:
	if room == null:
		return
	var was_cleared := room.cleared
	room.cleared = true
	if not was_cleared:
		room_cleared.emit(room)
	if spawn_key and not was_cleared:
		call_deferred("_ensure_room_key_reward", room)


func _ensure_room_key_reward(room: DungeonRoom3D) -> void:
	if (
		room == null
		or not is_instance_valid(room)
		or not room.cleared
		or room.room_type in ["START", "EXTRACTION", "FACILITY", "ELEVATOR"]
		or _spawned_key_rooms.has(room.room_id)
	):
		return
	_spawn_room_key(room)


func _spawn_room_key(room: DungeonRoom3D) -> void:
	if room == null or not is_instance_valid(room) or _spawned_key_rooms.has(room.room_id):
		return
	var key := KEY_SCRIPT.new() as RoomKeyPickup3D
	key.configure(room.room_id)
	room.add_child(key)
	var spawn_position := Vector3(0, 0.05, -2.2)
	if player != null and is_instance_valid(player) and _current_room_id == room.room_id:
		var player_local := room.to_local(player.global_position)
		player_local.y = 0.05
		var toward_center := Vector3(-player_local.x, 0, -player_local.z)
		if toward_center.length_squared() <= 0.001:
			var fallback_angle := fmod(float(room.room_seed) * 0.731, TAU)
			toward_center = Vector3(cos(fallback_angle), 0, sin(fallback_angle))
		spawn_position = player_local + toward_center.normalized() * 2.2
	var dimensions := room.get_dimensions()
	var safe_half_x := maxf(1.0, dimensions.x * 0.5 - 2.1)
	var safe_half_z := maxf(1.0, dimensions.y * 0.5 - 2.1)
	spawn_position.x = clampf(spawn_position.x, -safe_half_x, safe_half_x)
	spawn_position.z = clampf(spawn_position.z, -safe_half_z, safe_half_z)
	key.global_position = _find_supported_spawn_position(
		room.to_global(spawn_position),
		room.global_position
	)
	key.collected.connect(_on_room_key_collected)
	_spawned_key_rooms[room.room_id] = true


func _find_supported_spawn_position(
	requested_world_position: Vector3,
	fallback_world_position: Vector3
) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return requested_world_position
	for candidate in [requested_world_position, fallback_world_position]:
		var query := PhysicsRayQueryParameters3D.create(
			candidate + Vector3.UP * 3.0,
			candidate + Vector3.DOWN * 4.0,
			1
		)
		query.collide_with_areas = false
		query.hit_back_faces = true
		if player != null and is_instance_valid(player):
			query.exclude = [player.get_rid()]
		var hit := world.direct_space_state.intersect_ray(query)
		if (
			not hit.is_empty()
			and (hit.get("normal", Vector3.ZERO) as Vector3).y >= 0.55
		):
			return (hit.get("position", candidate) as Vector3) + Vector3.UP * 0.05
	return fallback_world_position + Vector3.UP * 0.05


func _on_room_key_collected(_room_id: String) -> void:
	_room_key_count += 1
	status_label.text = "获得房间钥匙 · 靠近门按 E 开启"
	_refresh_loot_label()


func _try_open_room_door(target_room_id: String) -> bool:
	if target_room_id.is_empty() or _current_room_id.is_empty():
		return false
	if _door_fate_active:
		status_label.text = "先选择当前命运卡片，再开启下一扇门"
		return false
	var edge := _edge_key(_current_room_id, target_room_id)
	var policy := _door_policy_for_edge(_current_room_id, target_room_id)
	if bool(_open_edges.get(edge, false)):
		# 边已开启也要刷新门视觉：默认开的 vertical edge
		# （如成顶↔99层基地）会在首次走到门附近时同时勾起门。
		_refresh_edge_visuals(_current_room_id, target_room_id, true)
		status_label.text = "通道已经开启"
		return true
	var current := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if current == null:
		return false
	if bool(policy.get("requires_clear", true)) and not current.cleared:
		status_label.text = "先清理当前房间，才能开启房门"
		return false
	var requires_key := bool(policy.get("requires_key", true))
	if requires_key and _get_total_room_keys() <= 0:
		status_label.text = "需要房间钥匙"
		return false
	if requires_key:
		_consume_room_key()
	_open_edges[edge] = true
	minimap.set_edge_open(_current_room_id, target_room_id, true)
	_update_room_streaming(_current_room_id)
	_refresh_edge_visuals(_current_room_id, target_room_id, true)
	status_label.text = (
		"房门已开启 · 剩余钥匙 %d" % _get_total_room_keys()
		if requires_key
		else "通行门已开启 · 未消耗钥匙"
	)
	_refresh_loot_label()
	if bool(policy.get("triggers_fate", true)):
		call_deferred("_show_door_fate_choices")
	return true


func try_open_room_door(target_room_id: String) -> bool:
	return _try_open_room_door(target_room_id)


func _show_door_fate_choices() -> void:
	if _door_fate_active:
		return
	var pool := FateCardPresets.door_reward_presets()
	if pool.is_empty():
		return
	_door_fate_choices.clear()
	var indices: Array[int] = []
	while indices.size() < mini(3, pool.size()):
		var index := _rng.randi_range(0, pool.size() - 1)
		if index not in indices:
			indices.append(index)
			_door_fate_choices.append(pool[index])
	_door_fate_active = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	_fate_overlay = Control.new()
	_fate_overlay.name = "DoorFateOverlay3D"
	_fate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_fate_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_fate_overlay.z_index = 900
	$HUD.add_child(_fate_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 360)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "门后命运 · 选择一项装配改造"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
	vbox.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	for choice_index in range(_door_fate_choices.size()):
		var card := _door_fate_choices[choice_index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(240, 220)
		button.text = "[%s] %s\n%s\n\n%s" % [
			FateCard.rarity_name(card.card_rarity), card.card_name,
			FateCard.type_name(card.card_type), card.description,
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = card.description
		button.pressed.connect(_on_door_fate_selected.bind(choice_index))
		row.add_child(button)
	status_label.text = "门已开启 · 选择命运卡片后继续行动"


func _on_door_fate_selected(choice_index: int) -> void:
	if not _door_fate_active or choice_index < 0 or choice_index >= _door_fate_choices.size():
		return
	var card := _door_fate_choices[choice_index]
	var result := FateCardGameBridge.apply_card(card)
	if not bool(result.get("success", false)):
		status_label.text = "当前装配无法承载 %s，请选择其他卡片" % card.card_name
		return
	_door_fate_active = false
	_door_fate_choices.clear()
	if _fate_overlay != null and is_instance_valid(_fate_overlay):
		_fate_overlay.queue_free()
	_fate_overlay = null
	_sync_player_input_lock()
	if AudioManager != null:
		AudioManager.play_fate_card_sfx()
	status_label.text = "命运生效：%s · %s" % [card.card_name, result.get("message", "")]


func resolve_fate_choice_for_test(choice_index := 0) -> void:
	if not _door_fate_active:
		return
	_on_door_fate_selected(clampi(choice_index, 0, _door_fate_choices.size() - 1))
	if not _door_fate_active:
		return
	for index in range(_door_fate_choices.size()):
		_on_door_fate_selected(index)
		if not _door_fate_active:
			return


func _get_total_room_keys() -> int:
	return _room_key_count + (_inventory.get_item_count("item_room_key") if _inventory != null else 0)


func _consume_room_key() -> void:
	if _inventory != null and _inventory.has_item("item_room_key"):
		_inventory.consume_item("item_room_key", 1)
	else:
		_room_key_count = maxi(0, _room_key_count - 1)


func _refresh_edge_visuals(a: String, b: String, opened: bool) -> void:
	var room_a := _room_by_id.get(a) as DungeonRoom3D
	var room_b := _room_by_id.get(b) as DungeonRoom3D
	if room_a == null or room_b == null:
		return
	var direction_a := _direction_between(room_a.global_position, room_b.global_position)
	room_a.set_door_open(direction_a, opened)
	room_b.set_door_open(_opposite_direction(direction_a), opened)


func _update_room_streaming(current_id: String) -> void:
	for room in _rooms:
		var state := 2 if room.room_id == current_id else 0
		if state == 0 and _room_neighbors.has(current_id) and room.room_id in (_room_neighbors[current_id] as Array):
			if bool(_open_edges.get(_edge_key(current_id, room.room_id), false)):
				state = 1
		room.set_stream_state(state)
		if state > 0:
			_prepare_revealed_hostile_room(room)
	_update_corridor_streaming(current_id)
	for room_id in _enemy_nodes_by_room.keys():
		var live_references: Array = []
		for value in _enemy_nodes_by_room[room_id]:
			if not is_instance_valid(value):
				continue
			var enemy := value as Enemy3D
			if enemy != null and is_instance_valid(enemy):
				live_references.append(enemy)
				var enemy_room := _room_by_id.get(str(room_id)) as DungeonRoom3D
				var room_visible := (
					enemy_room != null
					and int(enemy_room.get_room_snapshot().get("stream_state", 0)) > 0
				)
				enemy.set_runtime_active(str(room_id) == current_id, room_visible)
		_enemy_nodes_by_room[room_id] = live_references


func _update_corridor_streaming(current_id: String) -> void:
	for edge in _corridor_by_edge.keys():
		var corridor := _corridor_by_edge[edge] as StaticBody3D
		if corridor == null:
			continue
		var ids := str(edge).split("|")
		var active := bool(_open_edges.get(edge, false)) and current_id in ids
		corridor.visible = active
		corridor.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		_set_corridor_collisions_disabled(corridor, not active)


func _on_insure_item_requested(slot_index: int) -> void:
	if not _insurance.insure_item(_inventory, slot_index):
		status_label.text = "保险格已满或物品无效"


func _on_claim_insurance_requested(slot_index: int) -> void:
	var item := _insurance.claim_item(slot_index)
	if item.is_empty():
		return
	if _inventory.add_item(item, 1) <= 0:
		_insurance.insure_item_direct(item)
		status_label.text = "背包已满，保险物品未取出"


func _on_inventory_item_clicked(slot_index: int, _item_hint: Dictionary) -> void:
	var slot := _inventory.get_slot(slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	if item.get("type", "") == "weapon":
		_equip_weapon_from_inventory(slot_index, item)
		return
	if item.get("type", "") in ["module", "attachment"]:
		if _can_swap_installed_module(item, slot_index):
			_inventory.remove_from_slot(slot_index, 1)
			if not _install_weapon_module_from_item(item):
				_inventory.add_item(item, 1)
		return
	var use_action := str(item.get("use_action", ""))
	if use_action.is_empty():
		status_label.text = "%s：右键可存入保险格" % item.get("name", "物品")
		return
	var handler := ItemUseHandler.new()
	var applied := handler.apply(item, {"player": player, "extraction_director": self})
	handler.free()
	if applied:
		_inventory.remove_from_slot(slot_index, 1)
		status_label.text = "已使用 %s" % item.get("name", "物品")
	else:
		status_label.text = "%s 当前无法使用" % item.get("name", "物品")


func _equip_weapon_from_inventory(slot_index: int, item: Dictionary) -> bool:
	var tree := player.get_weapon_tree()
	if tree == null or tree.get_root() == null:
		return false
	var new_root := BlueprintRegistry.create_assembly_node(str(item.get("assembly_id", item.get("id", ""))))
	if new_root == null:
		return false
	var old_root := tree.get_root()
	var old_item := _item_for_weapon_root(old_root)
	if old_item.get("id", "") == item.get("id", ""):
		new_root.free()
		status_label.text = "当前已经装备 %s" % item.get("name", "武器")
		return false
	var detached_modules: Dictionary = {}
	for slot_type in old_root.slots.keys():
		var child := old_root.slots.get(slot_type) as AssemblyNode
		if child != null:
			tree.unmount(child)
			detached_modules[slot_type] = child
	_inventory.remove_from_slot(slot_index, 1)
	if not tree.set_root(new_root):
		for slot_type in detached_modules.keys():
			tree.mount(old_root, int(slot_type), detached_modules[slot_type] as AssemblyNode)
		_inventory.add_item(item, 1)
		new_root.free()
		return false
	var transferred := 0
	for slot_type in detached_modules.keys():
		var module := detached_modules[slot_type] as AssemblyNode
		if tree.mount(new_root, int(slot_type), module):
			transferred += 1
			continue
		var module_item := _item_for_assembly_node(module)
		if module_item.is_empty() or _inventory.add_item(module_item, 1) <= 0:
			push_error("[Dungeon3D] Detached module cannot be transferred or returned: %s" % module.node_name)
		module.free()
	if not old_item.is_empty():
		_inventory.add_item(old_item, 1)
	status_label.text = "已装备 %s · 原武器放回背包 · 保留 %d 个模块" % [
		item.get("name", "武器"), transferred,
	]
	return true


func _install_weapon_module_from_item(item: Dictionary) -> bool:
	var tree := player.get_weapon_tree()
	if tree == null or tree.get_root() == null:
		return false
	var new_node := BlueprintRegistry.create_assembly_node(str(item.get("assembly_id", item.get("id", ""))))
	if new_node == null:
		return false
	var slot_type := AssemblyNode.SlotType.MOUNT
	match str(item.get("subtype", "")):
		"bullet":
			slot_type = AssemblyNode.SlotType.BULLET
		"muzzle":
			slot_type = AssemblyNode.SlotType.MUZZLE
		"magazine":
			slot_type = AssemblyNode.SlotType.MAGAZINE
		_:
			slot_type = AssemblyNode.SlotType.MOUNT
	var root := tree.get_root()
	var existing := root.slots.get(slot_type) as AssemblyNode
	if existing != null and _item_id_for_assembly_node(existing) == str(item.get("id", "")):
		new_node.free()
		status_label.text = "当前槽位已经装配 %s" % item.get("name", "模块")
		return false
	if existing != null:
		tree.unmount(existing)
	if not tree.mount(root, slot_type, new_node):
		if existing != null:
			tree.mount(root, slot_type, existing)
		new_node.free()
		return false
	if existing != null:
		var old_item := _item_for_assembly_node(existing)
		if old_item.is_empty() or _inventory.add_item(old_item, 1) <= 0:
			tree.unmount(new_node)
			tree.mount(root, slot_type, existing)
			new_node.free()
			status_label.text = "模块交换失败 · 换下的模块无法放回背包"
			return false
		existing.free()
		status_label.text = "已装配 %s · 旧模块放回背包" % item.get("name", "模块")
	else:
		status_label.text = "已装配 %s" % item.get("name", "模块")
	return true


func _can_swap_installed_module(item: Dictionary, source_slot_index: int) -> bool:
	var tree := player.get_weapon_tree()
	if tree == null or tree.get_root() == null:
		return false
	var slot_type := _slot_type_for_item(item)
	var existing := tree.get_root().slots.get(slot_type) as AssemblyNode
	if existing == null:
		return true
	var existing_item := _item_for_assembly_node(existing)
	if existing_item.is_empty():
		status_label.text = "当前模块缺少物品映射，已阻止可能的数据丢失"
		return false
	if _item_id_for_assembly_node(existing) == str(item.get("id", "")):
		status_label.text = "当前槽位已经装配 %s" % item.get("name", "模块")
		return false
	if _inventory.get_free_slots() > 0:
		return true
	var source_slot := _inventory.get_slot(source_slot_index)
	if int(source_slot.get("count", 0)) <= 1:
		return true
	var existing_id := str(existing_item.get("id", ""))
	var stack_max := maxi(1, int(existing_item.get("stack_max", 1)))
	for occupied in _inventory.get_occupied_slots():
		if str((occupied.get("item", {}) as Dictionary).get("id", "")) == existing_id:
			if int(occupied.get("count", 0)) < stack_max:
				return true
	status_label.text = "背包没有空间容纳换下的模块"
	return false


func _slot_type_for_item(item: Dictionary) -> int:
	match str(item.get("subtype", "")):
		"bullet":
			return AssemblyNode.SlotType.BULLET
		"muzzle":
			return AssemblyNode.SlotType.MUZZLE
		"magazine":
			return AssemblyNode.SlotType.MAGAZINE
		_:
			return AssemblyNode.SlotType.MOUNT


func _item_for_weapon_root(root: AssemblyNode) -> Dictionary:
	if root == null:
		return {}
	var item_id: String = str({
		"GunBody_Pistol": "weapon_pistol", "GunBody_Shotgun": "weapon_shotgun",
		"GunBody_Rifle": "weapon_rifle", "GunBody_Machinegun": "weapon_machinegun",
		"GunBody_Sniper": "weapon_sniper", "GunBody_Launcher": "weapon_launcher",
		"GunBody_Charge": "weapon_charge",
	}.get(root.node_name, ""))
	return ItemRegistry.get_instance().get_item(item_id) if not item_id.is_empty() else {}


func _item_for_assembly_node(node: AssemblyNode) -> Dictionary:
	var item_id := _item_id_for_assembly_node(node)
	return ItemRegistry.get_instance().get_item(item_id) if not item_id.is_empty() else {}


func _item_id_for_assembly_node(node: AssemblyNode) -> String:
	if node == null:
		return ""
	return str({
		"Bullet_Standard": "mod_bullet_standard",
		"Bullet_Sticky": "mod_bullet_sticky",
		"Bullet_Bounce": "mod_bullet_bounce",
		"Bullet_Piercing": "mod_bullet_piercing",
		"Bullet_Explosive": "mod_bullet_explosive",
		"Bullet_Homing": "mod_bullet_homing",
		"Bullet_Blackhole": "mod_bullet_blackhole",
		"Bullet_Balloon": "mod_bullet_balloon",
		"Att_TripleMuzzle": "attach_triple_muzzle",
		"Att_RubberStock": "attach_rubber_stock",
		"Att_Scope": "attach_scope",
		"Att_BigMag": "attach_big_mag",
		"Att_Fan": "attach_fan",
		"Att_CopySticker": "attach_copy_sticker",
	}.get(node.node_name, ""))


func summon_beacon_extraction() -> bool:
	if _emergency_extraction != null and is_instance_valid(_emergency_extraction):
		return false
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null:
		return false
	_emergency_extraction = _create_extraction_beacon(room, "BEACON", 30.0, false, Vector3.ZERO)
	_emergency_extraction.global_position = player.global_position + player.aim_direction * 2.2
	status_label.text = "紧急撤离信标已部署 · 读条期间不得离开范围"
	return true


func get_inventory_module() -> InventoryModule:
	return _inventory


func get_insurance_module() -> InsuranceModule:
	return _insurance


func get_last_killed_enemy() -> Dictionary:
	return last_killed_enemy_data.duplicate(true)


func _on_extraction_started(start_duration: float, beacon: ExtractionBeacon3D) -> void:
	_active_extraction_beacon = beacon
	_extraction_defense_active = true
	_extraction_mid_wave_spawned = false
	_extraction_wave_2_spawned = false
	_extraction_wave_3_spawned = false
	_extraction_final_wave_spawned = false
	_close_inventory_for_modal()
	_sync_player_input_lock()
	if AudioManager != null:
		AudioManager.play_sfx("extraction_start")
	extraction_panel.visible = true
	extraction_bar.value = 0.0
	_spawn_extraction_attackers(0)
	# 自由撤离：玩家可移动、可射击，30 秒读条中只会越过阈值才离开。
	status_label.text = "%s撤离启动 · %.0f秒后安全返航，行动自由" % [
		beacon.beacon_type,
		start_duration,
	]


func _on_extraction_progress(progress: float, beacon: ExtractionBeacon3D) -> void:
	if beacon != _active_extraction_beacon:
		return
	extraction_bar.value = progress * 100.0
	# 5 阶段友驻点进场。阶段阈值划分：
	# stage 0：0%    (随机 4)
	# stage 1：18%   (伏击 5)
	# stage 2：36%   (伏击 6)
	# stage 3：58%   (精英 + 随机 3)
	# stage 4：78%   (精英 2 + 伏击 4)
	if not _extraction_mid_wave_spawned and progress >= 0.18:
		_extraction_mid_wave_spawned = true
		_spawn_extraction_attackers(1)
		status_label.text = "撤离信号 1/4 · 第一波增援逼近"
	elif progress >= 0.36 and not _extraction_wave_2_spawned:
		_extraction_wave_2_spawned = true
		_spawn_extraction_attackers(2)
		status_label.text = "撤离信号 2/4 · 第二波增援逼近"
	elif progress >= 0.58 and not _extraction_wave_3_spawned:
		_extraction_wave_3_spawned = true
		_spawn_extraction_attackers(3)
		status_label.text = "撤离信号 3/4 · 精英拦截者出现"
	elif progress >= 0.78 and not _extraction_final_wave_spawned:
		_extraction_final_wave_spawned = true
		_spawn_extraction_attackers(4)
		status_label.text = "撤离信号即将锁定 · 最后一波拦截"


func _on_extraction_cancelled(beacon: ExtractionBeacon3D) -> void:
	if beacon != _active_extraction_beacon:
		return
	_extraction_defense_active = false
	_active_extraction_beacon = null
	_sync_player_input_lock()
	if AudioManager != null:
		AudioManager.play_sfx("extraction_abort")
	extraction_panel.visible = false
	status_label.text = "撤离中断 · 受击或离开同步范围，拦截者仍然存在"


func _on_extraction_completed(beacon: ExtractionBeacon3D) -> void:
	if _active_extraction_beacon != null and beacon != _active_extraction_beacon:
		return
	_extraction_defense_active = false
	_active_extraction_beacon = null
	if AudioManager != null:
		AudioManager.play_sfx("extraction_done")
	_finish_run(true)


func _spawn_extraction_attackers(stage: int) -> void:
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null:
		return
	var floor := maxi(1, visual_theme.difficulty_rank)
	var floor_level := clampi(_record_index(room.room_id) / 3, 0, 3)
	var configs: Array[Dictionary] = []
	# 撤离现在是 30 秒长读条：5 阶段，每阶段 4-6 只。
	# 阶段 0：随机 4 只
	# 阶段 1：伏击 5 只
	# 阶段 2：伏击 6 只
	# 阶段 3：精英 + 随机 3 只
	# 阶段 4：精英 2 只 + 伏击 4 只
	match stage:
		0:
			configs.assign(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": floor_level}))
			while configs.size() < 4:
				configs.append_array(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": floor_level}))
		1:
			configs.assign(_monster_injector.generate_enemies({"type": "ambush", "count": 5, "floor": floor, "floor_level": floor_level}))
		2:
			configs.assign(_monster_injector.generate_enemies({"type": "ambush", "count": 6, "floor": floor, "floor_level": floor_level}))
		3:
			configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level}))
			configs.append_array(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": floor_level}))
			while configs.size() < 4:
				configs.append_array(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": floor_level}))
		_:
			configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level}))
			configs.append_array(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level}))
			configs.append_array(_monster_injector.generate_enemies({"type": "ambush", "count": 4, "floor": floor, "floor_level": floor_level}))
	_spawn_enemy_batch(room, configs, true)


func _on_player_hp_changed(current: int, maximum: int) -> void:
	hp_label.text = "HP %d/%d" % [current, maximum]
	var hp_ratio := float(current) / float(maxi(1, maximum))
	var vignette_intensity := clampf((0.34 - hp_ratio) / 0.34, 0.0, 1.0)
	var vignette_material := low_health_vignette.material as ShaderMaterial
	if vignette_material != null:
		vignette_material.set_shader_parameter("intensity", vignette_intensity)
	hp_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.28, 0.22) if hp_ratio <= 0.30 else Color(0.92, 0.95, 1.0),
	)
	var took_damage := _last_player_hp >= 0 and current < _last_player_hp
	_last_player_hp = current
	# 自由撤离：玩家可以被打但不被中断。
	# 只要 HP 不归零就读条继续。
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
	_close_inventory_for_modal()
	_sync_player_input_lock()
	extraction_panel.visible = false
	_run_loot = _collect_extracted_items()
	var settlement: Dictionary = {}
	if success:
		_death_settlement.process_extraction_settlement(_inventory, _insurance)
	else:
		settlement = _death_settlement.process_death_settlement(_inventory, _insurance)
		_run_loot = _collect_extracted_items()
	var summary := {
		"success": success, "kills": _kills, "value": _run_value,
		"loot": _run_loot.duplicate(true), "seed": run_seed,
		"theme_id": gameplay_theme.theme_id, "settlement": settlement,
		"inventory_capacity": _inventory.get_capacity(), "insurance_capacity": _insurance.get_max_slots(),
	}
	if not test_mode:
		BaseManager.record_run(success, _kills)
		if success:
			BaseManager.add_extraction_points(_run_value)
			BaseManager.add_extraction_loot_items(_run_loot)
	status_label.text = "撤离成功 · %d 击杀 · %d件物资" % [_kills, _run_loot.size()] if success else "行动失败 · 按原规则结算未保险物资"
	run_completed.emit(success, summary)
	if not test_mode:
		await get_tree().create_timer(1.6).timeout
		get_tree().change_scene_to_file(return_scene_path)


func _collect_extracted_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _inventory.get_occupied_slots():
		var item := (slot.get("item", {}) as Dictionary).duplicate(true)
		if item.is_empty():
			continue
		item["count"] = int(slot.get("count", 1))
		result.append(item)
	for slot in _insurance.get_occupied_slots():
		var insured := (slot.get("item", {}) as Dictionary).duplicate(true)
		if insured.is_empty():
			continue
		insured["count"] = int(slot.get("count", 1))
		result.append(insured)
	return result


func _refresh_loot_label() -> void:
	if loot_label == null or _inventory == null:
		return
	loot_label.text = "背包 %d/12 · 保险 %d/2 · 钥匙 %d · 魂 %d" % [
		_inventory.get_used_slots(), _insurance.get_used_slots(), _get_total_room_keys(), _run_value
	]


func _room_status(type_id: String) -> String:
	return {
		"START": "废土入口已建立定位", "SCAVENGE": "搜索区：检查带提示的容器",
		"STORAGE": "大型库存区：注意占地与退路", "MERCHANT": "安全补给终端",
		"UPGRADE": "武器改造终端", "EVENT": "检测到可交互异常信号",
		"BASEMENT": "地下层：精英守卫与高价值搜索物资",
		"STAIRS_DOWN": "下行楼梯：通往地下层", "STAIRS_UP": "上行楼梯：通往二层",
		"ELEVATOR": "废土电梯：连接垂直探索层",
		"EXTRACTION": "撤离区：信标仍受 Boss 干扰",
	}.get(type_id, "区域暂时安全")


func get_generation_snapshot() -> Dictionary:
	var branch_types: Array[String] = []
	var size_counts := {"small": 0, "medium": 0, "large": 0, "arena": 0}
	var record_summary: Array[Dictionary] = []
	for record in _records:
		if not bool(record["main"]):
			branch_types.append(str(record["type"]))
		size_counts[record["size"]] = int(size_counts.get(record["size"], 0)) + 1
		record_summary.append({
			"id": record["id"], "type": record["type"], "size": record["size"],
			"position": record["position"], "main": record["main"], "parent": record["parent"],
			"index": record["index"], "vertical_level": record.get("vertical_level", 0),
			"custom_dimensions": record.get("custom_dimensions", Vector2.ZERO),
			"tower_role": record.get("tower_role", ""),
			"doors": (record.get("doors", []) as Array).duplicate(),
			"door_targets": (
				record.get("door_targets", {}) as Dictionary
			).duplicate(),
		})
	return {
		"theme_id": gameplay_theme.theme_id, "visual_theme_id": visual_theme.theme_id, "seed": run_seed,
		"room_count": _records.size(), "branch_count": branch_types.size(), "branch_types": branch_types,
		"required_branch_types": gameplay_theme.required_branch_types.duplicate(), "size_counts": size_counts,
		"records": record_summary, "has_extraction": _extraction != null, "is_3d": true,
		"room_dimensions": DungeonRoom3D.ROOM_DIMENSIONS.duplicate(true),
		"locked_edge_count": _open_edges.size(), "initial_room_keys": 1,
		"inventory_capacity": 12, "insurance_capacity": 2,
		"streaming_policy": "current_plus_open_neighbors",
		"minimap": minimap.get_snapshot() if minimap != null else {},
	}


func force_enter_room_for_test(room_id: String) -> void:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room != null:
		_on_room_entered(room)


func force_open_edge_for_test(a: String, b: String) -> void:
	var edge := _edge_key(a, b)
	if not _open_edges.has(edge):
		return
	_open_edges[edge] = true
	minimap.set_edge_open(a, b, true)
	_update_room_streaming(_current_room_id)
	_refresh_edge_visuals(a, b, true)


func get_runtime_snapshot() -> Dictionary:
	var active_rooms := 0
	var built_shells := 0
	var detailed_rooms := 0
	var active_lights := 0
	var active_ai := 0
	for room in _rooms:
		var snapshot := room.get_room_snapshot()
		if int(snapshot.get("stream_state", 0)) > 0:
			active_rooms += 1
		if bool(snapshot.get("shell_built", false)):
			built_shells += 1
		if bool(snapshot.get("detail_built", false)):
			detailed_rooms += 1
	for light in get_tree().get_nodes_in_group("wasteland_light_3d"):
		if light is WastelandLight3D and bool((light as WastelandLight3D).get_snapshot().get("illumination_active", false)):
			active_lights += 1
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		if value is Enemy3D and (value as Enemy3D).is_runtime_ai_active():
			active_ai += 1
	var projectile_pool := get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	var effect_pool := get_node_or_null("CombatEffectPool3D") as CombatEffectPool3D
	var vision := player.get_node_or_null("PlayerVision3D") as PlayerVision3D
	var unclaimed_key_count := 0
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and is_ancestor_of(value):
			unclaimed_key_count += 1
	return {
		"current_room_id": _current_room_id, "active_rooms": active_rooms, "built_shells": built_shells,
		"detailed_rooms": detailed_rooms, "total_rooms": _rooms.size(),
		"active_lights": active_lights, "active_ai": active_ai,
		"keys": _get_total_room_keys(), "inventory_used": _inventory.get_used_slots(),
		"spawned_key_room_count": _spawned_key_rooms.size(), "unclaimed_key_count": unclaimed_key_count,
		"open_edges": _open_edges.values().count(true), "total_edges": _open_edges.size(),
		"edge_states": _open_edges.duplicate(true),
		"wave_numbers": _room_wave_numbers.duplicate(true),
		"wave_totals": _room_wave_totals.duplicate(true),
		"extraction_types": _conditional_extractions.keys(),
		"extraction_defense_active": _extraction_defense_active,
		"projectile_pool": projectile_pool.get_snapshot() if projectile_pool != null else {},
		"effect_pool": effect_pool.get_snapshot() if effect_pool != null else {},
		"vision": vision.get_snapshot() if vision != null else {},
	}


func force_unlock_extraction_for_test() -> void:
	if _extraction != null:
		_extraction.set_locked(false)


func force_extract_for_test() -> void:
	force_unlock_extraction_for_test()
	if _extraction != null:
		_extraction.force_complete_for_test()
