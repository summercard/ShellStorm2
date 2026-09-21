class_name VfxImpact3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-02 / VFX-IMPACT-3D 通用命中特效（高品质卡通 · v002）
## 视觉：亮芯 + 6-8 星芒（不同长度错峰）+ 冲击环 + 6-8 碎屑（不同长度错峰、含旋转）
## 行为：lifetime ~0.32s；local +Y 对齐 context.normal（默认 UP）；透明重叠受控、干净收尾。
## 资源：mesh/material 首次生成后复用；所有 geometry cast shadow OFF；不引用 ConeMesh。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

const _ASSET_ID := "VFX-IMPACT-3D"
const _ASSET_VERSION := "v002"
const _SPIKE_COUNT := 7
const _DEBRIS_COUNT := 8

var _normal: Vector3 = Vector3.UP

var _core: MeshInstance3D
var _ring: MeshInstance3D
var _spikes: Array[MeshInstance3D] = []
var _debris: Array[MeshInstance3D] = []

var _mat_core: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _mat_spike: StandardMaterial3D
var _mat_debris: StandardMaterial3D

var _spike_dirs: Array[Vector3] = []
var _spike_len: Array[float] = []
var _spike_phase: Array[float] = []
var _debris_dirs: Array[Vector3] = []
var _debris_len: Array[float] = []
var _debris_phase: Array[float] = []


func _on_activate(_world_pos: Vector3, color: Color, _size: float, context: Dictionary) -> void:
	lifetime = 0.32
	_normal = (context.get("normal", Vector3.UP) as Vector3)
	if _normal.length_squared() < 0.0001:
		_normal = Vector3.UP
	_normal = _normal.normalized()
	var ammo := color
	if ammo.a < 0.001:
		ammo = Color(1.0, 0.7, 0.3, 1.0)
	if _core == null:
		_build()
	# 朝向：local +Y 对齐 normal
	self.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, _normal)), global_position)
	_reset_state(ammo)
	_on_tick(0.0, lifetime)


func _build() -> void:
	# 亮芯
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = ToonVfx.core_mesh()
	_mat_core = ToonVfx.toon_material(Color(1.0, 0.96, 0.85, 1.0), 0.4)
	_core.material_override = _mat_core
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	# 冲击环（local +Y=normal 后转 90° 使环面法线沿 normal，展开为表面光晕）
	_ring = MeshInstance3D.new()
	_ring.name = "ShockRing"
	_ring.mesh = ToonVfx.ring_mesh()
	_ring.rotation.x = -PI / 2.0
	_mat_ring = ToonVfx.toon_material(Color(1.0, 0.75, 0.35, 1.0))
	_ring.material_override = _mat_ring
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# 星芒：沿 local XZ 平面（垂直于 normal 的切平面）放射，不同长度/相位错峰
	for i in _SPIKE_COUNT:
		var ang := float(i) / float(_SPIKE_COUNT) * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang)).normalized()
		_spike_dirs.append(dir)
		_spike_len.append(0.7 + fmod(float(i) * 0.37, 1.0) * 0.8)
		_spike_phase.append(fmod(float(i) * 0.13, 0.4))
		var sp := MeshInstance3D.new()
		sp.name = "Spike%d" % i
		sp.mesh = ToonVfx.spike_mesh()
		sp.quaternion = Quaternion(Vector3.UP, dir)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)
		_spikes.append(sp)

	# 碎屑：不同方向/长度/相位，含轻微法向偏移（向外喷溅）
	for i in _DEBRIS_COUNT:
		var ang := float(i) / float(_DEBRIS_COUNT) * TAU + 0.4
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		dir += Vector3.UP * (0.3 + fmod(float(i) * 0.21, 1.0) * 0.5)
		dir = dir.normalized()
		_debris_dirs.append(dir)
		_debris_len.append(0.6 + fmod(float(i) * 0.29, 1.0) * 0.9)
		_debris_phase.append(fmod(float(i) * 0.17, 0.35))
		var db := MeshInstance3D.new()
		db.name = "Debris%d" % i
		db.mesh = ToonVfx.debris_mesh()
		db.quaternion = Quaternion(Vector3.UP, dir)
		db.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(db)
		_debris.append(db)

	# 共享材质（实例级复用）
	_mat_spike = ToonVfx.toon_material(Color(1.0, 0.8, 0.4, 1.0))
	_mat_debris = ToonVfx.toon_material(Color(1.0, 0.7, 0.3, 1.0))
	for sp in _spikes:
		sp.material_override = _mat_spike
	for db in _debris:
		db.material_override = _mat_debris


func _reset_state(ammo: Color) -> void:
	_mat_core.albedo_color = Color(1.0, 0.96, 0.85, 1.0)
	_mat_ring.albedo_color = ammo
	_mat_spike.albedo_color = ammo
	_mat_debris.albedo_color = ammo
	_core.scale = Vector3.ONE
	_ring.scale = Vector3.ONE
	for sp in _spikes:
		sp.position = Vector3.ZERO
		sp.scale = Vector3.ONE
		sp.rotation = Vector3.ZERO
	for db in _debris:
		db.position = Vector3.ZERO
		db.scale = Vector3.ONE
		db.rotation = Vector3.ZERO


func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	var sz := effect_size
	# 亮芯
	_core.scale = Vector3.ONE * sz * (0.4 + (1.0 - t) * 0.5)
	_mat_core.albedo_color.a = 1.0 - t
	# 冲击环
	var rs := sz * (0.2 + t * 2.2)
	_ring.scale = Vector3.ONE * rs
	_mat_ring.albedo_color.a = clamp(0.9 * (1.0 - t), 0.0, 1.0)
	# 星芒（错峰）
	for i in _spikes.size():
		var lt: float = clamp((t - _spike_phase[i]) / maxf(0.001, 1.0 - _spike_phase[i]), 0.0, 1.0)
		var spike_length := _spike_len[i] * (0.25 + lt * 0.95) * sz
		_spikes[i].scale = Vector3(1.0, spike_length, 1.0)
		_spikes[i].position = _spike_dirs[i] * (spike_length * 0.5)
		_mat_spike.albedo_color.a = clamp(1.0 - lt * 1.05, 0.0, 1.0)
	# 碎屑（错峰 + 旋转）
	for i in _debris.size():
		var lt: float = clamp((t - _debris_phase[i]) / maxf(0.001, 1.0 - _debris_phase[i]), 0.0, 1.0)
		var dist := _debris_len[i] * lt * 1.1 * sz
		_debris[i].position = _debris_dirs[i] * dist
		_debris[i].rotation = Vector3(lt * 7.0 * (i + 1), lt * 5.0 * (i + 1), lt * 3.0 * (i + 1))
		_debris[i].scale = Vector3.ONE * sz * (1.0 - lt * 0.4)
		_mat_debris.albedo_color.a = clamp(1.0 - lt * 1.05, 0.0, 1.0)


## 供测试/巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	return {
		"asset_id": get_meta("asset_id", _ASSET_ID),
		"asset_version": get_meta("asset_version", _ASSET_VERSION),
		"node_count": get_child_count(),
		"has_muzzle_light": false,
		"light_name": "",
		"light_energy": 0.0,
		"light_range": 0.0,
		"light_shadows": false,
		"normal": _normal,
		"lifetime": lifetime,
	}
