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
## 引擎侧超距淡出（米，相对当前激活相机）。子弹灯自身范围只有 1.8m：
## 飞出 55m 后它照亮的地面已是不可分辨的像素，把能量淡到 0 不影响近场观感，
## 但能省掉远距离子弹的灯光着色。
const _LIGHT_FADE_BEGIN := 55.0
const _LIGHT_FADE_LENGTH := 15.0

# ---- 共享几何（零视觉损失）----
# 同一 Prefab 的弹体几何对所有实例完全相同，且建模后不再改动 ⇒ 跨实例复用同一份
# mesh 资源（与 src/vfx/ToonVfxGeometry.gd 同口径）。材质仍按实例持有，因为子弹色逐发可变。
static var _shared_core_mesh_cache: Mesh = null
static var _shared_shell_mesh_cache: Mesh = null
static var _shared_trail_mesh_cache: Mesh = null


## 低面数档（2026-10-14 业主「减面，减到 100 个面以下先」）：本体与 8 个弹种专属视觉
## 同口径 —— 弹芯/外壳用 4 边棱柱（CylinderMesh，16 面），尾迹锥 4 段（20 面），
## 单弹合计 52 面（改前 792 面）。取值依据见 `_scratch/probe_mesh_lod_sweep`。
const _SEGMENTS := 4


static func _shared_core_mesh() -> Mesh:
	if _shared_core_mesh_cache == null:
		var core := CylinderMesh.new()
		core.top_radius = 0.045
		core.bottom_radius = 0.045
		core.height = 0.20
		core.radial_segments = _SEGMENTS
		core.rings = 0
		_shared_core_mesh_cache = core
	return _shared_core_mesh_cache


static func _shared_shell_mesh() -> Mesh:
	if _shared_shell_mesh_cache == null:
		var shell := CylinderMesh.new()
		shell.top_radius = 0.075
		shell.bottom_radius = 0.075
		shell.height = 0.18
		shell.radial_segments = _SEGMENTS
		shell.rings = 0
		_shared_shell_mesh_cache = shell
	return _shared_shell_mesh_cache


static func _shared_trail_mesh() -> Mesh:
	if _shared_trail_mesh_cache == null:
		var trail := CylinderMesh.new()
		trail.top_radius = 0.0
		trail.bottom_radius = 0.06
		trail.height = 0.5
		trail.radial_segments = _SEGMENTS
		trail.rings = 0
		_shared_trail_mesh_cache = trail
	return _shared_trail_mesh_cache

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
## 敌方子弹的 billboard 图标（2026-11-09 主人：「敌方子弹也一样」）。
##
## 这个类就是**敌方子弹实际走的那条路由**：`WeaponModel3D` 只给玩家子弹填 `visual_id`，
## 敌人 `Enemy3D._launch_projectile()` 不填 ⇒ `Projectile3D._visual_scene_for("")` 落到
## 通用弹体 Prefab，脚本即本类。八弹种的 `VfxBulletBody3D` 只在关卡点名 `visual_id` 时才走。
##
## 所以「敌方子弹改成公告板」的主战场在这里 —— 只改 `VfxBulletBody3D` 是改错了地方。
var _billboard := false
var _icon: BulletBillboardIcon3D


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	_root = Node3D.new()
	_root.name = "BulletRoot"
	add_child(_root)

	# 白金亮芯：细长胶囊，长轴朝 -Z（前向）。
	var core_mesh := _shared_core_mesh()
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
	var shell_mesh := _shared_shell_mesh()
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
	var trail_mesh := _shared_trail_mesh()
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
	# 尾迹默认可见性由总开关决定（`GameDesignConfig.BULLET_TRAIL_VISIBLE`）。
	# 只藏不删：节点与材质照建，开关改回 true 即恢复。
	_trail.visible = GameDesignConfig.BULLET_TRAIL_VISIBLE
	_root.add_child(_trail)

	# 每弹一盏灯：无阴影、能量 1.2、范围 1.8；回收必须归零。
	_light = OmniLight3D.new()
	_light.name = "ProjectileLight"
	_light.shadow_enabled = false
	_light.light_energy = _LIGHT_ENERGY
	_light.omni_range = _LIGHT_RANGE
	_light.light_color = Color(0.45, 0.88, 1.0)
	# 零视觉损失收敛①：默认 light_cull_mask 是全部 32 层（引擎默认 4294967295，已实测），
	# 子弹灯实际只需要照亮世界与玩家。收敛到世界+玩家后近场照明与观感完全一致，
	# 但每物体光照不再把非世界层（全息城等）拉进计算。口径与房间灯/太阳一致。
	_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	# 零视觉损失收敛②：引擎侧超距淡出。子弹飞出可视距离后由引擎把灯光能量淡到 0，
	# 无逐帧脚本开销，也不改变近场观感。
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = _LIGHT_FADE_BEGIN
	_light.distance_fade_length = _LIGHT_FADE_LENGTH
	add_child(_light)

	# billboard 图标：恒建、默认隐藏，按 `_billboard` 切可见性。
	# 恒建而不是按需 add_child —— 池化复借时重建节点会让持有引用的一方全部失效。
	_icon = BulletBillboardIcon3D.new()
	_icon.name = "BillboardIcon"
	add_child(_icon)
	_icon.ensure_built()


