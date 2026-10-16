extends Node
## 远征01 room_03「踩点触发式遭遇」专项验收。
##
## 盯业主 2026-10-16 那七条要求里**能被机器判死**的部分：
##   ① 进房时**没有**刷怪盒、也**不刷怪**（否则玩家没走到触发点房就被判清、门就开了）
##   ② 走到房间中心才启动；启动瞬间入口门扇落下、房间被封
##   ③ 落门后**隔 start_delay 秒**才出第一波
##   ④ **一波清完才出下一波**（stage_advance=clear）；两波之间房间**不判清**
##   ⑤ 计时到点后**不再开新波**（剩余阶段作废）
##   ⑥ 到点自动开灯（结果动作 `light`）
##   ⑦ 全部打完 ⇒ 房间肃清 + 解除封门
##   ⑧ **事件怪主动围向玩家**（`hunt_player`）：不靠视锥、不靠视线，是真的会走过来的
##   ⑨ **右上角倒计时环**（`hud_countdown`）：触发即出现、读数与事件 elapsed 同源、
##      事件终结后立即消失（不能留残影）
##   ⑩ **满宽带触发不可绕过**（`room_04`/`room_06`/`room_09`/`room_10`）：带子铺满房间
##      整根横轴 ⇒ 贴任一侧墙走过都要触发；并做一次**贴边横穿**的端到端走位验证
##
## 刻意**不**在这里测：每波具体怪种与数量的数值口径由
## `verify_expedition01_spawn_ramp` 的 `TRIGGER_EXPECTED_WAVES` 逐值钉住（那是数据契约），
## 这里只测**行为**——两者分开，改数值不会让行为断言假红。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_KEY := "room_03"
## ⑩ 改成满宽带的房间（含走位验证的那一间）。
const BAND_ROOM_KEYS: Array[String] = ["room_04", "room_06", "room_09", "room_10"]
const WALK_ROOM_KEY := "room_04"
## ⑪ 本关唯一的 EVENT 房（事件 + 战斗双职房）。
const EVENT_ROOM_KEY := "room_09"
## ⑫ `room_03` 的入口方向与对端房 —— 入口是**共享边**（门扇由对端持有），
## 封门必须跨房关它。见 `_check` 里关于「封门后拿不到门扇就是失败」的说明。
const ENTRY_SIDE := "west"
const ENTRY_PEER_KEY := "room_02"
const SEED_VALUE := 77001199

var failures: Array[String] = []
var samples := 0
var tower: TowerDescent3D


