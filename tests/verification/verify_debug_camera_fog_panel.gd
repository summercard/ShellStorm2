extends Node
## 验收：调试面板「镜头雾气」页（TabId.CAMERA_FOG）与它带的两条链路。
##
## 四条断言线：
## ① 面板 → Player3D：俯仰 / 前后 / 平移三套按钮确实改到临时偏移量，行尾读数跟着变，
##    复位归零；步长必须等于规格 —— 角度 5°、位移 0.2 m。
## ② 面板 → TowerAtmosphere3D：切到本页把「当前场景」两套雾值回填滑条；
##    拖滑条精确改到 Environment；「清除覆盖」还原本场景原值。
## ③ 临时性：雾气覆盖优先级高于逐帧基础雾重算（覆盖期间不被改回去），
##    清除后地基雾照旧生效；面板任何镜头/雾气操作都不写 user://postfx_tuning.json。
## ④ 绕角色水平轴的圆轴算子：正角抬高（变高 + 水平距离变近）、负角压低、半径守恒。
##
## 跑法：--headless --path . res://tests/verification/verify_debug_camera_fog_panel.tscn

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const TOWER_SCRIPT := preload("res://src/world3d/TowerDescent3D.gd")
const PANEL_PATH := "FlashlightTweakerLayer/FlashlightColorTweaker"
const PERSIST_PATH := "user://postfx_tuning.json"

## 面板滑条范围外的「当前值」回填允许一次步进的量化误差。
const FILL_TOLERANCE := 0.0006
const MIN_CHECKS := 30

const OVERRIDE_DISTANCE := 0.021
const OVERRIDE_VOLUMETRIC := 0.0011
const SLIDER_DISTANCE := 0.024

var _checks := 0
var _failures: Array[String] = []
var _original_exists := false
var _original_text := ""


func _ready() -> void:
	await _run()


func _run() -> void:
	_capture_original_persist()
	# 干净起点：先删历史文件，后面「没被写出来」才是可信的。
	if FileAccess.file_exists(PERSIST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PERSIST_PATH))

	var atmosphere := await _spawn_atmosphere()
	atmosphere.update_base_interior_fog(false, 0.016, true)
	var base := atmosphere.get_scene_fog_snapshot()
	var base_distance := float(base.get("distance", -1.0))
	var base_volumetric := float(base.get("volumetric", -1.0))
	_expect_true(base_distance > 0.0, "probe_base_distance_positive")

	var player := await _spawn_player()
	var panel := player.get_node_or_null(PANEL_PATH) as FlashlightColorTweaker
	if panel == null:
		_finish("panel_missing")
		return

	_run_tab_checks(panel)
	_run_step_constant_checks()
	_run_camera_panel_checks(panel, player)
	_run_tab_open_fill_checks(panel, base_distance, base_volumetric)
	_run_panel_fog_checks(panel, atmosphere, base_distance)
	_run_override_semantics_checks(atmosphere, base_distance, base_volumetric)
	_run_orbit_formula_checks()

	# 镜头 / 雾气全程走过一遍后，等超过 PERSIST_DEBOUNCE_SECONDS(0.4) 再判「没落盘」。
	await get_tree().create_timer(0.9).timeout
	_expect_true(not FileAccess.file_exists(PERSIST_PATH), "camera_fog_never_persisted")
	var leaked: Array[String] = []
	var params: Dictionary = panel._collect_postfx_params()
	for key in params.keys():
		var name := str(key)
		if name.contains("scene_fog") or name.contains("camera"):
			leaked.append(name)
	_expect_true(leaked.is_empty(), "no_camera_fog_keys_in_persist_set")

	_finish("done")


# ---------- ① 页签结构 ----------

