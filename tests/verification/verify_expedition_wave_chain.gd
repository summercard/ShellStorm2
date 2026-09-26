extends Node
## 触发盒波次链路回归（远征 01 真机序列）。
##
## 业主 2026-09-26 报：「波次的衔接，要我去手动按离开的门才会触发，不合理」。
## 当天定位到**两条各自独立**的根因，本门禁各给一条判据，且都必须在
## **真机序列**（`_on_room_entered` → 清波 → 静等，全程不碰门）下成立：
##
##   ① **进房存档点旧快照回灌覆盖波次账**
##      `_on_room_entered` 里的 `BaseManager.flush_runtime_checkpoint("room_transition")`
##      跑在 `_spawn_room_enemies` **之前**，那一刻本房还没有 `_room_wave_totals`
##      条目，落进快照的 `wave_total` 只是 `get()` 的兜底值 1、`wave_queue` 是空。
##      这份快照随后被 `_update_room_streaming` 回灌，把 `_commit_room_waves`
##      刚写好的「2 波 · 1 波待发」压回「1 波 · 0 波待发」⇒ 清完第一波时
##      `_resolve_room_enemy_departure` 看到空队列直接 `_mark_room_cleared`，
##      第 2 波起永不出现。修法：`wave_established` 显式标记 + 回灌时不许
##      用「未建立过波次」的快照覆盖已建立的运行态。
##
##   ② **延迟出怪（`spawn_delay_sec`）双重记账**
##      `_alive_by_room` 的口径是「已实例化 ＋ 在途预约」（`_reserve_room_spawn`
##      在预约时就加、`_flush_reserved_room_spawns` 走 `count_reserved=true` 不再加、
##      `_repair_hostile_room_progress` / `_restore_room_runtime_state` 也按
##       `已实例化 + _reserved_spawn_count()` 重算）。延迟出怪原本两头都不占：
##      `_queue_delayed_spawn` 时**不加**，到点实到时却按 `additive=true` 加一次
##      ⇒ 每只延迟怪留下一个永远清不掉的幽灵计数，`_can_advance_room_wave` 的
##      `alive == 0` 恒不成立 ⇒ 下一波不会自动来，只能靠玩家按门触发
##      `_repair_hostile_room_progress`（用真实实体重算账目）才推进。
##
## 为什么塔楼版 `verify_dungeon_wave_intermission` 覆盖不到本 bug：
##   · 它直接调 `_commit_room_waves`，绕过 `_on_room_entered` 的存档点与流送回灌；
##   · 它的用例从不声明 `spawn_delay_sec`（从不制造在途延迟怪）；
##   · 它跑 `Dungeon3D.tscn`（塔楼），没有 `spawn_placements` 触发盒数据。
##
## 🔴 命运触发器（`fate_reinforce`）会在击杀阈值追加一波并 `_room_wave_totals += 1`，
##    会让「自动续波」判据失效，故全程禁用（塔楼门禁亦如此）。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const TEST_ROOM_ID := "room_01"
## 远征 01 各房的 `encounter.intermission_sec` 都没写 ⇒ 走全局缺省 2.0 秒。
const INTERMISSION := 2.0
const INTERMISSION_SLACK := 0.35

var failures: Array[String] = []
var tower: TowerDescent3D
var room: DungeonRoom3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	# 壳体 + 细节都要建：落点取样要看得到家具碰撞，否则取的点和真机不同。
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	room = tower._room_by_id.get(TEST_ROOM_ID) as DungeonRoom3D
	if room == null:
		_check(false, "找不到 %s" % TEST_ROOM_ID)
	else:
		await _verify_box_wave_chain()
		await _verify_delayed_spawn_accounting()
		await _verify_entry_snapshot_guard()
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("EXPEDITION_WAVE_CHAIN_OK")
		# quit() 只是请求退出、不中断当前调用栈；必须显式 return，
		# 否则会继续落到下面的 quit(1) 把退出码覆盖成 1（曾实测只打印 OK 却 RAW_EXIT=1）。
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


# ============================================================
# 用例 1：真机序列 —— 每一波都必须「不碰门」自己来
# ============================================================

