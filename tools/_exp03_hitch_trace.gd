extends Node
## 远征03「一顿一顿」帧时序审计：走遍全图，逐帧记墙钟 / GPU / CPU / draw call，
## 并把每一段的长帧对到具体事件（进房建 RuntimeDetail、首波刷怪、持续开火）。
##
## 为什么不是又一个 headless 探针：卡顿是**渲染线程**的现象。headless 没有 GPU，
## 帧时只剩脚本与物理，采不到「进房那一帧 GPU 突然多跑 30ms」这种。
## 所以本探针**必须真渲染**，并且先解除 `application/run/max_fps=60` 限帧 ——
## 否则读到的 p50 是限帧器的输出，不是渲染成本（2026-11-08 那条错误结论的教训）。
##
## 用法
##
##   godot --path . res://tools/_exp03_hitch_trace.tscn --quit-after 6000 -- --disable-vsync
##
## 产出：`.workbuddy/tmp/exp03_hitch_trace.csv`（逐帧）+ 控制台汇总。
## 只读：不改存档、不改关卡数据。`test_mode = true` 隔离持久化。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const OUT_CSV := "res://.workbuddy/tmp/exp03_hitch_trace.csv"

## 入场稳定后先采一段基线，作为"不做事时"的对照。
const BASELINE_FRAMES := 150
## 每间房停留帧数：够覆盖首波怪生成 + 第一帧 AI 启动。
const DWELL_FRAMES := 60
## 持续开火段：模拟战斗中（最容易被感知为"顿"的场景）。
const FIRE_FRAMES := 300

var _samples: Array[Dictionary] = []
var _events: Array[Dictionary] = []

var _collecting := false
var _frame_index := 0
var _last_usec := 0
var _stage := "boot"
var _stage_room := ""

var _tower: TowerDescent3D = null
var _player: Player3D = null
var _vp: Viewport = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _process(_delta: float) -> void:
	if not _collecting:
		return
	var now := Time.get_ticks_usec()
	var wall_ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	var gpu_ms := -1.0
	var cpu_ms := -1.0
	if _vp != null and is_instance_valid(_vp):
		gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid())
		cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(_vp.get_viewport_rid())
	var enemies := 0
	if _tower != null and is_instance_valid(_tower):
		for value in (_tower.get("_alive_by_room") as Dictionary).values():
			enemies += int(value)
	_samples.append({
		"frame": _frame_index,
		"t_ms": float(now) / 1000.0,
		"wall_ms": wall_ms,
		"gpu_ms": gpu_ms,
		"cpu_ms": cpu_ms,
		"draw": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"room": _stage_room,
		"stage": _stage,
		"enemies": enemies,
	})
	_frame_index += 1


