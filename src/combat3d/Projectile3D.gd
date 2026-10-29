class_name Projectile3D
extends CharacterBody3D

signal hit_confirmed(target: Node, applied_damage: int, critical: bool)
signal expired
signal retired(projectile: Projectile3D)

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d.tscn")
const BULLET_VISUAL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn")
## 弹种专属弹体视觉路由（落地 04 §6.2「子弹模块必填 visual_id」）。
## 键 = 子弹模块 content_id（mod_bullet_*）；查不到即回落通用弹体 BULLET_VISUAL_SCENE。
## 八个弹种一条 Prefab 一个类，见 src/vfx/VfxBullet<Type>3D.gd 与账本「子弹特效」大类。
const BULLET_VISUAL_REGISTRY: Dictionary = {
	"fate_rock": preload("res://assets/art/vfx/combat_3d/vfx_fate_rock_root_top3d.tscn"),
	"mod_bullet_standard": preload("res://assets/art/vfx/combat_3d/vfx_bullet_standard_root_top3d.tscn"),
	"mod_bullet_sticky": preload("res://assets/art/vfx/combat_3d/vfx_bullet_sticky_root_top3d.tscn"),
	"mod_bullet_bounce": preload("res://assets/art/vfx/combat_3d/vfx_bullet_bounce_root_top3d.tscn"),
	"mod_bullet_piercing": preload("res://assets/art/vfx/combat_3d/vfx_bullet_piercing_root_top3d.tscn"),
	"mod_bullet_explosive": preload("res://assets/art/vfx/combat_3d/vfx_bullet_explosive_root_top3d.tscn"),
	"mod_bullet_homing": preload("res://assets/art/vfx/combat_3d/vfx_bullet_homing_root_top3d.tscn"),
	"mod_bullet_blackhole": preload("res://assets/art/vfx/combat_3d/vfx_bullet_blackhole_root_top3d.tscn"),
	"mod_bullet_balloon": preload("res://assets/art/vfx/combat_3d/vfx_bullet_balloon_root_top3d.tscn"),
}
## 旧链（CombatEffectPool3D）图例：爆炸仍走旧链，待 14.6 §6 迁移完成后统一删除。
const LEGACY_EFFECT_EXPLOSION := &"explosion"

## ── 命中特效路由（2026-10-14 业主「对击中特效进行区分」）────────────────────
## 打中「僵尸三兄弟」（`Enemy3D.ZOMBIE_KINDS` = 小僵尸 / 警察僵尸 / 胖子僵尸）
## ⇒ FX01-20 `VFX-GOO-HIT-3D`；打中**其余一切**（墙面 / 掩体 / 地面 / 非僵尸怪种）
## ⇒ FX01-21 `VFX-METAL-SPARK-HIT-3D`（5 颗白方块 + 2 根金色长条火星）。
##
## ⚠ 2026-10-14 第四轮业主：「小僵尸和警察僵尸的受击特效**太大了**，
## **使用击中其它物体的那个特效**，然后**改成绿色**即可，放大大概 **10%**」
## ⇒ FX01-20 升 v002：造型与 FX01-21 **逐字共用**（只换色板），尺寸改为**同档位 ×1.10**。
## 所以僵尸那一组不再是独立定档值，而是**派生**自金属火星那一组 —— 以后调金属火星的档位，
## 僵尸那条自动跟着走，不会又漂回「一个绿方块糊住半个怪」。
##
## 本口径**取代**再上一轮的「受击的特效也不要太大，我看到有点太大了，小一点」
## （当时把首版的 0.85 / 1.00 压到 0.50 / 0.60）。
##
## ⚠ 2026-10-15 第五轮业主：「击中僵尸的受击特效，**放大 50%**，包括胖子僵尸的；
## 击中普通物品的也**放大 50%**」⇒ 引入**唯一一个倍率旋钮** `HIT_EFFECT_SIZE_SCALE`。
## 它写在**金属火星那组基准值上**，僵尸那组是「金属 ×1.10」的派生值 ⇒ 一次改动同时覆盖
## 四条路（打僵尸 / 打普通物体 / 打墙面地面 / 链电反弹），不会漏掉某一路。
##
## 要再调大小**只动下面这一组数**，别去改特效内部的几何常量（那会连死亡件一起带动）。
const HIT_EFFECT_SIZE_SCALE := 1.5
const METAL_SPARK_SIZE_TARGET := 0.34 * HIT_EFFECT_SIZE_SCALE
const METAL_SPARK_SIZE_ABSORB := 0.42 * HIT_EFFECT_SIZE_SCALE
const METAL_SPARK_SIZE_SURFACE := 0.28 * HIT_EFFECT_SIZE_SCALE
const METAL_SPARK_SIZE_BOUNCE := 0.20 * HIT_EFFECT_SIZE_SCALE
const METAL_SPARK_SIZE_CHAIN := 0.26 * HIT_EFFECT_SIZE_SCALE
## 僵尸受击件（FX01-20）的同档位尺寸 = 金属火星 ×1.10。只在这里派生，别再手写定档值。
const ZOMBIE_HIT_SIZE_RATIO := 1.10
const GOO_HIT_SIZE_TARGET := METAL_SPARK_SIZE_TARGET * ZOMBIE_HIT_SIZE_RATIO
const GOO_HIT_SIZE_ABSORB := METAL_SPARK_SIZE_ABSORB * ZOMBIE_HIT_SIZE_RATIO

var _weapon_socket: Marker3D
var _carried_weapon: WeaponModel3D
var _rock_vertical_speed := 0.0
var _rock_shattered := false

