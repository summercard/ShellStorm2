extends Node
## 远征02 门策略 / 钥匙经济验收（2026-11-06）。**已登记进 `core` 套件**。
##
## 业主口径：「远征02的关卡的方案也改成这种，以后不掉落那种大钥匙，开门逻辑不需要身上有钥匙，
## 只要本房间怪物清理后即可。」
##
## 本探针盯四件事，任何一条退回老口径都会红：
##   1. **全部 25 条边**都不消耗钥匙、都不弹命运卡；
##   2. 清房门槛的来源房判定与设计一致：非和平区要清房，和平区（走廊 / T字横廊 / 支廊 / 无编成事件房）
##      照旧全放行 —— 这与 `_door_policies_for_record` 的 `authored_layout_peaceful` 覆盖同源；
##   3. 开局手上没有钥匙，清房**不掉**钥匙实体；
##   4. 清完房直接开门成功，且**不弹**命运卡购买界面。
##
## 为什么必须有一条会失败的断言：这三项全部由 `TowerDescent3D._door_policy_for_edge()` 与
## `Dungeon3D._room_key_economy_enabled()` 决定，而它们对「关卡计划里没写这一段」是**静默**
## 回退到老口径（要钥匙 + 弹卡），不报错、不打日志。只靠 level_plan.json 里那两行 JSON，
## 下一次有人重跑 `build_expedition02_level_plan.py` 或手改数据就会无声失效。
##
## 跑法：
##   "<godot_console>" --headless --path "<project>" --scene res://tests/verification/verify_expedition02_door_policy.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"

var failures: Array[String] = []
var checked_edges := 0


func _ready() -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		_fail("远征02场景加载失败")
		_finish()
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle(12)

	if tower.get_expedition_run_id() != "expedition_02":
		_fail("场景标识不是 expedition_02：%s" % tower.get_expedition_run_id())
		_finish()
		return

	# —— 1) 钥匙经济退役 ——
	if tower._room_key_economy_enabled():
		_fail("远征02 的钥匙经济应已退役（_room_key_economy_enabled 仍为 true）")
	if int(tower.get("_room_key_count")) != 0:
		_fail("开局仍发了初始钥匙：%d" % int(tower.get("_room_key_count")))

	# —— 2) 全部边逐条过门策略 ——
	# 用 `_door_policy_towards()` 而不是 `_door_policy_for_edge()`：前者是玩家真正走的那条判据
	# （先读房间按方向声明的 `door_policies`，缺失才回落）。只测后者会漏掉「房间声明覆盖」这一层。
	var rooms: Dictionary = tower.get("_room_by_id")
	for room_id_value in rooms.keys():
		var room_id := str(room_id_value)
		var room := rooms[room_id_value] as DungeonRoom3D
		if room == null:
			continue
		var targets: Dictionary = room.door_targets
		for direction in targets.keys():
			var target_id := str(targets[direction])
			if target_id.is_empty():
				continue
			checked_edges += 1
			var policy: Dictionary = tower.call("_door_policy_towards", room_id, target_id)
			if bool(policy.get("requires_key", true)):
				_fail("%s→%s 仍要求房间钥匙：%s" % [room_id, target_id, policy])
			if bool(policy.get("triggers_fate", true)):
				_fail("%s→%s 开门仍会弹命运卡：%s" % [room_id, target_id, policy])
			# 清房门槛：来源房是和平区 ⇒ false；**入口交通门两侧都免费**（`_edge_key` 无序，
			# `_expedition_entry_gate_edges` 命中的是整条 start↔room_01 边，回程也不查清房）；
			# 其余内容房 ⇒ true。
			var is_entry_gate := (
				(room_id == "start" and target_id == "room_01")
				or (room_id == "room_01" and target_id == "start")
			)
			var expect_clear := not room.authored_layout_peaceful and not is_entry_gate
			if bool(policy.get("requires_clear", true)) != expect_clear:
				_fail("%s→%s 清房门槛与预期不符（期望 %s）：%s" % [
					room_id, target_id, str(expect_clear), policy
				])
	# 防假绿哨兵：一条边都没扫到说明房间字典没建起来，上面的断言全在空转。
	# 本关设计源 25 条 edge_policy，但 `door_targets` 是**按方向**登记的（长廊 12 门 ⇒ 两侧各记一次），
	# 所以正常会扫到 35 条以上。少于 25 就是字典不全。
	if checked_edges < 25:
		_fail("只核到 %d 条边，少于设计源的 25 条（房间字典不完整）" % checked_edges)

	# —— 3) 清房 → 免钥匙开门 → 不弹卡 ——
	# 用 room_01（非和平区、有编成）当来源：它才是「必须清完怪才能开门」的那一类。
	var foyer := rooms.get("room_01") as DungeonRoom3D
	if foyer == null:
		_fail("房间字典缺少 room_01")
		_finish()
		return
	tower._current_room_id = foyer.room_id
	foyer.cleared = false
	if tower._try_open_room_door("room_02"):
		_fail("本房未清也把门开了（清房门槛失效）")
	foyer.cleared = true
	# 清房那一刻的钥匙奖励必须被 `_room_key_economy_enabled()` 拦掉。
	tower.call("_ensure_room_key_reward", foyer)
	await _settle(2)
	var key_pickups := 0
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and foyer.is_ancestor_of(value):
			key_pickups += 1
	if key_pickups != 0:
		_fail("钥匙经济退役后清房仍掉出房间钥匙（%d 把）" % key_pickups)
	if not tower._try_open_room_door("room_02"):
		_fail("清房后仍无法开门（手上有 %d 把钥匙）：%s" % [
			tower._get_total_room_keys(), tower.status_label.text
		])
	else:
		await _settle(2)
		if bool(tower.get("_door_fate_active")):
			_fail("开门仍弹出了命运卡购买界面")
			tower._cancel_door_fate_selection()
			await _settle(2)

	_finish()


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame
		await get_tree().physics_frame


func _fail(message: String) -> void:
	failures.append(message)
	push_error("[EXP02_DOOR] %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION02_DOOR_POLICY_OK edges=%d" % checked_edges)
	else:
		print("EXPEDITION02_DOOR_POLICY_FAIL count=%d edges=%d" % [failures.size(), checked_edges])
		for failure in failures:
			print("  - %s" % failure)
	get_tree().quit(0 if failures.is_empty() else 1)
