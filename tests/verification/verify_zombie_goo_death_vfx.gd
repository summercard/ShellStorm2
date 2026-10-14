extends Node
## 专项验收：小僵尸 / 警察僵尸死亡「绿色方块爆开」特效（FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D`）
## ＋ 「状态机上去掉倒地动画」这条行为契约。
##
## 业主口径（2026-10-14）：「绿色方块爆开的粒子，掉落地面，然后地面上有方形像液体一样的
## 扁平模型，停留 0.5 秒后慢慢下沉消失；特效由三部分组成 —— 爆炸的粒子、飞溅出去的粒子、
## 地上的液体；节奏自己把控好，要有打击力度感、节奏感；粒子不要太小，可以大一点，
## 需要有大小的变化动画」，并「配置在小僵尸和警察僵尸死亡后，状态机上去掉倒地动画」。
##
## 两层验收（规范 docs/v0.1/14.6_特效系统与制作规范.md §6）：
##   A. 机制层：Prefab 资产契约 / 灯光真源 / 三段节奏与尺度动画 / 地面平铺 /
##      `floor_y` 契约 / 尺寸线性 / 无碰撞体；
##   B. 端到端接线层：`Enemy3D._die()` 真的借出了该特效、真的**不再走倒地动画**、
##      且**没有**把这类怪塞进死亡显影组；反向对照 = 胖子僵尸仍然保留倒地尸体。
## 期望值一律硬编码在验收侧（不引用被测脚本常量，防自印证）；末尾有防假绿哨兵。

const GOO_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_zombie_goo_death_root_top3d.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

const GOO_ASSET_ID := "VFX-ZOMBIE-GOO-DEATH-3D"
## v001：业主 2026-10-14 第二轮明确「**小僵尸的死亡特效不要改变**」⇒ 本件回到第一轮那一版，
## 未改版。（中途那一版「放大 2 倍 + 绿色冲击波」被业主指名是**给胖子僵尸用的**，
## 落在 FX01-17 `VfxDeathBlast3D`；本件与它共用 `VfxGooDeathBase3D` 的身体但不启用冲击波。）
const EXPECTED_VERSION := "v001"
const EXPECTED_LIFETIME := 1.35
const EXPECTED_BURST_COUNT := 12
const EXPECTED_SPLAT_COUNT := 14
const EXPECTED_PUDDLE_COUNT := 4
## 业主明确：**小僵尸死亡没有冲击波**（只有胖子僵尸那条有）⇒ 这里必须是 0
const EXPECTED_SHOCKWAVE_COUNT := 0
## 12 方块 + 14 飞溅 + 4 液体 + 1（GooLight）
const EXPECTED_NODE_MIN := 31
const EXPECTED_LIGHT_NAME := "GooLight"
const EXPECTED_LIGHT_RANGE_PER_SIZE := 4.2
const EXPECTED_LIGHT_ENERGY_PEAK := 6.0
## 灯必须在**地面液体公共停留窗口 [0.445, 0.870] 之前**归零，否则地面亮度一直在变，
## 真渲染上会把「液体完全静止的 0.5 秒」糊掉。
const EXPECTED_LIGHT_DECAY_SEC := 0.34
const PUDDLE_COMMON_HOLD_START := 0.445

## 三部分各自的节奏（秒）—— 期望值硬编码，与被测脚本的常量互不派生
const EXPECTED_BURST_WINDOW := 0.24
const EXPECTED_BURST_POP_RATIO := 0.18
## 尺度变化倍率 = 过冲峰值 / 起点 = 1.15 / 0.25 = 4.6（「有大小变化动画」的量化）
const EXPECTED_BURST_SCALE_PEAK_RATIO := 4.6
const EXPECTED_PUDDLE_HOLD_SECONDS := 0.50
const EXPECTED_PUDDLE_SINK_DEPTH := 0.30
const EXPECTED_PUDDLE_SINK_SEC := 0.36
const EXPECTED_PUDDLE_LIFT := 0.035

## 尺寸线性：size 1.0 与 0.8 的同一子节点 scale 比值 = 1.25
const SIZE_A := 1.0
const SIZE_B := 0.8
const SIZE_RATIO := 1.25
const SIZE_RATIO_TOLERANCE := 0.02

## 深层楼机位：塔楼楼层**向下**建造（`stage.position.y = -12.0 × 层号`，98F ≈ −1176 m）。
## 任何「地面高度 / 绝对坐标」类契约都必须在这个高度上验，否则会因为 y≈0 而假绿。
const FLOOR_DEEP := -1176.0
const SPAWN_LIFT := 0.65
## 反向对照用的地面位移（0.30m 不会触发「最低起抛高度 0.20m」的钳制）
const FLOOR_SHIFT := -0.30

const MIN_SAMPLES := 12

var _failures: Array[String] = []
var _samples := 0
var _steps: Array[Callable] = []
var _step_index := 0
var _goo_enemy: Enemy3D = null
var _killed_count := 0
var _fat_enemy: Enemy3D = null