func _run() -> void:
	_tower = SCENE.instantiate() as TowerDescent3D
	_tower.set("test_mode", true)
	add_child(_tower)

	# 装配是分帧推进的：等房间数量稳定，再等落位。
	var stable := 0
	var previous := -1
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var rooms: int = _tower._room_by_id.size()
		if rooms == previous and rooms >= 10:
			stable += 1
			if stable >= 40:
				break
		else:
			stable = 0
		previous = rooms
	print("HITCH rooms=%d" % _tower._room_by_id.size())

	_player = _tower.player
	if _player == null:
		printerr("HITCH_FAIL 没有玩家")
		get_tree().quit(1)
		return
	_vp = _player.get_viewport()

	# 让入场房先稳态：初始流送 + 入场刷怪 + 灯光收敛。
	_tower.call("_update_room_streaming", "start")
	for _i in 90:
		await get_tree().process_frame

	# ── 解限帧（顺序不能反：性能管理器会把 limit 写回 60）──
	RuntimePerformanceManager.set_verification_frame_budget_override(0)
	await get_tree().process_frame
	Engine.max_fps = 0
	for _i in 5:
		await get_tree().process_frame
	print("HITCH max_fps=%d physics_tick=%d" % [
		Engine.max_fps, Engine.physics_ticks_per_second])

	# ── 基线 ──
	_stage = "baseline"
	_stage_room = str(_tower.get("_current_room_id"))
	_begin_collect()
	await _wait_frames(BASELINE_FRAMES)
	_end_collect()
	_mark("BASELINE_END")

	# ── 走遍全图（BFS，按邻接逐门打开，模拟真实推进）──
	var order := _bfs_order()
	print("HITCH walk_order=%d %s" % [order.size(), ",".join(order)])
	for room_id in order:
		if room_id == str(_tower.get("_current_room_id")):
			continue
		await _walk_into(room_id)

	# ── 持续开火段：回到第一间有怪的房间 ──
	var combat_room := _pick_combat_room()
	if not combat_room.is_empty():
		await _walk_into(combat_room)
		await _fire_segment()

	# ── 对照 A：清空全图敌人，看稳态能回到多少 ──
	# 目的：把「帧时随存活敌人数量抬升」与「房间本身重」分开。
	# 不清怪时后半程攒到 34 只，稳态 p50 已经 32~38ms；若清完掉回 10ms 出头，
	# 说明用户感觉的"一直卡"主要是**活着没打的怪**在持续吃帧，而不是房间几何。
	var before_clear := _alive_total()
	_clear_all_enemies()
	_stage = "cleared"
	_stage_room = str(_tower.get("_current_room_id"))
	_begin_collect()
	await _wait_frames(120)
	_end_collect()
	_mark("CLEARED before=%d after=%d" % [before_clear, _alive_total()])

	# ── 对照 B：反向再走一遍 ──
	# 房间刚被离开又回来，`RuntimeDetail` 会真的释放再重建。若这一遍明显快于第一遍，
	# 说明首遍的尖峰里有很大一块是**首次资源加载/着色器编译**，不是每次都要付。
	var reverse: Array[String] = order.duplicate()
	reverse.reverse()
	for room_id in reverse:
		if room_id == str(_tower.get("_current_room_id")):
			continue
		await _walk_into(room_id, "2")

	_write_csv()

	# ── 拆「进房固定成本」：资源已全在内存，只剩纯构建 ──
	# 第一遍 teleport 的尖峰里混了首次 load / 着色器编译；第二次走快了一半，
	# 但仍有两百毫秒级。这一段把资源因素完全去掉，只量 `ensure_detail_built()`
	# 本身 —— 它才是玩家**每次**跨门都要付的钱。
	await _measure_rebuild_costs()

	# ── 拆「跨门整条路径」：不是只建 detail，还包括降级旧房、唤醒敌人、回灌快照 ──
	# 上面那段只量到 `ensure_detail_built()` 几十毫秒，但实测跨门帧是 200ms 级，
	# 差额必须落在 `_update_room_streaming()` 的其余分支上，不能靠猜。
	await _measure_stream_transition()

	_report()
	get_tree().quit(0)


func _measure_stream_transition() -> void:
	print("HITCH_STREAM_BEGIN")
	var probes := ["room_01", "hub_01", "n06", "shop", "boss"]
	for room_id in probes:
		var room := _tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var previous := str(_tower.get("_current_room_id"))
		# 先真降级（= 玩家离开时做的事），再计时完整升房。
		room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		_tower.call("_update_room_streaming", room_id)
		var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_tower.set("_current_room_id", room_id)
		var nxt := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms := float(Time.get_ticks_usec() - nxt) / 1000.0
		print("HITCH_STREAM %-12s full=%7.1fms next_frame=%6.1fms from=%s" % [
			room_id, total_ms, frame_ms, previous])


