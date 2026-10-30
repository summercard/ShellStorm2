extends Node
## 远征03 全量怪物「真实战斗中的位移越界」监控（2026-10-30）。
##
## 业主报「瞬移后打不中它、它的子弹也打不中玩家」，根因是**随机落点没有房内约束**
## （`_is_point_inside_room_hint` 用圆形近似判矩形房，半径还随当前位置自增 ⇒ 怪飘出房）。
## 之后要求「检查每只怪」，所以要有覆盖面 —— 但**覆盖面不能靠构造**：
##
## 第一版曾把每只怪构造到房里、直接 `set_runtime_active(true,true)` 让它跑，
## 结果 33 只里 32 只位移 0.00m —— 因为 AI 的移动由 `_ai_decision.awareness` 驱动，
## 而那个决策要完整感知链（视觉/光照/`MonsterAIManager`）。构造出来的怪压根没进入战斗，
## "没动"被记成"没出房"，是彻头彻尾的假绿。
##
## 所以本探针走**真实链路**：逐间战斗房真的进去、等门落、等出怪、让它们真的打
## `RUN_SECONDS` 秒，同时每物理帧检查场上每一只怪：
##   ① 水平位置是否超出房间矩形（出房 / 穿墙）
##   ② 是否掉到地板以下
##   ③ 位移量（用来证明"它真的动了"—— 位移恒 0 说明这一房没进入战斗，判据无效）
##
## ⚠ **能力边界，必读**：本探针是"广而浅"，**抓不到低频累积漂移**。
## 实测佐证：把瞬移的房内约束撤掉后跑本探针，结果**仍然全绿** —— 因为 4 秒窗口里
## 空尖弹只瞬移 1~2 次（间隔 2.8s），而那个 bug 要**几十次**累积才飘出房。
## 所以：
##   · 「瞬移/游荡落点算法」的主门禁是 `_egt_blink_probe`（600 次压测 + 墙角构造补测），
##     它验证过有效性：撤掉约束会立刻报 58%~84% 出房；
##   · 本探针只负责「真实战斗里有没有一次性大位移穿墙」（rush / leap / grab / 拉扯）。
## 两者互补，不能互相替代，也别拿本探针的全绿去证明落点算法没问题。
##
## 用法：godot --headless --path . --scene res://tools/_egt_enemy_motion_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
## 多种子：单种子只覆盖 5 间房 / 16 种怪（其余房在本种子下没刷出怪或被前面的战斗状态卡住），
## 换骨架才能覆盖到 `box_egt_*` 的其余组合。
const SEEDS := [77003244, 42]
## 每房监控多久。要够长让瞬移（间隔 2.8s）至少发生一次。
const RUN_SECONDS := 3.0
## 位移低于这个值就认为"这一房没进入战斗"，判据作废、明确报出来而不是当通过。
const MIN_MEANINGFUL_MOVE_M := 0.15

var _failures: Array[String] = []
var _rows: Array[String] = []


func _ready() -> void:
	print("=== EGT_ENEMY_MOTION_PROBE 真实战斗位移监控 ===")
	var tested_kinds := {}
	for seed_value in SEEDS:
		await _run_seed(int(seed_value), tested_kinds)

	_print_table()
	print("\n覆盖 %d 种怪：%s" % [tested_kinds.size(), _join_keys(tested_kinds)])
	_finish()


