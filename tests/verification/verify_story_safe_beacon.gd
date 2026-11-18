extends Node
## 仅验 wrapper/真实 GLB、0.6秒落下、主动8秒同步及普通能力对照；不代签 Tower 正式链。
## 必须由外部 runner 在 Autoload 前隔离；场景 guard 只拒绝错误启动，不补做隔离。

const SAFE_VISUAL_PATH := "res://assets/art/props/dungeon_3d/components/prp_extraction_safe_beacon/prp_extraction_safe_beacon_visual_top3d.glb"
const INTEGRATION_ENTRY := "res://tests/verification/verify_main_story_integration.tscn"
const SAFE_WRAPPER_PATH := "res://assets/art/props/dungeon_3d/prp_extraction_safe_beacon_root_top3d.tscn"
const STORY_JSON := "res://data/narrative/nar_main_032_key_return_call.json"
var failures: Array[String] = []
var checks := 0
var visual_mesh_count := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("STORY_SAFE_BEACON_FAIL " + message)

func _ready() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").simplify_path().to_lower().trim_suffix("/")
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower().trim_suffix("/")
	var custom_dir := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var isolated := OS.get_environment("NARRATIVE_PRESENTATION_QA_ISOLATED") == "1"
	isolated = isolated and appdata.is_absolute_path() and "/verification/narrative_presentation/" in appdata
	isolated = isolated and bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	isolated = isolated and custom_dir == "narrative_timeline_qa" and OS.get_environment("SHELLSTORM_QA_CUSTOM_USER_DIR") == custom_dir
	isolated = isolated and user_dir.begins_with(appdata + "/") and user_dir.ends_with("/" + custom_dir)
	check(isolated, "启动隔离：专用runner在Autoload前设置APPDATA、custom_user_dir及NARRATIVE_PRESENTATION_QA_ISOLATED=1")
	if not isolated:
		_finish(false)
		return
	var data := JSON.parse_string(FileAccess.get_file_as_string(STORY_JSON)) as Dictionary
	check(not data.is_empty(), "方式B JSON 可解析")
	check(str(data.get("narrative_id", "")) == "nar_main_032_key_return_call", "方式B ID 正确")
	check(float(data.get("duration", -1.0)) == 0.4, "方式B短剧情时长为0.4秒")
	var dialogue := (data.get("presentation", {}) as Dictionary).get("dialogue", {}) as Dictionary
	check(str(dialogue.get("mode", "")) == "B", "方式B presentation mode")
	check(bool(dialogue.get("require_completed_dialogue", false)), "要求完整对白收口")
	var dialogue_wait := false
	for cue_value in data.get("cues", []) as Array:
		var cue := cue_value as Dictionary
		if str(cue.get("do", "")) == "ui.dialogue" and bool(cue.get("wait", false)):
			dialogue_wait = true
	check(dialogue_wait, "ui.dialogue wait=true")

	check(ResourceLoader.exists(SAFE_WRAPPER_PATH), "安全信标 wrapper 真实存在")
	var safe_scene := load(SAFE_WRAPPER_PATH) as PackedScene if ResourceLoader.exists(SAFE_WRAPPER_PATH) else null
	check(safe_scene != null, "安全信标 wrapper load 成功")
	if safe_scene == null:
		_finish()
		return
	var safe := safe_scene.instantiate() as ExtractionBeacon3D
	check(safe != null, "安全信标 wrapper instantiate 成功")
	if safe == null:
		_finish()
		return
	add_child(safe)
	safe.configure(Color(0.32, 0.88, 1.0), 8.0, "STORY_SAFE", false)
	check(safe.visual_scene != null, "wrapper visual_scene 未被 configure 清空")
	check(safe.visual_scene != null and safe.visual_scene.resource_path == SAFE_VISUAL_PATH, "wrapper引用指定真实GLB而非程序占位")
	var visual := safe.get("_visual_root") as Node3D
	check(visual != null and visual.get_parent() == safe and visual.scene_file_path == SAFE_VISUAL_PATH, "真实GLB实例挂在wrapper内")
	if visual != null:
		visual_mesh_count = _count_imported_meshes(visual)
	check(visual_mesh_count > 0, "GLB实例子树存在有surface的真实ArrayMesh，不以灯光/碰撞/提示节点代签")
	check(safe.defense_encounter_enabled == false, "safe 防守能力关闭")
	check(safe.beacon_type == "STORY_SAFE", "safe 类型显式为 STORY_SAFE")
	var started: Array[float] = []
	var completed: Array[int] = []
	safe.extraction_started.connect(func(seconds: float) -> void: started.append(seconds))
	safe.extraction_completed.connect(func() -> void: completed.append(Time.get_ticks_msec()))
	safe.configure_story_safe_drop(0.6)
	# 去掉 locked/距离的遮蔽，让落下反例真正验证 interaction_ready 门闩。
	safe.set_locked(false)
	safe._player_in_range = true
	check(not safe.force_start_for_test(), "0.6秒落下期间不可启动")
	check(not safe.perform_interaction(null, {}), "落下期间正式交互入口也拒绝启动")
	check(visual != null and is_equal_approx(visual.position.y, 1.2), "落下从真实GLB实例的1.2米高度开始")
	await get_tree().create_timer(0.3).timeout
	check(not bool(safe.get_snapshot().get("interaction_ready", true)), "0.6秒落下中途仍不可交互")
	check(visual != null and visual.position.y > 0.0 and visual.position.y < 1.2, "真实Tween推进GLB落下，不只是空等计时")
	await get_tree().create_timer(0.4).timeout
	check(bool(safe.get_snapshot().get("interaction_ready", false)), "落下完成后可交互")
	check(visual != null and is_zero_approx(visual.position.y), "落地后真实GLB到达目标高度")
	safe.set_locked(false)
	await get_tree().create_timer(0.25).timeout
	check(started.is_empty() and completed.is_empty() and not bool(safe.get_snapshot().get("active", true)), "落地不自动启动或完成撤离")
	safe._player_in_range = false
	check(not safe.perform_interaction(null, {}), "范围外主动交互拒绝启动")
	safe._player_in_range = true
	# 单元只提供范围前置条件；不冒充 PlayerInteractionController 的物理按键链。
	check(safe.perform_interaction(null, {}), "safe 可通过正式主动交互入口启动真实同步")
	check(started.size() == 1 and is_equal_approx(started[0], 8.0), "启动信号只发一次且为8秒")
	check(is_equal_approx(float(safe.get_snapshot().get("duration", 0.0)), 8.0), "safe 同步时长为8秒")
	check(safe.defense_encounter_enabled == false, "safe 启动时仍无防守遭遇能力")
	check(not safe.perform_interaction(null, {}), "同步中重复主动交互不重启")
	safe._player_in_range = false
	await get_tree().create_timer(0.25).timeout
	var syncing := safe.get_snapshot()
	check(bool(syncing.get("active", false)) and completed.is_empty(), "离开范围仍持续同步且不提前完成")
	check(float(syncing.get("remaining", 0.0)) > 0.0 and float(syncing.get("remaining", 8.0)) < 8.0, "真实_process推进8秒剩余时间")
	await get_tree().create_timer(7.0).timeout
	check(completed.is_empty() and bool(safe.get_snapshot().get("active", false)), "真实同步跨过7秒仍未提前完成")
	var deadline := Time.get_ticks_msec() + 12000
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(completed.size() == 1 and not bool(safe.get_snapshot().get("active", true)) and is_zero_approx(float(safe.get_snapshot().get("remaining", -1.0))), "不强制完成或手动tick，真实8秒同步自然完成一次")
	await get_tree().create_timer(0.25).timeout
	check(started.size() == 1 and completed.size() == 1, "完成后不自动重复启动或发送完成信号")
	safe.abort_extraction()

	var ordinary := ExtractionBeacon3D.new()
	check(ordinary.defense_encounter_enabled, "普通信标缺省防守能力为true")
	ordinary.configure(Color.WHITE, 30.0, "STANDARD", true)
	add_child(ordinary)
	check(ordinary.defense_encounter_enabled, "普通信标保留防守能力")
	check(ordinary.beacon_type == "STANDARD", "普通信标类型未被safe污染")
	ordinary.queue_free()
	safe.queue_free()
	await get_tree().process_frame
	_finish()

