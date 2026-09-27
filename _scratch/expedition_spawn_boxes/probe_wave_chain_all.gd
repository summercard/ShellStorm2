extends Node3D
## 运行时探针（v3）：**全关主路逐房**扫波次衔接 —— 清空一波后，下一波到底会不会自己来。
##
## 业主 2026-09-26 报告：「波次的衔接，要我去手动按离开的门才会触发，不合理」。
## 本探针沿主路依次进每一间房（走正式 `_on_room_entered`），每房做同一套动作：
##   ① 进房（**不敲门**）→ 记录波号/总波数/队列/存活/名单/延迟/预约；
##   ② 逐只杀光（打印每次击杀的前后账，含 app 侧四元组）；
##   ③ 全清后**静等 3 秒**（不碰门、不换房）→ 看波号是否 +1、名单是否重新有怪；
##   ④ 若没推进，打印「幽灵计数」判据，并单独调一次 `_try_open_room_door()`
##      看它是不是把本该自动推进的波次补上（= 坐实业主的观察）。
##
## 同时把「声明了几个 stage」与「运行时真的提交了几波」并排打出来 ——
## stage 被静默丢弃（盒内没有合法落点）会表现为「这一房只有 1 波」。
##
## 🔴 命运触发器（fate_reinforce）会在击杀阈值处追加一波，干扰判据，故全程禁用
## （正式回归 `verify_dungeon_wave_intermission.gd` 亦如此）。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const INTERMISSION_WAIT := 3.0
const KILL_WINDOW := 4.0

var failures: Array[String] = []
var tower: TowerDescent3D
var current: DungeonRoom3D
var rows: Array[Dictionary] = []


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	print("    命运触发器已禁用（%d 条）" % tower._map_fate_triggers._triggers.size())
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	for room_id in _walk_order():
		await _probe_room(room_id)
	_report()


## 主路顺序（= 真机推进顺序），末尾补 boss。
func _walk_order() -> Array[String]:
	var out: Array[String] = []
	for key in ["room_01", "room_02", "room_03", "room_04", "room_05",
			"room_06", "room_07", "room_08", "room_09", "room_10", "boss"]:
		if tower._room_by_id.has(key):
			out.append(key)
	return out


