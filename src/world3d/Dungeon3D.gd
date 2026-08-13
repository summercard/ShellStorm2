class_name Dungeon3D
extends Node3D
## 四主题关卡共用的 3D 运行时。MapThemeProfile 保留原玩法配方，DungeonTheme3D 负责空间美术；
## 随机地图、房间内容、敌人、撤离和结算只有这一套实现。

signal generation_completed(snapshot: Dictionary)
signal run_completed(success: bool, summary: Dictionary)
signal kill_recorded()
signal room_cleared(room_data)
signal room_entered(room_data)
signal backpack_equipment_changed(snapshot: Dictionary)

const ROOM_SCENE: PackedScene = preload("res://assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d_v001.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const EXTRACTION_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_extraction_beacon_root_top3d_v001.tscn")
const KEY_SCRIPT := preload("res://src/world3d/RoomKeyPickup3D.gd")
const GROUND_LOOT_SCRIPT := preload("res://src/world3d/GroundLootPickup3D.gd")
const WORKBENCH_SCENE: PackedScene = preload("res://scenes/WorkbenchPanel.tscn")
const WEAPON_PRESENTATION_SCENE: PackedScene = preload("res://scenes/WeaponAssemblyTreePanel.tscn")
const CORRIDOR_FLOOR_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_floor_segment.tscn")
const CORRIDOR_WALL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_wall_segment.tscn")
const CORRIDOR_CEILING_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_ceiling_segment.tscn")
const CORRIDOR_STAIR_TREAD_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_stair_tread.tscn")
const CODE_HUD_GLYPH_SCRIPT := preload("res://src/ui/CodeHUDGlyph.gd")
const NEON_FRAME_SCRIPT := preload("res://src/ui/NeonFrameControl.gd")
const ITEM_MODEL_ICON_SCENE: PackedScene = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root_v001.tscn")
const HUD_UI_SCALE := 0.80
const EXTRACTION_MID_PROGRESS := 0.36
const EXTRACTION_FINAL_PROGRESS := 0.70
const ENEMY_PREACTIVATION_RANGE := 38.0
const ENEMY_PREACTIVATION_INTERVAL := 0.12
const HOSTILE_ROOM_TYPES: Array[String] = GameDesignConfig.ROOM_TYPES_WITH_HOSTILES
const ENEMY_FILL_ATTEMPT_LIMIT := 4
const MINIMAP_RUNTIME_INTERVAL := 1.0 / 15.0
const FATE_CURRENCY_BY_RARITY := [20, 40, 70, 120, 180]
const BASE_INVENTORY_CAPACITY := 12

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
@onready var hp_bar: ProgressBar = $HUD/TopBar/Margin/HBox/HPBar
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
var _death_dialog: Control = null
var _death_animation_ready := false
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
var _weapon_panel: WeaponAssemblyTreePanel
var _workbench_panel: WorkbenchPanel
var _merchant_ui: MerchantUI
var _trade_extraction_unlocked := false
var _door_prompt_accumulator := 0.0
var _enemy_preactivation_accumulator := 0.0
var _door_fate_active := false
var _door_fate_choices: Array[FateCard] = []
var _pending_fate_currency_choice := -1
var _fate_overlay: Control
var _fate_feedback_label: Label = null
var _map_fate_triggers: MapFateTriggers
# 模态浮窗（雷达 / 背包）的 ESC 关闭按钮
var _radar_close_button: Button = null
var _inventory_close_button: Button = null
var last_killed_enemy_data: Dictionary = {}
var _resolved_event_rooms: Dictionary = {}
var _event_combat_rooms: Dictionary = {}
var _next_chest_quality_boost := 0
var _extra_loot_next_chest_count := 0
var _next_room_enemy_count := 0
var _next_room_enemy_hp_multiplier := 1.0
var _next_room_enemy_damage_multiplier := 1.0
var _next_room_currency_multiplier := 1.0
var _room_enemy_hp_multipliers: Dictionary = {}
var _room_enemy_damage_multipliers: Dictionary = {}
var _room_currency_multipliers: Dictionary = {}
var _world_currency_multiplier := 1.0
var _room_clear_bounty_rooms := 0
var _room_clear_bounty_amount := 0
var _extraction_time_multiplier := 1.0
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
var _reference_hud_root: Control = null
var _hud_weapon_meta_label: Label = null
var _hud_weapon_fate_label: Label = null
var _hud_weapon_model_icon: ItemModelIcon3D = null
var _hud_weapon_model_instance_id := ""
var _hud_quick_item_icons: Array = [null, null]
var _hud_quick_item_icon_hosts: Array[Control] = []
var _hud_quick_item_labels: Array[Label] = []
var _quick_item_ids: Array[String] = ["", ""]

