extends Node3D
## 剧情系统验收：剧本解析 + 时间轴派发 + 四时机收口 + 与既有系统的接管/归还。
##
## 三层，各自独立判死：
##   A 静态 —— 目录登记 / JSON 校验 / radius 下限的反向对照 / 禁止节点路径字面量
##   B 机制 —— 同帧顺序、duration 收口、降级不停摆、失败可诊断、暂停冻结
##   C 端到端 —— 两段真实开场剧本：触发 → 接管（输入/姿态/相机/刷怪）→ 收口归还
##
## 防假绿：每层都打印实际参与数量（cue 数、刷怪次数、朝向最大偏转），
## 任一为 0 直接判红；「恢复原值」用**非 0 的接管前基线**做反向对照，
## 保证归还真是"还给原值"而不是"恰好都等于 0"。
##
## ⚠ 本场景刻意跑了一条执行失败的 cue（player.teleport 缺参数），
## 那行 ERROR 属预期，见 tests/verification/expected_errors/verify_narrative_timeline.txt。
##
## 运行：godot --headless --path . res://tests/verification/verify_narrative_timeline.tscn

signal room_entered(room)

const WAKE_ID := "nar_tower_opening_01_wake"
const ZOMBIES_ID := "nar_tower_opening_02_zombies"
const OPENING_ROOM_ID := "floor_01_exit"
const NEXT_ROOM_ID := "floor_01_main_02"
const FINISH_TIMEOUT_MS := 30000
const TIME_SCALE := 8.0
## 接管前的朝向基线。刻意取非 0：归还若写成"归零"就会露馅。
const FACING_BASELINE := 0.7


class FakeActor:
	extends Node3D
	var visual_root: Node3D
	var pose_active := false
	var pose_clip := ""
	var pose_phase := 0.0
	var pose_calls := 0
	var clear_calls := 0

	func _init() -> void:
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)

	func set_narrative_pose(clip: String, phase: float, _frozen := true) -> void:
		pose_active = true
		pose_clip = clip
		pose_phase = phase
		pose_calls += 1

	func clear_narrative_pose() -> void:
		pose_active = false
		pose_clip = ""
		clear_calls += 1


class FakePlayer:
	extends Node3D
	var input_locked := false
	var combat_enabled := true
	var is_invincible := false
	var aim_yaw := 0.0
	var camera: Camera3D = null
	var avatar: Node3D = null
	var lock_calls := 0

	func set_input_locked(locked: bool) -> void:
		input_locked = locked
		lock_calls += 1

	func set_combat_enabled(enabled: bool) -> void:
		combat_enabled = enabled


class FakeBark:
	extends Node
	var lines: Array[String] = []

	func say_text(text: String, _hold := -1.0) -> bool:
		lines.append(text)
		return true


class FakeRoom:
	extends Node3D
	var room_id := ""


## 只带 room_entered 信号的最小"地牢"，用来验证导演的自动绑定链。
class FakeDungeon:
	extends Node3D
	signal room_entered(room)


var _failures: Array[String] = []
var _checks := 0
var _notes: Array[String] = []
var _player: FakePlayer = null
var _avatar: FakeActor = null
var _camera: Camera3D = null
## 接管前那套俯角（度）。运镜是否真的"从上往下压"，只能拿它当基准比。
var _camera_rest_elevation := 0.0
var _bark: FakeBark = null
var _spawn_calls: Array = []
var _finish_reasons: Array[String] = []


func _ready() -> void:
	_build_world()
	await get_tree().process_frame
	# 导演在 autoload 阶段已自动登记目录剧本；这里重建一次，保证从干净状态起跑。
	NarrativeDirector.reset_for_test()
	NarrativeDirector.arm_all_from_catalog()
	await get_tree().process_frame

	_phase_a_static()
	await _phase_b_mechanics()
	await _phase_c_real_scripts()

	if is_equal_approx(Engine.time_scale, 1.0) == false:
		Engine.time_scale = 1.0
	_report()


