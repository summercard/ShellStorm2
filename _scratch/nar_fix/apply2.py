import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"


def patch(rel, edits):
    path = os.path.join(ROOT, rel)
    raw = open(path, "rb").read().decode("utf-8")
    text = raw.replace("\r\n", "\n")
    for name, old, new in edits:
        n = text.count(old)
        if n != 1:
            raise SystemExit("ANCHOR FAIL %s :: %s count=%d" % (rel, name, n))
        text = text.replace(old, new, 1)
    out = text.replace("\n", "\r\n").encode("utf-8")
    open(path, "wb").write(out)
    print("patched %-56s CR=%d LF=%d" % (rel, out.count(b"\r"), out.count(b"\n")))


# =====================================================================
# 1) NarrativeAdapter3D：camera.pan 也支持 elevation_deg
#    （camera.focus 已有；运镜动词不该只有一半能压俯角）
# =====================================================================
patch("src/narrative/NarrativeAdapter3D.gd", [
    ("class-doc-elev",
     """## 关键：**不硬编码任何相机高度/构图常量** —— 接管瞬间抓一次真实位姿当基准，
## 叙事只改「距离」与「绕玩家竖轴的方位」，其余（俯角、焦点）完全继承，
## 这样叙事镜头与玩法镜头永远同一套构图语言。
""",
     """## 关键：**不硬编码任何相机高度/构图常量** —— 接管瞬间抓一次真实位姿当基准，
## 叙事只改「距离」「绕玩家竖轴的方位」与「俯角」，焦点完全继承，
## 这样叙事镜头与玩法镜头永远同一套构图语言。
## ⚠ 俯角必须**显式**给 `elevation_deg` 才会变 —— 只改距离的运镜只是沿同一条轴滑动，
## 观感是"推近拉远"，不是"镜头从上往下压"（实测差异极大，见 08 文档 §5.2）。
"""),

    ("pan-elev",
     """	var target_yaw := float(params.get("yaw_deg", 0.0))
	var duration := maxf(0.0, float(params.get("duration", 0.6)))
	_camera_yaw_channel = {
		"from": _camera_yaw_deg(), "to": target_yaw, "t": 0.0, "duration": duration,
		"value": _camera_yaw_deg(),
	}
	# 同上：运镜也是一种占用，必须登记归还。
""",
     """	var target_yaw := float(params.get("yaw_deg", 0.0))
	var duration := maxf(0.0, float(params.get("duration", 0.6)))
	_camera_yaw_channel = {
		"from": _camera_yaw_deg(), "to": target_yaw, "t": 0.0, "duration": duration,
		"value": _camera_yaw_deg(),
	}
	# 平移默认只绕竖轴甩（老行为一字不变）。**要俯冲就得另给 elevation_deg** ——
	# 与 camera.focus 同一套仰角通道，只是不改距离。
	# 缺席时通道保持为空 = 俯角沿用接管前那套，所以老剧本不会被动到。
	if params.has("elevation_deg"):
		_camera_elev_channel = {
			"from": _camera_elev_deg(),
			"to": float(params.get("elevation_deg", _camera_rest_elevation_deg)),
			"t": 0.0, "duration": duration, "value": _camera_elev_deg(),
		}
	# 同上：运镜也是一种占用，必须登记归还。
"""),
])


