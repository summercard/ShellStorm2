class_name VfxGooDeathBase3D
extends VfxEffectBase3D
## 「绿浆四溅」死亡特效的**共享实现**（两条僵尸死亡链路共用；本类自身不挂 Prefab、也不注册进池）。
##
## 为什么抽出来（业主 2026-10-14）：业主口径是「把**小僵尸的死亡特效放大两倍**给胖子僵尸用，
## 然后带一个绿色冲击波的效果」—— 也就是两件事**本来就是同一套表现**，只差「尺寸」与
## 「有没有冲击波」两个旋钮。若各抄一份 400 行，两个 Prefab 的节奏 / 配色 / 落地数学会立刻开始漂移；
## 抽成基类后两者共用同一段身体，差异只剩子类里那几个覆盖点。
##
## ⚠ 本文件的身体是 FX01-19 v001 的**逐字副本**（含 `_burst_direction` 的抬高式俯仰、
## 各处内联公式）。业主明确要求「小僵尸的死亡特效不要改变」，所以这一份**不动**：
## 抽公共件时不能让既有特效的观感发生任何漂移。新件（命中爆点 FX01-20）走 `ToonVfxBurst`，
## 那里把 `pitch_center` 设成同一个 0.15 就能复刻这套形状。
##
## 子类只覆盖这几处（其余一行都不用改）：
##   · `_asset_id()` / `_asset_version()` —— 账本登记的资产身份
##   · `_shockwave_enabled()`             —— 要不要那圈绿色冲击波
## 尺寸**不在这里**：由调用方按 `effect_size` 传入（小僵尸 1.0 / 胖子僵尸 2.0），
## 保持「1.0 = 规格尺寸」这唯一一条口径。
##
## 四部分（节点名固定，验收按名读取）：
##   A. `Burst0..11` —— **爆炸粒子**：出生瞬间从胸口向外炸开的绿色方块。
##      尺寸走「很小 → 过冲峰值 → 收缩」三段（峰值/起点 = 4.6 倍），0.24s 内收干净
##      （「打击力度感」的主要来源：一帧内铺满视野再迅速收掉）。
##   B. `Splat0..13` —— **飞溅粒子**：同样从胸口抛出，按抛物线飞出、落地后压扁（squash）
##      再缩没。落点由**解析式**求出（起抛高度取自 `context.floor_y`），不接物理引擎、无碰撞体。
##   C. `Puddle0..3` —— **地上的液体**：落在**飞溅粒子真实落点**上的扁平方块（「方形」读法），
##      出现 → **严格停留 0.50s** → 慢慢下沉 0.30m 并淡出。四块错峰出现 ⇒ 有节奏。
##   D. `Shockwave0..2` —— **绿色冲击波**（**仅 `_shockwave_enabled()` 为真的子类**）：
##      贴地平铺、向外扫的 3 层错峰环，0.45s 后收、0.60s 收干净。
##
## 全向对称：刻意不消费 `context.forward` / `context.normal`（死亡爆发没有朝向）。
## 地面高度：`context.floor_y` 是**唯一真源**（本仓楼层向下建造，98F ≈ −1176 m，绝不写死 0）；
##          未传时按调用方口径 `world_pos.y - SPAWN_CENTER_LIFT` 反推脚底，仍不写死 0。
## 纯视觉：Prefab 内无任何碰撞体（验收有断言盯着）。
## 池化安全：所有可变状态（子节点 scale / position / rotation / 材质 alpha / 灯能量）
##          都由 `_on_tick(elapsed)` 从 elapsed **重算**（不依赖上一帧、不依赖 tick 历史）
##          ⇒ 复借天然复位，不残留上一轮形态。
## 确定性：脚本内**不出现 `randf()`** —— 逐项错峰量全部写成「下标 → 常量」的确定性映射。
## 颜色：业主指定「绿色方块」⇒ 基色恒为僵尸绿，调用方本色（小僵尸暗红 / 警察青 /
##      胖子僵尸橄榄绿）只作 25% 轻微偏移，保证绿色读法不被冲掉（见 `_reset_state`）。

## ── 子类覆盖点 ───────────────────────────────────────────────────────────
## 账本登记的 AssetID（Prefab 根 meta 里也写一份，验收两边比对）
func _asset_id() -> String:
	return ""


