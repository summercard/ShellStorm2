extends Node
## 专项验收：命中特效分流（业主 2026-10-14「对击中特效进行区分」）
##
## 业主口径（历轮原话）：
##   · 第一轮：「使用爆炸粒子 ×12 的这个特效，作为一个独立特效，作为打中小僵尸，警察僵尸，
##     胖子僵尸的受到枪击的特效，原来那个特效缩小 60%，作为击中其它物体的特效」；
##     追问「缩小 60% 的读数」与「近战是否复用」时，业主把后者改为：
##     「**重新制作一个**，通过一个打击到金属的粒子反馈的特效，用白色方块粒子和 2 根长条的
##      金色火星一样飞溅去替代，这个不要用太多粒子，**4-5 颗 + 2 根金色火星**即可」；
##     近战：**枪击 + 近战都用**；
##   · 第四轮（本版）：「**小僵尸和警察僵尸的受击特效太大了**，**使用击中其它物体的那个特效**，
##     然后**改成绿色**即可，放大大概 **10%**」；同轮「受击的盒子**没有贴着模型**，
##     碰撞盒里陷进去坐标大概 **0.2 米**」。
##
## ⇒ 最终落到两件资产：
##   · FX01-20 `VFX-GOO-HIT-3D` **v002**：5 颗绿方块 + 2 根绿色长条火星 —— 打中「僵尸三兄弟」；
##     造型与 FX01-21 **逐字共用**（父类 `VfxMetalSparkHit3D`），只换色板；
##     尺寸 = 金属火星同档位 ×1.10（由调用方给，见下）。
##   · FX01-21 `VFX-METAL-SPARK-HIT-3D` v001：5 颗白方块 + 2 根金色长条火星 —— 打中其余一切。
##
## 四条纪律（都按「反向对照」验，不只验正面）：
##   ① **分流唯一**：同一只怪「枪击」与「近战」必须走到同一件特效（判据共用
##      `Enemy3D.uses_goo_hit_burst()`），不允许出现「被枪打是一种、被刀砍是另一种」。
##   ② **两件都无灯**：它们是**每一发子弹 / 每一次近战**都要生成的高频件，
##      带灯会把同屏灯数拉起来。这条要**正面钉住**，否则以后有人「顺手加个灯」不会被发现。
##   ③ **同形**：FX01-20 与 FX01-21 在**同一 size** 下几何逐项相等（这就是业主说的
##      「使用击中其它物体的那个特效」）；差异只允许出现在颜色与资产身份上。
##      「放大 10%」由调用方按档位给 ⇒ 另有一条静态门禁盯着调用点真的乘了 1.10。
##   ④ **贴肉**：命中点必须先过 `Enemy3D.hit_effect_anchor()` 收进模型 0.2m
##      （否则弹体是在碰撞壳表面判命中的，特效会悬在怪旁边）。
## 期望值一律硬编码在验收侧（不引用被测脚本常量，防自印证）；末尾有防假绿哨兵。

const GOO_HIT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_goo_hit_root_top3d.tscn")
const METAL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_metal_spark_hit_root_top3d.tscn")
const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

const GOO_HIT_ID := "VFX-GOO-HIT-3D"
const METAL_ID := "VFX-METAL-SPARK-HIT-3D"
## 两件各自的身份：FX01-20 在第四轮换了造型语言 ⇒ 升 v002；FX01-21 未动过
const EXPECTED_GOO_HIT_VERSION := "v002"
const EXPECTED_METAL_VERSION := "v001"

## 期望值硬编码（不引用被测常量）
## FX01-20 v002 是 FX01-21 的**同形件**（只换色板）⇒ 件数与寿命与金属那件**完全一致**；
## 差异只允许是「颜色」与「调用方按档位给的尺寸 ×1.10」。
const EXPECTED_GOO_HIT_LIFETIME := 0.32
const EXPECTED_GOO_HIT_CUBES := 5
const EXPECTED_GOO_HIT_STREAKS := 2
const EXPECTED_METAL_LIFETIME := 0.32
const EXPECTED_METAL_CUBES := 5
const EXPECTED_METAL_STREAKS := 2
## 长条火星必须**落在切平面内**：世界方向与法线的点积要小
const EXPECTED_STREAK_NORMAL_DOT_MAX := 0.20
## 长条确实在「拉长」：末端长度 / 起点长度
const EXPECTED_STREAK_STRETCH_MIN := 1.5
## 僵尸受击件比金属火星大多少（业主「放大大概 10%」）—— 静态门禁按这个数钉住调用点
const EXPECTED_ZOMBIE_SIZE_RATIO := 1.10
## 贴肉判据的容差（米）：落点允许距模型盒面这么远（含 0.03 咬入 + 浮点余量）
const EXPECTED_HIT_INSET_BITE_TOLERANCE := 0.05
## **双向**判据的另一侧：贴肉**不许把落点推得比原来更深**。
##
## ⚠ 只判「在盒内」是**单向**的 —— 把包围盒算大、或把退让量调大，落点会埋得更深，
## 反而更容易判过（实测：故意让包围盒虚胖 2.6 倍，单向判据照样全绿）。
##
## 另一侧的正确不变式不是「绝对深度 < 某值」（那个值对三只怪各不相同、且没法解释），
## 而是：**新落点的埋深 ≤ 原始壳面命中点的埋深 + 咬入量**。
## 因为壳面本来就可能已经在模型里（胖子僵尸 X 向：壳半径 0.770 < 模型半宽 1.839），
## 那时**本来就不该再往里推**；这条不变式同时钉住「不许埋更深」与「该收时必须收」。
## 实测：用旧的「先 max(0.20) 再 min」写法，胖子僵尸 X 向会被推深到 0.712+0.20=0.912 ⇒ 本条变红。

## 僵尸三兄弟（含胖子僵尸）；以及一个**反例**怪种（召唤者，不属于三兄弟）
const ZOMBIE_KINDS: Array[String] = ["melee_chaser", "ranged_caster", "fat_zombie03"]
const NON_ZOMBIE_KIND := "summoner"

## 实际会跑出 27 个样本（含循环展开）。留一点余量：真有整段用例没执行时必然跌破这里。
const MIN_SAMPLES := 25

var _failures: Array[String] = []
var _samples := 0
var _steps: Array[Callable] = []
var _step_index := 0
var _zombie_enemy: Enemy3D = null
var _fat_enemy: Enemy3D = null


