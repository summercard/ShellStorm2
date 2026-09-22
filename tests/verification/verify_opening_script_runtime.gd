extends Node3D
## 开场剧本的**真机**验收：在真实塔楼场景 + 真实开场页上跑，盯四个真机缺陷。
##
## 为什么只靠 verify_narrative_timeline 不够：那条用例跑在"假玩家 + 假相机"的最小世界上，
## 而四个真机缺陷全部出在「剧情 × 开场页 × 玩家」的三方争用里；并且
## `TowerDescent3D._install_main_entry_screen()` 在 `test_mode / headless` 下**直接 return**，
## 普通探针根本看不到开场页 —— 这正是四个缺陷当初从验收网里漏掉的原因。
## 本文件把开场页实例**提前**塞进塔楼自己的 `_main_entry_screen` 字段，于是塔楼会走它自己的
## `_defer_gameplay_started()` **真接线**，时序与冷启动逐帧一致：
##   开场页 present()（锁输入、钉近景） → 点开始 → 转场 1.15s → transition_finished
##   → gameplay_started → 开场剧本起跑 → 收口归还。
##
## 四个缺陷 ⇄ 判据：
##   ① 开场就该锁死操作     → 演出全程逐帧断言 `input_locked == true`，违例数必须为 0
##   ② 镜头要从上往下压     → 逐帧测相机俯角，降幅必须够、且落到剧本写的角度
##   ③ 中间不许错乱         → 剧情起跑前不得播放（挂 room_entered 会在这里就空跑的反向对照）；
##                            收口后朝向占用必须释放（鼠标不再被让位逻辑挡掉）
##   ④ 收工要交回键盘与开枪 → 收口后 input_locked=false，且 `_tick_shoot_input` 的四道闸门全通
##
## 防假绿：打印采样帧数（要求 >= 300）；② 的反向对照是老实现（只改距离）实测降幅 0.0°。
##
## 运行：godot --headless --path . res://tests/verification/verify_opening_script_runtime.tscn

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const ENTRY_SCENE := "res://scenes/ui/MainEntryScreen3D.tscn"
const YIELD_SCRIPT_ID := "test_opening_entry_yield"
const WAKE_ID := "nar_tower_opening_01_wake"
const OPENING_ROOM_ID := "floor_01_exit"
## 第二段：位置触发的真实几何校验用它。
const ZOMBIES_ID := "nar_tower_opening_02_zombies"
const ZOMBIES_ROOM_ID := "floor_01_main_02"
## 98F 区块00 四房（和平区）：门策略必须三项全放行，否则每扇门都要清房+钥匙。
const BLOCK00_ROOM_IDS: Array[String] = [
	"floor_01_entry", "floor_01_hub", "floor_01_main_02", "floor_01_exit",
]
const SEED := 990098

const BOOT_TIMEOUT_MS := 30000
const START_TIMEOUT_MS := 30000
const FINISH_TIMEOUT_MS := 60000

## `play()` 与首帧派发之间可能隔一帧；从第 0 帧就数会把"还没轮到派发"误判成"没锁住"。
const SAMPLING_WARMUP_FRAMES := 2
## 俯角必须真降下来才算"从上往下压"。老实现（只改距离）实测降幅 0.0°。
const MIN_ELEVATION_DROP_DEG := 20.0
## 开场剧本 14.7s，60fps 约 880 帧。低于这个数说明探针没真跑到收场。
const MIN_SAMPLE_FRAMES := 300
## 俯角到达剧本目标值的容差（度）。
const ELEVATION_TOLERANCE_DEG := 3.0
## 开场页近景机位的固定俯角 = atan2(CLOSEUP_HEIGHT_M 1.42, CLOSEUP_DISTANCE_M 3.10)。
## 用来做"谁赢了相机"的对照：让位失效时相机就会停在这个角度，而不是叙事角度。
const CLOSEUP_ELEVATION_DEG := 24.6
## 让位用例里叙事镜头要压到的俯角。
const YIELD_TARGET_ELEVATION_DEG := 30.0

