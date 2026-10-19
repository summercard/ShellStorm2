class_name VfxBoardDebris3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-33 / VFX-BOARD-DEBRIS-3D —— 暗门木板被打碎时，**大块木板碎片**从门里飞出来。
##
## 业主口径（2026-10-19）：「做一个门被打碎的木头飞出来的特效，大块一点的，做完带入然后更新账本」。
## ⇒ 关键不是「有碎片」，而是「**大块**」：单片最长边最大 0.52m，对着 2.38 × 2.51m 的门板
##   读作「这块板被砸断了」，而不是「一撮锯末」。验收有专门的尺寸钉子（`MIN_PIECE_EXTENT_M`）。
##
## 与 FX01-10 弹壳（`VfxShellCasing3D`）同族 —— **抛出物**：
##   · 一次性取得初速度后完全由自己积分位置，**不绑 `context.follow`**
##     （绑了就永远跟着门，不落地）；
##   · 只做程序化碰撞（越线即触地），Prefab 内**无任何碰撞体**；
##   · 复借必须复位全部状态（速度 / 姿态 / 落地标记 / 灯能量）。
## 但件数与体积不同：8 块大碎片 + 5 片小碎屑，还自带一盏 0.55s 的短灯 ——
## 塔内夜间光下，不带灯的话碎块一出框就是一片黑，等于没做。
##
## ── 朝向契约 `context.forward` ────────────────────────────────────────────
##   局部 **-Z 对齐 `forward`**（`Basis.looking_at(forward)`），碎片朝局部 -Z 飞。
##   调用方（`SecretDoor3D._break_open()`）传 `-global_basis.z` = 门的房间侧法线 ⇒
##   碎片朝玩家站的那一侧（房间）崩出来，不会往墙里飞。
##
## ── 地面契约 `context.floor_y`（同弹壳，P0 级）────────────────────────────
##   **必须由调用方按真实世界给**，不能以 0 兜底：塔楼楼层是**向下**建的
##   （98F ≈ y = −1176m），给 0 会让碎片第一帧就判定触地、被夹到世界原点附近，
##   看起来像「特效没了」。调用方口径：`SecretDoor3D` 用门自己的世界 y（门原点即地面）。
##
## ── 随机化契约（同 §5.5.3）──────────────────────────────────────────────
##   本脚本**不含 `randf()`**：同一 `context.seed` 逐位可复现 —— 验收会拿同一个
##   seed 实例化两次逐字段比对。每次破板「散得不一样」由**调用方**给不同 seed 达成
##   （`SecretDoor3D._board_debris_seed()`）。散开量由 seed 派生，不是每帧抽随机。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

## 碎片视觉寿命：飞行 / 弹跳 / 贴地滑行 / 停放的总预算。
## 实测（1/60s 步进）：最后一枚落地静止约 1.15s ⇒ 停放约 1.7s，足够看清。
## 成本：单次破板只有一次（不是每发子弹），最坏同屏 = 1 个实例 × 13 件 × 12 面 ≈ 156 面。
const LIFETIME_S := 2.85

const GRAVITY := 9.8
## 大碎片数量（业主「大块一点」 ⇒ 少而大，不是多而碎）。
const CHUNK_COUNT := 8
## 小碎屑数量（点缀：只有大块会读成「几块板」，加点细屑才有"打碎"的粉尘感）。
const SPLINTER_COUNT := 5

## ── 大碎片尺寸（米，size = 1.0）──────────────────────────────────────────
## 木板本体厚 0.139m、门板 2.38 × 2.51m ⇒ 单片 0.36~0.58m 长 = 门宽的 1/6~1/4。
## 第一版按 0.16~0.24m 做（"碎屑"尺度），业主口径是「大块」，故整体翻倍；
## 拿实拍图核对后又上调一档（0.34~0.52 → 0.36~0.58）—— 7m 外看图，0.49m 那档偏碎。
const CHUNK_LENGTH_MIN := 0.36
const CHUNK_LENGTH_MAX := 0.58
const CHUNK_WIDTH_MIN := 0.16
const CHUNK_WIDTH_MAX := 0.26
const CHUNK_THICK_MIN := 0.07
const CHUNK_THICK_MAX := 0.10

## ── 小碎屑尺寸 ───────────────────────────────────────────────────────────
const SPLINTER_MIN := 0.045
const SPLINTER_MAX := 0.085

## 验收用的「大块」下限：最大碎片的世界最长边必须 ≥ 此值。
## 放在脚本侧只作**契约声明**，验收侧另有一份硬编码期望（防自印证，见 14.6 §6.9）。
const MIN_PIECE_EXTENT_M := 0.30

