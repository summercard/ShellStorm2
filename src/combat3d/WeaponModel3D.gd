class_name WeaponModel3D
extends Node3D
## 现有 BlueprintRegistry 的 3D 表现与射击适配层。目录、数值和 56 组枪弹组合仍只有一份来源。

signal shot_fired(projectile_count: int)
signal projectile_spawned(projectile: Projectile3D)
signal ammo_changed(current: int, maximum: int)
signal loadout_changed(gun_id: String, bullet_id: String)
signal reload_started(duration: float)
signal reload_progress_changed(progress: float, remaining: float)
signal reload_ended(completed: bool)

const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")
const MELEE_VISUAL_SCENES := {
	"bp_baseball_bat": preload("res://assets/art/weapons/melee_3d/wpn_melee_baseball_bat_root_top3d_v001.tscn"),
	"bp_greatblade": preload("res://assets/art/weapons/melee_3d/wpn_melee_greatblade_root_top3d_v001.tscn"),
	"bp_waraxe": preload("res://assets/art/weapons/melee_3d/wpn_melee_waraxe_root_top3d_v001.tscn"),
}
const GUN_VISUAL_SCENES := {
	"bp_pistol": preload("res://assets/art/weapons/weapon_3d/runtime/hair_dryer/wpn_hair_dryer_root_top3d_v001.tscn"),
	"bp_shotgun": preload("res://assets/art/weapons/weapon_3d/runtime/double_barrel_cannon/wpn_double_barrel_cannon_root_top3d_v001.tscn"),
	"bp_rifle": preload("res://assets/art/weapons/weapon_3d/runtime/broom_rifle/wpn_broom_rifle_root_top3d_v001.tscn"),
	"bp_machinegun": preload("res://assets/art/weapons/weapon_3d/runtime/water_tank_blaster/wpn_water_tank_blaster_root_top3d_v001.tscn"),
	"bp_sniper": preload("res://assets/art/weapons/weapon_3d/runtime/candy_sniper/wpn_candy_sniper_root_top3d_v001.tscn"),
	"bp_launcher": preload("res://assets/art/weapons/weapon_3d/runtime/toaster_launcher/wpn_toaster_launcher_root_top3d_v001.tscn"),
	"bp_charge": preload("res://assets/art/weapons/weapon_3d/runtime/gumball_cannon/wpn_gumball_cannon_root_top3d_v001.tscn"),
}

const GUN_PROFILES := {
	"bp_pistol": {"length": 0.72, "barrel": 0.32, "width": 0.18, "height": 0.22, "color": Color(0.28, 0.34, 0.34)},
	"bp_shotgun": {"length": 1.02, "barrel": 0.78, "width": 0.25, "height": 0.25, "color": Color(0.36, 0.25, 0.16)},
	"bp_rifle": {"length": 1.10, "barrel": 0.62, "width": 0.21, "height": 0.24, "color": Color(0.20, 0.30, 0.27)},
	"bp_machinegun": {"length": 1.18, "barrel": 0.58, "width": 0.31, "height": 0.30, "color": Color(0.27, 0.29, 0.20)},
	"bp_sniper": {"length": 1.30, "barrel": 1.02, "width": 0.19, "height": 0.22, "color": Color(0.18, 0.24, 0.30)},
	"bp_launcher": {"length": 1.08, "barrel": 0.72, "width": 0.38, "height": 0.36, "color": Color(0.30, 0.22, 0.16)},
	"bp_charge": {"length": 1.12, "barrel": 0.62, "width": 0.32, "height": 0.34, "color": Color(0.28, 0.18, 0.34)},
}

const BULLET_COLORS := {
	"mod_bullet_standard": Color(0.76, 0.86, 0.92),
	"mod_bullet_sticky": Color(0.32, 0.92, 0.62),
	"mod_bullet_bounce": Color(0.30, 0.70, 1.0),
	"mod_bullet_piercing": Color(1.0, 0.78, 0.22),
	"mod_bullet_explosive": Color(1.0, 0.28, 0.08),
	"mod_bullet_homing": Color(0.50, 1.0, 0.42),
	"mod_bullet_blackhole": Color(0.68, 0.25, 0.95),
	"mod_bullet_balloon": Color(0.98, 0.35, 0.72),
}

@export var gun_id := "bp_pistol"
@export var bullet_id := "mod_bullet_standard"
@export var display_only := false
@export_flags_3d_render var render_layers := 1

var damage := 20
var fire_rate := 3.5
var projectile_count := 1
var spread := 0.03
var reload_time := 1.5
var magazine_size := 12
var current_ammo := 12
var bullet_speed := 24.0
var bullet_tags: Array[String] = []
var bullet_color := Color(0.76, 0.86, 0.92)
var damage_multiplier := 1.0
var charge_time := 0.0
var weapon_kind := "ranged"
var _melee_profile: Dictionary = {}
var _base_damage := 20
var _copy_chance := 0.0
var _critical_chance := 0.10
var _critical_damage_multiplier := 1.5
var _projectile_behavior: Dictionary = {}
var _secondary_guns: Array[Dictionary] = []
var _source_tree: WeaponAssemblyTree
var _fire_sequence := 0

