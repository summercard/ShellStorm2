extends Node
## 验收：FX01-33 `VFX-BOARD-DEBRIS-3D` 暗门木板被打碎时飞出的木块碎块。
##
## 业主口径（2026-10-19）：「做一个门被打碎的木头飞出来的特效，**大块一点**的，做完带入然后更新账本」。
## ⇒ 本脚本盯三件业主真正会看见的事：
##   ① **大块**：单片最长边 ≥ 0.30m（不是"锯末"）；
##   ② **飞出来**：碎块朝 `context.forward` 那一侧崩，不是原地掉；
##   ③ **落地**：砸在地上，不是穿进地板或飞出一公里。
## 再加机制层四条：无碰撞体、灯会灭、复借复位、同 seed 可重放。
##
## ⚠ 全部用**非零地面高度**（`TEST_FLOOR_Y = 5.0`）测 —— 塔楼楼层向下建（98F ≈ y=-1176m），
##    `floor_y = 0` 恰好正确是本项目已经踩过的假绿坑（14.6 §5.5.2 弹壳）。
##
## 跑法：
##   godot --headless --path . res://tests/verification/verify_board_debris_vfx.tscn

## 「大块」的下限（米）——**硬编码在验收侧**，不从被测脚本派生（防自印证，14.6 §6.9）。
const EXPECTED_MIN_EXTENT := 0.30
## 上限。⚠ 只有下限是假绿温床：第一版把尺寸乘错了，每片都变成 1m 大方块
## （门宽才 2.38m），`1.0 ≥ 0.30` 照样绿 —— 是这条上限把它抓出来的。
const EXPECTED_MAX_EXTENT := 0.65
## 期望件数：8 大块 + 5 小碎屑。
const EXPECTED_PIECE_COUNT := 13
## 只用来避开「0 恰好对」的假绿。
const TEST_FLOOR_Y := 5.0
## 灯能量峰值（契约值，硬编码核对）。
const EXPECTED_LIGHT_PEAK := 1.5
## 出生点抬高量（门底 → 门洞中部）。碎片必须从门板上崩，不是从地面崩。
const EXPECTED_SPAWN_LIFT := 1.25

const DEBRIS_SCENE := preload("res://assets/art/vfx/combat_3d/vfx_board_debris_root_top3d.tscn")
const SECRET_DOOR_SCENE := preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/common_components/secret_door/secret_door_root_top3d.tscn"
)

const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _notes: Array[String] = []


func _ready() -> void:
	_check_identity()
	_check_no_collision()
	_check_light()
	_check_big_pieces()
	_check_flies_forward()
	_check_lands_on_floor()
	_check_deterministic()
	_check_reuse_reset()
	_check_end_to_end()

	if _failures.is_empty():
		for note in _notes:
			print("[NOTE] %s" % note)
		print(
			"BOARD_DEBRIS_VFX_OK 大块=%d件 单片≥%.2fm 朝前飞 落地不穿 灯会灭 复借复位 同seed可重放 端到端=破板即触发"
			% [EXPECTED_PIECE_COUNT, EXPECTED_MIN_EXTENT]
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	print("BOARD_DEBRIS_VFX_FAILED 共 %d 条" % _failures.size())
	get_tree().quit(1)


# ── A1 资产身份 ──────────────────────────────────────────────────────────
func _check_identity() -> void:
	var effect := DEBRIS_SCENE.instantiate() as VfxEffectBase3D
	if effect == null:
		_failures.append("A1 Prefab 根节点不是 VfxEffectBase3D 子类")
		return
	if String(effect.get_meta("asset_id", "")) != "VFX-BOARD-DEBRIS-3D":
		_failures.append("A1 Prefab 根 meta asset_id 不是 VFX-BOARD-DEBRIS-3D")
	if String(effect.get_meta("asset_version", "")) != "v001":
		_failures.append("A1 Prefab 根 meta asset_version 不是 v001")
	if VfxPool3D.FX01_BOARD_DEBRIS != "VFX-BOARD-DEBRIS-3D":
		_failures.append("A1 池常量 FX01_BOARD_DEBRIS 与 AssetID 不一致")
	if not VfxPool3D.has_effect(VfxPool3D.FX01_BOARD_DEBRIS):
		_failures.append("A1 池注册表里没有 FX01_BOARD_DEBRIS")
	# 契约常量自洽：脚本声明的下限必须等于验收侧硬编码的那个数（两条互不派生）。
	if absf(VfxBoardDebris3D.MIN_PIECE_EXTENT_M - EXPECTED_MIN_EXTENT) > 0.0001:
		_failures.append(
			"A1 脚本 MIN_PIECE_EXTENT_M=%.3f 与验收期望 %.3f 不一致"
			% [VfxBoardDebris3D.MIN_PIECE_EXTENT_M, EXPECTED_MIN_EXTENT]
		)
	effect.free()


# ── A2 无碰撞体 ──────────────────────────────────────────────────────────
func _check_no_collision() -> void:
	var effect := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 1)
	if effect == null:
		_failures.append("A2 无法创建特效实例")
		return
	var bodies := _count_collision(effect)
	_notes.append("A2 特效子树内 CollisionObject3D/CollisionShape3D 计数=%d" % bodies)
	if bodies != 0:
		_failures.append("A2 特效 Prefab 内出现碰撞体 %d 个（纯视觉件禁止带碰撞）" % bodies)
	_discard(effect)


