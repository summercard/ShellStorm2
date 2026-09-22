class_name VfxShellCasing3D
extends VfxEffectBase3D
## 开火抛出的弹壳：纯程序化模拟「弹出 → 抛物下落 → 触地碰撞 → 小弹跳 → 贴地滚动 → 躺平静止」。
##
## ⚠️ 刻意**不接物理引擎**：Prefab 无碰撞体，也**不做任何物理射线/空间查询**。
##    落地判定 = 弹壳中心是否越过「地面高度 + 弹壳半径」，地面高度来自 context.floor_y。
##    ⛔ **context.floor_y 必须由调用方按真实世界给**，不能用 0 想当然：
##       塔楼楼层是**向下**建的（`stage.position.y = -FLOOR_HEIGHT_M(12.0) × floor_index`），
##       98F ≈ **-1176 m**。若给出 0，弹壳出生点就已"低于地面" ⇒ 第一帧判定触地 ⇒
##       被夹到 y=0.058（世界原点附近）⇒ **掉出玩家视野，看起来像"弹壳特效没了"**
##       （2026-09-22 实机缺陷）。调用方口径见 `WeaponModel3D._resolve_shell_floor_y()`。
##    收效：不受场景碰撞体布局、物理帧率与查询开销影响；在无地板的 headless 场景里同样成立。
##    ⛔ 任何人把物理碰撞加回来（intersect_ray / direct_space_state / RigidBody3D …），
##       tests/verification/verify_combat_vfx_toon_v002.gd 的静态门禁会立刻变红。
##
## 随机化契约（业主 2026-09-22：「不然太整齐了」）：
##    本脚本**是确定性的** —— 给定同一 context 逐位可复现，绝不在 `_on_activate` / `_on_tick` 里抽随机数。
##    逐发随机的职责在**调用方** `WeaponModel3D._spawn_shell_casing`：
##    它按枪械局部基扰动抛出速度（方向 / 高度 / 前送）、自旋轴与自旋速度，并经
##    `context.initial_basis` 传入随机初始倾斜（本脚本只负责忠实采用 + 正交化）。
##    这样验收与视觉探针的逐帧断言仍然完全确定，而实机连发的弹壳各自散开。

## 弹壳视觉寿命：弹出 + 弹跳 + 滚动 + 静止的总预算。
## 业主 2026-09-22 两轮定档：
##   「弹壳的停留时长加 1.5 秒」   ⇒ 3.2 + 1.5 = 4.7
##   「弹壳的停留时长再缩短 1 秒」 ⇒ 4.7 − 1.0 = **3.7**
## 口径：飞行 / 弹跳 / 滚动三段的时长由物理常量与初速度决定，**不随寿命变化**
## ⇒ 寿命增减的部分**全部落在「落地静止后的停留」上**，所以业主说的「加/缩短 N 秒」
##    直接落成本常量 ±N，不需要另建「停留参数」（见验收 `_check_shell_settled_hold()`：
##    它实测静止时刻 `t_settle`，断言 `lifetime − t_settle ≥ 观感下限 1.5s`）。
## ⚠️ 本值同时就是「弹壳在地上的可见时长」—— 业主观感口径就是它，别在别处再塞一份。
## 成本提示：`VfxPool3D` 对 active 实例**无上限**（`max_per_kind` 只管 inactive 回收桶），
## 故寿命直接决定同屏存活弹壳数：射速 1.0 ~ 12.0 发/s × 3.7s ⇒ 最坏同屏 ≈ 44 枚
## （每枚 3 个 MeshInstance3D、288 三角面 ⇒ 约 13k 三角面 / 约 130 次绘制），仍在预算内。
## 若后续再改寿命，请先按此式复核同屏成本
## （对照：4.7s 时 ≈ 56 枚 / 约 16k 面 / 约 170 次绘制；3.2s 时 ≈ 38 枚）。
const DEFAULT_LIFETIME := 3.7

## 弹壳的**径向半展**（size = 1.0 时），决定躺平后的贴地高度 = 中心离地 = 此值 × size。
##
## ⚠️ 必须取三件里**最大**的那个径向半展，不能只看壳体：
##   壳体 CylinderMesh max(0.042, 0.046) = 0.046
##   底缘 TorusMesh outer_radius        = 0.058  ← 最大
##   底火 SphereMesh radius             = 0.025
##   曾经按壳体取 0.045 ⇒ 底缘比它多出 0.013，弹壳躺下时**整圈陷进地板 1.3cm**（探针量出来的）。
## 运行时优先用 `_measure_radial_half_extent()` 从已挂载 mesh 实测，本常量只作兜底与契约值
## （验收会把它当外部真源硬编码核对）。
const SHELL_BASE_RADIUS := 0.058