# 手电筒电量 HUD 复用头像下方原本未接玩法的三格指示器。
var _hud_battery_time_label: Label = null
var _hud_battery_cells: Array[Panel] = []
var _hud_battery_panel: Control = null
var _hud_battery_cell_prev_filled: Array[bool] = []
var _hud_battery_blink_accum := 0.0
var _last_battery_tier := -1
var _hud_battery_blink_visible := 1.0
var _full_map_overlay: Control = null
var _full_map_control: DungeonMinimap3D = null
var _hud_floor_label: Label = null
var _hud_timer_label: Label = null
var _hud_run_elapsed := 0.0
var _hud_last_elapsed_second := -1
var _minimap_runtime_accumulator := 0.0
var _runtime_restore_snapshot: Dictionary = {}
var _runtime_persistence_active := false
var _segment_runtime_state: Dictionary = {}
var _room_stream_state_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("room_game_mode")
	if not test_mode and BaseManager != null:
		var candidate := BaseManager.get_active_run_checkpoint()
		if str(candidate.get("schema", "")) in ["runtime_player_state_v1", "runtime_player_state_v2"]:
			_runtime_restore_snapshot = candidate
			run_seed_override = int(candidate.get("run_seed", run_seed_override))
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
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	_generate_layout()
	player.set_combat_enabled(true)
	FateCardGameBridge.reset_run_state()
	FateCardGameBridge.set_player(player)
	if not FateCardGameBridge.scope_state_changed.is_connected(_on_fate_scope_state_changed):
		FateCardGameBridge.scope_state_changed.connect(_on_fate_scope_state_changed)
	player.hp_changed.connect(_on_player_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.presentation_state_changed.connect(_on_player_state_changed)
	player.death_animation_finished.connect(_on_player_death_animation_finished)
	player.debug_scale_changed.connect(_on_player_debug_scale_changed)
	if not player.weapon_instance_changed.is_connected(_on_hud_weapon_instance_changed):
		player.weapon_instance_changed.connect(_on_hud_weapon_instance_changed)
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		_apply_persisted_flashlight_module()
		if not flashlight.charge_changed.is_connected(_on_flashlight_charge_changed):
			flashlight.charge_changed.connect(_on_flashlight_charge_changed)
		if not flashlight.state_changed.is_connected(_on_flashlight_state_changed):
			flashlight.state_changed.connect(_on_flashlight_state_changed)
		_update_battery_hud()
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
	call_deferred("_activate_runtime_persistence")


func _exit_tree() -> void:
	if not test_mode and BaseManager != null and _runtime_persistence_active:
		BaseManager.unregister_runtime_checkpoint_provider(self, true)
	_runtime_persistence_active = false


func _activate_runtime_persistence() -> void:
	if test_mode or BaseManager == null or not is_inside_tree():
		return
	if not _runtime_restore_snapshot.is_empty():
		_restore_runtime_save_snapshot(_runtime_restore_snapshot)
	_runtime_persistence_active = true
	BaseManager.register_runtime_checkpoint_provider(self)
	if _inventory != null and not _inventory.inventory_changed.is_connected(_on_runtime_inventory_changed):
		_inventory.inventory_changed.connect(_on_runtime_inventory_changed)
	if _insurance != null and not _insurance.insurance_changed.is_connected(_on_runtime_insurance_changed):
		_insurance.insurance_changed.connect(_on_runtime_insurance_changed)
	if player != null:
		if not player.weapon_loadout_changed.is_connected(_on_runtime_weapon_changed):
			player.weapon_loadout_changed.connect(_on_runtime_weapon_changed)
		if not player.backpack_equipment_changed.is_connected(_on_runtime_backpack_changed):
			player.backpack_equipment_changed.connect(_on_runtime_backpack_changed)
	BaseManager.queue_runtime_checkpoint("runtime_ready", 0.1)


func _on_runtime_inventory_changed() -> void:
	_queue_runtime_autosave("inventory_changed")


func _on_runtime_insurance_changed() -> void:
	_queue_runtime_autosave("insurance_changed")


func _on_runtime_weapon_changed(_snapshot: Dictionary) -> void:
	_queue_runtime_autosave("weapon_changed")


func _on_runtime_backpack_changed(_snapshot: Dictionary) -> void:
	_queue_runtime_autosave("backpack_changed")


func _queue_runtime_autosave(reason: String) -> void:
	if _runtime_persistence_active and not _completed and BaseManager != null:
		BaseManager.queue_runtime_checkpoint(reason)


func build_runtime_save_snapshot() -> Dictionary:
	if player == null or _inventory == null or _insurance == null:
		return {}
	var weapon_items: Array[Dictionary] = []
	for slot_index in range(2):
		weapon_items.append(player.get_equipped_weapon_item_for_slot(slot_index))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	# 场景卸载时子节点可能已经离开 SceneTree；此时读取 global_position 会触发引擎错误。
	# Tower 根节点没有运行时位移，因此本地 position 是安全的最终兜底。
	var position := player.global_position if player.is_inside_tree() else player.position
	var runtime_room_id := _runtime_current_room_id_for_save()
	var runtime_floor_index := _runtime_current_floor_index()
	var snapshot := {
		"valid": true,
		"schema": "runtime_player_state_v2",
		"checkpoint_id": "runtime_player_state_v2",
		"layout_id": "runtime_player_state_v2",
		"scope": _runtime_scope_for_save(runtime_floor_index, runtime_room_id),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"run_seed": run_seed,
		"current_room_id": runtime_room_id,
		"current_floor_index": runtime_floor_index,
		"player_position": [position.x, position.y, position.z],
		# 玩家根节点同时是固定俯视相机的父节点，不能持久化角色朝向。
		# 武器/角色朝向由 aim_yaw 与表现层单独管理；保留字段仅用于旧存档结构兼容。
		"player_rotation_y": 0.0,
		"player_hp": player.current_hp,
		"inventory_capacity": _inventory.get_capacity(),
		"inventory_slots": _inventory.get_slots_snapshot(),
		"insurance_capacity": _insurance.get_max_slots(),
		"insurance_slots": _insurance.get_slots_snapshot(),
		"equipped_weapon_items": weapon_items,
		"active_weapon_slot": player.get_active_weapon_slot(),
		"equipped_backpack_item": player.get_equipped_backpack_item(),
		"flashlight_module_id": flashlight.get_module_id() if flashlight != null else "basic",
		"flashlight_charge_ratio": flashlight.get_charge_ratio() if flashlight != null else 1.0,
		"quick_item_ids": _quick_item_ids.duplicate(),
		"room_key_count": _room_key_count,
		"run_value": _run_value,
		"kills": _kills,
		"run_currency": GameManager.currency,
		"edge_states": _open_edges.duplicate(true),
	}
	snapshot["world_state"] = _build_runtime_world_save_snapshot()
	return snapshot


func _runtime_current_floor_index() -> int:
	return 0


func _runtime_current_room_id_for_save() -> String:
	return _current_room_id


func _runtime_scope_for_save(_floor_index: int, room_id: String) -> String:
	return "base" if room_id == "facility" else "combat"


func _build_runtime_world_save_snapshot() -> Dictionary:
	_capture_loaded_runtime_rooms()
	return {
		"schema": "dungeon_world_state_v1",
		"segment_runtime_state": _segment_runtime_state.duplicate(true),
	}


func _restore_runtime_save_snapshot(snapshot: Dictionary) -> void:
	if not _restore_runtime_world_save_snapshot(snapshot):
		# 世界布局或版本校验失败时保留玩家所有权数据，但拒绝使用旧房间和坐标。
		# 子类可据此回退基地/入口安全点，不能把角色投放进半生成世界。
		snapshot = snapshot.duplicate(true)
		snapshot["world_restore_failed"] = true
		snapshot["current_room_id"] = ""
		snapshot["player_position"] = []
	var backpack := snapshot.get("equipped_backpack_item", {}) as Dictionary
	if player.has_method("clear_equipped_backpack"):
		player.clear_equipped_backpack()
	if not backpack.is_empty():
		player.equip_backpack_item(backpack)
	_inventory.set_capacity(maxi(1, int(snapshot.get("inventory_capacity", BASE_INVENTORY_CAPACITY))))
	var inventory_slots: Variant = snapshot.get("inventory_slots", [])
	if inventory_slots is Array:
		_inventory.restore_slots_snapshot(inventory_slots as Array)
	_insurance.set_max_slots(maxi(0, int(snapshot.get("insurance_capacity", _insurance.get_max_slots()))))
	var insurance_slots: Variant = snapshot.get("insurance_slots", [])
	if insurance_slots is Array:
		_insurance.restore_slots_snapshot(insurance_slots as Array)
	player.clear_all_equipped_weapons()
	var weapon_items: Variant = snapshot.get("equipped_weapon_items", [])
	if weapon_items is Array:
		for slot_index in mini(2, (weapon_items as Array).size()):
			var item: Variant = (weapon_items as Array)[slot_index]
			if item is Dictionary and not (item as Dictionary).is_empty():
				player.equip_weapon_item_to_slot(item as Dictionary, slot_index)
	var active_slot := clampi(int(snapshot.get("active_weapon_slot", 0)), 0, 1)
	if not player.get_equipped_weapon_item_for_slot(active_slot).is_empty():
		player.switch_weapon_slot(active_slot)
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		player.restore_flashlight_module(str(snapshot.get("flashlight_module_id", "basic")))
		flashlight.set_charge_ratio(float(snapshot.get("flashlight_charge_ratio", 1.0)))
	_quick_item_ids.assign(snapshot.get("quick_item_ids", ["", ""]) as Array)
	while _quick_item_ids.size() < 2:
		_quick_item_ids.append("")
	_quick_item_ids.resize(2)
	_room_key_count = maxi(0, int(snapshot.get("room_key_count", 1)))
	_run_value = maxi(0, int(snapshot.get("run_value", 0)))
	_kills = maxi(0, int(snapshot.get("kills", 0)))
	GameManager.currency = maxi(0, int(snapshot.get("run_currency", 0)))
	GameManager.currency_changed.emit(GameManager.currency)
	var edge_states: Variant = snapshot.get("edge_states", {})
	if edge_states is Dictionary:
		for edge_value in (edge_states as Dictionary).keys():
			var edge := str(edge_value)
			if _open_edges.has(edge):
				var opened := bool((edge_states as Dictionary)[edge_value])
				_open_edges[edge] = opened
				var edge_rooms := edge.split("|", false, 1)
				if edge_rooms.size() == 2:
					_refresh_edge_visuals(edge_rooms[0], edge_rooms[1], opened)
		minimap.configure(_records, _open_edges)
	var room := _resolve_runtime_restore_room(snapshot)
	if room != null:
		_current_room_id = ""
		_on_room_entered(room)
	var saved_position: Variant = snapshot.get("player_position", [])
	var restore_position := room.global_position + Vector3.UP * 0.05 if room != null else Vector3.ZERO
	if saved_position is Array and (saved_position as Array).size() >= 3:
		var candidate_position := Vector3(
			float((saved_position as Array)[0]),
			float((saved_position as Array)[1]),
			float((saved_position as Array)[2]),
		)
		if room != null and _is_runtime_restore_position_valid(room, candidate_position):
			restore_position = candidate_position
	if room != null:
		player.global_position = restore_position
		player.velocity = Vector3.ZERO
	# 旧存档曾写入约 +/-PI 的玩家根节点旋转，恢复后会连同子相机一起掉头，
	# 造成整幅画面与输入的屏幕相对方向同时反转。固定相机项目中根节点必须归零。
	player.rotation.y = 0.0
	player.current_hp = clampi(int(snapshot.get("player_hp", player.current_hp)), 1, player.max_hp)
	player.hp_changed.emit(player.current_hp, player.max_hp)
	if _inventory_ui != null:
		_inventory_ui.set_quick_item_assignments(_quick_item_ids)
	_refresh_quick_item_hud()
	_refresh_loot_label()


func _restore_runtime_world_save_snapshot(snapshot: Dictionary) -> bool:
	var world_state := snapshot.get("world_state", {}) as Dictionary
	var saved_segment_state: Variant = world_state.get("segment_runtime_state", {})
	if saved_segment_state is Dictionary:
		_segment_runtime_state = (saved_segment_state as Dictionary).duplicate(true)
	return true


func _resolve_runtime_restore_room(snapshot: Dictionary) -> DungeonRoom3D:
	return _room_by_id.get(str(snapshot.get("current_room_id", ""))) as DungeonRoom3D


func _is_runtime_restore_position_valid(room: DungeonRoom3D, world_position: Vector3) -> bool:
	if room == null or not world_position.is_finite():
		return false
	var local := (
		room.to_local(world_position)
		if room.is_inside_tree()
		else world_position - room.position
	)
	var dimensions := room.get_dimensions()
	return (
		absf(local.x) <= dimensions.x * 0.5 + 2.0
		and absf(local.z) <= dimensions.y * 0.5 + 2.0
		and local.y >= -0.6
		and local.y <= 2.5
	)


## 每局只在初始化时从 BaseData 注入模块；局内仍由 PlayerFlashlight3D 拒绝换装。
func _apply_persisted_flashlight_module() -> void:
	if player == null or not player.has_method("restore_flashlight_module"):
		return
	var module_id := BaseManager.get_equipped_flashlight_module_id()
	if not BaseManager.is_flashlight_module_unlocked(module_id):
		module_id = "basic"
	player.restore_flashlight_module(module_id)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		var key := key_event.keycode if key_event.keycode != 0 else key_event.physical_keycode
		if key == KEY_ESCAPE and _door_fate_active:
			_cancel_door_fate_selection()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_M:
			_toggle_full_map()
			get_viewport().set_input_as_handled()
			return
		if key in [KEY_1, KEY_2] and not _has_exclusive_modal() and not (_inventory_ui != null and _inventory_ui.is_inventory_open()):
			_select_weapon_slot(0 if key == KEY_1 else 1)
			get_viewport().set_input_as_handled()
			return
		if key in [KEY_3, KEY_4] and not _has_exclusive_modal() and not (_inventory_ui != null and _inventory_ui.is_inventory_open()):
			_use_quick_item(0 if key == KEY_3 else 1)
			get_viewport().set_input_as_handled()
			return
	if key_event != null and key_event.pressed and not key_event.echo and (key_event.keycode == KEY_K or key_event.physical_keycode == KEY_K):
		if _weapon_panel != null:
			_weapon_panel.toggle()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not _completed:
		var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
		if room != null:
			var door_info := room.get_nearest_door(player.global_position)
			if not door_info.is_empty() and not bool(door_info.get("is_open", false)):
				get_viewport().set_input_as_handled()
				_try_open_room_door(str(door_info.get("target_room_id", "")))


func _process(delta: float) -> void:
	_tick_bless_dead(delta)
	_tick_battery_blink(delta)
	_tick_enemy_preactivation(delta)
	_hud_run_elapsed += delta
	var elapsed_seconds := int(_hud_run_elapsed)
	if _hud_timer_label != null and elapsed_seconds != _hud_last_elapsed_second:
		_hud_last_elapsed_second = elapsed_seconds
		_hud_timer_label.text = "%02d:%02d" % [elapsed_seconds / 60, elapsed_seconds % 60]
	_minimap_runtime_accumulator += delta
	if _minimap_runtime_accumulator >= MINIMAP_RUNTIME_INTERVAL:
		_minimap_runtime_accumulator = fmod(
			_minimap_runtime_accumulator, MINIMAP_RUNTIME_INTERVAL
		)
		if _hud_floor_label != null and minimap != null:
			var next_floor_text := "高塔外层 · %s" % minimap.get_floor_label()
			if _hud_floor_label.text != next_floor_text:
				_hud_floor_label.text = next_floor_text
		if minimap != null and player != null:
			minimap.set_player_state(
				player.global_position,
				player.aim_direction
			)
			minimap.set_enemy_positions(_get_minimap_enemy_positions())
			if _full_map_control != null and is_instance_valid(_full_map_control):
				_full_map_control.copy_state_from(minimap)
	_door_prompt_accumulator += delta
	if _door_prompt_accumulator < 0.08:
		return
	_door_prompt_accumulator = 0.0
	var current := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if current != null and player != null:
		current.get_nearest_door(player.global_position)


func _tick_enemy_preactivation(delta: float) -> void:
	_enemy_preactivation_accumulator += delta
	if _enemy_preactivation_accumulator < ENEMY_PREACTIVATION_INTERVAL:
		return
	_enemy_preactivation_accumulator = fmod(
		_enemy_preactivation_accumulator, ENEMY_PREACTIVATION_INTERVAL
	)
	if player == null:
		return
	var candidates: Array[Node3D] = (
		GameplaySpatialRegistry3D.query_radius(
			player.global_position,
			ENEMY_PREACTIVATION_RANGE,
			[GameplaySpatialRegistry3D.KIND_ENEMY]
		)
		if GameplaySpatialRegistry3D != null
		else []
	)
	for value in candidates:
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and is_ancestor_of(enemy):
			enemy.activate_from_player_proximity(player, ENEMY_PREACTIVATION_RANGE)


func _setup_run_modules() -> void:
	GameManager.currency = 0
	GameManager.currency_changed.emit(0)
	_inventory = InventoryModule.new(BASE_INVENTORY_CAPACITY)
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
	_inventory_ui.set_weapon_owner(player)
	_inventory_ui.set_backpack_owner(self)
	_inventory_ui.set_world_drop_handler(_drop_inventory_item_to_world)
	_inventory_ui.item_to_insurance_requested.connect(_on_insure_item_requested)
	_inventory_ui.item_extraction_requested.connect(_on_claim_insurance_requested)
	_inventory_ui.insurance_item_move_requested.connect(_on_insurance_item_move_requested)
	_inventory_ui.item_clicked.connect(_on_inventory_item_clicked)
	_inventory_ui.inventory_open_changed.connect(_on_inventory_open_changed)
	_inventory_ui.weapon_slot_equip_requested.connect(_on_weapon_slot_equip_requested)
	_inventory_ui.equipped_weapon_to_inventory_requested.connect(_on_equipped_weapon_to_inventory_requested)
	_inventory_ui.equipped_weapon_drop_requested.connect(_on_equipped_weapon_drop_requested)
	_inventory_ui.attachment_slot_install_requested.connect(_on_attachment_slot_install_requested)
	_inventory_ui.attachment_slot_remove_requested.connect(_on_attachment_slot_remove_requested)
	_inventory_ui.backpack_slot_equip_requested.connect(_on_backpack_slot_equip_requested)
	_inventory_ui.equipped_backpack_to_inventory_requested.connect(_on_equipped_backpack_to_inventory_requested)
	_inventory_ui.equipped_backpack_drop_requested.connect(_on_equipped_backpack_drop_requested)
	_inventory_ui.quick_item_assignment_requested.connect(_on_quick_item_assignment_requested)
	_inventory_ui.set_quick_item_assignments(_quick_item_ids)
	_weapon_panel = WEAPON_PRESENTATION_SCENE.instantiate() as WeaponAssemblyTreePanel
	if _weapon_panel != null:
		_weapon_panel.name = "WeaponPresentationPage3D"
		$HUD.add_child(_weapon_panel)
		_weapon_panel.set_anchors_preset(Control.PRESET_CENTER)
		# 独立管理页居中覆盖战场，与背包/基地设施的模态信息架构一致。
		_weapon_panel.position = Vector2(-260, -310)
		_weapon_panel.size = Vector2(520, 620)
		_weapon_panel.z_index = 420
		_weapon_panel.set_weapon_tree(player.get_weapon_tree())
		_weapon_panel.set_weapon_owner(player)


func _install_holographic_hud_style() -> void:
	# 原节点路径仍由自动化读取；视觉层改由独立锚点控件承载。
	($HUD/TopBar as Control).visible = false
	($HUD/StatusPanel as Control).visible = false
	($HUD/ControlHint as Control).visible = false
	($HUD/VisionHint as Control).visible = false
	_build_reference_main_hud()

	var extraction_style := _make_hud_style(Color(0.22, 1.0, 0.66), Color(0.008, 0.044, 0.046, 0.94), 2)
	extraction_panel.add_theme_stylebox_override("panel", extraction_style)
	_anchor_control(extraction_panel, 0.5, 1.0, 0.5, 1.0, -250, -252, 250, -184)
	extraction_bar.custom_minimum_size = _hud_size(Vector2(460, 22))
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


func _build_reference_main_hud() -> void:
	_reference_hud_root = Control.new()
	_reference_hud_root.name = "ReferenceCombatHUD"
	_reference_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reference_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reference_hud_root.z_index = 100
	$HUD.add_child(_reference_hud_root)

	var cyan := Color(0.23, 0.88, 1.0)
	var subdued := Color(0.62, 0.74, 0.82)
	var identity := _make_hud_label("弹壳风暴 2  |  COMBAT / WEAPON / FATE-CARD", 15, Color(0.86, 0.92, 0.96))
	_anchor_control(identity, 0.0, 0.0, 0.0, 0.0, 18, 10, 520, 36)
	_reference_hud_root.add_child(identity)

	room_label = _make_hud_label("ROOM", 14, Color(0.60, 0.90, 1.0))
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(room_label, 0.5, 0.0, 0.5, 0.0, -220, 14, 220, 38)
	_reference_hud_root.add_child(room_label)

	var player_panel := _make_hud_panel(cyan, Color(0.006, 0.018, 0.030, 0.88))
	player_panel.name = "PlayerStatusBlock"
	_anchor_control(player_panel, 0.0, 0.0, 0.0, 0.0, 18, 46, 360, 178)
	_reference_hud_root.add_child(player_panel)
	_add_neon_frame(player_panel, cyan, 0.72, true)
	# tap 头像 → 切换背包（键 I / Tab 等效）
	player_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	player_panel.tooltip_text = "点击打开/关闭背包 [键 I / Tab]"
	player_panel.gui_input.connect(_on_player_status_gui_input.bind(player_panel))
	var player_margin := _make_margin(12, 10, 12, 10)
	player_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.add_child(player_margin)
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", _hud_int(12))
	player_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_margin.add_child(player_row)
	var portrait := CODE_HUD_GLYPH_SCRIPT.new() as CodeHUDGlyph
	portrait.custom_minimum_size = _hud_size(Vector2(82, 82))
	portrait.configure("robot", Color(1.0, 0.25, 0.84))
	player_row.add_child(portrait)
	var stat_vbox := VBoxContainer.new()
	stat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_vbox.add_theme_constant_override("separation", _hud_int(5))
	player_row.add_child(stat_vbox)
	hp_label = _make_hud_label("230 / 230", 17, Color.WHITE)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_vbox.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = _hud_size(Vector2(220, 22))
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.12, 0.02, 0.04), 4))
	var hp_fill := _make_bar_style(Color(0.93, 0.055, 0.12), 4)
	hp_fill.shadow_color = Color(0.95, 0.02, 0.12, 0.42)
	hp_fill.shadow_size = 5
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	stat_vbox.add_child(hp_bar)
	var energy := HBoxContainer.new()
	energy.name = "FlashlightBatteryPanel"
	energy.custom_minimum_size = _hud_size(Vector2(220, 14))
	energy.add_theme_constant_override("separation", _hud_int(6))
	energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_vbox.add_child(energy)
	_hud_battery_panel = energy
	for index in range(3):
		var pip := Panel.new()
		pip.name = "BatteryCell_%d" % index
		pip.custom_minimum_size = _hud_size(Vector2(34, 9))
		pip.add_theme_stylebox_override("panel", _make_hud_style(cyan, Color(cyan, 0.72), 1))
		energy.add_child(pip)
		_hud_battery_cells.append(pip)
	_hud_battery_time_label = _make_hud_label("FULL · 基地内", 11, Color(0.72, 0.86, 0.96))
	_hud_battery_time_label.name = "BatteryTimeLabel"
	_hud_battery_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_battery_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	energy.add_child(_hud_battery_time_label)
	loot_label = _make_hud_label("背包 0/12 · 钥匙 1 · 魂 0", 13, Color(1.0, 0.76, 0.26))
	stat_vbox.add_child(loot_label)

	seed_label = _make_hud_label("SEED", 12, subdued)
	_anchor_control(seed_label, 0.0, 0.0, 0.0, 0.0, 22, 180, 360, 202)
	_reference_hud_root.add_child(seed_label)

	# 圆形小地图沿用真实房间/玩家/敌人数据，只替换视觉外壳。
	minimap.z_index = 105
	_anchor_control(minimap, 1.0, 0.0, 1.0, 0.0, -292, 44, -18, 318)
	# tap 小地图 → 切换全层地图（键 M 等效）
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.tooltip_text = "点击打开/关闭全层地图 [键 M]"
	minimap.gui_input.connect(_on_radar_gui_input.bind(minimap))
	_hud_floor_label = _make_hud_label("高塔外层", 15, Color(0.90, 0.94, 0.96))
	_hud_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(_hud_floor_label, 1.0, 0.0, 1.0, 0.0, -300, 12, -12, 38)
	_reference_hud_root.add_child(_hud_floor_label)
	var timer_panel := _make_hud_panel(cyan, Color(0.006, 0.016, 0.026, 0.88))
	_anchor_control(timer_panel, 1.0, 0.0, 1.0, 0.0, -214, 318, -18, 358)
	_reference_hud_root.add_child(timer_panel)
	var timer_row := HBoxContainer.new()
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_theme_constant_override("separation", _hud_int(16))
	timer_panel.add_child(timer_row)
	var timer_caption := _make_hud_label("◷", 18, Color.WHITE)
	timer_row.add_child(timer_caption)
	_hud_timer_label = _make_hud_label("00:00", 17, Color.WHITE)
	timer_row.add_child(_hud_timer_label)
	var pause_icon := CODE_HUD_GLYPH_SCRIPT.new() as CodeHUDGlyph
	pause_icon.custom_minimum_size = _hud_size(Vector2(30, 30))
	pause_icon.configure("pause", Color(0.84, 0.90, 0.96))
	timer_row.add_child(pause_icon)

	var info_panel := _make_hud_panel(cyan, Color(0.008, 0.035, 0.052, 0.90))
	info_panel.name = "CurrentInfoPanel"
	_anchor_control(info_panel, 0.5, 1.0, 0.5, 1.0, -290, -184, 290, -126)
	_reference_hud_root.add_child(info_panel)
	_add_neon_frame(info_panel, cyan, 0.58, false)
	var info_margin := _make_margin(18, 8, 18, 8)
	info_panel.add_child(info_margin)
	status_label = _make_hud_label("正在建立行动区……", 14, Color(0.76, 0.91, 0.98))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_margin.add_child(status_label)

	var weapon_panel := _make_hud_panel(Color(0.56, 0.78, 0.88), Color(0.006, 0.012, 0.020, 0.94))
	weapon_panel.name = "CurrentWeaponPanel"
	_anchor_control(weapon_panel, 0.5, 1.0, 0.5, 1.0, -260, -118, 260, -20)
	_reference_hud_root.add_child(weapon_panel)
	_add_neon_frame(weapon_panel, cyan, 0.36, false)
	# 中央武器栏：tap 在主武器 / 副武器 之间切换（_on_ammo_changed 里 [N] 会自动反映新槽位）
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	weapon_panel.tooltip_text = "点击切换主/副武器"
	weapon_panel.gui_input.connect(_on_weapon_panel_gui_input.bind(weapon_panel))
	var weapon_margin := _make_margin(14, 10, 14, 8)
	weapon_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_panel.add_child(weapon_margin)
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", _hud_int(12))
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_margin.add_child(weapon_row)
	_hud_weapon_model_icon = ITEM_MODEL_ICON_SCENE.instantiate() as ItemModelIcon3D
	_hud_weapon_model_icon.name = "CurrentWeaponModelIcon3D"
	_hud_weapon_model_icon.custom_minimum_size = _hud_size(Vector2(96, 68))
	_hud_weapon_model_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hud_weapon_model_icon.set_camera_size_multiplier(0.52)
	_hud_weapon_model_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_hud_weapon_model_icon)
	_refresh_hud_weapon_model(true)
	var weapon_text := VBoxContainer.new()
	weapon_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_text.add_theme_constant_override("separation", _hud_int(2))
	weapon_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(weapon_text)
	_hud_weapon_meta_label = _make_hud_label("当前武器 · 未装备", 15, Color(0.92, 0.95, 0.98))
	_hud_weapon_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_text.add_child(_hud_weapon_meta_label)
	_hud_weapon_fate_label = _make_hud_label("实例 ------ · 命运 0/0 · K 详情", 12, Color(0.48, 0.84, 0.94))
	_hud_weapon_fate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_text.add_child(_hud_weapon_fate_label)
	ammo_label = _make_hud_label("0 / 0", 29, Color.WHITE)
	ammo_label.custom_minimum_size = _hud_size(Vector2(112, 62))
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(ammo_label)
	for quick_index in range(2):
		var quick_panel := _make_hud_panel(Color(0.30, 0.86, 0.72), Color(0.006, 0.020, 0.026, 0.94))
		quick_panel.name = "QuickItemHUD_%d" % quick_index
		var left := -372.0 if quick_index == 0 else 276.0
		var right := -276.0 if quick_index == 0 else 372.0
		_anchor_control(quick_panel, 0.5, 1.0, 0.5, 1.0, left, -112, right, -20)
		_reference_hud_root.add_child(quick_panel)
		# 快捷物品槽：[3]/[4] 直接 tap 使用，对应键位 use_quick_item_1/2
		quick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		quick_panel.tooltip_text = "点击使用快捷物品 [键%d]" % (quick_index + 3)
		quick_panel.gui_input.connect(_on_quick_item_gui_input.bind(quick_index, quick_panel))
		var quick_box := VBoxContainer.new()
		quick_box.alignment = BoxContainer.ALIGNMENT_CENTER
		quick_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_panel.add_child(quick_box)
		var quick_icon_host := Control.new()
		quick_icon_host.name = "QuickItemIconHost_%d" % quick_index
		quick_icon_host.custom_minimum_size = _hud_size(Vector2(80, 58))
		quick_icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_box.add_child(quick_icon_host)
		_hud_quick_item_icon_hosts.append(quick_icon_host)
		var quick_label := _make_hud_label("[%d] 空" % (quick_index + 3), 11, Color(0.66, 0.94, 0.84))
		quick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_box.add_child(quick_label)
		_hud_quick_item_labels.append(quick_label)
	_refresh_quick_item_hud()

	var actions := HBoxContainer.new()
	actions.name = "ActionKeyStrip"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", _hud_int(8))
	_anchor_control(actions, 1.0, 1.0, 1.0, 1.0, -374, -108, -18, -18)
	_reference_hud_root.add_child(actions)
	# 4 个右下角动作按钮桥接到 input action：R 换弹 / SHIFT 冲刺 / F 探照 / E 交互。
	# 同时供 PC 端和移动端使用：移动端直接 tap，PC 端鼠标点击也会触发 Input.parse_input_event。
	for data in [
		["reload", "R", "换弹", "reload"],
		["dash", "SHIFT", "冲刺", "dash"],
		["shield", "F", "探照", "toggle_flashlight"],
		["interact", "E", "交互", "interact"],
	]:
		actions.add_child(_make_action_key(str(data[0]), str(data[1]), str(data[2]), str(data[3]), cyan))