# =====================================================================
# 2) verify_narrative_timeline：把 C1 改挂 gameplay_started
#    （剧本 01 已改触发源；不改这条，老用例会直接变红），
#    并补上「俯角必须真的动」的机制断言与静态守卫。
# =====================================================================
patch("tests/verification/verify_narrative_timeline.gd", [
    ("decl-rest-elev",
     """var _player: FakePlayer = null
var _avatar: FakeActor = null
var _camera: Camera3D = null
""",
     """var _player: FakePlayer = null
var _avatar: FakeActor = null
var _camera: Camera3D = null
## 接管前那套俯角（度）。运镜是否真的"从上往下压"，只能拿它当基准比。
var _camera_rest_elevation := 0.0
"""),

    ("capture-rest-elev",
     """	_bark = FakeBark.new()
	_bark.name = "FakeBark"
	add_child(_bark)
""",
     """	# 玩法镜头的基准俯角：只量一次。运行中相机只被适配器改，所以它就是"接管前的原值"。
	_camera_rest_elevation = _camera_elevation_deg()

	_bark = FakeBark.new()
	_bark.name = "FakeBark"
	add_child(_bark)
"""),

    ("wake-static-guards",
     """	# radius 下限：轮询判定的漏触发风险必须有下限兜住 —— 反向对照
""",
     """	# 开场类剧本必须挂 gameplay_started，**不能挂 room_entered**：后者在场景 `_ready` 里就发了，
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
"""),

    ("c1-emit",
     """	_spawn_calls.clear()
	_bark.lines.clear()
	_finish_reasons.clear()
	_emit_room(OPENING_ROOM_ID)
	await _wait_frames(2)
	_check(
		NarrativeDirector.active_id() == WAKE_ID,
		"room_entered(%s) 触发 %s（实际 %s）"
		% [OPENING_ROOM_ID, WAKE_ID, NarrativeDirector.active_id()],
	)
""",
     """	_spawn_calls.clear()
	_bark.lines.clear()
	_finish_reasons.clear()
	_emit_gameplay_started(OPENING_ROOM_ID)
	await _wait_frames(2)
	_check(
		NarrativeDirector.active_id() == WAKE_ID,
		"gameplay_started(%s) 触发 %s（实际 %s）"
		% [OPENING_ROOM_ID, WAKE_ID, NarrativeDirector.active_id()],
	)
"""),

    ("c1-elev-assert",
     """	_check(track["max_deviation"] > 0.2, "张望期间朝向真的被接管（最大偏转 %.3f rad）" % track["max_deviation"])
	_check(track["min_phase"] < 0.2, "起身是相位过渡不是瞬移（最低相位 %.3f）" % track["min_phase"])
""",
     """	_check(track["max_deviation"] > 0.2, "张望期间朝向真的被接管（最大偏转 %.3f rad）" % track["max_deviation"])
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
"""),

    ("c3-emit",
     """	_finish_reasons.clear()
	_emit_room(OPENING_ROOM_ID)
	await _wait_frames(2)
	_check(not NarrativeDirector.is_playing(), "once=run 的第一段不会重播")
""",
     """	_finish_reasons.clear()
	_emit_gameplay_started(OPENING_ROOM_ID)
	await _wait_frames(2)
	_check(not NarrativeDirector.is_playing(), "once=run 的第一段不会重播")
"""),

    ("c4-emit",
     """	_emit_room(OPENING_ROOM_ID)  # 已被 once 消耗，这里改用显式播放验证 abort
""",
     """	_emit_gameplay_started(OPENING_ROOM_ID)  # 已被 once 消耗，这里改用显式播放验证 abort
"""),

    ("tracking-elev",
     """func _wait_tracking_facing() -> Dictionary:
	var deadline := Time.get_ticks_msec() + FINISH_TIMEOUT_MS
	var max_deviation := 0.0
	var min_phase := 1.0
	var samples := 0
	while NarrativeDirector.is_playing() and Time.get_ticks_msec() < deadline:
		samples += 1
		max_deviation = maxf(max_deviation, absf(_player.aim_yaw - FACING_BASELINE))
		if _avatar.pose_active and _avatar.pose_clip == "dead":
			min_phase = minf(min_phase, _avatar.pose_phase)
		await get_tree().process_frame
	_note("C1 采样 %d 帧" % samples)
	return {"max_deviation": max_deviation, "min_phase": min_phase}
""",
     """func _wait_tracking_facing() -> Dictionary:
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
"""),

    ("emit-gameplay-started",
     """func _emit_room(room_id: String) -> void:
""",
     """## 驱动「玩法正式开始」。与 _emit_room 同路：走导演的真实事件评估入口，
## 绕开信号接线本身，单独验证裁决逻辑（once / room_id 过滤）。
func _emit_gameplay_started(room_id: String) -> void:
	NarrativeDirector.evaluate_event_for_test("gameplay_started", room_id)


func _emit_room(room_id: String) -> void:
"""),
])


# =====================================================================
# 3) 验收套件登记新探针
# =====================================================================
patch("scripts/run_verification_suite.sh", [
    ("register",
     """  verify_narrative_timeline
""",
     """  verify_narrative_timeline
  verify_opening_script_runtime
"""),
])

print("ALL PATCHED (apply2)")