# =========================================================================
# 世界搭建：一个"玩家 + 相机 + 角色 + 气泡"的最小可鸭型环境
# =========================================================================

func _build_world() -> void:
	# 假相机必须给一个**真实第三人称位姿**：运镜的基准是"接管瞬间的相机-玩家偏移"，
	# 若偏移为 0，_apply_camera_pose() 会整段早退，运镜就成了没法被断言的空操作。
	_camera = Camera3D.new()
	_camera.name = "FakeCamera"
	add_child(_camera)
	_camera.global_position = Vector3(0.0, 3.5, 6.0)
	_camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)

	_avatar = FakeActor.new()
	_avatar.name = "FakeAvatar"
	add_child(_avatar)

	_player = FakePlayer.new()
	_player.name = "FakePlayer"
	_player.camera = _camera
	_player.avatar = _avatar
	_player.aim_yaw = FACING_BASELINE
	add_child(_player)
	# 入树之后再登记分组：SceneTree 的分组表只认已在树内的节点。
	_player.add_to_group("player_3d")

	# 玩法镜头的基准俯角：只量一次。运行中相机只被适配器改，所以它就是"接管前的原值"。
	_camera_rest_elevation = _camera_elevation_deg()

	_bark = FakeBark.new()
	_bark.name = "FakeBark"
	add_child(_bark)

	NarrativeDirector.narrative_finished.connect(_on_finished)


func _on_finished(_narrative_id: String, reason: String) -> void:
	_finish_reasons.append(reason)


## 场景根同时充当"地牢"：剧本的两个正门都开在这里。
func narrative_player_bark() -> Node:
	return _bark


func narrative_spawn_enemies(
	room_id: String, kind: String, count: int,
	origin: Vector3, axis: Vector3 = Vector3.RIGHT, spread: float = 1.6
) -> int:
	_spawn_calls.append({
		"room_id": room_id, "kind": kind, "count": count,
		"origin": origin, "axis": axis, "spread": spread,
	})
	return count


func narrative_despawn_enemies(_room_id: String) -> int:
	return 0


# =========================================================================
# A 静态
# =========================================================================

