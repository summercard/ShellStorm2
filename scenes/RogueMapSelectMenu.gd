extends CanvasLayer
class_name RogueMapSelectMenu
## Lifecycle adapter only; the city and input targets live in the gameplay world.
const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const LEVEL_SCENE := GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D
const CITY_SCENE = preload("res://assets/art/ui/expedition_city/hologram_city.tscn")
const CITY_LAYER := 1 << 18
## 情报室里**本局可见**的入口，顺序 = 全息城里的站位顺序。
##
## 真源是 `GameDesignConfig.EXPEDITION_LEVELS`（+ `nav_order` 排位）与解锁状态，
## 这里只是把它算出来 —— 不允许再手写一份关卡 id 数组（早期写死 `["expedition_01", "99"]`，
## 结果加第三关时这行和 HologramCity3D 里的对应数组必须同时改，漏一处就是错位或漏关）。
var LEVEL_IDS: Array[String] = []
const RETURN_PICK := -2
var _close_entry_from := 0.0
const OPENING_SECONDS := 4.4
const CLOSING_SECONDS := 3.6
# 关闭曲线：q 是"关闭自身归一化进度"（按下瞬间 1 → 完成 0）。指数 > 1 为起步快、收尾慢，
# 保证按下当帧就有位移；直接用 opening 的映射反向会让相机静止 1.62s、楼群静止 0.82s。
const CLOSE_EASED_FALLOFF := 1.35
const CLOSE_DEPLOY_FALLOFF := 1.6
# 点击弹性反馈的可见窗口：change_scene 会立刻接管画面，不留这段时间就只剩一帧脉冲。
const PUNCH_HOLD := 0.18
var _player: Node3D
var _facility: BaseFacility3D
var _original_camera: Camera3D
var _camera: Camera3D
var _city: Node3D
var _start_transform := Transform3D.IDENTITY
var _target_transform := Transform3D.IDENTITY
var _hidden: Array[Node] = []
var _world_fades: Array[Dictionary] = []
var _state := "opening"
var _progress := 0.0
var _close_from_progress := 1.0
var _close_deploy_from := 1.0
var _close_eased_from := 1.0
var _pending_level_id := ""
var _depart_countdown := 0.0
var _selection := 0
var _focus := 0
var _axis_latched := false
var _departing := false
var _previous_input_lock := false
var _initial_fov := 60.0
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _source_environment: Environment
var _city_environment: Environment
var _source_dof_blur_amount := 0.0
var _dof_attributes: CameraAttributesPractical

func set_player(value) -> void:
	_player = value

func set_facility(value: BaseFacility3D) -> void:
	_facility = value

func is_camera_override_active() -> bool:
	return is_instance_valid(_camera)