## 资产版本
func _asset_version() -> String:
	return "v001"


## 要不要那圈绿色冲击波（业主指定：只有胖子僵尸那条要）
func _shockwave_enabled() -> bool:
	return false


const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")
const Burst = preload("res://src/vfx/ToonVfxBurst.gd")


## ── 总寿命 ────────────────────────────────────────────────────────────────
## 1.35s = 0.28（爆开+飞溅落地） + 0.025×3（液体错峰） + 0.09（出现） + 0.50（停留）
##        + 0.36（下沉） + 0.045（尾巴）；最晚一块液体在 1.305s 收干净。
const TOTAL_LIFETIME := 1.35

## 调用方（`Enemy3D._spawn_effect` / `_spawn_goo_death_burst`）把一次性特效放在
## 「怪胸口」：global_position.y = 脚底 + 0.65。未显式给 `context.floor_y` 时按这个
## 口径反推脚底 —— 仍然不是写死 0。
const SPAWN_CENTER_LIFT := 0.65

## ── 颜色（僵尸绿）────────────────────────────────────────────────────────
const GOO_GREEN := Color(0.36, 0.78, 0.26, 1.0)
const GOO_GREEN_LIGHT := Color(0.63, 0.96, 0.40, 1.0)
const GOO_GREEN_DARK := Color(0.16, 0.44, 0.12, 1.0)
## 调用方本色只作这么多比例的偏移（0 = 完全忽略调用方颜色）
const CALLER_COLOR_BLEND := 0.25

## ── A 爆炸粒子 ───────────────────────────────────────────────────────────
const BURST_COUNT := 12
const BURST_WINDOW_SEC := 0.24
## 前 18% 冲到过冲峰值，其余时间收缩（尺度变化是「有大小变化动画」的硬证据）
const BURST_POP_RATIO := 0.18
const BURST_SCALE_MIN := 0.25
const BURST_SCALE_PEAK := 1.15
const BURST_SCALE_END := 0.35
## 出生半径基准（× size）：t=0 就该是**一圈数得出个数的方块壳**，而不是挤成一坨的实心球。
## 真渲染实测（2026-10-14）：不加这一项时 0.06s 帧读作「一大块绿色」，看不出「方块爆开」。
const BURST_RING_START := 0.30
const BURST_DIST_START := 0.05
const BURST_DIST_END := 1.35
## 外推包络的陡度：>1 = 前段就冲得远。要让「炸开半径」跑在「方块变大」前面，
## 否则 0.06s 那一帧十几个方块会互相插进去，读成一块整体而非「方块爆开」
## （真渲染实测：指数 2.0 时重合成团，3.0 时每个方块之间留得出缝）。
const BURST_REACH_POW := 3.0
## 方块基准边长（米，× effect_size × 各自 size_ratio）。业主「粒子不要太小」⇒ 基准偏大。
const BURST_CUBE_BASE := 0.34
const BURST_FADE_START_RATIO := 0.45

## ── B 飞溅粒子 ───────────────────────────────────────────────────────────
const SPLAT_COUNT := 14
## 重力取 30（比真重力 9.8 大三倍）：0.25s 内飞出去再砸到地上 ⇒ 紧凑、有「打击感」。
## 与 FX01-07 弹壳的 9.8 口径**无关**（那是真实抛壳手感，这是特效节奏）。
const SPLAT_GRAVITY := 30.0
const SPLAT_SPEED_MIN := 2.4
const SPLAT_SPEED_MAX := 5.4
const SPLAT_LIFT_MIN := 0.6
const SPLAT_LIFT_MAX := 2.0
const SPLAT_CUBE_BASE := 0.26
## 落地后压扁并缩没的时间
const SPLAT_SQUASH_SEC := 0.11
const SPLAT_FLY_SHRINK_END := 0.62

