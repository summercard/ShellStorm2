class_name VfxBulletBody3D
extends VfxEffectBase3D
## 八个弹种专属弹体视觉（弹体 + 尾迹）的共享基类（纯视觉：无碰撞体、不含玩法行为）。
##
## 契约与 r26 通用弹体 `VFX-BULLET-VISUAL-3D` 完全一致：
##   - 由 `Projectile3D` 作为子节点持有，生命周期随 `ProjectilePool3D`；
##   - 刻意**不进** `VfxPool3D` 注册表，避免弹体池与特效池双重 ownership；
##   - 只暴露公共接口（configure / activate / deactivate / set_trail_visible /
##     apply_growth / get_presentation_snapshot），调用方不得直接改子节点。
##
## 子类**只**覆写 `_bullet_profile()`：声明本弹种的弹体形态、配色、尾迹构图与灯参数。
## 八条设计原文取自内容库《武器》S 列（每弹种「武器/战斗表现」），见各子类头部注释。
##
## 去版本化：运行资产路径不含 `_vNNN`；版本号只落 Prefab 根 meta + 账本版本列。

# ---- 低面数档（2026-10-14 业主「减面，减到 100 个面以下先」）----
# 分段参数取值依据 = 实测扫描 `_scratch/probe_mesh_lod_sweep`（不靠估算）：
#
#   CapsuleMesh : rings=0 → 24 面（= 圆柱 + 2 片平盖扇），rings=1 → 48 面
#   CylinderMesh: rings=0 → 16 面     ← 同等轮廓下**严格省于** CapsuleMesh(rings=0)
#   CylinderMesh(锥, top_radius=0) : → 20 面
#   SphereMesh  : rings=1 → 16 面（最小有效值；rings=0 无效）
#   BoxMesh     : → 12 面             ← 全表最省
#
# 关键发现：CapsuleMesh 的**圆头来自 rings**，而 rings=0 的「胶囊」就是平盖圆柱再贵 8 面。
# 100 面预算下买不起圆头（rings=1 要 48 面/件，两件就吃掉全部预算），
# ⇒ 弹芯与外壳一律改用**低面数棱柱**（4 边圆柱），轮廓与 rings=0 的胶囊一致但更省。
#
# 单弹总面数（每件：弹芯 + 外壳 + 尾迹…）：
#   单锥 52 / 双锥 72 / 三锥 92 / 锥+3 滴珠 88 / 锥+3 火星 88   ⇒ 全部 < 100（改前 468~1020）
const MESH_SEGMENTS := 4   # 弹芯/外壳/尾迹的径向分段（4 边棱柱）
const MESH_RINGS := 0      # 圆柱高度分段（0 = 不细分）
const SPHERE_SEGMENTS := 4 # 球体分段（黑洞/气球弹的球核）
const SPHERE_RINGS := 1    # 球体最小有效 rings
const BEAD_BOX_SIZE := 1.0 # 滴珠用立方体（BoxMesh，12 面）而非球（16 面）—— 尺寸按半径 ×2

# ---- 共享 mesh 缓存：同一弹种几何跨实例复用（mesh 数据不可变，安全共享）----
# 键 = 形状参数串；material 仍按实例持有，因为子弹色逐发可变。
static var _prism_cache: Dictionary = {}
static var _sphere_cache: Dictionary = {}
static var _cone_cache: Dictionary = {}
static var _bead_cache: Dictionary = {}


## 弹芯/外壳的「低面数棱柱」：CylinderMesh（上下同半径），径向 4 段。
static func _cached_prism(key: String, radius: float, height: float) -> Mesh:
	if not _prism_cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = height
		c.radial_segments = MESH_SEGMENTS
		c.rings = MESH_RINGS
		_prism_cache[key] = c
	return _prism_cache[key]


static func _cached_sphere(key: String, radius: float) -> Mesh:
	if not _sphere_cache.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = SPHERE_SEGMENTS
		s.rings = SPHERE_RINGS
		_sphere_cache[key] = s
	return _sphere_cache[key]


## 锥体：Godot 4.x 无 ConeMesh，用 CylinderMesh(top_radius = 0) 实现（尖端在 +Y）。
static func _cached_cone(key: String, bottom_radius: float, height: float) -> Mesh:
	if not _cone_cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = bottom_radius
		c.height = height
		c.radial_segments = MESH_SEGMENTS
		c.rings = MESH_RINGS
		_cone_cache[key] = c
	return _cone_cache[key]