func _ready() -> void:
	_original_camera = get_viewport().get_camera_3d()
	if _facility == null:
		for item in get_tree().get_nodes_in_group("base_facility"):
			if item is BaseFacility3D and item.facility_id == "mission_operations" and get_parent().is_ancestor_of(item):
				_facility = item
				break
	if _facility == null or _original_camera == null:
		push_warning("[HologramCity] Missing facility or gameplay camera")
		queue_free()
		return
	_start_transform = _original_camera.global_transform
	_initial_fov = _original_camera.fov
	for node in get_parent().find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.is_visible_in_tree():
			_world_fades.append({"node": geometry, "transparency": geometry.transparency})
	if _player != null:
		_previous_input_lock = bool(_player.get("input_locked"))
		_player.call("set_input_locked", true)
	_refresh_level_ids()
	_city = CITY_SCENE.instantiate()
	# 导航清单是唯一真源：城市按它决定"显示哪几个入口、各在哪"，
	# 不再各自维护一份（早期两边各写一片数组，加关就会错位）。
	_city.level_ids = LEVEL_IDS.duplicate()
	# 牌面文案交给本菜单算 —— 只有这里同时知道「场景在不在」和「解没解锁」。
	# 必须**在 add_child 之前**注入：城市在 `_ready` 里就把牌面标签建好了，
	# 之后再给 provider 就改不到已经建出来的文字。
	_city.entry_hint_provider = _entry_hint_text
	get_parent().add_child(_city)
	var anchor := _facility.global_position + Vector3.UP * 1.7
	if _facility.has_method("get_hologram_anchor"):
		anchor = _facility.call("get_hologram_anchor")
	_city.global_position = anchor
	_city.scale = Vector3.ONE * 0.09
	_camera = Camera3D.new()
	_camera.name = "ExpeditionCloseupCamera"
	get_parent().add_child(_camera)
	_camera.global_transform = _start_transform
	_camera.fov = _initial_fov
	_camera.near = 0.015
	_camera.cull_mask = _original_camera.cull_mask | CITY_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.002, 0.004, 0.016)
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.16
	env.glow_hdr_threshold = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_city_environment = env
	_source_environment = _original_camera.environment
	if _source_environment == null:
		_source_environment = _original_camera.get_world_3d().environment
	if _source_environment == null:
		_source_environment = env
	_camera.environment = _source_environment.duplicate(true)
	# DOF is a CameraAttributesPractical value (not an Environment value).  Copy
	# the authored attributes so the transition never touches the gameplay camera.
	if _original_camera.attributes is CameraAttributesPractical:
		_dof_attributes = (_original_camera.attributes as CameraAttributesPractical).duplicate(true)
		_source_dof_blur_amount = _dof_attributes.dof_blur_amount
		_camera.attributes = _dof_attributes
	else:
		_camera.attributes = _original_camera.attributes
	_camera.compositor = _original_camera.compositor
	_camera.make_current()
	var destination := anchor + Vector3(0.65, 1.42, 1.85)
	_target_transform = Transform3D(Basis.looking_at((anchor + Vector3(0, 0.24, -0.05) - destination).normalized()), destination)
	for item in get_parent().find_children("*", "CanvasLayer", true, false):
		if item != self and item.visible:
			_hidden.append(item)
			item.visible = false
	for item in [_facility.name_label, _facility.prompt_label]:
		if is_instance_valid(item) and item.visible:
			_hidden.append(item)
			item.hide()
	_mouse_mode = Input.mouse_mode
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if not is_instance_valid(_city) or not is_instance_valid(_camera):
		return
	if _state == "opening":
		_progress = minf(1.0, _progress + delta / OPENING_SECONDS)
		_apply_transition()
		if _progress >= 1.0:
			_state = "active"
	elif _state == "closing":
		_progress = maxf(0.0, _progress - delta / CLOSING_SECONDS)
		_apply_transition()
		if _progress <= 0.0:
			queue_free()
	elif _state == "entering":
		# 点击后的弹性展示窗口；到点才真正交接出发。
		_depart_countdown = maxf(0.0, _depart_countdown - delta)
		if _depart_countdown <= 0.0:
			_commit_departure()
	_city.entries_ready = _state in ["active", "entering", "departing"]
	_city.focus = _focus
	_city.face_markers(_camera)
	_facility.name_label.hide()
	_facility.prompt_label.hide()

func _apply_transition() -> void:
	var eased := smoothstep(0.0, 0.55, _progress)
	var deployed := clampf((_progress - (0.35 - 1.0 / OPENING_SECONDS)) / 0.65, 0.0, 1.0)
	if _state == "closing":
		# 关闭独立起播：q 从按下瞬间的 1 连续收敛到 0，起点等于按下时的真实状态，
		# 因此途中退出不跳变，而两段平台期（相机 1.62s、楼群 0.82s）不再出现。
		var q := clampf(_progress / _close_from_progress, 0.0, 1.0)
		eased = _close_eased_from * pow(q, CLOSE_EASED_FALLOFF)
		deployed = _close_deploy_from * pow(q, CLOSE_DEPLOY_FALLOFF)
	_camera.global_transform = _start_transform.interpolate_with(_target_transform, eased)
	_camera.fov = lerpf(_initial_fov, 48.0, eased)
	_animate_depth_of_field(eased)
	_city.deployment = deployed
	_city.entry_deployment = _close_entry_from * pow(clampf(_progress / _close_from_progress, 0.0, 1.0), CLOSE_DEPLOY_FALLOFF) if _state == "closing" else smoothstep(0.8, 1.0, _progress)
	var fade := smoothstep(0.44, 0.72, _progress)
	_blend_environment(fade)
	for item in _world_fades:
		if is_instance_valid(item.node):
			item.node.transparency = lerpf(float(item.transparency), 1.0, fade)
	_camera.cull_mask = CITY_LAYER if _progress > 0.73 else (_original_camera.cull_mask | CITY_LAYER)
	if _facility.has_method("set_hologram_city_blend"):
		_facility.call("set_hologram_city_blend", smoothstep(0.12, 0.30, _progress))

