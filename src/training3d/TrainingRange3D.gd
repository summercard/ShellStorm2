class_name TrainingRange3D
extends Node3D
## 3D 测试靶场：只读 BlueprintRegistry 取出全部枪身与弹药，在军械库里自由取用
## （不限次数、不消耗）、在刷怪台上打实战、在命运卡组装台上把任意卡装到当前武器。
##
## 隔离契约（本场景存在的全部意义）：**只改运行时内存，从不写 BaseManager**。
## 进入时 player.clear_weapon() 清空装备，场内配的枪/弹/命运卡都只活在武器树上，
## 离场随场景释放；基地存档因此原样不变 —— 出来就回到进去前的状态与物品。
## 这条契约由 tests/verification/verify_training_range_3d_flow.gd 的
## is_base_data_unchanged() 与 verify_training_range_isolation.gd 的快照对比盯着，
## 不靠注释说明。

const SERVICE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d.tscn")

## 军械库阵列：枪身一排、弹药一排，货架正面统一朝北（场地中心方向）。
const ARMORY_BAY_PITCH := 2.5
const ARMORY_ROW_X0 := -13.0
const GUN_ROW_Z := 13.5
const BULLET_ROW_Z := 17.0
const ARMORY_FACING_YAW := PI
## 刷怪台：三个台子点名三种怪，盖住近战/远程/肉盾三类行为。
const SPAWN_PAD_DEFINITIONS := [
	{"type": "melee_chaser", "count": 3, "position": Vector3(18.0, 0.0, -14.0)},
	{"type": "ranged_caster", "count": 2, "position": Vector3(18.0, 0.0, -4.0)},
	{"type": "fat_zombie03", "count": 2, "position": Vector3(18.0, 0.0, 6.0)},
]
const RESET_STATION_NAME := "重置靶标与弹药"
const FATE_BENCH_NAME := "命运卡组装台"

@export var test_mode := false

@onready var player: Player3D = $Player3D
@onready var environment_kit: TrainingRangeEnvironment3D = $EnvironmentKit
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var loadout_label: Label = $HUD/TopBar/Margin/HBox/LoadoutLabel
@onready var ammo_label: Label = $HUD/TopBar/Margin/HBox/AmmoLabel
@onready var stats_label: Label = $HUD/TopBar/Margin/HBox/StatsLabel
@onready var status_label: Label = $HUD/StatusPanel/Margin/StatusLabel

var selected_gun_id := ""
var selected_bullet_id := ""
var total_hits := 0
var total_damage := 0
var targets_destroyed := 0
var _rack_count := {"gunbody": 0, "bullet": 0}
var _weapon_kind_count := {"ranged": 0, "melee": 0}
var _targets: Array[TrainingTarget3D] = []
var _spawn_pads: Array[TrainingSpawnPad3D] = []
var _fate_panel: TrainingFateBenchPanel = null
var _base_snapshot: Dictionary = {}


func _ready() -> void:
	if BaseManager != null:
		_base_snapshot = _get_training_owned_base_snapshot()
	_configure_environment()
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	_build_racks()
	_build_targets()
	_build_spawn_pads()
	_build_services()
	player.set_combat_enabled(true)
	# 必须用 clear_all_equipped_weapons() 而不是 clear_weapon()：后者只清「手上这把枪的
	# 呈现」，武器槽 equipped_weapon_slots 与实例都还留着 —— 切个枪基地的装备就回来了。
	# 靶场要求的是**一件都不带入**。被收回的武器不还给玩家、也不写回存档：
	# 它们本就在基地存档里，场景切换后自然还原。
	player.clear_all_equipped_weapons()
	player.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(0, 0)
	_refresh_stats()
	status_label.text = "军械库任意取用枪身与弹药，刷怪台可测实战，命运卡组装台可测任意卡；所有配置仅在本场生效，离开即还原。"


func _configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.026, 0.028)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.38, 0.38)
	environment.ambient_light_energy = 0.86
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.12
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.08, 0.10, 0.10)
	environment.fog_density = 0.008
	world_environment.environment = environment
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.register_environment(environment)