func _on_weapon_panel_gui_input(event: InputEvent, panel: PanelContainer) -> void:
	# tap 在主/副武器槽之间循环：当前 0 → 切 1，当前 1 → 切 0。状态本身存于 Player3D.active_weapon_slot。
	if not _is_panel_press(event):
		return
	if player == null:
		return
	var current_slot := 0
	if player.has_method("get_active_weapon_slot"):
		current_slot = int(player.call("get_active_weapon_slot"))
	var next_slot := 1 if current_slot == 0 else 0
	_select_weapon_slot(next_slot)
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _on_quick_item_gui_input(event: InputEvent, quick_index: int, panel: PanelContainer) -> void:
	# tap 使用快捷物品：对齐键位 3/4。空槽/物品耗尽时 _use_quick_item 会写 status_label 反馈。
	if not _is_panel_press(event):
		return
	_use_quick_item(quick_index)
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _is_panel_press(event: InputEvent) -> bool:
	# 同时识别 PC 鼠标左键和移动端触屏按下；用 _on_action_key_gui_input 的同款判断
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return st.pressed
	return false

func _on_radar_gui_input(event: InputEvent, panel: Control) -> void:
	# tap 右上小地图 = M 键
	if not _is_panel_press(event):
		return
	_toggle_full_map()
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _on_player_status_gui_input(event: InputEvent, panel: PanelContainer) -> void:
	# tap 头像面板 = I / Tab 键
	if not _is_panel_press(event):
		return
	if _inventory_ui != null:
		_inventory_ui.toggle_inventory_panel()
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _build_modal_close_button(label: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = label + "（对应 ESC 键）"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = _hud_size(Vector2(150, 36))
	btn.add_theme_font_size_override("font_size", _hud_int(13))
	var styles := UIStyleFactory.make_button_style(
		UIStyleFactory.make_panel_bg(2).bg_color,
		Color(0.62, 0.90, 0.96)
	)
	UIStyleFactory.apply_button_style(btn, styles)
	btn.pressed.connect(on_press)
	return btn

func _ensure_inventory_close_button() -> void:
	# 背包打开时显示 ESC 关闭按钮
	if _inventory_close_button != null and is_instance_valid(_inventory_close_button):
		return
	if _reference_hud_root == null:
		return
	var btn := _build_modal_close_button("关闭 · ESC", _close_inventory_via_button)
	# inventory_shell 是 PanelContainer，会把子节点撑满成自己 970×650 的尺寸。放到 _reference_hud_root (Control) 下才能用锚点 + offsets 定位。
	btn.z_index = 500
	_anchor_control(btn, 1.0, 0.0, 1.0, 0.0, -180, 18, -18, 60)
	_reference_hud_root.add_child(btn)
	_inventory_close_button = btn

func _teardown_inventory_close_button() -> void:
	if _inventory_close_button != null and is_instance_valid(_inventory_close_button):
		_inventory_close_button.queue_free()
	_inventory_close_button = null

func _close_inventory_via_button() -> void:
	if _inventory_ui != null:
		_inventory_ui.set_inventory_panel_open(false)


func _make_action_key(kind: String, key_text: String, caption: String, action_name: String, accent: Color) -> PanelContainer:
	var panel := _make_hud_panel(Color(accent, 0.72), Color(0.006, 0.014, 0.024, 0.88))
	panel.custom_minimum_size = _hud_size(Vector2(78, 82))
	# 关键：_make_hud_panel 默认 mouse_filter=IGNORE；动作键必须 STOP 才能收到 gui_input
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "%s  ·  %s" % [key_text, caption]
	panel.gui_input.connect(_on_action_key_gui_input.bind(action_name, panel, accent))
	var margin := _make_margin(6, 4, 6, 3)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)
	var icon := CODE_HUD_GLYPH_SCRIPT.new() as CodeHUDGlyph
	icon.custom_minimum_size = _hud_size(Vector2(52, 46))
	icon.configure(kind, Color(0.90, 0.96, 1.0))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)
	var key_label := _make_hud_label("%s · %s" % [key_text, caption], 10, Color(0.86, 0.90, 0.94))
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(key_label)
	return panel


func _on_action_key_gui_input(event: InputEvent, action_name: String, panel: PanelContainer, accent: Color) -> void:
	# 同时处理鼠标（PC）和触屏（移动端）两种来源的按下事件
	var should_press := false
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			should_press = true
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			should_press = true
	if not should_press:
		return
	_tap_input_action(action_name)
	_flash_action_key(panel)
	# 标记为已处理：避免被 MobileInput 的 _input / aim zone 重复触发
	get_viewport().set_input_as_handled()


func _flash_action_key(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	var original_modulate := panel.modulate
	panel.modulate = Color(1.55, 1.55, 1.55, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.10)
	tween.tween_callback(func():
		if is_instance_valid(panel):
			panel.modulate = original_modulate
	)


func _tap_input_action(action: StringName) -> void:
	# 仿照 Player3D._tap_input_action：把一次性的 input action 注入 Input 单次队列。
	# Player3D 端 _update_combat_input / PlayerFlashlight3D._unhandled_input / 状态机的
	# is_action_just_pressed("dash") 都会在下一帧检测到。
	var pressed_event := InputEventAction.new()
	pressed_event.action = action
	pressed_event.pressed = true
	Input.parse_input_event(pressed_event)
	var released_event := InputEventAction.new()
	released_event.action = action
	released_event.pressed = false
	Input.parse_input_event(released_event)


func _make_hud_panel(accent: Color, background: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_hud_style(accent, background, 1))
	return panel


func _make_hud_style(accent: Color, background: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = accent
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(accent, 0.22)
	style.shadow_size = 7
	return style


func _make_bar_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _make_hud_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", _hud_int(font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.025, 0.045, 0.94))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _make_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _hud_int(left))
	margin.add_theme_constant_override("margin_top", _hud_int(top))
	margin.add_theme_constant_override("margin_right", _hud_int(right))
	margin.add_theme_constant_override("margin_bottom", _hud_int(bottom))
	return margin


func _add_neon_frame(parent: Control, accent: Color, glow: float, scan_lines: bool) -> void:
	var frame := NEON_FRAME_SCRIPT.new() as NeonFrameControl
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.configure(accent, glow, scan_lines)
	parent.add_child(frame)
	parent.move_child(frame, parent.get_child_count() - 1)


func _anchor_control(
	control: Control,
	anchor_left: float, anchor_top: float, anchor_right: float, anchor_bottom: float,
	offset_left: float, offset_top: float, offset_right: float, offset_bottom: float
) -> void:
	control.anchor_left = anchor_left
	control.anchor_top = anchor_top
	control.anchor_right = anchor_right
	control.anchor_bottom = anchor_bottom
	control.offset_left = offset_left * HUD_UI_SCALE
	control.offset_top = offset_top * HUD_UI_SCALE
	control.offset_right = offset_right * HUD_UI_SCALE
	control.offset_bottom = offset_bottom * HUD_UI_SCALE


func _hud_size(value: Vector2) -> Vector2:
	return value * HUD_UI_SCALE


func _hud_int(value: int) -> int:
	return maxi(1, int(round(float(value) * HUD_UI_SCALE)))


func _on_inventory_open_changed(opened: bool) -> void:
	if opened and _has_exclusive_modal():
		_inventory_ui.set_inventory_panel_open(false)
		status_label.text = "先完成当前交互，再打开背包"
		return
	_sync_player_input_lock()
	if opened:
		status_label.text = "背包已打开 · 左键使用/装备，右键存入保险格"
		_ensure_inventory_close_button()
	else:
		status_label.text = "背包已关闭 · 继续搜索、战斗或撤离"
		_teardown_inventory_close_button()


func _has_exclusive_modal() -> bool:
	# 撤离不再锁定输入：玩家可以自由移动/开枪/翻滚；
	# _extraction_defense_active 仅作为“撤离进行中”标记存在。
	return (
		_completed
		or _door_fate_active
		or (_full_map_overlay != null and is_instance_valid(_full_map_overlay))
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
	if _full_map_overlay != null and is_instance_valid(_full_map_overlay):
		_close_full_map()
		return true
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
		_cancel_door_fate_selection()
		return true
	return false


func _toggle_full_map() -> void:
	if _full_map_overlay != null and is_instance_valid(_full_map_overlay):
		_close_full_map()
		return
	if _has_exclusive_modal():
		status_label.text = "先完成当前交互，再打开楼层大地图"
		return
	_close_inventory_for_modal()
	_full_map_overlay = Control.new()
	_full_map_overlay.name = "ExploredFloorMapOverlay"
	_full_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_map_overlay.z_index = 850
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.004, 0.010, 0.84)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_map_overlay.add_child(dim)
	_full_map_control = DungeonMinimap3D.new()
	_full_map_control.name = "FullFloorMap3D"
	_full_map_control.set_anchors_preset(Control.PRESET_CENTER)
	_full_map_control.position = Vector2(-470, -300)
	_full_map_control.size = Vector2(940, 600)
	_full_map_control.custom_minimum_size = Vector2(940, 600)
	_full_map_control.set_full_map_mode(true)
	_full_map_control.copy_state_from(minimap)
	_full_map_overlay.add_child(_full_map_control)
	var hint := _make_hud_label("M / ESC 关闭 · 仅显示本层已探索房间与当前位置", 14, Color(0.62, 0.90, 0.96))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(hint, 0.5, 1.0, 0.5, 1.0, -360, -44, 360, -16)
	_full_map_overlay.add_child(hint)
	$HUD.add_child(_full_map_overlay)
	_sync_player_input_lock()
	# tap 关闭按钮（ESC 等效）
	var radar_close_btn := _build_modal_close_button("关闭 · ESC", _close_full_map)
	_anchor_control(radar_close_btn, 1.0, 0.0, 1.0, 0.0, -180, 18, -18, 60)
	_full_map_overlay.add_child(radar_close_btn)
	_radar_close_button = radar_close_btn
	status_label.text = "楼层大地图已打开 · 仅展示已探索区域"


func _close_full_map() -> void:
	if _full_map_overlay != null and is_instance_valid(_full_map_overlay):
		_full_map_overlay.queue_free()
	_full_map_overlay = null
	_full_map_control = null
	if _radar_close_button != null and is_instance_valid(_radar_close_button):
		_radar_close_button.queue_free()
	_radar_close_button = null
	_sync_player_input_lock()
	status_label.text = "楼层大地图已关闭"


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
	key_light.add_to_group(EnemyIllumination3D.SUN_GROUP)
	key_light.set_meta("gameplay_light_kind", "sun")
	if GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.register_node(key_light, GameplaySpatialRegistry3D.KIND_SUN)
		key_light.tree_exiting.connect(GameplaySpatialRegistry3D.unregister_node.bind(key_light))


func apply_performance_quality(profile: String) -> void:
	if world_environment.environment != null:
		world_environment.environment.fog_enabled = profile != "low"
		world_environment.environment.fog_density = (
			visual_theme.fog_density
			if profile == "high"
			else visual_theme.fog_density * 0.72
		)
	key_light.shadow_enabled = profile != "low"
	key_light.directional_shadow_max_distance = 96.0 if profile == "high" else 64.0 if profile == "balanced" else 36.0


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
	_ensure_structural_shells_resident()
	for record in _records:
		if str(record.get("parent", "")).is_empty():
			continue
		var parent: DungeonRoom3D = _room_by_id.get(str(record["parent"])) as DungeonRoom3D
		var child: DungeonRoom3D = _room_by_id.get(str(record["id"])) as DungeonRoom3D
		if parent != null and child != null:
			_build_corridor(parent, child, int(record["index"]))
	_create_extraction()


func _ensure_structural_shells_resident() -> void:
	# 必须在门轴/最终房间坐标提交后构建，避免用未冻结拓扑生成错误门洞。
	for room in _rooms:
		if room != null and is_instance_valid(room):
			room.ensure_shell_built()
			room.visible = true


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
	beacon.configure(visual_theme.accent_color, countdown * _extraction_time_multiplier, type_id)
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
	var previous_runtime_room_id := _current_room_id
	if not _current_room_id.is_empty() and _current_room_id != room.room_id:
		var previous_room := _room_by_id.get(_current_room_id) as DungeonRoom3D
		if previous_room != null:
			previous_room.hide_door_prompts()
	if not previous_runtime_room_id.is_empty() and previous_runtime_room_id != room.room_id:
		_capture_room_runtime_state(previous_runtime_room_id)
	_current_room_id = room.room_id
	room_entered.emit(room)
	if _runtime_persistence_active and BaseManager != null:
		BaseManager.flush_runtime_checkpoint("room_transition")
	minimap.set_current_room(room.room_id)
	_update_room_streaming(room.room_id)
	room_label.text = "%s · %s/%s" % [room.room_id, room.room_type, room.size_class.to_upper()]
	var first_visit := not _spawned_rooms.has(room.room_id)
	if first_visit and player.has_method("on_fate_room_entered"):
		player.call("on_fate_room_entered")
	if _spawned_rooms.has(room.room_id):
		_ensure_room_key_reward(room)
		_repair_room_progress(room)
		status_label.text = _return_room_status(room)
		return
	_spawned_rooms[room.room_id] = true
	if room.room_type == "START":
		call_deferred("_spawn_starter_weapon_pickup", room)
	if room.room_type in HOSTILE_ROOM_TYPES:
		_spawn_room_enemies(room)
	elif room.room_type == "EVENT":
		room.cleared = false
		if _ensure_event_room_objective(room):
			status_label.text = "事件房：前往紫色光柱，按 E 使用异常信号终端"
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
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "boss", "floor": floor, "floor_level": floor_level, "floor_number": _elite_floor_number(room)}))
			enemy_configs.append_array(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level, "floor_number": _elite_floor_number(room), "encounter_id": _elite_encounter_id(room), "seed": run_seed}))
		"ELITE":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level, "floor_number": _elite_floor_number(room), "encounter_id": _elite_encounter_id(room), "seed": run_seed}))
		"TRAP":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "ambush", "count": 3 + floor / 2, "floor": floor, "floor_level": floor_level}))
		"BASEMENT":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": maxi(RoomData.FloorLevel.MEDIUM, floor_level), "floor_number": _elite_floor_number(room), "encounter_id": _elite_encounter_id(room), "seed": run_seed}))
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
	if _next_room_enemy_count > 0:
		var reinforcements := _monster_injector.generate_enemies({
			"type": "ambush", "count": _next_room_enemy_count, "floor": floor,
			"floor_level": floor_level,
		})
		enemy_configs.append_array(reinforcements)
		_next_room_enemy_count = 0
	_room_enemy_hp_multipliers[room.room_id] = _next_room_enemy_hp_multiplier
	_room_enemy_damage_multipliers[room.room_id] = _next_room_enemy_damage_multiplier
	_room_currency_multipliers[room.room_id] = _next_room_currency_multiplier
	_next_room_enemy_hp_multiplier = 1.0
	_next_room_enemy_damage_multiplier = 1.0
	_next_room_currency_multiplier = 1.0
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