func _ready() -> void:
	# ⚠ 分步执行：本仓 GDScript 的运行期报错会**中断当前函数**；全串在 `_ready` 里时
	# 中途一处报错会跳过 `_report()` ⇒ headless 场景永远挂着（本仓验收的经典假死）。
	_steps = [
		_check_pool_registration,
		_check_goo_hit_contract,
		_check_goo_hit_green_twin,
		_check_enemy_hit_anchor,
		_check_goo_hit_determinism,
		_check_metal_contract,
		_check_metal_normal_frame,
		_check_metal_streak_tangent,
		_check_both_light_free,
		_check_collision_free,
		_check_routing_predicate,
		_check_projectile_routing,
		_check_melee_routing,
		_check_size_linearity,
		_enemy_death_case_begin,
		_tick_wait,
		_tick_wait,
		_enemy_death_case_check,
	]
	_step_index = 0
	set_process(true)


func _process(_delta: float) -> void:
	if _step_index < _steps.size():
		var step: Callable = _steps[_step_index]
		_step_index += 1
		print("HIT_ROUTING_VFX_STEP %d/%d %s" % [_step_index, _steps.size(), step.get_method()])
		step.call()
		return
	set_process(false)
	_report()


func _tick_wait() -> void:
	pass


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _pool() -> VfxPool3D:
	var pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not pools.is_empty():
		return pools[0] as VfxPool3D
	return null


func _count_collision_nodes(node: Node) -> int:
	var total := 0
	if node is CollisionObject3D or node is CollisionShape3D:
		total += 1
	for child in node.get_children():
		total += _count_collision_nodes(child)
	return total


## 造一个手动步进的实例（关掉基类 `_process`，只由用例显式调 `_on_tick`）。
func _make_manual(scene: PackedScene, normal: Variant = null, size: float = 1.0) -> VfxEffectBase3D:
	var fx := scene.instantiate() as VfxEffectBase3D
	if fx == null:
		return null
	add_child(fx)
	fx.set_process(false)
	var context: Dictionary = {}
	if normal != null:
		context["normal"] = normal
	fx.activate(Vector3(3.0, 1.0, -2.0), Color(0.58, 0.19, 0.12), size, context)
	return fx


func _snap(fx: VfxEffectBase3D, elapsed: float, total: float) -> Dictionary:
	fx.call("_on_tick", elapsed, total)
	return fx.call("get_presentation_snapshot") as Dictionary


# ---------------------------------------------------------------- 池注册
func _check_pool_registration() -> void:
	var pool := _pool()
	if pool == null:
		_failures.append("VfxPool 缺失，命中特效分流用例未执行")
		return
	_samples += 1
	_expect(VfxPool3D.has_effect(VfxPool3D.FX01_GOO_HIT), "池未注册 FX01-20 VFX-GOO-HIT-3D")
	_expect(VfxPool3D.has_effect(VfxPool3D.FX01_METAL_SPARK_HIT), "池未注册 FX01-21 VFX-METAL-SPARK-HIT-3D")
	_expect(VfxPool3D.FX01_GOO_HIT == GOO_HIT_ID,
		"FX01_GOO_HIT 常量不是 %s：%s" % [GOO_HIT_ID, VfxPool3D.FX01_GOO_HIT])
	_expect(VfxPool3D.FX01_METAL_SPARK_HIT == METAL_ID,
		"FX01_METAL_SPARK_HIT 常量不是 %s：%s" % [METAL_ID, VfxPool3D.FX01_METAL_SPARK_HIT])


# ---------------------------------------------------------------- A1 FX01-20 契约（v002）
func _check_goo_hit_contract() -> void:
	var fx := _make_manual(GOO_HIT_SCENE, Vector3.UP)
	if fx == null:
		_failures.append("FX01-20 Prefab 根节点不是 VfxEffectBase3D")
		return
	_samples += 1
	var snapshot: Dictionary = fx.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == GOO_HIT_ID,
		"AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == EXPECTED_GOO_HIT_VERSION,
		"版本不是 %s：%s" % [EXPECTED_GOO_HIT_VERSION, snapshot.get("asset_version", "")])
	_expect(is_equal_approx(float(snapshot.get("lifetime", 0.0)), EXPECTED_GOO_HIT_LIFETIME),
		"寿命应为 %.2fs：%.3f" % [EXPECTED_GOO_HIT_LIFETIME, float(snapshot.get("lifetime", 0.0))])
	# 业主「使用击中其它物体的那个特效」⇒ 件数必须与 FX01-21 一致（5 + 2），不再是 12 枚方块
	_expect(int(snapshot.get("cube_count", 0)) == EXPECTED_GOO_HIT_CUBES,
		"方块数应为 %d（与 FX01-21 同形）：%d"
		% [EXPECTED_GOO_HIT_CUBES, int(snapshot.get("cube_count", 0))])
	_expect(int(snapshot.get("streak_count", 0)) == EXPECTED_GOO_HIT_STREAKS,
		"长条火星数应为 %d（与 FX01-21 同形）：%d"
		% [EXPECTED_GOO_HIT_STREAKS, int(snapshot.get("streak_count", 0))])
	for node_name in ["Cube0", "Cube4", "Streak0", "Streak1"]:
		_expect(fx.get_node_or_null(node_name) != null, "缺少节点：%s" % node_name)
	# 业主「改成绿色即可」⇒ **方块与长条两侧**都得绿主导
	# （只改一侧会读成「金火星 + 绿方块」，那就不是「改成绿色」了）
	_expect(_is_green_dominant(snapshot.get("cube_color", Color.BLACK)),
		"方块不是绿色主导：%s" % str(snapshot.get("cube_color", Color.BLACK)))
	_expect(_is_green_dominant(snapshot.get("streak_color", Color.BLACK)),
		"长条火星不是绿色主导：%s" % str(snapshot.get("streak_color", Color.BLACK)))
	# ⚠ 高频件**刻意无灯**：正面钉住，防止以后「顺手加个灯」
	_expect(not bool(snapshot.get("has_light", true)), "FX01-20 不该带灯（高频件，见脚本头）")
	# v002 起与 FX01-21 同形 ⇒ 同样消费 context.normal（贴合被击面）
	_expect(bool(snapshot.get("consumes_normal", false)), "FX01-20 v002 必须消费 context.normal")
	fx.free()


## 「绿色主导」判据：直接看颜色通道，**不依赖**被测脚本自己报的 `green_dominant` 字段
## （那个字段是可以被随手写死成 true 的，用它做断言等于自印证）。
func _is_green_dominant(color: Variant) -> bool:
	var value := color as Color
	return value.g > value.r and value.g > value.b