func _count_imported_meshes(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh is ArrayMesh and mesh.get_surface_count() > 0:
			count += 1
	for child in root.get_children():
		count += _count_imported_meshes(child)
	return count

func _finish(completed := true) -> void:
	print("STORY_SAFE_BEACON_REPORT ", JSON.stringify({
		"scope": "wrapper_drop_active_sync_unit",
		"completed": completed,
		"passed": completed and failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"wrapper_exists": ResourceLoader.exists(SAFE_WRAPPER_PATH),
		"visual_mesh_count": visual_mesh_count,
		"runtime_story_playback": false,
		"integration_acceptance": false,
		"rendered_acceptance": false,
		"integration_entry": INTEGRATION_ENTRY,
		"integration_method": "_verify_safe_return_flow",
		"not_covered": [
			"Tower真实方式B播放/skip重试/history/beacon_ready/零防守/正式结算返99F，另见integration入口，不由本单元代签",
			"普通防守true的实际遭遇派发与secret返航对照须在integration验证，本单元只验能力字段",
			"通讯history或beacon_ready写盘失败重试、call_pending/beacon_ready/cancelled恢复、旧schema迁移、坏字段/跨run/map拒绝，本单元未装配正式Tower夹具",
			"真实玩家物理接近和按E输入、地面选点避障、视觉像素/截图及纯新档完整人工流程",
			"受控runner接受场景路径，但尚未解析STORY_SAFE_BEACON_REPORT；runner汇总不由本单元代签",
		],
	}))
	get_tree().quit((0 if failures.is_empty() else 1) if completed else 2)