func _elite_encounter_id(room: DungeonRoom3D) -> String:
	var checkpoint_id := str(build_runtime_save_snapshot().get("checkpoint_id", "run:%d" % run_seed))
	return "%s:%s:elite" % [checkpoint_id, room.room_id]


func _elite_floor_number(room: DungeonRoom3D) -> int:
	return maxi(1, int(room.get_meta("floor_number", visual_theme.difficulty_rank)))


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
		var spawn_data := enemy_configs[index].duplicate(true)
		if not spawn_data.has("spawn_index"):
			spawn_data["spawn_index"] = index
		if not spawn_data.has("persistent_id"):
			spawn_data["persistent_id"] = "%s:wave_%d:%d" % [
				room.room_id,
				int(_room_wave_numbers.get(room.room_id, 1)),
				index,
			]
		enemy.configure_from_enemy_data(spawn_data)
		var hp_multiplier := float(_room_enemy_hp_multipliers.get(room.room_id, 1.0))
		if not is_equal_approx(hp_multiplier, 1.0):
			enemy.apply_health_multiplier(hp_multiplier)
		var damage_multiplier := float(_room_enemy_damage_multipliers.get(room.room_id, 1.0))
		if not is_equal_approx(damage_multiplier, 1.0):
			enemy.contact_damage = maxi(1, int(round(float(enemy.contact_damage) * damage_multiplier)))
		var points := room.enemy_spawn_points
		enemy.global_position = points[index % points.size()] if not points.is_empty() else room.global_position
		enemy.killed.connect(_on_enemy_killed)
		enemy.summon_requested.connect(_on_summon_requested)
		enemy.boss_phase_changed.connect(_on_boss_phase_changed)
		enemy.health_changed.connect(_on_enemy_health_changed)
		(_enemy_nodes_by_room[room.room_id] as Array).append(enemy)
		spawned_count += 1
		var room_visible := room.is_streamed()
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


func _repair_room_progress(room: DungeonRoom3D) -> void:
	if room == null or room.cleared:
		return
	if room.room_type in HOSTILE_ROOM_TYPES:
		_repair_hostile_room_progress(room)
		return
	if room.room_type != "EVENT":
		return
	if not _resolved_event_rooms.has(room.room_id):
		_ensure_event_room_objective(room)
		return
	if _event_combat_rooms.has(room.room_id):
		_repair_hostile_room_progress(room, true)
		return
	# 非战斗事件一经记录为已结算就不应继续锁门；这是热重载/旧存档兜底。
	_mark_room_cleared(room, true)


func _return_room_status(room: DungeonRoom3D) -> String:
	if room == null:
		return "返回已探索房间"
	if room.cleared:
		return "返回已探索房间 · 已肃清"
	if room.room_type == "EVENT":
		if _event_combat_rooms.has(room.room_id):
			return "返回事件房 · 异常敌群尚未肃清"
		return "返回事件房 · 前往紫色光柱，按 E 结算事件"
	return "返回已探索房间 · 战斗未结束"


func _ensure_event_room_objective(room: DungeonRoom3D) -> bool:
	if room == null or room.room_type != "EVENT":
		return false
	var station := room.ensure_required_service_station()
	if station != null:
		return true
	# 必做交互物实例化失败时，优先保住流程，绝不让一局永久卡死。
	push_error("Event room %s has no event station; unlocking room to prevent a soft lock" % room.room_id)
	_resolved_event_rooms[room.room_id] = true
	_mark_room_cleared(room, true)
	status_label.text = "事件终端载入失败，房间已安全解锁"
	return false


func _repair_hostile_room_progress(room: DungeonRoom3D, allow_event_combat := false) -> void:
	if (
		room == null
		or room.cleared
		or (room.room_type not in HOSTILE_ROOM_TYPES and not allow_event_combat)
	):
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
	if AudioManager != null:
		AudioManager.play_sfx("wave_start", -3.0)


func _record_index(room_id: String) -> int:
	var record := _find_record(room_id)
	return int(record.get("index", 0))


func _on_summon_requested(source: Enemy3D, count: int) -> void:
	if not _alive_by_room.has(source.room_id):
		return
	if source.ai_state == "dead" and source.elite_modifier_id != "Elite.SpawnOnDeath":
		return
	var live_count := 0
	for value in _enemy_nodes_by_room.get(source.room_id, []):
		if is_instance_valid(value) and value is Enemy3D and (value as Enemy3D).ai_state != "dead":
			live_count += 1
	var reserved_count := mini(mini(3, count), maxi(0, 8 - live_count))
	if reserved_count <= 0:
		return
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
			var spawn_data := minion_data[index % minion_data.size()].duplicate(true)
			spawn_data["spawn_index"] = index
			spawn_data["persistent_id"] = "%s:summon_%d:%d" % [room_id, Time.get_ticks_msec(), index]
			enemy.configure_from_enemy_data(spawn_data)
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
	# 房间试炼先写进掉落物；全局黄金潮汐在真正拾取/结算魂时统一应用，避免重复倍率。
	var currency_multiplier := float(_room_currency_multipliers.get(enemy.room_id, 1.0))
	for item in drops:
		if bool(item.get("is_currency", false)) or str(item.get("id", "")) == "__currency__":
			item["count"] = maxi(1, int(round(float(item.get("count", 1)) * currency_multiplier)))
	if enemy.enemy_kind in ["elite", "boss"] and player.has_method("on_fate_elite_killed"):
		player.call("on_fate_elite_killed")
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
	if AudioManager != null:
		AudioManager.play_sfx("wave_clear", -3.0)
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
		if AudioManager != null:
			AudioManager.play_sfx("boss_defeat", -1.0)
		status_label.text = "Boss 已清除 · 撤离信标已解锁"
	if bool(enemy_data.get("is_elite", false)) and room != null:
		call_deferred("_ensure_conditional_extraction", "ELITE_KILL", room, Vector3(4.0, 0.0, 3.0))
	_refresh_loot_label()


func _on_boss_phase_changed(enemy: Enemy3D, phase: int) -> void:
	if enemy == _active_boss and _boss_label != null:
		_boss_label.text = "%s · 阶段 %d" % [enemy.get_enemy_data().get("name", "废土首领"), phase]
	status_label.text = "Boss 阶段 %d · 攻击节奏与增援强度提升" % phase
	if AudioManager != null:
		AudioManager.play_sfx("boss_phase", -2.0)


func _on_enemy_health_changed(enemy: Enemy3D, current: int, maximum: int) -> void:
	if enemy != _active_boss or _boss_bar == null:
		return
	_boss_bar.max_value = maxi(1, maximum)
	_boss_bar.value = current


func _show_boss_hud(enemy: Enemy3D) -> void:
	var is_new_boss := enemy != _active_boss
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
	if is_new_boss and AudioManager != null:
		AudioManager.play_sfx("boss_intro", -1.5)
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
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(
			loot_hint.get("sound_position", room.global_position) as Vector3,
			8.0,
			"container_open",
			player
		)
	if _map_fate_triggers != null:
		_map_fate_triggers.on_container_opened(str(loot_hint.get("size_class", "crate")))
	var size_class := str(loot_hint.get("size_class", "medium"))
	var container_type := "crate" if size_class == "small" else "locker" if size_class == "medium" else "hidden_cache"
	var drops := _loot_module.generate_container_loot(container_type, maxi(1, visual_theme.difficulty_rank))
	if _next_chest_quality_boost > 0:
		var boosted := _loot_module.generate_container_loot("hidden_cache", maxi(1, visual_theme.difficulty_rank + _next_chest_quality_boost))
		if not boosted.is_empty():
			drops = [boosted[0]]
		_next_chest_quality_boost = 0
	if _extra_loot_next_chest_count > 0:
		var candidates: Array[Dictionary] = []
		candidates.append_array(drops)
		for _extra_index in range(_extra_loot_next_chest_count):
			var extra := _loot_module.generate_container_loot(container_type, maxi(1, visual_theme.difficulty_rank))
			if not extra.is_empty():
				candidates.append(extra[0])
		if not candidates.is_empty():
			candidates.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return int(a.get("loot_table_tier", 0)) > int(b.get("loot_table_tier", 0))
			)
			drops = [candidates[0]]
		_extra_loot_next_chest_count = 0
	if drops.is_empty():
		status_label.text = "容器为空"
		return
	var single_drop := drops[0].duplicate(true)
	single_drop["count"] = 1
	_spawn_loot_items(room, [single_drop], player.global_position + player.aim_direction * 1.2)
	status_label.text = "搜索完成 · 1 件物资落地"


func _spawn_loot_items(room: DungeonRoom3D, items: Array[Dictionary], world_position: Vector3) -> void:
	for index in range(items.size()):
		var item := items[index].duplicate(true)
		if not bool(item.get("is_currency", false)):
			item["count"] = 1
		var pickup := GROUND_LOOT_SCRIPT.new() as GroundLootPickup3D
		var color := ItemModelFactory3D.get_item_color(item)
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
		var granted := _grant_run_currency(int(item.get("count", 1)))
		if _map_fate_triggers != null:
			_map_fate_triggers.on_currency_collected(granted)
		pickup.accept_pickup()
		status_label.text = "取得 %d 魂" % granted
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


func _grant_run_currency(amount: int) -> int:
	var granted := maxi(0, int(round(float(maxi(0, amount)) * _world_currency_multiplier)))
	if granted > 0:
		GameManager.add_currency(granted)
	return granted


func _drop_inventory_item_to_world(item: Dictionary, count: int) -> bool:
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null or player == null or item.is_empty():
		return false
	var dropped := item.duplicate(true)
	dropped["count"] = maxi(1, count)
	_spawn_loot_items(
		room,
		[dropped],
		player.global_position + player.aim_direction * 1.55 + Vector3(0.0, 0.08, 0.0)
	)
	var identity := ""
	if str(dropped.get("type", "")) == "weapon":
		identity = " #%s" % str(dropped.get("weapon_instance_id", "")).right(6).to_upper()
	status_label.text = "已丢弃 %s%s x%d · 完整物品留在当前房间" % [
		dropped.get("name", dropped.get("id", "物品")), identity, maxi(1, count),
	]
	return true


func _get_minimap_enemy_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var live_enemies: Array = []
	for value in _enemy_nodes_by_room.get(_current_room_id, []):
		# 已释放对象不能先做类型转换；先验证实例，避免 Godot 的 freed-object cast 报错。
		if value == null or not is_instance_valid(value):
			continue
		var enemy := value as Enemy3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if enemy.current_hp <= 0:
			continue
		live_enemies.append(enemy)
		result.append(enemy.global_position)
	_enemy_nodes_by_room[_current_room_id] = live_enemies
	return result


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
	status_label.text = "改造台：7 远程 + 2 近战 · 8 弹药，使用同一装配树"


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
	_queue_runtime_autosave("currency_changed")


func _resolve_event_room(room: DungeonRoom3D) -> void:
	if room == null or _resolved_event_rooms.has(room.room_id):
		status_label.text = "本房事件已经结算"
		return
	_resolved_event_rooms[room.room_id] = true
	var event_station := room.get_service_station("event")
	if event_station != null:
		event_station.set_objective_resolved()
	var event_id: String = ["CURSE", "BLESSING", "TRADE", "GAMBLE", "REVEAL", "SUMMON"][_rng.randi_range(0, 5)]
	match event_id:
		"CURSE":
			room.cleared = false
			_event_combat_rooms[room.room_id] = true
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
				var granted := _grant_run_currency(reward)
				status_label.text = "命运交易完成：获得 %d 魂" % granted
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
					var granted := _grant_run_currency(bet * multiplier)
					status_label.text = "赌局胜利：投入 %d，获得 %d 魂" % [bet, granted]
				else:
					status_label.text = "赌局失败：损失 %d 魂" % bet
		"REVEAL":
			_reveal_nearby_rooms(room.room_id, 2)
			status_label.text = "地图揭示：周围房间类型已标记"
		"SUMMON":
			room.cleared = false
			_event_combat_rooms[room.room_id] = true
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
	_extra_loot_next_chest_count = maxi(_extra_loot_next_chest_count, 1 if enabled else 0)


func _on_fate_scope_state_changed(scope: String, stable_card_id: String) -> void:
	if scope != FateCard.scope_name(FateCard.Scope.WORLD):
		return
	var card := FateCardGameBridge.get_latest_applied_card(stable_card_id)
	if card == null:
		card = FateCardPresets.get_by_card_id(stable_card_id)
	if card == null:
		return
	var modifier := str(card.effect.get("modifier", ""))
	match modifier:
		"next_chest_quality":
			_next_chest_quality_boost += maxi(0, int(card.effect.get("tiers", 1)))
		"next_chest_extra":
			_extra_loot_next_chest_count += maxi(0, int(card.effect.get("count", 1)))
		"next_room_enemy_count":
			_next_room_enemy_count += maxi(0, int(card.effect.get("count", 0)))
		"reveal_rooms":
			_reveal_nearby_rooms(_current_room_id, int(card.effect.get("radius", 1)))
		"grant_room_key":
			_room_key_count += maxi(0, int(card.effect.get("count", 1)))
			_refresh_loot_label()
		"currency_gain":
			_world_currency_multiplier *= maxf(1.0, float(card.effect.get("multiplier", 1.0)))
		"next_room_enemy_hp":
			_next_room_enemy_hp_multiplier *= clampf(float(card.effect.get("multiplier", 1.0)), 0.1, 3.0)
		"next_room_trial":
			_next_room_enemy_damage_multiplier *= maxf(1.0, float(card.effect.get("damage_multiplier", 1.0)))
			_next_room_currency_multiplier *= maxf(1.0, float(card.effect.get("currency_multiplier", 1.0)))
		"room_clear_bounty":
			_room_clear_bounty_rooms += maxi(0, int(card.effect.get("rooms", 0)))
			_room_clear_bounty_amount = maxi(_room_clear_bounty_amount, int(card.effect.get("amount", 0)))
		"extraction_time":
			var multiplier := clampf(float(card.effect.get("multiplier", 1.0)), 0.1, 1.0)
			_extraction_time_multiplier *= multiplier
			for beacon_value in get_tree().get_nodes_in_group("extraction_beacon_3d"):
				var beacon := beacon_value as ExtractionBeacon3D
				if beacon != null and is_instance_valid(beacon):
					beacon.duration *= multiplier
		_:
			return


