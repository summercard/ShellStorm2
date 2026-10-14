class_name VfxMetalSparkHit3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-21 / VFX-METAL-SPARK-HIT-3D 金属打击反馈特效（击中「非僵尸三兄弟」的一切目标）
##
## 用途：子弹打到墙面 / 掩体 / 地面 / 非僵尸怪种时的命中反馈。
##
## 来历（业主 2026-10-14）：原本的口径是对旧 `VFX-IMPACT-3D`「缩小 60%」，
## 追问尺寸读数后业主改为「**重新制作一个**，通过一个打击到金属的粒子反馈的特效，
## 用白色方块粒子和 2 根长条的金色火星一样飞溅去替代，这个不要用太多粒子，
## 4-5 颗 + 2 根金色火星即可」。
##
## ⇒ 本件是**新资产**（新 AssetID），不是 `VFX-IMPACT-3D` 的改版：
##   · 造型语言完全不同（白方块 + 金色长条 vs 亮芯 + 星芒 + 冲击环 + 碎屑）；
##   · `VFX-IMPACT-3D`（FX01-02）保持原样，继续服务它剩下的用途
##     （非僵尸怪种的死亡爆点、护盾弹开反馈），那些是**死亡/格挡**语义，不是「击中非僵尸」。
##
## 件数刻意少（业主指定「不要用太多粒子」）：
##   · 5 颗白色方块 —— 打击的「实体感」；
##   · 2 根金色长条火星 —— 金属被打出火花的那两条「线」，是「金属」这个读法的关键。
##
## 朝向契约 `context.normal`（**本件与 FX01-17/19/20 相反，它是唯一消费法线的战斗命中件**）：
##   · 局部 +Y 对齐 `normal`（缺省 UP）⇒ 局部 XZ 平面 = 被击表面；
##   · 金色火星**在切平面内**飞（沿表面擦出去），白方块**沿法线向外**喷 ——
##     这正是金属被击：「火花擦着表面走、碎屑往外崩」。
##   · 反向对照见验收：喂一条垂直法线 ⇒ 火星方向与新切平面必须对不上（证明真的消费了它）。
##
## ⚠ **刻意不带灯**：与 FX01-20 同理，它是每一发子弹/每一次近战都生成的高频件。
## 纯视觉：Prefab 内无任何碰撞体（验收有断言盯着）。
## 池化安全：所有可变状态由 `_on_tick(elapsed)` 从 elapsed 重算 ⇒ 复借天然复位。
## 确定性：脚本内**不出现 `randf()`**，错落量是「下标 → 常量」的确定性映射。
##
## ── 本件同时是 FX01-20 僵尸受击件的**共享体** ──────────────────────────────
## 业主 2026-10-14 第四轮：「小僵尸和警察僵尸的受击特效太大了，**使用击中其它物体的那个
## 特效，然后改成绿色即可**，放大大概 10%」⇒ 僵尸受击件与打墙/打金属件**同形**，
## 只差「色板」与「调用方给的尺寸」。所以形状/件数/运动学只能有一份实现，本件就是那一份；
## `VfxGooHit3D` 只覆盖下面这几个色板钩子 + 资产身份（10% 由调用方按档位给，见
## `Projectile3D.ZOMBIE_HIT_SIZE_RATIO`）。两侧共用同一段身体 ⇒ 两件不可能在造型上漂移。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")


## ── 子类覆盖点 ───────────────────────────────────────────────────────────
## 账本登记的 AssetID（Prefab 根 meta 里也写一份，验收两边比对）
func _asset_id() -> String:
	return "VFX-METAL-SPARK-HIT-3D"


## 资产版本
func _asset_version() -> String:
	return "v001"


## 白方块基色
func _cube_base_color() -> Color:
	return WHITE_CUBE


## 长条火星基色
func _streak_base_color() -> Color:
	return GOLD_SPARK


## 调用方本色（弹药色）的混入比例
func _caller_color_blend() -> float:
	return CALLER_COLOR_BLEND

## 寿命 = 火星段 + 0.02s 尾巴
const HIT_LIFETIME := 0.32