## ── C 地上的液体 ─────────────────────────────────────────────────────────
const PUDDLE_COUNT := 4
## 液体的落点直接取这几颗飞溅粒子的**真实落点**（不再另立第二份散布口径）
const PUDDLE_SOURCE_SPLATS: Array[int] = [1, 4, 7, 10]
const PUDDLE_APPEAR_SEC := 0.28
const PUDDLE_APPEAR_STAGGER := 0.025
const PUDDLE_APPEAR_DUR := 0.09
const PUDDLE_POP_OVERSHOOT := 1.18
## 业主指定：停留 0.5 秒
const PUDDLE_HOLD_SEC := 0.50
const PUDDLE_SINK_SEC := 0.36
const PUDDLE_SIDE_BASE := 0.72
const PUDDLE_THICKNESS := 0.05
const PUDDLE_LIFT := 0.035
const PUDDLE_SINK_DEPTH := 0.30

## ── D 绿色冲击波（**仅 `_shockwave_enabled()` 为真的子类**）────────────────
## 贴地平铺的 3 层错峰环。`ToonVfx.ring_mesh()` 的 `outer_radius = 0.72`
## ⇒ 外缘世界半径 = 0.72 × scale，最大 = 0.72 × SHOCKWAVE_SCALE_END。
## 取 END = 2.15 ⇒ 外缘 1.548 × size，与爆炸粒子的外推半径（1.65 × size）同一量级
## ——冲击波「追得上」炸开的方块，不会显得是两件不相干的东西。
const SHOCKWAVE_COUNT := 3
const SHOCKWAVE_PERIOD_SEC := 0.55
const SHOCKWAVE_SCALE_START := 0.15
const SHOCKWAVE_SCALE_END := 2.15
const SHOCKWAVE_PEAK_ALPHA := 0.88
## 贴地高度（相对地面）：环面躺在 XZ，抬一点点避免与地板 z-fighting
const SHOCKWAVE_LIFT := 0.03
## 时间窗：0.45s 后开始收、0.60s 收干净。**必须有这一层** —— 相位是 `fmod` 循环的，
## 没有窗口的话任何时刻都至少有一层亮着，「到点收干净」永远不成立（实测 0.66s 仍亮）。
## 冲击波属于「爆开那一下」，不该跟后面 0.7s 的地面液体停留抢注意力。
const SHOCKWAVE_END_SEC := 0.60
const SHOCKWAVE_FADE_SEC := 0.15

## ── 灯光真源 ─────────────────────────────────────────────────────────────
## 范围随 size 线性（`omni_range = LIGHT_RANGE_BASE × effect_size`）；
## 能量按包络衰减且**不随 size 缩放**；寿命末端必须归零（否则池化复借会长明灯）。
##
## `LIGHT_DECAY_SEC` 必须**早于**地面液体的公共停留窗口（`[0.445, 0.870]`）结束：
## 灯还亮着时地面亮度一直在变，真渲染上会把「液体完全静止的 0.5 秒」糊掉
## （实拍对比 0.50s 与 0.85s 两帧：不设这条时限时像素差最大 83、13 万像素受影响；
## 提前到 0.34s 归零后两帧逐位相同 ⇒ 视觉上的「停留」与数值上的「停留」对齐）。
const LIGHT_RANGE_BASE := 4.2
const LIGHT_ENERGY := 6.0
const LIGHT_DECAY_SEC := 0.34
const LIGHT_COLOR := Color(0.55, 1.0, 0.42)

var _cube_mesh: BoxMesh

var _burst: Array[MeshInstance3D] = []
var _splat: Array[MeshInstance3D] = []
var _puddle: Array[MeshInstance3D] = []
var _shockwave: Array[MeshInstance3D] = []

var _mat_burst: StandardMaterial3D
var _mat_splat: StandardMaterial3D
var _mat_shockwave: StandardMaterial3D
var _puddle_mats: Array[StandardMaterial3D] = []

var _goo_light: OmniLight3D

## 逐项确定性常量（构建期算一次；tick 只按 elapsed 求值，避免随机与残留）
var _burst_dirs: Array[Vector3] = []
var _burst_size_ratio: Array[float] = []
var _splat_dirs: Array[Vector3] = []
var _splat_speed: Array[float] = []
var _splat_lift: Array[float] = []
var _splat_size_ratio: Array[float] = []
## 每次激活都要重算（依赖起抛高度 ⇒ 依赖 context.floor_y）
var _splat_land_t: Array[float] = []
var _splat_land_pos: Array[Vector3] = []

var _floor_local_y := 0.0
var _height_above_floor := SPAWN_CENTER_LIFT
var _goo_color := GOO_GREEN