# ── A3 灯真相 ────────────────────────────────────────────────────────────
func _check_light() -> void:
	var effect := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 7)
	if effect == null:
		_failures.append("A3 无法创建特效实例")
		return
	var snap: Dictionary = effect.call("get_presentation_snapshot")
	if not bool(snap.get("has_light", false)):
		_failures.append("A3 特效没有灯 —— 塔内夜间光下碎块一出框就是黑的")
		_discard(effect)
		return
	if str(snap.get("light_name", "")) != "DebrisLight":
		_failures.append("A3 灯节点名不是 DebrisLight：%s" % str(snap.get("light_name", "")))
	if bool(snap.get("light_shadows", true)):
		_failures.append("A3 灯开了阴影（特效灯必须 shadow_enabled=false）")
	var peak := float(snap.get("light_energy", 0.0))
	if absf(peak - EXPECTED_LIGHT_PEAK) > 0.0001:
		_failures.append("A3 出生灯能量 %.3f ≠ 契约值 %.3f" % [peak, EXPECTED_LIGHT_PEAK])
	var light_range := float(snap.get("light_range", 0.0))
	if light_range < 3.0 or light_range > 4.5:
		_failures.append("A3 灯范围 %.2fm 不在 3.0~4.5m 预期带内" % light_range)
	# 走到寿命结束：灯必须归零且不可见，否则池复借留长明灯（14.6 §4）。
	_step(effect, effect.lifetime + 0.05)
	var dead: Dictionary = effect.call("get_presentation_snapshot")
	if absf(float(dead.get("light_energy", 1.0))) > 0.0001:
		_failures.append("A3 寿命结束灯能量仍为 %.3f（应归零）" % float(dead.get("light_energy", 0.0)))
	var light := effect.get_node_or_null("DebrisLight") as OmniLight3D
	if light != null and light.visible:
		_failures.append("A3 寿命结束后灯仍 visible=true")
	# 半程必须已经收掉：这盏灯是 0.55s 的短灯，不是长明灯。
	var mid := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 7)
	_step(mid, 0.70)
	var mid_snap: Dictionary = mid.call("get_presentation_snapshot")
	if float(mid_snap.get("light_energy", 1.0)) > 0.0001:
		_failures.append("A3 0.70s 时灯能量仍为 %.3f（应已收）" % float(mid_snap.get("light_energy", 0.0)))
	_notes.append("A3 灯=DebrisLight 峰值=%.2f 范围=%.2fm 无阴影 / 0.55s 后归零" % [peak, light_range])
	_discard(effect)
	_discard(mid)


# ── A4 大块尺寸（业主「大块一点」的量化钉子）──────────────────────────────
func _check_big_pieces() -> void:
	var effect := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 3)
	if effect == null:
		_failures.append("A4 无法创建特效实例")
		return
	var snap: Dictionary = effect.call("get_presentation_snapshot")
	var count := int(snap.get("piece_count", 0))
	if count != EXPECTED_PIECE_COUNT:
		_failures.append("A4 件数 %d ≠ 预期 %d" % [count, EXPECTED_PIECE_COUNT])
	var extent := float(snap.get("max_piece_extent", 0.0))
	if extent < EXPECTED_MIN_EXTENT:
		_failures.append(
			"A4 最大碎片最长边仅 %.3fm（< %.2fm）—— 读作锯末，不是「大块」" % [extent, EXPECTED_MIN_EXTENT]
		)
	if extent > EXPECTED_MAX_EXTENT:
		_failures.append(
			"A4 最大碎片最长边 %.3fm（> %.2fm）—— 比门板还大，读作「一面墙在飞」"
			% [extent, EXPECTED_MAX_EXTENT]
		)
	_notes.append(
		"A4 碎片 %d 件；最大单片最长边实测 %.3fm（契约带 %.2f~%.2fm，门宽 2.38m 的 %.0f%%）"
		% [count, extent, EXPECTED_MIN_EXTENT, EXPECTED_MAX_EXTENT, extent / 2.38 * 100.0]
	)
	_discard(effect)