# ---------------------------------------------------------------- A2 FX01-20 ≡ FX01-21（同形）
## 业主「**使用击中其它物体的那个特效**，然后改成绿色即可」⇒ 两件在**同一 size** 下几何必须
## 逐项相等：件数、方块尺度过冲、方块外推量、长条长度、节点总数。差异只允许是颜色与资产身份。
## ⚠ 这条是**双向**的：既钉「僵尸那件没被换成别的造型」，也钉「打其它物体的那件没被顺手改小」——
## 只比一边的话，两件一起漂移（例如都缩 20%）不会被发现。
func _check_goo_hit_green_twin() -> void:
	var green := _make_manual(GOO_HIT_SCENE, Vector3.UP, 1.0)
	var metal := _make_manual(METAL_SCENE, Vector3.UP, 1.0)
	if green == null or metal == null:
		_failures.append("同形对照用例实例化失败")
		return
	_samples += 1
	var probe := EXPECTED_GOO_HIT_LIFETIME * 0.6
	var g := _snap(green, probe, EXPECTED_GOO_HIT_LIFETIME)
	var m := _snap(metal, probe, EXPECTED_METAL_LIFETIME)
	for key in ["cube_count", "streak_count", "node_count"]:
		_expect(int(g.get(key, -1)) == int(m.get(key, -2)),
			"同形对照失败：%s 不一致（僵尸件 %s / 金属件 %s）"
			% [key, str(g.get(key)), str(m.get(key))])
	for key in ["cube_scale_max_x", "streak_length_max", "cube_pos_max_y"]:
		_expect(absf(float(g.get(key, -1.0)) - float(m.get(key, -2.0))) < 0.0001,
			"同形对照失败：同一 size 下 %s 不相等（僵尸件 %.5f / 金属件 %.5f）"
			% [key, float(g.get(key, -1.0)), float(m.get(key, -2.0))])
	# 反向对照：颜色**必须不同**（否则「同形」也可能是因为两件根本是同一套色）
	_expect(not _same_color(g.get("cube_color", Color.BLACK), m.get("cube_color", Color.WHITE)),
		"僵尸件与金属件的方块颜色相同 ⇒「改成绿色」没生效")
	_expect(not _same_color(g.get("streak_color", Color.BLACK), m.get("streak_color", Color.WHITE)),
		"僵尸件与金属件的长条颜色相同 ⇒「改成绿色」没生效")
	# 长条确实在「拉长」（业主说的「2 根长条的火星」——短粗一截读不出「长条」）
	var birth_streak := float(_snap(green, 0.0, EXPECTED_GOO_HIT_LIFETIME).get("streak_length_max", 0.0))
	var end_streak := float(_snap(green, probe, EXPECTED_GOO_HIT_LIFETIME).get("streak_length_max", 0.0))
	_expect(end_streak > birth_streak * EXPECTED_STREAK_STRETCH_MIN,
		"僵尸受击件的长条没在拉长（%.3f → %.3f）" % [birth_streak, end_streak])
	green.free()
	metal.free()


func _same_color(a: Variant, b: Variant) -> bool:
	var left := a as Color
	var right := b as Color
	return (
		is_equal_approx(left.r, right.r)
		and is_equal_approx(left.g, right.g)
		and is_equal_approx(left.b, right.b)
	)


# ---------------------------------------------------------------- A3 FX01-20 确定性
## 脚本内不得有 `randf()`：同一 elapsed 两次求值必须逐位相同（池化复借才不会漂）。
func _check_goo_hit_determinism() -> void:
	var fx := _make_manual(GOO_HIT_SCENE, null, 1.0)
	if fx == null:
		_failures.append("FX01-20 确定性用例实例化失败")
		return
	_samples += 1
	var first := _snap(fx, 0.11, EXPECTED_GOO_HIT_LIFETIME)
	var second := _snap(fx, 0.11, EXPECTED_GOO_HIT_LIFETIME)
	_expect(
		is_equal_approx(
			float(first.get("cube_pos_max_y", 0.0)), float(second.get("cube_pos_max_y", 0.0))
		)
		and is_equal_approx(
			float(first.get("cube_scale_max_x", 0.0)), float(second.get("cube_scale_max_x", 0.0))
		)
		and is_equal_approx(
			float(first.get("streak_length_max", 0.0)), float(second.get("streak_length_max", 0.0))
		),
		"同一 elapsed 两次求值不一致 ⇒ 脚本里混进了随机源（逐位可复现是硬契约）"
	)
	# 对照：不同 elapsed 必须**不同**（否则上一条可能是因为「怎么算都一样」而假绿）
	var third := _snap(fx, 0.02, EXPECTED_GOO_HIT_LIFETIME)
	_expect(
		not is_equal_approx(
			float(second.get("cube_pos_max_y", 0.0)), float(third.get("cube_pos_max_y", 0.0))
		),
		"对照失效：0.02 与 0.11 的方块外推量相同 ⇒ 上一条的确定性判据没有辨别力"
	)
	fx.free()


# ---------------------------------------------------------------- B1 FX01-21 契约
func _check_metal_contract() -> void:
	var fx := _make_manual(METAL_SCENE, Vector3.UP)
	if fx == null:
		_failures.append("FX01-21 Prefab 根节点不是 VfxEffectBase3D")
		return
	_samples += 1
	var snapshot: Dictionary = fx.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == METAL_ID,
		"AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == EXPECTED_METAL_VERSION,
		"版本不是 %s：%s" % [EXPECTED_METAL_VERSION, snapshot.get("asset_version", "")])
	_expect(is_equal_approx(float(snapshot.get("lifetime", 0.0)), EXPECTED_METAL_LIFETIME),
		"寿命应为 %.2fs：%.3f" % [EXPECTED_METAL_LIFETIME, float(snapshot.get("lifetime", 0.0))])
	# 业主指定「4-5 颗 + 2 根金色火星」⇒ 刻意少量
	_expect(int(snapshot.get("cube_count", 0)) == EXPECTED_METAL_CUBES,
		"白方块数应为 %d：%d" % [EXPECTED_METAL_CUBES, int(snapshot.get("cube_count", 0))])
	_expect(int(snapshot.get("streak_count", 0)) == EXPECTED_METAL_STREAKS,
		"金色火星数应为 %d：%d" % [EXPECTED_METAL_STREAKS, int(snapshot.get("streak_count", 0))])
	for node_name in ["Cube0", "Cube4", "Streak0", "Streak1"]:
		_expect(fx.get_node_or_null(node_name) != null, "缺少节点：%s" % node_name)
	# 白方块 + 金火星
	var cube_color := snapshot.get("cube_color", Color.BLACK) as Color
	_expect(cube_color.r > 0.75 and cube_color.g > 0.75 and cube_color.b > 0.7,
		"白方块基色不白：%s" % str(cube_color))
	var streak_color := snapshot.get("streak_color", Color.BLACK) as Color
	_expect(streak_color.r > 0.9 and streak_color.g > 0.6 and streak_color.b < 0.45,
		"火星不是金色：%s" % str(streak_color))
	# 高频件刻意无灯
	_expect(not bool(snapshot.get("has_light", true)), "FX01-21 不该带灯（高频件，见脚本头）")
	_expect(bool(snapshot.get("consumes_normal", false)), "FX01-21 必须消费 context.normal")
	fx.free()