func _check(ok: bool, message: String) -> void:
	samples += 1
	if not ok:
		failures.append(message)


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var room := tower._room_by_id.get(ROOM_KEY) as DungeonRoom3D
	_check(room != null, "%s 在运行时不存在" % ROOM_KEY)
	if room == null:
		_finish()
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().physics_frame

	# ① 进房：不刷怪、不判清。玩家先站在房间**角落**（远离触发点），
	#    这样这一段的结论不会被触发逻辑顺带污染。
	var trigger_config := room.encounter.get("trigger", {}) as Dictionary
	_check(not trigger_config.is_empty(), "%s 没有 encounter.trigger" % ROOM_KEY)
	var radius := float(trigger_config.get("radius_m", 6.0))
	tower.player.global_position = room.global_position + Vector3(
		float(room.custom_dimensions.x * 0.5) - 2.0, 0.5, float(room.custom_dimensions.y * 0.5) - 2.0
	)
	tower.force_enter_room_for_test(ROOM_KEY)
	# **先把入口那条边打开**：玩家是从西边那扇门走进来的，那条边在真实游玩里已经是开的。
	# 不开边的话入口门本来就是关着的，下面「封门后门扇不能是开的」会**空过**
	# （门已经是关的 ⇒ 断言绿着，但封门逻辑其实坏着）。2026-10-16 的假绿就是这么来的。
	tower.force_open_edge_for_test(ENTRY_PEER_KEY, ROOM_KEY)
	await get_tree().process_frame
	await get_tree().process_frame
	var entry_leaf_before := room.get_door_node_towards(str(room.door_targets.get(ENTRY_SIDE, "")))
	_check(
		entry_leaf_before != null and entry_leaf_before.is_open,
		"前置条件不成立：进房后入口门不是「已打开」的状态（门扇=%s）⇒ 后面测不出封门失效"
			% str(entry_leaf_before)
	)
	_check(
		(tower._enemy_nodes_by_room.get(room.room_id, []) as Array).is_empty(),
		"进房就刷怪了（踩点遭遇房必须等触发）"
	)
	_check(int(tower._alive_by_room.get(room.room_id, 0)) == 0, "进房时存活账非 0")
	_check(not room.cleared, "进房就把房间判成已肃清（去路门会直接解锁）")
	_check(not tower._room_is_sealed(room.room_id), "还没触发就把房间封上了")
	_check(tower._hud_countdown_ring != null, "HUD 里没有遭遇倒计时环节点")
	_check(
		tower._hud_countdown_ring == null or not tower._hud_countdown_ring.visible,
		"还没触发就把倒计时环显示出来了"
	)

	# 位置在角落 ⇒ 站几帧也不该触发。
	for _frame in 4:
		await get_tree().process_frame
	_check(not tower._room_encounters_fired.has(room.room_id), "站在房间角落就触发了（半径过大）")

	# ② 走到房间中心 ⇒ 触发。
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(tower._room_encounters_fired.has(room.room_id), "走到房间中心没有触发")
	_check(tower._room_encounter_active.has(room.room_id), "触发后没有在跑的事件实例")
	_check(tower._room_is_sealed(room.room_id), "触发后没有封门（玩家可以原路走掉）")
	# 封门必须**真的把那扇门关上**，两件事都要查：
	#   ① `get_door_node_towards(target)` 必须拿得到门扇 —— 入口是**共享边**，门扇由对端
	#      （room_02）持有；若共享绑定没生效，本房这个方向**没有节点**。
	#   ② 拿到的那扇 `is_open` 必须是 false。
	#
	# ⚠ 旧写法是 `if door != null and door.is_open` —— **null 被静默当成通过**。
	# 2026-10-16 业主报「封门后还能从进来那扇门走出去」正是这个洞放过去的：
	# 入口门没绑进本房 ⇒ 循环里每个方向都 null 或已关 ⇒ 断言绿着，门却开着。
	# 「拿不到门扇」本身就是失败，必须显式报出来。
	var sealed_leaf_count := 0
	for direction_value in room.door_targets.keys():
		var direction := str(direction_value)
		var target := str(room.door_targets[direction_value])
		var leaf := room.get_door_node_towards(target)
		_check(
			leaf != null,
			"%s 的 %s 方向（->%s）封门后仍拿不到门扇 ⇒ 这扇门根本没被封上"
				% [room.room_id, direction, target]
		)
		if leaf == null:
			continue
		sealed_leaf_count += 1
		_check(
			not leaf.is_open,
			"%s 的 %s 方向（->%s）封门后门扇仍是开的" % [room.room_id, direction, target]
		)
	_check(
		sealed_leaf_count == room.door_targets.size(),
		"封门只覆盖了 %d/%d 扇门" % [sealed_leaf_count, room.door_targets.size()]
	)
	_check(
		not tower.get_interaction_candidate(tower.player).has("mode"),
		"封门期间仍给出门交互候选（玩家能按 E 开门）"
	)

	# ⑨ 触发瞬间 ⇒ 倒计时环出现，文字 = 总时长（`M:SS`）。
	#    两次 await 才保证中间跑过一帧 `_process`：`SceneTree.process_frame` 是
	#    **在** `_process` **之前**发出的，只 await 一次等于"还没刷新就读"。
	await get_tree().process_frame
	await get_tree().process_frame
	var ring := tower._hud_countdown_ring
	var expected_total := maxi(0, int(ceil(float(room.encounter.get("duration_sec", 60.0)))))
	_check(ring != null and ring.visible, "遭遇已触发但右上角倒计时环没显示")
	if ring != null:
		var ring_row := ring.get_snapshot()
		_check(
			str(ring_row.get("text", "")) == EncounterCountdownRing.format_time(expected_total),
			"倒计时环文字 %s ≠ 总时长对应的 %s"
			% [str(ring_row.get("text", "")), EncounterCountdownRing.format_time(expected_total)]
		)
		_check(
			float(ring_row.get("remaining_ratio", 0.0)) > 0.9,
			"刚触发时环就不是整圈：%s" % str(ring_row.get("remaining_ratio", 0.0))
		)

	var instance_id := str(tower._room_encounter_active.get(room.room_id, ""))
	_check(not instance_id.is_empty(), "事件实例 id 为空，后续断言无法进行")
	if instance_id.is_empty():
		_finish()
		return

	# ③ 落门后先等 start_delay，再出第一波。
	var delay := float(room.encounter.get("start_delay_sec", 1.0))
	tower._encounter_event_director.tick(maxf(0.05, delay - 0.3))
	_check(_spawned(instance_id) == 0, "还没到 start_delay 就出怪了")
	_check(_enemy_count(room) == 0, "延迟期内场上已有敌人")
	tower._encounter_event_director.tick(0.5)
	var wave_1 := _enemy_count(room)
	_check(wave_1 > 0, "过了 start_delay 仍没有出第一波")
	# 第一波的**编成签名**（怪种→只数）。第 ④ 段要拿它比第二波，
	# 见那里关于「比编成而不是比总数」的说明。
	var wave_1_signature := _wave_signature(room)
	_check(_stage_started(instance_id, 0), "第一波阶段未标记 started")
	_check(not _stage_started(instance_id, 1), "第一波还没清完，第二波就已经开始了")

	# ⑧ 事件猎杀：这一波怪必须**主动围向玩家**，而不是站在暗处等玩家撞上来。
	#    触发式遭遇是「把门落下来打完」，等同竞技场 —— 若还按野外潜行那套
	#    「要有视锥 + 视线才追」，关灯房里会有一半怪站原地不动。
	await get_tree().process_frame
	await get_tree().process_frame
	var hunters := _enemies(room)
	_check(not hunters.is_empty(), "猎杀断言：此时场上应有敌人")
	var stamped := 0
	var aware := 0
	for value in hunters:
		var enemy := value as Enemy3D
		if int(MonsterAIManager.get_enemy_snapshot(enemy).get("hunt_target_instance_id", 0)) == tower.player.get_instance_id():
			stamped += 1
		# 决策是**每帧缓存**的（`UPDATE_INTERVAL_MSEC`），这里强制重算再读，
		# 否则读到的是猎杀盖上之前的那一版。
		MonsterAIManager.force_refresh_enemy(enemy)
		if str(MonsterAIManager.get_enemy_snapshot(enemy).get("awareness", "")) == "hunt_contact":
			aware += 1
	_check(stamped == hunters.size(), "事件怪没有被盖上猎杀目标（%d/%d）" % [stamped, hunters.size()])
	_check(aware == hunters.size(), "事件怪的决策不是 hunt_contact（%d/%d）" % [aware, hunters.size()])

	# ⑨ 环的读数与事件 elapsed **同源**：容差 1 s（测试里手动 tick 过、`_process` 也在走），
	#    但绝不允许各记一份 —— 两处计时必然会漂，漂了之后没人知道该信哪个。
	if ring != null:
		var live := tower.get_encounter_event_snapshot(instance_id)
		var duration := maxf(0.001, float(room.encounter.get("duration_sec", 60.0)))
		var expected_remaining := duration - float(live.get("elapsed", 0.0))
		var showed := float(ring.get_snapshot().get("remaining_sec", -1.0))
		_check(
			absf(showed - expected_remaining) <= 1.0,
			"环上的剩余时间 %.2f 与事件 elapsed 推出来的 %.2f 差超过 1 s" % [showed, expected_remaining]
		)

	# ⑧ 真的会走过来：量「到玩家的距离」在若干物理帧后的变化。
	# 只要求"至少有一只明显靠近"，不要求全部 —— 已经在攻击距离内的、
	# 以及正在出招/被同伴挤开的，本来就不会继续缩短距离。
	var before := {}
	for value in hunters:
		var enemy := value as Enemy3D
		before[enemy.get_instance_id()] = enemy.global_position.distance_to(tower.player.global_position)
	for _frame in 120:
		await get_tree().physics_frame
	var closer := 0
	var engaged := 0
	for value in hunters:
		var enemy := value as Enemy3D
		if not is_instance_valid(enemy):
			continue
		var after := enemy.global_position.distance_to(tower.player.global_position)
		if after < float(before.get(enemy.get_instance_id(), after)) - 0.5:
			closer += 1
		if enemy.ai_state in ["alert", "chase", "telegraph", "attack", "recovery", "search"]:
			engaged += 1
	# 判据取 80% 而不是"全部"：出生点贴墙、被同伴挤住的个体不该让整条断言变红。
	# 阈值不是拍的 —— 同一场景下关掉 `hunt_player` 实测（120 物理帧 ≈ 2 s）：
	#
	#   | 猎杀 | 靠近 >0.5 m | 进交战态 | 最小靠近量 | 最远者剩余 |
	#   |  开  |    9/9      |   9/9    |  +2.34 m   |  16.73 m   |
	#   |  关  |    2/9      |   1/9    |  −0.17 m   |  21.22 m   |
	#
	# ⇒ 关掉之后**七只怪站着不动**（这正是业主说的"怪不围过来"），
	#   而 80% 与 22% / 11% 之间留着宽裕的判据带：不是"刚好卡过"，是两档。
	var needed := int(ceil(float(hunters.size()) * 0.8))
	_check(
		closer >= needed,
		"只有 %d/%d 只事件怪朝玩家靠近 ≥0.5 m（期望 ≥%d）—— 猎杀没落到行动上"
		% [closer, hunters.size(), needed]
	)
	_check(
		engaged >= needed,
		"只有 %d/%d 只事件怪进入交战状态（期望 ≥%d）—— 其余仍停在 idle/patrol"
		% [engaged, hunters.size(), needed]
	)

	# ④ 清完第一波 ⇒ 第二波才出；期间房间**不判清**。
	_clear_enemies(room)
	tower._encounter_event_director.tick(0.1)
	_check(_stage_started(instance_id, 1), "第一波清完后第二波没有开始")
	var wave_2 := _enemy_count(room)
	_check(wave_2 > 0, "第二波没有真的出怪")
	# 判「两波确实是不同编成」要**比编成本身，不能比总数**。
	# 2026-10-16 编成缩到 60% 后，`room_03` 第 1 波（胖1+小5）与第 2 波（胖1+小3+保2）
	# 的总数**正好都是 6** —— 旧断言（`wave_2 != wave_1`）因此误报。
	# 总量相同但组成不同是合法且常见的；反过来，两波组成完全一样才是真问题。
	_check(
		_wave_signature(room) != wave_1_signature,
		"两波编成完全相同（%s），第二波没换编成" % _wave_signature(room)
	)
	_check(not room.cleared, "波与波之间把房间判成已肃清（后续波次会被跳过）")
	_check(tower._room_is_sealed(room.room_id), "波与波之间把封门解开了")

	# ⑤ 计时到点：不再开新波，剩余阶段作废。
	var spawned_before_expiry := _spawned(instance_id)
	tower._encounter_event_director.tick(120.0)
	var snapshot := tower.get_encounter_event_snapshot(instance_id)
	_check(str(snapshot.get("status", "")) == "completed", "计时到点后事件状态不是 completed")
	_check(
		_spawned(instance_id) == spawned_before_expiry,
		"计时到点后仍在出怪（新波 %d → %d）" % [spawned_before_expiry, _spawned(instance_id)]
	)
	var dropped := int(snapshot.get("dropped", 0))
	_check(dropped > 0, "计时到点后有未开始的阶段却没记为作废（dropped=%d）" % dropped)
	_check(
		not tower._room_encounter_active.has(room.room_id),
		"事件已终结但 active 记账没清（房间永远判不清）"
	)
	# ⑨ 事件终结 ⇒ 环立即消失，不留残影。
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ring == null or not ring.visible, "事件已终结但倒计时环还挂着")

	# ⑥ 到点开灯。
	var light_applied := false
	for row_value in snapshot.get("result_actions", []) as Array:
		var row := row_value as Dictionary
		if str(row.get("type", "")) == "light" and bool(row.get("ok", false)):
			light_applied = true
	_check(light_applied, "到点开灯的 light 结果动作没有成功执行：%s" % str(snapshot.get("result_actions", [])))
	_check(room.is_room_light_on(), "到点后房间灯没有打开")

	# ⑦ 打完剩余怪 ⇒ 房间肃清 + 解封。
	var remaining := _enemies(room)
	_check(not remaining.is_empty(), "此时场上应仍有上一波的敌人")
	for index in remaining.size():
		var enemy := remaining[index] as Enemy3D
		if not is_instance_valid(enemy):
			continue
		if index < remaining.size() - 1:
			enemy.free()
			tower._enemy_nodes_by_room[room.room_id] = _live_refs(room)
			tower._alive_by_room[room.room_id] = maxi(
				0, int(tower._alive_by_room.get(room.room_id, 1)) - 1
			)
			continue
		# 最后一只走**真实击杀链**，让 `_resolve_room_enemy_departure` 真正跑到。
		tower._on_enemy_killed(enemy, enemy.get_enemy_data())
	await get_tree().process_frame
	_check(room.cleared, "清完所有怪后房间仍未肃清")
	_check(not tower._room_is_sealed(room.room_id), "肃清后封门没有解除（玩家出不去）")

	# ⓑ 解封后**入口门必须能从房内再开**（别把玩家锁成单向门）。
	# 入口是共享边、门扇在对端手里：只有共享绑定生效、本房 `_door_nodes` 里有这扇门，
	# `get_nearest_door()`（只遍历 `_door_nodes`）才找得到它，交互候选才会出现。
	# 这是"共享门绑定"的第二个可观测后果，漏了会变成「进来能进、回去不能回」。
	await get_tree().process_frame
	await get_tree().process_frame
	var entry_target := str(room.door_targets.get(ENTRY_SIDE, ""))
	_check(not entry_target.is_empty(), "%s 没有 %s 方向的入口" % [room.room_id, ENTRY_SIDE])
	var entry_leaf := room.get_door_node_towards(entry_target)
	_check(
		entry_leaf != null,
		"解封后仍拿不到入口门扇（%s -> %s）⇒ 玩家从房里走不回去" % [room.room_id, entry_target]
	)
	if entry_leaf != null:
		# 站到入口门前，交互候选必须给出这扇门。
		tower.player.global_position = entry_leaf.global_position + Vector3(0.0, 0.5, 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var candidate := tower.get_interaction_candidate(tower.player)
		_check(
			str(candidate.get("mode", "")) == "room_door",
			"站在入口门前没有门交互候选（候选=%s）⇒ 入口在房内开不了" % str(candidate)
		)

	# ⚠ 必须 `await`：本函数内部有 `await` ⇒ 它是协程。不 await 的话它跑到第一个
	# `await` 就返回，后面的断言**一条都不会执行**，而测试照样打印 OK —— 假绿。
	await _verify_band_rooms()
	await _verify_event_room_trigger_combat()

	_finish()


## ⑩ 满宽带触发：`room_04` / `room_06` / `room_09` / `room_10`。
##
## 业主口径：「这些区域都要横向铺开，不要让玩家可以绕开」。圆的半径再大也能贴墙绕过去，
## 所以这四房改成**满宽带**：沿一根房间局部轴铺满整个跨度，另一根轴上只有 6 m 厚。
##
## 分两层验：
##   · **判定层**（四房都做）：直接用运行时真正调用的那个判定
##     `_room_encounter_trigger_contains`，在**横向两侧贴边**处取点 ⇒ 必须命中。
##     这一层是"不可绕过"的决定性证据 —— 贴边都命中，中间更没有缝。
##   · **走位层**（`room_04` 做一次）：真的让玩家贴着侧墙从入口侧走到出口侧，
##     断言"带前不触发、进带才触发"。判定层证明了几何，这一层证明它**真的被轮询到**。
func _verify_band_rooms() -> void:
	# 走位要能真的启动事件：先确认玩家活着（上一步的猎杀段落里怪打过他）。
	if is_instance_valid(tower) and tower.player != null:
		tower.player.current_hp = tower.player.max_hp
	var band_checked := 0
	for key in BAND_ROOM_KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		_check(room != null, "带状触发房 %s 在运行时不存在" % key)
		if room == null:
			continue
		var trigger := room.encounter.get("trigger", {}) as Dictionary
		_check(
			str(trigger.get("shape", "")) == "band",
			"%s 触发形状不是 band（%s）⇒ 仍是圆，玩家能贴墙绕过" % [key, str(trigger.get("shape", "<无>"))]
		)
		var thickness := float(trigger.get("thickness_m", 0.0))
		_check(thickness > 0.0, "%s 带子厚度非正：%s" % [key, str(thickness)])
		# `axis` 是**铺满**的那根轴；`thin` 是厚度所在的那根轴。
		var dimensions := room.get_dimensions()
		var span_is_z := str(trigger.get("axis", "")) == "z"
		var cross_extent := dimensions.y if span_is_z else dimensions.x
		var thin_extent := dimensions.x if span_is_z else dimensions.y
		# 横向两侧贴边（留 0.4 m 余量，避开墙面本身的厚度）：都必须在带内。
		for side_value in [1.0, -1.0]:
			# `side_value` 来自无类型数组 ⇒ 是 Variant，必须显式转 float，
			# 否则 `:=` 推断撞项目「警告即错误」。
			var lateral := float(side_value) * (cross_extent * 0.5 - 0.4)
			var probe := Vector3(0.0, 0.0, lateral) if span_is_z else Vector3(lateral, 0.0, 0.0)
			_check(
				tower._room_encounter_trigger_contains(room, room.to_global(probe)),
				"%s 横向贴边处（%s=%.1f）不在触发带内 ⇒ 玩家贴这侧墙就能绕过去"
					% [key, "z" if span_is_z else "x", lateral]
			)
		# 带外一点（厚度轴外侧 1 m）：必须在带外，否则退化成"整间都是触发区"。
		var outside := Vector3(0.0, 0.0, 0.0)
		if span_is_z:
			outside = Vector3(thickness * 0.5 + 1.0, 0.0, 0.0)
		else:
			outside = Vector3(0.0, 0.0, thickness * 0.5 + 1.0)
		_check(
			not tower._room_encounter_trigger_contains(room, room.to_global(outside)),
			"%s 带外 1 m 处也被判成触发区内 ⇒ 带子厚到吃掉了通行距离" % key
		)
		# 带子厚度必须小于房间的通行跨度，否则一进门就在带里。
		_check(
			thickness < thin_extent,
			"%s 带子厚度 %.1f ≥ 房间通行跨度 %.1f ⇒ 退化成「进房即触发」"
				% [key, thickness, thin_extent]
		)
		band_checked += 1
	_check(band_checked == BAND_ROOM_KEYS.size(), "带状触发房只查了 %d 间" % band_checked)

	# —— 走位层：`room_04` 贴侧墙横穿 ——
	# room_04 的运行时朝向：西墙进（-x）、北墙出（-z），带子铺满 z、薄在 x、位于房心。
	# 所以"贴边横穿"= 在 z 取靠边的一行，从 x 负侧走到正侧。
	var walk_room := tower._room_by_id.get(WALK_ROOM_KEY) as DungeonRoom3D
	if walk_room == null:
		_check(false, "%s 在运行时不存在，走位验证无法进行" % WALK_ROOM_KEY)
		return
	var walk_trigger := walk_room.encounter.get("trigger", {}) as Dictionary
	_check(
		str(walk_trigger.get("axis", "")) == "z",
		"%s 带子不铺满 z 轴 ⇒ 走位脚本的假设（西进北出、薄在 x）不成立" % WALK_ROOM_KEY
	)
	var walk_dims := walk_room.get_dimensions()
	var walk_thickness := float(walk_trigger.get("thickness_m", 6.0))
	# 贴 z 的一侧：这是"玩家贴墙绕行"的最坏情况。
	var edge_z := walk_dims.y * 0.5 - 0.6
	var before_x := -(walk_thickness * 0.5 + 1.2)
	var after_x := walk_thickness * 0.5 + 1.2
	tower.player.global_position = walk_room.to_global(Vector3(before_x, 0.5, edge_z))
	tower.force_enter_room_for_test(WALK_ROOM_KEY)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		not tower._room_encounters_fired.has(walk_room.room_id),
		"%s 贴边站在带外就触发了 ⇒ 带子比设定的厚" % WALK_ROOM_KEY
	)
	# 沿 x **逐步走过**带子（全程贴着 z 的同一侧墙）。
	# ⚠ 不能直接瞬移到带外另一侧：判定只问"当前是否在带内"，瞬移会**跳过**带子，
	# 于是这次走位什么都没证明（第一版就是这么写错的，红得很对）。
	var fired_at_x := INF
	var step := 0.4
	var x := before_x
	while x <= after_x + 0.001:
		tower.player.global_position = walk_room.to_global(Vector3(x, 0.5, edge_z))
		await get_tree().process_frame
		if tower._room_encounters_fired.has(walk_room.room_id):
			fired_at_x = x
			break
		x += step
	_check(
		fired_at_x <= walk_thickness * 0.5 + 0.001,
		"%s 贴着侧墙横穿触发带却没触发（最近走到 x=%.2f，带子是 |x|≤%.2f）⇒ 玩家可以贴墙绕开"
			% [WALK_ROOM_KEY, fired_at_x, walk_thickness * 0.5]
	)
	_check(
		tower._room_is_sealed(walk_room.room_id),
		"%s 贴边横穿触发了但没封门" % WALK_ROOM_KEY
	)