var direction := Vector3(0, 0, -1)
var speed := 24.0
var damage := 10
var critical := false
var hostile := false
var bullet_tags: Array[String] = []
var bullet_color := Color(0.45, 0.88, 1.0)
## 当前已挂载的弹体视觉所用的 visual_id（"" = 通用弹体）。池化复借时按此判断要不要换视觉。
var _visual_id := ""
## 枪身维度的弹体几何档位（2026-10-14）。由 WeaponModel3D 随 projectile_config 下发，
## 键见 WeaponModel3D.BULLET_GEOMETRY_BY_GUN_TAG；空字典 = 中性档（不改观感）。
## 只影响弹体纯视觉的尺寸/拉伸/生长包络，不影响碰撞半径、伤害与射程。
var _gun_bullet_geometry: Dictionary = {}
var shooter: Node3D = null
var fate_behavior: Dictionary = {}
# 命中击退强度（m/s）。默认 0 = 不让怪物位移；霰弹枪=0.8（轻微）。
# 由 WeaponModel3D / 发射逻辑在 spawn 时赋值，命中时透传给 take_projectile_damage。
var hit_knockback := 0.0
## 射程上限（米），由枪身 base_stats 的 `range` 下发；`<= 0` 表示不启用（退回旧的「按存活时间」口径）。
## 与 `speed` 独立：改弹速只改飞行时间，不再连带改射程。
var range_m := 0.0
var _lifetime := 0.0
## 实际飞行路径长度（含反弹折线），用于判定射程上限。
var _traveled := 0.0
var _bounces_left := 0
var _pierces_left := 0
var _built := false
var _active := true
var _collision_shape: CollisionShape3D
var _visual: VfxEffectBase3D
var _returning := false
var _turret_active := false
var _turret_remaining := 0.0
var _turret_shot_timer := 0.0
var _attached_shot_timer := 0.0
var source_weapon_tree: WeaponAssemblyTree
var source_weapon: WeaponModel3D
var _flight_base_damage := 0
var _ungrown_damage := 0
var _hit_any := false
var _attached_hit_fired := false
var _return_hit_ids: Dictionary = {}
var _tracked_collision_exceptions: Array[PhysicsBody3D] = []
# 池引用缓存（零视觉损失）：命中特效 / 子投射物每次都要找个池；这三类池在战局里都是单例。
# `get_nodes_in_group` 每次都会新建数组，命中与炮台连发频率下是持续分配。
var _vfx_pool_cache: VfxPool3D
var _projectile_pool_cache: ProjectilePool3D
var _combat_effect_pool_cache: CombatEffectPool3D


func configure(config: Dictionary) -> void:
	direction = (config.get("direction", direction) as Vector3).normalized()
	speed = float(config.get("speed", speed))
	damage = int(config.get("damage", damage))
	critical = bool(config.get("critical", critical))
	hostile = bool(config.get("hostile", hostile))
	bullet_tags.assign(config.get("tags", []))
	bullet_color = config.get("color", bullet_color) as Color
	shooter = config.get("shooter", shooter) as Node3D
	fate_behavior = (config.get("behavior", {}) as Dictionary).duplicate(true)
	# 每次 configure 一律重取（缺省空字典 ⇒ 中性档），池化复借不得残留上一发的枪身档位。
	_gun_bullet_geometry = (config.get("gun_bullet_geometry", {}) as Dictionary).duplicate(true)
	var source_tree_value: Variant = fate_behavior.get("source_weapon_tree")
	var source_weapon_value: Variant = fate_behavior.get("source_weapon")
	source_weapon_tree = source_tree_value as WeaponAssemblyTree if is_instance_valid(source_tree_value) else null
	source_weapon = source_weapon_value as WeaponModel3D if is_instance_valid(source_weapon_value) else null
	_hit_any = false
	_rock_vertical_speed = 0.0
	_rock_shattered = false
	_ungrown_damage = damage
	_attached_hit_fired = false
	_return_hit_ids.clear()
	if bool(fate_behavior.get("size_growth", false)) and is_instance_valid(source_weapon_tree):
		var growth := minf(float(fate_behavior.get("max_fate_scale", 3.0)), 1.0 + source_weapon_tree.growth_stacks * float(fate_behavior.get("growth_per_hit", 0.2)))
		damage = maxi(1, int(damage * growth))
		var growth_size := minf(float(fate_behavior.get("max_fate_scale", 3.0)), 1.0 + source_weapon_tree.growth_stacks * float(fate_behavior.get("growth_scale_per_hit", 0.12)))
		fate_behavior["fate_scale"] = float(fate_behavior.get("fate_scale", 1.0)) * growth_size
	_flight_base_damage = damage
	damage = maxi(1, int(damage * float(fate_behavior.get("outbound_damage_multiplier", 1.0))))
	# 默认 0 = 不让怪物位移；霰弹枪在 WeaponModel3D 注入 0.8（轻微击退）。
	hit_knockback = float(config.get("hit_knockback", hit_knockback))
	# 射程上限（米）。0/缺省 = 不启用，保持旧行为（敌弹与旧内容不受影响）。
	range_m = maxf(0.0, float(config.get("range", 0.0)))
	_bounces_left = int(fate_behavior.get("bounce_count", 2 if bullet_tags.has("bounce") else 0))
	_pierces_left = int(fate_behavior.get("pierce_level", 2 if bullet_tags.has("piercing") else 0))
	_lifetime = 0.0
	_traveled = 0.0
	_returning = false
	_turret_active = false
	_turret_remaining = 0.0
	_turret_shot_timer = 0.0
	_attached_shot_timer = 0.12
	_sync_visual_route(config)
	if _built:
		_rebuild_carried_weapon()
		_apply_visual_configuration()
		_sync_visual_orientation()