func _verify_box_wave_chain() -> void:
	_reset_room()
	var expected := _box_wave_count()
	if expected < 2:
		_check(false, "%s 的触发盒只展开出 %d 波，用例前提不成立" % [TEST_ROOM_ID, expected])
		return
	_enter(room)
	var totals := int(tower._room_wave_totals.get(room.room_id, 0))
	var queued := (tower._room_wave_queues.get(room.room_id, []) as Array).size()
	_check(
		totals == expected,
		"进房后总波数 %d ≠ 触发盒展开的 %d 波（进房存档点的旧快照把波次账覆盖了）"
			% [totals, expected]
	)
	_check(
		queued == expected - 1,
		"进房后待发队列 %d ≠ %d（旧快照回灌抹掉了待发波次）" % [queued, expected - 1]
	)
	_check(not _enemies().is_empty(), "进房没有生成首波")

	for index in range(expected):
		var wave_number := _wave()
		await _kill_all()
		_check(
			_alive() == 0,
			"第 %d 波清空后存活账仍为 %d（幽灵计数 ⇒ 永远判不了全清）" % [wave_number, _alive()]
		)
		if index >= expected - 1:
			await get_tree().process_frame
			_check(room.cleared, "终波清空后房间没有自然解锁")
			continue
		_check(_pending(), "第 %d 波全清后没有进入间歇（= 需要玩家按门才推进）" % wave_number)
		await get_tree().create_timer(INTERMISSION + INTERMISSION_SLACK).timeout
		_check(
			_wave() == wave_number + 1,
			"第 %d 波清空后静等 %.2fs 仍未自动续波（波号停在 %d）"
				% [wave_number, INTERMISSION + INTERMISSION_SLACK, _wave()]
		)
		_check(not _enemies().is_empty(), "续到第 %d 波却没有敌人整批生成" % (wave_number + 1))


# ============================================================
# 用例 2：延迟出怪记账 —— 在途算存活，到点实到不得二次累加
# ============================================================

func _verify_delayed_spawn_accounting() -> void:
	_reset_room()
	var first: Array[Dictionary] = [
		{"enemy_type": "melee_chaser", "hp": 20, "damage": 1, "floor": 1},
		{"enemy_type": "melee_chaser", "hp": 20, "damage": 1, "floor": 1, "spawn_delay_sec": 0.4},
	]
	var second: Array[Dictionary] = [
		{"enemy_type": "melee_chaser", "hp": 20, "damage": 1, "floor": 1},
	]
	_check(tower._commit_room_waves(room, [first, second]), "延迟出怪用例提交波次失败")
	_check(_delayed() == 1, "延迟怪没有挂进待生成账")
	_check(
		_enemies().size() == 1 and _alive() == 2,
		"延迟怪在途时存活账应为「实到 1 + 在途 1」，实得 实体 %d / 存活 %d"
			% [_enemies().size(), _alive()]
	)

	await _kill_landed()
	_check(_alive() == 1 and _enemies().is_empty(), "在途延迟怪被当成「本波已清」")
	_check(not _pending(), "在途延迟怪还没到点就进入了下一波间歇")

	await get_tree().create_timer(0.6).timeout
	_check(_delayed() == 0, "延迟怪到点仍未落地")
	_check(_enemies().size() == 1, "延迟怪到点没有生成实体")
	_check(
		_alive() == 1,
		"延迟怪到点实到时存活账被二次累加（幽灵计数）：alive=%d，应为 1" % _alive()
	)

	await _kill_all()
	_check(_alive() == 0, "延迟怪清掉后存活账没有归零（幽灵计数 = %d）" % _alive())
	_check(_pending(), "延迟怪全清后没有自动进入下一波间歇")
	await get_tree().create_timer(INTERMISSION + INTERMISSION_SLACK).timeout
	_check(
		_wave() == 2 and _enemies().size() == 1,
		"延迟怪全清后没有自动续出第二波（wave=%d 实体=%d）" % [_wave(), _enemies().size()]
	)


# ============================================================
# 用例 3：进房存档点旧快照回灌 —— 已建立的波次账不许被压回
# ============================================================

