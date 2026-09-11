class_name VfxMeleeSlash3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-04 / VFX-MELEE-SLASH-3D 近战挥砍弧特效
## 视觉：SurfaceTool 自定义三角扇形 + 顶点 alpha 渐隐
## 行为：lifetime 0.28s；扇形从起点向外扫出，alpha 0.85→0
## 备注：方向由 activate 调用方的 rotation 决定；扇形 local 空间绕 +Y 轴展开

@export_range(0.3, 1.2, 0.01) var _inner_radius: float = 0.78
@export_range(0.6, 2.0, 0.01) var _outer_radius: float = 1.42
@export_range(30.0, 120.0, 1.0) var _arc_angle_deg: float = 90.0

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D

func _on_activate(_world_pos: Vector3, color: Color, size: float, _context: Dictionary) -> void:
	lifetime = 0.28
	# 重新构造 mesh（size 不同，弧形半径不同）
	var arc_rad: float = deg_to_rad(_arc_angle_deg)
	var half_arc: float = arc_rad * 0.5
	var seg_count: int = 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg_count):
		var a0: float = -half_arc + (arc_rad * float(i) / float(seg_count))
		var a1: float = -half_arc + (arc_rad * float(i + 1) / float(seg_count))
		var p0: Vector3 = Vector3(sin(a0) * _inner_radius * size, 0.0, cos(a0) * _inner_radius * size)
		var p1: Vector3 = Vector3(sin(a1) * _inner_radius * size, 0.0, cos(a1) * _inner_radius * size)
		var p2: Vector3 = Vector3(sin(a1) * _outer_radius * size, 0.0, cos(a1) * _outer_radius * size)
		var p3: Vector3 = Vector3(sin(a0) * _outer_radius * size, 0.0, cos(a0) * _outer_radius * size)
		# 渐隐：内/外 alpha = 1.0；中间 alpha = 0.6
		st.set_color(Color(color.r, color.g, color.b, 0.85))
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p0)
		st.add_vertex(p2)
		st.add_vertex(p3)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "SlashArc"
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.disable_receive_shadows = true
		_mesh_instance.material_override = _material
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	_material.albedo_color = Color(color.r, color.g, color.b, 0.85)

func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	# alpha 0.85→0；扇形略微外扩
	_material.albedo_color.a = 0.85 * (1.0 - t)
	_mesh_instance.scale = Vector3.ONE * (1.0 + t * 0.15)