## 调用方**未给** floor_y 时的兜底地面高度。
## ⛔ 0 只对「世界原点那一层」成立，绝不能当作通用值：塔楼 98F 在 y ≈ -1176。
##    调用方必须显式传真实地面（见文件头与 `WeaponModel3D._resolve_shell_floor_y()`）。
const DEFAULT_FLOOR_Y := 0.0

const GRAVITY := 9.8
const MAX_BOUNCES := 2

## —— 模拟碰撞的手感口径（全在这里，调手感只动这几个数）——
##   法向速度 v_n → 反弹 -v_n × BOUNCE_RESTITUTION
##   切向速度 v_t → 保留 v_t × GROUND_FRICTION
##   自旋速度 ω  → 保留 ω × SPIN_LOSS
const BOUNCE_RESTITUTION := 0.32
const GROUND_FRICTION := 0.42
const SPIN_LOSS := 0.68
## 触地时给的最小翻滚角速度（rad/s）：保证「磕一下才弹起」看得见。
const IMPACT_TUMBLE_SPEED := 8.0

## 静止阈值：法向速度低于 REST_SPEED 不再弹跳；滚动速度低于 ROLL_STOP_SPEED 转入静止。
const REST_SPEED := 0.12
const ROLL_STOP_SPEED := 0.28
## 滚动阶段速度的指数衰减率（1/s）：v(t) = v0 × exp(-ROLL_DAMPING × t)
const ROLL_DAMPING := 3.4
## 触地挤压（squash & stretch）包络：触地瞬间沿弹壳长轴压到 1 - SQUASH_DEPTH，SQUASH_DURATION 内回弹。
const SQUASH_DEPTH := 0.28
const SQUASH_DURATION := 0.14
## 静止姿态过渡时长：从翻滚姿态平滑转为「长轴水平躺平」，避免姿态瞬跳。
const SETTLE_TWEEN := 0.18

## 弹壳 PBR 参数（业主 2026-09-22 定档）：金属度 0.8 / 反光度（roughness 通道）0.6。
## 口径：三件（壳体 Body / 底缘 Rim / 底火 Primer）统一使用该组数值，各件只区分基色。
const SHELL_METALLIC := 0.8
const SHELL_ROUGHNESS := 0.6

## 运动阶段：飞行（含抛物与弹跳）→ 贴地滚动 → 静止。
enum Phase { FLYING, ROLLING, SETTLED }

var _body: MeshInstance3D
var _rim: MeshInstance3D
var _primer: MeshInstance3D
var _velocity := Vector3.ZERO
var _spin_axis := Vector3.UP
var _spin_speed := 0.0
var _floor_y := DEFAULT_FLOOR_Y
var _radius := SHELL_BASE_RADIUS
var _phase := Phase.FLYING
var _bounces := 0
var _impact_count := 0
var _squash := 0.0
var _scale_base := 1.0
var _scale_vec := Vector3.ONE
var _settle_elapsed := 0.0
var _settle_from_basis := Basis.IDENTITY
var _settle_to_basis := Basis.IDENTITY
var _last_tick_elapsed := 0.0

func _ready() -> void:
	lifetime = DEFAULT_LIFETIME
	_build_visuals()
	visible = false

func _build_visuals() -> void:
	if _body != null:
		return
	_body = get_node_or_null("Body") as MeshInstance3D
	_rim = get_node_or_null("Rim") as MeshInstance3D
	_primer = get_node_or_null("Primer") as MeshInstance3D

func _on_configure(context: Dictionary) -> void:
	# 唯一的地面真源：调用方给的地板高度。不做射线查询 —— 见文件头契约。
	_floor_y = float(context.get("floor_y", DEFAULT_FLOOR_Y))

