class_name TrainingRange3D
extends Node3D
## 3D 靶场只读取 BlueprintRegistry，7枪×8弹的 56 种组合均在同一空间可测试；
## 不写入基地存档、局内战利品或长期统计。

const SERVICE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d_v001.tscn")

@export var test_mode := false

@onready var player: Player3D = $Player3D
@onready var environment_kit: TrainingRangeEnvironment3D = $EnvironmentKit
@onready var world_environment: WorldEnvironment = $WorldEnvironment
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
var _targets: Array[TrainingTarget3D] = []
var _base_snapshot: Dictionary = {}


func _ready() -> void:
	if BaseManager != null and BaseManager.data != null:
		_base_snapshot = BaseManager.data._to_dict().duplicate(true)
	_configure_environment()
	_build_racks()
	_build_targets()
	_build_services()
	player.set_combat_enabled(true)
	player.clear_weapon()
	player.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(0, 0)
	_refresh_stats()
	status_label.text = "选择一件枪身和一枚弹药模块；所有组合仅在靶场生效。"


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


func _build_racks() -> void:
	var guns := BlueprintRegistry.get_available_gunbodies(99)
	var bullets := BlueprintRegistry.get_available_bullets(99)
	for index in range(guns.size()):
		_add_rack(guns[index], "gunbody", Vector3(-14.0 + index * 2.25, 0, 2.65))
	for index in range(bullets.size()):
		_add_rack(bullets[index], "bullet", Vector3(-14.0 + index * 2.15, 0, -0.25))


func _add_rack(entry: Dictionary, category: String, position: Vector3) -> void:
	var rack := TrainingRack3D.new()
	rack.configure(entry, category)
	rack.position = position
	$Racks.add_child(rack)
	rack.selected.connect(_on_rack_selected)
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


func _build_services() -> void:
	var reset_station := SERVICE_SCENE.instantiate() as ServiceStation3D
	reset_station.configure("reset", "重置靶标与弹药", Color(0.94, 0.55, 0.18))
	reset_station.position = Vector3(11.5, 0, 1.8)
	$Services.add_child(reset_station)
	reset_station.activated.connect(_on_reset_station)
	var exit := TrainingExit3D.new()
	exit.position = Vector3(15.5, 0, 2.8)
	$Services.add_child(exit)
	exit.exit_requested.connect(_on_exit_requested)


func _on_rack_selected(_rack: TrainingRack3D, item_id: String, category: String) -> void:
	if category == "gunbody":
		selected_gun_id = item_id
		if selected_bullet_id.is_empty():
			selected_bullet_id = "mod_bullet_standard"
	else:
		selected_bullet_id = item_id
		if selected_gun_id.is_empty():
			selected_gun_id = "bp_pistol"
	if player.equip_weapon(selected_gun_id, selected_bullet_id):
		var snapshot := player.get_weapon_snapshot()
		loadout_label.text = "%s + %s" % [selected_gun_id.trim_prefix("bp_"), selected_bullet_id.trim_prefix("mod_bullet_")]
		status_label.text = "组合已装配 · 伤害 %d · 射速 %.1f · 弹丸 %d" % [snapshot["damage"], snapshot["fire_rate"], snapshot["projectile_count"]]


func _on_target_damaged(_target: TrainingTarget3D, applied: int, critical: bool) -> void:
	total_hits += 1
	total_damage += applied
	status_label.text = "命中 %d%s" % [applied, " · 暴击" if critical else ""]
	_refresh_stats()


func _on_target_destroyed(_target: TrainingTarget3D) -> void:
	targets_destroyed += 1
	_refresh_stats()


func _on_reset_station(_station: ServiceStation3D) -> void:
	for target in _targets:
		target.reset_target()
	if player.weapon != null:
		player.weapon.current_ammo = player.weapon.magazine_size
		player.weapon.ammo_changed.emit(player.weapon.current_ammo, player.weapon.magazine_size)
	status_label.text = "靶标与弹药已重置；统计继续累计。"


func _on_ammo_changed(current: int, maximum: int) -> void:
	ammo_label.text = "AMMO %d/%d" % [current, maximum]


func _refresh_stats() -> void:
	stats_label.text = "命中 %d · 伤害 %d · 击破 %d" % [total_hits, total_damage, targets_destroyed]


func _on_exit_requested() -> void:
	if test_mode:
		status_label.text = "测试模式：已验证返回入口"
		return
	get_tree().change_scene_to_file(GameDesignConfig.BASE_SCENE_3D)


func get_training_snapshot() -> Dictionary:
	return {
		"gun_count": int(_rack_count["gunbody"]), "bullet_count": int(_rack_count["bullet"]),
		"combination_count": int(_rack_count["gunbody"]) * int(_rack_count["bullet"]),
		"target_types": _targets.map(func(target): return target.target_type),
		"has_reset_station": $Services.get_child_count() >= 1, "has_exit": $Services.get_child_count() >= 2,
		"base_data_unchanged": is_base_data_unchanged(), "environment": environment_kit.get_snapshot(), "is_3d": true,
	}


func is_base_data_unchanged() -> bool:
	if _base_snapshot.is_empty() or BaseManager == null or BaseManager.data == null:
		return true
	return _base_snapshot == BaseManager.data._to_dict()


func equip_combination_for_test(gun_id: String, bullet_id: String) -> bool:
	selected_gun_id = gun_id
	selected_bullet_id = bullet_id
	var equipped := player.equip_weapon(gun_id, bullet_id)
	if equipped:
		loadout_label.text = "%s + %s" % [gun_id.trim_prefix("bp_"), bullet_id.trim_prefix("mod_bullet_")]
	return equipped