func _on_activate(world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	lifetime = TOTAL_LIFETIME
	if _cube_mesh == null:
		_build()
	_resolve_floor(world_pos, context)
	_reset_state(color, size)
	_on_tick(0.0, lifetime)


## 地面高度真源：优先 `context.floor_y`；缺省时按调用方「胸口 = 脚底 + SPAWN_CENTER_LIFT」
## 的口径反推脚底。**绝不以 0 兜底** —— 塔楼楼层向下建造（`stage.position.y = -12.0 × 层号`，
## 98F ≈ −1176 m），写死 0 会让所有地面件瞬移到世界原点附近。
func _resolve_floor(world_pos: Vector3, context: Dictionary) -> void:
	var floor_y: float = float(context.get("floor_y", world_pos.y - SPAWN_CENTER_LIFT))
	# 起抛高度（胸口到地面）不得小于 0.20m，否则抛物线解析式退化成「立刻落地」
	_height_above_floor = maxf(0.20, world_pos.y - floor_y)
	_floor_local_y = -_height_above_floor


func _build() -> void:
	# 一个 1×1×1 的共享方块：所有件靠 scale 摊到各自尺寸（省 mesh，也保证「方块」读法统一）
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3.ONE

	# UNSHADED + ALPHA：卡通纯色、不受场景光照影响 ⇒ 暗处也读得出「绿」。
	_mat_burst = ToonVfx.toon_material(GOO_GREEN_LIGHT)
	_mat_splat = ToonVfx.toon_material(GOO_GREEN)

	# ── A 爆炸粒子 ──
	for index in BURST_COUNT:
		var cube := _add_cube("Burst%d" % index, _mat_burst)
		_burst_dirs.append(_burst_direction(index, BURST_COUNT))
		_burst_size_ratio.append(
			0.62 + 0.76 * float((index * 7) % BURST_COUNT) / float(BURST_COUNT)
		)
		_burst.append(cube)

	# ── B 飞溅粒子 ──
	for index in SPLAT_COUNT:
		var cube := _add_cube("Splat%d" % index, _mat_splat)
		var ratio := float((index * 5) % SPLAT_COUNT) / float(SPLAT_COUNT)
		_splat_dirs.append(_splat_direction(index, SPLAT_COUNT))
		_splat_speed.append(lerpf(SPLAT_SPEED_MIN, SPLAT_SPEED_MAX, ratio))
		# 飞得远的抛得低、飞得近的抛得高 ⇒ 落点分布不被压成一条弧线
		_splat_lift.append(lerpf(SPLAT_LIFT_MAX, SPLAT_LIFT_MIN, ratio))
		_splat_size_ratio.append(
			0.66 + 0.68 * float((index * 3) % SPLAT_COUNT) / float(SPLAT_COUNT)
		)
		_splat_land_t.append(0.0)
		_splat_land_pos.append(Vector3.ZERO)
		_splat.append(cube)

	# ── C 地上的液体（每块一份材质：可各自错峰出现与淡出）──
	for index in PUDDLE_COUNT:
		var mat := ToonVfx.toon_material(GOO_GREEN)
		var plate := _add_cube("Puddle%d" % index, mat)
		_puddle_mats.append(mat)
		_puddle.append(plate)

	# ── D 绿色冲击波（仅 `_shockwave_enabled()` 的子类）──
	# TorusMesh 的环轴是 Y ⇒ 环面天然躺在 XZ，**不需要旋转**（与 FX01-18 的「地面平铺」同口径）。
	if _shockwave_enabled():
		_mat_shockwave = ToonVfx.toon_material(GOO_GREEN_LIGHT, 0.75)
		for index in SHOCKWAVE_COUNT:
			var ring := MeshInstance3D.new()
			ring.name = "Shockwave%d" % index
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = 0.62
			ring_mesh.outer_radius = 0.72
			ring_mesh.rings = 40
			ring_mesh.ring_segments = 6
			ring.mesh = ring_mesh
			ring.material_override = _mat_shockwave
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
			_shockwave.append(ring)

	# 灯：贴胸口一盏绿灯，给爆开瞬间一点照明冲击；无阴影
	_goo_light = OmniLight3D.new()
	_goo_light.name = "GooLight"
	_goo_light.shadow_enabled = false
	_goo_light.light_color = LIGHT_COLOR
	_goo_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	_goo_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	add_child(_goo_light)


func _add_cube(node_name: String, mat: StandardMaterial3D) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.name = node_name
	cube.mesh = _cube_mesh
	cube.material_override = mat
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cube)
	return cube