func _on_activate(_world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	_build_visuals()
	# 池复借必须复位全部状态：速度 / 朝向 / 阶段 / 计数 / 挤压 / 静止插值。
	# 出生姿态：调用方可给随机倾斜（context.initial_basis），缺省恒等。
	# ⚠️ 随机化**不在本脚本**：本脚本对同一 context 必须逐位可复现 —— 验收与视觉探针都靠逐帧断言，
	#    一旦把 randf() 埋进来，那些断言全部会漂。逐发随机的职责在调用方
	#    `WeaponModel3D._spawn_shell_casing`（业主 2026-09-22：「不然太整齐了」）。
	var initial_basis: Basis = Basis.IDENTITY
	var provided_basis: Variant = context.get("initial_basis")
	if provided_basis is Basis:
		initial_basis = provided_basis
	# orthonormalized() 是硬要求：根 basis 非正交时，后面的旋转赋值（Basis(axis, angle) * basis）
	# 会被引擎刷一屏 `must be normalized in order to be casted to a Quaternion`。
	global_transform.basis = initial_basis.orthonormalized()
	_scale_base = maxf(size, 0.01)
	# 贴地高度取实测径向半展（几何改了自动跟随），实测失败才退回契约常量。
	var measured := _measure_radial_half_extent()
	_radius = (measured if measured > 0.0 else SHELL_BASE_RADIUS) * _scale_base
	_velocity = context.get("velocity", Vector3(1.8, 1.6, 0.25)) as Vector3
	if _velocity.length_squared() < 0.001:
		_velocity = Vector3(1.8, 1.6, 0.25)
	_spin_axis = (context.get("spin_axis", Vector3(0.7, 1.0, 0.2)) as Vector3).normalized()
	if _spin_axis.length_squared() < 0.001:
		_spin_axis = Vector3.UP
	_spin_speed = float(context.get("spin_speed", 18.0))
	_phase = Phase.FLYING
	_bounces = 0
	_impact_count = 0
	_squash = 0.0
	_settle_elapsed = 0.0
	_settle_from_basis = Basis.IDENTITY
	_settle_to_basis = Basis.IDENTITY
	_last_tick_elapsed = 0.0
	visible = true
	if _body != null:
		_body.visible = true
		_body.material_override = _make_material(color.darkened(0.12))
	if _rim != null:
		_rim.visible = true
		_rim.material_override = _make_material(color.lightened(0.12))
	if _primer != null:
		_primer.visible = true
		_primer.material_override = _make_material(Color(0.12, 0.10, 0.07))
	_apply_visual_scale()

func _on_tick(delta_elapsed: float, _total: float) -> void:
	# _on_tick 接收累计时间；转成相邻 tick 的增量，避免把累计时间当 dt 重复积分。
	var dt: float = clampf(delta_elapsed - _last_tick_elapsed, 0.0, 1.0 / 15.0)
	_last_tick_elapsed = delta_elapsed
	if dt <= 0.0:
		return
	_advance_squash(dt)
	if _phase == Phase.SETTLED:
		_advance_settle(dt)
		return
	if _phase == Phase.ROLLING:
		_tick_rolling(dt)
		return
	_tick_flight(dt)

## 飞行段：自积分抛物 + 程序化落地判定（越线即碰撞，不查物理世界）。
func _tick_flight(dt: float) -> void:
	_velocity.y -= GRAVITY * dt
	var next_position := global_position + _velocity * dt
	global_transform.basis = Basis(_spin_axis, _spin_speed * dt) * global_transform.basis
	if next_position.y - (_floor_y + _radius) > 0.0:
		global_position = next_position
		return
	_impact()

## 模拟碰撞：把越线位置夹回贴地，按恢复系数/摩擦拆解法向与切向速度，计入弹跳次数。
func _impact() -> void:
	_impact_count += 1
	_squash = 1.0
	global_position.y = _floor_y + _radius
	var normal_speed := _velocity.y
	var tangent := Vector3(_velocity.x, 0.0, _velocity.z)
	_spin_speed *= SPIN_LOSS
	if _bounces < MAX_BOUNCES and absf(normal_speed) > REST_SPEED:
		_bounces += 1
		_velocity = tangent * GROUND_FRICTION + Vector3.UP * (-normal_speed * BOUNCE_RESTITUTION)
		# 翻滚轴取「切向 × 地面法线」⇒ 弹壳沿抛出的方向翻过去，视觉上像磕了一下才起跳。
		var tumble_axis := tangent.cross(Vector3.UP)
		if tumble_axis.length_squared() > 0.0001:
			_spin_axis = tumble_axis.normalized()
		_spin_speed = maxf(_spin_speed, IMPACT_TUMBLE_SPEED)
		return
	# 弹跳次数用尽、或法向速度已低于阈值 ⇒ 改为贴地滚动。
	_enter_rolling(tangent)

func _enter_rolling(tangent: Vector3) -> void:
	_phase = Phase.ROLLING
	_velocity = tangent
	_spin_speed = maxf(_spin_speed, IMPACT_TUMBLE_SPEED * 0.4)
	if tangent.length() <= ROLL_STOP_SPEED:
		_begin_settle()

## 滚动段：贴地滑行 + 指数减速；转速同步衰减，停稳后转静止姿态。
func _tick_rolling(dt: float) -> void:
	var decay: float = exp(-ROLL_DAMPING * dt)
	var tangent := Vector3(_velocity.x, 0.0, _velocity.z) * decay
	_spin_speed *= decay
	_velocity = tangent
	global_position += tangent * dt
	global_position.y = _floor_y + _radius
	global_transform.basis = Basis(_spin_axis, _spin_speed * dt) * global_transform.basis
	if tangent.length() <= ROLL_STOP_SPEED:
		_begin_settle()

func _begin_settle() -> void:
	_phase = Phase.SETTLED
	_velocity = Vector3.ZERO
	_spin_speed = 0.0
	global_position.y = _floor_y + _radius
	_settle_elapsed = 0.0
	_settle_from_basis = global_transform.basis
	_settle_to_basis = _flat_resting_basis()

## 静止姿态：弹壳长轴（local Y）放平到地面上，朝向取当前长轴的水平投影。
func _flat_resting_basis() -> Basis:
	var projected := Vector3(global_transform.basis.y.x, 0.0, global_transform.basis.y.z)
	if projected.length_squared() < 0.0001:
		projected = Vector3.FORWARD
	var y_axis := projected.normalized()
	var z_axis := y_axis.cross(Vector3.UP).normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

## 静止姿态过渡：smoothstep 插值，避免从翻滚姿态瞬跳到躺平。
func _advance_settle(dt: float) -> void:
	if _settle_elapsed >= SETTLE_TWEEN:
		return
	_settle_elapsed = minf(_settle_elapsed + dt, SETTLE_TWEEN)
	var t: float = _settle_elapsed / SETTLE_TWEEN
	var k: float = t * t * (3.0 - 2.0 * t)
	global_transform.basis = _settle_from_basis.slerp(_settle_to_basis, k).orthonormalized()

## 触地挤压包络：沿弹壳长轴压扁再回弹（纯视觉，不改变运动）。
func _advance_squash(dt: float) -> void:
	if _squash <= 0.0:
		return
	_squash = maxf(0.0, _squash - dt / SQUASH_DURATION)
	_apply_visual_scale()

## 三件在 Prefab 里的 local 偏移（装配关系）：
## 底缘贴在壳体上端（+0.12）、底火贴在下端（-0.12），壳体自身居中。
const RIM_LOCAL_OFFSET := 0.12
const PRIMER_LOCAL_OFFSET := -0.12

## 视觉缩放：三件等比缩放，**并且子节点的偏移按同比例一起缩放**。
##
## 两条都是硬要求，踩过两次：
## ① 不能只缩放子节点而漏掉它们的偏移 —— 装配会散开：实测 size=0.8 时壳体半高缩到 0.096，
##    底缘却仍在 0.12，底缘环与壳体之间裂开一道缝（像素核对：0.8 那枚在画面里断成两块）。
## ② 也不能把缩放挂到**根节点**上 —— 根 basis 会被乘进缩放而变成非正交，
##    旋转赋值（`global_transform.basis = Basis(axis, angle) * basis`）需要正交基，
##    引擎会刷一屏 `must be normalized in order to be casted to a Quaternion` ERROR。
##    根节点保持纯旋转，缩放落在三件上 ⇒ 两条都干净。
func _apply_visual_scale() -> void:
	var compress: float = 1.0 - SQUASH_DEPTH * _squash
	var widen: float = 1.0 + SQUASH_DEPTH * 0.5 * _squash
	_scale_vec = Vector3(_scale_base * widen, _scale_base * compress, _scale_base * widen)
	if _body != null:
		_body.scale = _scale_vec
		_body.position = Vector3.ZERO
	if _rim != null:
		_rim.scale = _scale_vec
		_rim.position = Vector3(0.0, RIM_LOCAL_OFFSET * _scale_vec.y, 0.0)
	if _primer != null:
		_primer.scale = _scale_vec
		_primer.position = Vector3(0.0, PRIMER_LOCAL_OFFSET * _scale_vec.y, 0.0)

## 从已挂载的三件 mesh 实测**最大径向半展**（局部 X/Z 方向的半展）。
## 躺平后弹壳的竖直方向就是径向 ⇒ 贴地高度必须用它，否则会浮空或陷入。
## 实测失败（mesh 缺失）返回 0.0，由调用方退回 SHELL_BASE_RADIUS。
func _measure_radial_half_extent() -> float:
	var measured := 0.0
	for node in [_body, _rim, _primer]:
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var box := instance.mesh.get_aabb()
		measured = maxf(measured, maxf(
			maxf(absf(box.position.x), absf(box.end.x)),
			maxf(absf(box.position.z), absf(box.end.z))
		))
	return measured

func _on_lifetime_expired() -> void:
	_velocity = Vector3.ZERO
	_spin_speed = 0.0
	_phase = Phase.FLYING
	_bounces = 0
	_impact_count = 0
	_squash = 0.0
	_settle_elapsed = 0.0
	visible = false
	if _body != null:
		_body.visible = false
	if _rim != null:
		_rim.visible = false
	if _primer != null:
		_primer.visible = false

func get_presentation_snapshot() -> Dictionary:
	return {
		"asset_id": String(get_meta("asset_id", "")),
		"asset_version": String(get_meta("asset_version", "")),
		"lifetime": lifetime,
		"gravity": GRAVITY,
		"max_bounces": MAX_BOUNCES,
		"settled": _phase == Phase.SETTLED,
		"phase": int(_phase),
		"bounce_count": _bounces,
		"impact_count": _impact_count,
		"squash": _squash,
		"radius": _radius,
		"floor_y": _floor_y,
		"base_radius": SHELL_BASE_RADIUS,
		"measured_radial_half_extent": _measure_radial_half_extent(),
		"visual_scale": _scale_base,
		# 已挂载**三件子节点**的实际缩放（真值，非回读入参）：验收据此断言「缩到 80%」真的落到几何上。
		# 缩放落在子节点上（以壳体 Body 为代表），根节点只保留旋转 —— 见 _apply_visual_scale 注释。
		"shell_scale": _mounted_visual_scale(),
		# 根节点缩放真值：必须恒为单位缩放。根 basis 一旦带缩放就非正交，旋转赋值会报
		# `must be normalized in order to be casted to a Quaternion`。验收据此盯住这条回归。
		"root_scale": scale,
		"velocity": _velocity,
		# 自旋真值：验收据此断言「调用方真的逐发随机了自旋」（本脚本只忠实采用 context 给的值）。
		"spin_axis": _spin_axis,
		"spin_speed": _spin_speed,
		# 出生姿态（真值）：由 _on_activate 按 context.initial_basis 写入，缺省恒等。
		# 调用方随机化后，验收据 `spawn_basis.get_rotation_quaternion().get_angle()` 断言初始倾角真带随机。
		"spawn_basis": global_transform.basis,
		# 声明本特效为「程序化模拟碰撞」：验收据此断言它没有退回物理引擎。
		"simulated_collision": true,
		"body_mesh": _body != null and _body.mesh != null,
		"rim_mesh": _rim != null and _rim.mesh != null,
		# PBR 真值直接读已挂载材质（不是读常量），保证"改坏常量"能被断言抓到。
		"metallic": _material_float(_body, "metallic"),
		"roughness": _material_float(_body, "roughness"),
		"rim_metallic": _material_float(_rim, "metallic"),
		"rim_roughness": _material_float(_rim, "roughness"),
		"primer_metallic": _material_float(_primer, "metallic"),
		"primer_roughness": _material_float(_primer, "roughness"),
	}

## 已挂载三件的实际视觉缩放（以壳体为代表，三件同值）。无 mesh 时返回 ZERO 作哨兵（验收会失败）。
func _mounted_visual_scale() -> Vector3:
	if _body != null:
		return _body.scale
	if _rim != null:
		return _rim.scale
	if _primer != null:
		return _primer.scale
	return Vector3.ZERO

## 读某件已挂载材质的浮点属性；无材质/无属性时返回 -1.0 作哨兵（验收会因哨兵失败）。
func _material_float(node: MeshInstance3D, property_name: String) -> float:
	if node == null:
		return -1.0
	var material := node.material_override as StandardMaterial3D
	if material == null:
		return -1.0
	return float(material.get(property_name))

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = SHELL_METALLIC
	material.roughness = SHELL_ROUGHNESS
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.disable_receive_shadows = false
	return material