var _cooldown := 0.0
var _reload_remaining := 0.0
var _active_reload_duration := 0.0
var _recoil := 0.0
var _charge_active := false
var _charge_elapsed := 0.0
var _charge_aim := Vector3.FORWARD
var _charge_shooter: Node3D
var _visual_root: Node3D
var _muzzle: Marker3D

const GUN_NAME_TO_ID := {
	"GunBody_Pistol": "bp_pistol", "GunBody_Shotgun": "bp_shotgun",
	"GunBody_Rifle": "bp_rifle", "GunBody_Machinegun": "bp_machinegun",
	"GunBody_Sniper": "bp_sniper", "GunBody_Launcher": "bp_launcher",
	"GunBody_Charge": "bp_charge",
	"Melee_BaseballBat": "bp_baseball_bat",
	"Melee_Greatblade": "bp_greatblade",
	"Melee_Waraxe": "bp_waraxe",
}
const BULLET_NAME_TO_ID := {
	"Bullet_Standard": "mod_bullet_standard", "Bullet_Sticky": "mod_bullet_sticky",
	"Bullet_Bounce": "mod_bullet_bounce", "Bullet_Piercing": "mod_bullet_piercing",
	"Bullet_Explosive": "mod_bullet_explosive", "Bullet_Homing": "mod_bullet_homing",
	"Bullet_Blackhole": "mod_bullet_blackhole", "Bullet_Balloon": "mod_bullet_balloon",
}


func _ready() -> void:
	var weapon_item: Variant = get_meta("weapon_item_data", {})
	if display_only and weapon_item is Dictionary and not (weapon_item as Dictionary).is_empty():
		var instance := WeaponInstance.from_item(weapon_item as Dictionary)
		var preview_tree := instance.build_runtime_tree() if instance != null else null
		if preview_tree != null:
			preview_tree.name = "PreviewAssemblyTree"
			add_child(preview_tree)
			configure_from_tree(preview_tree)
			return
	if not gun_id.is_empty():
		configure(gun_id, bullet_id)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_remaining > 0.0:
		_reload_remaining = maxf(0.0, _reload_remaining - delta)
		if _reload_remaining <= 0.0:
			_finish_reload()
		else:
			reload_progress_changed.emit(get_reload_progress(), _reload_remaining)
	if _charge_active:
		_charge_elapsed = minf(charge_time, _charge_elapsed + delta)
	_recoil = lerpf(_recoil, 0.0, minf(1.0, delta * 15.0))
	if _visual_root != null:
		var reload_progress := get_reload_progress()
		var reload_arch := sin(reload_progress * PI) if is_reloading() else 0.0
		var service_tick := sin(reload_progress * TAU * 2.0) * reload_arch
		_visual_root.position = Vector3(0.0, -0.025 * reload_arch, _recoil + 0.04 * reload_arch)
		_visual_root.rotation = Vector3(
			_recoil * 0.22 + reload_arch * 0.24,
			0.0,
			-reload_arch * 0.16 + service_tick * 0.035
		)
	# 没有冷却/换弹/蓄力/明显后坐力时，整把枪没在动，关闭 process 节省 CPU。
	if (
		_cooldown <= 0.0
		and _reload_remaining <= 0.0
		and not _charge_active
		and absf(_recoil) < 0.001
	):
		set_process(false)


func configure(p_gun_id: String, p_bullet_id: String) -> bool:
	cancel_reload()
	cancel_charge()
	_cooldown = 0.0
	_recoil = 0.0
	var gun_node := BlueprintRegistry.create_assembly_node(p_gun_id)
	if gun_node == null:
		return false
	var is_melee := "melee" in gun_node.tags
	var bullet_node: AssemblyNode = null
	if not is_melee:
		bullet_node = BlueprintRegistry.create_assembly_node(p_bullet_id)
		if bullet_node == null:
			gun_node.free()
			return false
	gun_id = p_gun_id
	bullet_id = "" if is_melee else p_bullet_id
	var gun_stats := gun_node.get_base_stats()
	var bullet_stats := bullet_node.get_base_stats() if bullet_node != null else {}
	_configure_common_stats(gun_stats.merged(bullet_stats, true), is_melee)
	bullet_tags.clear()
	if bullet_node != null:
		bullet_tags.assign(bullet_node.tags)
	_copy_chance = 0.0
	_critical_chance = 0.12 if is_melee else (0.28 if gun_id == "bp_sniper" else 0.10)
	_critical_damage_multiplier = 1.5
	_projectile_behavior = _extract_projectile_behavior(gun_stats.merged(bullet_stats, true))
	_secondary_guns.clear()
	_source_tree = null
	_apply_gun_behavior_tags()
	bullet_color = BULLET_COLORS.get(bullet_id, Color(0.20, 0.84, 0.92) if is_melee else Color(0.76, 0.86, 0.92))
	gun_node.free()
	if bullet_node != null:
		bullet_node.free()
	_rebuild_visual()
	loadout_changed.emit(gun_id, bullet_id)
	ammo_changed.emit(current_ammo, magazine_size)
	return true