func _run_tab_checks(panel: FlashlightColorTweaker) -> void:
	# 页签序号是外部契约：既有脚本按 "TabBar/TabButton_3" 找「预留」页，
	# 新页必须追加在最后，不得挤动已有序号。
	_expect_float(float(FlashlightColorTweaker.TabId.RESERVED_3), 3.0, 0.001, "reserved_tab_index_preserved")
	_expect_float(float(FlashlightColorTweaker.TabId.CAMERA_FOG), 4.0, 0.001, "camera_fog_tab_index")
	_expect_true(panel._tab_buttons.has(FlashlightColorTweaker.TabId.CAMERA_FOG), "camera_fog_tab_button")
	var tab_button: Button = panel._tab_buttons.get(FlashlightColorTweaker.TabId.CAMERA_FOG)
	_expect_true(tab_button != null and not tab_button.disabled, "camera_fog_tab_enabled")
	_expect_true(panel._tab_pages.has(FlashlightColorTweaker.TabId.CAMERA_FOG), "camera_fog_page_built")


# ---------- ② 步长 = 规格 ----------

func _run_step_constant_checks() -> void:
	_expect_float(Player3D.DEBUG_CAMERA_PITCH_STEP_DEG, 5.0, 0.0001, "pitch_step_is_5deg")
	_expect_float(Player3D.DEBUG_CAMERA_TRAILING_STEP_M, 0.2, 0.0001, "dolly_step_is_0p2m")
	_expect_float(Player3D.DEBUG_CAMERA_PAN_STEP_M, 0.2, 0.0001, "pan_step_is_0p2m")


# ---------- ③ 面板 → Player3D ----------

func _run_camera_panel_checks(panel: FlashlightColorTweaker, player: Player3D) -> void:
	panel._on_camera_pitch(Player3D.DEBUG_CAMERA_PITCH_STEP_DEG)
	_expect_float(player.get_debug_camera_pitch_offset_deg(), 5.0, 0.0001, "pitch_up_5")
	_expect_true(panel._camera_pitch_value_label.text.begins_with("+5"), "pitch_label_plus5")

	panel._on_camera_pitch(-Player3D.DEBUG_CAMERA_PITCH_STEP_DEG)
	_expect_float(player.get_debug_camera_pitch_offset_deg(), 0.0, 0.0001, "pitch_back_to_zero")
	panel._on_camera_pitch(-Player3D.DEBUG_CAMERA_PITCH_STEP_DEG)
	_expect_true(
		panel._camera_pitch_value_label.text.begins_with("-5"),
		"pitch_label_minus5"
	)

	panel._on_camera_dolly(Player3D.DEBUG_CAMERA_TRAILING_STEP_M)
	_expect_float(player.get_debug_camera_trailing_offset_m(), 0.2, 0.0001, "dolly_back_0p2")
	_expect_true(panel._camera_dolly_value_label.text.begins_with("+0.2"), "dolly_label_plus0p2")

	panel._on_camera_pan(FlashlightColorTweaker.CAMERA_PAN_UP)
	_expect_float(player.get_debug_camera_pan_offset().y, 0.2, 0.0001, "pan_up_0p2")
	panel._on_camera_pan(FlashlightColorTweaker.CAMERA_PAN_DOWN)
	_expect_float(player.get_debug_camera_pan_offset().y, 0.0, 0.0001, "pan_down_returns")
	panel._on_camera_pan(FlashlightColorTweaker.CAMERA_PAN_RIGHT)
	var panned := player.get_debug_camera_pan_offset()
	_expect_true(
		absf(Vector2(panned.x, panned.z).length() - 0.2) <= 0.0001,
		"pan_right_horizontal_0p2"
	)

	panel._on_reset_camera_pressed()
	_expect_float(player.get_debug_camera_pitch_offset_deg(), 0.0, 0.0001, "reset_pitch")
	_expect_float(player.get_debug_camera_trailing_offset_m(), 0.0, 0.0001, "reset_dolly")
	_expect_true(player.get_debug_camera_pan_offset().is_zero_approx(), "reset_pan")

	# 跨文件读取端还在：TowerDescent3D 每帧要读这三个量才能把偏移画到镜头上。
	var tower: Node = TOWER_SCRIPT.new()
	_expect_true(tower.has_method("_read_debug_camera_pitch_offset_deg"), "tower_reads_pitch")
	_expect_true(tower.has_method("_read_debug_camera_pan_offset"), "tower_reads_pan")
	_expect_true(
		tower.has_method("_apply_debug_camera_pose_adjustments"),
		"tower_applies_offsets"
	)
	tower.free()