func _phase_a_static() -> void:
	print("[A] 静态：目录登记 / 剧本校验 / 纪律")
	for narrative_id in [WAKE_ID, ZOMBIES_ID]:
		_check(NarrativeCatalog.has_id(narrative_id), "目录登记 %s" % narrative_id)
		_check(
			FileAccess.file_exists(NarrativeCatalog.path_for(narrative_id)),
			"剧本文件存在 %s" % narrative_id,
		)
		var script := NarrativeScript3D.load_from_id(narrative_id)
		if script == null:
			_check(false, "剧本可加载 %s" % narrative_id)
			continue
		_check(script.is_valid(), "剧本校验通过 %s errors=%s" % [narrative_id, str(script.errors)])
		_check(script.cues.size() >= 3, "cue 数 >= 3（%s = %d）" % [narrative_id, script.cues.size()])
		if not script.cues.is_empty():
			var last_at := float(script.cues[script.cues.size() - 1]["at"])
			_check(
				script.duration >= last_at - 0.0001,
				"%s duration %.2f >= 末条 at %.2f" % [narrative_id, script.duration, last_at],
			)
		_check(
			str(script.trigger.get("kind", "")) == NarrativeScript3D.TRIGGER_KIND_EVENT,
			"%s 触发类型是 event" % narrative_id,
		)
		var filter: Dictionary = script.trigger.get("filter", {})
		_check(str(filter.get("room_id", "")) != "", "%s 触发带 room_id 过滤" % narrative_id)

	# 开场类剧本必须挂 gameplay_started，**不能挂 room_entered**：后者在场景 `_ready` 里就发了，
	# 那一刻开场页还没把相机与输入接管完，剧情会在菜单背后空跑、并与开场页互相顶
	# （输入锁被还原成"可操控"、相机被钉在近景）。这是真机缺陷，不是风格偏好。
	var wake := NarrativeScript3D.load_from_id(WAKE_ID)
	if wake != null and wake.is_valid():
		_check(
			str(wake.trigger.get("on", "")) == "gameplay_started",
			"%s 挂在 gameplay_started 上（实际 on=%s）" % [WAKE_ID, str(wake.trigger.get("on", ""))],
		)
		var scripted_elev := _scripted_elevation_deg(wake)
		_check(
			not is_nan(scripted_elev),
			"%s 的运镜显式给了 elevation_deg（只给 distance 不会有俯冲感）" % WAKE_ID,
		)
		if not is_nan(scripted_elev):
			_check(
				scripted_elev > 5.0 and scripted_elev < 88.0,
				"%s 的 elevation_deg=%.1f° 落在可用区间" % [WAKE_ID, scripted_elev],
			)

	# radius 下限：轮询判定的漏触发风险必须有下限兜住 —— 反向对照
	var too_small := NarrativeScript3D.from_dictionary(_point_script(0.5))
	_check(not too_small.is_valid(), "point radius=0.5 判死（反向对照）")
	_check(_any_contains(too_small.errors, "radius"), "判死理由点名 radius")
	var ok_radius := NarrativeScript3D.from_dictionary(_point_script(2.0))
	_check(
		ok_radius.is_valid(),
		"point radius=2.0 放行（对照组）errors=%s" % str(ok_radius.errors),
	)

	# duration 早于最后一步 = 该 cue 永远没机会执行 —— 反向对照
	var short_duration := NarrativeScript3D.from_dictionary({
		"narrative_id": "test_short_duration",
		"schema_version": 1,
		"duration": 0.2,
		"cues": [
			{"at": 0.0, "do": "flow.mark", "key": "a"},
			{"at": 0.6, "do": "flow.mark", "key": "b"},
		],
	})
	_check(not short_duration.is_valid(), "duration < 末条 at 判死（反向对照）")

	# schema 版本与 id 一致性
	var bad_id := NarrativeScript3D.from_dictionary({
		"narrative_id": "test_bad_id",
		"schema_version": 99,
		"cues": [{"at": 0.0, "do": "flow.mark", "key": "a"}],
	})
	_check(not bad_id.is_valid(), "schema_version 不符判死（反向对照）")

	_check(_no_path_literals(), "src/narrative/** 无节点路径字面量（注释除外）")
	_check(_tower_camera_override_wired(), "TowerDescent3D 的相机接管查询已接入剧情导演")
	_check(_dungeon_binding_wired(), "room_entered 信号节点入树即被导演绑定（触发链接线面）")
	_check(
		_dungeon_input_lock_yields(),
		"Dungeon3D 的每帧输入锁同步已让权给演出（否则'停住'会被逐帧顶掉）",
	)


## 触发链接线面之外的第二处"断了也不报错"的接线：Dungeon3D 每帧重算 input_locked，
## 它若不认演出的独占，剧本写"停住"也拦不住玩家。这里做源码级守卫。
func _dungeon_input_lock_yields() -> bool:
	var text := FileAccess.get_file_as_string("res://src/world3d/Dungeon3D.gd")
	var marker := "func _sync_player_input_lock() -> void:"
	var start := text.find(marker)
	if start < 0:
		return false
	var body := text.substr(start, 900)
	return body.contains("_narrative_holds_player_input") and body.contains("is_player_input_locked")


## 触发链的**接线面**：导演靠 _on_node_added 自动认领带 room_entered 的节点。
## 这层断了只会表现为"剧情不触发"，运行时零报错 —— 所以必须能断言。
func _dungeon_binding_wired() -> bool:
	var candidate := FakeDungeon.new()
	candidate.name = "BindingProbeDungeon"
	add_child(candidate)
	var bound := NarrativeDirector.bound_dungeon_for_test()
	var wired := bound == candidate
	if not wired:
		_note("绑定失败：bound=%s 期望=%s" % [str(bound), str(candidate)])
	candidate.queue_free()
	return wired