func configure_from_tree(tree: WeaponAssemblyTree) -> bool:
	cancel_reload()
	cancel_charge()
	_cooldown = 0.0
	_recoil = 0.0
	if tree == null or tree.get_root() == null:
		clear_weapon()
		return false
	var root := tree.get_root()
	_source_tree = tree
	var bullet: AssemblyNode = null
	for node in root.get_all_descendants():
		if node.node_type == AssemblyNode.NodeType.BULLET:
			bullet = node
			break
	gun_id = str(GUN_NAME_TO_ID.get(root.node_name, "bp_pistol"))
	var root_is_melee := "melee" in root.tags
	bullet_id = "" if root_is_melee else str(BULLET_NAME_TO_ID.get(bullet.node_name if bullet != null else "", "mod_bullet_standard"))
	var stats := tree.get_computed_stats()
	_configure_common_stats(stats, root_is_melee)
	_copy_chance = clampf(float(stats.get("copy_chance", 0.0)), 0.0, 1.0)
	_critical_chance = 0.12 if root_is_melee else (0.28 if gun_id == "bp_sniper" else 0.10)
	_critical_damage_multiplier = maxf(1.0, float(stats.get("crit_damage_multiplier", 1.5)))
	_projectile_behavior = _extract_projectile_behavior(stats)
	_secondary_guns.clear()
	bullet_tags.clear()
	if bullet != null:
		bullet_tags.assign(bullet.tags)
	var behavior_nodes := root.get_all_descendants()
	behavior_nodes.append(root)
	for node in behavior_nodes:
		for tag in node.tags:
			if tag not in bullet_tags:
				bullet_tags.append(tag)
		if node != root and node.node_type == AssemblyNode.NodeType.GUN_BODY:
			var child_stats := node.get_base_stats()
			if node.parent_node != null and node.parent_node.node_type == AssemblyNode.NodeType.BULLET:
				_projectile_behavior["attached_gun"] = {
					"damage": maxi(1, int(child_stats.get("damage", 5))),
					"fire_rate": maxf(0.2, float(child_stats.get("fire_rate", 2.0))),
					"bullet_count": maxi(1, int(child_stats.get("bullet_count", 1))),
				}
			elif "Fate.SecondaryGun" in node.tags:
				_secondary_guns.append({
					"damage": maxi(1, int(child_stats.get("damage", 5))),
					"bullet_count": maxi(1, int(child_stats.get("bullet_count", 1))),
				})
	if "Fate.ArmorPierced" in bullet_tags:
		_projectile_behavior["pierce_shield"] = true
	_apply_gun_behavior_tags()
	bullet_color = BULLET_COLORS.get(bullet_id, Color(0.20, 0.84, 0.92) if root_is_melee else Color(0.76, 0.86, 0.92))
	_rebuild_visual()
	loadout_changed.emit(gun_id, bullet_id)
	ammo_changed.emit(current_ammo, magazine_size)
	return true


func _configure_common_stats(stats: Dictionary, melee: bool) -> void:
	weapon_kind = "melee" if melee else "ranged"
	if melee:
		_base_damage = maxi(1, int(stats.get("damage", 1)))
		damage = maxi(1, int(_base_damage * damage_multiplier))
		fire_rate = 0.0
		projectile_count = 0
		spread = 0.0
		reload_time = 0.0
		magazine_size = 0
		current_ammo = 0
		bullet_speed = 0.0
		charge_time = 0.0
		_melee_profile = _build_melee_profile(stats)
		return
	_melee_profile.clear()
	_base_damage = maxi(1, int(stats.get("damage", 0)) + int(stats.get("bullet_damage", 5)))
	damage = maxi(1, int(_base_damage * damage_multiplier))
	fire_rate = maxf(0.2, float(stats.get("fire_rate", 3.0)))
	projectile_count = maxi(1, int(stats.get("bullet_count", 1)))
	spread = maxf(0.0, float(stats.get("spread", 0.0)))
	reload_time = maxf(0.25, float(stats.get("reload_time", 1.5)) + float(stats.get("reload_penalty", 0.0)))
	magazine_size = maxi(1, int(stats.get("magazine_size", 12)))
	current_ammo = magazine_size
	bullet_speed = 23.0 * float(stats.get("bullet_speed", 1.0))
	charge_time = maxf(0.0, float(stats.get("charge_time", 0.0)))


