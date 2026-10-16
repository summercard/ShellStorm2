class_name TrainingTarget3D
extends AnimatableBody3D
## 靶场靶标。加入 `enemy_3d` / `damageable_3d` 分组后，它会被整套战斗系统当成敌人对待，
## 因此**必须实现完整的受击契约** —— 而不是只实现自己顺手用到的那个短签名。
##
## 2026-10-16 修：原来只写了 `take_damage(amount, critical, hit_direction)` 三个参数，
## 而子弹命中走的是 `Projectile3D` 的四参调用（末位 hit_knockback）：
##   collider.call("take_damage", damage, critical, direction, hit_knockback)
## `Object.call()` 按**声明参数个数上限**校验（默认参数可省略、但不能多给），
## 于是四参打在三参签名上 → "Expected 3 argument(s)"。
## 现在签名对齐 `Enemy3D.take_damage`（5 参），并补 `take_projectile_damage`，
## 让子弹走带 tags/behavior 的富路径 —— 命运卡的命中效果才有落点。

signal damaged(target: TrainingTarget3D, applied: int, critical: bool)
signal destroyed(target: TrainingTarget3D)

@export_enum("standard", "armored", "runner") var target_type := "standard"
## 装甲减伤系数：与远征关卡同口径，便于在靶场复现实战手感。
const ARMORED_DAMAGE_SCALE := 0.58
const CRITICAL_DAMAGE_SCALE := 1.5

var max_hp := 100
var current_hp := 100
var _origin := Vector3.ZERO
var _elapsed := 0.0
var _active := true
var _body_material: StandardMaterial3D
var _label: Label3D


func configure(type_id: String) -> void:
	target_type = type_id


func _ready() -> void:
	add_to_group("training_target_3d")
	add_to_group("enemy_3d")
	# 近战判定走 damageable_3d 分组：不加这条，近战武器在靶场里砍不到靶子。
	add_to_group("damageable_3d")
	collision_layer = 4
	collision_mask = 0
	max_hp = 160 if target_type == "armored" else 100
	current_hp = max_hp
	_origin = position
	_build_visual()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if target_type == "runner" and _active:
		position.x = _origin.x + sin(_elapsed * 1.55) * 3.2


## 完整受击契约，签名与 `Enemy3D.take_damage` 对齐（5 参，后四个有默认值）。
func take_damage(
	amount: int,
	critical := false,
	_hit_direction := Vector3.ZERO,
	_hit_knockback := 0.0,
	_interrupt_movement := true
) -> void:
	if not _active:
		return
	var applied := _mitigated(amount, critical)
	current_hp = maxi(0, current_hp - applied)
	damaged.emit(self, applied, critical)
	_body_material.albedo_color = Color.WHITE
	_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]
	if current_hp <= 0:
		_begin_destroy()


## 子弹命中路径。`Projectile3D` 检测到本方法就优先走它，从而把弹种标签与命运行为带进来。
## 靶标不消费这些标签（它不是真敌人），但必须接住完整签名 —— 否则会回落到短签名路径。
func take_projectile_damage(
	amount: int,
	critical := false,
	hit_direction := Vector3.ZERO,
	_tags: Array[String] = [],
	behavior: Dictionary = {},
	_attacker: Node3D = null,
	hit_knockback := 0.0
) -> void:
	# 穿透类弹种无视装甲减伤：与 Enemy3D 的 pierce_shield 口径一致，
	# 这样"穿甲强化"这类命运卡在靶场里也能看出差别。
	if target_type == "armored" and bool(behavior.get("pierce_shield", false)):
		if not _active:
			return
		var pierced := maxi(1, amount)
		if critical:
			pierced = int(pierced * CRITICAL_DAMAGE_SCALE)
		current_hp = maxi(0, current_hp - pierced)
		damaged.emit(self, pierced, critical)
		_body_material.albedo_color = Color.WHITE
		_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]
		if current_hp <= 0:
			_begin_destroy()
		return
	take_damage(amount, critical, hit_direction, hit_knockback)


## 记录仇恨来源：靶标没有 AI，接受即可 —— 缺这个方法会让调用方在 has_method 之后调用失败。
func notify_attacked_by(_attacker: Node3D) -> void:
	pass


func apply_slow(_factor: float, _duration: float) -> void:
	pass


func is_dead() -> bool:
	return not _active


func reset_target() -> void:
	current_hp = max_hp
	_active = true
	scale = Vector3.ONE
	position = _origin
	_body_material.albedo_color = _target_color()
	_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]


func get_snapshot() -> Dictionary:
	return {"target_type": target_type, "hp": current_hp, "max_hp": max_hp, "active": _active, "is_3d": true}


func _mitigated(amount: int, critical: bool) -> int:
	var applied := maxi(1, int(amount * ARMORED_DAMAGE_SCALE)) if target_type == "armored" else maxi(1, amount)
	if critical:
		applied = int(applied * CRITICAL_DAMAGE_SCALE)
	return applied


func _begin_destroy() -> void:
	_active = false
	destroyed.emit(self)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.25, 0.08, 1.25), 0.18)
	tween.tween_interval(0.65)
	tween.tween_callback(reset_target)


func _build_visual() -> void:
	_body_material = _material(_target_color(), 0.45 if target_type == "armored" else 0.16, 0.52)
	var glow := _material(Color(1.0, 0.28, 0.12), 0.1, 0.3, true)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.5
	body_mesh.radial_segments = 12
	body_mesh.rings = 6
	body_mesh.material = _body_material
	var body := MeshInstance3D.new()
	body.position.y = 0.78
	body.mesh = body_mesh
	add_child(body)
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.22
	core_mesh.height = 0.44
	core_mesh.radial_segments = 10
	core_mesh.rings = 5
	core_mesh.material = glow
	var core := MeshInstance3D.new()
	core.position = Vector3(0, 0.95, -0.55)
	core.mesh = core_mesh
	add_child(core)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.58
	shape.height = 1.5
	var collision := CollisionShape3D.new()
	collision.position.y = 0.78
	collision.shape = shape
	add_child(collision)
	_label = Label3D.new()
	_label.position = Vector3(0, 2.0, 0)
	_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]
	_label.font_size = 38
	_label.pixel_size = 0.011
	_label.outline_size = 8
	_label.modulate = _target_color().lightened(0.22)
	add_child(_label)


func _target_color() -> Color:
	return {"standard": Color(0.30, 0.72, 0.82), "armored": Color(0.78, 0.44, 0.16), "runner": Color(0.50, 0.78, 0.30)}.get(target_type, Color.WHITE)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	return material
