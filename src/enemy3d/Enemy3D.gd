class_name Enemy3D
extends CharacterBody3D
## 3D 敌人统一有限状态机。不同怪物只配置参数和攻击策略，不复制生命、寻路、受击或死亡逻辑。

signal killed(enemy: Enemy3D, loot: Dictionary)
signal summon_requested(enemy: Enemy3D, count: int)
signal state_changed(previous: String, current: String)
signal boss_phase_changed(enemy: Enemy3D, phase: int)
signal health_changed(enemy: Enemy3D, current: int, maximum: int)

const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")
const VALID_STATES := ["idle", "patrol", "alert", "chase", "search", "telegraph", "attack", "stagger", "dead"]
const NORMAL_HP_MULTIPLIER := 3.0
const BOSS_HP_MULTIPLIER := 10.0
const GLOBAL_MOVE_SPEED_MULTIPLIER := 0.70
const BOSS_SIZE_MULTIPLIER := 2.0
const BOSS_HEALTH_BAR_SIZE := Vector2(3.4, 0.28)

const PROFILES := {
	"melee_chaser": {"hp": 58, "speed": 3.7, "damage": 12, "range": 1.90, "cooldown": 1.05},
	"ranged_caster": {"hp": 46, "speed": 2.25, "damage": 10, "range": 8.8, "cooldown": 1.8},
	"summoner": {"hp": 72, "speed": 1.65, "damage": 8, "range": 7.2, "cooldown": 4.8},
	"shielded": {"hp": 112, "speed": 2.0, "damage": 17, "range": 2.05, "cooldown": 1.55},
	"exploder": {"hp": 42, "speed": 3.1, "damage": 30, "range": 2.85, "cooldown": 3.0},
	"ambusher": {"hp": 50, "speed": 4.65, "damage": 18, "range": 2.15, "cooldown": 1.9},
	"boss": {"hp": 520, "speed": 1.72, "damage": 24, "range": 9.5, "cooldown": 1.45},
}

# MonsterInjector 的旧 2D 基线只用于还原楼层、主题、精英与小怪倍率；
# 实际 3D TTK 必须建立在上面的 PROFILES 上，避免 10–40 HP 覆盖 3D 战斗基线。
const SOURCE_HP_BASE := {
	"melee_chaser": 25.0, "ranged_caster": 15.0, "summoner": 30.0,
	"shielded": 40.0, "exploder": 10.0, "ambusher": 18.0, "boss": 200.0,
}
const SOURCE_DAMAGE_BASE := {
	"melee_chaser": 5.0, "ranged_caster": 8.0, "summoner": 0.0,
	"shielded": 3.0, "exploder": 15.0, "ambusher": 7.0, "boss": 20.0,
}

@export_enum("melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher", "boss") var enemy_kind := "melee_chaser"
@export var room_id := ""

var max_hp := 58
var current_hp := 58
var move_speed := 3.7
var contact_damage := 12
var attack_range := 1.35
var attack_cooldown := 1.05
var ai_state := "idle"
var _state_time := 0.0
var _attack_timer := 0.0
var _slow_factor := 1.0
var _slow_timer := 0.0
var _target: Node3D = null
var _last_hit_direction := Vector3.ZERO
var _summon_count := 0
var _external_velocity := Vector3.ZERO
var _external_timer := 0.0
var _dot_damage := 0
var _dot_remaining := 0.0
var _dot_tick := 0.0
var enemy_data: Dictionary = {}
var _lost_sight_time := 0.0
var _last_known_target_position := Vector3.ZERO
var _home_position := Vector3.ZERO
var _home_initialized := false
var _runtime_ai_active := true
var _patrol_target := Vector3.ZERO
var elite_modifier_id := ""
var _absorb_cooldown := 0.0
var boss_phase := 1
var _ambush_triggered := false
var _strafe_sign := 1.0
var _bypass_shield_once := false
var _source_hp_scale := 1.0
var _source_damage_scale := 1.0
var _overhead_health_root: Node3D
var _overhead_health_fill: MeshInstance3D

