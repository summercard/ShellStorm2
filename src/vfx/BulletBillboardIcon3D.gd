class_name BulletBillboardIcon3D
extends Node3D
## 子弹的「始终面对相机的图标」表现（2026-11-09 主人：「敌方子弹也一样」——
## 即敌方子弹也做成一直面对摄像机的公告板）。
##
## 为什么独立成一个节点，而不是塞进两个弹体类：敌方子弹有**两条**路由 ——
## ① 通用弹体 `VfxBulletVisual3D`（`visual_id` 为空，绝大多数敌人走这条）；
## ② 八弹种 `VfxBulletBody3D`（关卡在 `monster_rules` 里点名 `visual_id` 时）。
## 两处都要 billboard，各写一遍必然漂移（朝向算法 / 尺寸契约 / 快照字段）。
##
## 契约：
##   - **朝向**：局部基 = 相机基（折掉宿主基）。面片法线 (+Z) 因此正对镜头。
##     刻意不用 `BaseMaterial3D.billboard_mode` —— 那个只绕 **Y 轴**转，
##     本作相机俯视约 52°，面片会被压成 sin(52°) ≈ 0.79 的椭圆。
##   - **尺寸**：`hit_diameter` = 判定球直径，白热核心的 UV 直径占 0.6 ⇒
##     核心直径正好等于判定球直径，延续「所见即所中」。
##   - **池化安全**：节点恒建、靠 `visible` 切换，绝不重建 —— 重建会让调用方手里的引用失效。
##
## 为什么挂在 `self` 而不是弹体的 `_body_root`：`_body_root` 会被弹体的脉动 / 轴向拉伸缩放，
## 图标需要独立的「朝向层 + 尺寸层」两段，否则旋转与缩放互相覆盖。

const ICON_SHADER: Shader = preload(
	"res://assets/art/vfx/combat_3d/enemy_bullet_icon.gdshader"
)
## 图标里白热核心的 UV 半径 —— 必须与 shader 的 `core_radius` 一致。
## 用它把「判定球直径」反算成面片世界边长。
const CORE_UV_RADIUS := 0.30
## 判定球基准半径（与 `Projectile3D` 的 0.12 同口径）。
const HIT_RADIUS_M := 0.12

var _icon: MeshInstance3D
var _material: ShaderMaterial
var _hit_diameter := HIT_RADIUS_M * 2.0


## 惰性建节点：父类可能在自己的 `_ready` 里 add_child，此时本节点尚未入树，
## 用 `_ready` 建会有时序依赖；这里由调用方显式 `ensure_built()` 更稳。
func ensure_built() -> void:
	if _icon != null:
		return
	_material = ShaderMaterial.new()
	_material.shader = ICON_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_icon = MeshInstance3D.new()
	_icon.name = "Icon"
	_icon.mesh = quad
	_icon.material_override = _material
	_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_icon)
	visible = false


## 逐发染色（池化复借会换色）。
func set_tint(color: Color) -> void:
	ensure_built()
	_material.set_shader_parameter("bullet_color", color)


## 设定判定球直径（米）。核心亮区会正好铺满这个直径。
func set_hit_diameter(meters: float) -> void:
	ensure_built()
	_hit_diameter = maxf(0.01, meters)
	# 面片边长 = 核心直径 / 核心占 UV 的直径比例（2 × 0.30 = 0.6）。
	_icon.scale = Vector3.ONE * (_hit_diameter / (CORE_UV_RADIUS * 2.0))


## 每帧校朝向。折**父节点**基写局部基：宿主 `Projectile3D` 每帧 `look_at()` 飞行方向，
## 直接写 `global_transform` 会被它覆盖成「朝向飞行方向」，图标就又侧对镜头了。
## 同 `SpeechBubble3D._face_camera` 的口径（那里也踩过「父节点每帧覆盖」的坑）。
##
## ⚠ 反算必须用**父**基，不能用 `self.global_transform.basis`：
## 后者的值已经包含本节点上一帧的旋转，`self⁻¹ × wanted` 会算出 identity，
## 下一帧又被拉回相机基 ⇒ 两帧一次来回振荡（实测朝向余弦停在 cos45° 附近）。
func pose() -> void:
	if _icon == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return
	var wanted := camera.global_transform.basis.orthonormalized()
	var parent := get_parent() as Node3D
	var parent_basis := Basis.IDENTITY
	if parent != null:
		parent_basis = parent.global_transform.basis.orthonormalized()
	var local := parent_basis.inverse() * wanted
	if transform.basis.is_equal_approx(local):
		return
	transform.basis = local


## 面片法线 (+Z) 与**相机光轴**的夹角余弦（1 = 面片平行于近平面，即标准 billboard）。
## 用光轴而不是「图标→相机」向量：后者在视场边缘会天然偏离几度（透视），
## 会把「朝向完全正确」误判成 0.98，门槛就失去意义。
## 没有图标 / 没有相机时返回 -1，让调用方能区分「没测到」与「测到 0」。
func camera_alignment() -> float:
	if _icon == null or not is_inside_tree():
		return -1.0
	var viewport := get_viewport()
	if viewport == null:
		return -1.0
	var camera := viewport.get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return -1.0
	var normal := global_transform.basis.z.normalized()
	var camera_axis := camera.global_transform.basis.z.normalized()
	return normal.dot(camera_axis)


## 呈现快照（供验收读）。
func get_snapshot() -> Dictionary:
	return {
		"icon_visible": visible,
		"icon_world_side": _icon.scale.x if _icon != null else 0.0,
		"icon_core_diameter": (
			_icon.scale.x * CORE_UV_RADIUS * 2.0 if _icon != null else 0.0
		),
		"icon_hit_diameter": _hit_diameter,
		"icon_camera_alignment": camera_alignment(),
	}