## 滴珠：低面数档下改用 BoxMesh 立方体（12 面 / 16 面），半径即半边长 ×2。
## 滴珠世界尺寸只有 0.011~0.018m，球与立方体在实机上不可分辨，省下的 4 面用于保住尾迹锥。
static func _cached_bead(key: String, radius: float) -> Mesh:
	if not _bead_cache.has(key):
		var b := BoxMesh.new()
		b.size = Vector3.ONE * radius * 2.0 * BEAD_BOX_SIZE
		_bead_cache[key] = b
	return _bead_cache[key]


# ---- 默认 profile：中性直弹（子类全部覆写）----
const _DEFAULT_PROFILE := {
	# 弹芯（亮芯，沿 local -Z 前向；低面数档 = 4 边棱柱）
	"core_shape": "prism",
	"core_radius": 0.045,
	"core_height": 0.20,
	"core_color": Color(0.92, 0.96, 1.0),
	"core_emission": 2.2,
	# 外壳（弹色半透明）
	"shell_shape": "prism",
	"shell_radius": 0.075,
	"shell_height": 0.18,
	"shell_alpha": 1.0,
	"shell_emission": 1.6,
	# 尾迹（向 local +Z 身后）
	"trail_style": "cone",
	"trail_alpha": 0.36,
	"trail_emission": 1.4,
	"trail_anim": "none",
	# 灯
	"light_energy": 1.2,
	"light_range": 1.8,
	# 脉动
	"pulse_rate": 8.5,
	"pulse_amplitude": 0.05,
}

var _body_root: Node3D
var _core: MeshInstance3D
var _shell: MeshInstance3D
var _trail_root: Node3D
var _trail_parts: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _trail_material: StandardMaterial3D
var _base_scale := 1.0
var _pulse_phase := 0.0
var _profile: Dictionary = {}
## 枪身维度的弹体几何修饰（2026-10-14 业主：每把枪的子弹大小要做出区分）。
## 由调用方经 `activate(..., context)` 下发；缺省一律中性（不改观感）。
##   - `axial_scale`  ：沿飞行轴（local Z）拉长的倍率 —— 狙击枪用（弹体变长）。
##   - `grow_from`    ：出生瞬间的尺寸比例，飞行中线性长到 1.0 —— 霰弹枪用（由小变大）。
##   - `grow_duration`：长到 1.0 所需秒数；`0` 表示不启用生长包络。
## 三条只作用于纯视觉几何：不改碰撞半径、伤害与射程（碰撞半径在调用方另行缩放）。
var _axial_scale := 1.0
var _grow_from := 1.0
var _grow_duration := 0.0
var _flight_time := 0.0


## 子类覆写点：返回本弹种的视觉 profile（缺省键由 _DEFAULT_PROFILE 补齐）。
func _bullet_profile() -> Dictionary:
	return {}


func _ready() -> void:
	_profile = _DEFAULT_PROFILE.duplicate(true)
	var override := _bullet_profile()
	for key in override.keys():
		_profile[key] = override[key]
	_build_visual()
	_apply_geometry_scale()


func _build_visual() -> void:
	_body_root = Node3D.new()
	_body_root.name = "BulletRoot"
	add_child(_body_root)

	# 外壳：弹色半透明（略大），先建以便弹芯叠在其内。
	_shell_material = StandardMaterial3D.new()
	_shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_material.albedo_color = _shell_default_color()
	_shell_material.metallic = 0.0
	_shell_material.roughness = float(_profile.get("shell_roughness", 0.35))
	_shell_material.emission_enabled = true
	_shell_material.emission = _shell_default_color()
	_shell_material.emission_energy_multiplier = float(_profile.get("shell_emission", 1.6))
	_shell = _make_body_piece("Shell", _shell_material)
	_shell.rotation_degrees.x = -90.0

	# 弹芯：亮芯（长轴朝 -Z 前向）。
	var core_color: Color = _profile.get("core_color", Color(0.92, 0.96, 1.0))
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = core_color
	_core_material.metallic = 0.0
	_core_material.roughness = 0.25
	_core_material.emission_enabled = true
	_core_material.emission = core_color
	_core_material.emission_energy_multiplier = float(_profile.get("core_emission", 2.2))
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core = _make_body_piece("Core", _core_material)
	_core.rotation_degrees.x = -90.0

	_build_trail()
	_build_light()