# ---------------------------------------------------------------- B2 FX01-21 法线坐标系
## 白方块必须**沿法线向外**飞：喂不同法线 ⇒ 世界方向必须跟着换（真的消费了它）。
func _check_metal_normal_frame() -> void:
	var up_fx := _make_manual(METAL_SCENE, Vector3.UP)
	if up_fx == null:
		_failures.append("FX01-21 法线用例实例化失败")
		return
	_samples += 1
	var up_mid := _snap(up_fx, EXPECTED_METAL_LIFETIME * 0.7, EXPECTED_METAL_LIFETIME)
	_expect(float(up_mid.get("cube_pos_max_y", 0.0)) > 0.05,
		"法线=上时白方块没有向上飞：最高局部 y=%.4f" % float(up_mid.get("cube_pos_max_y", 0.0)))
	up_fx.free()

	# 对照：法线改成 +X ⇒ 同一批方块在世界里必须朝 +X 走，且局部 y 仍为正
	var side_normal := Vector3.RIGHT
	var side_fx := _make_manual(METAL_SCENE, side_normal)
	if side_fx == null:
		_failures.append("FX01-21 法线对照用例实例化失败")
		return
	_samples += 1
	side_fx.call("_on_tick", EXPECTED_METAL_LIFETIME * 0.7, EXPECTED_METAL_LIFETIME)
	var cube_nodes: Array[Node] = []
	for child in side_fx.get_children():
		if child.name.begins_with("Cube"):
			cube_nodes.append(child)
	var aligned := 0
	for node in cube_nodes:
		var cube := node as Node3D
		var offset := cube.global_position - side_fx.global_position
		if offset.length() > 0.01 and offset.normalized().dot(side_normal) > 0.5:
			aligned += 1
	_expect(aligned >= cube_nodes.size() - 1,
		"对照失效：法线改成 +X 后只有 %d/%d 颗方块朝 +X 飞 ⇒ 法线没被真正消费"
		% [aligned, cube_nodes.size()])
	side_fx.free()


# ---------------------------------------------------------------- B3 火星落在切平面
## 「打击到金属」的读法关键：金色火星**擦着表面走**（落在切平面内），不是往法线方向射。
func _check_metal_streak_tangent() -> void:
	for normal in [Vector3.UP, Vector3.RIGHT, Vector3(0.4, 0.6, 0.7).normalized()]:
		var fx := _make_manual(METAL_SCENE, normal)
		if fx == null:
			_failures.append("FX01-21 切平面对照用例实例化失败")
			return
		_samples += 1
		var snapshot := _snap(fx, EXPECTED_METAL_LIFETIME * 0.5, EXPECTED_METAL_LIFETIME)
		var dot_max := float(snapshot.get("streak_normal_dot_max", 1.0))
		_expect(dot_max <= EXPECTED_STREAK_NORMAL_DOT_MAX,
			"法线 %s：火星不在切平面内（|方向·法线| 最大 %.4f > %.2f）"
			% [str(normal), dot_max, EXPECTED_STREAK_NORMAL_DOT_MAX])
		# 长条确实在「拉长」
		var stretch := (
			float(snapshot.get("streak_length_max", 0.0))
			/ maxf(0.0001, float(_snap(fx, 0.0, EXPECTED_METAL_LIFETIME).get("streak_length_max", 0.0)))
		)
		_expect(stretch >= EXPECTED_STREAK_STRETCH_MIN,
			"法线 %s：火星没有拉长（末端/起点 = %.3f < %.1f）"
			% [str(normal), stretch, EXPECTED_STREAK_STRETCH_MIN])
		fx.free()


# ---------------------------------------------------------------- A4/B4 两件都无灯
func _check_both_light_free() -> void:
	for entry in [[GOO_HIT_SCENE, GOO_HIT_ID], [METAL_SCENE, METAL_ID]]:
		var packed: PackedScene = entry[0]
		var asset_id := String(entry[1])
		var count := 0
		var fx := packed.instantiate()
		for node in _walk(fx):
			if node is OmniLight3D or node is SpotLight3D or node is DirectionalLight3D:
				count += 1
		_expect(count == 0, "%s 内出现 %d 盏灯（高频命中件刻意无灯）" % [asset_id, count])
		fx.free()
		_samples += 1


func _walk(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_walk(child))
	return result


# ---------------------------------------------------------------- A5 无碰撞体
func _check_collision_free() -> void:
	for entry in [[GOO_HIT_SCENE, GOO_HIT_ID], [METAL_SCENE, METAL_ID]]:
		var packed: PackedScene = entry[0]
		var asset_id := String(entry[1])
		var effect := packed.instantiate()
		var collisions := _count_collision_nodes(effect)
		_expect(collisions == 0, "%s 内出现碰撞体 %d 个（特效必须纯视觉）" % [asset_id, collisions])
		effect.free()
		_samples += 1


# ---------------------------------------------------------------- C1 分流判据
func _check_routing_predicate() -> void:
	if ENEMY_SCENE == null:
		_failures.append("敌人场景未加载，分流判据用例未执行")
		return
	for kind in ZOMBIE_KINDS:
		var enemy := _spawn_enemy(kind)
		if enemy == null:
			_failures.append("%s 实例化失败" % kind)
			continue
		_samples += 1
		_expect(enemy.uses_goo_hit_burst(), "%s 应走 FX01-20（僵尸三兄弟）" % kind)
		_expect(enemy.uses_no_corpse_death(), "%s 死亡后不该留尸体 / 不该播倒地动画" % kind)
		enemy.free()
	# 反例：不属于三兄弟的怪种
	var other := _spawn_enemy(NON_ZOMBIE_KIND)
	if other == null:
		_failures.append("%s 实例化失败" % NON_ZOMBIE_KIND)
		return
	_samples += 1
	_expect(not other.uses_goo_hit_burst(), "对照失效：%s 被误判为僵尸三兄弟" % NON_ZOMBIE_KIND)
	_expect(not other.uses_no_corpse_death(), "%s 不应在「无尸体」名单里（只有僵尸三兄弟）" % NON_ZOMBIE_KIND)
	other.free()