func _verify_entry_snapshot_guard() -> void:
	_reset_room()
	# ① 造一份「建壳期」快照：本房尚未建立任何波次账（= 真机进房存档点的形态）。
	tower._room_wave_totals.erase(room.room_id)
	tower._room_wave_queues.erase(room.room_id)
	tower._room_wave_numbers.erase(room.room_id)
	tower._alive_by_room.erase(room.room_id)
	tower._capture_room_runtime_state(room.room_id)
	var stale := tower._segment_runtime_state.get(room.room_id, {}) as Dictionary
	_check(
		stale.get("wave_established", true) == false,
		"用例没能造出「未建立波次」的快照（wave_established 标记缺失）"
	)

	# ② 本房随即真的建立了 2 波。
	var first: Array[Dictionary] = [
		{"enemy_type": "melee_chaser", "hp": 20, "damage": 1, "floor": 1},
	]
	var second: Array[Dictionary] = [
		{"enemy_type": "melee_chaser", "hp": 20, "damage": 1, "floor": 1},
	]
	_check(tower._commit_room_waves(room, [first, second]), "波次提交失败")

	# ③ 旧快照回灌：波次账必须原样保留。
	tower._restore_room_runtime_state(room.room_id)
	var totals := int(tower._room_wave_totals.get(room.room_id, 0))
	var queued := (tower._room_wave_queues.get(room.room_id, []) as Array).size()
	_check(totals == 2, "未建立波次的旧快照回灌把总波数压回 %d（应为 2）" % totals)
	_check(queued == 1, "未建立波次的旧快照回灌抹掉了待发波次（队列 %d，应为 1）" % queued)

	# ④ 反向对照：**建立过波次**的快照仍必须能正常回灌（卸载/存档恢复语义不许被削弱）。
	tower._capture_room_runtime_state(room.room_id)
	var live := tower._segment_runtime_state.get(room.room_id, {}) as Dictionary
	_check(
		live.get("wave_established", false) == true,
		"建立过波次的快照没有带上 wave_established 标记"
	)
	tower._room_wave_totals[room.room_id] = 9
	tower._room_wave_queues[room.room_id] = []
	tower._restore_room_runtime_state(room.room_id)
	totals = int(tower._room_wave_totals.get(room.room_id, 0))
	queued = (tower._room_wave_queues.get(room.room_id, []) as Array).size()
	_check(totals == 2, "建立过波次的快照被误判为陈旧而没回灌（总波数 %d，应为 2）" % totals)
	_check(queued == 1, "建立过波次的快照没有回灌待发队列（队列 %d，应为 1）" % queued)
	tower._cancel_room_wave_intermission(room.room_id)


# ============================================================
# 辅助
# ============================================================

## 与运行时同参数展开一次触发盒波次，只取波数（`_spawn_box_waves` 用私有 rng，无副作用）。
func _box_wave_count() -> int:
	var floor_number := maxi(1, tower.visual_theme.difficulty_rank)
	var denom := maxf(1.0, float(tower._records.size() - 1))
	var floor_level := clampi(
		int(float(tower._record_index(room.room_id)) / denom * 3.0), 0, 3
	)
	return tower._spawn_box_waves(room, floor_number, floor_level).size()


## 把本房退回「未访问、未刷怪、无快照、无在途」的干净态，供下一个用例重复使用。
func _reset_room() -> void:
	for value in _enemies().duplicate():
		if is_instance_valid(value):
			(value as Node).free()
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._reserved_room_spawns.erase(room.room_id)
	tower._pending_delayed_spawns.erase(room.room_id)
	tower._room_spawn_blocked.erase(room.room_id)
	tower._room_fate_wave_queued.erase(room.room_id)
	tower._cancel_room_wave_intermission(room.room_id)
	tower._segment_runtime_state.erase(room.room_id)
	tower._spawned_rooms.erase(room.room_id)
	tower._alive_by_room[room.room_id] = 0
	room.cleared = false


## 走正式进房生命周期（**不敲门**）。
func _enter(target: DungeonRoom3D) -> void:
	tower.player.global_position = target.global_position + Vector3(0.0, 0.5, 0.0)
	tower._on_room_entered(target)


## 杀光「已经落地」的敌人；在途的延迟怪不动（用例 2 要单独观察在途账）。
func _kill_landed() -> void:
	for value in _enemies().duplicate():
		var enemy := value as Enemy3D
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy._die()
	await get_tree().process_frame


## 杀光本房所有敌人，含到点才落地的延迟怪 —— 轮询到「存活账 0 且在途 0」为止。
func _kill_all() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		for value in _enemies().duplicate():
			var enemy := value as Enemy3D
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			enemy._die()
			await get_tree().process_frame
		if _alive() == 0 and _delayed() == 0:
			return
		await get_tree().create_timer(0.05).timeout


func _check(ok: bool, message: String) -> void:
	if ok:
		return
	failures.append(message)
	print("  EXPEDITION_WAVE_CHAIN_FAIL %s" % message)


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


func _delayed() -> int:
	return int((tower._pending_delayed_spawns.get(room.room_id, []) as Array).size())
