class_name VfxMuzzleFlash3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-01 / VFX-MUZZLE-FLASH-3D 枪口火光特效
## 视觉：1 SphereMesh 闪核（白色核心）+ 1 TorusMesh 环（橙黄外圈）
## 行为：lifetime 0.12s；闪核缩放 1.0→0.3，环缩放 0.5→2.0 + 透明度 0.8→0

@export_range(0.05, 0.5, 0.01) var _core_radius: float = 0.18
@export_range(0.05, 0.5, 0.005) var _ring_thickness: float = 0.045

var _core: MeshInstance3D
var _ring: MeshInstance3D
var _core_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D

func _on_activate(_world_pos: Vector3, color: Color, size: float, _context: Dictionary) -> void:
	lifetime = 0.12
	# 核心球
	if _core == null:
		_core = MeshInstance3D.new()
		_core.name = "Core"
		var sphere := SphereMesh.new()
		sphere.radius = _core_radius
		sphere.height = _core_radius * 2.0
		_core.mesh = sphere
		_core_mat = StandardMaterial3D.new()
		_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_core_mat.albedo_color = Color(1, 1, 1, 1)
		_core_mat.disable_receive_shadows = true
		_core.material_override = _core_mat
		add_child(_core)
	# 环
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.name = "Ring"
		var torus := TorusMesh.new()
		torus.inner_radius = _core_radius * 1.3
		torus.outer_radius = _core_radius * 2.0
		_ring.mesh = torus
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.albedo_color = color
		_ring_mat.disable_receive_shadows = true
		_ring.material_override = _ring_mat
		add_child(_ring)
	# 缩放
	_core.scale = Vector3.ONE * size
	_ring.scale = Vector3.ONE * size
	# 颜色：核白色 + 环按调用方
	_core_mat.albedo_color = Color(1.0, 1.0, 0.9, 1.0)
	_ring_mat.albedo_color = color

func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	# 核心：1.0→0.3
	_core.scale = Vector3.ONE * effect_size * (1.0 - t * 0.7)
	_core_mat.albedo_color.a = 1.0 - t
	# 环：0.5→2.0，alpha 0.8→0
	_ring.scale = Vector3.ONE * effect_size * (0.5 + t * 1.5)
	_ring_mat.albedo_color.a = 0.8 * (1.0 - t)
