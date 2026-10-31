extends Node
## 怪物「朝向 vs 移动方向」验收（2026-10-31 业主："有些怪物会横着移动，非常奇怪，
## 怪物没有向着自己的移动方向"）。
##
## ## 判据怎么设计才是可证伪的
##
## 直接问"它看起来像不像在横着走"没法判。能判的是**角度**：
## `模型 forward` 与 `真实位移方向` 的夹角。模型的 forward 契约是 −Z
## （`EnemyAvatar3D` 表头写死，三个 GLB 同口径）。
##
## | 样本 | 位移与"朝玩家"夹角 | 期望 |
## |---|---|---|
## | 纯横移 | 90° | forward ≈ 位移方向（≤ 20°）|
## | 后退 | 180° | 同上 |
## | 小侧移 | 30° | forward **仍朝玩家**（≤ 20°）—— 边瞄边挪要保留 |
## | 举枪（telegraph）+ 横移 | 90° | forward **仍朝玩家**（枪口要对准弹道）|
## | 位移方向过期（非本帧） | 90° | forward **仍朝玩家**（不该被旧方向带走）|
##
## 旧实现（无条件朝玩家）在 90°/180° 两档必然 ≥ 55°，本探针当场红。
##
## ## ⚠ 位移**不能**靠 `move_and_slide()` 在这类探针里制造
##
## 第一版就是这么写的，结果 12 个样本全测出 0.0° —— 因为 `move_and_slide()`
## 在 `set_physics_process(false)` 的 `_ready` 同步循环里**根本不推进位置**
## （实测 `global_position` 8 帧纹丝不动），于是 `_last_move_direction` 恒为 ZERO、
## 夹角恒为 0，是彻底的假绿。
## ⇒ 这里**直接注入** `_last_move_direction` / `_last_move_speed` / `_last_move_age`，
##    只验 `_update_facing()` 这一段决策逻辑。位移来源是 `_commit_motion()` 的既有职责，
##    它的正确性由 `verify_3d_enemy_behavior_flow` 的位移断言守着。
##
## 用法：`godot --headless --path . --scene res://tools/_egt_facing_probe.tscn`

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const INJECTOR := preload("res://src/map/MonsterInjector.gd")

## 期望角度的容差（度）。转身是逐帧插值，60 帧后稳态应 < 5°；留 20° 给过渡。
const ALIGN_TOLERANCE_DEG := 20.0
## 每档跑多少帧。60 帧 @ 60Hz = 1 s，够转 180°（`FACE_MOVE_TURN_RATE` 14 ⇒ 约 0.25 s）。
const FRAMES := 60
const DELTA := 1.0 / 60.0
## 注入的位移速度（m/s）。必须高于 `Enemy3D.FACE_MOVE_MIN_SPEED`（0.40）。
const MOVE_SPEED := 2.6
## 初始朝向刻意给成 70°：否则"没转身"和"本来就在正确方向"分不开。
const START_YAW_DEG := 70.0

const KINDS: Array[String] = ["egt_bullet_kin", "egt_keybullet_kin", "egt_gun_fairy"]

var _failures: Array[String] = []
var _rows: Array[String] = []


func _ready() -> void:
	print("=== EGT_FACING_PROBE 朝向 vs 移动方向 ===")
	for kind in KINDS:
		_case(kind, 90.0, false, "纯横移", FRAMES)
		_case(kind, 180.0, false, "后退", FRAMES)
		_case(kind, 30.0, true, "小侧移", FRAMES)
		_case_stale(kind)
		_case_locked(kind)
	_print_rows()
	_finish()


## 一档：位移方向相对「朝玩家方向」偏 `angle_deg`。
##
## `expect_face_target = true` 表示期望**不转身**（仍朝玩家）。
func _case(
	kind: String, angle_deg: float, expect_face_target: bool, label: String, frames: int
) -> void:
	var enemy := _spawn(kind)
	if enemy == null:
		return
	var player := _make_player(Vector3(0, 0, -10))
	enemy.global_position = Vector3.ZERO
	enemy.set("_target", player)
	var to_target := player.global_position - enemy.global_position
	to_target.y = 0.0
	# 怪应朝 −Z（玩家方向）；位移方向绕 Y 转 angle_deg。
	var move_dir := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(angle_deg))
	enemy.rotation.y = deg_to_rad(START_YAW_DEG)
	for step in frames:
		_inject_motion(enemy, move_dir, 0.0)
		enemy._update_facing(to_target, DELTA)

	var measured := _measure(enemy, to_target, expect_face_target)
	var label_ok := "朝玩家" if expect_face_target else "朝移动"
	_rows.append("%-20s %-10s %4.0f°  偏位移=%5.1f° 偏玩家=%5.1f°  → %s" % [
		kind, label, angle_deg, measured.x, measured.y,
		"OK（%s %.1f°）" % [label_ok, measured.x if expect_face_target == false and false else (measured.y if expect_face_target else measured.x)],
	])
	var value: float = measured.y if expect_face_target else measured.x
	_check(
		value <= ALIGN_TOLERANCE_DEG,
		"%s %s（位移偏 %.0f°）：期望%s %.0f° 内，实测 %.1f°"
		% [kind, label, angle_deg, label_ok, ALIGN_TOLERANCE_DEG, value]
	)
	player.queue_free()
	enemy.queue_free()