var _tower: TowerDescent3D = null
var _entry: CanvasLayer = null
var _player: Player3D = null
var _failures: Array[String] = []
var _checks := 0
var _notes: Array[String] = []


func _ready() -> void:
	await _boot()
	if _tower == null or _player == null or _entry == null:
		return
	_phase_a_before_start()
	await _phase_b_runtime()
	_phase_c_handback()
	await _phase_d_entry_camera_yield()
	_phase_e_zombie_trigger_geometry()
	_phase_f_block00_door_policies()
	_phase_g_opening_room_light()
	_report()


# =========================================================================
# 搭台：真实塔楼 + 真实开场页 + 塔楼自己的 gameplay_started 接线
# =========================================================================

func _boot() -> void:
	var tower_packed := load(TOWER_SCENE) as PackedScene
	if tower_packed == null:
		_fatal("塔楼场景加载失败：%s" % TOWER_SCENE)
		return
	var entry_packed := load(ENTRY_SCENE) as PackedScene
	if entry_packed == null:
		_fatal("开场页场景加载失败：%s" % ENTRY_SCENE)
		return
	_tower = tower_packed.instantiate() as TowerDescent3D
	if _tower == null:
		_fatal("塔楼场景根不是 TowerDescent3D")
		return
	_tower.test_mode = true
	_tower.run_seed_override = SEED
	_tower.force_new_game_opening_for_test = true
	_entry = entry_packed.instantiate() as CanvasLayer
	if _entry == null:
		_fatal("开场页场景根不是 CanvasLayer")
		return
	# 关键一行：把开场页实例提前塞进塔楼自己的字段。test_mode 下
	# `_install_main_entry_screen()` 会早退（不会覆盖它），于是 `_defer_gameplay_started()`
	# 走"连 transition_finished"的真接线，而不是 call_deferred 立刻发。
	# 这一行就是本探针与冷启动时序等价的原因。
	_tower.set("_main_entry_screen", _entry)
	add_child(_tower)
	add_child(_entry)

	var deadline := Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		_player = get_tree().get_first_node_in_group("player_3d") as Player3D
		if _player != null and bool(_entry.get("_presenting")):
			break
		await get_tree().process_frame
	if _player == null:
		_fatal("30s 内没等到玩家入分组 player_3d")
		return
	if not bool(_entry.get("_presenting")):
		_fatal("开场页 30s 内没有 present()（本探针的时序前提不成立）")
		return
	_check(
		str(_tower.get("_current_room_id")) == OPENING_ROOM_ID,
		"冷启动落点是 %s（实际 %s）" % [OPENING_ROOM_ID, str(_tower.get("_current_room_id"))],
	)


# =========================================================================
# A 点开始之前：剧情不许已经在跑
# =========================================================================

func _phase_a_before_start() -> void:
	print("[A] 点开始之前：剧情不许起跑（挂 room_entered 的反向对照）")
	_check(bool(_entry.get("_presenting")), "开场页正在接管相机与输入（复刻冷启动）")
	_check(
		not NarrativeDirector.is_playing(),
		"开场页还在时剧情未起跑 —— 挂 room_entered 会在这里就空跑（缺陷①③的根因）",
	)
	print("  >>> 模拟点击「开始」（转场 1.15s）")
	_entry.call("start_game")


# =========================================================================
# B 真机运行：全程锁输入 + 相机俯冲
# =========================================================================