## 塔楼把相机交给「叙事相机」的那一处开关：一旦被误删，剧情镜头会被玩法镜头每帧顶掉，
## 而运行时只表现为"镜头没动"，不会报错。所以这里做一次源码级守卫。
func _tower_camera_override_wired() -> bool:
	var text := FileAccess.get_file_as_string("res://src/world3d/TowerDescent3D.gd")
	var marker := "func _has_camera_presentation_override() -> bool:"
	var start := text.find(marker)
	if start < 0:
		return false
	var body := text.substr(start, 800)
	return body.contains("NarrativeDirector") and body.contains("is_camera_override_active")


func _point_script(radius: float) -> Dictionary:
	return {
		"narrative_id": "test_point_radius",
		"schema_version": 1,
		"trigger": {"kind": "point", "point": [0.0, 0.0, 0.0], "radius": radius},
		"cues": [{"at": 0.0, "do": "flow.mark", "key": "p"}],
	}


func _no_path_literals() -> bool:
	var directory := DirAccess.open("res://src/narrative")
	if directory == null:
		_note("无法打开 res://src/narrative")
		return false
	var forbidden := ["get_node(\"", "get_node_or_null(\"", "NodePath(\"", "\"../"]
	var scanned := 0
	for file_name in directory.get_files():
		if not file_name.ends_with(".gd"):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string("res://src/narrative/" + file_name)
		var line_number := 0
		for raw_line in text.split("\n"):
			line_number += 1
			var line := raw_line.strip_edges()
			if line.begins_with("#"):
				continue
			for token in forbidden:
				if line.contains(token):
					_note("%s:%d 含路径字面量 %s" % [file_name, line_number, token])
					return false
	_note("扫描 %d 个叙事脚本，无路径字面量" % scanned)
	return scanned > 0


# =========================================================================
# B 机制
# =========================================================================

func _phase_b_mechanics() -> void:
	print("[B] 机制：同帧顺序 / 降级不停摆 / 失败可诊断 / 暂停冻结")

	# B1 同一 at 的多条 cue 必须按书写顺序、在同一帧内连续执行
	var pulse := NarrativeScript3D.from_dictionary({
		"narrative_id": "test_pulse",
		"schema_version": 1,
		"cues": [
			{"at": 0.0, "do": "actor.say", "text": "同步1"},
			{"at": 0.0, "do": "actor.say", "text": "同步2"},
			{"at": 0.15, "do": "flow.mark", "key": "mid"},
			{"at": 0.3, "do": "actor.say", "text": "末句"},
		],
	})
	NarrativeDirector.register_script_for_test("test_pulse", pulse)
	_bark.lines.clear()
	_finish_reasons.clear()
	_check(NarrativeDirector.play("test_pulse"), "test_pulse 开始播放")
	await _wait_until_finished()
	_check(
		_finish_reasons.size() == 1 and _finish_reasons[0] == "duration",
		"无 flow.end 时按 duration 收口（reason=%s）" % str(_finish_reasons),
	)
	_check(
		_bark.lines == ["同步1", "同步2", "末句"],
		"同帧两条按书写顺序执行（实际 %s）" % str(_bark.lines),
	)
	_check(bool(NarrativeDirector.has_flag("mid")), "flow.mark 落标记")
	_check(not _player.input_locked, "收口后输入未被锁死")
	_note("B1 cue 数=%d 台词数=%d" % [pulse.cues.size(), _bark.lines.size()])

	# B2 降级（能继续）与失败（要诊断）都不许把时间轴卡死
	var rocky := NarrativeScript3D.from_dictionary({
		"narrative_id": "test_rocky",
		"schema_version": 1,
		"cues": [
			{"at": 0.0, "do": "grant.item", "id": "does_not_exist"},
			{"at": 0.1, "do": "player.teleport"},
			{"at": 0.2, "do": "actor.say", "text": "仍然走到这里"},
			{"at": 0.3, "do": "flow.end"},
		],
	})
	NarrativeDirector.register_script_for_test("test_rocky", rocky)
	_bark.lines.clear()
	_finish_reasons.clear()
	_check(NarrativeDirector.play("test_rocky"), "test_rocky 开始播放")
	await _wait_until_finished()
	_check(
		_finish_reasons.size() == 1 and _finish_reasons[0] == "flow.end",
		"降级与失败都不停摆，flow.end 仍被派发（reason=%s）" % str(_finish_reasons),
	)
	_check(_bark.lines == ["仍然走到这里"], "失败条之后的 cue 照常执行")
	var diagnostics := NarrativeDirector.diagnostics()
	_check(_any_contains(diagnostics, "grant.item"), "降级写入诊断（%s）" % str(diagnostics))
	_check(_any_contains(diagnostics, "player.teleport"), "执行失败写入诊断")

	# B3 暂停冻结：本 autoload 是 PAUSABLE；DialogueUI 是 ALWAYS，靠显式同步
	var long_run := NarrativeScript3D.from_dictionary({
		"narrative_id": "test_long",
		"schema_version": 1,
		"cues": [
			{"at": 0.0, "do": "player.lock_input", "locked": true},
			{"at": 3.0, "do": "flow.end"},
		],
	})
	NarrativeDirector.register_script_for_test("test_long", long_run)
	_check(NarrativeDirector.play("test_long"), "test_long 开始播放")
	await _wait_frames(3)
	get_tree().paused = true
	await _wait_frames(2)
	var frozen_a := NarrativeDirector.active_time()
	await _wait_frames(6)
	var frozen_b := NarrativeDirector.active_time()
	_check(
		is_equal_approx(frozen_a, frozen_b),
		"树暂停时时间轴冻结（%.3f 保持为 %.3f）" % [frozen_a, frozen_b],
	)
	_check(DialogueUI.is_paused(), "暂停时 DialogueUI 被显式冻结（ALWAYS 节点必须同步）")
	get_tree().paused = false
	await _wait_frames(3)
	_check(NarrativeDirector.active_time() > frozen_b, "取消暂停后时间轴继续推进")
	_check(not DialogueUI.is_paused(), "取消暂停后 DialogueUI 解冻")
	NarrativeDirector.abort("b3_cleanup")
	await _wait_frames(2)
	_check(not _player.input_locked, "abort 立即归还输入（不等 duration）")