func activate(config: Dictionary, world_position: Vector3) -> void:
	configure(config)
	collision_mask = 1 if hostile else 5
	for exception in _tracked_collision_exceptions:
		# 对象池保留的碰撞例外可能指向已死亡并释放的上一任发射者；Godot
		# 会把服务端列表中的对象变成null占位，连枚举都会触发body=null报错。
		if is_instance_valid(exception):
			remove_collision_exception_with(exception)
	_tracked_collision_exceptions.clear()
	if shooter is PhysicsBody3D:
		_add_tracked_collision_exception(shooter as PhysicsBody3D)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = world_position
	velocity = Vector3.ZERO
	_sync_visual_orientation()
	if _visual != null:
		_visual.activate(global_position, bullet_color, _visual_scale_factor(), _bullet_visual_context())
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 if hostile else 5
	if shooter is PhysicsBody3D:
		_add_tracked_collision_exception(shooter as PhysicsBody3D)
	_build_visual()
	_built = true
	_rebuild_carried_weapon()
	_apply_visual_configuration()
	_sync_visual_orientation()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _turret_active:
		_tick_turret(delta)
		return
	_lifetime += delta
	# 子弹最大存活时间：默认下限 1.0 秒；命运卡行为可注入更长的 home_lifetime（如追踪弹 5 秒）。
	# 有射程字段时，生存时间按「飞满射程」反推并留 50% 余量 —— 否则固定 1 秒会把远射武器提前掐断
	# （例：狙击 60 m ÷ 23 m·s⁻¹ = 2.6 s，远超 1 s）。距离本身仍由 `range_m` 判定，这里只是兜底。
	var max_lifetime := maxf(1.0, float(fate_behavior.get("home_lifetime", 1.0)))
	if range_m > 0.0:
		max_lifetime = maxf(max_lifetime, range_m / maxf(1.0, speed) * 1.5)
	if _lifetime >= max_lifetime:
		if not _returning and bool(fate_behavior.get("spawn_turret_on_land", false)):
			_become_turret()
		elif not _returning and bool(fate_behavior.get("home_on_land", false)):
			_begin_return()
		else:
			expired.emit()
			_retire()
		return
	_tick_attached_gun(delta)
	if _returning:
		if not is_instance_valid(shooter):
			_retire()
			return
		var destination := _return_destination()
		if global_position.distance_to(destination) <= maxf(0.72, speed * delta):
			if is_instance_valid(source_weapon):
				source_weapon.refund_projectile_ammo(int(fate_behavior.get("refund_ammo", 0)), source_weapon_tree)
			_retire()
			return
		direction = (destination - global_position).normalized()
	elif (bullet_tags.has("homing") or bool(fate_behavior.get("homing", false))) and not hostile:
		var target := _nearest_target()
		if target != null:
			var desired := (target.global_position + Vector3(0, 0.68, 0) - global_position).normalized()
			var homing_rate := lerpf(1.6, 7.0, clampf(float(fate_behavior.get("homing_strength", 0.3)), 0.0, 1.0))
			direction = direction.slerp(desired, minf(1.0, delta * homing_rate)).normalized()
	_sync_visual_orientation()
	velocity = direction * speed
	if bool(fate_behavior.get("rock_projectile", false)) and not _returning:
		_rock_vertical_speed -= 18.0 * delta
		velocity.y = _rock_vertical_speed
		if is_instance_valid(_visual):
			_visual.call("roll", speed * delta / 0.18)
	var step := velocity * delta
	# 射程上限：按实际飞行路径长度累计（含反弹折线）。榴弹类到点自动引爆，其余直接消失。
	# 回旋镖返航（_returning）不受射程限制，否则会被掐在半路。
	if not _returning and range_m > 0.0:
		_traveled += step.length()
		if _traveled >= range_m:
			if _is_explosive_payload():
				_explode()
			else:
				expired.emit()
			_retire()
			return
	var collision := move_and_collide(step)
	if collision == null:
		return
	# 物理命中上下文（先于反弹方向变化），供命中特效读取法线/接触点。
	var hit_context := {"normal": collision.get_normal(), "position": collision.get_position()}
	var collider := collision.get_collider() as Node
	if collider == shooter:
		return
	if collider != null and collider.has_method("take_damage"):
		_hit_target(collider, hit_context)
		return
	if bool(fate_behavior.get("rock_projectile", false)) and collision.get_normal().y > 0.55:
		_rock_vertical_speed = 0.0
		var planar := Vector3(direction.x, 0.0, direction.z).normalized() * speed * delta
		var ground_collision := move_and_collide(planar)
		if ground_collision != null:
			var obstacle := ground_collision.get_collider() as Node
			if obstacle != null and obstacle.has_method("take_damage"):
				_hit_target(obstacle)
			else:
				_hit_surface(ground_collision.get_normal())
		return
	_hit_surface(collision.get_normal(), hit_context)


func _hit_target(collider: Node, hit_context: Dictionary = {}) -> void:
	if not _active:
		return
	if _returning and (damage <= 0 or _return_hit_ids.has(collider.get_instance_id())):
		return
	if collider != null:
		if collider.has_method("can_absorb_projectile") and bool(collider.call("can_absorb_projectile", bullet_tags)):
			if collider.has_method("on_projectile_absorbed"):
				collider.call("on_projectile_absorbed", damage)
			_spawn_hit_effect(collider, GOO_HIT_SIZE_ABSORB, METAL_SPARK_SIZE_ABSORB, hit_context)
			if bool(fate_behavior.get("rock_shatter", false)):
				_shatter_rock()
			_retire()
			return
		if bool(fate_behavior.get("size_growth", false)) and is_instance_valid(source_weapon_tree):
			var growth := minf(float(fate_behavior.get("max_fate_scale", 3.0)), 1.0 + source_weapon_tree.growth_stacks * float(fate_behavior.get("growth_per_hit", 0.2)))
			_flight_base_damage = maxi(1, int(_ungrown_damage * growth))
			damage = maxi(0, int(_flight_base_damage * float(fate_behavior.get("return_damage_multiplier", 0.6)))) if _returning else maxi(1, int(_flight_base_damage * float(fate_behavior.get("outbound_damage_multiplier", 1.0))))
		_hit_any = true
		if _returning:
			_return_hit_ids[collider.get_instance_id()] = true
		if collider.has_method("take_projectile_damage"):
			collider.call("take_projectile_damage", damage, critical, direction, bullet_tags, fate_behavior, shooter, hit_knockback)
		else:
			if shooter != null and collider.has_method("notify_attacked_by"):
				collider.call("notify_attacked_by", shooter)
			collider.call("take_damage", damage, critical, direction, hit_knockback)
		_apply_secondary_effect(collider)
		_apply_fate_on_hit(collider)
		if bool(fate_behavior.get("rock_shatter", false)):
			_shatter_rock()
			_retire()
			return
		hit_confirmed.emit(collider, damage, critical)
		_spawn_hit_effect(collider, GOO_HIT_SIZE_TARGET, METAL_SPARK_SIZE_TARGET, hit_context)
		if bool(fate_behavior.get("spawn_turret_on_land", false)):
			_become_turret()
			return
		if _returning:
			if collider is PhysicsBody3D:
				_add_tracked_collision_exception(collider as PhysicsBody3D)
			return
		if bool(fate_behavior.get("return_on_hit", false)) or bool(fate_behavior.get("return_to_player", false)) or bool(fate_behavior.get("home_on_land", false)):
			_begin_return()
			if bool(fate_behavior.get("return_on_hit", false)) and damage > 0:
				_hit_target(collider, hit_context)
			global_position += direction * 0.28
			return
		if _pierces_left > 0:
			_pierces_left -= 1
			if collider is PhysicsBody3D:
				_add_tracked_collision_exception(collider as PhysicsBody3D)
			global_position += direction * 0.28
			return
		if _is_explosive_payload():
			_explode()
		_retire()
		return