## 爆炸粒子的放射方向：等角分布 + 交替俯仰（避免全挤在同一平面显得单薄）。
func _burst_direction(index: int, count: int) -> Vector3:
	var angle := float(index) / float(count) * TAU
	var pitch := -0.30 + 0.90 * float((index * 5) % count) / float(maxi(1, count - 1))
	return Vector3(
		cos(angle) * cos(pitch), sin(pitch), sin(angle) * cos(pitch)
	).normalized()


## 飞溅粒子的水平方向（单位向量，y 恒 0；抬升单独由 `_splat_lift` 承担）。
func _splat_direction(index: int, count: int) -> Vector3:
	var angle := float(index) / float(count) * TAU + 0.21
	return Vector3(cos(angle), 0.0, sin(angle))


func _reset_state(caller_color: Color, size: float) -> void:
	# 绿色是业主指定的口径：调用方本色（小僵尸暗红 / 警察青）只作轻微偏移，
	# 保证「绿色方块」读法不被冲掉。
	var tint := caller_color if caller_color.a > 0.001 else GOO_GREEN
	_goo_color = GOO_GREEN.lerp(tint, CALLER_COLOR_BLEND)
	_goo_color.a = 1.0
	_mat_burst.albedo_color = GOO_GREEN_LIGHT.lerp(_goo_color, 0.45)
	_mat_burst.albedo_color.a = 1.0
	_mat_splat.albedo_color = _goo_color
	_mat_splat.albedo_color.a = 1.0
	for index in _puddle_mats.size():
		_puddle_mats[index].albedo_color = GOO_GREEN_DARK.lerp(_goo_color, 0.7)
		_puddle_mats[index].albedo_color.a = 1.0

	# 冲击波（仅在启用时存在）：贴地平铺 + 不复用上一轮的缩放（tick 会立刻按相位重算）
	if not _shockwave.is_empty():
		_mat_shockwave.albedo_color = GOO_GREEN_LIGHT
		_mat_shockwave.albedo_color.a = 1.0
		for ring in _shockwave:
			ring.rotation = Vector3.ZERO
			ring.position = Vector3(0.0, _floor_local_y + SHOCKWAVE_LIFT, 0.0)
			ring.scale = Vector3.ONE

	# 飞溅粒子的抛物线落点：由解析式求出（起点在胸口 = 节点本地原点，
	# 地面在本地 y = _floor_local_y = -height）。
	for index in _splat.size():
		var lift := _splat_lift[index]
		var land_t: float = (
			lift + sqrt(lift * lift + 2.0 * SPLAT_GRAVITY * _height_above_floor)
		) / SPLAT_GRAVITY
		_splat_land_t[index] = land_t
		_splat_land_pos[index] = _splat_dirs[index] * (_splat_speed[index] * land_t)

	_goo_light.omni_range = LIGHT_RANGE_BASE * size
	_goo_light.position = Vector3(0.0, 0.12, 0.0)
	_goo_light.light_energy = LIGHT_ENERGY


func _on_tick(elapsed: float, _total: float) -> void:
	var size: float = effect_size
	_tick_burst(elapsed, size)
	_tick_splat(elapsed, size)
	_tick_shockwave(elapsed, size)
	_tick_puddle(elapsed, size)
	# 灯：出生峰值 → 指数式衰减 → 0.34s 归零（远早于地面液体的公共停留窗口）
	var decay: float = clampf(1.0 - elapsed / LIGHT_DECAY_SEC, 0.0, 1.0)
	_goo_light.light_energy = LIGHT_ENERGY * pow(decay, 1.5)