func _build_melee_profile(stats: Dictionary) -> Dictionary:
	var steps: Array[Dictionary] = []
	var combo_count := clampi(int(stats.get("melee_combo_count", 3)), 1, 3)
	for index in range(1, combo_count + 1):
		steps.append({
			"damage_scale": float(stats.get("melee_%d_damage_scale" % index, 1.0)),
			"windup_s": float(stats.get("melee_%d_windup_s" % index, 0.2)),
			"active_s": float(stats.get("melee_%d_active_s" % index, 0.1)),
			"recovery_s": float(stats.get("melee_%d_recovery_s" % index, 0.25)),
			"knockback_scale": float(stats.get("melee_%d_knockback_scale" % index, 1.0)),
			"pose_id": ["sweep_left", "sweep_right", "overhead_finisher"][index - 1],
		})
	return {
		"content_id": gun_id.replace("bp_", "weapon_"),
		"assembly_id": gun_id,
		"reach": float(stats.get("melee_reach", 2.5)),
		"arc_degrees": float(stats.get("melee_arc_degrees", 100.0)),
		"knockback": float(stats.get("melee_knockback", 4.0)),
		"combo_count": combo_count,
		"combo_steps": steps,
	}


func clear_weapon() -> void:
	cancel_reload()
	cancel_charge()
	gun_id = ""
	bullet_id = ""
	current_ammo = 0
	magazine_size = 0
	weapon_kind = "ranged"
	_melee_profile.clear()
	if _visual_root != null:
		_visual_root.queue_free()
		_visual_root = null
	_muzzle = null
	_source_tree = null
	_projectile_behavior.clear()
	_secondary_guns.clear()
	loadout_changed.emit("", "")
	ammo_changed.emit(0, 0)


func try_fire(aim_direction: Vector3, shooter: Node3D) -> bool:
	if is_melee_weapon() or display_only or gun_id.is_empty() or _cooldown > 0.0 or _reload_remaining > 0.0:
		return false
	if current_ammo <= 0:
		request_reload()
		return false
	if gun_id == "bp_charge":
		_charge_aim = aim_direction.normalized()
		_charge_shooter = shooter
		if not _charge_active:
			_charge_active = true
			_charge_elapsed = 0.0
			# 蓄力期间需要每帧更新，唤醒 process。
			set_process(true)
		return false
	return _fire_now(aim_direction, shooter, 1.0)


func release_charge() -> bool:
	if not _charge_active:
		return false
	var ratio := clampf(_charge_elapsed / maxf(0.01, charge_time), 0.0, 1.0)
	_charge_active = false
	_charge_elapsed = 0.0
	var active_shooter := _charge_shooter
	_charge_shooter = null
	if ratio < 0.12 or active_shooter == null or not is_instance_valid(active_shooter):
		return false
	return _fire_now(_charge_aim, active_shooter, lerpf(0.72, 2.35, ratio))


func cancel_charge() -> void:
	_charge_active = false
	_charge_elapsed = 0.0
	_charge_shooter = null


func _fire_now(aim_direction: Vector3, shooter: Node3D, shot_damage_multiplier: float) -> bool:
	if display_only or gun_id.is_empty() or _cooldown > 0.0 or _reload_remaining > 0.0 or current_ammo <= 0:
		return false
	var world := get_tree().current_scene
	if world == null:
		return false
	_cooldown = 1.0 / fire_rate
	current_ammo -= 1
	_fire_sequence += 1
	_recoil = 0.16 if gun_id == "bp_shotgun" or gun_id == "bp_launcher" else 0.09
	# 开火触发后坐力衰减，重新打开 process。
	set_process(true)
	var behavior := _projectile_behavior.duplicate(true)
	var base_direction := aim_direction.normalized()
	if bool(behavior.get("uncontrolled_gun", false)):
		var randomness := clampf(float(behavior.get("aim_randomness", 0.5)), 0.0, 1.0)
		base_direction = base_direction.rotated(Vector3.UP, randf_range(-PI, PI) * randomness)
		shot_damage_multiplier *= float(behavior.get("uncontrolled_damage_scale", 1.0))
	var nth := int(behavior.get("every_nth_fire", 0))
	if nth > 0 and _fire_sequence % nth == 0:
		shot_damage_multiplier *= float(behavior.get("nth_damage_multiplier", 2.0))
		behavior["nth_explosion"] = true
	var emitted_count := 0
	for index in range(projectile_count):
		var angle := 0.0
		if projectile_count > 1:
			angle = lerpf(-spread * 0.5, spread * 0.5, float(index) / float(projectile_count - 1))
		elif spread > 0.0:
			angle = randf_range(-spread * 0.5, spread * 0.5)
		var shot_direction := base_direction.rotated(Vector3.UP, angle).normalized()
		var is_critical := _consume_forced_critical() or randf() < _critical_chance
		var projectile_damage := maxi(1, int(damage * shot_damage_multiplier))
		if is_critical:
			# Enemy3D 的通用暴击入口会乘 1.5；在这里补齐命运卡的实际倍率差额。
			projectile_damage = maxi(1, int(projectile_damage * _critical_damage_multiplier / 1.5))
		var projectile_config := {
			"direction": shot_direction,
			"speed": bullet_speed,
			"damage": projectile_damage,
			"critical": is_critical,
			"hostile": false,
			"tags": bullet_tags,
			"color": bullet_color,
			"shooter": shooter,
			"behavior": behavior,
		}
		var projectile := _acquire_projectile(
			world, projectile_config, _muzzle.global_position if _muzzle != null else global_position
		)
		projectile_spawned.emit(projectile)
		emitted_count += 1
		if _copy_chance > 0.0 and randf() < _copy_chance:
			var copied_config := projectile_config.duplicate(true)
			copied_config["direction"] = shot_direction.rotated(
				Vector3.UP, 0.045 if index % 2 == 0 else -0.045
			)
			var copied := _acquire_projectile(
				world,
				copied_config,
				_muzzle.global_position if _muzzle != null else global_position,
			)
			projectile_spawned.emit(copied)
			emitted_count += 1
	for secondary in _secondary_guns:
		emitted_count += _fire_secondary_gun(world, shooter, base_direction, secondary)
	if bool(behavior.get("copy_fire", false)):
		emitted_count += _fire_copy_wave(
			world,
			shooter,
			base_direction,
			float(behavior.get("second_wave_damage_scale", 0.6)),
			behavior,
		)
	_spawn_muzzle_effect(world)
	if AudioManager != null:
		AudioManager.play_fire_sfx(fire_rate, emitted_count)
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(
			shooter.global_position if shooter != null else global_position,
			20.0 if gun_id == "bp_launcher" else 14.0,
			"weapon_fire",
			shooter
		)
	shot_fired.emit(emitted_count)
	ammo_changed.emit(current_ammo, magazine_size)
	if current_ammo <= 0:
		request_reload()
	return true