## 负控：位移方向**过期**（不是本帧走的）⇒ 不许被旧方向带走。
##
## 这条挡的是"读完 `_last_move_direction` 从不检查新鲜度"的写法：
## 那种实现在怪停下之后还会继续朝最后的方向站着，看起来像"卡住不看人"。
func _case_stale(kind: String) -> void:
	var enemy := _spawn(kind)
	if enemy == null:
		return
	var player := _make_player(Vector3(0, 0, -10))
	enemy.global_position = Vector3.ZERO
	enemy.set("_target", player)
	var to_target := player.global_position - enemy.global_position
	to_target.y = 0.0
	enemy.rotation.y = 0.0
	for step in 6:
		enemy._update_facing(to_target, DELTA)
	for step in FRAMES:
		# `_last_move_age` 注入成远超有效期 ⇒ 视为"没在走"。
		_inject_motion(enemy, Vector3(1, 0, 0), 5.0)
		enemy._update_facing(to_target, DELTA)
	var measured := _measure(enemy, to_target, true)
	_rows.append("%-20s %-10s %4.0f°  偏位移=%5.1f° 偏玩家=%5.1f°  → %s" % [
		kind, "方向过期", 90.0, measured.x, measured.y,
		"OK（朝玩家 %.1f°）" % measured.y,
	])
	_check(
		measured.y <= ALIGN_TOLERANCE_DEG,
		"%s 位移方向已过期却仍被带走：偏玩家 %.1f°" % [kind, measured.y]
	)
	player.queue_free()
	enemy.queue_free()


## 举枪（telegraph）期间即使横移也必须盯玩家 —— 枪口要对准弹道。
##
## 这条不是"顺手加的"：`telegraph` 属于 `FACING_LOCKED_STATES`，
## 若被写成"任何移动都转身"，玩家会看到怪边举枪边转身，弹道与枪口对不上。
func _case_locked(kind: String) -> void:
	var enemy := _spawn(kind)
	if enemy == null:
		return
	var player := _make_player(Vector3(0, 0, -10))
	enemy.global_position = Vector3.ZERO
	enemy.set("_target", player)
	var to_target := player.global_position - enemy.global_position
	to_target.y = 0.0
	enemy.rotation.y = 0.0
	for step in 6:
		enemy._update_facing(to_target, DELTA)
	enemy.transition_to("telegraph")
	for step in FRAMES:
		_inject_motion(enemy, Vector3(1, 0, 0), 0.0)
		enemy._update_facing(to_target, DELTA)
	var measured := _measure(enemy, to_target, true)
	_rows.append("%-20s %-10s %4.0f°  偏位移=%5.1f° 偏玩家=%5.1f°  → %s" % [
		kind, "举枪横移", 90.0, measured.x, measured.y,
		"OK（朝玩家 %.1f°）" % measured.y,
	])
	_check(
		measured.y <= ALIGN_TOLERANCE_DEG,
		"%s 举枪期间横移，朝向偏离玩家 %.1f°（枪口必须对着弹道）" % [kind, measured.y]
	)
	player.queue_free()
	enemy.queue_free()


## 注入"本帧走过"的事实。`age` 用来做新鲜度负控。
func _inject_motion(enemy: Enemy3D, direction: Vector3, age: float) -> void:
	enemy.set("_last_move_direction", Vector3(direction.x, 0.0, direction.z).normalized())
	enemy.set("_last_move_speed", MOVE_SPEED)
	# 注意：`_update_facing()` 内部会 `+= delta`，所以这里要**减去**一帧，
	# 否则第一档（age=0）会被加成本帧之后的值，语义更绕。
	enemy.set("_last_move_age", age - DELTA)


## 返回 (偏位移, 偏玩家)，单位度。
func _measure(enemy: Enemy3D, to_target: Vector3, _face_target: bool) -> Vector2:
	var forward := -enemy.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var moved := Vector3(enemy.get("_last_move_direction") as Vector3)
	moved.y = 0.0
	var to_move := -1.0
	if moved.length_squared() > 0.5:
		to_move = rad_to_deg(acos(clampf(forward.dot(moved.normalized()), -1.0, 1.0)))
	else:
		_failures.append("%s 位移方向为空，本档判据无效" % enemy.enemy_kind)
	var target_dir := to_target.normalized()
	var to_player := rad_to_deg(acos(clampf(forward.dot(target_dir), -1.0, 1.0)))
	return Vector2(to_move, to_player)


func _spawn(kind: String) -> Enemy3D:
	var data: Dictionary = INJECTOR.new().generate_box_enemy(kind, 1, 1)
	if data.is_empty():
		_failures.append("%s 无法生成" % kind)
		return null
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("%s 预制体实例化失败" % kind)
		return null
	add_child(enemy)
	enemy.configure_from_enemy_data(data)
	# 只驱动 `_update_facing`：引擎自己的 AI 不许插手，否则量到的是两份逻辑的叠加。
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy


func _make_player(at: Vector3) -> Node3D:
	var player := Node3D.new()
	player.set("current_hp", 100.0)
	add_child(player)
	player.global_position = at
	return player


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _print_rows() -> void:
	print("%-20s %-10s %5s  %s" % ["怪", "样本", "偏角", "测量"])
	for row in _rows:
		print(row)


func _finish() -> void:
	if _failures.is_empty():
		print("EGT_FACING_PROBE_OK")
	else:
		print("EGT_FACING_PROBE_FAILED（%d 项）" % _failures.size())
		for failure in _failures:
			print("  ✗ %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