func _hit_surface(normal: Vector3, hit_context: Dictionary = {}) -> void:
	# 撞墙炸散（Gun Nut 的「大 jammed 弹」）。原作原文：
	#   "they also fire a larger jammed bullet that **explodes into non-jammed bullets
	#    in all directions upon hitting an obstacle**"
	# 默认关闭：只有 `fate_behavior.shatter_on_wall = true` 的子弹走这条，
	# 其余所有子弹（玩家武器、Boss、既有敌人）行为逐字不变。
	if bool(fate_behavior.get("shatter_on_wall", false)):
		_shatter_into_ring()
		_retire()
		return
	if bool(fate_behavior.get("rock_shatter", false)):
		_shatter_rock()
		_retire()
		return
	if _returning:
		return
	if _bounces_left > 0:
		direction = direction.bounce(normal).normalized()
		damage = maxi(1, int(damage * float(fate_behavior.get("bounce_damage_scale", 0.85))))
		_sync_visual_orientation()
		_bounces_left -= 1
		# 反弹：打在**表面**上 ⇒ 金属火星（没有 collider，直接指定）
		_spawn_effect(
			VfxPool3D.FX01_METAL_SPARK_HIT, global_position, bullet_color,
			METAL_SPARK_SIZE_BOUNCE, hit_context
		)
		return
	if bool(fate_behavior.get("spawn_turret_on_land", false)):
		_become_turret()
		return
	if bool(fate_behavior.get("return_to_player", false)) or bool(fate_behavior.get("home_on_land", false)):
		_begin_return()
		return
	if _is_explosive_payload():
		_explode()
	# 落地：打在**表面**上 ⇒ 金属火星
	_spawn_effect(
		VfxPool3D.FX01_METAL_SPARK_HIT, global_position, bullet_color,
		METAL_SPARK_SIZE_SURFACE, hit_context
	)
	_retire()


func _add_tracked_collision_exception(body: PhysicsBody3D) -> void:
	if not is_instance_valid(body) or body in _tracked_collision_exceptions:
		return
	add_collision_exception_with(body)
	_tracked_collision_exceptions.append(body)


func _apply_secondary_effect(target: Node) -> void:
	if bullet_tags.has("sticky") or bullet_tags.has("slow") or bullet_tags.has("balloon"):
		if target.has_method("apply_slow"):
			target.call("apply_slow", 0.62, 2.0)
	if bullet_tags.has("sticky") and target.has_method("apply_damage_over_time"):
		target.call("apply_damage_over_time", maxi(2, damage / 3), 2.4)
	if bullet_tags.has("pull") and shooter != null and target.has_method("apply_pull"):
		target.call("apply_pull", shooter.global_position, 3.2)


func _apply_fate_on_hit(target: Node) -> void:
	if target.has_method("apply_fate_element"):
		var elements: Dictionary = fate_behavior.get("fate_elements", {})
		for element in elements:
			target.call("apply_fate_element", element, elements[element], _flight_base_damage, source_weapon_tree, shooter)
	var attached: Dictionary = fate_behavior.get("attached_gun", {})
	if bool(attached.get("fire_on_hit", false)) and not _attached_hit_fired:
		_attached_hit_fired = true
		_fire_attached_gun(attached, direction)
	if bool(fate_behavior.get("chain_lightning", false)):
		_apply_chain_lightning(target)
	if is_instance_valid(source_weapon_tree):
		source_weapon_tree.record_growth_result(true, fate_behavior)
		var attachment := source_weapon_tree.claim_attachment_trigger("hit", target) if bool(fate_behavior.get("fate_attachment_hit_trigger", false)) else {}
		if attachment.has("pull_strength") and target.has_method("apply_pull") and is_instance_valid(shooter):
			target.call("apply_pull", shooter.global_position, float(attachment["pull_strength"]))
		var count := int(attachment.get("bullet_count", 0))
		if randf() < float(attachment.get("copy_chance", 0.0)):
			count += 1
		for index in range(count):
			var angle := (float(index) - float(count - 1) * 0.5) * float(attachment.get("spread", 0.0))
			_spawn_child_projectile(direction.rotated(Vector3.UP, angle), damage, bullet_color)