func apply_performance_quality(profile: String) -> void:
	if world_environment.environment != null:
		world_environment.environment.fog_enabled = (
			profile != "low"
			and (GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog"))
		)
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 96.0 if profile == "high" else 64.0 if profile == "balanced" else 36.0


## 军械库：全部枪身与全部弹药各占一个货架格，点一次即装到玩家身上。
## 取用不限次数 —— 这里没有库存，也没有任何消耗写入。
func _build_racks() -> void:
	var guns := BlueprintRegistry.get_available_gunbodies(99)
	var bullets := BlueprintRegistry.get_available_bullets(99)
	for index in range(guns.size()):
		var tags := guns[index].get("tags", []) as Array
		var kind := "melee" if "melee" in tags else "ranged"
		_weapon_kind_count[kind] = int(_weapon_kind_count[kind]) + 1
		_add_armory_bay(
			guns[index],
			"gunbody",
			Vector3(ARMORY_ROW_X0 + float(index) * ARMORY_BAY_PITCH, 0.0, GUN_ROW_Z)
		)
	for index in range(bullets.size()):
		_add_armory_bay(
			bullets[index],
			"bullet",
			Vector3(ARMORY_ROW_X0 + float(index) * ARMORY_BAY_PITCH, 0.0, BULLET_ROW_Z)
		)


func _add_armory_bay(entry: Dictionary, category: String, position: Vector3) -> void:
	var bay := TrainingArmoryBay3D.new()
	bay.configure(entry, category)
	bay.position = position
	bay.rotation.y = ARMORY_FACING_YAW
	$Racks.add_child(bay)
	bay.selected.connect(_on_rack_selected)
	_rack_count[category] = int(_rack_count[category]) + 1


func _build_targets() -> void:
	var definitions := [
		{"type": "standard", "position": Vector3(-8, 0, -18)},
		{"type": "armored", "position": Vector3(0, 0, -20)},
		{"type": "runner", "position": Vector3(8, 0, -18)},
	]
	for definition in definitions:
		var target := TrainingTarget3D.new()
		target.configure(definition["type"])
		target.position = definition["position"]
		$Targets.add_child(target)
		target.damaged.connect(_on_target_damaged)
		target.destroyed.connect(_on_target_destroyed)
		_targets.append(target)


func _build_spawn_pads() -> void:
	for definition in SPAWN_PAD_DEFINITIONS:
		var pad := TrainingSpawnPad3D.new()
		pad.configure(str(definition["type"]), int(definition["count"]))
		pad.position = definition["position"]
		pad.enemy_container = $Enemies
		$SpawnPads.add_child(pad)
		pad.wave_spawned.connect(_on_wave_spawned)
		_spawn_pads.append(pad)


func _build_services() -> void:
	var reset_station := SERVICE_SCENE.instantiate() as ServiceStation3D
	reset_station.configure("reset", RESET_STATION_NAME, Color(0.94, 0.55, 0.18))
	reset_station.position = Vector3(14.0, 0, 16.0)
	$Services.add_child(reset_station)
	reset_station.activated.connect(_on_reset_station)
	var fate_bench := SERVICE_SCENE.instantiate() as ServiceStation3D
	fate_bench.configure("event", FATE_BENCH_NAME, Color(0.72, 0.36, 0.86))
	fate_bench.position = Vector3(7.0, 0, 20.5)
	$Services.add_child(fate_bench)
	fate_bench.activated.connect(_on_fate_bench_activated)
	var exit := TrainingExit3D.new()
	exit.position = Vector3(21.0, 0, 21.0)
	$Services.add_child(exit)
	exit.exit_requested.connect(_on_exit_requested)


func _on_rack_selected(_rack: TrainingRack3D, item_id: String, category: String) -> void:
	if category == "gunbody":
		selected_gun_id = item_id
		if _is_melee_gunbody(selected_gun_id):
			selected_bullet_id = ""
		elif selected_bullet_id.is_empty():
			selected_bullet_id = "mod_bullet_standard"
	else:
		selected_bullet_id = item_id
		if selected_gun_id.is_empty() or _is_melee_gunbody(selected_gun_id):
			selected_gun_id = "bp_pistol"
	if player.equip_weapon(selected_gun_id, selected_bullet_id):
		var snapshot := player.get_weapon_snapshot()
		_refresh_loadout_feedback(snapshot)


func _on_target_damaged(_target: TrainingTarget3D, applied: int, critical: bool) -> void:
	total_hits += 1
	total_damage += applied
	status_label.text = "命中 %d%s" % [applied, " · 暴击" if critical else ""]
	_refresh_stats()


func _on_target_destroyed(_target: TrainingTarget3D) -> void:
	targets_destroyed += 1
	_refresh_stats()


func _on_wave_spawned(_pad: TrainingSpawnPad3D, count: int) -> void:
	status_label.text = "刷出 %d 只敌人；清场后离开触发区再踏入可再次触发。" % count


func _on_reset_station(_station: ServiceStation3D) -> void:
	for target in _targets:
		target.reset_target()
	for pad in _spawn_pads:
		pad.clear_wave()
	if player.weapon != null:
		player.weapon.current_ammo = player.weapon.magazine_size
		player.weapon.ammo_changed.emit(player.weapon.current_ammo, player.weapon.magazine_size)
	status_label.text = "靶标、敌人与弹药已重置；统计继续累计。"


func _on_fate_bench_activated(_station: ServiceStation3D) -> void:
	if _fate_panel != null and is_instance_valid(_fate_panel):
		return
	var panel := TrainingFateBenchPanel.new()
	_fate_panel = panel
	panel.set_player(player)
	panel.closed.connect(_on_fate_bench_closed)
	add_child(panel)


func _on_fate_bench_closed() -> void:
	_fate_panel = null
	status_label.text = "组装台已关闭；本次装配只存在于测试武器上，离开靶场即还原。"


func _on_ammo_changed(current: int, maximum: int) -> void:
	if player != null and player.weapon != null and player.weapon.is_melee_weapon():
		ammo_label.text = "MELEE · 三段"
	else:
		ammo_label.text = "AMMO %d/%d" % [current, maximum]


func _refresh_stats() -> void:
	stats_label.text = "命中 %d · 伤害 %d · 击破 %d" % [total_hits, total_damage, targets_destroyed]


func _on_exit_requested() -> void:
	if test_mode:
		status_label.text = "测试模式：已验证返回入口"
		return
	get_tree().change_scene_to_file(GameDesignConfig.BASE_SCENE_3D)


func get_training_snapshot() -> Dictionary:
	var combination_count := (
		int(_weapon_kind_count["ranged"]) * int(_rack_count["bullet"])
		+ int(_weapon_kind_count["melee"])
	)
	return {
		"gun_count": int(_rack_count["gunbody"]), "bullet_count": int(_rack_count["bullet"]),
		"ranged_weapon_count": int(_weapon_kind_count["ranged"]),
		"melee_weapon_count": int(_weapon_kind_count["melee"]),
		"combination_count": combination_count,
		"target_types": _targets.map(func(target): return target.target_type),
		"spawn_pad_count": _spawn_pads.size(),
		"spawn_pad_types": _spawn_pads.map(func(pad): return pad.enemy_type),
		"has_fate_bench": _has_service_named(FATE_BENCH_NAME),
		"has_reset_station": _has_service_named(RESET_STATION_NAME),
		"has_exit": _has_exit_station(),
		"base_data_unchanged": is_base_data_unchanged(), "environment": environment_kit.get_snapshot(), "is_3d": true,
	}


func _has_service_named(target_name: String) -> bool:
	for child in $Services.get_children():
		if child is ServiceStation3D and (child as ServiceStation3D).display_name == target_name:
			return true
	return false


func _has_exit_station() -> bool:
	for child in $Services.get_children():
		if child is TrainingExit3D:
			return true
	return false


func is_base_data_unchanged() -> bool:
	if _base_snapshot.is_empty() or BaseManager == null:
		return true
	return _base_snapshot == _get_training_owned_base_snapshot()


func _get_training_owned_base_snapshot() -> Dictionary:
	var snapshot := BaseManager.get_profile_snapshot()
	# 世界时钟与按世界时间恢复的基地能源属于常驻全局系统；它们在任何
	# 可游玩场景中都会推进，不能被误判为靶场装备/目标写入了长期进度。
	for global_key in [
		"world_time_elapsed_game_seconds",
		"base_energy_current",
		"base_energy_capacity",
		"base_energy_last_synced_game_seconds",
	]:
		snapshot.erase(global_key)
	return snapshot


func equip_combination_for_test(gun_id: String, bullet_id: String) -> bool:
	selected_gun_id = gun_id
	selected_bullet_id = "" if _is_melee_gunbody(gun_id) else bullet_id
	var equipped := player.equip_weapon(gun_id, selected_bullet_id)
	if equipped:
		_refresh_loadout_feedback(player.get_weapon_snapshot())
	return equipped


func _is_melee_gunbody(gun_id: String) -> bool:
	for entry in BlueprintRegistry.get_available_gunbodies(99):
		if str(entry.get("item_id", "")) == gun_id:
			return "melee" in (entry.get("tags", []) as Array)
	return false


func _refresh_loadout_feedback(snapshot: Dictionary) -> void:
	var weapon_name := selected_gun_id.trim_prefix("bp_")
	if bool(snapshot.get("melee", false)):
		var profile := player.weapon.get_melee_profile()
		loadout_label.text = "%s · 近战" % weapon_name
		ammo_label.text = "MELEE · 三段"
		status_label.text = "近战已装备 · 伤害 %d · 距离 %.2fm · %d 段" % [
			int(snapshot.get("damage", 0)),
			float(profile.get("reach", 0.0)),
			int(profile.get("combo_count", 0)),
		]
		return
	loadout_label.text = "%s + %s" % [weapon_name, selected_bullet_id.trim_prefix("mod_bullet_")]
	ammo_label.text = "AMMO %d/%d" % [int(snapshot.get("current_ammo", 0)), int(snapshot.get("magazine_size", 0))]
	status_label.text = "组合已装配 · 伤害 %d · 射速 %.1f · 弹丸 %d" % [
		int(snapshot.get("damage", 0)),
		float(snapshot.get("fire_rate", 0.0)),
		int(snapshot.get("projectile_count", 0)),
	]