## ── 初速度（米/秒，局部系：-Z = 朝房间侧）──────────────────────────────
## 前向 1.7~3.4 ⇒ 0.4s 时已飞出 0.7~1.4m，明显"崩出来"而不是"掉下来"。
const SPEED_FORWARD_MIN := 1.7
const SPEED_FORWARD_MAX := 3.4
const SPEED_UP_MIN := 1.3
const SPEED_UP_MAX := 2.9
## 侧向绝对值抖动（±），避免整排平行飞出。
const SPEED_SIDE := 1.5
## 小碎屑的速度倍率（更轻 ⇒ 更快更飘）。
const SPLINTER_SPEED_MUL := 1.35

## ── 程序化碰撞（不接物理引擎，口径同弹壳）────────────────────────────────
const BOUNCE_RESTITUTION := 0.26
const GROUND_FRICTION := 0.52
const SPIN_LOSS := 0.62
const MAX_BOUNCES := 1
const REST_SPEED := 0.45
## 贴地滑行速度的指数衰减率（1/s）。
const SLIDE_DAMPING := 5.2

## 自旋（rad/s）
const SPIN_MIN := 4.0
const SPIN_MAX := 11.0

## ── 材质（木头，业主没指定数值，取「哑光木头」的常规值，写清通道口径）──────
## 金属度 metallic = 0.0（木头非金属）
## 反光度 roughness = 0.86（哑光，**这是 roughness 通道，不是 metallic**）
const WOOD_METALLIC := 0.0
const WOOD_ROUGHNESS := 0.86
## 自发光强度。塔内是夜间光（room_03 子树里 Light3D 数量 = 0）：
## 纯受光的深木色碎块在实拍里是**一团黑剪影**（第一版真图核对时看到的就是这个），
## 加一点点自发光让「木头」这个读法在暗房里立得住，同时保留受光的高光与阴影。
const WOOD_EMISSION_ENERGY := 0.38
## 断面上浅一档：真实木板断口的木芯比表面新。逐片按 index 交替取这两个色阶，
## 一排碎片就有了"新断口 / 旧板面"的层次。
const WOOD_BREAK_LIGHTEN := 0.18

## ── 灯（塔内夜间光必需）────────────────────────────────────────────────
## 峰值 → 0.14s 开始收 → 0.55s 归零。碎片飞行的可见窗口就是这半秒。
## ⚠ 属性名是 `light_energy`（不是 `.energy`）；`omni_range` 随 size 缩放，能量不随。
const LIGHT_NAME := "DebrisLight"
const LIGHT_PEAK_ENERGY := 1.5
const LIGHT_RANGE_M := 3.6
const LIGHT_FADE_OUT_START := 0.14
const LIGHT_FADE_OUT_END := 0.55
const LIGHT_LOCAL_OFFSET := Vector3(0.0, 0.45, -0.65)
const LIGHT_COLOR := Color(1.0, 0.82, 0.58)

## 未给 floor_y 时的兜底（⛔ 只对世界原点那一层成立，调用方必须显式传）。
const DEFAULT_FLOOR_Y := 0.0
## 未给 seed 时的兜底（确定性，便于验收重放）。
const DEFAULT_SEED := 20261019

var _pieces: Array[MeshInstance3D] = []
var _velocities: Array[Vector3] = []
var _spin_axes: Array[Vector3] = []
var _spin_speeds: Array[float] = []
var _half_heights: Array[float] = []
var _landed: Array[bool] = []
var _bounces: Array[int] = []

var _materials: Array[StandardMaterial3D] = []
var _light: OmniLight3D = null

var _forward := Vector3.FORWARD
var _floor_y := DEFAULT_FLOOR_Y
var _floor_local_y := 0.0
var _debris_seed := DEFAULT_SEED
var _last_tick_elapsed := 0.0


func _on_activate(_world_pos: Vector3, color: Color, _size: float, context: Dictionary) -> void:
	lifetime = LIFETIME_S
	_forward = context.get("forward", Vector3.FORWARD) as Vector3
	if _forward.length_squared() < 0.0001:
		_forward = Vector3.FORWARD
	_forward = _forward.normalized()
	_floor_y = float(context.get("floor_y", DEFAULT_FLOOR_Y))
	_debris_seed = int(context.get("seed", DEFAULT_SEED))
	if _pieces.is_empty():
		_build()
	# 局部 -Z 对齐 forward ⇒ 碎片朝 -Z 飞就是朝房间侧飞。
	global_transform.basis = Basis.looking_at(_forward).orthonormalized()
	# 出生点抬到门洞中部：调用方给的是门底中心，碎片应从上半个门板崩出来。
	global_position = global_position + _forward * 0.18 + Vector3.UP * 1.25
	_floor_local_y = _floor_y - global_position.y
	_reset_state(color)
	_apply_light()
	_on_tick(0.0, lifetime)


