class_name VfxMuzzleFlash3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-01 / VFX-MUZZLE-FLASH-3D 枪口火光特效（高品质卡通 · v002）
## 视觉：铂金亮芯 + 橙金/弹药色立体楔形火焰 + 交叉面尖瓣 + 少量飞散火星 + 短冲击环 + MuzzleLight
## 行为：lifetime ~0.16s；local -Z 对齐 context.forward（Basis.looking_at）；
##       OmniLight3D(名 MuzzleLight) 无阴影、范围 3-4m、能量随快速包络归零（范围仅设置一次，不随 effect_size 重复缩放）。
## 资源：mesh/material 首次生成后复用；所有 geometry cast shadow OFF；透明重叠受控不泛白。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

const _ASSET_ID := "VFX-MUZZLE-FLASH-3D"
const _ASSET_VERSION := "v002"
const _LIGHT_RANGE_BASE := 3.5
const _LIGHT_ENERGY := 5.0
const _SPARK_COUNT := 5

var _forward: Vector3 = Vector3.FORWARD

var _core: MeshInstance3D
var _flame: MeshInstance3D
var _petal_a: MeshInstance3D
var _petal_b: MeshInstance3D
var _ring: MeshInstance3D
var _sparks: Array[MeshInstance3D] = []

var _mat_core: StandardMaterial3D
var _mat_flame: StandardMaterial3D
var _mat_petal: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _mat_spark: StandardMaterial3D

var _muzzle_light: OmniLight3D
var _spark_dirs: Array[Vector3] = []


func _on_activate(_world_pos: Vector3, color: Color, _size: float, context: Dictionary) -> void:
	lifetime = 0.16
	_forward = (context.get("forward", Vector3.FORWARD) as Vector3)
	if _forward.length_squared() < 0.0001:
		_forward = Vector3.FORWARD
	_forward = _forward.normalized()
	var ammo := color
	if ammo.a < 0.001:
		ammo = Color(1.0, 0.6, 0.2, 1.0)
	if _core == null:
		_build()
	# 朝向：local -Z 对齐 forward
	self.global_transform = Transform3D(Basis.looking_at(_forward), global_position)
	_reset_state(ammo)
	_on_tick(0.0, lifetime)


func _build() -> void:
	# 铂金亮芯
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = ToonVfx.core_mesh()
	_mat_core = ToonVfx.toon_material(Color(1.0, 0.97, 0.85, 1.0), 0.4)
	_core.material_override = _mat_core
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	# 立体楔形火焰（CylinderMesh top_radius=0，apex 朝 -Z）
	_flame = MeshInstance3D.new()
	_flame.name = "Flame"
	_flame.mesh = ToonVfx.flame_mesh()
	_flame.rotation.x = -PI / 2.0
	_flame.position.z = -0.5
	_mat_flame = ToonVfx.toon_material(Color(1.0, 0.55, 0.12, 1.0))
	_flame.material_override = _mat_flame
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)

	# 交叉面尖瓣（两片垂直 Quad，沿 -Z 延伸）
	_mat_petal = ToonVfx.toon_material(Color(1.0, 0.6, 0.2, 1.0))
	_petal_a = MeshInstance3D.new()
	_petal_a.name = "PetalA"
	_petal_a.mesh = ToonVfx.petal_mesh()
	_petal_a.rotation.x = -PI / 2.0
	_petal_a.position.z = -0.55
	_petal_a.material_override = _mat_petal
	_petal_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_petal_a)
	_petal_b = MeshInstance3D.new()
	_petal_b.name = "PetalB"
	# 第二片绕 forward(-Z) 轴旋转 90° 形成十字
	_petal_b.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0)) * Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)),
		Vector3(0.0, 0.0, -0.55)
	)
	_petal_b.mesh = ToonVfx.petal_mesh()
	_petal_b.material_override = _mat_petal
	_petal_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_petal_b)

	# 短冲击环（默认位于 XY 平面，垂直于 -Z forward，作为枪口光晕）
	_ring = MeshInstance3D.new()
	_ring.name = "ShockRing"
	_ring.mesh = ToonVfx.ring_mesh()
	_mat_ring = ToonVfx.toon_material(Color(1.0, 0.7, 0.3, 1.0))
	_ring.material_override = _mat_ring
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# 少量飞散火星
	_mat_spark = ToonVfx.toon_material(Color(1.0, 0.85, 0.4, 1.0), 0.6)
	for i in _SPARK_COUNT:
		var s := MeshInstance3D.new()
		s.name = "Spark%d" % i
		s.mesh = ToonVfx.spark_mesh()
		var dir := _spark_dir(i)
		_spark_dirs.append(dir)
		s.quaternion = Quaternion(Basis.looking_at(dir))
		s.material_override = _mat_spark
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		_sparks.append(s)

	# 枪口灯（无阴影、范围仅设置一次）
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "MuzzleLight"
	_muzzle_light.shadow_enabled = false
	_muzzle_light.light_color = Color(1.0, 0.82, 0.55)
	add_child(_muzzle_light)