@onready var avatar: EnemyAvatar3D = $Avatar
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("enemy_3d")
	add_to_group("damageable_3d")
	collision_layer = 4
	collision_mask = 1
	apply_profile(enemy_kind)
	health_changed.connect(_on_self_health_changed)
	transition_to("idle")


func apply_profile(kind: String) -> void:
	enemy_kind = kind if PROFILES.has(kind) else "melee_chaser"
	var profile: Dictionary = PROFILES[enemy_kind]
	var hp_multiplier := BOSS_HP_MULTIPLIER if enemy_kind == "boss" else NORMAL_HP_MULTIPLIER
	max_hp = int(round(float(profile["hp"]) * hp_multiplier))
	current_hp = max_hp
	move_speed = float(profile["speed"]) * GLOBAL_MOVE_SPEED_MULTIPLIER
	contact_damage = int(profile["damage"])
	attack_range = float(profile["range"])
	attack_cooldown = float(profile["cooldown"])
	if collision_shape != null:
		var footprint := EnemyAvatar3D.get_footprint_profile(enemy_kind)
		var shape := CylinderShape3D.new()
		shape.radius = float(footprint.get("radius", 0.8))
		shape.height = float(footprint.get("height", 1.2))
		collision_shape.shape = shape
		collision_shape.position.y = shape.height * 0.5
	if avatar != null:
		avatar.configure(enemy_kind)
		avatar.set_ambush_revealed(enemy_kind != "ambusher" or _ambush_triggered)
	_strafe_sign = -1.0 if get_instance_id() % 2 == 0 else 1.0


func configure_from_enemy_data(data: Dictionary) -> void:
	enemy_data = data.duplicate(true)
	apply_profile(str(data.get("enemy_type", enemy_kind)))
	var profile_hp := max_hp
	var profile_damage := contact_damage
	var source_hp_base := float(SOURCE_HP_BASE.get(enemy_kind, profile_hp))
	var source_max_hp := maxf(1.0, float(data.get("max_hp", data.get("hp", source_hp_base))))
	var source_current_hp := clampf(float(data.get("hp", source_max_hp)), 0.0, source_max_hp)
	_source_hp_scale = maxf(0.05, source_max_hp / maxf(1.0, source_hp_base))
	max_hp = maxi(1, int(round(float(profile_hp) * _source_hp_scale)))
	current_hp = clampi(int(round(float(max_hp) * source_current_hp / source_max_hp)), 1, max_hp)
	var source_damage_base := float(SOURCE_DAMAGE_BASE.get(enemy_kind, profile_damage))
	var source_damage := float(data.get("damage", source_damage_base))
	_source_damage_scale = (
		maxf(0.0, source_damage / source_damage_base)
		if source_damage_base > 0.0
		else 1.0
	)
	contact_damage = maxi(0, int(round(float(profile_damage) * _source_damage_scale)))
	# 2D px/s 按24 px/m适配到3D，再统一降到旧速度的70%。使用原始Profile
	# 作为缺省值，避免apply_profile已经降速后被重复乘0.7。
	var source_speed := float(data.get("speed", float(PROFILES[enemy_kind]["speed"]) * 24.0))
	move_speed = maxf(0.35, source_speed / 24.0 * GLOBAL_MOVE_SPEED_MULTIPLIER)
	if bool(data.get("is_elite", false)):
		elite_modifier_id = str(data.get("modifier_id_en", "Elite.Huge"))
		var modifier_data := data.get("modifier_data", {}) as Dictionary
		if elite_modifier_id == "Elite.Huge":
			var hp_mult := float(modifier_data.get("hp_mult", 2.0))
			max_hp = int(max_hp * hp_mult)
			current_hp = max_hp
			move_speed *= float(modifier_data.get("speed_mult", 0.8))
			scale *= float(modifier_data.get("scale_mult", 1.5))
		else:
			scale *= 1.16
	if enemy_kind == "boss":
		scale *= float(data.get("boss_scale", 1.0)) * BOSS_SIZE_MULTIPLIER
		_ensure_boss_overhead_health_bar()
	health_changed.emit(self, current_hp, max_hp)