func _phase_b_runtime() -> void:
	print("[B] 真机运行：演出全程锁输入 + 相机从上往下压")
	var deadline := Time.get_ticks_msec() + START_TIMEOUT_MS
	while not NarrativeDirector.is_playing() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not NarrativeDirector.is_playing():
		_fatal("点开始后 30s 内开场剧本仍未起跑（gameplay_started 触发链断了）")
		return
	_check(
		NarrativeDirector.active_id() == WAKE_ID,
		"点开始后起跑的是 %s（实际 %s）" % [WAKE_ID, NarrativeDirector.active_id()],
	)

	var samples := 0
	var lock_violations := 0
	var first_violation := -1
	var elev_first := NAN
	var elev_min := NAN
	deadline = Time.get_ticks_msec() + FINISH_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		# 先确认"这一帧还在演"再计数：收口是上一帧导演 _process 里做的，
		# 那一帧的输入已被**正确归还**，算进来就成了探针自己的差一错。
		if not NarrativeDirector.is_playing():
			break
		samples += 1
		if samples <= SAMPLING_WARMUP_FRAMES:
			continue
		if not _player.input_locked:
			lock_violations += 1
			if first_violation < 0:
				first_violation = samples
		var elevation := _camera_elevation_deg()
		if not is_nan(elevation):
			if is_nan(elev_first):
				elev_first = elevation
			elev_min = elevation if is_nan(elev_min) else minf(elev_min, elevation)

	_check(not NarrativeDirector.is_playing(), "开场剧本已收场（没有被卡住）")
	_check(
		samples >= MIN_SAMPLE_FRAMES,
		"采样帧数 %d >= %d（防假绿：没跑到收场就不算过）" % [samples, MIN_SAMPLE_FRAMES],
	)
	_check(
		lock_violations == 0,
		"演出全程玩家输入被锁死：违例 %d / %d 帧（首个违例在第 %s 帧）"
		% [lock_violations, samples, str(first_violation)],
	)
	_check(
		not is_nan(elev_first) and not is_nan(elev_min),
		"采到相机俯角（首帧 %.1f°、最低 %.1f°）" % [elev_first, elev_min],
	)
	if not is_nan(elev_first) and not is_nan(elev_min):
		_check(
			elev_first - elev_min >= MIN_ELEVATION_DROP_DEG,
			"镜头真的从上往下压：俯角 %.1f° → %.1f°（降幅 %.1f°，要求 >= %.1f°）"
			% [elev_first, elev_min, elev_first - elev_min, MIN_ELEVATION_DROP_DEG],
		)
		var target := _scripted_elevation_deg(WAKE_ID)
		_check(not is_nan(target), "剧本 %s 里写了 elevation_deg" % WAKE_ID)
		if not is_nan(target):
			_check(
				absf(elev_min - target) <= ELEVATION_TOLERANCE_DEG,
				"俯角到达剧本写的 %.1f°（实测最低 %.1f°）" % [target, elev_min],
			)
	_note("B 采样 %d 帧；俯角首帧 %.1f° → 最低 %.1f°" % [samples, elev_first, elev_min])
	print("  dispatch_log=%s" % str(NarrativeDirector.dispatch_log()))


# =========================================================================
# C 收口归还：输入 / 相机 / 朝向 / 开枪门
# =========================================================================

func _phase_c_handback() -> void:
	print("[C] 收口归还：输入 / 相机 / 朝向 / 开枪门")
	_check(not _player.input_locked, "收口后玩家输入真的解锁（缺陷①④）")
	_check(not NarrativeDirector.is_player_input_locked(), "收口后导演交回输入独占权")
	_check(not NarrativeDirector.is_camera_override_active(), "收口后相机归还玩法镜头")
	_check(not _player.is_invincible, "收口后受击免疫归还")
	_check(
		not bool(NarrativeDirector.is_actor_facing_overridden()),
		"收口后朝向占用释放（缺陷③：鼠标瞄准不再被让位逻辑挡掉）",
	)
	# 「不能开枪」的直接判据就是 `_tick_shoot_input` 的那几道闸门，逐个断言。
	_check(_player.current_hp > 0, "开枪闸门 1/4：角色未阵亡（hp=%d）" % _player.current_hp)
	_check(_player.get("weapon") != null, "开枪闸门 2/4：手上有武器")
	_check(_player.combat_enabled, "开枪闸门 3/4：combat_enabled 已开")
	_check(
		not bool(_player.call("_narrative_holds_aim")),
		"开枪闸门 4/4：鼠标瞄准不被剧情让位",
	)
	var log_lines := NarrativeDirector.dispatch_log()
	var last_line := "<空>"
	if not log_lines.is_empty():
		last_line = str(log_lines[log_lines.size() - 1])
	_check(last_line == "finish:flow.end", "收口原因是 flow.end（末条 %s）" % last_line)
	_check(
		NarrativeDirector.diagnostics().is_empty(),
		"全程零诊断（%s）" % str(NarrativeDirector.diagnostics()),
	)