func _ready() -> void:
	# ⚠ 分步执行（不写成 _ready 里一长串同步调用）：本仓 GDScript 的运行期报错会
	# **中断当前函数**；全串在 `_ready` 里时，中途一处报错会跳过 `_report()` ⇒
	# headless 场景永远挂着（本仓验收的经典假死）。每帧推进一步即可避免。
	_steps = [
		_check_prefab_contract,
		_check_light_truth,
		_check_rhythm_burst,
		_check_rhythm_splat,
		_check_rhythm_puddle,
		_check_ground_flatness,
		_check_floor_contract,
		_check_size_linearity,
		_check_collision_free,
		_enemy_death_case_begin,
		_tick_wait,
		_tick_wait,
		_enemy_death_case_check_recycled,
		_fat_zombie_reverse_begin,
		_tick_wait,
		_tick_wait,
		_fat_zombie_reverse_check,
		_check_shockwave_rhythm,
	]
	_step_index = 0
	set_process(true)


func _process(_delta: float) -> void:
	if _step_index < _steps.size():
		var step: Callable = _steps[_step_index]
		_step_index += 1
		print("ZOMBIE_GOO_DEATH_VFX_STEP %d/%d %s" % [_step_index, _steps.size(), step.get_method()])
		step.call()
		return
	set_process(false)
	_report()


## 空转一帧（用于等 `queue_free` 真正生效）
func _tick_wait() -> void:
	pass


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _pool() -> VfxPool3D:
	var pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if pools.is_empty():
		return null
	return pools[0] as VfxPool3D


func _count_collision_nodes(node: Node) -> int:
	var total := 0
	if node is CollisionObject3D or node is CollisionShape3D:
		total += 1
	for child in node.get_children():
		total += _count_collision_nodes(child)
	return total


## 造一个「手动步进」的实例：关掉基类 `_process`，只由用例显式调 `_on_tick`。
func _make_manual(world_y: float, floor_y: Variant, size: float) -> VfxEffectBase3D:
	var fx := GOO_SCENE.instantiate() as VfxEffectBase3D
	if fx == null:
		return null
	add_child(fx)
	fx.set_process(false)
	var context: Dictionary = {}
	if floor_y != null:
		context["floor_y"] = floor_y
	fx.activate(
		Vector3(4.0, world_y, -3.0), Color(0.58, 0.19, 0.12), size, context
	)
	return fx


func _snap(fx: VfxEffectBase3D, elapsed: float) -> Dictionary:
	fx.call("_on_tick", elapsed, EXPECTED_LIFETIME)
	return fx.call("get_presentation_snapshot") as Dictionary


# ---------------------------------------------------------------- A1 Prefab 契约
func _check_prefab_contract() -> void:
	var fx := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if fx == null:
		_failures.append("绿色方块爆开 Prefab 根节点不是 VfxEffectBase3D")
		return
	_samples += 1
	var snapshot: Dictionary = fx.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == GOO_ASSET_ID,
		"AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == EXPECTED_VERSION,
		"版本不是 %s：%s" % [EXPECTED_VERSION, snapshot.get("asset_version", "")])
	_expect(is_equal_approx(float(snapshot.get("lifetime", 0.0)), EXPECTED_LIFETIME),
		"寿命应为 %.2fs：%.3f" % [EXPECTED_LIFETIME, float(snapshot.get("lifetime", 0.0))])
	_expect(int(snapshot.get("node_count", 0)) >= EXPECTED_NODE_MIN,
		"子节点过少，三部分几何未构建：%d" % int(snapshot.get("node_count", 0)))
	_expect(int(snapshot.get("burst_count", 0)) == EXPECTED_BURST_COUNT,
		"爆炸粒子数应为 %d：%d" % [EXPECTED_BURST_COUNT, int(snapshot.get("burst_count", 0))])
	_expect(int(snapshot.get("splat_count", 0)) == EXPECTED_SPLAT_COUNT,
		"飞溅粒子数应为 %d：%d" % [EXPECTED_SPLAT_COUNT, int(snapshot.get("splat_count", 0))])
	_expect(int(snapshot.get("puddle_count", 0)) == EXPECTED_PUDDLE_COUNT,
		"地上液体数应为 %d：%d" % [EXPECTED_PUDDLE_COUNT, int(snapshot.get("puddle_count", 0))])
	# 业主明确「小僵尸死亡没有冲击波，只有胖子僵尸死亡有冲击波」⇒ 本件必须为 0
	_expect(int(snapshot.get("shockwave_count", -1)) == EXPECTED_SHOCKWAVE_COUNT,
		"小僵尸死亡不该有冲击波（期望 %d 层）：%d"
		% [EXPECTED_SHOCKWAVE_COUNT, int(snapshot.get("shockwave_count", -1))])
	_expect(snapshot.get("shockwave_color", Color.BLACK) == Color.BLACK or
		float(snapshot.get("shockwave_alpha", 0.0)) == 0.0,
		"未启用冲击波时不该有可见的环材质")

	# 三部分按名存在（避免「数量对上但名字换了、别处按名取件取不到」）
	for node_name in ["Burst0", "Burst11", "Splat0", "Splat13", "Puddle0", "Puddle3", "GooLight"]:
		_expect(fx.get_node_or_null(node_name) != null, "缺少节点：%s" % node_name)
	# 反向对照：冲击波那两个节点**必须不存在**（业主口径），存在即说明切换没生效
	for node_name in ["Shockwave0", "Shockwave2"]:
		_expect(fx.get_node_or_null(node_name) == null,
			"小僵尸死亡件里出现了 %s —— 冲击波只该出现在胖子僵尸那条" % node_name)

	# 业主指定「绿色」：解析出的颜色必须绿色主导
	_expect(bool(snapshot.get("green_dominant", false)),
		"爆开色不是绿色主导：%s" % str(snapshot.get("goo_color", Color.BLACK)))
	var goo := snapshot.get("goo_color", Color.BLACK) as Color
	_expect(goo.g > goo.r and goo.g > goo.b, "爆开色 G 通道未占优：%s" % str(goo))
	# 对照：调用方本色（小僵尸暗红）本身**不是**绿色主导 ⇒ 证明上面这条有辨别力
	var caller := Color(0.58, 0.19, 0.12)
	_expect(not (caller.g > caller.r and caller.g > caller.b),
		"对照失效：调用方本色本身就是绿色主导")

	fx.free()