# ---------- ④ 打开即显示当前值 ----------

func _run_tab_open_fill_checks(
	panel: FlashlightColorTweaker, base_distance: float, base_volumetric: float
) -> void:
	panel._select_tab(FlashlightColorTweaker.TabId.CAMERA_FOG)
	_expect_float(
		panel._scene_fog_density_slider.value,
		base_distance,
		FILL_TOLERANCE,
		"tab_open_fills_distance"
	)
	_expect_float(
		panel._scene_volumetric_fog_density_slider.value,
		base_volumetric,
		FILL_TOLERANCE,
		"tab_open_fills_volumetric"
	)
	_expect_true(
		panel._scene_fog_status.text.begins_with("当前："),
		"tab_open_status_has_values"
	)


# ---------- ⑤ 面板拖滑条 / 清除覆盖 ----------

func _run_panel_fog_checks(
	panel: FlashlightColorTweaker, atmosphere: TowerAtmosphere3D, base_distance: float
) -> void:
	panel._scene_fog_density_slider.value = SLIDER_DISTANCE
	var driven := atmosphere.get_scene_fog_snapshot()
	_expect_float(float(driven.get("distance", -1.0)), SLIDER_DISTANCE, 0.00001, "panel_drives_distance")

	panel._on_clear_scene_fog_pressed()
	var restored := atmosphere.get_scene_fog_snapshot()
	_expect_float(
		float(restored.get("distance", -1.0)),
		base_distance,
		0.00001,
		"panel_clear_restores_base"
	)
	_expect_true(not atmosphere.has_debug_scene_fog_override(), "panel_clear_drops_flag")


# ---------- ⑥ 覆盖的优先级与临时性 ----------

func _run_override_semantics_checks(
	atmosphere: TowerAtmosphere3D, base_distance: float, base_volumetric: float
) -> void:
	atmosphere.set_debug_scene_fog_override(OVERRIDE_DISTANCE, OVERRIDE_VOLUMETRIC)
	var set_snapshot := atmosphere.get_scene_fog_snapshot()
	_expect_float(
		float(set_snapshot.get("distance", -1.0)), OVERRIDE_DISTANCE, 0.000001, "override_exact_distance"
	)
	_expect_float(
		float(set_snapshot.get("volumetric", -1.0)),
		OVERRIDE_VOLUMETRIC,
		0.000001,
		"override_exact_volumetric"
	)
	_expect_true(atmosphere.has_debug_scene_fog_override(), "override_flag_on")

	# 走一次真实逐帧路径：基础雾会重算，但覆盖期间画面值必须纹丝不动。
	atmosphere.update_base_interior_fog(true, 0.016, true)
	var repainted := atmosphere.get_scene_fog_snapshot()
	_expect_float(
		float(repainted.get("distance", -1.0)),
		OVERRIDE_DISTANCE,
		0.000001,
		"override_survives_repaint"
	)
	_expect_float(
		float(repainted.get("volumetric", -1.0)),
		OVERRIDE_VOLUMETRIC,
		0.000001,
		"override_survives_repaint_volumetric"
	)

	atmosphere.update_base_interior_fog(false, 0.016, true)
	atmosphere.clear_debug_scene_fog_override()
	var cleared := atmosphere.get_scene_fog_snapshot()
	_expect_true(not atmosphere.has_debug_scene_fog_override(), "override_flag_off")
	_expect_float(
		float(cleared.get("distance", -1.0)), base_distance, 0.00001, "clear_restores_distance"
	)
	_expect_float(
		float(cleared.get("volumetric", -1.0)),
		base_volumetric,
		0.00001,
		"clear_restores_volumetric"
	)


# ---------- ⑦ 圆轴算子（纯函数，不需要整场景） ----------

