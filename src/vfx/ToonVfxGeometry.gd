extends RefCounted
## 私有静态 mesh / material 工具（无 class_name；由 VfxMuzzleFlash3D / VfxImpact3D 通过 preload 调用）。
## 设计约束：
##   - 所有 mesh 首次生成后缓存在静态变量中跨实例复用（mesh 数据不可变，安全共享）。
##   - material 由调用方在实例内首次创建并持有（实例级复用），本文件只负责生成。
##   - 不引用任何不存在的图元（如 ConeMesh）；楔形火焰用 CylinderMesh(top_radius=0) 实现。

# ---- 静态 mesh 缓存 ----
static var _core_mesh: Mesh = null
static var _flame_mesh: Mesh = null
static var _petal_mesh: Mesh = null
static var _ring_mesh: Mesh = null
static var _spark_mesh: Mesh = null
static var _spike_mesh: Mesh = null
static var _debris_mesh: Mesh = null


static func core_mesh() -> Mesh:
	if _core_mesh == null:
		var s := SphereMesh.new()
		s.radius = 0.18
		s.height = 0.36
		_core_mesh = s
	return _core_mesh


static func flame_mesh() -> Mesh:
	# 立体楔形火焰：CylinderMesh + top_radius=0（棱锥/锥），radial_segments 低以保证清晰尖瓣。
	if _flame_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.34
		c.height = 1.0
		c.radial_segments = 6
		_flame_mesh = c
	return _flame_mesh


static func petal_mesh() -> Mesh:
	# 交叉面尖瓣用的平面片（QuadMesh/PlaneMesh）。
	if _petal_mesh == null:
		var p := PlaneMesh.new()
		p.size = Vector2(0.6, 1.2)
		_petal_mesh = p
	return _petal_mesh


static func ring_mesh() -> Mesh:
	if _ring_mesh == null:
		var t := TorusMesh.new()
		t.inner_radius = 0.6
		t.outer_radius = 0.72
		_ring_mesh = t
	return _ring_mesh


static func spark_mesh() -> Mesh:
	# 火星：细长条（长轴沿本地 Z）。
	if _spark_mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 0.05, 0.34)
		_spark_mesh = b
	return _spark_mesh


static func spike_mesh() -> Mesh:
	# 星芒：细长子（长轴沿本地 Y，便于用 Quaternion(UP, dir) 对齐放射方向）。
	if _spike_mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.04, 1.0, 0.04)
		_spike_mesh = b
	return _spike_mesh


static func debris_mesh() -> Mesh:
	if _debris_mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.08, 0.08, 0.18)
		_debris_mesh = b
	return _debris_mesh


## 生成一份卡通无光照半透明材质（调用方持有并复用）。
## emission_boost>0 时开启自发光以提升亮芯/火星的通透感，但保持不泛白的饱和层次。
static func toon_material(base_color: Color, emission_boost: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = base_color
	m.disable_receive_shadows = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.no_depth_test = false
	if emission_boost > 0.0:
		m.emission_enabled = true
		m.emission = base_color
		m.emission_energy_multiplier = emission_boost
	return m