# ── A5 朝 forward 侧飞（消费者契约 + 反向对照）───────────────────────────
func _check_flies_forward() -> void:
	var dir_a := Vector3(0.0, 0.0, -1.0)
	var dir_b := Vector3(0.0, 0.0, 1.0)
	var effect_a := _spawn(Vector3(100.0, TEST_FLOOR_Y, 0.0), dir_a, TEST_FLOOR_Y, 11)
	var origin_a: Vector3 = effect_a.global_position
	_step(effect_a, 0.30)
	var snap_a: Dictionary = effect_a.call("get_presentation_snapshot")
	var moved_a: Vector3 = (snap_a.get("centroid", Vector3.ZERO) as Vector3) - origin_a
	var along_a := Vector3(moved_a.x, 0.0, moved_a.z).dot(dir_a)
	if along_a < 0.25:
		_failures.append("A5 forward=-Z 时碎块沿 forward 只前进 %.3fm（应 >0.25m）" % along_a)
	# 反向对照：喂相反方向，位移必须跟着翻 —— 证明真的消费了 forward，不是"恰好朝 -Z"。
	var effect_b := _spawn(Vector3(200.0, TEST_FLOOR_Y, 0.0), dir_b, TEST_FLOOR_Y, 11)
	var origin_b: Vector3 = effect_b.global_position
	_step(effect_b, 0.30)
	var snap_b: Dictionary = effect_b.call("get_presentation_snapshot")
	var moved_b: Vector3 = (snap_b.get("centroid", Vector3.ZERO) as Vector3) - origin_b
	var along_b := Vector3(moved_b.x, 0.0, moved_b.z).dot(dir_b)
	if along_b < 0.25:
		_failures.append("A5 反向对照失败：forward=+Z 时碎块沿该方向只前进 %.3fm" % along_b)
	_notes.append(
		"A5 forward 消费：-Z 位移 %.3fm / +Z 位移 %.3fm（同 seed，方向翻过来）" % [along_a, along_b]
	)
	_discard(effect_a)
	_discard(effect_b)


# ── A6 落地不穿地、不飞远 ────────────────────────────────────────────────
func _check_lands_on_floor() -> void:
	var origin := Vector3(0.0, TEST_FLOOR_Y, 0.0)
	var effect := _spawn(origin, Vector3.FORWARD, TEST_FLOOR_Y, 5)
	if effect == null:
		_failures.append("A6 无法创建特效实例")
		return
	_step(effect, 2.2)
	var snap: Dictionary = effect.call("get_presentation_snapshot")
	var lowest := float(snap.get("lowest_y", -9999.0))
	if lowest < TEST_FLOOR_Y - 0.02:
		_failures.append(
			"A6 有碎片穿进地板：最低点 y=%.3f < 地面 %.2f" % [lowest, TEST_FLOOR_Y]
		)
	if lowest > TEST_FLOOR_Y + 0.60:
		_failures.append(
			"A6 碎片没有落到地面：最低点 y=%.3f，地面 %.2f（悬空 %.2fm）"
			% [lowest, TEST_FLOOR_Y, lowest - TEST_FLOOR_Y]
		)
	var landed := int(snap.get("landed_count", 0))
	if landed != int(snap.get("piece_count", 0)):
		_failures.append("A6 只有 %d/%d 片落地" % [landed, int(snap.get("piece_count", 0))])
	var centroid: Vector3 = snap.get("centroid", Vector3.ZERO) as Vector3
	var spread := Vector2(centroid.x - origin.x, centroid.z - origin.z).length()
	if spread > 4.0:
		_failures.append("A6 碎块飞出 %.2fm（>4m）—— 已经飞出门口了" % spread)
	_notes.append(
		"A6 非零地面 y=%.1f：最低点 %.3f（离地 %.3f），%d/%d 落地，散开 %.2fm"
		% [TEST_FLOOR_Y, lowest, lowest - TEST_FLOOR_Y, landed, int(snap.get("piece_count", 0)), spread]
	)
	_discard(effect)