func _apply_gun_behavior_tags() -> void:
	if gun_id == "bp_launcher" and "explosive" not in bullet_tags:
		bullet_tags.append("explosive")
	if gun_id == "bp_charge" and "charged" not in bullet_tags:
		bullet_tags.append("charged")
	if bool(_projectile_behavior.get("homing", false)) and "homing" not in bullet_tags:
		bullet_tags.append("homing")
	if bool(_projectile_behavior.get("bounce", false)) and "bounce" not in bullet_tags:
		bullet_tags.append("bounce")
	if int(_projectile_behavior.get("pierce_level", 0)) > 0 and "piercing" not in bullet_tags:
		bullet_tags.append("piercing")


func _extract_projectile_behavior(stats: Dictionary) -> Dictionary:
	var behavior := {}
	for key in [
		"homing", "homing_strength", "bounce", "bounce_count", "bounce_walls",
		"bounce_damage_scale", "pierce_level", "chain_lightning", "chain_count",
		"chain_range", "chain_damage_scale", "fuse_damage", "fuse_damage_type",
		"dot_damage_per_sec", "dot_damage_per_stack", "dot_duration", "max_stacks",
		"freeze_duration", "freeze_duration_elite", "fate_scale", "size_growth",
		"growth_per_hit", "max_fate_scale", "return_to_player", "home_on_land",
		"home_lifetime", "return_damage_multiplier", "spawn_turret_on_land",
		"turret_duration", "turret_fire_rate", "uncontrolled_gun", "aim_randomness",
		"uncontrolled_damage_scale", "copy_fire", "copy_fire_delay",
		"second_wave_damage_scale", "explode_on_reload", "explosion_radius",
		"explosion_damage_scale", "every_nth_fire", "every_nth_attach_gun",
		"visual_has_eyes", "visual_has_legs",
		"fate_attachment_hit_trigger",
		"crit_on_kill", "crit_damage_multiplier",
	]:
		if stats.has(key):
			behavior[key] = stats[key]
	if "Fate.ArmorPierced" in bullet_tags or int(stats.get("pierce_level", 0)) > 0:
		behavior["pierce_shield"] = true
	return behavior


func _consume_forced_critical() -> bool:
	return _source_tree != null and _source_tree.consume_crit_on_kill_stack()


func _fire_secondary_gun(
	world: Node,
	shooter: Node3D,
	aim_direction: Vector3,
	secondary: Dictionary
) -> int:
	var count := maxi(1, int(secondary.get("bullet_count", 1)))
	for index in range(count):
		var angle := (float(index) - float(count - 1) * 0.5) * 0.08
		_acquire_projectile(world, {
			"direction": aim_direction.rotated(Vector3.UP, angle),
			"speed": bullet_speed,
			"damage": maxi(1, int(secondary.get("damage", 5))),
			"critical": false,
			"hostile": false,
			"tags": bullet_tags,
			"color": bullet_color.lightened(0.12),
			"shooter": shooter,
			"behavior": {},
		}, _muzzle.global_position if _muzzle != null else global_position)
	return count