# ---------------------------------------------------------------- A2 灯光真源
func _check_light_truth() -> void:
	var fx := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if fx == null:
		_failures.append("绿色方块爆开 Prefab 实例化失败（灯光用例）")
		return
	_samples += 1
	var snapshot: Dictionary = fx.call("get_presentation_snapshot")
	_expect(bool(snapshot.get("has_goo_light", false)), "缺少 OmniLight3D")
	_expect(String(snapshot.get("light_name", "")) == EXPECTED_LIGHT_NAME,
		"灯节点名不是 %s：%s" % [EXPECTED_LIGHT_NAME, snapshot.get("light_name", "")])
	_expect(not bool(snapshot.get("light_shadows", true)), "灯不应投射阴影")
	var range_per_size := float(snapshot.get("light_range", 0.0)) / SIZE_A
	_expect(absf(range_per_size - EXPECTED_LIGHT_RANGE_PER_SIZE) < 0.001,
		"灯范围应为 %.1f × size：实测每单位 %.3f"
		% [EXPECTED_LIGHT_RANGE_PER_SIZE, range_per_size])
	var birth := float(snapshot.get("light_energy", 0.0))
	_expect(absf(birth - EXPECTED_LIGHT_ENERGY_PEAK) < 0.001,
		"出生灯能量应为峰值 %.1f：%.3f" % [EXPECTED_LIGHT_ENERGY_PEAK, birth])
	var half := float(_snap(fx, EXPECTED_LIGHT_DECAY_SEC * 0.5).get("light_energy", 0.0))
	_expect(half < birth and half > 0.0,
		"灯能量未按包络衰减或半程就归零：%.3f -> %.3f" % [birth, half])
	var end := float(_snap(fx, EXPECTED_LIGHT_DECAY_SEC).get("light_energy", 0.0))
	_expect(is_zero_approx(end), "灯能量在 %.2fs 未归零：%.4f" % [EXPECTED_LIGHT_DECAY_SEC, end])
	# 「停留时必须真的静止」在**光照**这一面也要成立：灯必须早于公共停留窗口就熄灭
	_expect(EXPECTED_LIGHT_DECAY_SEC < PUDDLE_COMMON_HOLD_START,
		"灯熄灭时刻 %.2fs 落在液体公共停留窗口（起 %.3fs）之内 ⇒ 停留段地面亮度仍在变"
		% [EXPECTED_LIGHT_DECAY_SEC, PUDDLE_COMMON_HOLD_START])
	_expect(is_zero_approx(float(_snap(fx, PUDDLE_COMMON_HOLD_START).get("light_energy", 1.0))),
		"公共停留窗口开始时灯仍未熄灭 ⇒ 视觉上的「停留」被光照变化糊掉")
	fx.call("_on_lifetime_expired")
	var retired := float((fx.call("get_presentation_snapshot") as Dictionary).get("light_energy", 1.0))
	_expect(is_zero_approx(retired), "回收后灯能量必须归零（否则复借会长明）：%.4f" % retired)
	fx.free()


# ---------------------------------------------------------------- A3 爆炸粒子节奏
func _check_rhythm_burst() -> void:
	var fx := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if fx == null:
		_failures.append("爆炸粒子用例实例化失败")
		return
	_samples += 1
	# 「粒子不要太小」：出生尺度就得是可观的（基准 0.34m × size × size_ratio × 0.25）
	var start_scale := float(_snap(fx, 0.0).get("burst_scale_max_x", 0.0))
	_expect(start_scale > 0.08, "爆炸粒子出生尺度过小：%.4f" % start_scale)
	var peak_t: float = EXPECTED_BURST_WINDOW * EXPECTED_BURST_POP_RATIO
	var peak_scale := float(_snap(fx, peak_t).get("burst_scale_max_x", 0.0))
	var end_scale := float(_snap(fx, EXPECTED_BURST_WINDOW).get("burst_scale_max_x", 0.0))
	_expect(peak_scale > start_scale, "爆炸粒子未膨胀（%.4f -> %.4f）" % [start_scale, peak_scale])
	_expect(end_scale < peak_scale, "爆炸粒子未收缩（峰值 %.4f -> 末值 %.4f）" % [peak_scale, end_scale])
	var ratio := peak_scale / maxf(start_scale, 0.000001)
	_expect(absf(ratio - EXPECTED_BURST_SCALE_PEAK_RATIO) < 0.05,
		"爆炸粒子尺度变化倍率应 ≈ %.1f：实测 %.3f" % [EXPECTED_BURST_SCALE_PEAK_RATIO, ratio])
	# 窗口结束后必须真的收干净（否则会在天上挂一排绿方块）
	var tail := _snap(fx, EXPECTED_BURST_WINDOW * 0.999)
	var alpha_end := float(tail.get("burst_alpha", 1.0))
	_expect(alpha_end < 0.02, "爆炸粒子在窗口末端未淡出：alpha=%.4f" % alpha_end)
	# 「打击力度感」= 一帧内铺满视野：峰值尺度必须足够大（绝对量，不派生）
	_expect(peak_scale > 0.35, "峰值尺度太小，读不出炸开：%.4f" % peak_scale)

	# 出生就必须是**一圈数得出个数的方块壳**（真渲染实测：不散开时读作「一大块绿色」）
	var birth := _snap(fx, 0.0)
	var birth_radius_min := float(birth.get("burst_radius_min", 0.0))
	_expect(birth_radius_min > 0.15,
		"爆炸粒子出生挤在一起（最小半径 %.4f），读不出「方块爆开」" % birth_radius_min)
	# 并真的要向外炸：峰值时刻的最远半径必须明显大于出生时刻
	var birth_radius_max := float(birth.get("burst_radius_max", 0.0))
	var peak_radius_max := float(_snap(fx, peak_t).get("burst_radius_max", 0.0))
	_expect(peak_radius_max - birth_radius_max > 0.15,
		"爆炸粒子没有向外炸开：%.3f -> %.3f" % [birth_radius_max, peak_radius_max])
	# 对照：起点半径与终点半径也不能撞上（否则上面的差值可以靠别的项凑出来）
	var tail_radius_max := float(_snap(fx, EXPECTED_BURST_WINDOW).get("burst_radius_max", 0.0))
	_expect(tail_radius_max > peak_radius_max + 0.02,
		"对照失效：峰值与窗口末端的半径没拉开（%.3f vs %.3f）" % [peak_radius_max, tail_radius_max])
	fx.free()