func get_world_fate_snapshot() -> Dictionary:
	return {
		"next_chest_quality": _next_chest_quality_boost,
		"next_chest_extra": _extra_loot_next_chest_count,
		"next_room_enemy_count": _next_room_enemy_count,
		"next_room_enemy_hp_multiplier": _next_room_enemy_hp_multiplier,
		"next_room_enemy_damage_multiplier": _next_room_enemy_damage_multiplier,
		"next_room_currency_multiplier": _next_room_currency_multiplier,
		"currency_multiplier": _world_currency_multiplier,
		"bounty_rooms": _room_clear_bounty_rooms,
		"bounty_amount": _room_clear_bounty_amount,
		"extraction_time_multiplier": _extraction_time_multiplier,
	}


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
	if not was_cleared and room.room_type in HOSTILE_ROOM_TYPES and _room_clear_bounty_rooms > 0:
		_grant_run_currency(_room_clear_bounty_amount)
		_room_clear_bounty_rooms -= 1
		_refresh_loot_label()
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
	_repair_room_progress(current)
	if bool(policy.get("requires_clear", true)) and not current.cleared:
		if current.room_type == "EVENT":
			status_label.text = (
				"先清除事件召唤的敌群，才能开启房门"
				if _event_combat_rooms.has(current.room_id)
				else "先前往紫色光柱，按 E 结算房间事件"
			)
		else:
			status_label.text = "先清理当前房间，才能开启房门"
		return false
	var requires_key := bool(policy.get("requires_key", true))
	if requires_key and _get_total_room_keys() <= 0:
		status_label.text = "需要房间钥匙"
		return false
	if requires_key:
		_consume_room_key()
	_open_edges[edge] = true
	if MonsterAIManager != null and player != null:
		MonsterAIManager.broadcast_sound_stimulus(player.global_position, 6.5, "door_open", player)
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
	var offer := FateCardPresets.draw_offer(3, _rng)
	if offer.is_empty():
		return
	_door_fate_choices.clear()
	_pending_fate_currency_choice = -1
	_door_fate_choices.assign(offer)
	_door_fate_active = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	_build_door_fate_overlay()
	status_label.text = "门已开启 · 选择命运卡片后继续行动"


func _build_door_fate_overlay() -> void:
	_fate_overlay = Control.new()
	_fate_overlay.name = "DoorFateOverlay3D"
	_fate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_fate_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_fate_overlay.z_index = 900
	$HUD.add_child(_fate_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.002, 0.008, 0.016, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.add_child(dim)

	var protocol := _make_hud_label("FATE PROTOCOL / SELECT ONE", 13, Color(0.38, 0.74, 0.86))
	protocol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(protocol, 0.5, 0.0, 0.5, 0.0, -320, 42, 320, 64)
	_fate_overlay.add_child(protocol)
	var title := Label.new()
	title.text = "《  命 运 卡 三 选 一  》"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _hud_int(40))
	title.add_theme_color_override("font_color", Color(0.46, 0.94, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.48, 0.70, 0.70))
	title.add_theme_constant_override("outline_size", _hud_int(7))
	_anchor_control(title, 0.5, 0.0, 0.5, 0.0, -470, 32, 470, 90)
	_fate_overlay.add_child(title)

	# 三张卡是本弹窗的主体，占据标题与信息条之间的全部纵向空间。
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _hud_int(64))
	_anchor_control(row, 0.5, 0.0, 0.5, 0.0, -570, 134, 570, 706)
	_fate_overlay.add_child(row)
	for choice_index in range(_door_fate_choices.size()):
		var card := _door_fate_choices[choice_index]
		var card_button := _create_reference_fate_card(card, choice_index)
		row.add_child(card_button)
		_play_reference_tarot_flip(card_button, card, choice_index)

	var info_panel := _make_hud_panel(Color(0.23, 0.88, 1.0), Color(0.006, 0.036, 0.055, 0.94))
	_anchor_control(info_panel, 0.5, 0.0, 0.5, 0.0, -380, 730, 380, 806)
	_fate_overlay.add_child(info_panel)
	_add_neon_frame(info_panel, Color(0.23, 0.88, 1.0), 0.52, false)
	var info_margin := _make_margin(20, 10, 20, 10)
	info_panel.add_child(info_margin)
	_fate_feedback_label = _make_hud_label(
		"当前信息\n请选择一张命运卡强化本次行动 · ESC 可放弃本次选择",
		15,
		Color(0.72, 0.91, 0.98),
	)
	_fate_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fate_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_margin.add_child(_fate_feedback_label)


func _create_reference_fate_card(card: FateCard, choice_index: int) -> Button:
	var accent := FateCard.scope_color(card.scope)
	var button := Button.new()
	button.name = "FateChoiceCard_%d" % choice_index
	button.custom_minimum_size = _hud_size(Vector2(350, 552))
	button.text = ""
	button.clip_contents = false
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s · %s\n%s" % [card.card_name, card.orientation_name(), card.description]
	button.disabled = true
	button.set_meta("tarot_face_ready", false)
	button.set_meta("tarot_orientation", card.orientation_name())
	var normal := _make_hud_style(Color(accent, 0.82), Color(0.008, 0.014, 0.034, 0.97), 2)
	normal.set_corner_radius_all(8)
	normal.shadow_color = Color(accent, 0.36)
	normal.shadow_size = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.018, 0.028, 0.060, 0.99)
	hover.border_color = accent.lightened(0.20)
	hover.set_border_width_all(3)
	hover.shadow_color = Color(accent, 0.66)
	hover.shadow_size = 16
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.18)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)

	var margin := _make_margin(22, 20, 22, 20)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.name = "TarotFaceText"
	margin.visible = false
	button.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", _hud_int(8))
	margin.add_child(vbox)
	var scope_label := _make_hud_label(FateCard.scope_display_name(card.scope), 20, accent)
	scope_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(scope_label)
	var ornament_holder := Control.new()
	ornament_holder.custom_minimum_size = _hud_size(Vector2(0, 112))
	ornament_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(ornament_holder)
	var ornament := Control.new()
	ornament.name = "TarotOrientationOrnament"
	ornament.set_anchors_preset(Control.PRESET_FULL_RECT)
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament_holder.add_child(ornament)
	var symbol := _make_hud_label(FateCard.scope_symbol(card.scope), 88, accent.lightened(0.10))
	symbol.set_anchors_preset(Control.PRESET_FULL_RECT)
	symbol.custom_minimum_size = _hud_size(Vector2(0, 104))
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.add_child(symbol)
	var direction_mark := _make_hud_label("▲", 14, Color(accent, 0.82))
	direction_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(direction_mark, 0.5, 0.0, 0.5, 0.0, -24, 0, 24, 20)
	ornament.add_child(direction_mark)
	var card_name := _make_hud_label(card.card_name, 28, Color(0.94, 0.96, 1.0))
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(card_name)
	var orientation_label := _make_hud_label(
		"%s %s" % [card.orientation_symbol(), card.orientation_name()],
		18,
		Color(1.0, 0.72, 0.34) if card.is_reversed() else Color(0.62, 0.94, 1.0),
	)
	orientation_label.name = "TarotOrientationLabel"
	orientation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(orientation_label)
	var rarity := _make_hud_label(
		"%s · %s" % [FateCard.rarity_name(card.card_rarity), FateCard.type_name(card.card_type)],
		17,
		_rarity_color(card.card_rarity),
	)
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", _hud_int(2))
	vbox.add_child(rule)
	var target := _make_hud_label(_get_fate_target_preview(card), 16, Color(0.62, 0.84, 0.92))
	target.custom_minimum_size = _hud_size(Vector2(288, 50))
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(target)
	var effect_text := card.short_description if not card.short_description.is_empty() else card.description
	var effect := _make_hud_label(effect_text, 19, Color(0.91, 0.93, 0.96))
	effect.custom_minimum_size = _hud_size(Vector2(288, 80))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(effect)
	var footer_text := "本局生效 · 不占枪槽"
	if card.scope == FateCard.Scope.WEAPON:
		footer_text = (
			"命运槽已满 · 再次点击兑魂"
			if _is_weapon_fate_target_full(card)
			else "永久刻印 · 不可逆"
		)
	var footer := _make_hud_label(
		footer_text,
		15,
		Color(accent, 0.86),
	)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)
	_add_neon_frame(button, accent, 1.0, true)
	var back := Panel.new()
	back.name = "TarotCardBack"
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back_style := _make_hud_style(Color(accent, 0.92), Color(0.006, 0.012, 0.030, 0.99), 3)
	back_style.set_corner_radius_all(8)
	back.add_theme_stylebox_override("panel", back_style)
	button.add_child(back)
	var back_glyph := _make_hud_label("✦\n命运塔罗\nFATE", 30, Color(accent, 0.92))
	back_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	back_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(back_glyph)
	button.move_child(back, button.get_child_count() - 1)
	button.set_meta("tarot_face_node", margin)
	button.set_meta("tarot_back_node", back)
	button.resized.connect(_center_control_pivot.bind(button))
	button.mouse_entered.connect(_on_reference_fate_card_hover.bind(button, true))
	button.mouse_exited.connect(_on_reference_fate_card_hover.bind(button, false))
	button.pressed.connect(_on_door_fate_selected.bind(choice_index))
	return button


func _play_reference_tarot_flip(button: Button, card: FateCard, choice_index: int) -> void:
	if button == null:
		return
	button.scale = Vector2.ONE
	button.pivot_offset = button.size * 0.5
	var face := button.get_meta("tarot_face_node") as Control
	var back := button.get_meta("tarot_back_node") as Control
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if reduce_motion:
		button.rotation = PI if card.is_reversed() else 0.0
		if back != null:
			back.visible = false
		if face != null:
			face.visible = true
		button.modulate.a = 0.0
		tween.tween_property(button, "modulate:a", 1.0, 0.15)
	else:
		tween.tween_interval(0.10 + float(choice_index) * 0.08)
		tween.tween_property(button, "scale:x", 0.04, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_reveal_reference_tarot_face.bind(button, face, back, card.is_reversed()))
		tween.tween_property(button, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_reference_tarot_flip.bind(button, card))


func _reveal_reference_tarot_face(button: Control, face: Control, back: Control, is_reversed: bool) -> void:
	# 逆位是整张实体卡面旋转180°：边框、名称、天体、数值和说明共同倒置。
	# 描述内容已由 FateCard 的逆位效果快照替换，不再保留独立正向文字层。
	if button != null and is_instance_valid(button):
		button.rotation = PI if is_reversed else 0.0
	if back != null and is_instance_valid(back):
		back.visible = false
	if face != null and is_instance_valid(face):
		face.visible = true


func _finish_reference_tarot_flip(button: Button, card: FateCard) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.disabled = false
	button.set_meta("tarot_face_ready", true)
	button.set_meta("tarot_orientation", card.orientation_name())
	button.set_meta("tarot_face_rotation", button.rotation)


func _get_fate_target_preview(card: FateCard) -> String:
	if card.scope != FateCard.Scope.WEAPON:
		return FateCard.scope_target_text(card.scope)
	var target := FateCardGameBridge.get_target_summary(card)
	var used := int(target.get("fate_slot_used", 0))
	var capacity := int(target.get("fate_slot_capacity", 0))
	if capacity > 0 and used >= capacity:
		return "当前枪 #%s\n命运槽已满 %d / %d · 可兑魂%d" % [
			target.get("instance_suffix", str(target.get("weapon_instance_id", "")).right(6).to_upper()),
			used, capacity, _fate_currency_value(card),
		]
	return "当前枪 #%s\n下一槽 %d / %d" % [
		target.get("instance_suffix", str(target.get("weapon_instance_id", "")).right(6).to_upper()),
		mini(used + 1, capacity),
		capacity,
	]


func _center_control_pivot(control: Control) -> void:
	control.pivot_offset = control.size * 0.5


func _on_reference_fate_card_hover(control: Control, hovered: bool) -> void:
	if control == null or not is_instance_valid(control):
		return
	var tween := control.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * (1.025 if hovered else 1.0), 0.12)


func _rarity_color(rarity: FateCard.CardRarity) -> Color:
	match rarity:
		FateCard.CardRarity.COMMON: return Color(0.76, 0.82, 0.88)
		FateCard.CardRarity.RARE: return Color(0.24, 0.72, 1.0)
		FateCard.CardRarity.EPIC: return Color(0.78, 0.36, 1.0)
		FateCard.CardRarity.LEGENDARY: return Color(1.0, 0.70, 0.22)
		FateCard.CardRarity.MYSTIC: return Color(1.0, 0.22, 0.28)
	return Color.WHITE


func _get_fate_choice_text(card: FateCard) -> String:
	var target_text := FateCard.scope_target_text(card.scope)
	if card.scope == FateCard.Scope.WEAPON:
		var target := FateCardGameBridge.get_target_summary(card)
		var instance_tail := str(target.get("weapon_instance_id", "")).right(6).to_upper()
		var used := int(target.get("fate_slot_used", 0))
		var capacity := int(target.get("fate_slot_capacity", 0))
		target_text = "当前枪 #%s · 下一槽 %d/%d\n永久刻印，不可逆" % [
			instance_tail, mini(used + 1, capacity), capacity,
		]
	return "%s\n[%s · %s] %s\n%s\n\n%s" % [
		FateCard.scope_display_name(card.scope),
		FateCard.rarity_name(card.card_rarity), FateCard.type_name(card.card_type),
		card.card_name, target_text, card.description,
	]


func _on_door_fate_selected(choice_index: int) -> void:
	if not _door_fate_active or choice_index < 0 or choice_index >= _door_fate_choices.size():
		return
	var card := _door_fate_choices[choice_index]
	if _is_weapon_fate_target_full(card):
		var currency_value := _fate_currency_value(card)
		if _pending_fate_currency_choice != choice_index:
			_pending_fate_currency_choice = choice_index
			status_label.text = "%s：命运槽已满，再次点击转换为%d魂" % [card.card_name, currency_value]
			if _fate_feedback_label != null:
				_fate_feedback_label.text = "转换确认 · %s\n再次点击同一张卡：放弃刻印并获得 %d 魂" % [card.card_name, currency_value]
				_fate_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
			return
		GameManager.add_currency(currency_value)
		_close_door_fate_overlay()
		status_label.text = "命运转化：%s → %d魂" % [card.card_name, currency_value]
		return
	_pending_fate_currency_choice = -1
	var result := FateCardGameBridge.apply_card(card)
	if not bool(result.get("success", false)):
		var failure := str(result.get("reason", result.get("message", "当前目标无法承载该命运")))
		status_label.text = "%s：%s" % [card.card_name, failure]
		if _fate_feedback_label != null:
			_fate_feedback_label.text = "应用失败 · %s\n%s · 请改选其他命运" % [card.card_name, failure]
			_fate_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.40, 0.30))
		return
	_close_door_fate_overlay()
	if AudioManager != null:
		AudioManager.play_fate_card_sfx()
	status_label.text = "命运生效：%s · %s" % [card.card_name, result.get("message", "")]