## 绿色冲击波：3 层错峰向外扫（`_shockwave_enabled()` 为假时本函数是空转）。
func _tick_shockwave(elapsed: float, size: float) -> void:
	if _shockwave.is_empty():
		return
	var window := Burst.shockwave_window(elapsed, SHOCKWAVE_END_SEC, SHOCKWAVE_FADE_SEC)
	var best_alpha := 0.0
	for index in _shockwave.size():
		var phase: float = fmod(
			elapsed / SHOCKWAVE_PERIOD_SEC + float(index) / float(SHOCKWAVE_COUNT), 1.0
		)
		var grow := Burst.shockwave_grow(
			phase, SHOCKWAVE_SCALE_START / SHOCKWAVE_SCALE_END
		)
		var scale_now: float = size * grow * SHOCKWAVE_SCALE_END
		# ⚠ 只摊 XZ、**不缩放 Y** —— 保持「平铺在地面上」的读法（验收有平铺断言 + 倾斜对照）
		_shockwave[index].scale = Vector3(scale_now, 1.0, scale_now)
		# 三层共材质 ⇒ alpha 取最亮那层，避免互相覆盖
		best_alpha = maxf(best_alpha, Burst.shockwave_alpha(phase, SHOCKWAVE_PEAK_ALPHA))
	_mat_shockwave.albedo_color.a = clampf(best_alpha * window, 0.0, 1.0)


func _tick_burst(elapsed: float, size: float) -> void:
	var lt: float = clampf(elapsed / BURST_WINDOW_SEC, 0.0, 1.0)
	var scale_mul := 0.0
	if lt <= BURST_POP_RATIO:
		scale_mul = lerpf(BURST_SCALE_MIN, BURST_SCALE_PEAK, lt / BURST_POP_RATIO)
	else:
		scale_mul = lerpf(
			BURST_SCALE_PEAK, BURST_SCALE_END, (lt - BURST_POP_RATIO) / (1.0 - BURST_POP_RATIO)
		)
	var reach: float = (
		BURST_DIST_START
		+ (BURST_DIST_END - BURST_DIST_START) * (1.0 - pow(1.0 - lt, BURST_REACH_POW))
	)
	var alpha := 1.0
	if lt > BURST_FADE_START_RATIO:
		alpha = 1.0 - (lt - BURST_FADE_START_RATIO) / (1.0 - BURST_FADE_START_RATIO)
	_mat_burst.albedo_color.a = clampf(alpha, 0.0, 1.0)

	for index in _burst.size():
		var cube := _burst[index]
		var direction := _burst_dirs[index]
		var edge: float = (
			size * BURST_CUBE_BASE * _burst_size_ratio[index] * maxf(0.0001, scale_mul)
		)
		cube.position = direction * ((BURST_RING_START + reach) * size)
		cube.scale = Vector3.ONE * edge
		# 翻滚角是 elapsed 的纯函数（不依赖 tick 历史 ⇒ 复借/跳帧都逐位可复现）
		cube.rotation = Vector3(
			direction.z * elapsed * 5.0, direction.x * elapsed * 4.0, direction.y * elapsed * 5.0
		)


func _tick_splat(elapsed: float, size: float) -> void:
	for index in _splat.size():
		var cube := _splat[index]
		var direction := _splat_dirs[index]
		var land_t: float = _splat_land_t[index]
		var edge: float = size * SPLAT_CUBE_BASE * _splat_size_ratio[index]
		if elapsed < land_t:
			var t := elapsed
			cube.position = (
				direction * (_splat_speed[index] * t)
				+ Vector3.UP * (_splat_lift[index] * t - 0.5 * SPLAT_GRAVITY * t * t)
			)
			var shrink: float = lerpf(1.0, SPLAT_FLY_SHRINK_END, clampf(t / land_t, 0.0, 1.0))
			cube.scale = Vector3.ONE * maxf(0.0001, edge * shrink)
			cube.rotation = Vector3(
				direction.z * elapsed * 9.0, direction.x * elapsed * 6.0, direction.x * elapsed * 7.0
			)
		else:
			# 落地：压扁（squash）→ 缩没；位置钉在解析式算出的落点上
			var after: float = clampf((elapsed - land_t) / SPLAT_SQUASH_SEC, 0.0, 1.0)
			var fade: float = 1.0 - after
			cube.position = (
				_splat_land_pos[index] + Vector3.UP * (_floor_local_y + PUDDLE_LIFT * 0.5)
			)
			cube.scale = Vector3(
				maxf(0.0001, edge * 1.35 * fade),
				maxf(0.0001, edge * 0.22 * fade),
				maxf(0.0001, edge * 1.35 * fade)
			)
			cube.rotation = Vector3(
				direction.z * land_t * 9.0, direction.x * land_t * 6.0, direction.x * land_t * 7.0
			)