func _ensure_boss_overhead_health_bar() -> void:
	if enemy_kind != "boss" or _overhead_health_root != null:
		return
	_overhead_health_root = Node3D.new()
	_overhead_health_root.name = "BossOverheadHealthBar"
	add_child(_overhead_health_root)
	var parent_scale := maxf(0.01, maxf(scale.x, maxf(scale.y, scale.z)))
	var footprint := EnemyAvatar3D.get_footprint_profile("boss")
	_overhead_health_root.position.y = float(footprint.get("height", 2.3)) + 0.62 / parent_scale
	_overhead_health_root.scale = Vector3.ONE / parent_scale
	var background := _create_health_bar_quad(
		"Background", BOSS_HEALTH_BAR_SIZE + Vector2(0.18, 0.14), Color(0.035, 0.015, 0.018, 0.94)
	)
	background.position.z = 0.01
	_overhead_health_root.add_child(background)
	_overhead_health_fill = _create_health_bar_quad(
		"HealthFill", BOSS_HEALTH_BAR_SIZE, Color(0.96, 0.055, 0.07, 1.0)
	)
	_overhead_health_fill.position.z = -0.01
	_overhead_health_root.add_child(_overhead_health_fill)
	_on_self_health_changed(self, current_hp, max_hp)


func _create_health_bar_quad(node_name: String, quad_size: Vector2, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.albedo_color = color
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _on_self_health_changed(_enemy: Enemy3D, current: int, maximum: int) -> void:
	if _overhead_health_fill == null:
		return
	var ratio := clampf(float(current) / float(maxi(1, maximum)), 0.0, 1.0)
	_overhead_health_fill.scale.x = ratio
	_overhead_health_fill.position.x = -BOSS_HEALTH_BAR_SIZE.x * (1.0 - ratio) * 0.5


func get_enemy_data() -> Dictionary:
	var result := enemy_data.duplicate(true)
	if result.is_empty():
		result = {"enemy_type": enemy_kind, "floor": 1, "loot_table": "loot_floor_1_2"}
	return result


func set_runtime_active(active: bool, presentation_ready_when_inactive := false) -> void:
	# 已开启门后的邻房会预先显示敌人，但在玩家正式进入前暂停 AI。
	# process_mode 不能在可见邻房设为 DISABLED：PlayerVision3D 会把它解释为
	# 未加载目标并强制隐藏。改为单独暂停物理 AI，让视野系统仍可正常判定显隐。
	_runtime_ai_active = active
	# 邻房目标先交给 PlayerVision3D 做距离/遮挡判定，避免刚生成的一帧穿墙闪现。
	visible = active
	process_mode = (
		Node.PROCESS_MODE_INHERIT
		if active or presentation_ready_when_inactive
		else Node.PROCESS_MODE_DISABLED
	)
	set_physics_process(active)


func is_runtime_ai_active() -> bool:
	return _runtime_ai_active


func _physics_process(delta: float) -> void:
	if not _home_initialized:
		_home_position = global_position
		_home_initialized = true
	_state_time += delta
	_absorb_cooldown = maxf(0.0, _absorb_cooldown - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_slow_timer = maxf(0.0, _slow_timer - delta)
	_external_timer = maxf(0.0, _external_timer - delta)
	if _external_timer <= 0.0:
		_external_velocity = Vector3.ZERO
	_tick_damage_over_time(delta)
	if _slow_timer <= 0.0:
		_slow_factor = 1.0
	if ai_state == "dead":
		velocity = Vector3.ZERO
		return
	if _target == null or not is_instance_valid(_target) or _target.get("current_hp") <= 0:
		_target = _find_target()
	if _target == null:
		if ai_state == "idle" and _state_time > 2.2:
			transition_to("patrol")
		if ai_state == "patrol":
			_tick_patrol(delta)
		else:
			transition_to("idle")
			velocity = velocity.move_toward(Vector3.ZERO, delta * 10.0)
			move_and_slide()
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var target_visible := _has_line_of_sight(_target)
	if enemy_kind == "ambusher" and not _ambush_triggered:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 16.0)
		avatar.set_ambush_revealed(false)
		if distance <= 4.4 or current_hp < max_hp:
			_ambush_triggered = true
			avatar.set_ambush_revealed(true)
			transition_to("telegraph")
		else:
			move_and_slide()
			return
	if target_visible:
		_last_known_target_position = _target.global_position
		_lost_sight_time = 0.0
	else:
		_lost_sight_time += delta
		if ai_state == "idle" and _state_time > 2.2:
			transition_to("patrol")
	if distance < 13.5 and ai_state in ["idle", "patrol", "search"] and target_visible:
		transition_to("alert")
	if ai_state == "alert" and _state_time > 0.28:
		transition_to("chase")
	match ai_state:
		"chase":
			if _lost_sight_time > 1.15:
				transition_to("search")
			else:
				_tick_chase(to_target, distance, delta)
		"search":
			_tick_search(delta)
		"patrol":
			_tick_patrol(delta)
		"telegraph":
			velocity = velocity.move_toward(Vector3.ZERO, delta * 18.0) + _external_velocity
			move_and_slide()
			if _state_time >= _telegraph_duration():
				transition_to("attack")
		"attack":
			_perform_attack(to_target, distance)
			transition_to("chase")
		"stagger":
			velocity = _last_hit_direction * 1.6
			move_and_slide()
			if _state_time > 0.16:
				transition_to("chase")
	if to_target.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), minf(1.0, delta * 8.0))