func _fire_copy_wave(
	world: Node,
	shooter: Node3D,
	aim_direction: Vector3,
	damage_scale: float,
	behavior: Dictionary
) -> int:
	for index in range(projectile_count):
		var angle := 0.0 if projectile_count <= 1 else lerpf(
			-spread * 0.5, spread * 0.5, float(index) / float(projectile_count - 1)
		)
		_acquire_projectile(world, {
			"direction": aim_direction.rotated(Vector3.UP, angle + 0.025),
			"speed": bullet_speed,
			"damage": maxi(1, int(damage * damage_scale)),
			"critical": false,
			"hostile": false,
			"tags": bullet_tags,
			"color": bullet_color.darkened(0.10),
			"shooter": shooter,
			"behavior": behavior,
		}, _muzzle.global_position if _muzzle != null else global_position)
	return projectile_count


func _acquire_projectile(world: Node, config: Dictionary, world_position: Vector3) -> Projectile3D:
	var pools := get_tree().get_nodes_in_group("projectile_pool_3d")
	if not pools.is_empty() and pools[0] is ProjectilePool3D:
		return (pools[0] as ProjectilePool3D).acquire(config, world_position)
	var projectile := PROJECTILE_SCRIPT.new() as Projectile3D
	projectile.configure(config)
	world.add_child(projectile)
	projectile.global_position = world_position
	return projectile


func request_reload() -> bool:
	if is_melee_weapon() or display_only or gun_id.is_empty() or _reload_remaining > 0.0 or current_ammo >= magazine_size:
		return false
	_active_reload_duration = maxf(0.01, reload_time)
	_reload_remaining = _active_reload_duration
	cancel_charge()
	_perform_reload_explosion()
	if AudioManager != null:
		AudioManager.play_reload_sfx()
	reload_started.emit(_active_reload_duration)
	reload_progress_changed.emit(0.0, _reload_remaining)
	# 换弹动画每帧更新，唤醒 process。
	set_process(true)
	return true


func refill_ammo() -> bool:
	if is_melee_weapon() or display_only or gun_id.is_empty():
		return false
	cancel_reload()
	current_ammo = magazine_size
	ammo_changed.emit(current_ammo, magazine_size)
	return true


func cancel_reload() -> bool:
	if not is_reloading():
		return false
	_reload_remaining = 0.0
	_active_reload_duration = 0.0
	reload_progress_changed.emit(0.0, 0.0)
	reload_ended.emit(false)
	return true


func set_damage_multiplier(multiplier: float) -> void:
	damage_multiplier = maxf(0.1, multiplier)
	damage = maxi(1, int(_base_damage * damage_multiplier))


func is_reloading() -> bool:
	return _reload_remaining > 0.0


func is_melee_weapon() -> bool:
	return weapon_kind == "melee" and not _melee_profile.is_empty()


func get_melee_profile() -> Dictionary:
	return _melee_profile.duplicate(true)


func roll_melee_critical() -> bool:
	return is_melee_weapon() and randf() < _critical_chance


func get_visual_bounds_hint() -> Vector3:
	if gun_id == "bp_baseball_bat":
		return Vector3(0.28, 0.28, 1.48)
	if gun_id == "bp_greatblade":
		return Vector3(0.82, 0.30, 2.42)
	if gun_id == "bp_waraxe":
		return Vector3(1.18, 0.34, 2.62)
	var ranged := GUN_PROFILES.get(gun_id, GUN_PROFILES["bp_pistol"]) as Dictionary
	return Vector3(float(ranged.get("width", 0.2)), float(ranged.get("height", 0.2)), float(ranged.get("length", 0.8)))


func get_reload_progress() -> float:
	if not is_reloading() or _active_reload_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_remaining / _active_reload_duration, 0.0, 1.0)


func get_reload_snapshot() -> Dictionary:
	return {
		"active": is_reloading(),
		"progress": get_reload_progress(),
		"remaining": _reload_remaining,
		"duration": _active_reload_duration if is_reloading() else reload_time,
	}


func get_snapshot() -> Dictionary:
	return {
		"gun_id": gun_id,
		"bullet_id": bullet_id,
		"weapon_kind": weapon_kind,
		"uses_ammo": not is_melee_weapon(),
		"melee": is_melee_weapon(),
		"melee_profile": get_melee_profile(),
		"visual_bounds_hint": get_visual_bounds_hint(),
		"damage": damage,
		"fire_rate": fire_rate,
		"projectile_count": projectile_count,
		"magazine_size": magazine_size,
		"current_ammo": current_ammo,
		"reloading": is_reloading(),
		"reload_progress": get_reload_progress(),
		"reload_remaining": _reload_remaining,
		"reload_duration": _active_reload_duration if is_reloading() else reload_time,
		"bullet_tags": bullet_tags.duplicate(),
		"charge_time": charge_time,
		"charge_active": _charge_active,
		"charge_ratio": clampf(_charge_elapsed / maxf(0.01, charge_time), 0.0, 1.0) if charge_time > 0.0 else 0.0,
		"copy_chance": _copy_chance,
		"critical_chance": _critical_chance,
		"fate_behavior": _projectile_behavior.duplicate(true),
		"secondary_gun_count": _secondary_guns.size(),
		"has_model": _visual_root != null,
		"render_layers": render_layers,
		"is_3d": true,
	}