# ── A7 确定性（同 seed 逐位可重放 / 不同 seed 真的散开）─────────────────
func _check_deterministic() -> void:
	var one := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 424242)
	var two := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 424242)
	var other := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 777001)
	_step(one, 0.45)
	_step(two, 0.45)
	_step(other, 0.45)
	var a := _piece_positions(one)
	var b := _piece_positions(two)
	var c := _piece_positions(other)
	if a.size() != b.size() or a.size() != c.size():
		_failures.append("A7 三次实例化的碎片数不一致")
		_discard(one)
		_discard(two)
		_discard(other)
		return
	var worst_same := 0.0
	var worst_diff := 0.0
	for index in a.size():
		worst_same = maxf(worst_same, a[index].distance_to(b[index]))
		worst_diff = maxf(worst_diff, a[index].distance_to(c[index]))
	if worst_same > 0.0001:
		_failures.append("A7 同 seed 两实例散开不一致：最大差 %.4fm（脚本里混进了随机）" % worst_same)
	if worst_diff < 0.05:
		_failures.append("A7 不同 seed 两实例几乎重合：最大差 %.4fm（seed 没起作用）" % worst_diff)
	_notes.append("A7 同 seed 最大差 %.6fm；不同 seed 最大差 %.3fm" % [worst_same, worst_diff])
	_discard(one)
	_discard(two)
	_discard(other)


# ── A8 复借复位 ──────────────────────────────────────────────────────────
func _check_reuse_reset() -> void:
	var effect := _spawn(Vector3.ZERO, Vector3.FORWARD, TEST_FLOOR_Y, 31)
	if effect == null:
		_failures.append("A8 无法创建特效实例")
		return
	_step(effect, effect.lifetime + 0.05)
	# 池复借：同一个实例再次 activate，全部状态必须回到出生瞬间。
	effect.activate(Vector3(0.0, TEST_FLOOR_Y, 0.0), Color(0.32, 0.2, 0.1), 1.0, {
		"forward": Vector3.FORWARD,
		"floor_y": TEST_FLOOR_Y,
		"seed": 31,
	})
	var snap: Dictionary = effect.call("get_presentation_snapshot")
	if int(snap.get("landed_count", -1)) != 0:
		_failures.append("A8 复借后 landed_count=%d（应全部回到飞行态）" % int(snap.get("landed_count", -1)))
	if absf(float(snap.get("light_energy", 0.0)) - EXPECTED_LIGHT_PEAK) > 0.0001:
		_failures.append("A8 复借后灯能量 %.3f（应回到峰值）" % float(snap.get("light_energy", 0.0)))
	if effect.get_node_or_null("DebrisLight") == null:
		_failures.append("A8 复借后 DebrisLight 节点丢失")
	# 出生点必须抬到门洞中部：门底 → 门洞中部 1.25m。
	var lift := effect.global_position.y - TEST_FLOOR_Y
	if absf(lift - EXPECTED_SPAWN_LIFT) > 0.01:
		_failures.append("A8 出生点只抬了 %.3fm（应 %.2fm：碎片要从门板崩，不是从地面）" % [lift, EXPECTED_SPAWN_LIFT])
	_notes.append("A8 复借复位：落地清零 / 灯回峰值 / 出生点抬高 %.2fm" % lift)
	_discard(effect)