func _spawn_enemy(kind: String) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		return null
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.configure_from_enemy_data({"enemy_type": kind, "name": kind})
	return enemy


# ---------------------------------------------------------------- C1b 贴肉落点（打在怪身上）
## 业主（同轮）：「受击的盒子**没有贴着模型**，碰撞盒里陷进去坐标大概 **0.2 米**」。
##
## ⚠ 本用例的判据**不是**「下沉量 == 0.2m」—— 那只是业主给的初估，且实测**不够**：
## 碰撞壳是**玩法口径的圆柱**（世界半径 0.714 / 0.770 / 0.770，各向同性），
## 而模型是**各向异性**的（小僵尸模型半宽 0.448×0.334、胖子僵尸 1.839×0.712）。
## 只退 0.2m 时，小僵尸从正面打仍差 **0.182m**、警察僵尸差 **0.236m**。
##
## 真正的判据是「**落点落在模型身上**」，用真渲染/探针量出来的口径直接钉：
##   对三只僵尸 × 8 个水平方向 + 1 个越顶，落点必须**位于模型可视件包围盒内**
##   （或距盒面 ≤ 3cm 的浮点余量）。这才是业主看到的「贴在身上 / 悬空」。
##
## 另两条纪律：
##   ① 换一条法线 ⇒ 落点必须跟着换（否则说明法线参数没被真正用上）；
##   ② 零法线走兜底（「怪体中心 → 命中点」），落点必须仍在模型内。
func _check_enemy_hit_anchor() -> void:
	if ENEMY_SCENE == null:
		_failures.append("敌人场景未加载，贴肉落点用例未执行")
		return
	for kind in ZOMBIE_KINDS:
		var enemy := _spawn_enemy(kind)
		if enemy == null:
			_failures.append("贴肉落点用例：%s 实例化失败" % kind)
			continue
		enemy.global_position = Vector3(10.0, -1176.0, 5.0)
		enemy.rotation = Vector3.ZERO
		_samples += 1
		# ⚠ 同步执行、不 await：分步执行器 `_process` 不会等协程，
		# 一旦在这里挂起，循环会跟后面的步骤交错，测量时机就不可控了。
		# 也让「测试量包围盒」与「实现缓存包围盒」落在同一帧、同一姿势上。
		_assert_anchor_on_body(enemy, kind)
		enemy.queue_free()


## 逐方向验「落点是否在模型身上」。方向取 8 个水平角 + 1 个越顶 ——
## 圆柱壳各向同性、模型各向异性，「正面贴住了」不代表「侧面也贴住了」。
func _assert_anchor_on_body(enemy: Enemy3D, kind: String) -> void:
	# 碰撞柱世界半径/高度（含 Enemy3D 的缩放）——模拟弹体打到的壳面
	var local_r := 0.0
	var local_h := 0.0
	var shape: Shape3D = null
	if enemy.collision_shape != null:
		shape = enemy.collision_shape.shape
	if shape is CylinderShape3D:
		local_r = (shape as CylinderShape3D).radius
		local_h = (shape as CylinderShape3D).height
	var world_r := local_r * enemy.scale.x
	var world_h := local_h * enemy.scale.y
	var aim_y := enemy.global_position.y + world_h * 0.55
	# ⚠ 判据用**命中高度那一层**的横截面，不是整只怪的包围盒 —— 理由同实现：
	# 整盒会被头顶 / 脚部的宽件撑大，「在盒内」因此偏松、与观感对不上。
	var box := _model_slab_aabb(enemy, aim_y)
	if box.size.length_squared() < 0.001:
		_failures.append("%s：量不到命中高度那一层的模型横截面，贴肉用例无效" % kind)
		return

	var worst := 0.0
	var worst_dir := ""
	var deepest := 0.0
	var deepest_dir := ""
	var probes: Array[Vector3] = []
	for i in 8:
		var angle := float(i) / 8.0 * TAU
		probes.append(Vector3(sin(angle), 0.0, cos(angle)))
	probes.append(Vector3.UP)
	for outward in probes:
		var horizon := Vector3(outward.x, 0.0, outward.z)
		var hull_point := Vector3(enemy.global_position.x, aim_y, enemy.global_position.z)
		if horizon.length_squared() > 0.0001:
			hull_point += horizon.normalized() * world_r
		else:
			hull_point.y = enemy.global_position.y + world_h * 0.5
		var anchored := enemy.hit_effect_anchor(hull_point, outward)
		var gap := _outside_gap(box, anchored)
		if gap > worst:
			worst = gap
			worst_dir = str(outward.snappedf(0.01))
		# 反侧不变式：新落点**不许比原始壳面命中点更深**
		# （壳面本来就在模型里时不该再推；只允许咬入量那点余量）
		var over := _inside_depth(box, anchored) - _inside_depth(box, hull_point)
		if over > deepest:
			deepest = over
			deepest_dir = str(outward.snappedf(0.01))
	_expect(worst <= EXPECTED_HIT_INSET_BITE_TOLERANCE,
		"%s：受击特效仍悬在模型外（最差方向 %s 距模型 %.3f m，容差 %.2f）"
		% [kind, worst_dir, worst, EXPECTED_HIT_INSET_BITE_TOLERANCE])
	_expect(deepest <= EXPECTED_HIT_INSET_BITE_TOLERANCE,
		"%s：贴肉把落点推得比原来更深 %.3f m（方向 %s，容差 %.2f）⇒ 会读成「从肚子里炸」"
		% [kind, deepest, deepest_dir, EXPECTED_HIT_INSET_BITE_TOLERANCE])
	# 方向对照：换法线必须换落点
	var base_point := enemy.global_position + Vector3(0, world_h * 0.55, 0) + Vector3.FORWARD * world_r
	var right_anchor := enemy.hit_effect_anchor(base_point, Vector3.RIGHT)
	var up_anchor := enemy.hit_effect_anchor(base_point, Vector3.UP)
	_expect(not is_equal_approx(right_anchor.y, up_anchor.y),
		"%s：换一条法线后落点没变 ⇒ 法线参数没被真正消费" % kind)
	# 零法线兜底：仍在模型内
	var fallback := enemy.hit_effect_anchor(base_point, Vector3.ZERO)
	_expect(_outside_gap(box, fallback) <= EXPECTED_HIT_INSET_BITE_TOLERANCE,
		"%s：零法线兜底的落点跑到模型外（差 %.3f m）" % [kind, _outside_gap(box, fallback)])
	# 反向对照（防「怎么算都算在盒内」的假绿）：把碰撞壳半径**人为放大 3 倍**，
	# 落点若还老老实实停在原处、说明它根本没有按「壳面 → 模型」的关系现算。
	var far_point := base_point + Vector3.FORWARD * world_r * 2.0
	var far_anchor := enemy.hit_effect_anchor(far_point, Vector3.FORWARD)
	_expect(far_anchor.distance_to(far_point) > right_anchor.distance_to(base_point) + 0.05,
		"%s：命中点被推远后，贴肉量没有跟着变大 ⇒ 判据没有辨别力" % kind)