func _finish_reload() -> void:
	current_ammo = magazine_size
	_reload_remaining = 0.0
	reload_progress_changed.emit(1.0, 0.0)
	_active_reload_duration = 0.0
	ammo_changed.emit(current_ammo, magazine_size)
	reload_ended.emit(true)


func _perform_reload_explosion() -> void:
	if not bool(_projectile_behavior.get("explode_on_reload", false)):
		return
	var player := _find_owner_player()
	if player == null:
		return
	var radius := maxf(1.0, float(_projectile_behavior.get("explosion_radius", 150.0)) / 30.0)
	var damage_scale := float(_projectile_behavior.get("explosion_damage_scale", 0.8))
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		var enemy := value as Enemy3D
		if enemy == null or enemy.ai_state == "dead" or player.global_position.distance_to(enemy.global_position) > radius:
			continue
		enemy.notify_attacked_by(player)
		enemy.take_damage(maxi(1, int(damage * damage_scale)), false, (enemy.global_position - player.global_position).normalized())
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire("explosion", bullet_color, radius * 0.35, player.global_position)


func _find_owner_player() -> Player3D:
	var node := get_parent()
	while node != null:
		if node is Player3D:
			return node as Player3D
		node = node.get_parent()
	return null


func _rebuild_visual() -> void:
	if not is_inside_tree():
		return
	if _visual_root != null:
		_visual_root.queue_free()
	_visual_root = Node3D.new()
	_visual_root.name = "MeleeVisual" if is_melee_weapon() else "GunVisual"
	add_child(_visual_root)
	_visual_root.scale = Vector3.ONE * clampf(float(_projectile_behavior.get("fate_scale", 1.0)), 0.45, 2.5)
	if is_melee_weapon():
		var melee_scene := MELEE_VISUAL_SCENES.get(gun_id) as PackedScene
		if melee_scene != null:
			var melee_visual := melee_scene.instantiate() as Node3D
			_visual_root.add_child(melee_visual)
			if melee_visual.has_method("configure"):
				melee_visual.call("configure", render_layers)
		_muzzle = null
		return
	var profile: Dictionary = GUN_PROFILES.get(gun_id, GUN_PROFILES["bp_pistol"])
	var length := float(profile["length"])
	var barrel := float(profile["barrel"])
	var width := float(profile["width"])
	var height := float(profile["height"])
	var body_color := profile["color"] as Color
	var body_material := _material(body_color, 0.72, 0.34)
	var dark_material := _material(Color(0.055, 0.07, 0.07), 0.84, 0.28)
	var accent_material := _material(bullet_color.darkened(0.14), 0.32, 0.30, true)
	var imported_scene := GUN_VISUAL_SCENES.get(gun_id) as PackedScene
	if imported_scene != null:
		var imported_asset := imported_scene.instantiate() as Node3D
		_visual_root.add_child(imported_asset)
		_apply_render_layers_recursive(imported_asset)
		_muzzle = imported_asset.get_node_or_null("MuzzleSocket") as Marker3D
		_add_imported_attachment_visuals(imported_asset, accent_material)
		return
	_add_box("Receiver", Vector3(0, 0, -length * 0.42), Vector3(width, height, length), body_material)
	_add_box("Stock", Vector3(0, -0.03, 0.14), Vector3(width * 0.82, height * 0.82, length * 0.34), dark_material)
	_add_box("Grip", Vector3(0, -height * 0.55, -length * 0.30), Vector3(width * 0.48, height * 0.75, 0.18), dark_material)
	_add_cylinder("Barrel", Vector3(0, 0.01, -length - barrel * 0.48), width * (0.26 if gun_id != "bp_launcher" else 0.52), barrel, dark_material)
	if gun_id in ["bp_sniper", "bp_charge"]:
		_add_cylinder("Optic", Vector3(0, height * 0.72, -length * 0.55), width * 0.22, length * 0.48, accent_material)
	if gun_id == "bp_machinegun":
		_add_box("AmmoBox", Vector3(width * 0.70, -height * 0.18, -length * 0.45), Vector3(width * 0.72, height * 1.05, length * 0.42), accent_material)
	if gun_id == "bp_charge":
		for side in [-1.0, 1.0]:
			_add_cylinder("ChargeCoil", Vector3(width * side, 0, -length * 0.72), width * 0.18, length * 0.52, accent_material)
	if _source_tree != null and _source_tree.get_root() != null:
		var source_root := _source_tree.get_root()
		if source_root.slots.get(AssemblyNode.SlotType.MUZZLE) != null:
			_add_cylinder("InstalledMuzzle", Vector3(0, 0.01, -length - barrel * 0.96), width * 0.34, barrel * 0.44, accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.MAGAZINE) != null:
			_add_box("InstalledMagazine", Vector3(0, -height * 0.80, -length * 0.48), Vector3(width * 0.82, height * 1.10, length * 0.26), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.SCOPE) != null:
			_add_cylinder("InstalledScope", Vector3(0, height * 0.82, -length * 0.58), width * 0.22, length * 0.40, accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.STOCK) != null:
			_add_box("InstalledStock", Vector3(0, -0.03, length * 0.30), Vector3(width * 0.92, height * 0.92, length * 0.42), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.TACTICAL) != null:
			_add_box("InstalledTactical", Vector3(width * 0.70, -height * 0.06, -length * 0.62), Vector3(width * 0.32, height * 0.32, length * 0.28), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.MUTATOR) != null:
			_add_box("InstalledMutator", Vector3(-width * 0.56, height * 0.10, -length * 0.42), Vector3(width * 0.12, height * 0.54, length * 0.36), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.MOUNT) != null:
			_add_box("InstalledMount", Vector3(0, height * 0.78, -length * 0.48), Vector3(width * 0.60, height * 0.32, length * 0.30), accent_material)
	var fate_used := maxi(0, int(get_meta("fate_slot_used", 0)))
	for fate_index in mini(fate_used, 8):
		var row := fate_index / 4
		var column := fate_index % 4
		_add_box(
			"FateRune%02d" % (fate_index + 1),
			Vector3(width * (-0.66 + float(column) * 0.44), height * (0.52 - float(row) * 0.34), -length * 0.42),
			Vector3(width * 0.12, height * 0.12, length * 0.08),
			accent_material,
		)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, -length - barrel)
	_visual_root.add_child(_muzzle)