func _spark_dir(i: int) -> Vector3:
	# 以 forward(-Z) 为轴向四周散开
	var ang := float(i) / float(_SPARK_COUNT) * TAU
	var lateral := Vector3(cos(ang), sin(ang), 0.0) * 0.5
	var fwd := Vector3(0.0, 0.0, -1.0) * 0.9
	return (fwd + lateral).normalized()


func _reset_state(ammo: Color) -> void:
	# 复用材质，仅按弹药色/固定色更新 albedo
	_mat_core.albedo_color = Color(1.0, 0.97, 0.85, 1.0)
	_mat_flame.albedo_color = ammo
	_mat_petal.albedo_color = ammo
	_mat_ring.albedo_color = ammo
	_mat_spark.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
	# 复位 basis 子节点 scale / 位置 / alpha 与灯
	_core.scale = Vector3.ONE
	_flame.scale = Vector3.ONE
	_petal_a.scale = Vector3.ONE
	_petal_b.scale = Vector3.ONE
	_ring.scale = Vector3.ONE
	for s in _sparks:
		s.position = Vector3.ZERO
		s.scale = Vector3.ONE
	_muzzle_light.shadow_enabled = false
	_muzzle_light.omni_range = _LIGHT_RANGE_BASE * effect_size
	_muzzle_light.position = Vector3.ZERO
	_muzzle_light.light_energy = _LIGHT_ENERGY


func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	var sz := effect_size
	# 亮芯：快速收缩并淡出
	_core.scale = Vector3.ONE * sz * (0.35 + (1.0 - t) * 0.3)
	_mat_core.albedo_color.a = 1.0 - t
	# 立体楔形火焰：沿 -Z 伸长，粗壮→收
	var fg := sz * (0.55 + (1.0 - t) * 0.5)
	var fl := sz * (0.7 + (1.0 - t) * 1.1)
	_flame.scale = Vector3(fg, fl, fg)
	_mat_flame.albedo_color.a = clamp(1.0 - t * 1.25, 0.0, 1.0)
	# 交叉尖瓣
	var pg := sz * (0.6 + (1.0 - t) * 0.6)
	var pl := sz * (0.7 + (1.0 - t) * 1.2)
	_petal_a.scale = Vector3(pg, pl, pg)
	_petal_b.scale = Vector3(pg, pl, pg)
	_mat_petal.albedo_color.a = clamp(1.0 - t * 1.4, 0.0, 1.0)
	# 短冲击环：快速扩张并淡出
	var rs := sz * (0.3 + t * 1.7)
	_ring.scale = Vector3.ONE * rs
	_mat_ring.albedo_color.a = clamp(0.9 * (1.0 - t * 1.2), 0.0, 1.0)
	# 火星：向外飞散
	for i in _sparks.size():
		var s := _sparks[i]
		var d := _spark_dirs[i]
		var dist := (0.25 + t * 0.9) * sz
		s.position = d * dist
		s.scale = Vector3.ONE * sz * (0.7 - t * 0.45)
	_mat_spark.albedo_color.a = clamp(1.0 - t * 1.2, 0.0, 1.0)
	# 枪口灯：能量随快速包络归零（范围只设置一次，不随 effect_size 重复缩放，节点不缩放）
	_muzzle_light.light_energy = _LIGHT_ENERGY * pow(1.0 - t, 1.5)


func _on_lifetime_expired() -> void:
	if is_instance_valid(_muzzle_light):
		_muzzle_light.light_energy = 0.0


## 供测试/巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	var light_valid := is_instance_valid(_muzzle_light)
	return {
		"asset_id": get_meta("asset_id", _ASSET_ID),
		"asset_version": get_meta("asset_version", _ASSET_VERSION),
		"node_count": get_child_count(),
		"has_muzzle_light": light_valid,
		"light_name": _muzzle_light.name if light_valid else "",
		"light_energy": _muzzle_light.light_energy if light_valid else 0.0,
		"light_range": _muzzle_light.omni_range if light_valid else 0.0,
		"light_shadows": _muzzle_light.shadow_enabled if light_valid else false,
		"forward": _forward,
		"lifetime": lifetime,
	}