# =========================================================================
# D 两个系统抢同一台相机：让位查询必须挡住开场页
# =========================================================================

func _phase_d_entry_camera_yield() -> void:
	print("[D] 开场页 × 叙事镜头争用：开场页必须让位")
	var script := NarrativeScript3D.from_dictionary({
		"narrative_id": YIELD_SCRIPT_ID,
		"schema_version": 1,
		"duration": 6.0,
		"cues": [
			{"at": 0.0, "do": "player.lock_input", "locked": true},
			{
				"at": 0.0, "do": "camera.focus", "distance": 6.0,
				"elevation_deg": YIELD_TARGET_ELEVATION_DEG, "duration": 0.05,
			},
			{"at": 6.0, "do": "flow.end"},
		],
	})
	NarrativeDirector.register_script_for_test(YIELD_SCRIPT_ID, script)
	if not NarrativeDirector.play(YIELD_SCRIPT_ID, {"priority": 99}):
		_fatal("让位用例：剧情没能开始播放")
		return
	await _wait_frames(5)
	_check(
		bool(_entry.call("_narrative_holds_presentation")),
		"开场页认出了叙事持有镜头/输入（让位查询已接线）",
	)
	var narrative_elev := _camera_elevation_deg()
	# 剧情正在演的时候硬把开场页 present 起来 —— 这正是真机里两个系统互抢的场面。
	_entry.call("present", _player)
	await _wait_frames(5)
	var after := _camera_elevation_deg()
	_check(
		absf(after - YIELD_TARGET_ELEVATION_DEG) <= ELEVATION_TOLERANCE_DEG,
		"让位挡住了抢镜：相机仍在叙事俯角 %.1f°（近景机位是 %.1f°）"
		% [after, CLOSEUP_ELEVATION_DEG],
	)
	_check(
		absf(after - narrative_elev) <= ELEVATION_TOLERANCE_DEG,
		"让位期间叙事机位没被顶掉（让位前 %.1f° → 让位后 %.1f°）" % [narrative_elev, after],
	)
	_note("D 让位前 %.1f° → 让位后 %.1f°（近景机位 %.1f°）" % [narrative_elev, after, CLOSEUP_ELEVATION_DEG])
	NarrativeDirector.abort("d_cleanup")
	await _wait_frames(2)


# =========================================================================
# 量测与断言
# =========================================================================

## 相机相对玩家的实际俯角（度）。运镜有没有真的"从上往下压"，只能看这个量。
func _camera_elevation_deg() -> float:
	if _player == null or _player.camera == null or not is_instance_valid(_player.camera):
		return NAN
	var offset := _player.camera.global_position - _player.global_position
	var planar := Vector2(offset.x, offset.z).length()
	if planar <= 0.0001:
		return NAN
	return rad_to_deg(atan2(offset.y, planar))


## 剧本里显式声明的俯角（最后一条带 elevation_deg 的运镜 cue）。没写返回 NAN。
func _scripted_elevation_deg(narrative_id: String) -> float:
	var script := NarrativeScript3D.load_from_id(narrative_id)
	if script == null:
		return NAN
	var found := NAN
	for cue in script.cues:
		if not str(cue.get("do", "")).begins_with("camera."):
			continue
		if cue.has("elevation_deg"):
			found = float(cue.get("elevation_deg", 0.0))
	return found


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures.append(label)
		push_error("OPENING_SCRIPT_RUNTIME_FAIL: %s" % label)