# =========================================================================
# C 端到端：两段真实脚本
# =========================================================================

func _phase_c_real_scripts() -> void:
	print("[C] 端到端：两段真实开场剧本")
	Engine.time_scale = TIME_SCALE
	_player.aim_yaw = FACING_BASELINE

	# ---- C1 开场：趴着 → 镜头推近 → 起身 → 左右张望 → 「人呢」
	_spawn_calls.clear()
	_bark.lines.clear()
	_finish_reasons.clear()
	_emit_gameplay_started(OPENING_ROOM_ID)
	await _wait_frames(2)
	_check(
		NarrativeDirector.active_id() == WAKE_ID,
		"gameplay_started(%s) 触发 %s（实际 %s）"
		% [OPENING_ROOM_ID, WAKE_ID, NarrativeDirector.active_id()],
	)
	_check(_player.input_locked, "接管了输入")
	_check(NarrativeDirector.is_player_input_locked(), "演出对外声明自己持着输入独占")
	_check(
		_avatar.pose_active and _avatar.pose_clip == "dead",
		"接管了姿态（clip=%s active=%s）" % [_avatar.pose_clip, str(_avatar.pose_active)],
	)
	_check(NarrativeDirector.is_camera_override_active(), "接管了摄影机")
	_check(_player.is_invincible, "锁输入期间自动挂受击免疫（作者没写也生效）")

	var track: Dictionary = await _wait_tracking_facing()
	_check(
		_finish_reasons.size() == 1 and _finish_reasons[0] == "flow.end",
		"开场剧本按 flow.end 收口（%s）" % str(_finish_reasons),
	)
	_check(track["max_deviation"] > 0.2, "张望期间朝向真的被接管（最大偏转 %.3f rad）" % track["max_deviation"])
	_check(track["min_phase"] < 0.2, "起身是相位过渡不是瞬移（最低相位 %.3f）" % track["min_phase"])
	# 运镜必须真的动俯角：老实现只改距离，实测俯角降幅 0.0°，
	# 看上去只是推近，「镜头从上往下压」完全不成立。
	var c1_elev := _scripted_elevation_deg(NarrativeScript3D.load_from_id(WAKE_ID))
	_check(
		float(track["elev_dev"]) > 1.0,
		"运镜真的改动了俯角（相对接管前基线最大偏离 %.2f°）" % float(track["elev_dev"]),
	)
	if not is_nan(c1_elev):
		_check(
			absf(float(track["elev_best"]) - c1_elev) < 2.5,
			"俯角到达剧本写的 %.1f°（实测 %.1f°）" % [c1_elev, float(track["elev_best"])],
		)
	_check(_avatar.pose_calls >= 2, "姿态被下过至少两次指令（实际 %d）" % _avatar.pose_calls)
	_check(_bark.lines == ["人呢"], "台词是『人呢』（实际 %s）" % str(_bark.lines))
	_check(not _player.input_locked, "收口后输入归还")
	_check(not NarrativeDirector.is_player_input_locked(), "收口后交回输入独占权")
	_check(not NarrativeDirector.is_camera_override_active(), "收口后摄影机归还")
	_check(not _avatar.pose_active, "收口后姿态归还")
	_check(not _player.is_invincible, "收口后受击免疫归还")
	_check(
		is_equal_approx(_player.aim_yaw, FACING_BASELINE),
		"朝向归还到接管前的原值 %.3f（实际 %.4f）" % [FACING_BASELINE, _player.aim_yaw],
	)

	# ---- C2 下一间房：停住 → 镜头右移 → 右边五只小僵尸 → 挪回 → 「它们是什么？」
	_spawn_calls.clear()
	_bark.lines.clear()
	_finish_reasons.clear()
	_emit_room(NEXT_ROOM_ID)
	await _wait_frames(2)
	_check(
		NarrativeDirector.active_id() == ZOMBIES_ID,
		"room_entered(%s) 触发 %s（实际 %s）"
		% [NEXT_ROOM_ID, ZOMBIES_ID, NarrativeDirector.active_id()],
	)
	_check(_player.input_locked, "第二段同样先停住角色")
	_check(NarrativeDirector.is_camera_override_active(), "第二段接管了摄影机（只平移不改变构图距离）")
	_check(_spawn_calls.size() == 1, "刷怪正门被调用 1 次（实际 %d）" % _spawn_calls.size())
	if not _spawn_calls.is_empty():
		var call: Dictionary = _spawn_calls[0]
		_check(int(call.get("count", 0)) == 5, "刷 5 只（实际 %s）" % str(call.get("count")))
		_check(
			str(call.get("kind", "")) == "melee_chaser",
			"怪物是 melee_chaser（显示名『小僵尸』，实际 %s）" % str(call.get("kind")),
		)
		_check(str(call.get("room_id", "")) == NEXT_ROOM_ID, "刷在 %s" % NEXT_ROOM_ID)
		var axis: Variant = call.get("axis", null)
		_check(
			axis is Vector3 and (axis as Vector3).length() > 0.5,
			"展开轴是有效向量（5 参 vs 6 参缺陷的反向对照）",
		)
		var origin: Variant = call.get("origin", null)
		_check(
			origin is Vector3 and (origin as Vector3).length() > 0.0,
			"队列中心由玩家位置推出（不是原点）",
		)
	# 构图断言：镜头右移的驻留窗口（平移 0.1+1.3 结束 → 2.6 开始回摆）内逐帧测量。
	var framing: Dictionary = await _sample_framing(1.5, 2.55)
	_check(
		int(framing["samples"]) > 0,
		"镜头右移驻留窗口内采到帧（%d 帧，峰值 t=%.2f）"
		% [int(framing["samples"]), float(framing["peak_t"])],
	)
	_check(
		float(framing["depth"]) > 8.0 and float(framing["depth"]) < 13.5,
		"僵尸队列在相机前方 8~13.5m（depth=%.2f）" % float(framing["depth"]),
	)
	# 反向对照：把 camera.pan 的符号写反，队列会从 +16° 甩到 +37°（贴近画面边缘），
	# 深度也从 10.7m 掉到 6.9m —— 所以角度带与深度带同时收紧才能抓住符号翻转。
	_check(
		float(framing["angle_deg"]) > 12.0 and float(framing["angle_deg"]) < 24.0,
		"僵尸队列落在画面**右侧**且与角色分离（水平偏角 %.1f°，目标 12~24°）"
		% float(framing["angle_deg"]),
	)
	_note(
		"C2 构图采样：偏角=%.1f° 深度=%.2fm 峰值 t=%.2f"
		% [float(framing["angle_deg"]), float(framing["depth"]), float(framing["peak_t"])]
	)
	await _wait_until_finished()
	_check(
		_finish_reasons.size() == 1 and _finish_reasons[0] == "flow.end",
		"第二段按 flow.end 收口（%s）" % str(_finish_reasons),
	)
	_check(not NarrativeDirector.is_camera_override_active(), "第二段收口后摄影机归还")
	_check(not _player.input_locked, "第二段收口后输入归还")
	_check(_bark.lines == ["它们是什么？"], "台词是『它们是什么？』（实际 %s）" % str(_bark.lines))

	# ---- C3 once=run：同一局内不许重播
	_finish_reasons.clear()
	_emit_gameplay_started(OPENING_ROOM_ID)
	await _wait_frames(2)
	_check(not NarrativeDirector.is_playing(), "once=run 的第一段不会重播")
	_emit_room(NEXT_ROOM_ID)
	await _wait_frames(2)
	_check(not NarrativeDirector.is_playing(), "once=run 的第二段不会重播")

	# ---- C4 中断路径：演到一半切场景前必须先把现场还回去
	_emit_gameplay_started(OPENING_ROOM_ID)  # 已被 once 消耗，这里改用显式播放验证 abort
	NarrativeDirector.play(WAKE_ID, {"priority": 99})
	_check(NarrativeDirector.is_playing(), "abort 用例：高优先级可抢占式播放")
	await _wait_frames(2)
	_check(_player.input_locked, "abort 用例：已进入接管")
	NarrativeDirector.abort("scene_switch")
	await _wait_frames(2)
	_check(not NarrativeDirector.is_playing(), "abort 后演出结束")
	_check(not _player.input_locked, "abort 归还输入")
	_check(not NarrativeDirector.is_camera_override_active(), "abort 归还摄影机")
	_check(not _avatar.pose_active, "abort 归还姿态")
	_note(
		"C 统计：刷怪调用=%d，台词累计=%d，姿态指令=%d"
		% [_spawn_calls.size(), _bark.lines.size(), _avatar.pose_calls]
	)