func _is_weapon_fate_target_full(card: FateCard) -> bool:
	if card == null or card.scope != FateCard.Scope.WEAPON:
		return false
	var target := FateCardGameBridge.get_target_summary(card)
	var capacity := int(target.get("fate_slot_capacity", 0))
	return capacity > 0 and int(target.get("fate_slot_used", 0)) >= capacity


func _fate_currency_value(card: FateCard) -> int:
	if card == null:
		return 0
	return int(FATE_CURRENCY_BY_RARITY[clampi(int(card.card_rarity), 0, FATE_CURRENCY_BY_RARITY.size() - 1)])


func _close_door_fate_overlay() -> void:
	_door_fate_active = false
	_door_fate_choices.clear()
	_pending_fate_currency_choice = -1
	if _fate_overlay != null and is_instance_valid(_fate_overlay):
		_fate_overlay.queue_free()
	_fate_overlay = null
	_fate_feedback_label = null
	_sync_player_input_lock()


func _cancel_door_fate_selection() -> void:
	if not _door_fate_active:
		return
	_close_door_fate_overlay()
	status_label.text = "已放弃本次命运选择 · 行动继续"


func show_reference_fate_overlay_for_test() -> bool:
	if _door_fate_active:
		return false
	var pool := FateCardPresets.door_reward_presets()
	_door_fate_choices.clear()
	_pending_fate_currency_choice = -1
	for wanted_scope in [FateCard.Scope.WEAPON, FateCard.Scope.WORLD, FateCard.Scope.CHARACTER]:
		for card in pool:
			if card.scope == wanted_scope:
				_door_fate_choices.append(card)
				break
	if _door_fate_choices.size() != 3:
		return false
	_door_fate_choices[0].set_orientation(FateCard.Orientation.UPRIGHT, 0.25)
	_door_fate_choices[1].set_orientation(FateCard.Orientation.REVERSED, 0.75)
	_door_fate_choices[2].set_orientation(FateCard.Orientation.UPRIGHT, 0.25)
	_door_fate_active = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	_build_door_fate_overlay()
	status_label.text = "视觉验收 · 命运卡三选一"
	return true


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
		var state := DungeonRoom3D.STREAM_ACTIVE if room.room_id == current_id else DungeonRoom3D.STREAM_DATA_ONLY
		if state == DungeonRoom3D.STREAM_DATA_ONLY and _room_neighbors.has(current_id) and room.room_id in (_room_neighbors[current_id] as Array):
			if bool(_open_edges.get(_edge_key(current_id, room.room_id), false)):
				state = DungeonRoom3D.STREAM_SHELL_READY
		var previous_state := int(_room_stream_state_cache.get(room.room_id, DungeonRoom3D.STREAM_DATA_ONLY))
		if previous_state != state:
			if state == DungeonRoom3D.STREAM_DATA_ONLY and previous_state != DungeonRoom3D.STREAM_DATA_ONLY:
				_hibernate_room_entities(room.room_id)
			_room_stream_state_cache[room.room_id] = state
		room.set_stream_state(state)
		if state > 0:
			_prepare_revealed_hostile_room(room)
			_restore_room_runtime_state(room.room_id)
	_update_corridor_streaming(current_id)
	for room_id in _enemy_nodes_by_room.keys():
		var live_references: Array = []
		for value in _enemy_nodes_by_room[room_id]:
			if not is_instance_valid(value) or (value as Node).is_queued_for_deletion():
				continue
			var enemy := value as Enemy3D
			if enemy != null and is_instance_valid(enemy):
				live_references.append(enemy)
				var enemy_room := _room_by_id.get(str(room_id)) as DungeonRoom3D
				var room_visible := (
					enemy_room != null
					and enemy_room.is_streamed()
				)
				enemy.set_runtime_active(str(room_id) == current_id, room_visible)
		_enemy_nodes_by_room[room_id] = live_references


func _hibernate_room_entities(room_id: String) -> void:
	_capture_room_runtime_state(room_id)
	for value in _enemy_nodes_by_room.get(room_id, []):
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if MonsterAIManager != null:
			MonsterAIManager.unregister_enemy(enemy)
		enemy.queue_free()
	_enemy_nodes_by_room[room_id] = []
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null:
		return
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value):
			(value as GroundLootPickup3D).queue_free()
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and room.is_ancestor_of(value):
			(value as RoomKeyPickup3D).queue_free()


func _capture_room_runtime_state(room_id: String) -> void:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return
	var enemy_states: Array[Dictionary] = []
	for value in _enemy_nodes_by_room.get(room_id, []):
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if enemy.ai_state == "dead":
			continue
		enemy_states.append(enemy.export_runtime_state())
	var ground_items: Array[Dictionary] = []
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value):
			var pickup := value as GroundLootPickup3D
			ground_items.append({
				"item_data": pickup.item_data.duplicate(true),
				"position": [pickup.global_position.x, pickup.global_position.y, pickup.global_position.z],
			})
	var room_keys: Array[Dictionary] = []
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
			var key := value as RoomKeyPickup3D
			room_keys.append({
				"room_id": key.room_id,
				"position": [key.global_position.x, key.global_position.y, key.global_position.z],
			})
	var container_states: Dictionary = {}
	for value in get_tree().get_nodes_in_group("room_prop_3d"):
		if value is RoomFurniture3D and room.is_ancestor_of(value):
			var prop := value as RoomFurniture3D
			container_states[prop.prop_id] = prop.is_searched()
	_segment_runtime_state[room_id] = {
		"visited": room.visited,
		"cleared": room.cleared,
		"room_light_on": room.is_room_light_on(),
		"enemies": enemy_states,
		"ground_items": ground_items,
		"room_keys": room_keys,
		"containers": container_states,
		"alive_count": int(_alive_by_room.get(room_id, enemy_states.size())),
		"wave_queue": (_room_wave_queues.get(room_id, []) as Array).duplicate(true),
		"wave_number": int(_room_wave_numbers.get(room_id, 1)),
		"wave_total": int(_room_wave_totals.get(room_id, 1)),
		"captured_at_msec": Time.get_ticks_msec(),
	}


func _restore_room_runtime_state(room_id: String) -> void:
	if not _segment_runtime_state.has(room_id):
		return
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return
	var state := _segment_runtime_state[room_id] as Dictionary
	room.visited = bool(state.get("visited", room.visited))
	room.cleared = bool(state.get("cleared", room.cleared))
	_alive_by_room[room_id] = maxi(0, int(state.get("alive_count", _alive_by_room.get(room_id, 0))))
	_room_wave_queues[room_id] = (state.get("wave_queue", []) as Array).duplicate(true)
	_room_wave_numbers[room_id] = maxi(1, int(state.get("wave_number", 1)))
	_room_wave_totals[room_id] = maxi(1, int(state.get("wave_total", 1)))
	room.apply_runtime_detail_state({
		"room_light_on": bool(state.get("room_light_on", false)),
		"containers": (state.get("containers", {}) as Dictionary).duplicate(true),
	})
	var live_enemies: Array = []
	for value in _enemy_nodes_by_room.get(room_id, []):
		if is_instance_valid(value) and not (value as Node).is_queued_for_deletion() and value is Enemy3D:
			live_enemies.append(value)
			var persistent_id := (value as Enemy3D).get_persistent_id()
			for runtime_value in state.get("enemies", []):
				var enemy_state := runtime_value as Dictionary
				if str(enemy_state.get("persistent_id", "")) == persistent_id:
					(value as Enemy3D).import_runtime_state(enemy_state)
					break
	if live_enemies.is_empty() and not room.cleared:
		for runtime_value in state.get("enemies", []):
			var enemy_state := runtime_value as Dictionary
			var enemy_data := (enemy_state.get("enemy_data", {}) as Dictionary).duplicate(true)
			if enemy_data.is_empty():
				enemy_data = {
					"enemy_type": str(enemy_state.get("enemy_kind", "melee_chaser")),
					"persistent_id": str(enemy_state.get("persistent_id", "")),
					"floor": maxi(1, visual_theme.difficulty_rank),
				}
			var enemy := ENEMY_SCENE.instantiate() as Enemy3D
			if enemy == null:
				continue
			enemy.room_id = room_id
			$ActiveEnemies.add_child(enemy)
			enemy.configure_from_enemy_data(enemy_data)
			enemy.killed.connect(_on_enemy_killed)
			enemy.summon_requested.connect(_on_summon_requested)
			enemy.boss_phase_changed.connect(_on_boss_phase_changed)
			enemy.health_changed.connect(_on_enemy_health_changed)
			enemy.import_runtime_state(enemy_state)
			live_enemies.append(enemy)
			if enemy.enemy_kind == "boss":
				_show_boss_hud(enemy)
	_enemy_nodes_by_room[room_id] = live_enemies
	# 地面掉落只在当前 ACTIVE 房创建；邻房安全壳不承担可拾取物和预览模型成本。
	if room_id != _current_room_id:
		return
	var has_live_ground_item := false
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
			has_live_ground_item = true
			break
	if not has_live_ground_item:
		for runtime_value in state.get("ground_items", []):
			var item_state := runtime_value as Dictionary
			var item_data := (item_state.get("item_data", {}) as Dictionary).duplicate(true)
			if item_data.is_empty():
				continue
			var pickup := GROUND_LOOT_SCRIPT.new() as GroundLootPickup3D
			pickup.configure(item_data, ItemModelFactory3D.get_item_color(item_data))
			room.add_child(pickup)
			var saved_position: Variant = item_state.get("position", room.global_position)
			if saved_position is Vector3:
				pickup.global_position = saved_position as Vector3
			elif saved_position is Array and (saved_position as Array).size() >= 3:
				pickup.global_position = Vector3(
					float((saved_position as Array)[0]),
					float((saved_position as Array)[1]),
					float((saved_position as Array)[2])
				)
			pickup.pickup_requested.connect(_on_ground_loot_requested)
	var has_live_room_key := false
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
			has_live_room_key = true
			break
	if not has_live_room_key:
		for runtime_value in state.get("room_keys", []):
			var key_state := runtime_value as Dictionary
			var key := KEY_SCRIPT.new() as RoomKeyPickup3D
			key.configure(str(key_state.get("room_id", room_id)))
			room.add_child(key)
			var saved_position: Variant = key_state.get("position", room.global_position)
			if saved_position is Array and (saved_position as Array).size() >= 3:
				key.global_position = Vector3(
					float((saved_position as Array)[0]),
					float((saved_position as Array)[1]),
					float((saved_position as Array)[2])
				)
			key.collected.connect(_on_room_key_collected)
			_spawned_key_rooms[room_id] = true


func get_segment_runtime_snapshot() -> Dictionary:
	_capture_loaded_runtime_rooms()
	return {
		"schema": "segment_runtime_state_v2",
		"current_room_id": _current_room_id,
		"room_count": _segment_runtime_state.size(),
		"rooms": _segment_runtime_state.duplicate(true),
		"stream_states": _room_stream_state_cache.duplicate(),
	}


func _capture_loaded_runtime_rooms() -> void:
	# 当前房及已预刷邻房都必须进快照。否则重启后会留下 spawned=true、
	# 但没有可恢复敌人的锁房。
	for room in _rooms:
		if room == null or room.get_stream_state() == DungeonRoom3D.STREAM_DATA_ONLY:
			continue
		if (
			room.room_id == _current_room_id
			or _spawned_rooms.has(room.room_id)
			or _segment_runtime_state.has(room.room_id)
		):
			_capture_room_runtime_state(room.room_id)


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
	var count := maxi(1, int(item.get("count", 1)))
	var inventory_before := _inventory.get_slots_snapshot()
	if _inventory.add_item(item, count) != count:
		_inventory.restore_slots_snapshot(inventory_before)
		_insurance.insure_item_direct(item)
		status_label.text = "背包已满，保险物品未取出"


func _on_insurance_item_move_requested(
	insurance_slot_index: int, target_index: int, target_kind: String
) -> void:
	# 保险是“当前所在集合享受离场保留”，不是物品锁。转出采用背包与
	# 保险双快照；目标操作失败时恢复两个集合，避免丢失或复制。
	var inventory_before := _inventory.get_slots_snapshot()
	var insurance_before := _insurance.get_slots_snapshot()
	var item := _insurance.claim_item(insurance_slot_index)
	if item.is_empty():
		return
	var count := maxi(1, int(item.get("count", 1)))
	var moved := false
	match target_kind:
		"inventory":
			moved = _inventory.put_item_in_empty_slot(target_index, item, count)
		"drop":
			moved = _drop_inventory_item_to_world(item, count)
		"quick_0", "quick_1":
			moved = _inventory.add_item(item, count) == count
			if moved:
				_on_quick_item_assignment_requested(int(target_kind.trim_prefix("quick_")), str(item.get("id", "")))
		"weapon_0", "weapon_1", "backpack":
			var staging_slot := _find_empty_inventory_slot()
			if staging_slot >= 0 and _inventory.put_item_in_empty_slot(staging_slot, item, count):
				moved = (
					_equip_weapon_from_inventory(staging_slot, item, int(target_kind.trim_prefix("weapon_")))
					if target_kind.begins_with("weapon_")
					else _equip_backpack_from_inventory(staging_slot, item)
				)
		_ when target_kind.begins_with("attachment_"):
			var staging_slot := _find_empty_inventory_slot()
			var parts := target_kind.split("_")
			if staging_slot >= 0 and parts.size() >= 3 and _inventory.put_item_in_empty_slot(staging_slot, item, count):
				moved = _install_attachment_from_inventory(
					staging_slot, item, int(parts[1]), int(parts[2])
				)
	if moved:
		return
	_inventory.restore_slots_snapshot(inventory_before)
	_insurance.restore_slots_snapshot(insurance_before)
	status_label.text = "移动失败，物品仍保留在保险格"


func _find_empty_inventory_slot() -> int:
	for index in _inventory.get_capacity():
		if _inventory.get_slot(index).is_empty():
			return index
	return -1