## ⑪ `room_09` 是**事件房**（`room_type == EVENT`）——踩点遭遇必须被认成"编排战斗"。
##
## 这一条是本轮实际抓到的回归：`_event_room_has_authored_combat()` 旧判据只看
## `spawn_placements` 是否非空。room_09 改踩点遭遇后盒子清空 ⇒ 判据 false ⇒
## `_on_room_entered` 的 EVENT 分支不调 `_spawn_room_enemies()`、`_event_combat_rooms`
## 不登记 ⇒ **事件终端一结算就 `_mark_room_cleared()`，敌群还在场上门就开了**。
## 所以这里必须同时钉住「判据为真」与「进房后登记成立」两件事，
## 光测「遭遇能不能跑起来」是抓不到的。
func _verify_event_room_trigger_combat() -> void:
	var room := tower._room_by_id.get(EVENT_ROOM_KEY) as DungeonRoom3D
	_check(room != null, "%s 在运行时不存在" % EVENT_ROOM_KEY)
	if room == null:
		return
	_check(
		room.room_type == "EVENT",
		"%s 房型是 %s 而不是 EVENT ⇒ 本段验证的前提不成立" % [EVENT_ROOM_KEY, room.room_type]
	)
	_check(
		tower._event_room_has_authored_combat(room),
		"%s 带踩点遭遇却被判成「没有编排战斗」⇒ 会被当成纯事件房：事件一结算就放行，敌群还活着"
			% EVENT_ROOM_KEY
	)
	# 真的走一遍进房：EVENT 分支必须把本房登记成「带战斗的事件房」，且**进房不刷怪**。
	tower.player.global_position = room.to_global(Vector3(0.0, 0.5, 0.0))
	tower.force_enter_room_for_test(EVENT_ROOM_KEY)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		tower._event_combat_rooms.has(room.room_id),
		"%s 进房后没登记进 `_event_combat_rooms` ⇒ 事件结算不会等敌群清空" % EVENT_ROOM_KEY
	)
	_check(
		(tower._enemy_nodes_by_room.get(room.room_id, []) as Array).is_empty(),
		"%s 是踩点遭遇房，进房就刷怪了" % EVENT_ROOM_KEY
	)
	_check(
		not room.cleared,
		"%s 进房就被判成已肃清 ⇒ 去路门会立刻解锁，触发也没意义" % EVENT_ROOM_KEY
	)