func _run_orbit_formula_checks() -> void:
	var tower: Node = TOWER_SCRIPT.new()
	var pivot := Vector3.ZERO
	var point := Vector3(0.0, 9.54, 4.45)
	var radius := point.length()
	var raised: Vector3 = tower._orbit_point_about_pivot(point, pivot, 5.0)
	_expect_true(raised.y > point.y, "orbit_raise_raises_height")
	_expect_true(absf(raised.z) < absf(point.z), "orbit_raise_shortens_horizontal")
	_expect_float(raised.length(), radius, 0.0001, "orbit_keeps_radius")
	var lowered: Vector3 = tower._orbit_point_about_pivot(point, pivot, -5.0)
	_expect_true(lowered.y < point.y, "orbit_lower_lowers_height")
	# 正上方是退化姿态：靠极角夹在 88° 以内避免 look_at 抖动。
	var extreme: Vector3 = tower._orbit_point_about_pivot(point, pivot, 200.0)
	_expect_true(
		extreme.y <= radius * sin(deg_to_rad(88.0)) + 0.0001,
		"orbit_clamped_below_88deg"
	)
	tower.free()


# ---------- 场景装配 ----------

func _spawn_player() -> Player3D:
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	return player


## 一块独立大气：不实例化 TowerDescent3D，避免触发关卡生成的整套副作用。
func _spawn_atmosphere() -> TowerAtmosphere3D:
	var environment := Environment.new()
	environment.fog_enabled = true
	environment.fog_density = 0.030
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.009
	var sun := DirectionalLight3D.new()
	sun.name = "ProbeKeyLight"
	# 真实链路里 key_light 已在场景树内才 configure；先入树才不会在
	# GameplaySpatialRegistry3D 上撞 "!is_inside_tree()"。
	add_child(sun)
	var atmosphere := TowerAtmosphere3D.new()
	atmosphere.name = "ProbeAtmosphere"
	atmosphere.legacy_city_silhouette_enabled = false
	atmosphere.background_music_enabled = false
	atmosphere.configure(environment, sun)
	add_child(atmosphere)
	await get_tree().process_frame
	return atmosphere


# ---------- 断言与收尾 ----------

func _expect_float(actual: float, want: float, tolerance: float, tag: String) -> void:
	_checks += 1
	if absf(actual - want) > tolerance:
		_failures.append("%s got=%s want=%s" % [tag, str(actual), str(want)])


func _expect_true(condition: bool, tag: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(tag)


func _finish(context: String) -> void:
	if not _failures.is_empty():
		for failure in _failures:
			printerr("[DEBUG_CAMERA_FOG_PANEL] FAIL %s" % failure)
		printerr(
			"[DEBUG_CAMERA_FOG_PANEL] DEBUG_CAMERA_FOG_PANEL_FAILED checks=%d context=%s"
			% [_checks, context]
		)
		_restore_original_persist()
		get_tree().quit(1)
		return
	if _checks < MIN_CHECKS:
		printerr("[DEBUG_CAMERA_FOG_PANEL] FAIL too_few_checks_%d" % _checks)
		_restore_original_persist()
		get_tree().quit(1)
		return
	_restore_original_persist()
	print("[DEBUG_CAMERA_FOG_PANEL] DEBUG_CAMERA_FOG_PANEL_OK checks=%d" % _checks)
	get_tree().quit(0)


func _capture_original_persist() -> void:
	_original_exists = FileAccess.file_exists(PERSIST_PATH)
	if not _original_exists:
		return
	var file := FileAccess.open(PERSIST_PATH, FileAccess.READ)
	if file != null:
		_original_text = file.get_as_text()
		file.close()


func _restore_original_persist() -> void:
	# 验收会真实删改 user://postfx_tuning.json（那是玩家的实际滤镜参数），
	# 无论成功失败都必须还原。
	if _original_exists:
		var file := FileAccess.open(PERSIST_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_original_text)
			file.close()
	elif FileAccess.file_exists(PERSIST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PERSIST_PATH))