func _tick_chase(to_target: Vector3, distance: float, delta: float) -> void:
	if distance <= attack_range and _attack_timer <= 0.0:
		transition_to("telegraph")
		return
	var desired := to_target.normalized() * move_speed * _slow_factor
	if enemy_kind in ["ranged_caster", "summoner", "boss"]:
		var radial := to_target.normalized()
		var tangent := Vector3(-radial.z, 0, radial.x) * _strafe_sign
		var ideal_distance := attack_range * (0.78 if enemy_kind != "summoner" else 0.86)
		var radial_weight := clampf((distance - ideal_distance) / maxf(1.0, ideal_distance), -1.0, 1.0)
		desired = (tangent * 0.78 + radial * radial_weight).normalized() * move_speed * _slow_factor
		if distance < attack_range * 0.52:
			desired = (-radial * 0.82 + tangent * 0.35).normalized() * move_speed * _slow_factor
	velocity = velocity.lerp(desired, minf(1.0, delta * 5.5)) + _external_velocity
	move_and_slide()


func _tick_search(delta: float) -> void:
	var offset := _last_known_target_position - global_position
	offset.y = 0.0
	if offset.length() > 0.65:
		velocity = velocity.lerp(offset.normalized() * move_speed * 0.72, minf(1.0, delta * 4.0))
		move_and_slide()
	else:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 8.0)
		move_and_slide()
	if _state_time > 2.4:
		_target = null
		transition_to("patrol")


func _tick_patrol(delta: float) -> void:
	if _patrol_target == Vector3.ZERO or global_position.distance_to(_patrol_target) < 0.55:
		var angle := fmod(float(get_instance_id() % 97) * 0.73 + Time.get_ticks_msec() * 0.0003, TAU)
		_patrol_target = _home_position + Vector3(cos(angle), 0, sin(angle)) * 1.7
	var offset := _patrol_target - global_position
	offset.y = 0.0
	velocity = velocity.lerp(offset.normalized() * move_speed * 0.32, minf(1.0, delta * 3.2))
	move_and_slide()


func _has_line_of_sight(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.72, 0),
		target.global_position + Vector3(0, 0.72, 0),
		1,
		[get_rid()]
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == target or (collider != null and target.is_ancestor_of(collider))