func _probe_room(room_id: String) -> void:
	var room := tower._room_by_id.get(room_id) as DungeonRoom3D
	current = room
	if room == null:
		return
	print("\n========== %s（room_type=%s）==========" % [room_id, room.room_type])
	var placements: Array = room.spawn_placements
	var declared_stages := _declared_stages(room)
	print("  资产层声明：spawn_placements=%d，encounter.stages=%s"
		% [placements.size(), str(declared_stages)])
	# 与运行时同法展开一次（不改状态），看每个 stage 能出几条 —— 出 0 条 = 该波被静默丢弃。
	var preview := _preview_stage_entries(room)
	print("  逐 stage 实出条目数：%s" % str(preview))

	# ① 进房（不敲门）
	var floor_r := maxi(1, tower.visual_theme.difficulty_rank)
	var denom := maxf(1.0, float(tower._records.size() - 1))
	var floor_level_r := clampi(
		int(float(tower._record_index(room_id)) / denom * 3.0), 0, 3
	)
	print("  run_seed=%d difficulty=%d floor=%d floor_level=%d 已spawned=%s"
		% [tower.run_seed, tower.visual_theme.difficulty_rank, floor_r, floor_level_r,
		   str(tower._spawned_rooms.has(room_id))])
	var w_fake := tower._spawn_box_waves(room, 1, 1)
	var w_real := tower._spawn_box_waves(room, floor_r, floor_level_r)
	print("  _spawn_box_waves(1,1)      → %d 波 %s" % [w_fake.size(), str(_wave_sizes(w_fake))])
	print("  _spawn_box_waves(真实参数) → %d 波 %s" % [w_real.size(), str(_wave_sizes(w_real))])
	if w_fake.size() != w_real.size():
		for type_id in ["melee_chaser", "ranged_caster", "summoner",
				"shielded", "exploder", "ambusher", "elite", "boss"]:
			var fake_cfg := tower._make_box_enemy(type_id, 1, 1, room)
			var real_cfg := tower._make_box_enemy(type_id, floor_r, floor_level_r, room)
			if fake_cfg.is_empty() != real_cfg.is_empty():
				print("    🔴 装配差异 type=%s：假参数=%s 真参数=%s"
					% [type_id,
					   "空" if fake_cfg.is_empty() else "OK",
					   "空" if real_cfg.is_empty() else "OK"])
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower._on_room_entered(room)
	await get_tree().process_frame
	await get_tree().physics_frame
	print("  进房后 status=「%s」 totals=%d 队列=%d"
		% [tower.status_label.text, int(tower._room_wave_totals.get(room_id, 0)),
		   int((tower._room_wave_queues.get(room_id, []) as Array).size())])
	var row := {
		"room": room_id,
		"placements": placements.size(),
		"stages_declared": declared_stages.size(),
		"stages_live": preview.size(),
		"totals": int(tower._room_wave_totals.get(room_id, 0)),
		"queue": int((tower._room_wave_queues.get(room_id, []) as Array).size()),
		"alive_enter": _alive(),
		"list_enter": _enemies().size(),
		"advance": false,
		"ghost": 0,
	}
	print("  [进房] wave=%d totals=%d 队列=%d alive=%d 名单=%d 延迟=%d 预约=%d"
		% [_wave(), row["totals"], row["queue"], _alive(), _enemies().size(), _delayed(), _reserved()])
	if row["totals"] <= 0:
		# 没波形可测（事件房 / 未摆盒 / 全是空波）。
		print("  → 本房没有可推进的波次")
		rows.append(row)
		return

	# ② 杀光
	var killed := await _kill_all(KILL_WINDOW)
	print("  [清空] 用时 %.2fs → alive=%d 名单=%d 延迟=%d 预约=%d pending=%s"
		% [killed, _alive(), _enemies().size(), _delayed(), _reserved(), str(_pending())])
	row["alive_after_kill"] = _alive()
	row["ghost"] = 1 if _is_ghost() else 0
	row["pending_after_kill"] = _pending()
	if _is_ghost():
		print("  🔴 幽灵计数：alive=%d 但名单=0 延迟=0 预约=0（本波已全清却判不清）"
			% _alive())
	if not _pending() and row["queue"] > 0:
		print("  🔴 全清后**未**进入间歇（队列里还有 %d 波，却没走推进）" % row["queue"])

	# ③ 静等（不碰门）
	var wave_before := _wave()
	var list_before := _enemies().size()
	await get_tree().create_timer(INTERMISSION_WAIT).timeout
	var wave_after := _wave()
	var list_after := _enemies().size()
	var advanced := wave_after > wave_before or list_after > 0
	row["advance"] = advanced
	print("  [静等 %.1fs] wave %d→%d 名单 %d→%d pending=%s ⇒ %s"
		% [INTERMISSION_WAIT, wave_before, wave_after, list_before, list_after,
		   str(_pending()), "自动续波 ✔" if advanced else "🔴 没有续波"])

	# ④ 对照：按门（等价玩家按 E）
	if not advanced and row["queue"] > 0:
		var before_ghost := _alive()
		var opened := tower._try_open_room_door(_other_room_id())
		await get_tree().process_frame
		print("  [对照·按门] opened=%s → alive %d→%d，pending=%s，wave=%d"
			% [str(opened), before_ghost, _alive(), str(_pending()), _wave()])
		if _pending() or _alive() != before_ghost:
			print("  ⇒ 坐实：开门入口修复了幽灵计数并补上间歇（= 业主看到的「按门才推进」）")
			row["door_fix"] = true
	rows.append(row)


func _declared_stages(room: DungeonRoom3D) -> Array:
	var raw: Variant = room.encounter.get("stages", [])
	return raw if raw is Array else []


func _wave_sizes(waves: Array) -> Array:
	var out: Array = []
	for wave in waves:
		out.append((wave as Array).size())
	return out