# ── A9 端到端接线：真打门，破板就播 ─────────────────────────────────────
func _check_end_to_end() -> void:
	var pool := get_node_or_null("/root/VfxPool") as VfxPool3D
	if pool == null:
		_failures.append("A9 拿不到 autoload VfxPool")
		return
	pool.clear_all()
	var door := SECRET_DOOR_SCENE.instantiate() as SecretDoor3D
	if door == null:
		_failures.append("A9 暗门预制体实例化失败")
		return
	# ⚠ 顺序：先 add_child 再定位 —— 未入树时写 `global_position` 会报
	#   `Condition "!is_inside_tree()"`，且坐标不可靠（第一版这么写，引擎报了两条 ERROR）。
	add_child(door)
	door.global_position = Vector3(12.0, -24.0, 6.0)
	door.configure({"site_id": "t_s1", "pair_id": 0, "role": "entry"}, 60)
	var before := pool.active_count(VfxPool3D.FX01_BOARD_DEBRIS)
	door.take_damage(9999)
	var after := pool.active_count(VfxPool3D.FX01_BOARD_DEBRIS)
	if after != before + 1:
		_failures.append("A9 打碎门板后没有借出碎块特效（active %d→%d）" % [before, after])
		door.queue_free()
		return
	var effect := _active_of(pool, VfxPool3D.FX01_BOARD_DEBRIS)
	if effect == null:
		_failures.append("A9 池里取不到碎块实例")
		door.queue_free()
		return
	var delta := effect.global_position - door.global_position
	# 出生点 = 门底 + forward×0.18 + 上 1.25m
	if absf(delta.y - EXPECTED_SPAWN_LIFT) > 0.05:
		_failures.append("A9 特效出生点相对门底 y 差 %.3fm（应 %.2fm）" % [delta.y, EXPECTED_SPAWN_LIFT])
	var snap: Dictionary = effect.call("get_presentation_snapshot")
	var forward: Vector3 = snap.get("forward", Vector3.ZERO) as Vector3
	var door_forward := -door.global_basis.z
	if forward.dot(door_forward) < 0.99:
		_failures.append(
			"A9 特效 forward 未对齐门的房间侧法线（点积 %.3f）" % forward.dot(door_forward)
		)
	if absf(float(snap.get("floor_y", -9999.0)) - door.global_position.y) > 0.01:
		_failures.append(
			"A9 floor_y=%.3f 未取门的世界 y=%.3f（⛔ 不许以 0 兜底）"
			% [float(snap.get("floor_y", -9999.0)), door.global_position.y]
		)
	# 读档恢复 / 静默打开不能补播 —— 那会让"进游戏时门早破了"的玩家看到墙自己炸。
	pool.clear_all()
	var door2 := SECRET_DOOR_SCENE.instantiate() as SecretDoor3D
	add_child(door2)
	door2.global_position = Vector3(-12.0, -24.0, 6.0)
	door2.configure({"site_id": "t_s2", "pair_id": 0, "role": "exit"}, 60)
	door2.restore_state({"site_id": "t_s2", "pair_id": 0, "broken": true, "locked": false})
	if pool.active_count(VfxPool3D.FX01_BOARD_DEBRIS) != 0:
		_failures.append("A9 读档恢复已破的门也播了碎块（应静默）")
	_notes.append(
		"A9 端到端：破板 → 借出 1 个实例，出生抬高 %.2fm，forward 点积 %.3f，floor_y=%.1f；读档恢复不重播"
		% [delta.y, forward.dot(door_forward), float(snap.get("floor_y", 0.0))]
	)
	pool.clear_all()
	door.queue_free()
	door2.queue_free()


# ── 工具 ─────────────────────────────────────────────────────────────────
func _spawn(at: Vector3, forward: Vector3, floor_y: float, seed_value: int) -> VfxEffectBase3D:
	var effect := DEBRIS_SCENE.instantiate() as VfxEffectBase3D
	if effect == null:
		return null
	add_child(effect)
	effect.activate(at, Color(0.30, 0.19, 0.09), 1.0, {
		"forward": forward,
		"floor_y": floor_y,
		"seed": seed_value,
	})
	return effect


## 手动步进（同步循环内引擎不会插帧 ⇒ 时间线完全可控）。
func _step(effect: VfxEffectBase3D, seconds: float) -> void:
	if effect == null:
		return
	var frames := int(round(seconds / STEP))
	for _frame in frames:
		effect.call("_process", STEP)


func _discard(effect: VfxEffectBase3D) -> void:
	if effect != null and is_instance_valid(effect):
		effect.queue_free()


func _count_collision(root: Node) -> int:
	var count := 0
	if root is CollisionObject3D or root is CollisionShape3D:
		count += 1
	for child in root.get_children():
		count += _count_collision(child)
	return count


func _piece_positions(effect: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for child in effect.get_children():
		if child is MeshInstance3D:
			out.append((child as MeshInstance3D).global_position)
	return out


func _active_of(pool: VfxPool3D, asset_id: StringName) -> VfxEffectBase3D:
	var active: Variant = pool.get("_active")
	if not (active is Dictionary):
		return null
	var bucket: Variant = (active as Dictionary).get(asset_id, [])
	if not (bucket is Array) or (bucket as Array).is_empty():
		return null
	return (bucket as Array).back() as VfxEffectBase3D
