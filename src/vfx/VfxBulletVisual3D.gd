class_name VfxBulletVisual3D
extends VfxEffectBase3D
## 独立子弹纯视觉 Prefab（第三类 VFX：子弹，不是爆炸）。
## 由 ProjectilePool3D 宿主生命周期管理，不放 VfxPool 自动计时，避免双池 ownership。
## 调用方只能使用公共接口（configure / activate / deactivate / get_presentation_snapshot /
## set_trail_visible / apply_growth），不能直接改动子节点接管内在视觉。

const _CORE_COLOR := Color(0.92, 0.96, 1.0)
const _TRAIL_ALPHA := 0.36
const _LIGHT_ENERGY := 1.2
const _LIGHT_RANGE := 1.8

var _root: Node3D
var _core: MeshInstance3D
var _shell: MeshInstance3D
var _trail: MeshInstance3D
var _light: OmniLight3D
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _trail_material: StandardMaterial3D
var _base_scale := 1.0
var _pulse_phase := 0.0


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	_root = Node3D.new()
	_root.name = "BulletRoot"
	add_child(_root)

	# 白金亮芯：细长胶囊，长轴朝 -Z（前向）。
	var core_mesh := CapsuleMesh.new()
	core_mesh.radius = 0.045
	core_mesh.height = 0.20
	core_mesh.radial_segments = 10
	core_mesh.rings = 4
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = _CORE_COLOR
	_core_material.metallic = 0.0
	_core_material.roughness = 0.25
	_core_material.emission_enabled = true
	_core_material.emission = _CORE_COLOR
	_core_material.emission_energy_multiplier = 2.2
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = core_mesh
	_core.material_override = _core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.rotation_degrees.x = -90.0
	_root.add_child(_core)

	# 高饱和外壳：略大的胶囊，使用子弹色，半透明发光。
	var shell_mesh := CapsuleMesh.new()
	shell_mesh.radius = 0.075
	shell_mesh.height = 0.18
	shell_mesh.radial_segments = 12
	shell_mesh.rings = 4
	_shell_material = StandardMaterial3D.new()
	_shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_material.albedo_color = Color(0.45, 0.88, 1.0)
	_shell_material.metallic = 0.0
	_shell_material.roughness = 0.35
	_shell_material.emission_enabled = true
	_shell_material.emission = Color(0.45, 0.88, 1.0)
	_shell_material.emission_energy_multiplier = 1.6
	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	_shell.mesh = shell_mesh
	_shell.material_override = _shell_material
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.rotation_degrees.x = -90.0
	_root.add_child(_shell)

	# 真正渐缩的锥形拖尾：朝 +Z（后方），宽端贴弹体、尖端拖向尾部。
	# Godot 4.x 无 ConeMesh；锥体用 CylinderMesh(top_radius=0) 实现：尖端在 +Y，底圆在 -Y。
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.0
	trail_mesh.bottom_radius = 0.06
	trail_mesh.height = 0.5
	trail_mesh.radial_segments = 12
	_trail_material = StandardMaterial3D.new()
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.albedo_color = Color(0.45, 0.88, 1.0, _TRAIL_ALPHA)
	_trail_material.metallic = 0.0
	_trail_material.roughness = 0.5
	_trail_material.emission_enabled = true
	_trail_material.emission = Color(0.45, 0.88, 1.0)
	_trail_material.emission_energy_multiplier = 1.4
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail.mesh = trail_mesh
	_trail.material_override = _trail_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.rotation_degrees.x = 90.0
	_trail.position.z = 0.25
	_root.add_child(_trail)

	# 每弹一盏灯：无阴影、能量 1.2、范围 1.8；回收必须归零。
	_light = OmniLight3D.new()
	_light.name = "ProjectileLight"
	_light.shadow_enabled = false
	_light.light_energy = _LIGHT_ENERGY
	_light.omni_range = _LIGHT_RANGE
	_light.light_color = Color(0.45, 0.88, 1.0)
	add_child(_light)


func configure(color: Color, size: float = 1.0, context: Dictionary = {}) -> void:
	super.configure(color, size, context)
	_base_scale = size
	_apply_geometry_scale()
	# 复借复色：外壳/拖尾用子弹色；亮芯保持白金；灯色跟随子弹色。
	if _core_material != null:
		_core_material.albedo_color = _CORE_COLOR
		_core_material.emission = _CORE_COLOR
	if _shell_material != null:
		_shell_material.albedo_color = color
		_shell_material.emission = color
	if _trail_material != null:
		_trail_material.albedo_color = Color(color.r, color.g, color.b, _TRAIL_ALPHA)
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
	# 复借复位：重新点亮并恢复拖尾可见。
	if _light != null:
		_light.visible = true
		_light.light_energy = _LIGHT_ENERGY
	if _root != null:
		_root.visible = true
	set_trail_visible(true)


func deactivate() -> void:
	_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	# 隐藏灯与根；灯能量归零（回收必须归零）。不 emit retired、不 queue_free，随宿主离树释放。
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false
	if _root != null:
		_root.visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	# 仅做轻微脉动，不自动 retire（生命周期由宿主 Projectile3D 管理）。
	_pulse_phase += delta
	var pulse := 1.0 + sin(_pulse_phase * 8.5) * 0.05
	if _root != null:
		_root.scale = Vector3.ONE * _base_scale * pulse


## 纯视觉：切换拖尾可见性（炮台形态隐藏拖尾）。
func set_trail_visible(visible_state: bool) -> void:
	if _trail != null:
		_trail.visible = visible_state


## 纯视觉：按倍率增长几何（命运 growth 等玩法调用）。不改变碰撞/伤害。
func apply_growth(factor: float) -> void:
	if factor <= 0.0:
		return
	_base_scale *= factor
	_apply_geometry_scale()


func _apply_geometry_scale() -> void:
	if _root != null:
		_root.scale = Vector3.ONE * _base_scale


## 呈现快照：供调用方/测试读取，不写入 res://。
func get_presentation_snapshot() -> Dictionary:
	var light_energy := 0.0
	var light_range := 0.0
	var light_visible := false
	if _light != null:
		light_energy = _light.light_energy
		light_range = _light.omni_range
		light_visible = _light.visible
	var trail_pos := Vector3.ZERO
	var trail_behind := false
	if _trail != null:
		trail_pos = _trail.position
		trail_behind = _trail.position.z > 0.0
	return {
		"asset_id": get_meta("asset_id", "VFX-BULLET-VISUAL-3D"),
		"asset_version": get_meta("asset_version", "v001"),
		"light_name": "ProjectileLight" if _light != null else "",
		"light_energy": light_energy,
		"light_range": light_range,
		"light_visible": light_visible,
		"light_shadows": false,
		"trail_local_position": trail_pos,
		"trail_is_behind": trail_behind,
		"forward": (-global_basis.z) if is_inside_tree() else Vector3(0.0, 0.0, -1.0),
		"base_scale": _base_scale,
		"node_count": get_child_count(),
	}