func _tick_puddle(elapsed: float, size: float) -> void:
	for index in _puddle.size():
		var plate := _puddle[index]
		var source := _splat_land_pos[PUDDLE_SOURCE_SPLATS[index] % _splat_land_pos.size()]
		var appear_at: float = PUDDLE_APPEAR_SEC + float(index) * PUDDLE_APPEAR_STAGGER
		var hold_start: float = appear_at + PUDDLE_APPEAR_DUR
		var hold_end: float = hold_start + PUDDLE_HOLD_SEC
		var sink_end: float = hold_end + PUDDLE_SINK_SEC
		var span: float = PUDDLE_COUNT - 1
		var side: float = (
			size * PUDDLE_SIDE_BASE * (0.86 + 0.30 * float(index) / maxf(1.0, span))
		)
		var lift := PUDDLE_LIFT
		var scale_mul := 0.0001
		var alpha := 0.0
		if elapsed >= appear_at and elapsed < hold_start:
			var t: float = (elapsed - appear_at) / PUDDLE_APPEAR_DUR
			scale_mul = lerpf(0.35, PUDDLE_POP_OVERSHOOT, 1.0 - pow(1.0 - t, 2.4))
			alpha = clampf(t * 1.6, 0.0, 1.0)
		elif elapsed >= hold_start and elapsed < hold_end:
			# 严格停留：这 0.50s 内 scale / position / alpha 一律不动
			scale_mul = 1.0
			alpha = 1.0
		elif elapsed >= hold_end and elapsed < sink_end:
			var t: float = (elapsed - hold_end) / PUDDLE_SINK_SEC
			scale_mul = lerpf(1.0, 0.84, t)
			lift = PUDDLE_LIFT - PUDDLE_SINK_DEPTH * t
			alpha = 1.0 - t
		plate.scale = Vector3(side * scale_mul, PUDDLE_THICKNESS, side * scale_mul)
		plate.position = Vector3(source.x, _floor_local_y + lift, source.z)
		plate.rotation = Vector3(0.0, float(index) * 0.62 + 0.18, 0.0)
		_puddle_mats[index].albedo_color.a = alpha


func _on_lifetime_expired() -> void:
	if is_instance_valid(_goo_light):
		_goo_light.light_energy = 0.0