func _perform_attack(to_target: Vector3, distance: float) -> void:
	_attack_timer = attack_cooldown
	match enemy_kind:
		"ranged_caster":
			_fire_projectile_volley(to_target, contact_damage, Color(0.20, 0.82, 0.92), 3, 0.18)
		"summoner":
			_summon_count += 1
			summon_requested.emit(self, 2 if _summon_count % 2 == 1 else 1)
			_heal_nearby_allies()
		"exploder":
			_explode()
		"boss":
			_fire_projectile_volley(to_target, contact_damage, Color(1.0, 0.20, 0.08), 3 if boss_phase >= 2 else 1, 0.14, true)
			if _summon_count % 3 == 2:
				summon_requested.emit(self, 2)
			_summon_count += 1
		"melee_chaser":
			_external_velocity = to_target.normalized() * 7.2
			_external_timer = 0.16
			if distance <= attack_range + 0.65 and _target.has_method("take_damage"):
				_target.call("take_damage", contact_damage, false, to_target.normalized())
		"ambusher":
			_external_velocity = to_target.normalized() * 9.4
			_external_timer = 0.28
			if distance <= attack_range + 1.0 and _target.has_method("take_damage"):
				_target.call("take_damage", contact_damage, false, to_target.normalized())
		_:
			if distance <= attack_range + 0.65 and _target.has_method("take_damage"):
				_target.call("take_damage", contact_damage, false, to_target.normalized())
	if elite_modifier_id == "Elite.WeaponParasite" and _target != null and _target.has_method("apply_silence"):
		_target.call("apply_silence", 1.8)


func _fire_projectile(to_target: Vector3, amount: int, color: Color, explosive := false) -> void:
	if get_tree().current_scene == null:
		return
	var config := {
		"direction": to_target.normalized(), "speed": 11.5, "damage": amount,
		"hostile": true, "critical": false, "tags": ["explosive"] if explosive else [],
		"color": color, "shooter": self,
	}
	var world_position := global_position + Vector3(0, 0.92, 0) + to_target.normalized() * 0.72
	var pools := get_tree().get_nodes_in_group("projectile_pool_3d")
	if not pools.is_empty() and pools[0] is ProjectilePool3D:
		(pools[0] as ProjectilePool3D).acquire(config, world_position)
	else:
		var projectile := PROJECTILE_SCRIPT.new() as Projectile3D
		projectile.configure(config)
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = world_position


func _fire_projectile_volley(
	to_target: Vector3,
	amount: int,
	color: Color,
	count: int,
	spread_radians: float,
	explosive := false
) -> void:
	var shot_count := maxi(1, count)
	for index in range(shot_count):
		var ratio := 0.5 if shot_count == 1 else float(index) / float(shot_count - 1)
		var angle := lerpf(-spread_radians, spread_radians, ratio)
		_fire_projectile(to_target.rotated(Vector3.UP, angle), amount, color, explosive)


func _heal_nearby_allies() -> void:
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		var ally := value as Enemy3D
		if ally == null or ally == self or ally.room_id != room_id or ally.ai_state == "dead":
			continue
		if global_position.distance_to(ally.global_position) <= 6.5:
			ally.receive_healing(maxi(2, int(ally.max_hp * 0.08)))


func receive_healing(amount: int) -> void:
	if ai_state == "dead" or current_hp >= max_hp:
		return
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	health_changed.emit(self, current_hp, max_hp)
	_spawn_effect("damage", 0.52)


func _explode() -> void:
	_spawn_effect("explosion", 1.75)
	for player in get_tree().get_nodes_in_group("player_3d"):
		if player is Node3D and global_position.distance_to((player as Node3D).global_position) <= 3.0 and player.has_method("take_damage"):
			player.call("take_damage", contact_damage, false, ((player as Node3D).global_position - global_position).normalized())
	_die()