## 模型可视件的世界包围盒 —— **滤掉隐藏件**（占位件 _core/_shell/_appendages 在挂上正式
## 模型后会被隐藏，但网格数据还在；不滤会把盒子撑到 2.6 倍，让「在不在身上」判成全在）。
func _model_world_aabb(root: Node) -> AABB:
	var box := AABB()
	var has := false
	for node in _walk(root):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if not mesh_node.is_visible_in_tree():
			continue
		var world := mesh_node.global_transform * mesh_node.get_aabb()
		if not has:
			box = world
			has = true
		else:
			box = box.merge(world)
	return box


## 点在 AABB 内的**埋深**（到最近一个面的距离）；在盒外返回 0
func _inside_depth(box: AABB, point: Vector3) -> float:
	if _outside_gap(box, point) > 0.0:
		return 0.0
	var lower := box.position
	var upper := box.position + box.size
	return minf(
		minf(point.x - lower.x, upper.x - point.x),
		minf(minf(point.y - lower.y, upper.y - point.y), minf(point.z - lower.z, upper.z - point.z))
	)


## 「命中盒」：**X/Z 取命中高度那一层的横截面**，**Y 用整只怪的全高**。
## 与实现 `_visual_local_hit_box()` 同一口径 —— 验收与实现必须量同一个盒子，
## 否则会出现「解析说贴住了、画面里明显在外面」这种对不上的结论（本项目真遇到过）。
##
## 两个空间各取所需：
##   · X/Z 用横截面 ⇒ 不被头顶 / 脚部的宽件撑大（那会让「在盒内」偏松、与观感对不上）；
##   · Y 用全高     ⇒ 沿斜法线退让后落点会自然落到更低那一层躯干上，那是**正常**的
##                    （贴肉是沿法线走，不是沿水平面走），用薄带判会把它误报成「跑到盒外」。
func _model_slab_aabb(enemy: Enemy3D, world_y: float) -> AABB:
	var band := 0.30 * enemy.scale.y
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	var min_y := INF
	var max_y := -INF
	for node in _walk(enemy):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if not mesh_node.is_visible_in_tree():
			continue
		var world := mesh_node.global_transform * mesh_node.get_aabb()
		min_y = minf(min_y, world.position.y)
		max_y = maxf(max_y, world.position.y + world.size.y)
		if world.position.y + world.size.y < world_y - band or world.position.y > world_y + band:
			continue
		min_x = minf(min_x, world.position.x)
		min_z = minf(min_z, world.position.z)
		max_x = maxf(max_x, world.position.x + world.size.x)
		max_z = maxf(max_z, world.position.z + world.size.z)
	if min_x > max_x or min_z > max_z:
		return AABB()
	return AABB(
		Vector3(min_x, min_y, min_z),
		Vector3(
			maxf(0.001, max_x - min_x),
			maxf(0.001, max_y - min_y),
			maxf(0.001, max_z - min_z)
		)
	)


## 点离 AABB 还有多远（在盒内 = 0）
func _outside_gap(box: AABB, point: Vector3) -> float:
	var lower := box.position
	var upper := box.position + box.size
	var clamped := Vector3(
		clampf(point.x, lower.x, upper.x),
		clampf(point.y, lower.y, upper.y),
		clampf(point.z, lower.z, upper.z),
	)
	return (point - clamped).length()


# ---------------------------------------------------------------- C2 枪击路由
func _check_projectile_routing() -> void:
	var pool := _pool()
	if pool == null:
		_failures.append("VfxPool 缺失，枪击路由用例未执行")
		return
	var projectile := PROJECTILE_SCRIPT.new() as Projectile3D
	if projectile == null:
		_failures.append("Projectile3D 实例化失败")
		return
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.bullet_color = Color(0.45, 0.88, 1.0)

	# ① 打中小僵尸 ⇒ 绿方块爆开
	var zombie := _spawn_enemy("melee_chaser")
	var goo_before := pool.active_count(VfxPool3D.FX01_GOO_HIT)
	var metal_before := pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT)
	projectile.call("_spawn_hit_effect", zombie, 0.85, 0.55, {"normal": Vector3.RIGHT})
	_samples += 1
	_expect(pool.active_count(VfxPool3D.FX01_GOO_HIT) == goo_before + 1,
		"打中小僵尸未借出 FX01-20（%d → %d）"
		% [goo_before, pool.active_count(VfxPool3D.FX01_GOO_HIT)])
	_expect(pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT) == metal_before,
		"打中小僵尸误借了 FX01-21（金属火星）")
	# 贴肉：借出的那件必须**落在僵尸的模型上**，而不是停在碰撞壳表面（业主：「没有贴着模型」）。
	# ⚠ 判据是「在模型包围盒内」，不是「退了正好 0.2m」—— 退让量是按模型体型现算的，三只怪各不相同。
	var goo_bucket: Array = pool._active.get(VfxPool3D.FX01_GOO_HIT, [])
	_expect(not goo_bucket.is_empty(), "枪击路由用例：借出的僵尸命中件读不到")
	if not goo_bucket.is_empty():
		var pooled := goo_bucket.back() as VfxEffectBase3D
		if pooled == null:
			_failures.append("枪击路由用例：借出的僵尸命中件不是 VfxEffectBase3D")
		else:
			var body_box := _model_world_aabb(zombie)
			var gap := _outside_gap(body_box, pooled.global_position)
			_expect(gap <= EXPECTED_HIT_INSET_BITE_TOLERANCE,
				"借出的僵尸命中件没落在模型身上（距模型 %.3f m，落点 %s）"
				% [gap, str(pooled.global_position)])
			# 反向对照：**当原始出生点在模型外时**，必须确实往里收了 ——
			# 「原地不动」也能满足「在盒内」（弹体本来就打得很近时），所以这条要带前提，
			# 否则会误报（本用例第一次就是栽在这个无条件断言上）。
			var raw_gap := _outside_gap(body_box, projectile.global_position)
			if raw_gap > 0.05:
				_expect(
					pooled.global_position.distance_to(projectile.global_position) > 0.05,
					"原始出生点在模型外 %.3f m，却完全没做贴肉收进" % raw_gap
				)

	# ② 对照：打中召唤者 ⇒ 金属火星，且**不得**再借 FX01-20
	var other := _spawn_enemy(NON_ZOMBIE_KIND)
	goo_before = pool.active_count(VfxPool3D.FX01_GOO_HIT)
	metal_before = pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT)
	projectile.call("_spawn_hit_effect", other, 0.85, 0.55, {})
	_samples += 1
	_expect(pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT) == metal_before + 1,
		"打中召唤者未借出 FX01-21（%d → %d）"
		% [metal_before, pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT)])
	_expect(pool.active_count(VfxPool3D.FX01_GOO_HIT) == goo_before,
		"对照失效：打中召唤者也借了 FX01-20")

	# ③ 对照：打在墙面上（`_hit_surface` 那条路）⇒ 金属火星
	goo_before = pool.active_count(VfxPool3D.FX01_GOO_HIT)
	metal_before = pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT)
	projectile.call("_hit_surface", Vector3.UP, {})
	_samples += 1
	_expect(pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT) == metal_before + 1,
		"打墙面未借出 FX01-21（%d → %d）"
		% [metal_before, pool.active_count(VfxPool3D.FX01_METAL_SPARK_HIT)])
	_expect(pool.active_count(VfxPool3D.FX01_GOO_HIT) == goo_before,
		"对照失效：打墙面借了 FX01-20")

	pool.clear_kind(VfxPool3D.FX01_GOO_HIT)
	pool.clear_kind(VfxPool3D.FX01_METAL_SPARK_HIT)
	zombie.free()
	other.free()
	projectile.queue_free()