## 与运行时同规则展开：每个 stage 收集条目，条目为 0 则该 stage 被丢弃。
func _preview_stage_entries(room: DungeonRoom3D) -> Array:
	var placements: Array = room.spawn_placements
	if placements.is_empty():
		return []
	var stages: Array = tower._resolve_encounter_stages(room.encounter, placements.size())
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = tower.run_seed ^ room.room_id.hash() ^ 0x424f5831
	for stage_value in stages:
		var entries: Array[Dictionary] = []
		for instance_value in (stage_value as Array):
			tower._collect_box_stage_entries(
				room, placements, int(instance_value), 1, 1, rng, entries
			)
		out.append(entries.size())
	return out


func _kill_all(seconds: float) -> float:
	var start := Time.get_ticks_msec()
	var seen := 0
	while (Time.get_ticks_msec() - start) < int(seconds * 1000.0):
		var batch := _enemies().duplicate()
		for value in batch:
			var enemy := value as Enemy3D
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			var a0 := _alive()
			var l0 := _enemies().size()
			seen += 1
			enemy._die()
			await get_tree().process_frame
			print("      杀 #%-2d %-22s alive %d→%d 名单 %d→%d 延迟 %d→%d"
				% [seen, str(enemy.get_persistent_id()), a0, _alive(), l0, _enemies().size(),
				   l0, _enemies().size()])
		if _alive() == 0 and _reserved() == 0 and _delayed() == 0:
			break
		await get_tree().physics_frame
		await get_tree().create_timer(0.05).timeout
	return (Time.get_ticks_msec() - start) / 1000.0


## 幽灵计数：账上还有存活，但实体、延迟、预约三本账都空了 ⇒ 本波其实已清。
func _is_ghost() -> bool:
	return _alive() > 0 and _enemies().is_empty() and _delayed() == 0 and _reserved() == 0


func _other_room_id() -> String:
	for value in current.door_targets.values():
		var target := str(value)
		if not target.is_empty():
			return target
	return "room_02"


func _enemies() -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(current.room_id, []) as Array:
		if is_instance_valid(value) and not (value as Node).is_queued_for_deletion():
			out.append(value)
	return out


func _alive() -> int:
	return int(tower._alive_by_room.get(current.room_id, 0))


func _wave() -> int:
	return int(tower._room_wave_numbers.get(current.room_id, 0))


func _pending() -> bool:
	return tower._wave_spawn_pending.has(current.room_id)


func _reserved() -> int:
	return int((tower._reserved_room_spawns.get(current.room_id, []) as Array).size())


func _delayed() -> int:
	return int((tower._pending_delayed_spawns.get(current.room_id, []) as Array).size())


func _report() -> void:
	print("\n================ 汇总 ================")
	print("%-9s %4s %4s %5s %5s %6s %6s %6s %s"
		% ["房", "摆盒", "声明", "实出", "总波", "进房活", "清空活", "幽灵", "自动续波"])
	for row in rows:
		print("%-9s %4d %4d %5d %5d %6d %6d %6d %s"
			% [row["room"], row["placements"], row["stages_declared"], row["stages_live"],
			   row["totals"], row["alive_enter"], int(row.get("alive_after_kill", -1)),
			   row["ghost"], "✔" if row["advance"] else "✘"])
	var ghost_rooms: Array[String] = []
	var no_advance: Array[String] = []
	var dropped: Array[String] = []
	for row in rows:
		if int(row["ghost"]) == 1:
			ghost_rooms.append(row["room"])
		if int(row["totals"]) > 1 and not row["advance"]:
			no_advance.append(row["room"])
		if int(row["stages_live"]) < int(row["stages_declared"]):
			dropped.append("%s(%d/%d)" % [row["room"], row["stages_live"], row["stages_declared"]])
	print("\n幽灵计数的房：%s" % str(ghost_rooms))
	print("多波却不自动续波的房：%s" % str(no_advance))
	print("stage 被静默丢弃的房：%s" % str(dropped))
	print("WAVE_CHAIN_ALL_SUMMARY ghost=%d no_advance=%d dropped=%d"
		% [ghost_rooms.size(), no_advance.size(), dropped.size()])
	print("WAVE_CHAIN_ALL_DONE")
	get_tree().quit(0)