## 建件。只建一次 —— 池复借只复位状态，不重建几何。
func _build() -> void:
	# 木质材质：两档色阶（断口浅 / 板面深），逐片取用。
	for level in 2:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.30, 0.19, 0.09)
		material.metallic = WOOD_METALLIC
		material.roughness = WOOD_ROUGHNESS
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.disable_receive_shadows = false
		material.emission_enabled = true
		material.emission = Color(0.30, 0.19, 0.09)
		material.emission_energy_multiplier = WOOD_EMISSION_ENERGY
		_materials.append(material)

	for index in CHUNK_COUNT:
		var piece := MeshInstance3D.new()
		piece.name = "Chunk%d" % index
		piece.mesh = ToonVfx.unit_cube_mesh()
		piece.material_override = _materials[index % _materials.size()]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		_pieces.append(piece)
	for index in SPLINTER_COUNT:
		var splinter := MeshInstance3D.new()
		splinter.name = "Splinter%d" % index
		splinter.mesh = ToonVfx.unit_cube_mesh()
		splinter.material_override = _materials[(index + 1) % _materials.size()]
		splinter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(splinter)
		_pieces.append(splinter)

	_light = get_node_or_null(LIGHT_NAME) as OmniLight3D


## 池复借的唯一保障：把「上一轮用剩的」全部清掉，尺寸/速度/姿态/落地全部重算。
func _reset_state(color: Color) -> void:
	var base := color if color.a > 0.001 else Color(0.30, 0.19, 0.09)
	base.a = 1.0
	var break_face := base.lightened(WOOD_BREAK_LIGHTEN)
	_materials[0].albedo_color = base
	_materials[0].emission = base
	_materials[1].albedo_color = break_face
	_materials[1].emission = break_face

	_velocities.clear()
	_spin_axes.clear()
	_spin_speeds.clear()
	_half_heights.clear()
	_landed.clear()
	_bounces.clear()
	_last_tick_elapsed = 0.0

	var total := _pieces.size()
	for index in total:
		var is_chunk := index < CHUNK_COUNT
		var local_index := index if is_chunk else index - CHUNK_COUNT
		var count := CHUNK_COUNT if is_chunk else SPLINTER_COUNT
		var piece := _pieces[index]

		# 尺寸：长轴沿 Z（"板条"），宽 X、厚 Y。碎屑近立方。
		var length_ratio := _hash01(local_index, 1)
		var width_ratio := _hash01(local_index, 2)
		var thick_ratio := _hash01(local_index, 3)
		var size_vec: Vector3
		if is_chunk:
			size_vec = Vector3(
				lerpf(CHUNK_WIDTH_MIN, CHUNK_WIDTH_MAX, width_ratio) * effect_size,
				lerpf(CHUNK_THICK_MIN, CHUNK_THICK_MAX, thick_ratio) * effect_size,
				lerpf(CHUNK_LENGTH_MIN, CHUNK_LENGTH_MAX, length_ratio) * effect_size
			)
		else:
			var edge: float = lerpf(SPLINTER_MIN, SPLINTER_MAX, length_ratio) * effect_size
			size_vec = Vector3(edge, edge * 0.7, edge * 1.6)
		_half_heights.append(size_vec.y * 0.5)

		# 出生分布：铺在门板内（宽 ±0.85、高 0.30~2.10），不挤在一点。
		var spread_x: float = lerpf(-0.85, 0.85, _hash01(local_index, 4))
		var spread_y: float = lerpf(0.30, 2.10, _hash01(local_index, 5)) - 1.25
		var spread_z: float = lerpf(-0.08, 0.10, _hash01(local_index, 6))
		piece.position = Vector3(spread_x * effect_size, spread_y * effect_size, spread_z)

		# 初速度：局部 -Z 为主 + 抬升 + 侧向抖动。碎屑整体更快。
		var speed_mul: float = 1.0 if is_chunk else SPLINTER_SPEED_MUL
		_velocities.append(Vector3(
			lerpf(-SPEED_SIDE, SPEED_SIDE, _hash01(local_index, 7)) * speed_mul,
			lerpf(SPEED_UP_MIN, SPEED_UP_MAX, _hash01(local_index, 8)) * speed_mul,
			-lerpf(SPEED_FORWARD_MIN, SPEED_FORWARD_MAX, _hash01(local_index, 9)) * speed_mul
		))

		# 自旋：随机单位轴 + 4~11 rad/s。轴从单位立方体取再归一化（球坐标会在两极堆积）。
		var axis := Vector3(
			lerpf(-1.0, 1.0, _hash01(local_index, 10)),
			lerpf(-1.0, 1.0, _hash01(local_index, 11)),
			lerpf(-1.0, 1.0, _hash01(local_index, 12))
		)
		_spin_axes.append(axis.normalized() if axis.length_squared() > 0.0001 else Vector3.UP)
		_spin_speeds.append(lerpf(SPIN_MIN, SPIN_MAX, _hash01(local_index, 13)))
		_landed.append(false)
		_bounces.append(0)
		# 出生姿态：绕自身轴预先歪一下，否则一开始全是"正正方方的板条"，很假。
		# ⚠ 尺寸必须**乘进 basis**（`Basis.scaled`），不能先写 `piece.scale` 再写 `piece.basis`：
		#    `basis` 的 setter 是整矩阵覆盖，会把先前设的 scale 抹成 1 ⇒ 每片都是 1m 大方块
		#    （第一版就这么错，验收读到「最大单片 1.000m」才抓出来 —— 那条断言当时只有下限，
		#    1m ≥ 0.30m 照样绿；已补上限，见验收 A4）。
		piece.basis = Basis(
			Vector3(0.31, 1.0, 0.17).normalized(),
			lerpf(0.0, TAU, _hash01(local_index, 14))
		).scaled(size_vec)

	if _light != null:
		_light.visible = true
		_light.light_color = LIGHT_COLOR
		_light.omni_range = LIGHT_RANGE_M * maxf(effect_size, 0.01)
		_light.light_energy = LIGHT_PEAK_ENERGY
		_light.shadow_enabled = false
		_light.position = LIGHT_LOCAL_OFFSET