## ── 白色方块（业主：4-5 颗）──────────────────────────────────────────────
const CUBE_COUNT := 5
const CUBE_BASE := 0.16
const CUBE_SCALE_MIN := 0.45
const CUBE_SCALE_PEAK := 1.05
const CUBE_SCALE_END := 0.30
const CUBE_POP_RATIO := 0.20
## 白方块沿法线向外 + 切向散开。真渲染实测（2026-10-14 第一版）：切向占比 0.35~0.8、
## 外推只 0.30m 时，5 颗方块挤成一坨读不出「颗粒」，故把**切向占比整体抬高**
## （`CUBE_TANGENT_MIN/MAX`）并加大外推 —— 要的是「一撮碎屑炸开」，不是「一坨白点」。
const CUBE_OUT_DIST := 0.40
const CUBE_SPREAD_DIST := 0.34
const CUBE_TANGENT_MIN := 0.55
const CUBE_TANGENT_MAX := 1.05
const CUBE_FADE_START := 0.45

## ── 金色长条火星（业主：2 根）──────────────────────────────────────────
const STREAK_COUNT := 2
## 火星在**切平面内**擦出去；两根张角（弧度，绕法线轴对称）。
## 真渲染实测：0.34 rad 时两根几乎重叠、读成「一根小凸起」，抬到 0.62 rad 才看得出是两根。
const STREAK_HALF_ANGLE := 0.62
## 长条长度（米，× effect_size）：**这是「长条」读法的关键**。
## 第一版 0.22→0.78（size 0.55 下即 0.12→0.43m）在实拍里只是一小截凸起；
## 拉到 0.50→1.30 后才是一条能看出「拉长」的线。
const STREAK_LENGTH_START := 0.50
const STREAK_LENGTH_END := 1.30
const STREAK_DIST_START := 0.10
const STREAK_DIST_END := 0.86
## 长条从「短粗」拉成「细长」：这是火星的伸展感（不只是位移）
const STREAK_WIDTH_START := 1.20
const STREAK_WIDTH_END := 0.30
const STREAK_FADE_START := 0.30
## 外推指数：火星要「一瞬间射出去」（前段快），与方块的二次式不同
const STREAK_REACH_POW := 1.6
## 两根不等长（避免「两根一模一样的棍」的机械感）
const STREAK_LENGTH_RATIO: Array[float] = [1.0, 0.78]

## ── 颜色 ─────────────────────────────────────────────────────────────────
const WHITE_CUBE := Color(0.94, 0.94, 0.90, 1.0)
const GOLD_SPARK := Color(1.0, 0.78, 0.28, 1.0)
## 调用方本色（弹药色）只作轻微偏移，保证「白方块 + 金火星」的金属读法不被冲掉
const CALLER_COLOR_BLEND := 0.18

var _normal: Vector3 = Vector3.UP

var _cubes: Array[MeshInstance3D] = []
var _streaks: Array[MeshInstance3D] = []

var _mat_cube: StandardMaterial3D
var _mat_streak: StandardMaterial3D

var _cube_dirs: Array[Vector3] = []
var _cube_size_ratios: Array[float] = []
var _streak_dirs: Array[Vector3] = []


func _on_activate(_world_pos: Vector3, color: Color, _size: float, context: Dictionary) -> void:
	lifetime = HIT_LIFETIME
	_normal = context.get("normal", Vector3.UP) as Vector3
	if _normal.length_squared() < 0.0001:
		_normal = Vector3.UP
	_normal = _normal.normalized()
	if _cubes.is_empty():
		_build()
	# 朝向：局部 +Y 对齐 normal（同 VfxImpact3D 口径）⇒ 局部 XZ 平面就是被击表面
	global_transform = Transform3D(Basis(Quaternion(Vector3.UP, _normal)), global_position)
	_reset_state(color)
	_on_tick(0.0, lifetime)