func _apply_chain_lightning(first_target: Node) -> void:
	var chain_count := maxi(0, int(fate_behavior.get("chain_count", 3)))
	var chain_range := maxf(1.0, float(fate_behavior.get("chain_range", 150.0)) / 30.0)
	var chain_scale := clampf(float(fate_behavior.get("chain_damage_scale", 0.7)), 0.05, 1.0)
	var current := first_target as Node3D
	var visited := {first_target.get_instance_id(): true}
	var chain_damage := damage
	for _index in range(chain_count):
		var nearest: Enemy3D = null
		var nearest_distance := chain_range
		for value in get_tree().get_nodes_in_group("enemy_3d"):
			var enemy := value as Enemy3D
			if enemy == null or enemy.ai_state == "dead" or visited.has(enemy.get_instance_id()):
				continue
			var distance := current.global_position.distance_to(enemy.global_position)
			if distance < nearest_distance:
				nearest = enemy
				nearest_distance = distance
		if nearest == null:
			break
		chain_damage = maxi(1, int(chain_damage * chain_scale))
		var hit_behavior := fate_behavior.duplicate()
		hit_behavior["damage_element"] = "lightning"
		var arc_start := current.global_position + Vector3.UP * 0.6
		var arc_end := nearest.global_position + Vector3.UP * 0.6
		_spawn_effect(VfxPool3D.FX01_FATE_LIGHTNING, arc_start, Color.WHITE, 1.0, {"end_position": arc_end, "delay": _index * 0.025})
		nearest.take_projectile_damage(chain_damage, false, (nearest.global_position - current.global_position).normalized(), bullet_tags, hit_behavior, shooter)
		visited[nearest.get_instance_id()] = true
		current = nearest


func _is_explosive_payload() -> bool:
	## 命中/到期时应当引爆而不是直接消失的弹体。命中路径与射程上限共用同一判据，
	## 避免「到射程上限直接消失」与「命中就爆炸」两套条件漂移。
	return (
		bullet_tags.has("explosive") or bullet_tags.has("blackhole")
		or bullet_tags.has("balloon") or bool(fate_behavior.get("nth_explosion", false))
	)


func _explode() -> void:
	var radius := maxf(0.5, float(fate_behavior.get("explosion_radius", 90.0)) / 30.0) if fate_behavior.has("explosion_radius") else 3.0
	if bullet_tags.has("blackhole"):
		radius = 4.0
	elif bullet_tags.has("balloon"):
		radius = 3.6
	_spawn_effect(LEGACY_EFFECT_EXPLOSION, global_position, bullet_color, radius * 0.42)
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(
			global_position, maxf(12.0, radius * 4.0), "explosion", shooter
		)
	var group_name := "player_3d" if hostile else "enemy_3d"
	for target in get_tree().get_nodes_in_group(group_name):
		if target == shooter or not target is Node3D or not target.has_method("take_damage"):
			continue
		var target_3d := target as Node3D
		var distance := global_position.distance_to(target_3d.global_position)
		if distance > radius:
			continue
		var falloff := clampf(1.0 - distance / radius, 0.25, 1.0)
		var hit_direction := (target_3d.global_position - global_position).normalized()
		var explosion_scale := float(fate_behavior.get("explosion_damage_scale", 0.72))
		if shooter != null and target.has_method("notify_attacked_by"):
			target.call("notify_attacked_by", shooter)
		if target.has_method("take_projectile_damage"):
			target.call("take_projectile_damage", maxi(1, int(damage * falloff * explosion_scale)), false, hit_direction, bullet_tags, fate_behavior, shooter)
		else:
			target.call("take_damage", maxi(1, int(damage * falloff * explosion_scale)), false, hit_direction)
		if bullet_tags.has("blackhole") and target.has_method("apply_pull"):
			target.call("apply_pull", global_position, 3.0 + falloff * 5.0)
		if bullet_tags.has("balloon") and target.has_method("apply_slow"):
			target.call("apply_slow", 0.48, 2.6)


func _nearest_target() -> Node3D:
	var best: Node3D = null
	var farthest := str(fate_behavior.get("target_mode", "nearest")) == "farthest"
	var best_distance := -1.0 if farthest else 12.0
	for candidate in get_tree().get_nodes_in_group("enemy_3d"):
		if not candidate is Node3D:
			continue
		var candidate_3d := candidate as Node3D
		if candidate is Enemy3D and (candidate as Enemy3D).ai_state == "dead":
			continue
		var distance := global_position.distance_to(candidate_3d.global_position)
		if distance > 12.0:
			continue
		if farthest and not _target_visible(candidate_3d):
			continue
		if (distance > best_distance if farthest else distance < best_distance):
			best = candidate_3d
			best_distance = distance
	return best