func _note(message: String) -> void:
	_notes.append(message)
	print("  note %s" % message)


func _fatal(message: String) -> void:
	_checks += 1
	_failures.append(message)
	push_error("OPENING_SCRIPT_RUNTIME_FAIL: %s" % message)
	_report()


## 第二段触发器是**房间相对**的（`point_room` + `point_offset`）。假世界只能验证算术；
## 这里在**真机几何**上验：解出来的点必须落在会议室内部、且**不在**玩家上一个房间（办公室）里
## —— 证明「必须真的走进房间、门关上之后才触发」这条约束在真实楼层上成立。
func _phase_e_zombie_trigger_geometry() -> void:
	var rooms: Variant = _tower.get("_room_by_id")
	if not (rooms is Dictionary):
		_check(false, "拿不到塔楼房间表（本段几何校验无法进行）")
		return
	var room := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D
	_check(room != null, "98F 存在房间 %s" % ZOMBIES_ROOM_ID)
	if room == null:
		return
	var origin: Variant = NarrativeDirector.point_origin_for_test(ZOMBIES_ID)
	_check(origin is Vector3, "第二段的位置触发原点可解析（房间相对写法）")
	if not (origin is Vector3):
		return
	var point := origin as Vector3
	_check(
		room.contains_world_position(point),
		"触发点落在会议室**内部**（world=%.1f, %.1f, %.1f）" % [point.x, point.y, point.z],
	)
	var office := (rooms as Dictionary).get(OPENING_ROOM_ID) as DungeonRoom3D
	if office != null:
		_check(
			not office.contains_world_position(point),
			"触发点**不在**办公室内（玩家必须真的走进会议室才触发）",
		)
	_note(
		"E 第二段触发点 = (%.1f, %.1f, %.1f)；会议室中心 = (%.1f, %.1f, %.1f)"
		% [
			point.x, point.y, point.z,
			room.global_position.x, room.global_position.y, room.global_position.z,
		]
	)