func _build() -> void:
	# 白方块：沿法线向外为主 + 少量切向
	_cube_dirs = _cube_directions_local(CUBE_COUNT)
	_cube_size_ratios = _size_ratios(CUBE_COUNT)
	_mat_cube = ToonVfx.toon_material(_cube_base_color(), 0.35)
	for index in CUBE_COUNT:
		var cube := MeshInstance3D.new()
		cube.name = "Cube%d" % index
		cube.mesh = ToonVfx.unit_cube_mesh()
		cube.material_override = _mat_cube
		cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cube)
		_cubes.append(cube)

	# 金色长条火星：两根，在**切平面（局部 XZ）**内对称擦出去。
	# ⚠ 朝向用 `Basis.looking_at`（把**本地 -Z** 对到切向）—— 不能写 `Quaternion(UP, dir)`：
	# 后者是「把 +Y 转到 dir」，而 streak_mesh 的长轴是本地 **Z**，用错轴会让火星指向天上。
	_mat_streak = ToonVfx.toon_material(_streak_base_color(), 1.0)
	for index in STREAK_COUNT:
		var sign_t := 1.0 if index == 0 else -1.0
		var angle := STREAK_HALF_ANGLE * sign_t
		_streak_dirs.append(Vector3(sin(angle), 0.0, cos(angle)).normalized())
		var streak := MeshInstance3D.new()
		streak.name = "Streak%d" % index
		streak.mesh = ToonVfx.streak_mesh()
		streak.material_override = _mat_streak
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		streak.basis = Basis.looking_at(_streak_dirs[index])
		add_child(streak)
		_streaks.append(streak)


## 白方块方向（局部空间）：法线为主 + 切向散开（局部 +Y 就是法线）。
func _cube_directions_local(count: int) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	for index in count:
		var angle := float(index) / float(count) * TAU + 0.37
		# 切向占比逐颗不同（0.55~1.05）⇒ 一撮散开，而不是一圈等角
		var tangent_share: float = lerpf(
			CUBE_TANGENT_MIN,
			CUBE_TANGENT_MAX,
			float((index * 3) % count) / float(maxi(1, count - 1))
		)
		dirs.append(Vector3(
			cos(angle) * tangent_share, 1.0, sin(angle) * tangent_share
		).normalized())
	return dirs


func _size_ratios(count: int) -> Array[float]:
	var ratios: Array[float] = []
	for index in count:
		ratios.append(0.78 + 0.48 * float((index * 2) % count) / float(count))
	return ratios


func _reset_state(caller_color: Color) -> void:
	var tint := caller_color if caller_color.a > 0.001 else _cube_base_color()
	var blended := _cube_base_color().lerp(tint, _caller_color_blend())
	blended.a = 1.0
	_mat_cube.albedo_color = blended
	_mat_streak.albedo_color = _streak_base_color()
	for cube in _cubes:
		cube.position = Vector3.ZERO
		cube.scale = Vector3.ONE
		cube.rotation = Vector3.ZERO
	for index in _streaks.size():
		_streaks[index].scale = Vector3.ONE
		_streaks[index].position = Vector3.ZERO


func _on_tick(elapsed: float, _total: float) -> void:
	var size: float = effect_size
	var lt: float = clampf(elapsed / HIT_LIFETIME, 0.0, 1.0)

	# 白方块：过冲后收缩，沿法线向外喷
	var cube_mul := _scale_mul(lt, CUBE_POP_RATIO, CUBE_SCALE_MIN, CUBE_SCALE_PEAK, CUBE_SCALE_END)
	var cube_out := (CUBE_OUT_DIST + CUBE_SPREAD_DIST) * pow(lt, 0.75)
	var cube_alpha := 1.0
	if lt > CUBE_FADE_START:
		cube_alpha = 1.0 - (lt - CUBE_FADE_START) / (1.0 - CUBE_FADE_START)
	_mat_cube.albedo_color.a = clampf(cube_alpha, 0.0, 1.0)
	for index in _cubes.size():
		var cube := _cubes[index]
		var direction := _cube_dirs[index]
		var edge: float = size * CUBE_BASE * _cube_size_ratios[index] * maxf(0.0001, cube_mul)
		cube.position = direction * (cube_out * size)
		cube.scale = Vector3.ONE * edge
		cube.rotation = Vector3(
			direction.z * elapsed * 7.0, direction.x * elapsed * 5.0, direction.y * elapsed * 6.0
		)

	# 金色长条火星：前段快速射出去 + 从短粗拉成细长
	var streak_reach := _reach(lt, STREAK_DIST_START, STREAK_DIST_END, STREAK_REACH_POW)
	var streak_len: float = lerpf(STREAK_LENGTH_START, STREAK_LENGTH_END, pow(lt, 0.55))
	var streak_width: float = lerpf(STREAK_WIDTH_START, STREAK_WIDTH_END, pow(lt, 0.6))
	var streak_alpha := 1.0
	if lt > STREAK_FADE_START:
		streak_alpha = 1.0 - (lt - STREAK_FADE_START) / (1.0 - STREAK_FADE_START)
	_mat_streak.albedo_color.a = clampf(streak_alpha, 0.0, 1.0)
	for index in _streaks.size():
		var streak := _streaks[index]
		var direction := _streak_dirs[index]
		streak.position = direction * (streak_reach * size)
		# 长轴是本地 Z（mesh 基准长 1.0m）⇒ scale.z 直接就是米数
		var length_ratio: float = (
			STREAK_LENGTH_RATIO[index % STREAK_LENGTH_RATIO.size()]
		)
		streak.scale = Vector3(
			streak_width, streak_width, maxf(0.0001, streak_len * length_ratio * size)
		)