func _target_visible(target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, target.global_position + Vector3(0, 0.68, 0), 1)
	query.exclude = [get_rid()]
	if shooter is CollisionObject3D:
		query.exclude.append(shooter.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target


func _build_visual() -> void:
	# 独立子弹纯视觉 Prefab：由 ProjectilePool3D 宿主生命周期管理，不放 VfxPool 自动计时。
	# ⚠️ 视觉可能已在未入树时由 configure() 按 visual_id 建好（回落路径 configure→add_child），
	#    此处不得无条件覆盖成通用弹体，否则弹种视觉被悄悄换回默认。
	if not is_instance_valid(_visual):
		_ensure_visual(_visual_scene_for(_visual_id))
	# 单独建立球碰撞（半径 0.12，与命运缩放公式保持一致）。
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = shape
	add_child(_collision_shape)


## 挂载/替换弹体视觉实例：释放旧实例，按目标 Prefab 重建。
## 池化复借时同种弹药（visual_id 不变）零成本——由 _sync_visual_route 拦在调用之前。
func _ensure_visual(scene: PackedScene) -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = scene.instantiate() as VfxEffectBase3D
	add_child(_visual)


## visual_id → 弹体视觉 Prefab；未登记的 id 一律回落通用弹体（不报错、不中断开火）。
func _visual_scene_for(visual_id: String) -> PackedScene:
	if BULLET_VISUAL_REGISTRY.has(visual_id):
		return BULLET_VISUAL_REGISTRY[visual_id] as PackedScene
	return BULLET_VISUAL_SCENE


## 按 config.visual_id 切换弹体视觉（缺省 "" = 通用弹体，与未接入弹种前的行为一致）。
func _sync_visual_route(config: Dictionary) -> void:
	var requested := "fate_rock" if bool(fate_behavior.get("rock_projectile", false)) else String(config.get("visual_id", ""))
	if requested == _visual_id and is_instance_valid(_visual):
		return
	_visual_id = requested
	_ensure_visual(_visual_scene_for(_visual_id))


## 弹体视觉总尺寸 = 弹种/命运倍率 × 枪身档位倍率（枪身维度：榴弹更大 / 霰弹更大等）。
func _visual_scale_factor() -> float:
	return _base_scale_factor() * float(_gun_bullet_geometry.get("scale", 1.0))


## 碰撞半径倍率 = 弹种/命运倍率 —— **刻意不含枪身档位**。
## 枪族档位是纯视觉契约（14.6 §3.7）：`0.12` 基准球本身已是为可玩性放大的判定体，
## 再叠枪身倍率等于顺手改命中率（霰弹 ×2 会让 5 发弹丸的判定面膨胀到 4 倍）。
## 与 `WeaponModel3D.BULLET_GEOMETRY_BY_GUN_TAG` 的分离由验收的正面断言钉住。
func _collision_scale_factor() -> float:
	return _base_scale_factor()


## 弹种 × 命运：视觉与碰撞共用的底座倍率。
func _base_scale_factor() -> float:
	var scale_factor := 1.55 if bullet_tags.has("balloon") else 1.0
	scale_factor *= clampf(float(fate_behavior.get("fate_scale", 1.0)), 0.35, 4.0)
	return scale_factor


## 弹体几何 context：枪身档位决定的轴向拉伸与生长包络（纯视觉）。
func _bullet_visual_context() -> Dictionary:
	return {
		"axial_scale": float(_gun_bullet_geometry.get("axial", 1.0)),
		"grow_from": float(_gun_bullet_geometry.get("grow_from", 1.0)),
		"grow_duration": float(_gun_bullet_geometry.get("grow_duration", 0.0)),
	}

func _apply_visual_configuration() -> void:
	if _visual != null:
		_visual.configure(bullet_color, _visual_scale_factor(), _bullet_visual_context())
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = (0.18 if bool(fate_behavior.get("rock_projectile", false)) else 0.12) * _collision_scale_factor()


func _return_destination() -> Vector3:
	if int(fate_behavior.get("refund_ammo", 0)) > 0 and is_instance_valid(source_weapon):
		return source_weapon.global_position
	return shooter.global_position + Vector3(0, 0.72, 0)


func _begin_return() -> void:
	if _returning:
		return
	if not is_instance_valid(shooter):
		_retire()
		return
	_returning = true
	_lifetime = 0.0
	damage = maxi(0, int(_flight_base_damage * float(fate_behavior.get("return_damage_multiplier", 0.6))))
	# 返航不再被去程穿透例外或墙体阻断；回程每个目标只结算一次。
	for exception in _tracked_collision_exceptions:
		if is_instance_valid(exception) and exception != shooter:
			remove_collision_exception_with(exception)
	_tracked_collision_exceptions.clear()
	if shooter is PhysicsBody3D:
		_add_tracked_collision_exception(shooter)
	collision_mask = 4 if damage > 0 else 0
	direction = (_return_destination() - global_position).normalized()
	_sync_visual_orientation()


func _become_turret() -> void:
	_turret_active = true
	velocity = Vector3.ZERO
	_turret_remaining = maxf(0.5, float(fate_behavior.get("turret_duration", 5.0)))
	_turret_shot_timer = 0.0
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	if _visual != null:
		if _visual.has_method("set_trail_visible"):
			_visual.call("set_trail_visible", false)
		if _visual.has_method("apply_growth"):
			_visual.call("apply_growth", 1.45)
	_spawn_effect(VfxPool3D.FX01_METAL_SPARK_HIT, global_position, bullet_color, METAL_SPARK_SIZE_SURFACE)


## 命中特效分流：打中「僵尸三兄弟」⇒ FX01-20（金属火星造型 + 僵尸绿，尺寸 ×1.10）；
## 其余 ⇒ FX01-21 金属火星。
## `goo_size` / `metal_size` 是**同一档位下两件各自的尺寸**（FX01-20 比 FX01-21 大 10%，
## 见 `ZOMBIE_HIT_SIZE_RATIO`）。
## `world_position` 缺省取弹体自身位置；链电那种「在别的怪身上炸」的场景要显式传。
## ⚠ 命中点先经 `Enemy3D.hit_effect_anchor()` **收进模型 0.2m** —— 弹体是在碰撞壳表面判定
## 命中的，而壳比模型大一圈，直接用交点会让特效悬在怪旁边（业主 2026-10-14：「受击的盒子
## 没有贴着模型」）。只对怪收，墙面 / 掩体不收（那里收了会钻进墙里）。
func _spawn_hit_effect(
	collider: Node,
	goo_size: float,
	metal_size: float,
	hit_context: Dictionary = {},
	world_position: Variant = null
) -> void:
	var is_zombie := collider is Enemy3D and (collider as Enemy3D).uses_goo_hit_burst()
	var asset_id: StringName = VfxPool3D.FX01_GOO_HIT if is_zombie else VfxPool3D.FX01_METAL_SPARK_HIT
	var size: float = goo_size if is_zombie else metal_size
	var spawn_position: Vector3 = global_position if world_position == null else world_position
	if collider is Enemy3D:
		spawn_position = (collider as Enemy3D).hit_effect_anchor(
			spawn_position, hit_context.get("normal", Vector3.ZERO) as Vector3
		)
	_spawn_effect(asset_id, spawn_position, bullet_color, size, hit_context)


func _tick_turret(delta: float) -> void:
	if bool(fate_behavior.get("mobile_turret", false)) and is_instance_valid(shooter):
		global_position = global_position.move_toward(shooter.global_position + Vector3(0, 0.72, 0), speed * delta)
	_turret_remaining -= delta
	if _turret_remaining <= 0.0:
		_retire()
		return
	_turret_shot_timer -= delta
	if _turret_shot_timer > 0.0:
		return
	var target := _nearest_target()
	if target == null:
		return
	_turret_shot_timer = 1.0 / maxf(0.2, float(fate_behavior.get("turret_fire_rate", 2.0)))
	_spawn_child_projectile(
		(target.global_position + Vector3(0, 0.65, 0) - global_position).normalized(),
		maxi(1, int(damage * 0.30)),
		bullet_color.lightened(0.16),
	)


func _rebuild_carried_weapon() -> void:
	if is_instance_valid(_carried_weapon):
		_carried_weapon.free()
	_carried_weapon = null
	if not is_instance_valid(_weapon_socket):
		_weapon_socket = Marker3D.new()
		_weapon_socket.name = "BulletWeaponSocket"
		add_child(_weapon_socket)
	_weapon_socket.transform = Transform3D.IDENTITY
	_weapon_socket.position = Vector3(0.0, 0.12, 0.0)
	_weapon_socket.scale = Vector3.ONE * 0.45
	var attached := fate_behavior.get("attached_gun", {}) as Dictionary
	if attached.is_empty():
		return
	_weapon_socket.rotation.y = PI if bool(attached.get("mount_reversed", false)) else 0.0
	_carried_weapon = WeaponModel3D.create_mounted(attached.get("assembly_snapshot", {}), _weapon_socket)
	if is_instance_valid(_carried_weapon):
		_carried_weapon.set_damage_multiplier(float(fate_behavior.get("owner_damage_multiplier", 1.0)))


func _tick_attached_gun(delta: float) -> void:
	# Legacy saved reverse Chariot retains its recorded on-hit trigger; new r3 cards never set it.
	if bool((fate_behavior.get("attached_gun", {}) as Dictionary).get("fire_on_hit", false)):
		return
	if not is_instance_valid(_carried_weapon):
		return
	_attached_shot_timer -= delta
	if _attached_shot_timer > 0.0:
		return
	_attached_shot_timer = 0.65 if _carried_weapon.is_melee_weapon() else 1.0 / maxf(0.2, _carried_weapon.fire_rate)
	var muzzle := _carried_weapon._muzzle
	var forward := -muzzle.global_basis.z.normalized() if is_instance_valid(muzzle) else -_weapon_socket.global_basis.z.normalized()
	_carried_weapon.fire_mounted(shooter, forward)


## 环形爆散：把这一发拆成 N 发朝各个方向的小弹（同一阵营、同一射手）。
## 只在 `shatter_on_wall` 下调用；`shatter_count` / `shatter_damage_ratio` 可覆盖。
func _shatter_into_ring() -> void:
	var count := maxi(1, int(fate_behavior.get("shatter_count", 8)))
	var ratio := float(fate_behavior.get("shatter_damage_ratio", 0.5))
	var child_damage := maxi(1, int(round(float(maxi(1, damage)) * ratio)))
	var child_speed := float(fate_behavior.get("shatter_speed", maxf(4.0, speed * 1.1)))
	var pools := get_tree().get_nodes_in_group("projectile_pool_3d")
	if pools.is_empty():
		return
	var pool := pools[0] as ProjectilePool3D
	if pool == null:
		return
	var origin := global_position
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		pool.acquire(
			{
				"direction": dir,
				"speed": child_speed,
				"range": maxf(6.0, range_m * 0.6),
				"damage": child_damage,
				"hostile": hostile,
				"critical": false,
				"tags": [],
				"color": bullet_color,
				"shooter": shooter,
			},
			origin + dir * 0.35
		)


func _shatter_rock() -> void:
	if _rock_shattered:
		return
	_rock_shattered = true
	for target in get_tree().get_nodes_in_group("enemies"):
		if not target is Node3D or not target.has_method("apply_melee_knockback"):
			continue
		var offset: Vector3 = target.global_position - global_position
		if offset.length() <= 3.0:
			var away := Vector3(offset.x, 0.0, offset.z).normalized()
			if away.length_squared() < 0.01:
				away = Vector3(direction.x, 0.0, direction.z).normalized()
			target.call("apply_melee_knockback", away, 6.0, 0.25)
	var pool := _resolve_vfx_pool()
	if pool != null:
		pool.acquire(VfxPool3D.FX01_FATE_ROCK_SHATTER, global_position, Color(0.48, 0.40, 0.30), 1.0, {})


func _fire_attached_gun(attached: Dictionary, base_direction: Vector3) -> void:
	var count := maxi(1, int(attached.get("bullet_count", 1)))
	var child_damage := (float(attached.get("damage", 0)) + float(attached.get("bullet_damage", 5))) * float(attached.get("fate_damage_multiplier", 1.0)) * float(fate_behavior.get("owner_damage_multiplier", 1.0))
	if bool(fate_behavior.get("uncontrolled_gun", false)):
		base_direction = base_direction.rotated(Vector3.UP, randf_range(-PI, PI) * float(fate_behavior.get("aim_randomness", 1.0)))
		child_damage *= float(fate_behavior.get("uncontrolled_damage_scale", 1.0))
	var child_behavior := attached.duplicate(true)
	if bool(fate_behavior.get("uncontrolled_gun", false)) and is_instance_valid(source_weapon):
		source_weapon._recoil = maxf(source_weapon._recoil, 0.09 * float(fate_behavior.get("uncontrolled_recoil_scale", 1.0)))
		source_weapon.set_process(true)
	child_behavior.erase("attached_gun")
	child_behavior.erase("size_growth")
	for index in range(count):
		var angle := (float(index) - float(count - 1) * 0.5) * float(attached.get("spread", 0.10))
		_spawn_child_projectile(base_direction.rotated(Vector3.UP, angle), maxi(1, int(child_damage)), bullet_color.lightened(0.10), child_behavior)


func _resolve_projectile_pool() -> ProjectilePool3D:
	if is_instance_valid(_projectile_pool_cache):
		return _projectile_pool_cache
	var pools := get_tree().get_nodes_in_group("projectile_pool_3d")
	_projectile_pool_cache = pools[0] as ProjectilePool3D if not pools.is_empty() and pools[0] is ProjectilePool3D else null
	return _projectile_pool_cache


func _resolve_vfx_pool() -> VfxPool3D:
	if is_instance_valid(_vfx_pool_cache):
		return _vfx_pool_cache
	var vfx_pools := get_tree().get_nodes_in_group("vfx_pool_3d")
	_vfx_pool_cache = vfx_pools[0] as VfxPool3D if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D else null
	return _vfx_pool_cache


func _resolve_combat_effect_pool() -> CombatEffectPool3D:
	if is_instance_valid(_combat_effect_pool_cache):
		return _combat_effect_pool_cache
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	_combat_effect_pool_cache = pools[0] as CombatEffectPool3D if not pools.is_empty() and pools[0] is CombatEffectPool3D else null
	return _combat_effect_pool_cache


func _spawn_child_projectile(shot_direction: Vector3, shot_damage: int, color: Color, child_behavior: Dictionary = {}) -> void:
	child_behavior = child_behavior.duplicate(true)
	child_behavior["source_weapon_tree"] = source_weapon_tree
	child_behavior["source_weapon"] = source_weapon
	var is_critical := randf() < float(fate_behavior.get("owner_critical_chance", 0.0))
	var critical_multiplier := float(fate_behavior.get("owner_critical_multiplier", 1.5))
	var config := {
		"direction": shot_direction,
		"speed": 23.0 * float(child_behavior.get("bullet_speed", speed / 23.0)) * float(child_behavior.get("fate_speed_multiplier", 1.0)),
		"damage": maxi(1, int(shot_damage * (critical_multiplier / 1.5 if is_critical else 1.0))),
		"critical": is_critical,
		"hostile": hostile,
		"tags": child_behavior.get("tags", []),
		"color": color,
		# 子投射物默认继承父弹当前弹种视觉（_visual_id）；child_behavior 显式带 visual_id 时以它为准。
		"visual_id": String(child_behavior.get("visual_id", _visual_id)),
		# 枪身几何档位一并继承：分裂/子母弹的子弹应与母弹同尺寸。
		"gun_bullet_geometry": _gun_bullet_geometry,
		"shooter": shooter,
		"behavior": child_behavior,
	}
	var pool := _resolve_projectile_pool()
	if pool != null:
		pool.acquire(config, global_position + shot_direction * 0.32)
		return
	var projectile := Projectile3D.new()
	projectile.configure(config)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + shot_direction * 0.32


func _sync_visual_orientation() -> void:
	if direction.length_squared() <= 0.0001 or not is_inside_tree():
		return
	var forward := direction.normalized()
	if absf(forward.dot(Vector3.UP)) > 0.995:
		return
	look_at(global_position + forward, Vector3.UP)


func get_orientation_snapshot() -> Dictionary:
	var snapshot := {
		"direction": direction,
		"visual_forward": -global_basis.z,
		"alignment": direction.normalized().dot((-global_basis.z).normalized()),
		"trail_local_position": Vector3.ZERO,
		"trail_is_behind": false,
		"visual_asset_id": "",
		"visual_profile": "",
		"collision_radius": 0.0,
	}
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		snapshot["collision_radius"] = (_collision_shape.shape as SphereShape3D).radius
	if _visual != null and _visual.has_method("get_presentation_snapshot"):
		var presentation := _visual.call("get_presentation_snapshot") as Dictionary
		snapshot["trail_local_position"] = presentation.get("trail_local_position", Vector3.ZERO)
		snapshot["trail_is_behind"] = presentation.get("trail_is_behind", false)
		snapshot["visual_asset_id"] = presentation.get("asset_id", "")
		snapshot["visual_profile"] = presentation.get("bullet_profile", "")
		snapshot["visual_base_scale"] = presentation.get("base_scale", 0.0)
		snapshot["visual_body_scale"] = presentation.get("body_scale", 0.0)
		snapshot["visual_axial_scale"] = presentation.get("axial_scale", 1.0)
		snapshot["visual_growth_factor"] = presentation.get("growth_factor", 1.0)
	return snapshot


func _retire() -> void:
	if is_instance_valid(_carried_weapon):
		_carried_weapon.queue_free()
		_carried_weapon.set_process(false)
		_carried_weapon.visible = false
	_carried_weapon = null
	if not _active:
		return
	_active = false
	if not _hit_any and is_instance_valid(source_weapon_tree):
		source_weapon_tree.record_growth_result(false, fate_behavior)
	velocity = Vector3.ZERO
	visible = false
	if _visual != null and _visual.has_method("deactivate"):
		_visual.call("deactivate")
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	process_mode = Node.PROCESS_MODE_DISABLED
	if retired.get_connections().is_empty():
		queue_free()
	else:
		retired.emit(self)


func _spawn_effect(effect_id: StringName, world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	# 已注册 AssetID（FX01-* 战斗反馈）走全局 VfxPool 新体系，按 AssetID 路由。
	var vfx_pool := _resolve_vfx_pool()
	if vfx_pool != null and VfxPool3D.has_effect(effect_id):
		vfx_pool.acquire(effect_id, world_position, color, size, context)
		return
	if get_tree().current_scene == null:
		return
	# 未注册 AssetID（爆炸等旧链图例）：仍走 CombatEffectPool3D，待 14.6 §6 迁移完成后删除。
	var effect_pool := _resolve_combat_effect_pool()
	if effect_pool != null:
		effect_pool.acquire(str(effect_id), color, size, world_position)
		return
	# VfxPool 不在场（异常态）且该 AssetID 已注册：直接从注册表实例化，保留 AssetID 语义。
	var pooled_effect := VfxPool3D.create_unpooled(effect_id)
	if pooled_effect != null:
		get_tree().current_scene.add_child(pooled_effect)
		pooled_effect.activate(world_position, color, size, context)
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(str(effect_id), color, size)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position