func take_damage(amount: int, critical := false, hit_direction := Vector3.ZERO) -> void:
	if ai_state == "dead":
		return
	var applied := maxi(1, amount)
	if elite_modifier_id == "Elite.Ricochet" and randf() < 0.30:
		applied = maxi(1, int(applied * 0.5))
		if _target != null and _target.has_method("take_damage"):
			_target.call("take_damage", maxi(1, int(amount * 0.35)), false, -hit_direction)
	if enemy_kind == "shielded" and not _bypass_shield_once and hit_direction.dot(-global_basis.z) < -0.15:
		if randf() < 0.15:
			avatar.flash_hit()
			_spawn_effect("impact", 0.82)
			return
		applied = maxi(1, int(applied * 0.32))
	if critical:
		applied = maxi(1, int(applied * 1.5))
	current_hp = maxi(0, current_hp - applied)
	health_changed.emit(self, current_hp, max_hp)
	_update_boss_phase()
	_last_hit_direction = hit_direction
	avatar.flash_hit()
	_spawn_effect("damage", 0.72)
	if current_hp <= 0:
		_die()
	else:
		if AudioManager != null:
			if critical:
				AudioManager.play_crit_sfx()
			else:
				AudioManager.play_enemy_hit_sfx()
		transition_to("stagger")


func take_projectile_damage(
	amount: int,
	critical := false,
	hit_direction := Vector3.ZERO,
	tags: Array[String] = [],
	behavior: Dictionary = {}
) -> void:
	_bypass_shield_once = (
		"armor" in tags
		or "piercing" in tags
		or bool(behavior.get("pierce_shield", false))
	)
	take_damage(amount, critical, hit_direction)
	_bypass_shield_once = false


func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = clampf(factor, 0.25, 1.0)
	_slow_timer = maxf(_slow_timer, duration)


func apply_pull(origin: Vector3, strength: float) -> void:
	var direction := origin - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	_external_velocity = direction.normalized() * clampf(strength, 0.5, 9.0)
	_external_timer = 0.32


func apply_damage_over_time(total_damage: int, duration: float) -> void:
	_dot_damage = maxi(_dot_damage, maxi(1, total_damage))
	_dot_remaining = maxf(_dot_remaining, maxf(0.5, duration))
	_dot_tick = minf(_dot_tick, 0.35)


func _tick_damage_over_time(delta: float) -> void:
	if _dot_remaining <= 0.0 or ai_state == "dead":
		return
	_dot_remaining = maxf(0.0, _dot_remaining - delta)
	_dot_tick -= delta
	if _dot_tick > 0.0:
		return
	_dot_tick = 0.5
	current_hp = maxi(0, current_hp - maxi(1, int(ceil(float(_dot_damage) * 0.2))))
	health_changed.emit(self, current_hp, max_hp)
	avatar.flash_hit()
	if current_hp <= 0:
		_die()


func transition_to(state_id: String) -> bool:
	if not VALID_STATES.has(state_id) or ai_state == "dead" and state_id != "dead":
		return false
	if ai_state == state_id:
		return true
	var previous := ai_state
	ai_state = state_id
	_state_time = 0.0
	if avatar != null:
		avatar.set_ai_state(state_id)
	state_changed.emit(previous, state_id)
	return true


func get_state_snapshot() -> Dictionary:
	var shape_snapshot := {}
	if collision_shape != null and collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		shape_snapshot = {"radius": cylinder.radius, "height": cylinder.height}
	return {
		"enemy_kind": enemy_kind, "state": ai_state, "valid_states": VALID_STATES.duplicate(),
		"hp": current_hp, "max_hp": max_hp, "room_id": room_id, "is_3d": true,
		"elite_modifier_id": elite_modifier_id, "boss_phase": boss_phase,
		"source_hp_scale": _source_hp_scale, "source_damage_scale": _source_damage_scale,
		"hp_balance_multiplier": BOSS_HP_MULTIPLIER if enemy_kind == "boss" else NORMAL_HP_MULTIPLIER,
		"move_speed_multiplier": GLOBAL_MOVE_SPEED_MULTIPLIER,
		"boss_size_multiplier": BOSS_SIZE_MULTIPLIER if enemy_kind == "boss" else 1.0,
		"world_collision_radius": float(shape_snapshot.get("radius", 0.0)) * scale.x,
		"overhead_health_bar": _overhead_health_root != null,
		"collision_profile": shape_snapshot,
		"ambush_triggered": _ambush_triggered,
		"behavior_role": _behavior_role(),
		"component_snapshot": avatar.get_component_snapshot() if avatar != null else {},
	}