func _scale_mul(lt: float, pop_ratio: float, low: float, peak: float, end: float) -> float:
	var t: float = clampf(lt, 0.0, 1.0)
	var pop: float = clampf(pop_ratio, 0.01, 0.99)
	if t <= pop:
		return lerpf(low, peak, t / pop)
	return lerpf(peak, end, (t - pop) / (1.0 - pop))


func _reach(lt: float, dist_start: float, dist_end: float, expo: float) -> float:
	var t: float = clampf(lt, 0.0, 1.0)
	return dist_start + (dist_end - dist_start) * (1.0 - pow(1.0 - t, maxf(1.0, expo)))


## 供验收 / 巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	var streak_world_dirs: Array[Vector3] = []
	for index in _streaks.size():
		if is_instance_valid(_streaks[index]):
			streak_world_dirs.append(-_streaks[index].global_basis.z)
	return {
		"asset_id": get_meta("asset_id", _asset_id()),
		"asset_version": get_meta("asset_version", _asset_version()),
		"node_count": get_child_count(),
		"lifetime": lifetime,
		"effect_size": effect_size,
		"cube_count": _cubes.size(),
		"streak_count": _streaks.size(),
		"normal": _normal,
		"cube_color": _mat_cube.albedo_color if _mat_cube != null else Color.BLACK,
		"streak_color": _mat_streak.albedo_color if _mat_streak != null else Color.BLACK,
		"cube_scale_max_x": _max_scale(_cubes),
		"streak_length_max": _max_scale_z(_streaks),
		"cube_pos_max_y": _max_pos_y(_cubes),
		"streak_dir_world": streak_world_dirs,
		# 火星是否真的**在切平面内**（世界方向 · normal 应 ≈ 0）
		"streak_normal_dot_max": _streak_normal_dot(streak_world_dirs),
		"has_light": false,
		"light_name": "",
		"light_energy": 0.0,
		"light_range": 0.0,
		"light_shadows": false,
		"consumes_normal": true,
	}


func _max_scale(nodes: Array[MeshInstance3D]) -> float:
	var value := 0.0
	for node in nodes:
		if is_instance_valid(node):
			value = maxf(value, node.scale.x)
	return value


func _max_scale_z(nodes: Array[MeshInstance3D]) -> float:
	var value := 0.0
	for node in nodes:
		if is_instance_valid(node):
			value = maxf(value, node.scale.z)
	return value


func _max_pos_y(nodes: Array[MeshInstance3D]) -> float:
	var value := -INF
	for node in nodes:
		if is_instance_valid(node):
			value = maxf(value, node.position.y)
	return value if value > -INF else 0.0


func _streak_normal_dot(world_dirs: Array[Vector3]) -> float:
	var value := 0.0
	for direction in world_dirs:
		if direction.length_squared() < 0.0001:
			continue
		value = maxf(value, absf(direction.normalized().dot(_normal)))
	return value
