extends Node3D
## 运行时探针：**波次衔接**实测 —— 清空一波之后，下一波是「自动来」还是「要玩家按门」。
##
## 业主 2026-09-26 报告：「波次的衔接，要我去手动按离开的门才会触发，不合理」。
## 本探针复刻真机序列，逐步记录每次状态变化，回答三个问题：
##   ① 首波是不是进房就出；
##   ② 首波全清后，间歇计时器有没有被调度（`_wave_spawn_pending` 是否置位）；
##   ③ 计时器到点后，第二波到底有没有生成 —— **全程不碰门、不换房**。
## 同时跑一条对照：清空后调一次 `_try_open_room_door()`（等价于玩家按门），
## 看它是否会把「本该自动推进」的波次补上 —— 若是，即坐实业主的观察。
##
## v2（2026-09-26 晚）：① 禁用 MapFateTriggers 以隔离「命运增援」干扰；
## ② 加**逐帧台账监视器** —— 只要 (alive, 名单, 预约, 延迟) 四元组发生变化就打一行，
## 用于精确定位幽灵计数是哪一帧、由哪条路径写进去的。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")

var failures: Array[String] = []
var tower: TowerDescent3D
var room: DungeonRoom3D
var _mon_prev: Array = []
var _mon_frame := 0
var _mon_on := false


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	# 🔴 隔离干扰：命运增援（fate_reinforce）会往本房队列追加一波并 +1 总波数，
	# 那会让「首波全清后是否自动推进」的判据失效。正式回归也这么做。
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	print("    命运触发器已禁用（%d 条）" % tower._map_fate_triggers._triggers.size())
	# 先建壳体：落点取样要看到家具碰撞，否则取的点和真机不同。
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	room = tower._room_by_id.get("room_01") as DungeonRoom3D
	if room == null:
		_fail("找不到 room_01")
		_report()
		return

	await _run(room)
	_report()


func _run(target: DungeonRoom3D) -> void:
	print("--- 探针开始：room_01（3 盒 / 2 波）---")
	# ① 进房（**不敲门**，直接走正式进房生命周期）
	tower.player.global_position = target.global_position + Vector3(0.0, 0.5, 0.0)
	tower._on_room_entered(target)
	await get_tree().process_frame
	await get_tree().physics_frame
	var wave1 := _enemies()
	print("[1] 进房后：wave=%d alive=%d 实体=%d pending=%s cleared=%s"
		% [_wave(), _alive(), wave1.size(), str(_pending()), str(target.cleared)])
	_check(not wave1.is_empty(), "进房没有生成首波")
	_check(_wave() >= 1, "进房后波号仍为 0")
	_check(not _pending(), "首波刚生成就处于间歇态")

	# ② 杀光首波（含延迟怪：等它们真的落地再杀干净）—— 逐只杀，打印计数变化
	print("    首波明细：%s" % _dump())
	_mon_prev = _ledger()
	print("    [监视开始] %s" % _ledger_str(_mon_prev))
	_start_monitor()
	var killed := await _kill_all_until_clear(6.0)
	_stop_monitor()
	print("[2] 首波清空：用时 %.2fs，wave=%d alive=%d 实体=%d pending=%s cleared=%s"
		% [killed, _wave(), _alive(), _enemies().size(), str(_pending()), str(target.cleared)])
	print("    终态明细：%s" % _dump())
	_check(_alive() == 0, "杀完了存活数仍非 0")
	# 🔴 核心判据：全清的那一刻，间歇计时器**必须**已被调度
	_check(_pending(), "全清后没有进入间歇（没有调度下一波）")
	print("    → 队列剩余波数=%d，波号=%d/%d，_current_room_id=%s"
		% [int((tower._room_wave_queues.get(target.room_id, []) as Array).size()),
		   _wave(), int(tower._room_wave_totals.get(target.room_id, 0)),
		   str(tower._current_room_id)])

	# ③ 什么都不做（不按门、不换房），等间歇 + 余量
	_mon_prev = _ledger()
	_start_monitor()
	await get_tree().create_timer(4.0).timeout
	_stop_monitor()
	var wave2 := _enemies()
	print("[3] 清空后静等 4.0s（**全程没碰门**）：wave=%d alive=%d 实体=%d pending=%s"
		% [_wave(), _alive(), wave2.size(), str(_pending())])
	_check(not wave2.is_empty() or _wave() >= 2,
		"⚠ 清空后静等 4 秒仍未生成第二波 —— 复现业主说的「要按门才推进」")
	if wave2.is_empty():
		# ④ 对照：调一次开门入口（等价玩家按 E），看它是否把波次补上
		print("[4] 对照组：调 _try_open_room_door()（等价玩家按门）…")
		var opened := tower._try_open_room_door(_other_room_id())
		await get_tree().process_frame
		print("    → opened=%s wave=%d 实体=%d pending=%s status=%s"
			% [str(opened), _wave(), _enemies().size(), str(_pending()),
			   str(tower.status_label.text)])
		_check(false, "开门调用改变了波次状态（opened=%s, wave=%d）" % [str(opened), _wave()])