# ---------------------------------------------------------------- C3 近战路由
## 业主追问后明确「枪击 + 近战都用」⇒ 近战打中同一只怪必须走到**同一件**特效。
func _check_melee_routing() -> void:
	var source_path := "res://src/player3d/melee/PlayerMeleeCombat3D.gd"
	var source := FileAccess.get_file_as_string(source_path)
	_expect(not source.is_empty(), "读不到 %s，近战路由静态用例未执行" % source_path)
	_samples += 1
	# 静态门禁：近战命中件必须按 `uses_goo_hit_burst()` 分流到 FX01_GOO_HIT
	_expect(source.contains("uses_goo_hit_burst"), "近战命中未按 uses_goo_hit_burst() 分流")
	_expect(source.contains("VfxPool3D.FX01_GOO_HIT"), "近战命中未引用 VfxPool3D.FX01_GOO_HIT")
	# 非僵尸仍走近战专属件（不能把 FX01-05 变成无人引用的孤儿）
	_expect(source.contains("VfxPool3D.FX01_MELEE_IMPACT"),
		"近战命中未保留 FX01_MELEE_IMPACT（非僵尸怪种仍该用它）")
	# 静态门禁：`Projectile3D` 也必须走同一个判据（两条路一个入口）
	var proj_source := FileAccess.get_file_as_string("res://src/combat3d/Projectile3D.gd")
	_expect(proj_source.contains("uses_goo_hit_burst"),
		"Projectile3D 未按 uses_goo_hit_burst() 分流 ⇒ 枪击与近战会各走一套判据")
	# 静态门禁：`VFX-IMPACT-3D` 不该再从命中路径出（它保留给非僵尸死亡爆点 / 护盾弹开）
	_expect(not proj_source.contains("FX01_IMPACT"),
		"Projectile3D 仍在借用 FX01_IMPACT ⇒ 命中特效分流没做干净")
	# 静态门禁（第四轮口径）：命中点必须过 `hit_effect_anchor()` 收进模型，否则又会悬在壳外
	_expect(proj_source.contains("hit_effect_anchor"),
		"Projectile3D 命中特效没经过 Enemy3D.hit_effect_anchor() ⇒ 会重新悬在碰撞壳外")
	# 静态门禁：僵尸那件的尺寸必须**派生**自金属火星档位（业主「放大大概 10%」）
	_expect(proj_source.contains("ZOMBIE_HIT_SIZE_RATIO"),
		"Projectile3D 未按 ZOMBIE_HIT_SIZE_RATIO 给僵尸那件定尺寸 ⇒「放大 10%」没落地")
	_expect(proj_source.contains("%s" % EXPECTED_ZOMBIE_SIZE_RATIO),
		"ZOMBIE_HIT_SIZE_RATIO 不再是 %.2f（业主定档值）" % EXPECTED_ZOMBIE_SIZE_RATIO)
	# 静态门禁：近战僵尸分支不能沿用近战件那套 `size`（会把方块放大到糊住怪）
	var melee_source := FileAccess.get_file_as_string(
		"res://src/player3d/melee/PlayerMeleeCombat3D.gd"
	)
	_expect(melee_source.contains("ZOMBIE_HIT_BASE_SIZE"),
		"近战僵尸分支未换用 ZOMBIE_HIT_BASE_SIZE 档位 ⇒ 又会变成「太大」")


# ---------------------------------------------------------------- C4 尺寸线性
func _check_size_linearity() -> void:
	for entry in [
		[GOO_HIT_SCENE, "cube_scale_max_x"], [METAL_SCENE, "cube_scale_max_x"]
	]:
		var packed: PackedScene = entry[0]
		var key := String(entry[1])
		var a := _make_manual(packed, Vector3.UP, 1.0)
		var b := _make_manual(packed, Vector3.UP, 0.8)
		if a == null or b == null:
			_failures.append("尺寸线性用例实例化失败：%s" % entry[0])
			continue
		_samples += 1
		var value_a := float(_snap(a, 0.05, 0.32).get(key, 0.0))
		var value_b := float(_snap(b, 0.05, 0.32).get(key, 0.0))
		a.free()
		b.free()
		if value_b <= 0.0:
			_failures.append("尺寸用例：size 0.8 下的 %s 未测到" % key)
			continue
		_expect(absf(value_a / value_b - 1.25) <= 0.02,
			"未随 size 线性（比值 %.4f，期望 1.25）" % (value_a / value_b))