## 驱动"进房"事件。走导演的真实事件评估入口（Dungeon3D 的 room_entered 信号路径
## 等价物），而不是直接播 —— 这样裁决（once / cooldown / room_id 过滤）全程参与。
## 在 [from_t, to_t] 窗口内逐帧测僵尸队列中心相对相机的构图：
## 返回 {"angle_deg": 画面水平偏角（>0 = 中心右侧）, "depth": 沿视线深度, "peak_t": 峰值时刻, "samples": 帧数}。
## 判据用**角度**而不是屏幕像素：角度与分辨率/FOV 无关，headless 下也测得准。
func _sample_framing(from_t: float, to_t: float) -> Dictionary:
	var best := {"angle_deg": -999.0, "depth": -1.0, "peak_t": -1.0, "samples": 0}
	var deadline := Time.get_ticks_msec() + FINISH_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var t := NarrativeDirector.active_time()
		if t >= from_t and t <= to_t and not _spawn_calls.is_empty():
			var point: Vector3 = _spawn_calls[0].get("origin", Vector3.ZERO)
			var basis := _camera.global_transform.basis
			var forward := -basis.z
			var to_point := point - _camera.global_position
			var depth := to_point.dot(forward)
			if depth > 0.01:
				var angle := rad_to_deg(atan2(to_point.dot(basis.x), depth))
				best["samples"] = int(best["samples"]) + 1
				if angle > float(best["angle_deg"]):
					best["angle_deg"] = angle
					best["depth"] = depth
					best["peak_t"] = t
		elif t > to_t and int(best["samples"]) > 0:
			break
		await get_tree().process_frame
	return best