func _measure_rebuild_costs() -> void:
	print("HITCH_REBUILD_BEGIN")
	var rows: Array[Dictionary] = []
	for room_id in (_tower._room_by_id as Dictionary).keys():
		var room := _tower._room_by_id[room_id] as DungeonRoom3D
		if room == null:
			continue
		# 拆三段：释放旧 detail（remove_child 当场、queue_free 落帧末）、
		# 重建 detail、以及重建后那一帧真正付掉的墙钟。
		var u0 := Time.get_ticks_usec()
		room.call("_unload_runtime_detail")
		var unload_ms := float(Time.get_ticks_usec() - u0) / 1000.0
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var free_frame_ms := float(Time.get_ticks_usec() - f0) / 1000.0
		var t0 := Time.get_ticks_usec()
		room.ensure_detail_built()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var f1 := Time.get_ticks_usec()
		await get_tree().process_frame
		var build_frame_ms := float(Time.get_ticks_usec() - f1) / 1000.0
		var children := 0
		var detail := room.get_node_or_null("RuntimeDetail")
		if detail != null:
			children = detail.find_children("*", "", true, false).size()
		rows.append({
			"room": str(room_id), "ms": ms, "children": children,
			"unload": unload_ms, "free_frame": free_frame_ms,
			"build_frame": build_frame_ms,
		})
	for r in rows:
		print("HITCH_REBUILD %-26s build=%7.1fms unload=%6.1fms free_frame=%6.1fms build_frame=%6.1fms children=%d" % [
			str(r["room"]), float(r["ms"]), float(r["unload"]),
			float(r["free_frame"]), float(r["build_frame"]), int(r["children"])])
	var total := 0.0
	var worst := 0.0
	var worst_unload := 0.0
	var worst_free_frame := 0.0
	for r in rows:
		total += float(r["ms"])
		worst = maxf(worst, float(r["ms"]))
		worst_unload = maxf(worst_unload, float(r["unload"]))
		worst_free_frame = maxf(worst_free_frame, float(r["free_frame"]))
	print("HITCH_REBUILD_SUMMARY rooms=%d total=%.0fms avg=%.1fms worst_build=%.1fms worst_unload=%.1fms worst_free_frame=%.1fms" % [
		rows.size(), total, total / maxf(1.0, float(rows.size())), worst,
		worst_unload, worst_free_frame])


func _walk_into(room_id: String, pass_tag := "") -> void:
	var room := _tower._room_by_id.get(room_id) as DungeonRoom3D
	if room == null:
		return
	# 先把门打开（真实推进也要开门，否则邻房不会预热壳体）。
	for neighbor in (_tower.get("_room_neighbors") as Dictionary).get(room_id, []) as Array:
		_tower.force_open_edge_for_test(room_id, str(neighbor))
	# 玩家先到位：真实玩法里是玩家跨过门框后触发器上报，房间才激活。
	# 直接调 `_on_room_entered` 会跳过这一步，光靠后者会让敌人凭空在远处生成。
	_move_player_to(room)
	_stage = "teleport" + pass_tag
	_stage_room = room_id
	_begin_collect()
	await _wait_frames(3)
	_end_collect()
	_mark("TELEPORT%s %s" % [pass_tag, room_id])

	var t0 := Time.get_ticks_usec()
	_tower.force_enter_room_for_test(room_id)
	var enter_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_mark("ENTER%s %s sync=%.1fms" % [pass_tag, room_id, enter_ms])

	_stage = "dwell" + pass_tag
	_stage_room = room_id
	_begin_collect()
	await _wait_frames(DWELL_FRAMES)
	_end_collect()
	_mark("DWELL_END%s %s" % [pass_tag, room_id])


## 清空全图存活敌人：只为把"寄生在敌人身上的持续帧成本"从房间几何里剥离。
## 不走伤害流程（那会引入死亡特效与掉落，反而污染对照）。
func _clear_all_enemies() -> void:
	for room_id in (_tower.get("_enemy_nodes_by_room") as Dictionary).keys():
		for value in (_tower.get("_enemy_nodes_by_room") as Dictionary)[room_id] as Array:
			var enemy := value as Enemy3D
			if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.queue_free()
		(_tower.get("_alive_by_room") as Dictionary)[room_id] = 0
	_tower.call("_update_room_streaming", str(_tower.get("_current_room_id")))


func _alive_total() -> int:
	var total := 0
	for value in (_tower.get("_alive_by_room") as Dictionary).values():
		total += int(value)
	return total


func _fire_segment() -> void:
	var weapon := _player.weapon
	if weapon == null:
		print("HITCH fire_skipped no_weapon")
		return
	_stage = "fire"
	_begin_collect()
	var aim := _player.aim_direction
	for _i in FIRE_FRAMES:
		# 直接喂武器：冷却由 `try_fire` 自己拦，等价于玩家一直扣着扳机。
		weapon.try_fire(aim, _player)
		await get_tree().process_frame
	_end_collect()
	_mark("FIRE_END")


func _move_player_to(room: DungeonRoom3D) -> void:
	var dims := room.get_dimensions()
	var center := room.global_position + Vector3(0, maxf(0.2, float(dims.y) * 0.05), 0)
	if _player.is_inside_tree():
		_player.global_position = center
		_player.velocity = Vector3.ZERO