func _finish() -> void:
	if is_instance_valid(tower):
		tower.queue_free()
	if failures.is_empty():
		print("ENCOUNTER_TRIGGER_ROOM_OK samples=%d" % samples)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _spawned(instance_id: String) -> int:
	return int(tower.get_encounter_event_snapshot(instance_id).get("spawned", -1))


func _stage_started(instance_id: String, index: int) -> bool:
	var stages := tower.get_encounter_event_snapshot(instance_id).get("stage_states", []) as Array
	if index >= stages.size():
		return false
	return bool((stages[index] as Dictionary).get("started", false))


func _live_refs(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		if is_instance_valid(value) and not (value as Node).is_queued_for_deletion():
			out.append(value)
	return out


func _enemies(room: DungeonRoom3D) -> Array:
	return _live_refs(room)


func _enemy_count(room: DungeonRoom3D) -> int:
	return _live_refs(room).size()


## 当前场上敌人的**编成签名**：`怪种:只数` 按怪种名排序后用 `|` 连接。
##
## 为什么需要它：要证明"第二波确实是另一套编成"，**只能比组成**。
## 比总数是个弱代理 —— 2026-10-16 编成缩到 60% 后，`room_03` 第 1 波（胖1+小5）
## 与第 2 波（胖1+小3+保2）总数**正好都是 6**，旧断言因此误报"第二波没换编成"。
## 反过来，真出问题时（两波组成一致）本签名会逐字相同，照样抓得住。
func _wave_signature(room: DungeonRoom3D) -> String:
	var tally := {}
	for value in _live_refs(room):
		var enemy := value as Enemy3D
		if enemy == null:
			continue
		var kind := str(enemy.enemy_kind)
		tally[kind] = int(tally.get(kind, 0)) + 1
	var kinds := tally.keys()
	kinds.sort()
	var parts: Array[String] = []
	for kind_value in kinds:
		var kind := str(kind_value)
		parts.append("%s:%d" % [kind, int(tally[kind])])
	return "|".join(parts)


## 只清「已落地」的敌人；在途（预约 / 延迟）不动 —— 它们不该被当成已出的波。
func _clear_enemies(room: DungeonRoom3D) -> void:
	for value in _live_refs(room):
		(value as Node).free()
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._alive_by_room[room.room_id] = 0