func _on_inventory_item_clicked(slot_index: int, _item_hint: Dictionary) -> void:
	var slot := _inventory.get_slot(slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	if item.get("type", "") == "weapon":
		_equip_weapon_from_inventory(slot_index, item)
		return
	if str(item.get("type", "")) == "equipment" and str(item.get("subtype", "")) == "backpack":
		_equip_backpack_from_inventory(slot_index, item)
		return
	if str(item.get("subtype", "")) == "flashlight_module":
		var flashlight_handler := ItemUseHandler.new()
		var flashlight_applied := flashlight_handler.apply(item, {"player": player, "extraction_director": self})
		flashlight_handler.free()
		if flashlight_applied:
			_inventory.remove_from_slot(slot_index, 1)
			status_label.text = "已安装%s" % item.get("name", "手电筒模块")
		else:
			status_label.text = "%s只能在99F基地安装" % item.get("name", "手电筒模块")
		return
	if item.get("type", "") == "attachment":
		_install_attachment_from_inventory(slot_index, item, player.get_active_weapon_slot(), _slot_type_for_item(item))
		return
	if item.get("type", "") == "module":
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


func _on_weapon_slot_equip_requested(source_slot_index: int, weapon_slot_index: int) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	if str(item.get("type", "")) != "weapon":
		status_label.text = "只能把枪械拖入主/副武器栏"
		return
	_equip_weapon_from_inventory(source_slot_index, item, weapon_slot_index)


func _on_attachment_slot_install_requested(
	source_slot_index: int, weapon_slot_index: int, attachment_slot_type: int
) -> void:
	var source := _inventory.get_slot(source_slot_index)
	if source.is_empty():
		return
	_install_attachment_from_inventory(
		source_slot_index,
		source.get("item", {}) as Dictionary,
		weapon_slot_index,
		attachment_slot_type
	)


func _on_attachment_slot_remove_requested(
	weapon_slot_index: int, attachment_slot_type: int, target_slot_index: int
) -> void:
	_remove_attachment_to_inventory(weapon_slot_index, attachment_slot_type, target_slot_index)


func get_equipped_backpack_item() -> Dictionary:
	return player.get_equipped_backpack_item() if player != null and player.has_method("get_equipped_backpack_item") else {}


func get_backpack_equipment_snapshot() -> Dictionary:
	var snapshot := player.get_backpack_equipment_snapshot() if player != null and player.has_method("get_backpack_equipment_snapshot") else {}
	snapshot["base_capacity"] = BASE_INVENTORY_CAPACITY
	snapshot["inventory_capacity"] = _inventory.get_capacity() if _inventory != null else BASE_INVENTORY_CAPACITY
	return snapshot


func _on_backpack_slot_equip_requested(source_slot_index: int) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	_equip_backpack_from_inventory(source_slot_index, slot.get("item", {}) as Dictionary)


func _equip_backpack_from_inventory(slot_index: int, item: Dictionary) -> bool:
	if player == null or not player.has_method("equip_backpack_item"):
		return false
	if str(item.get("type", "")) != "equipment" or str(item.get("subtype", "")) != "backpack":
		status_label.text = "只能把背包装备拖入背包栏"
		return false
	var target_capacity := BASE_INVENTORY_CAPACITY + int(item.get("extra_slots", 0))
	var old_item := get_equipped_backpack_item()
	var predicted_used := _inventory.get_used_slots() - 1 + (0 if old_item.is_empty() else 1)
	if predicted_used > target_capacity and not _can_spawn_overflow_in_current_room():
		status_label.text = "更换背包失败：当前房间无法生成溢出物"
		return false
	if not _inventory.remove_from_slot(slot_index, 1):
		return false
	var equip_result := player.call("equip_backpack_item", item) as Dictionary
	if not bool(equip_result.get("success", false)):
		_inventory.put_item_in_empty_slot(slot_index, item, 1)
		status_label.text = str(equip_result.get("reason", "背包装备失败"))
		return false
	if not old_item.is_empty() and not _inventory.put_item_in_empty_slot(slot_index, old_item, 1):
		player.call("equip_backpack_item", old_item)
		_inventory.put_item_in_empty_slot(slot_index, item, 1)
		status_label.text = "更换背包失败：旧背包无法返回来源格，已回滚"
		return false
	var overflow := _inventory.resize_capacity_collect_overflow(target_capacity)
	_drop_backpack_capacity_overflow(overflow)
	_emit_backpack_equipment_changed()
	status_label.text = "已装备%s · 背包容量%d格%s" % [
		item.get("name", "背包"), target_capacity,
		" · %d格物品已落地" % overflow.size() if not overflow.is_empty() else "",
	]
	return true


func _on_equipped_backpack_to_inventory_requested(target_slot_index: int) -> void:
	if player == null or not player.has_method("unequip_backpack_item"):
		return
	if target_slot_index < 0 or target_slot_index >= BASE_INVENTORY_CAPACITY:
		status_label.text = "卸下背包时请选择基础12格内的空格"
		return
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "卸下背包失败：目标格已有物品"
		return
	var predicted_used := _inventory.get_used_slots() + 1
	if predicted_used > BASE_INVENTORY_CAPACITY and not _can_spawn_overflow_in_current_room():
		status_label.text = "卸下背包失败：当前房间无法生成溢出物"
		return
	var result := player.call("unequip_backpack_item") as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸下背包失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, old_item, 1):
		player.call("equip_backpack_item", old_item)
		status_label.text = "卸下背包失败：目标格写入失败，已回滚"
		return
	var overflow := _inventory.resize_capacity_collect_overflow(BASE_INVENTORY_CAPACITY)
	_drop_backpack_capacity_overflow(overflow)
	_emit_backpack_equipment_changed()
	status_label.text = "已卸下%s%s" % [
		old_item.get("name", "背包"),
		" · %d格物品已落地" % overflow.size() if not overflow.is_empty() else "",
	]


func _on_equipped_backpack_drop_requested() -> void:
	if player == null or not player.has_method("unequip_backpack_item"):
		return
	var current := get_equipped_backpack_item()
	if current.is_empty():
		return
	var predicted_overflow := maxi(0, _inventory.get_used_slots() - BASE_INVENTORY_CAPACITY)
	if predicted_overflow > 0 and not _can_spawn_overflow_in_current_room():
		status_label.text = "丢弃背包失败：当前房间无法生成溢出物"
		return
	var result := player.call("unequip_backpack_item") as Dictionary
	if not bool(result.get("success", false)):
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _drop_inventory_item_to_world(old_item, 1):
		player.call("equip_backpack_item", old_item)
		status_label.text = "丢弃背包失败：已恢复装备"
		return
	var overflow := _inventory.resize_capacity_collect_overflow(BASE_INVENTORY_CAPACITY)
	_drop_backpack_capacity_overflow(overflow)
	_emit_backpack_equipment_changed()
	status_label.text = "已丢弃%s · 容量恢复%d格%s" % [
		old_item.get("name", "背包"), BASE_INVENTORY_CAPACITY,
		" · %d格物品同时落地" % overflow.size() if not overflow.is_empty() else "",
	]


func _can_spawn_overflow_in_current_room() -> bool:
	return player != null and _room_by_id.get(_current_room_id) is DungeonRoom3D


func _drop_backpack_capacity_overflow(overflow: Array[Dictionary]) -> void:
	for entry in overflow:
		var item := entry.get("item", {}) as Dictionary
		var count := int(entry.get("count", 1))
		_drop_inventory_item_to_world(item, count)


func _emit_backpack_equipment_changed() -> void:
	var snapshot := get_backpack_equipment_snapshot()
	backpack_equipment_changed.emit(snapshot)
	_refresh_loot_label()


func _on_quick_item_assignment_requested(quick_slot_index: int, item_id: String) -> void:
	if quick_slot_index < 0 or quick_slot_index >= _quick_item_ids.size():
		return
	var item := ItemRegistry.get_instance().get_item(item_id)
	if item.is_empty() or str(item.get("use_action", "")).is_empty():
		status_label.text = "该物品不能主动使用，无法放入快捷栏"
		return
	_quick_item_ids[quick_slot_index] = item_id
	_inventory_ui.set_quick_item_assignments(_quick_item_ids)
	_refresh_quick_item_hud()
	status_label.text = "已将%s绑定到快捷键%d" % [item.get("name", item_id), quick_slot_index + 3]


func _use_quick_item(quick_slot_index: int) -> bool:
	if quick_slot_index < 0 or quick_slot_index >= _quick_item_ids.size():
		return false
	var item_id := _quick_item_ids[quick_slot_index]
	if item_id.is_empty():
		status_label.text = "快捷栏%d尚未绑定物品" % (quick_slot_index + 3)
		return false
	if _inventory.get_item_count(item_id) <= 0:
		status_label.text = "快捷栏%d物品已用完" % (quick_slot_index + 3)
		return false
	var item := ItemRegistry.get_instance().get_item(item_id)
	var handler := ItemUseHandler.new()
	var applied := handler.apply(item, {"player": player, "extraction_director": self})
	handler.free()
	if not applied:
		status_label.text = "%s当前无法使用" % item.get("name", "物品")
		return false
	_inventory.consume_item(item_id, 1)
	_refresh_quick_item_hud()
	status_label.text = "[%d] 已使用%s" % [quick_slot_index + 3, item.get("name", "物品")]
	return true


func _refresh_quick_item_hud() -> void:
	if _hud_quick_item_icons.size() < 2 or _hud_quick_item_labels.size() < 2:
		return
	for quick_index in range(2):
		var item_id := _quick_item_ids[quick_index]
		var count := _inventory.get_item_count(item_id) if _inventory != null and not item_id.is_empty() else 0
		if item_id.is_empty():
			var empty_icon := _hud_quick_item_icons[quick_index] as ItemModelIcon3D
			if empty_icon != null:
				empty_icon.clear_model()
			_hud_quick_item_labels[quick_index].text = "[%d] 空" % (quick_index + 3)
			continue
		var item := ItemRegistry.get_instance().get_item(item_id)
		var quick_icon := _ensure_hud_quick_item_icon(quick_index)
		if quick_icon != null:
			quick_icon.configure(item)
		_hud_quick_item_labels[quick_index].text = "[%d] %s ×%d" % [
			quick_index + 3, item.get("name", item_id), count,
		]


func _ensure_hud_quick_item_icon(quick_index: int) -> ItemModelIcon3D:
	if quick_index < 0 or quick_index >= _hud_quick_item_icons.size() or quick_index >= _hud_quick_item_icon_hosts.size():
		return null
	var existing := _hud_quick_item_icons[quick_index] as ItemModelIcon3D
	if existing != null and is_instance_valid(existing):
		return existing
	var icon := ITEM_MODEL_ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.name = "QuickItemModelIcon3D_%d" % quick_index
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.set_camera_size_multiplier(0.68)
	_hud_quick_item_icon_hosts[quick_index].add_child(icon)
	_hud_quick_item_icons[quick_index] = icon
	return icon


func _select_weapon_slot(slot_index: int) -> bool:
	if player == null or not player.has_method("switch_weapon_slot"):
		return false
	var result := player.call("switch_weapon_slot", slot_index) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "武器切换失败"))
		return false
	var snapshot := result.get("snapshot", player.get_weapon_presentation_snapshot()) as Dictionary
	status_label.text = "已切换至[%d] %s #%s" % [
		slot_index + 1, snapshot.get("display_name", "武器"), snapshot.get("instance_suffix", "------"),
	]
	return true


func _equip_weapon_from_inventory(slot_index: int, item: Dictionary, target_weapon_slot := -1) -> bool:
	if player == null or not player.has_method("equip_weapon_item"):
		return false
	var incoming := WeaponInstance.ensure_weapon_item(item)
	var incoming_id := str(incoming.get("weapon_instance_id", ""))
	for equipped_slot in range(2):
		if player.has_method("get_equipped_weapon_instance_id_for_slot") and incoming_id == str(player.call("get_equipped_weapon_instance_id_for_slot", equipped_slot)):
			status_label.text = "该枪械实例已在%s #%s" % ["主武器栏" if equipped_slot == 0 else "副武器栏", incoming_id.right(6).to_upper()]
			return false
	if not _inventory.remove_from_slot(slot_index, 1):
		return false
	var equip_result := (
		player.call("equip_weapon_item_to_slot", incoming, target_weapon_slot) as Dictionary
		if target_weapon_slot >= 0 and player.has_method("equip_weapon_item_to_slot")
		else player.call("equip_weapon_item", incoming) as Dictionary
	)
	if not bool(equip_result.get("success", false)):
		_inventory.add_item(incoming, 1)
		status_label.text = str(equip_result.get("message", "换枪失败"))
		return false
	var old_item := equip_result.get("old_item", {}) as Dictionary
	if not old_item.is_empty() and _inventory.add_item(old_item, 1) <= 0:
		# 理论上来源槽已经释放；若仍失败则恢复旧枪，避免完整实例丢失。
		var rollback := (
			player.call("equip_weapon_item_to_slot", old_item, int(equip_result.get("slot_index", target_weapon_slot))) as Dictionary
			if target_weapon_slot >= 0 and player.has_method("equip_weapon_item_to_slot")
			else player.call("equip_weapon_item", old_item) as Dictionary
		)
		if bool(rollback.get("success", false)):
			_inventory.add_item(incoming, 1)
		status_label.text = "换枪失败：原武器无法放回背包，已完整回滚"
		return false
	var snapshot := equip_result.get("snapshot", {}) as Dictionary
	status_label.text = "已装备到%s：%s #%s · 构筑 %d/%d · 原武器完整放回背包" % [
		"当前栏" if target_weapon_slot < 0 else "主武器栏" if target_weapon_slot == 0 else "副武器栏",
		snapshot.get("display_name", item.get("name", "武器")),
		snapshot.get("instance_suffix", "------"),
		snapshot.get("fate_slot_used", 0),
		snapshot.get("fate_slot_capacity", 0),
	]
	return true


func _on_equipped_weapon_to_inventory_requested(weapon_slot_index: int, target_slot_index: int) -> void:
	if player == null or not player.has_method("unequip_weapon_item_from_slot"):
		return
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "卸装失败：目标背包格已有物品"
		return
	var result := player.call("unequip_weapon_item_from_slot", weapon_slot_index) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸装失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, old_item, 1):
		var rollback := player.call("equip_weapon_item_to_slot", old_item, weapon_slot_index) as Dictionary
		status_label.text = (
			"卸装失败：背包写入失败，已恢复原武器"
			if bool(rollback.get("success", false))
			else "卸装事务异常：原武器恢复失败"
		)
		return
	status_label.text = "已卸下 %s #%s · 完整构筑进入背包" % [
		old_item.get("name", "武器"),
		str(old_item.get("weapon_instance_id", "")).right(6).to_upper(),
	]


func _on_equipped_weapon_drop_requested(weapon_slot_index: int) -> void:
	if player == null or not player.has_method("unequip_weapon_item_from_slot"):
		return
	var result := player.call("unequip_weapon_item_from_slot", weapon_slot_index) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸装失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _drop_inventory_item_to_world(old_item, 1):
		var rollback := player.call("equip_weapon_item_to_slot", old_item, weapon_slot_index) as Dictionary
		status_label.text = (
			"丢弃失败：已恢复原武器"
			if bool(rollback.get("success", false))
			else "丢弃事务异常：原武器恢复失败"
		)
		return
	status_label.text = "已卸下并丢弃 %s #%s" % [
		old_item.get("name", "武器"),
		str(old_item.get("weapon_instance_id", "")).right(6).to_upper(),
	]


func _install_attachment_from_inventory(
	source_slot_index: int,
	item: Dictionary,
	weapon_slot_index: int,
	attachment_slot_type: int
) -> bool:
	if player == null or not player.has_method("install_attachment_item_to_weapon_slot"):
		return false
	if str(item.get("type", "")) != "attachment":
		status_label.text = "只能把枪械配件拖入配件槽"
		return false
	var inventory_before := _inventory.get_slots_snapshot()
	if not _inventory.remove_from_slot(source_slot_index, 1):
		return false
	var result := player.call(
		"install_attachment_item_to_weapon_slot", item, weapon_slot_index, attachment_slot_type
	) as Dictionary
	if not bool(result.get("success", false)):
		_inventory.restore_slots_snapshot(inventory_before)
		status_label.text = str(result.get("reason", "配件安装失败"))
		return false
	var removed_item := result.get("removed_item", {}) as Dictionary
	if not removed_item.is_empty() and _inventory.add_item(removed_item, 1) != 1:
		# 背包写入异常时把旧配件重新装回，并精确恢复格位快照。
		player.call(
			"install_attachment_item_to_weapon_slot",
			removed_item,
			weapon_slot_index,
			attachment_slot_type
		)
		_inventory.restore_slots_snapshot(inventory_before)
		status_label.text = "配件交换失败：旧配件无法返回背包，已回滚"
		return false
	status_label.text = "已给%s安装%s%s" % [
		"主武器" if weapon_slot_index == 0 else "副武器",
		item.get("name", "配件"),
		" · 旧配件已回到背包" if not removed_item.is_empty() else "",
	]
	return true