# ---------------------------------------------------------------- A4 飞溅粒子节奏
func _check_rhythm_splat() -> void:
	var fx := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if fx == null:
		_failures.append("飞溅粒子用例实例化失败")
		return
	_samples += 1
	var floor_local := float((fx.call("get_presentation_snapshot") as Dictionary).get("floor_local_y", 0.0))
	_expect(absf(floor_local + SPAWN_LIFT) < 0.01,
		"floor_local_y 与脚底口径不一致：%.4f" % floor_local)
	# 起飞段：确有粒子被抛到胸口以上
	var up := _snap(fx, 0.06)
	var up_max := float(up.get("splat_pos_max_y", -99.0))
	_expect(up_max > 0.03, "飞溅粒子没有被抛起来（最高 y=%.4f）" % up_max)
	# 落地段：全部落到地面（本地 y ≈ floor_local + 半个液体厚度），且没有一个穿透地面
	var land_t := float((fx.call("get_presentation_snapshot") as Dictionary).get("splat_land_t_max", 1.0))
	_expect(land_t > 0.10 and land_t < 0.40,
		"飞溅粒子飞行时长应在 0.10~0.40s（节奏紧凑）：%.4f" % land_t)
	var down := _snap(fx, land_t + 0.01)
	var down_max := float(down.get("splat_pos_max_y", 99.0))
	var down_min := float(down.get("splat_pos_min_y", 99.0))
	var expect_rest := floor_local + EXPECTED_PUDDLE_LIFT * 0.5
	_expect(absf(down_max - expect_rest) < 0.02,
		"飞溅粒子未全部落地：最高 %.4f，期望 %.4f" % [down_max, expect_rest])
	_expect(down_min > floor_local - 0.02,
		"飞溅粒子穿透地面：最低 %.4f，地面 %.4f" % [down_min, floor_local])
	# 对照：起飞段与落地段的高度必须真的不同（否则上面两条可以同时假绿）
	_expect(up_max - down_max > 0.05,
		"对照失效：起飞与落地的高度差不多（%.4f vs %.4f）" % [up_max, down_max])
	fx.free()