func _animate_depth_of_field(amount: float) -> void:
	# `amount` follows the same continuous camera approach in both directions:
	# existing blur amount → 0 at the close-up; closing restores the exact
	# captured authored values without a snap.
	if _dof_attributes != null:
		_dof_attributes.dof_blur_amount = lerpf(_source_dof_blur_amount, 0.0, amount)

func _blend_environment(amount: float) -> void:
	# Keep the original environment throughout approach; never mutate shared resources.
	var env := _camera.environment
	for key in ["background_color", "ambient_light_color"]:
		env.set(key, (_source_environment.get(key) as Color).lerp(_city_environment.get(key), amount))
	for key in ["background_energy_multiplier", "ambient_light_energy", "tonemap_exposure", "glow_intensity", "glow_bloom", "glow_hdr_threshold", "fog_density", "volumetric_fog_density", "ssao_intensity", "ssil_intensity", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation"]:
		env.set(key, lerpf(float(_source_environment.get(key)), float(_city_environment.get(key)), amount))
	for key in ["background_mode", "ambient_light_source", "tonemap_mode", "glow_enabled", "fog_enabled", "volumetric_fog_enabled", "ssao_enabled", "ssil_enabled", "adjustment_enabled"]:
		env.set(key, _city_environment.get(key) if amount >= 0.999 else _source_environment.get(key))
	# Keep the copied attributes alive at the close-up: only its DOF amount is
	# animated, while all other authored camera-attribute values stay unchanged.
	_camera.attributes = _dof_attributes if _dof_attributes != null else (null if amount >= 0.999 else _original_camera.attributes)
	_camera.compositor = null if amount >= 0.999 else _original_camera.compositor

func _input(event: InputEvent) -> void:
	if not is_instance_valid(_camera):
		return
	# Scene replacement detaches this node synchronously. Consume before dispatch.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		request_close()
	elif _state == "active":
		if event is InputEventMouseMotion:
			# _pick 返回可见关卡索引、RETURN_PICK = 返回、-1 = 未命中。
			# 焦点必须如实反映"当前指着谁"，包括指向空白；只有选中项才在移开时保留。
			var hovered := _pick(event.position)
			_focus = hovered if hovered >= 0 and hovered < LEVEL_IDS.size() else -1
			if hovered >= 0 and hovered < LEVEL_IDS.size():
				_selection = hovered
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var picked := _pick(event.position)
			if picked == RETURN_PICK:
				request_close()
			elif picked >= 0:
				_selection = picked
				_focus = picked
				confirm_selection()
		elif event.is_action_pressed("ui_accept"):
			confirm_selection()
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
			_shift_selection(posmod(_selection - 1, LEVEL_IDS.size()))
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
			_shift_selection(posmod(_selection + 1, LEVEL_IDS.size()))
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode in [KEY_A, KEY_W, KEY_D, KEY_S]:
				_shift_selection(posmod(_selection + (-1 if event.physical_keycode in [KEY_A, KEY_W] else 1), LEVEL_IDS.size()))
		elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			if absf(event.axis_value) < 0.3:
				_axis_latched = false
			elif absf(event.axis_value) > 0.65 and not _axis_latched:
				_axis_latched = true
				_shift_selection(posmod(_selection + (-1 if event.axis_value < 0.0 else 1), LEVEL_IDS.size()))

func _shift_selection(index: int) -> void:
	# 键盘/手柄切换时把焦点一起带过去，否则光标停在空白后按键看不出选中了谁。
	_selection = index
	_focus = index

func _pick(screen: Vector2) -> int:
	if _state != "active":
		return -1
	var origin := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	for i in LEVEL_IDS.size():
		var marker: Node3D = _city.markers[i]
		var local_origin := marker.to_local(origin)
		var local_dir := marker.global_basis.inverse() * direction
		if absf(local_dir.z) > 0.00001:
			var t := (0.12 - local_origin.z) / local_dir.z
			var p := local_origin + local_dir * t
			if t > 0.0 and absf(p.x) < 1.8 and absf(p.y) < 1.3:
				return i
		var site: Node3D = _city.sites[i]
		var plane := Plane(Vector3.UP, site.global_position.y)
		var hit: Variant = plane.intersects_ray(origin, direction)
		if hit != null and Vector2(hit.x - site.global_position.x, hit.z - site.global_position.z).length() < 0.18:
			return i
	var back: Node3D = _city.return_marker
	if not _camera.is_position_behind(back.global_position) and _camera.unproject_position(back.global_position).distance_to(screen) < 45:
		return RETURN_PICK
	return -1

func request_close() -> void:
	if _departing or _state == "closing":
		return
	# 先记下按下瞬间的真实状态，关闭动画才可能从这一刻起播而不是从平台期之后。
	_close_from_progress = maxf(_progress, 0.0001)
	_close_deploy_from = _city.deployment if is_instance_valid(_city) else 1.0
	_close_eased_from = smoothstep(0.0, 0.55, _progress)
	_close_entry_from = _city.entry_deployment if is_instance_valid(_city) else 0.0
	_state = "closing"

func _on_close_pressed() -> void:
	request_close()

func _on_teleport_pressed() -> void:
	_enter_level(GameDesignConfig.default_expedition_level_id())


## 把"本局情报室列出哪些入口"算出来，顺序按 `nav_order`。
##
## 可见性（`nav_visibility`）与可出发性是**两件事**，故意分层：
## - 可见性回答"这个入口在不在全息城里"（表现层），由配置的 `nav_visibility` 决定：
##   `always` = 恒列出（缺省值）；`on_unlock` = 玩家解锁后才列出（远征02 的旧口径）。
## - 可出发性回答"点下去会不会真的走"（玩法权限），由 `BaseManager` 的解锁状态
##   + 到达场景是否存在共同决定，见 `_enter_level()`。
##
## 为什么不用 `ResourceLoader.exists()` 来推可见性：验收套件在隔离工程副本里跑，
## 场景"在不在"的判定会随导入状态变化 —— 一旦拿它决定可见性，
## 同一份配置在头尾两次验收里会给出不同的入口数量，门禁就不稳了。
func _refresh_level_ids() -> void:
	LEVEL_IDS.clear()
	for level_id in GameDesignConfig.expedition_nav_order():
		var entry := GameDesignConfig.expedition_level(level_id)
		if entry.is_empty():
			continue
		if str(entry.get("nav_visibility", "always")) == "on_unlock" \
				and not BaseManager.is_expedition_level_unlocked(level_id):
			continue
		LEVEL_IDS.append(level_id)


## 未开放/未解锁的入口，点下去要给准确回执，而不是静默不动。
##
## 「准确」指的是**说对是哪一种**：场景没建（尚未开放）和还没解锁（尚未解锁）
## 对玩家是两件事 —— 前者只能等，后者去通关前置关卡就行。
## 旧版无论哪种都写「尚未开放」，而牌面（`HologramCity3D` 只看场景在不在）
## 又会一直写「点击进入」，两处说法还互相矛盾。
func _notify_entry_blocked(level_id: String, message: String) -> void:
	if is_instance_valid(_city):
		_city.status.text = message + "  ·  ESC 返回"
		var index := LEVEL_IDS.find(level_id)
		if index >= 0 and index < _city.entry_hints.size():
			_city.entry_hints[index].text = _entry_hint_text(level_id)


## 入口状态：**唯一判定处**。「场景在不在」+「解没解锁」两道门都在这里。
## 牌面文案与点击后的回执都由它派生，因此不会再出现「牌面说能进、按下去说进不去」。
const ENTRY_OPEN := "open"
const ENTRY_COMING_SOON := "coming_soon"
const ENTRY_LOCKED := "locked"

func entry_state(level_id: String) -> String:
	var entry := GameDesignConfig.expedition_level(level_id)
	if entry.is_empty():
		return ENTRY_COMING_SOON
	if not ResourceLoader.exists(str(entry.get("scene_3d", ""))):
		return ENTRY_COMING_SOON
	if not BaseManager.is_expedition_level_unlocked(level_id):
		return ENTRY_LOCKED
	return ENTRY_OPEN

func _entry_hint_text(level_id: String) -> String:
	match entry_state(level_id):
		ENTRY_OPEN:
			return "点击进入  ·  ENTER"
		ENTRY_LOCKED:
			return "尚未解锁  ·  LOCKED"
		_:
			return "尚未开放"

func _on_alternate_level_pressed(level_id: String) -> void:
	_enter_level(level_id)

func confirm_selection() -> void:
	if _state == "active":
		if is_instance_valid(_city):
			_city.punch_marker(_selection)
		_enter_level(LEVEL_IDS[_selection])

func _enter_level(level_id: String) -> void:
	if _departing or _state == "closing":
		return
	var display_name := GameDesignConfig.expedition_level_display_name(level_id)
	# 顺序有意为之：先查"到达场景在不在"，再查解锁。
	# 反过来（先查解锁就 return）会让"未解锁 + 场景没建"的关卡点下去毫无反应 ——
	# 玩家分不清是没解锁还是没做完，也无从判断该等哪一样。
	# 两道门与牌面文案共用 `entry_state()`，因此点下去的提示与牌面永远一致。
	match entry_state(level_id):
		ENTRY_COMING_SOON:
			_notify_entry_blocked(level_id, "%s尚未开放" % display_name)
			return
		ENTRY_LOCKED:
			_notify_entry_blocked(level_id, "%s尚未解锁" % display_name)
			return
	if not GameDesignConfig.select_expedition_level(level_id):
		return
	_departing = true
	_state = "entering"
	_pending_level_id = level_id
	# 弹性反馈先播完这 0.18s 再交接，出发逻辑本身不动。
	_depart_countdown = PUNCH_HOLD
	if _depart_countdown <= 0.0:
		_commit_departure()

## 出发收拢的圆心：把主角投影到屏幕归一化坐标，做到"黑圈往角色中间收进去"。
## 任何一步拿不到可信数据就回退屏幕中心 —— 只影响观感，不影响任何判定。
func _iris_center() -> Vector2:
	var fallback := Vector2(0.5, 0.5)
	if _camera == null or not is_instance_valid(_camera):
		return fallback
	if _player == null or not is_instance_valid(_player):
		return fallback
	var viewport := _camera.get_viewport()
	if viewport == null:
		return fallback
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return fallback
	var focus := _player.global_position + Vector3(0.0, 0.75, 0.0)
	if _camera.is_position_behind(focus):
		return fallback
	var screen := _camera.unproject_position(focus)
	return Vector2(
		clampf(screen.x / size.x, 0.0, 1.0),
		clampf(screen.y / size.y, 0.0, 1.0)
	)

func _commit_departure() -> void:
	if _state != "entering" or _pending_level_id == "":
		return
	_state = "departing"
	var ticket := ExpeditionDepartureService.prepare(get_parent(), ExpeditionEntryContext.BASE)
	if not bool(ticket.get("success", false)):
		_departure_failed(str(ticket.get("message", "出发失败，请重试")))
		return
	var request_id := GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT, GameEntryFlow.SPAWN_SAVED_PROGRESS)
	# 出发过场：黑圈往屏幕中心收拢，把整屏压到全黑之后再切读取界面。
	# 读取界面的纯黑底正好接手（它在 _ready 里放开遮罩），视觉上无缝。
	# 无头验收跳过：保持"读条结束即同步 change_scene"这条既有门禁时序。
	# 🔴 本函数因此在真实运行时成为协程 —— `_state` 已在 await 之前置为 "departing"，
	# `_process` 的重复调用会被 `_state != "entering"` 挡掉，不会重入。
	if DisplayServer.get_name() != "headless" and IrisTransition != null:
		await IrisTransition.iris_close(IrisTransition.CLOSE_SECONDS, _iris_center())
	var error := get_tree().change_scene_to_file(LOADING_SCENE)
	if error != OK:
		if request_id > 0:
			GameEntryFlow.cancel_request(request_id)
		ExpeditionDepartureService.rollback(ticket)
		_departure_failed("读取界面加载失败，请重试")

func _departure_failed(message: String) -> void:
	_departing = false
	_pending_level_id = ""
	_state = "active"
	GameDesignConfig.pending_expedition_level_id = ""
	if is_instance_valid(_city):
		_city.status.text = message + "  ·  ESC 返回"
	push_error("[HologramCity] " + message)

func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_mode
	if is_instance_valid(_original_camera) and _original_camera.is_inside_tree():
		_original_camera.make_current()
	for item in _world_fades:
		if is_instance_valid(item.node):
			item.node.transparency = float(item.transparency)
	if is_instance_valid(_facility) and _facility.has_method("set_hologram_city_blend"):
		_facility.call("set_hologram_city_blend", 0.0)
	for item in _hidden:
		if is_instance_valid(item):
			item.show()
	if is_instance_valid(_player) and not _previous_input_lock:
		_player.call("set_input_locked", false)
	if is_instance_valid(_camera):
		_camera.queue_free()
	if is_instance_valid(_city):
		_city.queue_free()