## 98F 区块00 是**和平区**：门只做普通开关（不清房 / 不要钥匙 / 不弹命运卡）。
## 这里在真机上验门策略真的全放行了 —— 老实现门开启走的是硬编码默认策略，
## 那句「门只做普通开关」是空承诺（人报「98 层每个房间都有钥匙」）。
func _phase_f_block00_door_policies() -> void:
	var rooms: Variant = _tower.get("_room_by_id")
	if not (rooms is Dictionary):
		_check(false, "拿不到塔楼房间表（门策略校验无法进行）")
		return
	var checked := 0
	var leaked := 0
	for room_id in BLOCK00_ROOM_IDS:
		var room := (rooms as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			continue
		checked += 1
		_check(
			room.authored_layout_peaceful,
			"%s 带和平区标记（否则门策略会退回默认）" % room_id,
		)
		var policies: Dictionary = room.door_policies
		for direction in policies.keys():
			var policy: Dictionary = policies[direction]
			if (
				bool(policy.get("requires_clear", true))
				or bool(policy.get("requires_key", true))
				or bool(policy.get("triggers_fate", true))
			):
				leaked += 1
		_check(
			leaked == 0,
			"%s 门策略全放行（实际有 %d 个方向仍要清房/钥匙/命运卡）" % [room_id, leaked],
		)
	_check(checked == BLOCK00_ROOM_IDS.size(), "四房全部在本层（实际 %d）" % checked)
	# 关键：门**开启路径**读到的策略必须也是放行的（老 bug 就出在这一跳）。
	for room_id in BLOCK00_ROOM_IDS:
		var room := (rooms as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			continue
		for direction in room.door_targets.keys():
			var neighbour := str(room.door_targets[direction])
			if neighbour.is_empty():
				continue
			var policy: Dictionary = _tower.call("_door_policy_towards", room_id, neighbour)
			_check(
				not bool(policy.get("requires_clear", true))
				and not bool(policy.get("requires_key", true))
				and not bool(policy.get("triggers_fate", true)),
				"%s → %s 的开门策略放行（老 bug：这一跳读的是硬编码默认）"
				% [room_id, neighbour],
			)


	# 源码级守卫：门**开启路径**必须走 `_door_policy_towards`（会读房间声明的策略）。
	# 退回 `_door_policy_for_edge` 就是那个「98F 每扇门都要钥匙」的老 bug —— 运行时零报错，
	# 只有人报才会发现，所以必须能断言。
	var d3_source := FileAccess.get_file_as_string("res://src/world3d/Dungeon3D.gd")
	var open_marker := "func _try_open_room_door(target_room_id: String) -> bool:"
	var open_start := d3_source.find(open_marker)
	_check(open_start >= 0, "Dungeon3D 有 _try_open_room_door（开门路径）")
	if open_start >= 0:
		var open_body := d3_source.substr(open_start, 900)
		_check(
			open_body.contains("_door_policy_towards("),
			"开门路径读房间声明的门策略（老 bug：读硬编码默认 ⇒ 98F 每扇门都要钥匙）",
		)


## 开局第一间房（主人办公室 `floor_01_exit`）的灯必须**默认打开** ——
## 玩家在开场演出里一睁眼不该是黑的。会议室仍是默认关（反向对照：不是全层都开）。
## 顺带把「第二段刷怪点」也按声明在真机上验一遍几何（房间相对锚点解出来必须落在房内）。
func _phase_g_opening_room_light() -> void:
	var rooms: Variant = _tower.get("_room_by_id")
	if not (rooms is Dictionary):
		_check(false, "拿不到塔楼房间表（灯与刷怪点校验无法进行）")
		return
	var office := (rooms as Dictionary).get(OPENING_ROOM_ID) as DungeonRoom3D
	_check(office != null, "有办公室房 %s" % OPENING_ROOM_ID)
	if office != null:
		_check(office.authored_room_light_on, "办公室声明了「灯默认开」")
		_check(office.is_room_light_on(), "办公室的灯**确实亮着**（开局不该是黑的）")
	var meeting := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D
	if meeting != null:
		_check(
			not meeting.is_room_light_on(),
			"会议室仍默认关灯（反向对照：不是全层都点亮）",
		)
	var zombies := NarrativeScript3D.load_from_id(ZOMBIES_ID)
	if zombies == null:
		return
	for cue in zombies.cues:
		if str(cue.get("do", "")) != "scene.spawn":
			continue
		if str(cue.get("point_room", "")) != ZOMBIES_ROOM_ID:
			continue
		var offset_raw: Variant = cue.get("point_offset", null)
		var room := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D
		if room == null or not (offset_raw is Array) or (offset_raw as Array).size() != 3:
			continue
		var off: Array = offset_raw
		var spawn_point := room.to_global(Vector3(float(off[0]), float(off[1]), float(off[2])))
		_check(
			room.contains_world_position(spawn_point),
			"第二段刷怪点落在会议室内部（world=%.1f, %.1f, %.1f）"
			% [spawn_point.x, spawn_point.y, spawn_point.z],
		)
		_note(
			"G 刷怪点 = (%.1f, %.1f, %.1f)" % [spawn_point.x, spawn_point.y, spawn_point.z]
		)


func _report() -> void:
	print("--- 统计 %d 项检查，%d 项观察 ---" % [_checks, _notes.size()])
	if _failures.is_empty():
		print("verify_opening_script_runtime_OK checks=%d" % _checks)
		get_tree().quit(0)
		return
	print("verify_opening_script_runtime_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1)