# ---------------------------------------------------------------- A5 地上液体节奏
func _check_rhythm_puddle() -> void:
	var fx := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if fx == null:
		_failures.append("地上液体用例实例化失败")
		return
	_samples += 1
	# 出现前不可见
	_expect(is_zero_approx(float(_snap(fx, 0.20).get("puddle_alpha", 1.0))),
		"液体在出现时刻之前就已可见")
	# 停留段：scale / position / alpha 三者在整段内**逐位不动**（业主要求「停留 0.5 秒」）
	var hold_point := _snap(fx, 0.60)
	var hold_scale := float(hold_point.get("puddle_scale_x", 0.0))
	var hold_y := float(hold_point.get("puddle_pos_y", 0.0))
	var hold_alpha := float(hold_point.get("puddle_alpha", 0.0))
	_expect(is_equal_approx(hold_alpha, 1.0), "停留段液体不可见：alpha=%.4f" % hold_alpha)
	_expect(hold_scale > 0.10, "停留段液体扁平件尺度太小：%.4f" % hold_scale)
	var floor_local := float(hold_point.get("floor_local_y", 0.0))
	_expect(absf(hold_y - (floor_local + EXPECTED_PUDDLE_LIFT)) < 0.001,
		"液体未贴地：y=%.4f，期望 %.4f" % [hold_y, floor_local + EXPECTED_PUDDLE_LIFT])
	# 扫描测出停留窗口（行为测量，不读被测常量）
	var window := _measure_puddle_hold(fx, hold_scale, hold_y)
	var hold_len: float = window.y - window.x
	_expect(window.x > 0.0 and hold_len > 0.0, "未能测到停留窗口（扫描失效）")
	_expect(absf(hold_len - EXPECTED_PUDDLE_HOLD_SECONDS) <= 0.02,
		"停留时长应 ≈ %.2fs：实测 %.3fs（%.3f → %.3f）"
		% [EXPECTED_PUDDLE_HOLD_SECONDS, hold_len, window.x, window.y])
	_expect(is_equal_approx(float(hold_point.get("puddle_hold_seconds", 0.0)), EXPECTED_PUDDLE_HOLD_SECONDS),
		"puddle_hold_seconds 定档值不是 %.2fs" % EXPECTED_PUDDLE_HOLD_SECONDS)
	_expect(window.x > 0.30 and window.x < 0.42,
		"液体出现时刻应在飞溅落地之后（0.30~0.42s）：实测 %.3f" % window.x)

	# 下沉段：慢慢下沉并淡出，总深度 ≈ 0.30m
	var sink_end: float = window.y + EXPECTED_PUDDLE_SINK_SEC
	var mid := _snap(fx, window.y + EXPECTED_PUDDLE_SINK_SEC * 0.5)
	var mid_y := float(mid.get("puddle_pos_y", 0.0))
	var mid_alpha := float(mid.get("puddle_alpha", 1.0))
	_expect(mid_y < hold_y - 0.05, "液体没有下沉：%.4f -> %.4f" % [hold_y, mid_y])
	_expect(mid_alpha < 1.0 and mid_alpha > 0.0, "液体下沉期 alpha 不在淡出区间：%.4f" % mid_alpha)
	var deep := _snap(fx, sink_end - 0.01)
	var deep_y := float(deep.get("puddle_pos_y", 0.0))
	var depth: float = hold_y - deep_y
	_expect(absf(depth - EXPECTED_PUDDLE_SINK_DEPTH) < 0.02,
		"下沉深度应 ≈ %.2fm：实测 %.4f" % [EXPECTED_PUDDLE_SINK_DEPTH, depth])
	_expect(float(deep.get("puddle_alpha", 1.0)) < 0.06, "下沉到底时液体未淡净")
	_expect(is_zero_approx(float(_snap(fx, sink_end + 0.02).get("puddle_alpha", 1.0))),
		"停留 + 下沉结束后液体必须完全消失")
	# 对照：停留段与下沉段的 y 必须不同（证明「下沉」这条不是恒真）
	_expect(mid_y < hold_y - 0.05, "对照失效：停留段与下沉段的 y 一致")

	# 液体落在飞溅粒子的**真实落点**上（不是另立一份散布口径）
	var landed := _snap(fx, 1.0)
	var splat_positions: Array = landed.get("splat_land_positions", [])
	var puddle_positions: Array = landed.get("puddle_positions", [])
	_expect(splat_positions.size() == EXPECTED_SPLAT_COUNT,
		"飞溅落点数组长度不对：%d" % splat_positions.size())
	_expect(puddle_positions.size() == EXPECTED_PUDDLE_COUNT,
		"液体位置数组长度不对：%d" % puddle_positions.size())
	if splat_positions.size() > 1 and not puddle_positions.is_empty():
		var source := splat_positions[1] as Vector3
		var plate := puddle_positions[0] as Vector3
		_expect(
			absf(source.x - plate.x) < 0.001 and absf(source.z - plate.z) < 0.001,
			"液体未落在飞溅粒子落点上：落点(%.3f,%.3f) vs 液体(%.3f,%.3f)"
			% [source.x, source.z, plate.x, plate.z]
		)
		# 对照：不同来源的飞溅粒子落点彼此不同 ⇒ 上一条不是「都在原点」的巧合
		var other := splat_positions[4] as Vector3
		_expect(
			Vector2(source.x - other.x, source.z - other.z).length() > 0.20,
			"对照失效：不同飞溅落点几乎重合（%.3f m）"
			% Vector2(source.x - other.x, source.z - other.z).length()
		)
	fx.free()


## 扫描出「alpha=1 且 scale / y 完全冻结」的连续窗口（行为测量）。
func _measure_puddle_hold(fx: VfxEffectBase3D, side: float, hold_y: float) -> Vector2:
	var first := -1.0
	var last := -1.0
	var t := 0.30
	while t <= 1.34:
		fx.call("_on_tick", t, EXPECTED_LIFETIME)
		var snapshot: Dictionary = fx.call("get_presentation_snapshot")
		var scale_x := float(snapshot.get("puddle_scale_x", 0.0))
		var pos_y := float(snapshot.get("puddle_pos_y", 0.0))
		var alpha := float(snapshot.get("puddle_alpha", 0.0))
		if (
			absf(scale_x - side) < 1e-6
			and absf(pos_y - hold_y) < 1e-6
			and absf(alpha - 1.0) < 1e-6
		):
			if first < 0.0:
				first = t
			last = t
		t += 0.005
	return Vector2(first, last)


# ---------------------------------------------------------------- A6 地面平铺
func _check_ground_flatness() -> void:
	var fx := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if fx == null:
		_failures.append("地面平铺用例实例化失败")
		return
	_samples += 1
	_snap(fx, 0.60)
	var flat_dot := float((fx.call("get_presentation_snapshot") as Dictionary).get("ground_plane_dot_min", -1.0))
	_expect(flat_dot > 0.999, "地上液体未平铺（与世界 UP 的最小点积 %.4f）" % flat_dot)
	# 对照：故意把根节点倾斜 90°，同一判据必须塌掉
	var tilted := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if tilted == null:
		_failures.append("地面平铺对照用例实例化失败")
		fx.free()
		return
	_samples += 1
	tilted.rotation.x = PI * 0.5
	_snap(tilted, 0.60)
	var tilted_dot := float((tilted.call("get_presentation_snapshot") as Dictionary).get("ground_plane_dot_min", 1.0))
	_expect(tilted_dot < 0.5, "对照失效：倾斜 90° 后平铺判据仍成立（dot=%.4f）" % tilted_dot)
	tilted.free()
	fx.free()