## 按 profile 的 shell_shape / core_shape 建弹体件（capsule / sphere）。
func _make_body_piece(piece_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var is_core := piece_name == "Core"
	var shape := String(_profile.get("core_shape" if is_core else "shell_shape", "prism"))
	var radius := float(_profile.get("core_radius" if is_core else "shell_radius", 0.045))
	var height := float(_profile.get("core_height" if is_core else "shell_height", 0.20))
	var mesh: Mesh
	if shape == "sphere":
		mesh = _cached_sphere("%s|%.4f" % [piece_name, radius], radius)
	elif shape == "capsule":
		# 兼容旧键：低面数档下按棱柱产出，避免误用高价 CapsuleMesh 冲破面数预算。
		mesh = _cached_prism("%s|%.4f|%.4f" % [piece_name, radius, height], radius, height)
	else:
		mesh = _cached_prism("%s|%.4f|%.4f" % [piece_name, radius, height], radius, height)
	var node := MeshInstance3D.new()
	node.name = piece_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_root.add_child(node)
	return node


func _shell_default_color() -> Color:
	return _profile.get("shell_color", Color(0.45, 0.88, 1.0)) as Color


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "ProjectileLight"
	_light.shadow_enabled = false
	_light.light_energy = float(_profile.get("light_energy", 1.2))
	_light.omni_range = float(_profile.get("light_range", 1.8))
	_light.light_color = _shell_default_color()
	_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 55.0
	_light.distance_fade_length = 15.0
	add_child(_light)


## 尾迹构图：全部由 profile 声明，基类统一建造（锥段 / 小珠 / 火星条）。
## 每段用同一个 _trail_material（弹色），逐段明暗靠 alpha 分量与缩放，逐帧只动 transform。
func _build_trail() -> void:
	_trail_root = Node3D.new()
	_trail_root.name = "Trail"
	_body_root.add_child(_trail_root)

	_trail_material = StandardMaterial3D.new()
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.albedo_color = Color(0.45, 0.88, 1.0, float(_profile.get("trail_alpha", 0.36)))
	_trail_material.metallic = 0.0
	_trail_material.roughness = float(_profile.get("trail_roughness", 0.5))
	_trail_material.emission_enabled = true
	_trail_material.emission = Color(0.45, 0.88, 1.0)
	_trail_material.emission_energy_multiplier = float(_profile.get("trail_emission", 1.4))

	for spec in _trail_segments():
		var offset_z := float(spec.get("z", 0.25))
		var bottom_radius := float(spec.get("radius", 0.06))
		var height := float(spec.get("height", 0.5))
		var alpha_mul := float(spec.get("alpha", 1.0))
		var piece := MeshInstance3D.new()
		piece.name = "TrailSeg%d" % _trail_parts.size()
		piece.mesh = _cached_cone(
			"trail|%.4f|%.4f" % [bottom_radius, height], bottom_radius, height
		)
		piece.material_override = _trail_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 锥尖朝 +Y，旋转 +90° 让尖端朝 -Z（前方），宽端拖向 +Z（身后）。
		piece.rotation_degrees.x = 90.0
		piece.position.z = offset_z
		piece.set_meta("trail_alpha_mul", alpha_mul)
		# 记录基准轴向偏移：枪身轴向拉伸要同步拉开段距，否则段与段会脱节。
		piece.set_meta("trail_base_z", offset_z)
		_trail_root.add_child(piece)
		_trail_parts.append(piece)

	for spec in _trail_beads():
		var offset_z := float(spec.get("z", 0.5))
		var radius := float(spec.get("radius", 0.02))
		var piece := MeshInstance3D.new()
		piece.name = "TrailBead%d" % _trail_parts.size()
		piece.mesh = _cached_bead("bead|%.4f" % radius, radius)
		piece.material_override = _trail_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.position = Vector3(float(spec.get("x", 0.0)), float(spec.get("y", 0.0)), offset_z)
		piece.set_meta("trail_alpha_mul", float(spec.get("alpha", 1.0)))
		piece.set_meta("trail_base_z", offset_z)
		_trail_root.add_child(piece)
		_trail_parts.append(piece)

	for spec in _trail_sparks():
		var offset: Vector3 = spec.get("offset", Vector3(0.0, 0.0, 0.4))
		var length := float(spec.get("length", 0.22))
		var b := BoxMesh.new()
		b.size = Vector3(0.03, 0.03, length)
		var piece := MeshInstance3D.new()
		piece.name = "TrailSpark%d" % _trail_parts.size()
		piece.mesh = b
		piece.material_override = _trail_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.position = offset
		piece.set_meta("trail_alpha_mul", float(spec.get("alpha", 0.8)))
		piece.set_meta("trail_base_z", offset.z)
		_trail_root.add_child(piece)
		_trail_parts.append(piece)


## 尾迹锥段构图（子类覆写或经 profile 声明）。缺省三段渐缩锥。
func _trail_segments() -> Array:
	if _profile.has("trail_segments"):
		return _profile["trail_segments"] as Array
	return [{"z": 0.25, "radius": 0.06, "height": 0.5, "alpha": 1.0}]


func _trail_beads() -> Array:
	return _profile.get("trail_beads", []) as Array


func _trail_sparks() -> Array:
	return _profile.get("trail_sparks", []) as Array


func configure(color: Color, size: float = 1.0, context: Dictionary = {}) -> void:
	super.configure(color, size, context)
	_base_scale = size
	# 枪身维度几何修饰：每次 configure 一律重算并回落中性缺省，
	# 池化复借时不得残留上一发的枪身档位（拉伸 / 生长进度）。
	_axial_scale = maxf(0.05, float(context.get("axial_scale", 1.0)))
	_grow_from = clampf(float(context.get("grow_from", 1.0)), 0.05, 1.0)
	_grow_duration = maxf(0.0, float(context.get("grow_duration", 0.0)))
	_flight_time = 0.0
	_apply_geometry_scale()
	# 复借复色：外壳/尾迹/灯用子弹色；亮芯保持自身亮色。
	if _shell_material != null:
		_shell_material.albedo_color = color
		_shell_material.emission = color
	if _trail_material != null:
		var trail_alpha := float(_profile.get("trail_alpha", 0.36))
		_trail_material.albedo_color = Color(color.r, color.g, color.b, trail_alpha)
		_trail_material.emission = color
	if _light != null:
		_light.light_color = color


func activate(world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	configure(color, size, context)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	# 作为投射物子节点：保持 local 原点，跟随宿主变换，不叠加 global 偏移。
	position = Vector3.ZERO
	_on_activate(world_position, color, size, context)
	_elapsed = 0.0
	if _light != null:
		_light.visible = true
		_light.light_energy = float(_profile.get("light_energy", 1.2))
	if _body_root != null:
		_body_root.visible = true
	set_trail_visible(true)


func deactivate() -> void:
	_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	# 几何修饰一并复位：复借的下一发不得继承上一发的枪身档位。
	_axial_scale = 1.0
	_grow_from = 1.0
	_grow_duration = 0.0
	_flight_time = 0.0
	_apply_geometry_scale()
	# 隐藏灯与主体；灯能量归零（回收必须归零）。不 emit retired、不 queue_free，随宿主离树释放。
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false
	if _body_root != null:
		_body_root.visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	# 仅做轻微脉动与尾迹动画，不自动 retire（生命周期由宿主 Projectile3D 管理）。
	_pulse_phase += delta
	_flight_time += delta
	var rate := float(_profile.get("pulse_rate", 8.5))
	var ampl := float(_profile.get("pulse_amplitude", 0.05))
	var pulse := 1.0 + sin(_pulse_phase * rate) * ampl
	if _body_root != null:
		_body_root.scale = Vector3.ONE * _base_scale * pulse * _growth_factor()
	_animate_trail()


## 尾迹动画（确定性，不使用随机数——本类被逐帧断言驱动）。
func _animate_trail() -> void:
	var anim := String(_profile.get("trail_anim", "none"))
	if anim == "none" or _trail_root == null:
		return
	if anim == "spin":
		_trail_root.rotation.z += 0.18
	elif anim == "wave":
		for index in _trail_parts.size():
			var piece := _trail_parts[index]
			piece.position.x = sin(_pulse_phase * 6.0 + float(index) * 0.9) * 0.05
	elif anim == "flicker":
		var k := 0.85 + 0.3 * absf(sin(_pulse_phase * 24.0))
		_trail_root.scale = Vector3(k, k, 1.0)
	elif anim == "drip":
		for index in _trail_parts.size():
			var piece := _trail_parts[index]
			piece.position.y = -absf(sin(_pulse_phase * 3.2 + float(index) * 1.7)) * 0.04


## 纯视觉：切换尾迹可见性（炮台形态等玩法调用）。
func set_trail_visible(visible_state: bool) -> void:
	if _trail_root != null:
		_trail_root.visible = visible_state


## 纯视觉：按倍率增长几何（命运 growth 等玩法调用）。不改变碰撞/伤害。
func apply_growth(factor: float) -> void:
	if factor <= 0.0:
		return
	_base_scale *= factor
	_apply_geometry_scale()


## 生长包络：出生为 `grow_from`，到 `grow_duration` 线性长到 1.0（霰弹枪「由小变大」）。
## 确定性：只读 `_flight_time`，不使用随机数（本类被逐帧断言驱动）。
func _growth_factor() -> float:
	if _grow_duration <= 0.0 or _grow_from >= 1.0:
		return 1.0
	var t: float = clampf(_flight_time / _grow_duration, 0.0, 1.0)
	return lerpf(_grow_from, 1.0, t)


func _apply_geometry_scale() -> void:
	if _body_root == null:
		return
	# 各向同性部分落 _body_root；轴向拉伸落在各件自己的局部长轴上 —— 这样不会与
	# 子节点的旋转（弹芯 -90° / 尾迹锥 +90° / 黑洞 spin）叠加出剪切变形。
	_body_root.scale = Vector3.ONE * _base_scale * _growth_factor()
	_apply_axial_scale()


## 轴向拉伸：只改各件的局部长轴缩放与尾迹段距，绝不写父级 scale / rotation。
## 父级非均匀缩放 × 子级旋转 = 剪切变形（同 skill §5.5.1 坑 3 的同源问题）。
## 不提前 return：`_axial_scale` 回到 1.0 时也必须把上一次的拉伸收回。
func _apply_axial_scale() -> void:
	if _core != null:
		_core.scale = Vector3(1.0, _axial_scale, 1.0)
	if _shell != null:
		_shell.scale = Vector3(1.0, _axial_scale, 1.0)
	for piece in _trail_parts:
		var base_z: float = float(piece.get_meta("trail_base_z", piece.position.z))
		piece.position.z = base_z * _axial_scale
		if piece.name.begins_with("TrailSpark"):
			piece.scale = Vector3(1.0, 1.0, _axial_scale)
		elif piece.name.begins_with("TrailSeg"):
			piece.scale = Vector3(1.0, _axial_scale, 1.0)
		# TrailBead 只挪位置：滴珠是球体，拉伸会变成怪椭球，不参与轴向变形。


## 呈现快照：供调用方/测试读取，不写入 res://。
func get_presentation_snapshot() -> Dictionary:
	var light_energy := 0.0
	var light_range := 0.0
	var light_visible := false
	if _light != null:
		light_energy = _light.light_energy
		light_range = _light.omni_range
		light_visible = _light.visible
	var trail_z := 0.0
	var trail_behind := false
	if _trail_root != null and not _trail_parts.is_empty():
		trail_z = _trail_parts[0].position.z
		trail_behind = trail_z > 0.0
	var body_scale := 0.0
	if _body_root != null:
		body_scale = _body_root.scale.x
	return {
		"asset_id": get_meta("asset_id", ""),
		"asset_version": get_meta("asset_version", "v001"),
		"bullet_profile": String(_profile.get("key", "")),
		"light_name": "ProjectileLight" if _light != null else "",
		"light_energy": light_energy,
		"light_range": light_range,
		"light_visible": light_visible,
		"light_shadows": false,
		"trail_style": String(_profile.get("trail_style", "cone")),
		"trail_parts": _trail_parts.size(),
		"trail_local_z": trail_z,
		"trail_is_behind": trail_behind,
		"core_shape": String(_profile.get("core_shape", "capsule")),
		"core_radius": float(_profile.get("core_radius", 0.045)),
		"base_scale": _base_scale,
		"body_scale": body_scale,
		"axial_scale": _axial_scale,
		"core_axis_scale": _core.scale.y if _core != null else 0.0,
		"grow_from": _grow_from,
		"grow_duration": _grow_duration,
		"flight_time": _flight_time,
		"growth_factor": _growth_factor(),
		"node_count": get_child_count(),
	}