func _run_seed(seed_value: int, tested_kinds: Dictionary) -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		_failures.append("场景不是 TowerDescent3D")
		return
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	print("\n--- 种子 %d ---" % seed_value)
	for room_value in tower._rooms:
		var room := room_value as DungeonRoom3D
		if room == null:
			continue
		if str(room.room_type) not in Dungeon3D.HOSTILE_ROOM_TYPES:
			continue
		if str(room.room_type) == "BOSS":
			continue
		if (room.spawn_placements as Array).is_empty():
			continue
		await _monitor_room(tower, room, tested_kinds)

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _monitor_room(tower: TowerDescent3D, room: DungeonRoom3D, tested_kinds: Dictionary) -> void:
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(room.room_id)
	# flow 关卡把刷怪推到落门之后（`FLOW_ROOM_SEAL_DELAY_S` + `FLOW_ROOM_SPAWN_PAUSE_S`）。
	await get_tree().create_timer(
		TowerDescent3D.FLOW_ROOM_SEAL_DELAY_S
		+ TowerDescent3D.FLOW_ROOM_SPAWN_PAUSE_S + 0.6
	).timeout
	for _frame in 4:
		await get_tree().process_frame

	var enemies: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy == null or not is_instance_valid(enemy) or enemy.ai_state == "dead":
			continue
		enemies.append(enemy)
	if enemies.is_empty():
		print("  %-16s 无怪（跳过）" % room.room_id)
		return

	var starts := {}
	for enemy in enemies:
		starts[enemy] = enemy.global_position
		tested_kinds[enemy.enemy_kind] = true

	var frames := int(RUN_SECONDS * 60.0)
	var worst_by_enemy := {}
	for index in range(frames):
		await get_tree().physics_frame
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.ai_state == "dead":
				continue
			var overflow := _room_overflow_m(enemy.global_position, room)
			var record: Dictionary = worst_by_enemy.get(enemy, {
				"overflow": 0.0, "below": 0.0, "moved": 0.0,
			})
			record["overflow"] = maxf(float(record["overflow"]), overflow)
			record["below"] = maxf(
				float(record["below"]), room.global_position.y - enemy.global_position.y
			)
			var start: Vector3 = starts[enemy]
			record["moved"] = maxf(float(record["moved"]), Vector2(
				enemy.global_position.x - start.x, enemy.global_position.z - start.z
			).length())
			worst_by_enemy[enemy] = record

	var max_overflow := 0.0
	var max_below := 0.0
	var max_moved := 0.0
	var kinds: Array[String] = []
	for enemy in worst_by_enemy.keys():
		if not is_instance_valid(enemy):
			continue
		var record: Dictionary = worst_by_enemy[enemy]
		kinds.append(str(enemy.enemy_kind))
		max_overflow = maxf(max_overflow, float(record["overflow"]))
		max_below = maxf(max_below, float(record["below"]))
		max_moved = maxf(max_moved, float(record["moved"]))
		if float(record["overflow"]) > 0.01:
			_failures.append(
				"%s 在 %s 出房 %.2fm"
				% [str(enemy.enemy_kind), room.room_id, float(record["overflow"])]
			)
		if float(record["below"]) > 1.0:
			_failures.append(
				"%s 在 %s 掉到地板下 %.2fm"
				% [str(enemy.enemy_kind), room.room_id, float(record["below"])]
			)

	_rows.append("%-16s 怪 %d 只 [%s]  最大位移 %5.2fm  最大出房 %5.2fm  最大穿地 %5.2fm"
		% [room.room_id, kinds.size(), ", ".join(kinds), max_moved, max_overflow, maxf(0.0, max_below)])

	# 位移恒为 0 ⇒ 这一房根本没打起来，判据无效。**必须报出来**，
	# 否则"怪没动"会伪装成"怪没出房"（第一版就是这样拿到 33 只全绿的）。
	if max_moved < MIN_MEANINGFUL_MOVE_M:
		_failures.append(
			"%s 里所有怪都没移动（最大位移 %.2fm）—— 没进入战斗，本次判据作废"
			% [room.room_id, max_moved]
		)


func _room_overflow_m(point: Vector3, room: DungeonRoom3D) -> float:
	var local := room.global_transform.affine_inverse() * point
	var half := room.get_dimensions() * 0.5
	var over_x := maxf(0.0, absf(local.x) - half.x)
	var over_z := maxf(0.0, absf(local.z) - half.y)
	return maxf(over_x, over_z)


func _join_keys(table: Dictionary) -> String:
	var keys: Array[String] = []
	for key in table.keys():
		keys.append(str(key))
	keys.sort()
	return ", ".join(keys)


func _print_table() -> void:
	print("\n房间逐个结果：")
	for line in _rows:
		print("  " + line)


func _finish() -> void:
	if _failures.is_empty():
		print("\nEGT_ENEMY_MOTION_PROBE_OK 真实战斗中无怪出房、无怪穿地板")
		get_tree().quit(0)
		return
	print("\nEGT_ENEMY_MOTION_PROBE_FAIL 共 %d 项：" % _failures.size())
	for line in _failures:
		print("  - %s" % line)
	get_tree().quit(1)
