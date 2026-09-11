class_name VfxMeleeImpact3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-05 / VFX-MELEE-IMPACT-3D 近战命中爆点特效
## 视觉：1 SphereMesh 核心 + 2 TorusMesh 环 + 6 BoxMesh 飞散碎片
## 行为：lifetime 0.32s；核心 + 双环与 impact 类似；6 碎片向外飞散 + 旋转

@export_range(0.05, 0.4, 0.01) var _core_radius: float = 0.19
@export var _fragment_count: int = 6
@export_range(0.05, 0.2, 0.005) var _fragment_size: float = 0.08

var _core: MeshInstance3D
var _ring1: MeshInstance3D
var _ring2: MeshInstance3D
var _fragments: Array[MeshInstance3D] = []
var _mat_core: StandardMaterial3D
var _mat_ring1: StandardMaterial3D
var _mat_ring2: StandardMaterial3D
var _mat_fragment: StandardMaterial3D
var _fragment_dirs: Array[Vector3] = []

func _on_activate(_world_pos: Vector3, color: Color, size: float, _context: Dictionary) -> void:
	lifetime = 0.32
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
		_mat_core.disable_receive_shadows = true
		_core.material_override = _mat_core
		add_child(_core)
	if _ring1 == null:
		_ring1 = MeshInstance3D.new()
		_ring1.name = "Ring1"
		var torus := TorusMesh.new()
		torus.inner_radius = _core_radius * 1.2
		torus.outer_radius = _core_radius * 1.5
		_ring1.mesh = torus
		_mat_ring1 = StandardMaterial3D.new()
		_mat_ring1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ring1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ring1.disable_receive_shadows = true
		_ring1.material_override = _mat_ring1
		add_child(_ring1)
	if _ring2 == null:
		_ring2 = MeshInstance3D.new()
		_ring2.name = "Ring2"
		var torus := TorusMesh.new()
		torus.inner_radius = _core_radius * 1.7
		torus.outer_radius = _core_radius * 2.0
		_ring2.mesh = torus
		_mat_ring2 = StandardMaterial3D.new()
		_mat_ring2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ring2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ring2.disable_receive_shadows = true
		_ring2.material_override = _mat_ring2
		add_child(_ring2)
	if _fragments.is_empty():
		_mat_fragment = StandardMaterial3D.new()
		_mat_fragment.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_fragment.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_fragment.disable_receive_shadows = true
		var box := BoxMesh.new()
		box.size = Vector3(_fragment_size, _fragment_size, _fragment_size)
		for i in _fragment_count:
			var frag := MeshInstance3D.new()
			frag.name = "Fragment%d" % i
			frag.mesh = box
			frag.material_override = _mat_fragment
			# 360° 内均匀分布
			var angle: float = float(i) / float(_fragment_count) * TAU
			_fragment_dirs.append(Vector3(cos(angle), 0.4 + (i % 2) * 0.3, sin(angle)).normalized())
			add_child(frag)
			_fragments.append(frag)
	_core.scale = Vector3.ONE * size
	_ring1.scale = Vector3.ONE * size
	_ring2.scale = Vector3.ONE * size
	for f in _fragments:
		f.scale = Vector3.ONE * size
	_mat_core.albedo_color = Color(1.0, 1.0, 0.95, 1.0)
	_mat_ring1.albedo_color = color
	_mat_ring2.albedo_color = color
	_mat_fragment.albedo_color = color

func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	_core.scale = Vector3.ONE * effect_size * (1.0 - t * 0.5)
	_mat_core.albedo_color.a = 1.0 - t
	var t1: float = clamp(elapsed / 0.18, 0.0, 1.0)
	_ring1.scale = Vector3.ONE * effect_size * (0.4 + t1 * 1.4)
	_mat_ring1.albedo_color.a = 0.9 * (1.0 - t1)
	var t2: float = clamp(elapsed / 0.30, 0.0, 1.0)
	_ring2.scale = Vector3.ONE * effect_size * (0.3 + t2 * 1.7)
	_mat_ring2.albedo_color.a = 0.7 * (1.0 - t2)
	# 碎片向外飞散 + 旋转 + 缩放
	for i in range(_fragments.size()):
		var frag := _fragments[i]
		var dir := _fragment_dirs[i]
		var dist: float = t * 0.5
		frag.position = dir * dist * effect_size
		frag.rotation = Vector3(t * 5.0 * (i + 1), t * 4.0 * (i + 1), t * 3.0 * (i + 1))
		frag.scale = Vector3.ONE * effect_size * (1.0 - t * 0.5)
	_mat_fragment.albedo_color.a = 1.0 - t