## 供验收 / 巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	var light_valid := is_instance_valid(_goo_light)
	# 地面件相对世界 UP 的对齐度（1.0 = 完全平铺；故意倾斜会掉下来）
	var plane_dot_min := 1.0
	for plate in _puddle:
		if is_instance_valid(plate):
			plane_dot_min = minf(
				plane_dot_min, plate.global_basis.y.normalized().dot(Vector3.UP)
			)
	var shockwave_outer_world_radius := 0.0
	var shockwave_count := 0
	var shockwave0_scale := 0.0
	for index in _shockwave.size():
		var ring := _shockwave[index]
		if not is_instance_valid(ring):
			continue
		if index == 0:
			shockwave0_scale = ring.scale.x
		plane_dot_min = minf(
			plane_dot_min, ring.global_basis.y.normalized().dot(Vector3.UP)
		)
		if ring.mesh is TorusMesh:
			shockwave_count += 1
			shockwave_outer_world_radius = maxf(
				shockwave_outer_world_radius,
				Burst.ring_outer_radius(ring.mesh as TorusMesh, ring.scale.x)
			)
	var land_t_max := 0.0
	for value in _splat_land_t:
		land_t_max = maxf(land_t_max, value)
	# 飞溅粒子的高度包络（验收用它证明「真的抛起来又掉到地上」）
	var splat_max_y := -INF
	var splat_min_y := INF
	var splat_positions: Array[Vector3] = []
	var splat_scale_max := 0.0
	for cube in _splat:
		if is_instance_valid(cube):
			splat_max_y = maxf(splat_max_y, cube.position.y)
			splat_min_y = minf(splat_min_y, cube.position.y)
			splat_scale_max = maxf(splat_scale_max, cube.scale.x)
			splat_positions.append(cube.position)
	var burst_scale_max := 0.0
	var burst_radius_min := INF
	var burst_radius_max := 0.0
	for cube in _burst:
		if is_instance_valid(cube):
			burst_scale_max = maxf(burst_scale_max, cube.scale.x)
			var radius := Vector3(cube.position.x, 0.0, cube.position.z).length()
			burst_radius_min = minf(burst_radius_min, radius)
			burst_radius_max = maxf(burst_radius_max, radius)
	# 方块方向之和：**分别给出水平（绕竖直轴的均匀性）与三维模长**。
	# ⚠ 别只给三维模长：这套方向沿用死亡件 v001 的「抬高式俯仰」，垂直分量天然不抵消
	# （三维模长实测 ~2.7）。判「一圈炸开」要看**水平分量**，看三维会把这个有意设计误判成缺陷。
	var spread := Vector3.ZERO
	for direction in _burst_dirs:
		spread += direction
	var puddle_positions: Array[Vector3] = []
	for plate in _puddle:
		if is_instance_valid(plate):
			puddle_positions.append(plate.position)
	return {
		"asset_id": get_meta("asset_id", _asset_id()),
		"asset_version": get_meta("asset_version", _asset_version()),
		"node_count": get_child_count(),
		"lifetime": lifetime,
		"effect_size": effect_size,
		"burst_count": _burst.size(),
		"splat_count": _splat.size(),
		"puddle_count": _puddle.size(),
		"shockwave_count": shockwave_count,
		"shockwave_alpha": _mat_shockwave.albedo_color.a if _mat_shockwave != null else 0.0,
		"shockwave_color": _mat_shockwave.albedo_color if _mat_shockwave != null else Color.BLACK,
		"shockwave_outer_world_radius": shockwave_outer_world_radius,
		# 第 1 环自己的 scale：验收靠它量「单层真的从很小扫到很大」。
		# ⚠ 不能拿「所有层取最大」去量生长 —— 三层相位错开，最大层在 t=0 就已经很大了
		# （实测 1.068），会把「起始」读成峰值、判据恒假。
		"shockwave0_scale_x": shockwave0_scale,
		"goo_color": _goo_color,
		"green_dominant": _goo_color.g > _goo_color.r and _goo_color.g > _goo_color.b,
		"has_goo_light": light_valid,
		"light_name": _goo_light.name if light_valid else "",
		"light_energy": _goo_light.light_energy if light_valid else 0.0,
		"light_range": _goo_light.omni_range if light_valid else 0.0,
		"light_shadows": _goo_light.shadow_enabled if light_valid else false,
		"burst_scale_x": _burst[0].scale.x if not _burst.is_empty() else 0.0,
		"burst_scale_max_x": burst_scale_max,
		"burst_radius_min": burst_radius_min if not _burst.is_empty() else 0.0,
		"burst_radius_max": burst_radius_max,
		"burst_alpha": _mat_burst.albedo_color.a if _mat_burst != null else 0.0,
		"splat_scale_x": _splat[0].scale.x if not _splat.is_empty() else 0.0,
		"splat_scale_max_x": splat_scale_max,
		"splat_pos_max_y": splat_max_y if not _splat.is_empty() else 0.0,
		"splat_pos_min_y": splat_min_y if not _splat.is_empty() else 0.0,
		"splat_land_positions": splat_positions,
		"puddle_scale_x": _puddle[0].scale.x if not _puddle.is_empty() else 0.0,
		"puddle_pos_y": _puddle[0].position.y if not _puddle.is_empty() else 0.0,
		"puddle_positions": puddle_positions,
		"puddle_alpha": _puddle_mats[0].albedo_color.a if not _puddle_mats.is_empty() else 0.0,
		"floor_local_y": _floor_local_y,
		"height_above_floor": _height_above_floor,
		"splat_land_t_max": land_t_max,
		"puddle_hold_seconds": PUDDLE_HOLD_SEC,
		"ground_plane_dot_min": plane_dot_min,
		"spread_sum_x": spread.x,
		"spread_sum_z": spread.z,
		"spread_sum_length": spread.length(),
		# 尺度变化倍率（过冲峰值 / 起点）：验收用它证明「真的有大小变化动画」
		"burst_scale_peak_ratio": BURST_SCALE_PEAK / BURST_SCALE_MIN,
	}