func _on_tick(delta_elapsed: float, _total: float) -> void:
	# `_on_tick` 给的是累计时间，不是 dt：要位移就得自己转增量，并夹住卡帧尖峰
	# （一次 0.5s 卡顿不夹会让碎片瞬移穿过地板）。
	var dt: float = clampf(delta_elapsed - _last_tick_elapsed, 0.0, 1.0 / 15.0)
	_last_tick_elapsed = delta_elapsed
	_apply_light_energy(delta_elapsed)
	if dt <= 0.0:
		return
	for index in _pieces.size():
		if _landed[index]:
			_tick_slide(index, dt)
		else:
			_tick_fly(index, dt)


## 飞行段：自积分抛物 + 越线即触地（不查物理世界）。
func _tick_fly(index: int, dt: float) -> void:
	var piece := _pieces[index]
	var velocity := _velocities[index]
	velocity.y -= GRAVITY * dt
	var next := piece.position + velocity * dt
	piece.basis = Basis(_spin_axes[index], _spin_speeds[index] * dt) * piece.basis
	_velocities[index] = velocity
	var floor_line: float = _floor_local_y + _half_heights[index]
	if next.y > floor_line:
		piece.position = next
		return
	# 触地：夹回贴地线，法向按恢复系数反弹，切向按摩擦衰减。
	piece.position = Vector3(next.x, floor_line, next.z)
	_spin_speeds[index] *= SPIN_LOSS
	var normal_speed := velocity.y
	if _bounces[index] < MAX_BOUNCES and absf(normal_speed) > REST_SPEED:
		_bounces[index] += 1
		velocity.y = -normal_speed * BOUNCE_RESTITUTION
		velocity.x *= GROUND_FRICTION
		velocity.z *= GROUND_FRICTION
		_velocities[index] = velocity
		var tumble := Vector3(velocity.x, 0.0, velocity.z).cross(Vector3.UP)
		if tumble.length_squared() > 0.0001:
			_spin_axes[index] = tumble.normalized()
		_spin_speeds[index] = maxf(_spin_speeds[index], 3.0)
		return
	_landed[index] = true
	velocity.y = 0.0
	_velocities[index] = velocity