# ---------------------------------------------------------------- A7 floor_y 契约
func _check_floor_contract() -> void:
	# A：显式给真实地面（深层楼）⇒ 液体落在该层地面上，绝不在世界原点附近
	var explicit := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if explicit == null:
		_failures.append("floor_y 用例实例化失败")
		return
	_samples += 1
	var world_a := float(_snap(explicit, 0.60).get("puddle_pos_y", 0.0)) + explicit.global_position.y
	_expect(absf(world_a - (FLOOR_DEEP + EXPECTED_PUDDLE_LIFT)) < 0.01,
		"液体未落在 context.floor_y 那一层：%.3f vs %.3f" % [world_a, FLOOR_DEEP + EXPECTED_PUDDLE_LIFT])
	_expect(absf(world_a) > 100.0, "液体落在世界原点附近（%.3f），用例没真正测到深层楼" % world_a)
	explicit.free()

	# B：不给 floor_y ⇒ 按调用方「胸口 = 脚底 + 0.65」口径反推，结果必须与 A 一致
	var fallback := _make_manual(FLOOR_DEEP + SPAWN_LIFT, null, SIZE_A)
	if fallback == null:
		_failures.append("floor_y 缺省用例实例化失败")
		return
	_samples += 1
	var world_b := float(_snap(fallback, 0.60).get("puddle_pos_y", 0.0)) + fallback.global_position.y
	_expect(absf(world_b - world_a) < 0.01,
		"缺省 floor_y 的反推口径与显式传入不一致：%.3f vs %.3f" % [world_b, world_a])
	# 对照：缺省路径**不是**以 0 兜底（若兜底成 0，地面件会落到原点附近）
	_expect(absf(world_b - FLOOR_DEEP) < 0.05,
		"缺省 floor_y 兜底错了：%.3f 应贴 %.3f" % [world_b, FLOOR_DEEP])
	fallback.free()

	# C：故意把 floor_y 下移 0.30m（不触发最低起抛高度钳制）⇒ 液体必须**精确**跟着下移
	#    （证明 floor_y 真的被消费，不是写死的常量）
	var shifted := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP + FLOOR_SHIFT, SIZE_A)
	if shifted == null:
		_failures.append("floor_y 反向对照实例化失败")
		return
	_samples += 1
	var world_c := float(_snap(shifted, 0.60).get("puddle_pos_y", 0.0)) + shifted.global_position.y
	_expect(absf(world_c - world_a - FLOOR_SHIFT) < 0.01,
		"对照失效：floor_y 移动 %.2fm 后液体只移动了 %.3f m" % [FLOOR_SHIFT, world_c - world_a])
	shifted.free()


# ---------------------------------------------------------------- A8 尺寸线性
func _check_size_linearity() -> void:
	var a := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	var b := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_B)
	if a == null or b == null:
		_failures.append("尺寸用例实例化失败")
		return
	_samples += 1
	var snap_a := _snap(a, 0.60)
	var snap_b := _snap(b, 0.60)
	var burst_a := float(snap_a.get("burst_scale_x", 0.0))
	var burst_b := float(snap_b.get("burst_scale_x", 0.0))
	var puddle_a := float(snap_a.get("puddle_scale_x", 0.0))
	var puddle_b := float(snap_b.get("puddle_scale_x", 0.0))
	var range_a := float(snap_a.get("light_range", 0.0))
	var range_b := float(snap_b.get("light_range", 0.0))
	a.free()
	b.free()
	if burst_b <= 0.0 or puddle_b <= 0.0 or range_a <= 0.0:
		_failures.append("尺寸用例：未测到可比的尺度量")
		return
	_expect(absf(burst_a / burst_b - SIZE_RATIO) <= SIZE_RATIO_TOLERANCE,
		"爆炸粒子未随 size 线性（比值 %.4f，期望 %.3f）" % [burst_a / burst_b, SIZE_RATIO])
	_expect(absf(puddle_a / puddle_b - SIZE_RATIO) <= SIZE_RATIO_TOLERANCE,
		"地上液体未随 size 线性（比值 %.4f，期望 %.3f）" % [puddle_a / puddle_b, SIZE_RATIO])
	_expect(absf(range_b / range_a - SIZE_B) <= 0.01,
		"灯范围未随 size 线性（比值 %.4f，期望 %.2f）" % [range_b / range_a, SIZE_B])


# ---------------------------------------------------------------- A9 无碰撞体
func _check_collision_free() -> void:
	var effect := GOO_SCENE.instantiate()
	var collisions := _count_collision_nodes(effect)
	_expect(collisions == 0, "Prefab 内出现碰撞体 %d 个（特效必须纯视觉）" % collisions)
	effect.free()
	_samples += 1


