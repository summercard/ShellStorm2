class_name Enemy3D
extends CharacterBody3D
## 3D 敌人统一有限状态机。不同怪物只配置参数和攻击策略，不复制生命、寻路、受击或死亡逻辑。

signal killed(enemy: Enemy3D, loot: Dictionary)
signal summon_requested(enemy: Enemy3D, count: int)
signal state_changed(previous: String, current: String)

const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")
const VALID_STATES := ["idle", "alert", "chase", "telegraph", "attack", "stagger", "dead"]

const PROFILES := {
	"melee_chaser": {"hp": 58, "speed": 3.7, "damage": 12, "range": 1.35, "cooldown": 1.05},
	"ranged_caster": {"hp": 46, "speed": 2.25, "damage": 10, "range": 8.8, "cooldown": 1.8},
	"summoner": {"hp": 72, "speed": 1.65, "damage": 8, "range": 7.2, "cooldown": 4.8},
	"shielded": {"hp": 112, "speed": 2.0, "damage": 17, "range": 1.55, "cooldown": 1.55},
	"exploder": {"hp": 42, "speed": 3.1, "damage": 30, "range": 2.45, "cooldown": 3.0},
	"ambusher": {"hp": 50, "speed": 4.65, "damage": 18, "range": 1.65, "cooldown": 1.9},
	"boss": {"hp": 520, "speed": 1.72, "damage": 24, "range": 9.5, "cooldown": 1.45},
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

@onready var avatar: EnemyAvatar3D = $Avatar
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("enemy_3d")
	add_to_group("damageable_3d")
	collision_layer = 4
	collision_mask = 1
	apply_profile(enemy_kind)
	transition_to("idle")


func apply_profile(kind: String) -> void:
	enemy_kind = kind if PROFILES.has(kind) else "melee_chaser"
	var profile: Dictionary = PROFILES[enemy_kind]
	max_hp = int(profile["hp"])
	current_hp = max_hp
	move_speed = float(profile["speed"])
	contact_damage = int(profile["damage"])
	attack_range = float(profile["range"])
	attack_cooldown = float(profile["cooldown"])
	if collision_shape != null:
		var shape := collision_shape.shape as CapsuleShape3D
		shape = shape.duplicate() as CapsuleShape3D
		shape.radius = 1.05 if enemy_kind == "boss" else 0.56
		shape.height = 2.1 if enemy_kind == "boss" else 1.2
		collision_shape.shape = shape
		collision_shape.position.y = shape.height * 0.5
	if avatar != null:
		avatar.configure(enemy_kind)


func _physics_process(delta: float) -> void:
	_state_time += delta
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
		transition_to("idle")
		velocity = velocity.move_toward(Vector3.ZERO, delta * 10.0)
		move_and_slide()
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance < 13.5 and ai_state == "idle":
		transition_to("alert")
	if ai_state == "alert" and _state_time > 0.28:
		transition_to("chase")
	match ai_state:
		"chase":
			_tick_chase(to_target, distance, delta)
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
	if enemy_kind in ["ranged_caster", "summoner", "boss"] and distance < attack_range * 0.58:
		desired = -to_target.normalized() * move_speed * 0.64
	velocity = velocity.lerp(desired, minf(1.0, delta * 5.5)) + _external_velocity
	move_and_slide()


func _perform_attack(to_target: Vector3, distance: float) -> void:
	_attack_timer = attack_cooldown
	match enemy_kind:
		"ranged_caster":
			_fire_projectile(to_target, contact_damage, Color(0.20, 0.82, 0.92))
		"summoner":
			_summon_count += 1
			summon_requested.emit(self, 2 if _summon_count % 2 == 1 else 1)
		"exploder":
			_explode()
		"boss":
			_fire_projectile(to_target, contact_damage, Color(1.0, 0.20, 0.08), true)
			if _summon_count % 3 == 2:
				summon_requested.emit(self, 2)
			_summon_count += 1
		_:
			if distance <= attack_range + 0.65 and _target.has_method("take_damage"):
				_target.call("take_damage", contact_damage, false, to_target.normalized())


func _fire_projectile(to_target: Vector3, amount: int, color: Color, explosive := false) -> void:
	if get_tree().current_scene == null:
		return
	var projectile := PROJECTILE_SCRIPT.new() as Projectile3D
	projectile.configure({
		"direction": to_target.normalized(), "speed": 11.5, "damage": amount,
		"hostile": true, "critical": false, "tags": ["explosive"] if explosive else [],
		"color": color, "shooter": self,
	})
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3(0, 0.92, 0) + to_target.normalized() * 0.72


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
	if enemy_kind == "shielded" and hit_direction.dot(-global_basis.z) < -0.15:
		applied = maxi(1, int(applied * 0.32))
	if critical:
		applied = maxi(1, int(applied * 1.5))
	current_hp = maxi(0, current_hp - applied)
	_last_hit_direction = hit_direction
	avatar.flash_hit()
	_spawn_effect("damage", 0.72)
	if current_hp <= 0:
		_die()
	else:
		transition_to("stagger")


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
	return {
		"enemy_kind": enemy_kind, "state": ai_state, "valid_states": VALID_STATES.duplicate(),
		"hp": current_hp, "max_hp": max_hp, "room_id": room_id, "is_3d": true,
		"component_snapshot": avatar.get_component_snapshot() if avatar != null else {},
	}


func _telegraph_duration() -> float:
	if enemy_kind == "exploder":
		return 0.9
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
	collision_layer = 0
	collision_mask = 0
	_spawn_effect("explosion" if enemy_kind == "boss" else "impact", 1.4 if enemy_kind == "boss" else 0.8)
	killed.emit(self, {"scrap": 12 if enemy_kind == "boss" else 2, "kind": enemy_kind})
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.25, 0.05, 1.25), 0.34)
	tween.tween_callback(queue_free)


func _spawn_effect(kind: String, size: float) -> void:
	if get_tree().current_scene == null:
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(kind, EnemyAvatar3D.COLORS.get(enemy_kind, Color.WHITE), size)
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position + Vector3(0, 0.65, 0)