## 贴地滑行：指数减速 + 贴住地面；停下后姿态放平（长轴水平），避免"插进地里"。
func _tick_slide(index: int, dt: float) -> void:
	var piece := _pieces[index]
	var velocity := _velocities[index]
	var decay: float = exp(-SLIDE_DAMPING * dt)
	velocity.x *= decay
	velocity.z *= decay
	_spin_speeds[index] *= decay
	_velocities[index] = velocity
	var step := Vector3(velocity.x, 0.0, velocity.z) * dt
	piece.position += step
	piece.position.y = _floor_local_y + _half_heights[index]
	if _spin_speeds[index] > 0.05:
		piece.basis = Basis(_spin_axes[index], _spin_speeds[index] * dt) * piece.basis
	else:
		# 放平：长轴（局部 Z）投到水平面，其余轴由它派生。
		# ⚠ 同样要 `.scaled(piece.scale)` —— `Basis(a,b,c)` 是最新纯旋转，直接赋值会把尺寸抹回 1m。
		var flat := Vector3(piece.basis.z.x, 0.0, piece.basis.z.z)
		if flat.length_squared() > 0.0004:
			flat = flat.normalized()
			var side := flat.cross(Vector3.UP).normalized()
			var up := side.cross(flat).normalized()
			piece.basis = Basis(side, up, flat).scaled(piece.scale)


## 灯能量包络：峰值 → 0.14s 起收 → 0.55s 归零，之后**一直保持 0**（不浪费）。
## ⚠ 回收时必须显式归零：池复借会留长明灯（14.6 §4）。
func _apply_light_energy(elapsed: float) -> void:
	if _light == null:
		return
	if elapsed >= LIGHT_FADE_OUT_END:
		_light.light_energy = 0.0
		_light.visible = false
		return
	if elapsed <= LIGHT_FADE_OUT_START:
		_light.light_energy = LIGHT_PEAK_ENERGY
		return
	var t: float = clampf(
		(elapsed - LIGHT_FADE_OUT_START) / (LIGHT_FADE_OUT_END - LIGHT_FADE_OUT_START), 0.0, 1.0
	)
	_light.light_energy = LIGHT_PEAK_ENERGY * (1.0 - t)


func _apply_light() -> void:
	if _light == null:
		return
	_light.visible = true
	_light.light_energy = LIGHT_PEAK_ENERGY


func _on_lifetime_expired() -> void:
	_velocities.clear()
	_landed.clear()
	_bounces.clear()
	_last_tick_elapsed = 0.0
	visible = false
	for piece in _pieces:
		if is_instance_valid(piece):
			piece.visible = false
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false


## 确定性 0~1 散列：同 (seed, index, salt) 逐位同值，脚本内**不出现 randf()**。
func _hash01(index: int, salt: int) -> float:
	var h: int = (_debris_seed + index * 7919 + salt * 104729) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7FFFFFFF
	return float(h % 100003) / 100003.0


## 供验收 / 巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	var max_extent := 0.0
	var lowest := INF
	var landed := 0
	var centroid := Vector3.ZERO
	for piece in _pieces:
		if not is_instance_valid(piece):
			continue
		var extent := piece.scale
		max_extent = maxf(max_extent, maxf(extent.x, maxf(extent.y, extent.z)))
		lowest = minf(lowest, piece.global_position.y)
		centroid += piece.global_position
	for flag in _landed:
		if flag:
			landed += 1
	if not _pieces.is_empty():
		centroid /= float(_pieces.size())
	return {
		"asset_id": String(get_meta("asset_id", "")),
		"asset_version": String(get_meta("asset_version", "")),
		"lifetime": lifetime,
		"piece_count": _pieces.size(),
		"chunk_count": CHUNK_COUNT,
		"splinter_count": SPLINTER_COUNT,
		"max_piece_extent": max_extent,
		"min_piece_extent": MIN_PIECE_EXTENT_M,
		"centroid": centroid,
		"lowest_y": lowest if lowest < INF else 0.0,
		"landed_count": landed,
		"forward": _forward,
		"floor_y": _floor_y,
		"floor_local_y": _floor_local_y,
		"seed": _debris_seed,
		"metallic": _material_float(0, "metallic"),
		"roughness": _material_float(0, "roughness"),
		"has_light": _light != null,
		"light_name": _light.name if _light != null else "",
		"light_energy": _light.light_energy if _light != null else 0.0,
		"light_range": _light.omni_range if _light != null else 0.0,
		"light_shadows": _light.shadow_enabled if _light != null else false,
		"consumes_forward": true,
		"simulated_collision": true,
	}


## 读某档已挂载材质的浮点属性；无材质时返回 -1.0 作哨兵（0.0 会被当成合法值混过断言）。
func _material_float(index: int, property_name: String) -> float:
	if index < 0 or index >= _materials.size():
		return -1.0
	var material := _materials[index]
	if material == null:
		return -1.0
	return float(material.get(property_name))
