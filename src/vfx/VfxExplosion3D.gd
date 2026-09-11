class_name VfxExplosion3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-03 / VFX-EXPLOSION-3D 爆炸特效
## 视觉：1 SphereMesh 核心 + 2 TorusMesh 冲击波环（径向波 + 二次环）
## 行为：lifetime 0.46s；核心 1.0→2.0 扩大+淡出，双环错峰扩散

@export_range(0.2, 0.8, 0.01) var _core_radius: float = 0.42

var _core: MeshInstance3D
var _ring1: MeshInstance3D
var _ring2: MeshInstance3D
var _mat_core: StandardMaterial3D
var _mat_ring1: StandardMaterial3D
var _mat_ring2: StandardMaterial3D

func _on_activate(_world_pos: Vector3, color: Color, size: float, _context: Dictionary) -> void:
	lifetime = 0.46
	if _core == null:
		_core = MeshInstance3D.new()
		_core.name = "Core"
		var sphere := SphereMesh.new()
		sphere.radius = _core_radius
		sphere.height = _core_radius * 2.0
		_core.mesh = sphere
		_mat_core = StandardMaterial3D.new()
		_mat_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_core.albedo_color = color
		_mat_core.disable_receive_shadows = true
		_core.material_override = _mat_core
		add_child(_core)
	if _ring1 == null:
		_ring1 = MeshInstance3D.new()
		_ring1.name = "Ring1"
		var torus := TorusMesh.new()
		torus.inner_radius = _core_radius * 1.1
		torus.outer_radius = _core_radius * 1.4
		_ring1.mesh = torus
		_mat_ring1 = StandardMaterial3D.new()
		_mat_ring1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ring1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ring1.albedo_color = color
		_mat_ring1.disable_receive_shadows = true
		_ring1.material_override = _mat_ring1
		add_child(_ring1)
	if _ring2 == null:
		_ring2 = MeshInstance3D.new()
		_ring2.name = "Ring2"
		var torus := TorusMesh.new()
		torus.inner_radius = _core_radius * 1.6
		torus.outer_radius = _core_radius * 1.95
		_ring2.mesh = torus
		_mat_ring2 = StandardMaterial3D.new()
		_mat_ring2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ring2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ring2.albedo_color = color
		_mat_ring2.disable_receive_shadows = true
		_ring2.material_override = _mat_ring2
		add_child(_ring2)
	_core.scale = Vector3.ONE * size
	_ring1.scale = Vector3.ONE * size
	_ring2.scale = Vector3.ONE * size
	_mat_core.albedo_color = color
	_mat_ring1.albedo_color = color
	_mat_ring2.albedo_color = color

func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	# 核心 1.0→2.0 + alpha 1.0→0
	_core.scale = Vector3.ONE * effect_size * (1.0 + t * 1.0)
	_mat_core.albedo_color.a = (1.0 - t) * 0.95
	# 环 1: 0.5→1.8 + alpha 0.8→0
	var t1: float = clamp(elapsed / 0.30, 0.0, 1.0)
	_ring1.scale = Vector3.ONE * effect_size * (0.5 + t1 * 1.3)
	_mat_ring1.albedo_color.a = 0.8 * (1.0 - t1)
	# 环 2: 0.3→2.2 延迟启动（lifetime 0.10 后） + alpha 0.6→0
	var t2: float = clamp((elapsed - 0.10) / 0.30, 0.0, 1.0)
	_ring2.scale = Vector3.ONE * effect_size * (0.3 + t2 * 1.9)
	_mat_ring2.albedo_color.a = 0.6 * (1.0 - t2)