func _remove_attachment_to_inventory(
	weapon_slot_index: int, attachment_slot_type: int, target_slot_index: int = -1
) -> bool:
	if player == null or not player.has_method("remove_attachment_from_weapon_slot"):
		return false
	if target_slot_index >= 0 and not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "拆卸失败：目标背包格已有物品"
		return false
	var result := player.call(
		"remove_attachment_from_weapon_slot", weapon_slot_index, attachment_slot_type
	) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "配件拆卸失败"))
		return false
	var removed_item := result.get("removed_item", {}) as Dictionary
	var stored := (
		_inventory.put_item_in_empty_slot(target_slot_index, removed_item, 1)
		if target_slot_index >= 0
		else _inventory.add_item(removed_item, 1) == 1
	)
	if not stored:
		var rollback := player.call(
			"install_attachment_item_to_weapon_slot",
			removed_item,
			weapon_slot_index,
			attachment_slot_type
		) as Dictionary
		status_label.text = (
			"背包已满，配件已恢复到原枪"
			if bool(rollback.get("success", false))
			else "拆卸事务异常：配件恢复失败"
		)
		return false
	status_label.text = "已从%s拆下%s" % [
		"主武器" if weapon_slot_index == 0 else "副武器",
		removed_item.get("name", AssemblyNode.get_attachment_slot_display_name(attachment_slot_type)),
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
		"scope":
			return AssemblyNode.SlotType.SCOPE
		"stock":
			return AssemblyNode.SlotType.STOCK
		"external":
			return AssemblyNode.SlotType.TACTICAL
		"mutator":
			return AssemblyNode.SlotType.MUTATOR
		_:
			return AssemblyNode.SlotType.MOUNT


func _item_for_weapon_root(root: AssemblyNode) -> Dictionary:
	return BlueprintRegistry.get_item_for_assembly_node(root)


func _item_for_assembly_node(node: AssemblyNode) -> Dictionary:
	return BlueprintRegistry.get_item_for_assembly_node(node)


func _item_id_for_assembly_node(node: AssemblyNode) -> String:
	return BlueprintRegistry.get_item_id_for_assembly_node(node)


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
	_queue_runtime_autosave("health_changed")
	hp_label.text = "%d / %d" % [current, maximum]
	hp_bar.max_value = maxi(1, maximum)
	hp_bar.value = clampi(current, 0, maximum)
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
		status_label.text = "生命信号中断 · 正在确认防护体状态"


func _on_player_debug_scale_changed(snapshot: Dictionary) -> void:
	status_label.text = "角色调试尺寸：%d%% · 每档按基础尺寸增减10%%" % int(
		snapshot.get("scale_percent", 100)
	)


func _on_ammo_changed(current: int, maximum: int) -> void:
	_queue_runtime_autosave("ammo_changed")
	var snapshot := player.get_weapon_presentation_snapshot() if player != null else {}
	var weapon_snapshot := player.get_weapon_snapshot() if player != null else {}
	ammo_label.text = "近战 · 三段" if bool(weapon_snapshot.get("melee", false)) else "%d / %d" % [current, maximum]
	if _hud_weapon_meta_label != null:
		var active_slot := player.get_active_weapon_slot() if player != null and player.has_method("get_active_weapon_slot") else 0
		_hud_weapon_meta_label.text = "[%d] %s · %s" % [
			active_slot + 1, snapshot.get("display_name", "未装备武器"),
			"主武器" if active_slot == 0 else "副武器",
		]
	if _hud_weapon_fate_label != null:
		_hud_weapon_fate_label.text = "实例 #%s · 命运 %d/%d · K 详情" % [
			snapshot.get("instance_suffix", "------"),
			snapshot.get("fate_slot_used", 0),
			snapshot.get("fate_slot_capacity", 0),
		]


func _on_hud_weapon_instance_changed(_snapshot: Dictionary) -> void:
	_refresh_hud_weapon_model(true)
	var weapon_snapshot := player.get_weapon_snapshot() if player != null else {}
	_on_ammo_changed(
		int(weapon_snapshot.get("current_ammo", 0)),
		int(weapon_snapshot.get("magazine_size", 0)),
	)


func _refresh_hud_weapon_model(force := false) -> void:
	if _hud_weapon_model_icon == null or player == null:
		return
	var item := player.get_equipped_weapon_item()
	var instance_id := str(item.get("weapon_instance_id", ""))
	if item.is_empty():
		_hud_weapon_model_instance_id = ""
		_hud_weapon_model_icon.clear_model()
		return
	if not force and instance_id == _hud_weapon_model_instance_id:
		return
	_hud_weapon_model_instance_id = instance_id
	_hud_weapon_model_icon.configure(item)


func get_hud_weapon_model_snapshot() -> Dictionary:
	return _hud_weapon_model_icon.get_snapshot() if _hud_weapon_model_icon != null else {}


func _on_player_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == "dead":
		status_label.text = "行动失败 · 防护体失去响应"


func _on_player_death_animation_finished() -> void:
	if _completed or _death_animation_ready:
		return
	_death_animation_ready = true
	_show_death_confirmation_dialog()


func _show_death_confirmation_dialog() -> void:
	if _death_dialog != null and is_instance_valid(_death_dialog):
		return
	var overlay := Control.new()
	overlay.name = "DeathConfirmationDialog"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 950
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.010, 0.018, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-260, -130)
	panel.custom_minimum_size = Vector2(520, 260)
	panel.add_theme_stylebox_override(
		"panel",
		UIStyleFactory.make_panel_with_border(0, UIPalette.HP_LOW, 8, 2)
	)
	overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 15)
	margin.add_child(box)
	var title := Label.new()
	title.text = "行动人员已倒下"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.34, 0.28))
	box.add_child(title)
	var detail := Label.new()
	detail.text = "未保险物资将按死亡规则结算。确认后返回 99F 基地中点。"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	box.add_child(detail)
	var confirm := Button.new()
	confirm.text = "确认结算并返回基地"
	confirm.custom_minimum_size = Vector2(0, 52)
	UIStyleFactory.apply_button_style(
		confirm,
		UIStyleFactory.make_button_style(Color(0.15, 0.035, 0.045, 0.98), UIPalette.HP_LOW)
	)
	confirm.pressed.connect(_confirm_death_return)
	box.add_child(confirm)
	$HUD.add_child(overlay)
	_death_dialog = overlay
	confirm.grab_focus()
	_sync_player_input_lock()


func _confirm_death_return() -> void:
	if _completed or not _death_animation_ready:
		return
	if _death_dialog != null and is_instance_valid(_death_dialog):
		_death_dialog.queue_free()
	_death_dialog = null
	_finish_run(false)


func _finish_run(success: bool) -> void:
	if _completed:
		return
	_completed = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	extraction_panel.visible = false
	_run_loot = _collect_extracted_items(success)
	var settlement: Dictionary = {}
	if success:
		_death_settlement.process_extraction_settlement(_inventory, _insurance)
	else:
		settlement = _death_settlement.process_death_settlement(_inventory, _insurance)
		_run_loot = _collect_extracted_items(false)
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
			# 成功撤离:清理检查点(电量不补满)
			BaseManager.clear_active_run_checkpoint("run_success")
		else:
			var insurance_saved := settlement.get("insurance_saved", []) as Array
			if not insurance_saved.is_empty():
				var insurance_return := BaseManager.store_insurance_return_items(
					insurance_saved, BaseShopService.generate_transaction_id("death_insurance")
				) as Dictionary
				if bool(insurance_return.get("success", false)):
					_insurance.clear_all()
			# 玩家确认死亡后行动已经结算，不能再恢复到结算前的战斗房间。
			BaseManager.clear_active_run_checkpoint("run_death_settled")
		# 结算后的场景卸载不再回写旧运行态；保险/战利品已经进入长期事务。
		BaseManager.unregister_runtime_checkpoint_provider(self, false)
		_runtime_persistence_active = false
	status_label.text = "撤离成功 · %d 击杀 · %d件物资" % [_kills, _run_loot.size()] if success else "行动失败 · 按原规则结算未保险物资"
	run_completed.emit(success, summary)
	if not test_mode:
		await get_tree().create_timer(0.18 if not success else 1.6).timeout
		get_tree().change_scene_to_file(return_scene_path)


func _collect_extracted_items(include_equipped_weapon := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if include_equipped_weapon and player != null:
		if player.has_method("get_equipped_backpack_item"):
			var equipped_backpack := player.call("get_equipped_backpack_item") as Dictionary
			if not equipped_backpack.is_empty():
				equipped_backpack["count"] = 1
				result.append(equipped_backpack)
		if player.has_method("get_equipped_weapon_item_for_slot"):
			for weapon_slot_index in range(2):
				var equipped := player.call("get_equipped_weapon_item_for_slot", weapon_slot_index) as Dictionary
				if not equipped.is_empty():
					equipped["count"] = 1
					result.append(equipped)
		elif player.has_method("get_equipped_weapon_item"):
			var equipped := player.call("get_equipped_weapon_item") as Dictionary
			if not equipped.is_empty():
				equipped["count"] = 1
				result.append(equipped)
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
	loot_label.text = "背包 %d/%d · 钥匙 %d · 魂 %d" % [
		_inventory.get_used_slots(), _inventory.get_capacity(), _get_total_room_keys(), _run_value
	]
	_refresh_quick_item_hud()


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
		"inventory_capacity": _inventory.get_capacity() if _inventory != null else BASE_INVENTORY_CAPACITY,
		"inventory_base_capacity": BASE_INVENTORY_CAPACITY,
		"equipped_backpack": get_backpack_equipment_snapshot(),
		"insurance_capacity": 2,
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
		"inventory_capacity": _inventory.get_capacity(),
		"equipped_backpack": get_backpack_equipment_snapshot(),
		"spawned_key_room_count": _spawned_key_rooms.size(), "unclaimed_key_count": unclaimed_key_count,
		"open_edges": _open_edges.values().count(true), "total_edges": _open_edges.size(),
		"edge_states": _open_edges.duplicate(true),
		"wave_numbers": _room_wave_numbers.duplicate(true),
		"wave_totals": _room_wave_totals.duplicate(true),
		"resolved_event_rooms": _resolved_event_rooms.keys(),
		"event_combat_rooms": _event_combat_rooms.keys(),
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


## — 手电筒电量 HUD —

func _update_battery_hud() -> void:
	if player == null:
		return
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null or _hud_battery_cells.is_empty():
		return
	var ratio := clampf(float(flashlight.get_charge_ratio()), 0.0, 1.0)
	var tier := int(flashlight.get_tier())
	_apply_battery_fill_color(tier, ratio)
	_last_battery_tier = tier
	_refresh_battery_time_label(flashlight)


## 把"剩余秒数"格式化为 mm:ss 或 --:-- / OFF / FULL
func _refresh_battery_time_label(flashlight: Node) -> void:
	if _hud_battery_time_label == null:
		return
	if flashlight.is_in_facility():
		_hud_battery_time_label.text = "FULL · 基地内"
		return
	var ratio := float(flashlight.get_charge_ratio())
	if ratio <= 0.0:
		_hud_battery_time_label.text = "00:00 · 耗尽"
		return
	if not flashlight.is_light_enabled():
		_hud_battery_time_label.text = "OFF · %d%%" % int(round(ratio * 100.0))
		return
	var secs := float(flashlight.get_estimated_remaining_seconds())
	if is_inf(secs) or secs <= 0.0:
		_hud_battery_time_label.text = "FULL"
		return
	var total := int(ceil(secs))
	var mm := total / 60
	var ss := total % 60
	_hud_battery_time_label.text = "%02d:%02d" % [mm, ss]


func _apply_battery_fill_color(tier: int, ratio: float) -> void:
	if _hud_battery_cells.is_empty():
		return
	var color := Color(0.94, 0.96, 0.42)
	match tier:
		0:
			color = Color(0.32, 0.92, 0.45)
		1:
			color = Color(0.94, 0.92, 0.34)
		2:
			color = Color(0.96, 0.62, 0.20)
		3:
			color = Color(0.96, 0.30, 0.18)
		_:
			color = Color(0.86, 0.20, 0.18)
	var active_cells := int(ceil(ratio * _hud_battery_cells.size())) if ratio > 0.0 else 0
	while _hud_battery_cell_prev_filled.size() < _hud_battery_cells.size():
		_hud_battery_cell_prev_filled.append(false)
	for index in _hud_battery_cells.size():
		var cell := _hud_battery_cells[index]
		var filled := index < active_cells
		var was_filled := _hud_battery_cell_prev_filled[index]
		var style := _make_hud_style(
			Color(0.23, 0.88, 1.0) if not filled else color,
			Color(0.23, 0.88, 1.0, 0.16) if not filled else Color(color, 0.82),
			1,
		)
		if filled:
			style.shadow_color = Color(color, 0.38)
			style.shadow_size = 3
		cell.add_theme_stylebox_override("panel", style)
		if filled != was_filled:
			_animate_battery_cell_transition(cell, was_filled, filled, color, index)
		_hud_battery_cell_prev_filled[index] = filled


## 电量格状态切换的视觉反馈：充电时一格一格闪烁变出，放电时闪一下再变空。样式保持原样。
func _animate_battery_cell_transition(cell: Panel, was_filled: bool, now_filled: bool, color: Color, position_index: int) -> void:
	if cell.has_meta("battery_anim_tween"):
		var old_tween: Variant = cell.get_meta("battery_anim_tween")
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
	var tween := create_tween()
	cell.set_meta("battery_anim_tween", tween)
	if now_filled and not was_filled:
		var stagger := float(position_index) * 0.12
		cell.scale = Vector2(0.45, 0.45)
		cell.modulate = Color(2.6, 2.6, 2.6, 1.0)
		tween.tween_interval(stagger)
		tween.tween_property(cell, "scale", Vector2(1.22, 1.22), 0.10)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(cell, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18)
		tween.tween_property(cell, "scale", Vector2(1.0, 1.0), 0.10)
	elif was_filled and not now_filled:
		cell.modulate = Color(2.4, 2.4, 2.4, 1.0)
		cell.scale = Vector2(1.0, 1.0)
		tween.tween_property(cell, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.08)
		tween.tween_property(cell, "scale", Vector2(0.86, 0.86), 0.10)
		tween.tween_property(cell, "scale", Vector2(1.0, 1.0), 0.10)


func _on_flashlight_charge_changed(_ratio: float, _tier: int) -> void:
	_update_battery_hud()
	_persist_flashlight_state_to_checkpoint()


func _on_flashlight_state_changed(state_id: String, context: Dictionary) -> void:
	match state_id:
		"depleted":
			if status_label != null:
				status_label.text = "手电已耗尽,返回基地补给"
			if _hud_battery_panel != null:
				_flash_action_key(_hud_battery_panel)
			if AudioManager != null:
				AudioManager.play_sfx("flashlight_depleted")
		"restored":
			if status_label != null:
				var pct := int(round(float(context.get("amount", 0.0)) * 100.0))
				status_label.text = "电量 +%d%%" % pct
			if AudioManager != null:
				AudioManager.play_sfx("flashlight_charge_up")
		"facility_recharged":
			if status_label != null:
				status_label.text = "已回到99F基地 · 手电筒充满"
			if AudioManager != null:
				AudioManager.play_sfx("flashlight_charge_up")
		"consume_refused":
			if status_label != null:
				status_label.text = "电量耗尽,无法开启"
	_persist_flashlight_state_to_checkpoint()


## 行动检查点由其它局内系统决定何时创建；本模块只在已有检查点上补写自身状态。
func _persist_flashlight_state_to_checkpoint() -> void:
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") if player != null else null
	if BaseManager != null and flashlight != null:
		BaseManager.patch_active_run_checkpoint({
			"flashlight_charge_ratio": flashlight.get_charge_ratio(),
			"flashlight_module_id": flashlight.get_module_id(),
		})
	_queue_runtime_autosave("flashlight_state")


## 物理 tick 推进电量闪烁 (低/临界/耗尽档 3Hz/5.5Hz)
func _tick_battery_blink(delta: float) -> void:
	if _hud_battery_panel == null:
		return
	_hud_battery_blink_accum += delta
	# 默认无闪烁
	var target_alpha := 1.0
	if _last_battery_tier == 3:
		# 3 Hz blink (0..1..0) on critical tier
		var phase := fmod(_hud_battery_blink_accum, 1.0 / 3.0) * 3.0
		target_alpha = 1.0 if phase < 0.5 else 0.45
	elif _last_battery_tier >= 4:
		# 5.5 Hz on depleted
		var phase := fmod(_hud_battery_blink_accum, 1.0 / 5.5) * 5.5
		target_alpha = 1.0 if phase < 0.5 else 0.30
	_hud_battery_blink_visible = target_alpha
	_hud_battery_panel.modulate.a = target_alpha
	# 倒计时每秒变化一次,但 2% 一格的耗电模式会让秒数频繁跳。
	# 这里用 process 帧频率刷新文本:消耗期间 mm:ss 走得很顺。
	if player != null:
		var flashlight := player.get_node_or_null("PlayerFlashlight3D")
		if flashlight != null:
			_refresh_battery_time_label(flashlight)