## 反复收割，直到本房存活数为 0 且无预约/延迟 或超时（等延迟怪落地）。
## 每次击杀打印**真实**的前后值（v1 曾把 alive 当名单前值打，误导排查）。
func _kill_all_until_clear(seconds: float) -> float:
	var start := Time.get_ticks_msec()
	var seen := 0
	while (Time.get_ticks_msec() - start) < int(seconds * 1000.0):
		for value in _enemies().duplicate():
			var enemy := value as Enemy3D
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			var alive_before := _alive()
			var list_before := _enemies().size()
			seen += 1
			enemy._die()
			await get_tree().process_frame
			print("      杀 #%d %s：alive %d→%d，名单 %d→%d，预约=%d，延迟=%d"
				% [seen, str(enemy.get_persistent_id()), alive_before, _alive(),
				   list_before, _enemies().size(),
				   _reserved_only(), _delayed()])
		await get_tree().physics_frame
		if _alive() == 0 and tower._reserved_spawn_count(room.room_id) == 0:
			return (Time.get_ticks_msec() - start) / 1000.0
		await get_tree().create_timer(0.05).timeout
	return (Time.get_ticks_msec() - start) / 1000.0


## 逐帧监视：(alive, 名单数, 预约数, 延迟数) 一变就打印，附当前波号与 pending。
func _start_monitor() -> void:
	_mon_on = true
	_monitor()


func _stop_monitor() -> void:
	_mon_on = false


func _monitor() -> void:
	while _mon_on and is_inside_tree():
		await get_tree().process_frame
		_mon_frame += 1
		var now := _ledger()
		if now != _mon_prev:
			print("      [监视 f%03d] %s → %s"
				% [_mon_frame, _ledger_str(_mon_prev), _ledger_str(now)])
			_mon_prev = now


func _ledger() -> Array:
	return [_alive(), _enemies().size(), _reserved_only(), _delayed()]


func _ledger_str(entry: Array) -> String:
	return "alive=%d 名单=%d 预约=%d 延迟=%d" % [entry[0], entry[1], entry[2], entry[3]]


func _reserved_only() -> int:
	return int((tower._reserved_room_spawns.get(room.room_id, []) as Array).size())


func _delayed() -> int:
	return int((tower._pending_delayed_spawns.get(room.room_id, []) as Array).size())


func _other_room_id() -> String:
	for value in room.door_targets.values():
		var target := str(value)
		if not target.is_empty():
			return target
	return "room_02"


## 把「计数 vs 实体」两本账并排打出来，用于定位幽灵计数。
func _dump() -> String:
	var active := tower.get_node_or_null("ActiveEnemies")
	var active_ids: Array[String] = []
	if active != null:
		for child in active.get_children():
			active_ids.append("%s(id=%s)" % [child.name, str(child.get("room_id"))])
	var pending_ids: Array[String] = []
	for value in tower._pending_delayed_spawns.get(room.room_id, []) as Array:
		var entry := value as Dictionary
		var config := entry.get("config", {}) as Dictionary
		pending_ids.append("%s#%s" % [str(config.get("enemy_type", "?")), str(entry.get("serial", "?"))])
	var named: Array[String] = []
	for value in _enemies():
		named.append(str((value as Enemy3D).get_persistent_id()))
	return (
		"alive_by_room=%d 名单=%d ActiveEnemies=%d 延迟待生成=%d 预约=%d"
		% [
			_alive(), _enemies().size(), active_ids.size(),
			_delayed(), _reserved_only(),
		]
		+ "\n      ActiveEnemies=%s\n      本房名单=%s\n      延迟字典=%s"
		% [str(active_ids), str(named), str(pending_ids)]
	)


func _enemies() -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []) as Array:
		if is_instance_valid(value) and not (value as Node).is_queued_for_deletion():
			out.append(value)
	return out


func _alive() -> int:
	return int(tower._alive_by_room.get(room.room_id, 0))


func _wave() -> int:
	return int(tower._room_wave_numbers.get(room.room_id, 0))


func _pending() -> bool:
	return tower._wave_spawn_pending.has(room.room_id)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("  WAVE_CHAIN_FAIL %s" % message)


func _fail(message: String) -> void:
	failures.append(message)


func _report() -> void:
	print("WAVE_CHAIN_SUMMARY failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	print("WAVE_CHAIN_OK" if failures.is_empty() else "WAVE_CHAIN_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