# ---------------------------------------------------------------- D 死亡接线（胖子僵尸）
func _enemy_death_case_begin() -> void:
	# 胖子僵尸：无关卡自爆规格 ⇒ 仍必须出**表现**（橙红方块 + 绿色冲击波），且**不留尸体**
	var pool := _pool()
	if pool == null:
		_failures.append("VfxPool 缺失，胖子僵尸死亡用例未执行")
		return
	var fat := ENEMY_SCENE.instantiate() as Enemy3D
	if fat == null:
		_failures.append("胖子僵尸实例化失败")
		return
	add_child(fat)
	fat.set_physics_process(false)
	fat.global_position = Vector3(6.0, -1176.0, -4.0)
	fat.configure_from_enemy_data({"enemy_type": "fat_zombie03", "name": "胖子僵尸"})
	fat.room_id = "room_hit_probe"
	_expect(not fat.uses_goo_death_burst(), "胖子僵尸不该走 FX01-19（它走自爆 FX01-17）")
	_expect(fat.uses_no_corpse_death(), "胖子僵尸应在「无尸体」名单里")
	var blast_before := pool.active_count(VfxPool3D.FX01_DEATH_BLAST)
	var goo_before := pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)
	fat.take_damage(999999)
	_samples += 1
	_fat_enemy = fat
	# 同帧：模型必须已收起（倒地动画做不到 —— 它要先留一具躯干播 2.6s）
	if fat.avatar != null and fat.avatar.has_formal_normal():
		_expect(not fat.avatar.visible, "胖子僵尸死亡同帧模型未收起（仍在走倒地表现）")
	_expect(not fat.is_in_group("enemy_death_visual_3d"),
		"胖子僵尸不应进入死亡显影组（本表现没有尸体）")
	_expect(pool.active_count(VfxPool3D.FX01_DEATH_BLAST) == blast_before + 1,
		"胖子僵尸死亡未借出自爆特效（%d → %d）"
		% [blast_before, pool.active_count(VfxPool3D.FX01_DEATH_BLAST)])
	_expect(pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH) == goo_before,
		"胖子僵尸死亡误借了 FX01-19（小僵尸死亡件）")
	var bucket: Array = pool._active.get(VfxPool3D.FX01_DEATH_BLAST, [])
	if not bucket.is_empty():
		var fx := bucket.back() as VfxEffectBase3D
		if fx != null:
			var snapshot: Dictionary = fx.call("get_presentation_snapshot")
			# 业主口径「把小僵尸的死亡特效放大两倍给胖子僵尸用」⇒ 固定 2.0（小僵尸那条是 1.0）
			_expect(is_equal_approx(fx.effect_size, 2.0),
				"胖子僵尸死亡视觉尺寸应为 2.0（小僵尸 1.0 的两倍）：%.3f" % fx.effect_size)
			_expect(absf(float(snapshot.get("floor_local_y", 0.0)) + 0.65) < 0.01,
				"floor_y 未按脚底口径传入：floor_local_y=%.4f"
				% float(snapshot.get("floor_local_y", 0.0)))
			# 与 FX01-19 是同一段身体 ⇒ 件数必须一致；差别只在尺寸与冲击波
			_expect(int(snapshot.get("burst_count", 0)) == 12,
				"胖子僵尸死亡应有 12 枚爆炸粒子（与小僵尸死亡同一段身体）：%d"
				% int(snapshot.get("burst_count", 0)))
			_expect(int(snapshot.get("splat_count", 0)) == 14, "胖子僵尸死亡应有 14 枚飞溅粒子")
			_expect(int(snapshot.get("puddle_count", 0)) == 4, "胖子僵尸死亡应有 4 块地面液体")
			_expect(int(snapshot.get("shockwave_count", 0)) == 3,
				"胖子僵尸死亡应有 3 层绿色冲击波（业主：只有它有）：%d"
				% int(snapshot.get("shockwave_count", 0)))
			_expect(bool(snapshot.get("green_dominant", false)), "胖子僵尸死亡不是绿色主导")
			_expect(bool(snapshot.get("green_dominant", false)), "自爆冲击波不是绿色主导")

	# 小僵尸：走 FX01-19，尺寸 = 2.0（业主「放大 2 倍」）
	var zombie := _spawn_enemy("melee_chaser")
	if zombie == null:
		_failures.append("小僵尸实例化失败")
		return
	zombie.global_position = Vector3(-6.0, -1176.0, 3.0)
	goo_before = pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)
	blast_before = pool.active_count(VfxPool3D.FX01_DEATH_BLAST)
	zombie.take_damage(999999)
	_samples += 1
	_zombie_enemy = zombie
	_expect(pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH) == goo_before + 1,
		"小僵尸死亡未借出 FX01-19（%d → %d）"
		% [goo_before, pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)])
	_expect(pool.active_count(VfxPool3D.FX01_DEATH_BLAST) == blast_before,
		"小僵尸死亡误借了 FX01-17（胖子僵尸自爆件）")
	var goo_bucket: Array = pool._active.get(VfxPool3D.FX01_ZOMBIE_GOO_DEATH, [])
	if not goo_bucket.is_empty():
		var fx := goo_bucket.back() as VfxEffectBase3D
		if fx != null:
			# 业主第二轮明确「**小僵尸的死亡特效不要改变**」⇒ 尺寸保持 1.0（规格尺寸）
			_expect(is_equal_approx(fx.effect_size, 1.0),
				"小僵尸死亡特效尺寸应为 1.0（未改版）：%.3f" % fx.effect_size)
			var snapshot: Dictionary = fx.call("get_presentation_snapshot")
			# 业主：小僵尸死亡**没有**冲击波，只有胖子僵尸那条有
			_expect(int(snapshot.get("shockwave_count", -1)) == 0,
				"小僵尸死亡不该有冲击波：%d" % int(snapshot.get("shockwave_count", -1)))
			_expect(bool(snapshot.get("green_dominant", false)), "FX01-19 不是绿色主导")


func _enemy_death_case_check() -> void:
	_expect(not is_instance_valid(_fat_enemy),
		"胖子僵尸未立即回收 —— 仍在原地播倒地动画 / 留尸体")
	_expect(not is_instance_valid(_zombie_enemy), "小僵尸未立即回收")
	_expect(get_tree().get_nodes_in_group("enemy_death_visual_3d").is_empty(),
		"死亡显影组残留：僵尸三兄弟不该有尸体进组")


func _report() -> void:
	if _samples < MIN_SAMPLES:
		_failures.append("防假绿哨兵：实际样本数 %d 少于预期 %d，验收未真正执行" % [_samples, MIN_SAMPLES])
	if _failures.is_empty():
		print("HIT_ROUTING_VFX_OK: fx01-20 goo hit + fx01-21 metal spark + routing pass (samples=%d)" % _samples)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