func _apply_render_layers_recursive(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		mesh_instance.layers = render_layers
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in root.get_children():
		_apply_render_layers_recursive(child)


func _socket_position(asset: Node3D, socket_name: String, fallback: Vector3) -> Vector3:
	var socket := asset.get_node_or_null(socket_name) as Marker3D
	return socket.position if socket != null else fallback


func _add_imported_attachment_visuals(asset: Node3D, accent_material: StandardMaterial3D) -> void:
	if _source_tree != null and _source_tree.get_root() != null:
		var source_root := _source_tree.get_root()
		if source_root.slots.get(AssemblyNode.SlotType.MUZZLE) != null:
			_add_cylinder("InstalledMuzzle", _socket_position(asset, "MuzzleAttachmentSocket", Vector3(0, 0, -0.75)), 0.055, 0.16, accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.MAGAZINE) != null:
			_add_box("InstalledMagazine", _socket_position(asset, "MagazineSocket", Vector3(0, -0.12, -0.20)), Vector3(0.14, 0.24, 0.18), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.SCOPE) != null:
			_add_cylinder("InstalledScope", _socket_position(asset, "ScopeSocket", Vector3(0, 0.24, -0.35)), 0.045, 0.28, accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.STOCK) != null:
			_add_box("InstalledStock", _socket_position(asset, "StockSocket", Vector3(0, 0.05, 0.25)), Vector3(0.22, 0.22, 0.32), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.TACTICAL) != null:
			_add_box("InstalledTactical", _socket_position(asset, "TacticalSocket", Vector3(0.14, 0.02, -0.35)), Vector3(0.08, 0.08, 0.20), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.MUTATOR) != null:
			_add_box("InstalledMutator", _socket_position(asset, "MutatorSocket", Vector3(-0.14, 0.02, -0.30)), Vector3(0.06, 0.16, 0.16), accent_material)
		if source_root.slots.get(AssemblyNode.SlotType.MOUNT) != null:
			_add_box("InstalledMount", _socket_position(asset, "ScopeSocket", Vector3(0, 0.24, -0.30)), Vector3(0.18, 0.08, 0.18), accent_material)
	var fate_used := maxi(0, int(get_meta("fate_slot_used", 0)))
	var rune_origin := _socket_position(asset, "MutatorSocket", Vector3(-0.14, 0.06, -0.28))
	for fate_index in mini(fate_used, 8):
		var row := fate_index / 4
		var column := fate_index % 4
		_add_box(
			"FateRune%02d" % (fate_index + 1),
			rune_origin + Vector3(float(column) * 0.035, float(row) * -0.035, 0.0),
			Vector3(0.024, 0.024, 0.045),
			accent_material,
		)


func _spawn_muzzle_effect(world: Node) -> void:
	if _muzzle == null:
		return
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire("muzzle", bullet_color, 1.0, _muzzle.global_position)
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure("muzzle", bullet_color, 1.0)
	world.add_child(effect)
	effect.global_position = _muzzle.global_position


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	instance.layers = render_layers
	# 手持武器与角色相同：允许太阳/房间灯投影；玩家灯通过层遮罩避开 layer 2。
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_visual_root.add_child(instance)


func _add_cylinder(node_name: String, position: Vector3, radius: float, length: float, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 14
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees.x = 90.0
	instance.mesh = mesh
	instance.layers = render_layers
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_visual_root.add_child(instance)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	return material