# ---------------------------------------------------------------- B1 端到端接线
func _enemy_death_case_begin() -> void:
	if ENEMY_SCENE == null:
		_failures.append("敌人场景未加载，端到端接线用例未执行")
		return
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("敌人生成场景根节点不是 Enemy3D，端到端接线用例未执行")
		return
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(7.0, FLOOR_DEEP, -5.0)
	enemy.configure_from_enemy_data({"enemy_type": "melee_chaser", "name": "小僵尸"})
	enemy.room_id = "room_goo_probe"
	_expect(enemy.uses_goo_death_burst(), "小僵尸未被识别为「绿色方块爆开」怪种")
	# 先量出「倒地段」本来有多长：回收再快，也只有在这段确实存在时才说明问题
	var fall_duration := 0.0
	if enemy.avatar != null and enemy.avatar.has_formal_normal():
		fall_duration = enemy.avatar.get_formal_death_duration()
	_expect(fall_duration > 2.0,
		"对照失效：小僵尸的「dead」倒地段本就该 > 2s（实测 %.2f），否则「立即回收」证明不了什么"
		% fall_duration)
	var pool := _pool()
	if pool == null:
		_failures.append("VfxPool 缺失，端到端接线用例未执行")
		enemy.free()
		return
	var before := pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)
	_killed_count = 0
	enemy.killed.connect(_on_goo_enemy_killed)
	enemy.take_damage(999999)
	_samples += 1
	_goo_enemy = enemy

	# 同帧断言①：不得进入死亡显影组（那条路是「管尸体显隐」的，本表现没有尸体）
	_expect(not enemy.is_in_group("enemy_death_visual_3d"),
		"goo 死亡不应进入死亡显影组（本表现没有尸体）")
	# 同帧断言②：**模型本帧就收起**。
	# 倒地动画要求先把一具躯干留在场上播 2.4s（见上面的 fall_duration），做不到「同帧收起」。
	if enemy.avatar != null and enemy.avatar.has_formal_normal():
		_expect(not enemy.avatar.visible, "死亡同帧模型未收起（仍在走倒地表现）")
	else:
		_failures.append("端到端用例：小僵尸未挂载正式普通怪表现，倒地契约测不到")

	# 同帧断言③：特效真的经池借出，且**不跟随任何挂点**（全向世界锚定）
	var after := pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)
	_expect(after == before + 1, "死亡未借出绿色方块爆开特效（%d -> %d）" % [before, after])
	var bucket: Array = pool._active.get(VfxPool3D.FX01_ZOMBIE_GOO_DEATH, [])
	if bucket.is_empty():
		_failures.append("特效桶为空，无法继续端到端断言")
		return
	var fx := bucket.back() as VfxEffectBase3D
	if fx == null:
		_failures.append("借出的特效类型不对")
		return
	_expect(not fx.has_follow_target(), "死亡特效不应跟随挂点（爆发没有朝向/宿主）")
	_expect(absf(fx.global_position.y - (FLOOR_DEEP + SPAWN_LIFT)) < 0.001,
		"特效出生点未落在胸口（脚底 + %.2f）：%.4f" % [SPAWN_LIFT, fx.global_position.y])
	_expect(absf(fx.global_position.y) > 100.0,
		"特效位置落在世界原点附近，用例可能没真正测到深层楼")
	var fx_snapshot: Dictionary = fx.call("get_presentation_snapshot")
	_expect(String(fx_snapshot.get("asset_id", "")) == GOO_ASSET_ID,
		"借出的不是 FX01-19：%s" % fx_snapshot.get("asset_id", ""))
	# floor_y 必须按「脚底行走面」传入（本地地面偏移 = −0.65）
	_expect(absf(float(fx_snapshot.get("floor_local_y", 0.0)) + SPAWN_LIFT) < 0.01,
		"floor_y 未按脚底口径传入：floor_local_y=%.4f" % float(fx_snapshot.get("floor_local_y", 0.0)))


func _on_goo_enemy_killed(_enemy: Enemy3D, _data: Dictionary) -> void:
	_killed_count += 1


func _enemy_death_case_check_recycled() -> void:
	_expect(not is_instance_valid(_goo_enemy),
		"绿色方块爆开死亡未立即回收 —— 仍在原地播倒地动画 / 留尸体")
	_expect(_killed_count == 1, "死亡结算次数不是 1：%d" % _killed_count)
	_expect(get_tree().get_nodes_in_group("enemy_death_visual_3d").is_empty(),
		"死亡显影组残留：goo 死亡不该有尸体进组")
	var pool := _pool()
	if pool != null:
		pool.clear_kind(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)


# ---------------------------------------------------------------- B2 反向对照
## 反向对照：改动是**旁路**，不是把「倒地 + 尸体」整条链删掉。
##
## 为什么这里只能用源码级钉子：业主第二轮把**胖子僵尸也**加进了「去掉倒地动画」名单
## （`Enemy3D.ZOMBIE_KINDS`），而本仓挂了 `has_formal_normal()`（有倒地段）的怪种
## —— `fat_zombie03` / `melee_chaser` / `ranged_caster` —— **正好就是僵尸三兄弟**，
## 于是已经不存在「有倒地动画」的怪种可以做行为对照（原来那条「胖子僵尸仍留尸体」
## 的对照随本轮需求一起作废）。
## ⇒ 改成钉住「那条链仍然在源码里、且分支按 no-corpse 收敛」：
##    若有人图省事把 `tween_interval(get_formal_death_duration())` 整段删掉，这条会变红。
func _fat_zombie_reverse_begin() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("反向对照：胖僵尸实例化失败")
		return
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(-9.0, FLOOR_DEEP, 8.0)
	enemy.configure_from_enemy_data({"enemy_type": "fat_zombie03", "name": "胖子僵尸"})
	_expect(not enemy.uses_goo_death_burst(), "对照失效：胖子僵尸被识别成 FX01-19 怪种")
	_expect(enemy.uses_no_corpse_death(), "胖子僵尸应在「无尸体」名单里（本轮新加）")
	enemy.take_damage(999999)
	_fat_enemy = enemy
	_samples += 1
	_expect(not enemy.is_in_group("enemy_death_visual_3d"),
		"胖子僵尸不应进入死亡显影组（本表现没有尸体）")