## 驱动「玩法正式开始」。与 _emit_room 同路：走导演的真实事件评估入口，
## 绕开信号接线本身，单独验证裁决逻辑（once / room_id 过滤）。
func _emit_gameplay_started(room_id: String) -> void:
	NarrativeDirector.evaluate_event_for_test("gameplay_started", room_id)


func _emit_room(room_id: String) -> void:
	var room := FakeRoom.new()
	room.name = "FakeRoom_" + room_id
	room.room_id = room_id
	add_child(room)
	NarrativeDirector.evaluate_event_for_test("room_entered", room_id)
	room.queue_free()


## 跑完整场，同时采样：朝向相对基线的最大偏转、姿态达到过的最低相位。
func _wait_tracking_facing() -> Dictionary:
	var deadline := Time.get_ticks_msec() + FINISH_TIMEOUT_MS
	var max_deviation := 0.0
	var min_phase := 1.0
	var samples := 0
	var elev_best := NAN          # 与接管前基线偏离最大那一帧的俯角
	var elev_dev := 0.0
	while NarrativeDirector.is_playing() and Time.get_ticks_msec() < deadline:
		samples += 1
		max_deviation = maxf(max_deviation, absf(_player.aim_yaw - FACING_BASELINE))
		if _avatar.pose_active and _avatar.pose_clip == "dead":
			min_phase = minf(min_phase, _avatar.pose_phase)
		var elevation := _camera_elevation_deg()
		if not is_nan(elevation):
			var deviation := absf(elevation - _camera_rest_elevation)
			if deviation > elev_dev:
				elev_dev = deviation
				elev_best = elevation
		await get_tree().process_frame
	_note("C1 采样 %d 帧" % samples)
	return {
		"max_deviation": max_deviation, "min_phase": min_phase,
		"elev_best": elev_best, "elev_dev": elev_dev,
	}