## BFS 房间序列：从当前房出发沿邻接扩展，保证每一跳都是"隔壁那间"。
func _bfs_order() -> Array[String]:
	var neighbors := _tower.get("_room_neighbors") as Dictionary
	var start := str(_tower.get("_current_room_id"))
	if start.is_empty():
		start = "start"
	var order: Array[String] = []
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		order.append(current)
		for neighbor in (neighbors.get(current, []) as Array):
			var next := str(neighbor)
			if seen.has(next):
				continue
			if not (_tower._room_by_id as Dictionary).has(next):
				continue
			seen[next] = true
			queue.append(next)
	# 图里可能有孤立房（隐藏分支），补在后面，别漏掉。
	for id in (_tower._room_by_id as Dictionary).keys():
		if not seen.has(str(id)):
			seen[str(id)] = true
			order.append(str(id))
	return order


func _pick_combat_room() -> String:
	for room in _tower._rooms as Array:
		var r := room as DungeonRoom3D
		if r != null and r.room_type in ["COMBAT", "BOSS", "ELITE"]:
			return r.room_id
	return ""


func _begin_collect() -> void:
	_last_usec = Time.get_ticks_usec()
	_collecting = true


func _end_collect() -> void:
	_collecting = false


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _mark(text: String) -> void:
	var idx := _samples.size()
	_events.append({"at": idx, "text": text})
	print("HITCH_EVENT #%d %s" % [idx, text])


func _write_csv() -> void:
	var dir := OUT_CSV.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(OUT_CSV, FileAccess.WRITE)
	if file == null:
		printerr("HITCH_FAIL 写不了 %s" % OUT_CSV)
		return
	file.store_line("frame,wall_ms,gpu_ms,cpu_ms,draw,enemies,stage,room")
	for s in _samples:
		file.store_line("%d,%.3f,%.3f,%.3f,%d,%d,%s,%s" % [
			int(s["frame"]), float(s["wall_ms"]), float(s["gpu_ms"]),
			float(s["cpu_ms"]), int(s["draw"]), int(s["enemies"]),
			str(s["stage"]), str(s["room"])])
	file.close()
	print("HITCH csv=%s frames=%d" % [OUT_CSV, _samples.size()])
	# 事件表另存，方便与逐帧对齐。
	var ev := FileAccess.open(OUT_CSV.get_basename() + "_events.txt", FileAccess.WRITE)
	if ev != null:
		for e in _events:
			ev.store_line("%d\t%s" % [int(e["at"]), str(e["text"])])
		ev.close()


func _report() -> void:
	var walls: Array[float] = []
	var gpus: Array[float] = []
	for s in _samples:
		walls.append(float(s["wall_ms"]))
		if float(s["gpu_ms"]) >= 0.0:
			gpus.append(float(s["gpu_ms"]))
	walls.sort()
	gpus.sort()
	var over16 := 0
	var over33 := 0
	var over50 := 0
	for w in walls:
		if w > 16.7:
			over16 += 1
		if w > 33.0:
			over33 += 1
		if w > 50.0:
			over50 += 1
	print("HITCH_SUMMARY frames=%d wall_p50=%.2f p95=%.2f max=%.1f gpu_p50=%.2f gpu_p95=%.2f over16=%d over33=%d over50=%d" % [
		walls.size(), _pct(walls, 0.5), _pct(walls, 0.95), walls[walls.size() - 1],
		_pct(gpus, 0.5), _pct(gpus, 0.95), over16, over33, over50])
	# 最长的 20 帧点名，附所属阶段，直接对上事件。
	var idx: Array[int] = []
	for i in _samples.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		return float(_samples[a]["wall_ms"]) > float(_samples[b]["wall_ms"]))
	print("HITCH_WORST")
	for k in mini(20, idx.size()):
		var s: Dictionary = _samples[idx[k]]
		print("  #%d %.1fms gpu=%.1f cpu=%.1f draw=%d stage=%s room=%s enemies=%d" % [
			int(s["frame"]), float(s["wall_ms"]), float(s["gpu_ms"]),
			float(s["cpu_ms"]), int(s["draw"]), str(s["stage"]),
			str(s["room"]), int(s["enemies"])])


func _pct(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var i := int(float(sorted_values.size() - 1) * ratio)
	return sorted_values[clampi(i, 0, sorted_values.size() - 1)]