func _behavior_role() -> String:
	return str({
		"melee_chaser": "rush_melee",
		"ranged_caster": "strafe_three_shot_volley",
		"summoner": "summon_and_heal_support",
		"shielded": "frontal_block_tank",
		"exploder": "proximity_charge_and_fragments",
		"ambusher": "buried_trigger_and_lunge",
		"boss": "phased_volley_and_summon",
	}.get(enemy_kind, "rush_melee"))


func _telegraph_duration() -> float:
	if enemy_kind == "exploder":
		return 0.9
	if enemy_kind == "ambusher":
		return 0.46
	if enemy_kind == "boss":
		return 0.62
	return 0.38


func _find_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("player_3d"):
		if not candidate is Node3D:
			continue
		var distance := global_position.distance_squared_to((candidate as Node3D).global_position)
		if distance < nearest_distance:
			nearest = candidate as Node3D
			nearest_distance = distance
	return nearest


func _die() -> void:
	if ai_state == "dead":
		return
	transition_to("dead")
	if AudioManager != null:
		AudioManager.play_enemy_die_sfx()
	if elite_modifier_id == "Elite.SpawnOnDeath":
		summon_requested.emit(self, 3)
	elif elite_modifier_id == "Elite.Parasite":
		_strengthen_nearest_enemy()
	if enemy_kind == "exploder":
		_spawn_death_fragments()
	collision_layer = 0
	collision_mask = 0
	_spawn_effect("explosion" if enemy_kind == "boss" else "impact", 1.4 if enemy_kind == "boss" else 0.8)
	killed.emit(self, get_enemy_data())
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.25, 0.05, 1.25), 0.34)
	tween.tween_callback(queue_free)


func _spawn_death_fragments() -> void:
	for index in range(8):
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / 8.0)
		_fire_projectile(direction, maxi(3, int(contact_damage * 0.28)), Color(1.0, 0.42, 0.10))


func can_absorb_projectile(_tags: Array[String]) -> bool:
	return elite_modifier_id == "Elite.BulletEater" and _absorb_cooldown <= 0.0


func on_projectile_absorbed(absorbed_damage: int) -> void:
	_absorb_cooldown = 0.75
	if _target != null:
		_fire_projectile(
			_target.global_position - global_position,
			maxi(4, absorbed_damage / 2),
			Color(0.78, 0.28, 0.94)
		)


func apply_elite_boon(multiplier: float) -> void:
	max_hp = int(max_hp * multiplier)
	current_hp = mini(max_hp, int(current_hp * multiplier + max_hp * 0.15))
	contact_damage = int(contact_damage * multiplier)
	move_speed *= minf(1.2, multiplier)
	scale *= 1.08


func _strengthen_nearest_enemy() -> void:
	var best: Enemy3D = null
	var best_distance := 12.0
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		var candidate := value as Enemy3D
		if candidate == null or candidate == self or candidate.ai_state == "dead":
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	if best != null:
		best.apply_elite_boon(1.3)


func _update_boss_phase() -> void:
	if enemy_kind != "boss" or max_hp <= 0:
		return
	var ratio := float(current_hp) / float(max_hp)
	var next_phase := 3 if ratio <= 0.30 else 2 if ratio <= 0.65 else 1
	if next_phase <= boss_phase:
		return
	boss_phase = next_phase
	attack_cooldown *= 0.82
	move_speed *= 1.10
	if boss_phase == 3:
		summon_requested.emit(self, 3)
	boss_phase_changed.emit(self, boss_phase)


func _spawn_effect(kind: String, size: float) -> void:
	if get_tree().current_scene == null:
		return
	var world_position := global_position + Vector3(0, 0.65, 0)
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire(
			kind, EnemyAvatar3D.COLORS.get(enemy_kind, Color.WHITE), size, world_position
		)
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(kind, EnemyAvatar3D.COLORS.get(enemy_kind, Color.WHITE), size)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position
