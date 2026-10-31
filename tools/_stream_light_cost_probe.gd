extends Node
## 「房屋流送把灯罩自发光翻掉」的代价体检。
##
## 起因（2026-10-31）：受击闪白用 `emission_enabled` 开关实现，实测每翻一次 ~100ms
## （见 `_material_variant_cost_probe`）。顺线查同类写法，发现两个更严重的：
##
##   · `WastelandLight3D._update_lens_state()`：`emission_enabled = light_enabled and _runtime_active`
##     —— 而它在 **每次房间流送状态切换**时被逐灯调用（`DungeonRoom3D._set_room_light_runtime_state`）。
##     一间房 8 盏灯进出就是 8 次翻转。
##   · `BaseLampDynamics3D._set_self_owned_emission()`：玩家按灯开关时逐面翻。
##
## 本探针只量**灯这一层**：把一盏灯 `set_runtime_active(true/false)` 往返一次，
## 记帧时。用真实房间里的真实灯，不用假件 —— 灯罩材质的 shader 配置（是否有贴图、
## 是否 unshaded）会影响变体重建成本，假件量不准。
##
## 用法：godot --path . --scene res://tools/_stream_light_cost_probe.tscn --disable-vsync
## 只读。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED := 77003244
const BUDGET_MS := 16.7

var _failures: Array[String] = []


func _ready() -> void:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _i in 20:
		await get_tree().process_frame
	var rooms: Array = tower.get("_rooms") as Array
	var best_room: DungeonRoom3D = null
	var best_lights: Array = []
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_shell_built()
		room.ensure_detail_built()
	for _i in 3:
		await get_tree().process_frame
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		var lights: Array = []
		_collect_lights(room, lights)
		if lights.size() > best_lights.size():
			best_lights = lights
			best_room = room
	print("LIGHT_COUNT rooms=%d 最多的一间=%s 灯=%d"
		% [rooms.size(), best_room.room_id if best_room != null else "-", best_lights.size()])
	if best_lights.is_empty():
		print("LIGHT_PROBE_SKIP 远征03 没有 WastelandLight3D")
		get_tree().quit(0)
		return

	# 基线：空闲帧
	var idle := await _sample_frames(40, func() -> void: pass)

	# 全房熄灯 → 全房亮灯：等价于「离开这间房再走回来」的灯具那一段。
	var off_ms := await _sample_hit_frame(func() -> void:
		for light in best_lights:
			(light as WastelandLight3D).set_runtime_active(false, false, false)
	)
	var on_ms := await _sample_hit_frame(func() -> void:
		for light in best_lights:
			(light as WastelandLight3D).set_runtime_active(true, true, true)
	)
	print("  LIGHT_TOGGLE off=%6.2fms on=%6.2fms idle_p50=%6.2fms  (n=%d 盏)"
		% [off_ms, on_ms, idle, best_lights.size()])
	if maxf(off_ms, on_ms) > BUDGET_MS:
		_failures.append(
			"%d 盏灯一次开关 %.1fms > 一帧预算 %.1fms"
			% [best_lights.size(), maxf(off_ms, on_ms), BUDGET_MS]
		)
	for reason in _failures:
		printerr("LIGHT_COST_FAIL ", reason)
	print("LIGHT_COST_%s" % ("OK" if _failures.is_empty() else "FAILED"))
	tower.queue_free()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _collect_lights(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is WastelandLight3D:
			out.append(child)
		else:
			_collect_lights(child, out)


## 空闲帧 p50 —— 必须用同一套采样口径，否则"差值"没有意义。
func _sample_frames(count: int, action: Callable) -> float:
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in count:
		action.call()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
	return _percentile(frames, 0.5)


## 单次动作的帧时：动作前后各等一帧，取**动作那一帧**的整帧耗时。
## 不能用 p50 —— 翻转只发生一次，p50 会把它平均掉（这正是"平均帧率看着正常、
## 手感却一顿"的来源）。
func _sample_hit_frame(action: Callable) -> float:
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	action.call()
	var spent := float(Time.get_ticks_usec() - t0) / 1000.0
	await get_tree().process_frame
	return spent


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * ratio), sorted.size() - 1)]