## 相机相对玩家的实际俯角（度）。运镜有没有真的"从上往下压"，只能看这个量。
func _camera_elevation_deg() -> float:
	if _camera == null or _player == null or not is_instance_valid(_camera):
		return NAN
	var offset := _camera.global_position - _player.global_position
	var planar := Vector2(offset.x, offset.z).length()
	if planar <= 0.0001:
		return NAN
	return rad_to_deg(atan2(offset.y, planar))


## 剧本里显式声明的俯角（最后一条带 elevation_deg 的运镜 cue）。没写返回 NAN。
func _scripted_elevation_deg(script: NarrativeScript3D) -> float:
	if script == null:
		return NAN
	var found := NAN
	for cue in script.cues:
		if not str(cue.get("do", "")).begins_with("camera."):
			continue
		if cue.has("elevation_deg"):
			found = float(cue.get("elevation_deg", 0.0))
	return found


func _wait_until_finished() -> void:
	var deadline := Time.get_ticks_msec() + FINISH_TIMEOUT_MS
	while NarrativeDirector.is_playing() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


# =========================================================================
# 断言与汇报
# =========================================================================

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures.append(label)
		push_error("NARRATIVE_TIMELINE_FAIL: %s" % label)


func _note(message: String) -> void:
	_notes.append(message)
	print("  note %s" % message)


func _any_contains(haystack: Array, needle: String) -> bool:
	for item in haystack:
		if str(item).contains(needle):
			return true
	return false


func _report() -> void:
	print("--- 统计 %d 项检查，%d 项观察 ---" % [_checks, _notes.size()])
	if _failures.is_empty():
		print("verify_narrative_timeline_OK checks=%d" % _checks)
		get_tree().quit(0)
		return
	print("verify_narrative_timeline_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1)