## 切换 3D 弹体与 billboard 图标的可见性。两者互斥，绝不叠着画。
func _apply_billboard_mode() -> void:
	if _root != null:
		_root.visible = not _billboard and _active
	if _icon != null:
		_icon.visible = _billboard and _active
	if _billboard and _trail != null:
		# billboard 模式下 3D 尾迹没有意义：它挂在会被 `look_at` 旋转的宿主上，
		# 而图标始终正对相机，两者方向永远不一致 —— 会看到「图标 + 一根斜插的锥」。
		_trail.visible = false


## 图标世界尺寸：核心直径 **严格等于判定球直径**（上一轮「所见即所中」的延伸）。
func _apply_icon_scale() -> void:
	if _icon == null:
		return
	_icon.set_hit_diameter(BulletBillboardIcon3D.HIT_RADIUS_M * 2.0 * _base_scale)


func configure(color: Color, size: float = 1.0, context: Dictionary = {}) -> void:
	super.configure(color, size, context)
	_base_scale = size
	_billboard = bool(context.get("billboard", false))
	_apply_geometry_scale()
	_apply_billboard_mode()
	# 复借复色：外壳/拖尾用子弹色；亮芯保持白金；灯色跟随子弹色。图标同理逐发染色。
	if _icon != null:
		_icon.set_tint(color)
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
	# 弹体 / 图标的可见性由 billboard 模式统一决定，不在这里硬写 `_root.visible = true`
	# —— 否则敌方子弹会同时露出 3D 棱柱和图标。
	_apply_billboard_mode()
	# 复借按总开关复位：关着的时候不得被重新点亮。
	set_trail_visible(GameDesignConfig.BULLET_TRAIL_VISIBLE)


func deactivate() -> void:
	_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	# 隐藏灯与根；灯能量归零（回收必须归零）。不 emit retired、不 queue_free，随宿主离树释放。
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false
	_billboard = false
	_apply_billboard_mode()


func _process(delta: float) -> void:
	if not _active:
		return
	# 仅做轻微脉动，不自动 retire（生命周期由宿主 Projectile3D 管理）。
	_pulse_phase += delta
	var pulse := 1.0 + sin(_pulse_phase * 8.5) * 0.05
	if _root != null:
		_root.scale = Vector3.ONE * _base_scale * pulse
	# billboard 图标：脉动**不进尺寸**，否则「核心直径 = 判定球直径」会被 ±5% 破掉。
	# 每帧只校朝向；尺寸由 `_apply_icon_scale()` 在 configure / growth 时算一次。
	if _billboard and _icon != null:
		_icon.pose()


## 纯视觉：切换拖尾可见性（炮台形态隐藏拖尾）。
func set_trail_visible(visible_state: bool) -> void:
	if _trail == null:
		return
	# billboard 模式下尾迹恒隐藏：图标始终正对相机，而尾迹挂在被 `look_at` 旋转的宿主上，
	# 两者方向永远对不上。总开关和调用方都不能把它放出来。
	_trail.visible = visible_state and not _billboard


## 纯视觉：按倍率增长几何（命运 growth 等玩法调用）。不改变碰撞/伤害。
func apply_growth(factor: float) -> void:
	if factor <= 0.0:
		return
	_base_scale *= factor
	_apply_geometry_scale()


func _apply_geometry_scale() -> void:
	_apply_icon_scale()
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
		"trail_visible": _trail.visible if _trail != null else false,
		"forward": (-global_basis.z) if is_inside_tree() else Vector3(0.0, 0.0, -1.0),
		"base_scale": _base_scale,
		"body_scale": _root.scale.x if _root != null else 0.0,
		# billboard 图标（敌方子弹）：供验收读「图标在不在、朝向对不对、核心多大」。
		# 玩家子弹走同一条路由但 `billboard=false`，这几项恒为 false / 0。
		"billboard": _billboard,
		"body_visible": _root.visible if _root != null else false,
		"icon_visible": _icon.visible if _icon != null else false,
		"icon_world_side": _icon.get_snapshot()["icon_world_side"] if _icon != null else 0.0,
		"icon_core_diameter": (
			_icon.get_snapshot()["icon_core_diameter"] if _icon != null else 0.0
		),
		"icon_camera_alignment": (
			_icon.get_snapshot()["icon_camera_alignment"] if _icon != null else -1.0
		),
		# 图标核心相对判定球的倍率（2026-11-10 起 0.70）。验收用它区分
		# 「图标按倍率收缩」与「判定球被误改」。
		"icon_size_scale": _icon.get_snapshot()["icon_size_scale"] if _icon != null else -1.0,
		"node_count": get_child_count(),
	}