func _fat_zombie_reverse_check() -> void:
	_expect(not is_instance_valid(_fat_enemy), "胖子僵尸未立即回收（倒地动画没去掉）")
	# 源码级对照：倒地那条链必须仍在（旁路，不是删除）
	var source := FileAccess.get_file_as_string("res://src/enemy3d/Enemy3D.gd")
	_expect(not source.is_empty(), "读不到 Enemy3D.gd，源码级对照未执行")
	_expect(source.contains("tween_interval(avatar.get_formal_death_duration())"),
		"对照失效：「倒地 + 尸体」那条链被整条删掉了（应当只对 ZOMBIE_KINDS 旁路）")
	_expect(source.contains("uses_no_corpse_death"),
		"对照失效：死亡分支没有按 uses_no_corpse_death() 收敛")


# ---------------------------------------------------------------- D 共享基类的开关（业主口径）
## 两件事必须**同时**成立，缺一即说明「共用身体 + 子类开关」这套结构没搭对：
##   ① 小僵尸这条（FX01-19）**没有**冲击波；
##   ② 胖子僵尸那条（FX01-17）**有** 3 层冲击波，且真的从很小扫到很大、到点收干净。
## 只验 ①会漏掉「开关永远关着」；只验 ②会漏掉「开关永远开着」。两侧一起钉才闭合。
## 冲击波自身的节奏细节在 `verify_death_blast_vfx` 里逐帧验，这里只验开关的**两侧**。
func _check_shockwave_rhythm() -> void:
	# ① 小僵尸这条：没有
	var plain := _make_manual(FLOOR_DEEP + SPAWN_LIFT, FLOOR_DEEP, SIZE_A)
	if plain == null:
		_failures.append("开关用例：FX01-19 实例化失败")
		return
	_samples += 1
	_expect(int((plain.call("get_presentation_snapshot") as Dictionary).get("shockwave_count", -1)) == 0,
		"FX01-19（小僵尸死亡）不该有冲击波")
	plain.free()

	# ② 胖子僵尸这条：有 3 层，且能扫、能收
	var fat_prefab := load("res://assets/art/vfx/combat_3d/vfx_death_blast_root_top3d.tscn") as PackedScene
	if fat_prefab == null:
		_failures.append("开关用例：FX01-17 场景未加载")
		return
	var fat := fat_prefab.instantiate() as VfxEffectBase3D
	if fat == null:
		_failures.append("开关用例：FX01-17 实例化失败")
		return
	add_child(fat)
	fat.set_process(false)
	fat.activate(Vector3(2.0, FLOOR_DEEP + SPAWN_LIFT, 1.0), Color(0.38, 0.43, 0.26), SIZE_A, {"floor_y": FLOOR_DEEP})
	_samples += 1
	var fat_total := float((fat.call("get_presentation_snapshot") as Dictionary).get("lifetime", 1.35))
	_expect(int((fat.call("get_presentation_snapshot") as Dictionary).get("shockwave_count", 0)) == 3,
		"FX01-17（胖子僵尸死亡）应有 3 层冲击波：%d"
		% int((fat.call("get_presentation_snapshot") as Dictionary).get("shockwave_count", 0)))

	# 单环 scale 从最小到最大（不能拿「三层取最大」当起始值：相位错开，t=0 就已很大）
	var ring0_min := INF
	var ring0_max := 0.0
	var alpha_peak := 0.0
	var probe := 0.0
	while probe <= 0.70:
		fat.call("_on_tick", probe, fat_total)
		var snapshot: Dictionary = fat.call("get_presentation_snapshot")
		ring0_min = minf(ring0_min, float(snapshot.get("shockwave0_scale_x", 0.0)))
		ring0_max = maxf(ring0_max, float(snapshot.get("shockwave0_scale_x", 0.0)))
		alpha_peak = maxf(alpha_peak, float(snapshot.get("shockwave_alpha", 0.0)))
		probe += 0.005
	_expect(ring0_min > 0.0 and ring0_max > ring0_min * 3.0,
		"FX01-17 冲击波没有向外扫（单环 scale %.3f → %.3f）" % [ring0_min, ring0_max])
	_expect(alpha_peak > 0.3, "FX01-17 冲击波几乎不可见（峰值 alpha %.3f）" % alpha_peak)
	fat.call("_on_tick", 0.66, fat_total)
	_expect(float((fat.call("get_presentation_snapshot") as Dictionary).get("shockwave_alpha", 1.0)) < 0.05,
		"FX01-17 冲击波在 0.66s 未淡净（相位是循环的，必须有时间窗）")
	# 平铺
	_expect(float((fat.call("get_presentation_snapshot") as Dictionary).get("ground_plane_dot_min", -1.0)) > 0.999,
		"FX01-17 冲击波未平铺在世界 UP 上")
	fat.free()


func _report() -> void:
	if _samples < MIN_SAMPLES:
		_failures.append("防假绿哨兵：实际样本数 %d 少于预期 %d，验收未真正执行" % [_samples, MIN_SAMPLES])
	if _failures.is_empty():
		print("ZOMBIE_GOO_DEATH_VFX_OK: fx01-19 goo death pass (samples=%d)" % _samples)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
