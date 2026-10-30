class_name RoomDoor3D
extends StaticBody3D
## 一条地图边在房间侧的实体门。地图边状态由 Dungeon3D 统一管理，门只负责表现、阻挡和提示。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const PANEL_THICKNESS_M := 0.18
const COLLISION_DEPTH_M := 0.42
const OPEN_LIFT_CLEARANCE_M := 0.32
const DEFAULT_MOTION_DURATION_S := 0.24

## 开合方式。**默认是升降**（`lift`），塔楼、基地99F、远征01/02 全部走它 —— 逐字不变。
## `slide` 是双扇对开（左右滑开），只给远征03 这类 EGT 房间用（业主 2026-10-28 要求）。
const OPENING_STYLE_LIFT := "lift"
const OPENING_STYLE_SLIDE := "slide"
## 双扇**可视宽度的放大系数**。
##
## 为什么不是正好 0.5（每扇半个门洞）：门板美术是「一整扇 2.2m 的门」，四周留了边框内缩，
## 压到 50% 时中间会露出深色竖缝。放大到 55% 后每扇覆盖 1.21m，中间有 0.11m 真实重叠、
## 两端各超出门洞 0.055m（被墙挡住）。
##
## ⚠️ 关门时中间那条**亮线不是缝**：把两扇材质换成纯色无光照后实测 80 列全是纯色、
## 非纯色 0 列 —— 几何完全覆盖。那条亮线是门板美术自带的发光竖条（原本在单扇门的中央，
## 压扁后跟着落在每扇中央）。改动前请先读这条，别再去调宽度系数"修缝"。
const SLIDE_PANEL_WIDTH_SCALE := 1.10
## 右扇沿门厚方向让开 8mm。两扇在中间有重叠区，同 z 会 z-fighting（关闭时闪一条亮线）。
const SLIDE_PANEL_DEPTH_OFFSET_M := 0.008
## 开到位后，两扇门板沿门法线**向房间内侧**偏移的距离。
##
## 业主 2026-10-30：「远征03 的其它房间的门，应该是可打开和不可打开的状态，
## 而不是直接消失」。滑门只走 x 方向时，门板整块退进门洞外的墙体
## （墙厚 0.28 > 门板 0.18），深度测试把它挡在墙后 —— 玩家看到的是一个空洞，
## 分不清"这里本来有门"还是"这只是一条通道"。
##
## 数值 = 墙半厚 0.14 + 门板半厚 0.09：门板背面正好贴在墙内表面，
## 门洞全通不占宽度，同时两块门板始终留在视野里，开门/关门是两种可分辨的形态。
##
## ⚠️ 与 2026-10-28「门看起来贴在墙外面」不是同一件事：那次是基地 99F 的**滑升门体**
## （可视厚度 0.88m）滑到门洞两侧时凸出 0.31m，露出一整块蓝门体；这里是 0.18m 厚的
## 门板贴墙，凸出量只有门板自身厚度，观感是"门板收在墙边"。
const SLIDE_PARKED_WALL_INSET_M := 0.23

## —— 感应自动开合（远征03 房门的「可开启」态）——
##
## 业主 2026-10-30：「这个门的状态，使用可开启和不可开启。在可开启状态，
## 人走近了会自动打开，然后再关闭。不可开启状态人走近了不会打开。」
##
## 于是门的**权限**（`openable`）与门的**位置**（`is_open`）拆成两件事：
##   · `openable = true`  ⇒ 门关着但允许通行，玩家靠近即自动开、离开即自动关；
##   · `openable = false` ⇒ 门关着且拒绝一切自动开启（战斗封锁 / 退局气闸）。
## 原先"清了房就把门永远推开"的写法让「可开启」这个状态在画面上根本不存在 ——
## 门要么开着、要么关死，玩家读不出"这扇门能不能过"。
const PROXIMITY_OPEN_DISTANCE_M := 3.6
const PROXIMITY_CLOSE_DISTANCE_M := 4.4
## 离开后的关闭延迟：给玩家一个"已经过去了"的余量，也避免贴着门框反复开合。
const PROXIMITY_CLOSE_DELAY_S := 0.45

## 门扇动画结束（开到位或关到底）。门不是 Area3D，交互靠距离判定，
## 因此"门关上了"这个事实只能从这里发出，供上层订阅。
signal motion_finished(is_open: bool)

var direction := "east"
var target_room_id := ""
## 可开启 / 不可开启。**权限**，与 `is_open` 的位置状态正交。
var openable := true
var is_open := false
var requires_key := true
var requires_clear := true
var triggers_fate := true
var _panel: Node3D
## 双扇对开的第二扇（只 `slide` 模式存在；`lift` 模式恒为 null）。
var _panel_right: Node3D
var _opening_style := OPENING_STYLE_LIFT
var _presentation_clear_width_m := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M
var _collision: CollisionShape3D
var _prompt: Label3D
var _panel_visual_scene: PackedScene
var _motion_duration_s := DEFAULT_MOTION_DURATION_S
var _collision_tracks_panel_motion := false
var _manual_close_enabled := false
var _prompt_override := ""
var _motion_tween: Tween
var _transitioning := false
var _target_open := false
var _presentation_clear_height_m := TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M
## 感应开合的检测目标（本局玩家）。为 null = 本门不走感应，行为与旧版逐字一致。
var _proximity_target: Node3D
var _proximity_close_elapsed := 0.0

## Geometry-only adaptation; access policy and motion state stay owned by the map edge.
func set_presentation_opening(width_m: float, height_m: float) -> void:
	_presentation_clear_width_m = width_m
	_presentation_clear_height_m = height_m
	if _collision != null and _collision.shape is BoxShape3D:
		var shape := (_collision.shape as BoxShape3D).duplicate() as BoxShape3D
		shape.size = Vector3(width_m, height_m, COLLISION_DEPTH_M)
		_collision.shape = shape
		_collision.position.y = height_m * 0.5
	set_open(is_open, true)


## 选择开合方式。**必须在 `configure()` 之前调用** —— 面板结构在 `_build()` 里按它生成。
func set_opening_style(style: String) -> void:
	_opening_style = (
		OPENING_STYLE_SLIDE if style == OPENING_STYLE_SLIDE else OPENING_STYLE_LIFT
	)


func get_opening_style() -> String:
	return _opening_style


func configure(
	p_direction: String,
	p_target_room_id: String,
	accent: Color,
	p_panel_visual_scene: PackedScene = null
) -> void:
	direction = p_direction
	target_room_id = p_target_room_id
	_panel_visual_scene = p_panel_visual_scene
	_build(accent)


func set_access_policy(policy: Dictionary) -> void:
	requires_key = bool(policy.get("requires_key", true))
	requires_clear = bool(policy.get("requires_clear", true))
	triggers_fate = bool(policy.get("triggers_fate", true))
	_refresh_prompt()


func set_motion_profile(duration_s: float, collision_tracks_panel := false) -> void:
	_motion_duration_s = clampf(duration_s, 0.05, 2.0)
	_collision_tracks_panel_motion = collision_tracks_panel
	if _collision == null or _panel == null:
		return
	# CollisionShape3D必须保持为StaticBody3D的直接子节点才会参与物理。
	# 同步模式通过并行动画保持其Y与门板一致，而不是把碰撞挂到视觉节点下。
	if _collision_tracks_panel_motion:
		_collision.position.y = _panel.position.y


func set_manual_close_enabled(enabled: bool) -> void:
	_manual_close_enabled = enabled
	_refresh_prompt()


## 设置「可开启 / 不可开启」。
##
## 不可开启 ⇒ 立刻回到关闭态并保持（门板挡在门洞，玩家一眼读得出过不去）。
## 可开启 ⇒ **不在这里开门**：开合交给感应（`_process`），否则又回到
## 「清了房门就永远敞开」的老样子，玩家无从分辨两种状态。
func set_openable(value: bool, immediate := false) -> void:
	openable = value
	_proximity_close_elapsed = 0.0
	if not value:
		set_open(false, immediate)
	_refresh_prompt()


func is_openable() -> bool:
	return openable


## 交给门自己去盯的玩家节点。**只有 flow 关卡的门**会被设上，
## 其余关卡（塔楼 / 基地 / 远征01-02）保持 null ⇒ `_process` 不跑，行为不变。
func set_proximity_target(target: Node3D) -> void:
	_proximity_target = target
	_proximity_close_elapsed = 0.0
	set_process(target != null)


## 感应门是否需要玩家按 E —— 玩家一走近它就开，交互圆点与提示都应让位。
## 退役判定留在门自己手里，`Dungeon3D.get_interaction_candidate` 只读结果。
func has_proximity_target() -> bool:
	return _proximity_target != null


func is_manual_interaction_enabled() -> bool:
	return _proximity_target == null


## 感应开合：近则开、远则关（带迟滞与延迟，避免门框上反复抽搐）。
##
## 只做表现与阻挡，不改任何门态账：`openable` 由上层（`TowerDescent3D`）按
## 「封锁 / 可通行」推导，本函数只消费它。门态仍然不存档。
func _process(delta: float) -> void:
	if _proximity_target == null or not is_instance_valid(_proximity_target):
		return
	if not openable or _transitioning:
		_proximity_close_elapsed = 0.0
		return
	var distance := _proximity_target.global_position.distance_to(global_position)
	if distance <= PROXIMITY_OPEN_DISTANCE_M:
		_proximity_close_elapsed = 0.0
		if not is_open:
			set_open(true)
		return
	if not is_open:
		_proximity_close_elapsed = 0.0
		return
	if distance <= PROXIMITY_CLOSE_DISTANCE_M:
		_proximity_close_elapsed = 0.0
		return
	_proximity_close_elapsed += delta
	if _proximity_close_elapsed < PROXIMITY_CLOSE_DELAY_S:
		return
	_proximity_close_elapsed = 0.0
	set_open(false)


func set_prompt_override(text: String) -> void:
	_prompt_override = text
	_refresh_prompt()


func is_in_motion() -> bool:
	return _transitioning


func set_open(opened: bool, immediate := false) -> void:
	if _transitioning and _target_open == opened and not immediate:
		return
	var changed := is_open != opened or (_transitioning and _target_open != opened)
	is_open = opened
	_target_open = opened
	if _panel == null:
		if _collision != null:
			_collision.set_deferred("disabled", opened)
		_transitioning = false
		_refresh_prompt()
		return
	if _opening_style == OPENING_STYLE_SLIDE:
		_set_open_slide(opened, changed, immediate)
		return
	var closed_y := _presentation_clear_height_m * 0.5
	var open_y := _presentation_clear_height_m * 1.5 + OPEN_LIFT_CLEARANCE_M
	var target_y := (
		open_y
		if opened
		else closed_y
	)
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	if immediate or not is_inside_tree() or not changed:
		_transitioning = false
		_panel.position.y = target_y
		if _collision != null:
			if _collision_tracks_panel_motion:
				_collision.position.y = target_y
			_collision.set_deferred("disabled", opened)
		_refresh_prompt()
		return
	_transitioning = true
	# 专用升降门的碰撞与门板同步运动；普通房门继续保持旧的即时放行合同，
	# 避免改变既有战斗门节奏。
	if _collision != null:
		_collision.set_deferred(
			"disabled",
			false if _collision_tracks_panel_motion else opened
		)
	var full_travel := maxf(0.001, open_y - closed_y)
	var travel_ratio := clampf(absf(target_y - _panel.position.y) / full_travel, 0.05, 1.0)
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_motion_tween.set_parallel(_collision_tracks_panel_motion and _collision != null)
	_motion_tween.tween_property(
		_panel,
		"position:y",
		target_y,
		_motion_duration_s * travel_ratio
	)
	if _collision_tracks_panel_motion and _collision != null:
		_motion_tween.tween_property(
			_collision,
			"position:y",
			target_y,
			_motion_duration_s * travel_ratio
		)
	_motion_tween.finished.connect(_on_motion_finished.bind(opened, target_y))
	_refresh_prompt()
	if opened and AudioManager != null:
		AudioManager.play_sfx("door_open", -3.0)


## 双扇对开：两扇各占半个门洞，向左右滑出门洞，开到位后贴到门墙内侧。
##
## 只走 x 方向时门板会整块没入墙体、在画面上"消失"（见 `SLIDE_PARKED_WALL_INSET_M`）。
## 现在开到位后额外挪到墙内侧，门洞照旧全通，但两块门板始终可见 ——
## 「可打开 / 不可打开」两种状态从画面上就能读出来。
##
## 碰撞仍是**单块覆盖整个门洞**（不跟门板走）：门开到一半时人钻不过去，
## 开完立即放行，与既有普通房门的放行语义一致（`_collision_tracks_panel_motion`
## 只服务于基地 99F 那种"碰撞随门板升降"的滑升门）。
##
## ⚠️ 贴墙是**纯表现**：行程、碰撞禁用时机、`is_open` 与门态判定逐字未动。
func _set_open_slide(opened: bool, changed: bool, immediate: bool) -> void:
	var y := _presentation_clear_height_m * 0.5
	var half_width := _presentation_clear_width_m * 0.5
	var quarter := half_width * 0.5
	# 开到位 = 门板的内缘退到门洞边线之外。门板半宽比 quarter 大
	# （SLIDE_PANEL_WIDTH_SCALE），行程必须按**门板实际半宽**算，否则会有一小截
	# 门板仍压在门洞里 —— 视觉上就是"门开了但洞口没全通"。
	var panel_half := quarter * SLIDE_PANEL_WIDTH_SCALE
	var travel := half_width - quarter + panel_half
	var left_target := -quarter - (travel if opened else 0.0)
	var right_target := quarter + (travel if opened else 0.0)
	# 开到位后整体挪到墙内侧；关着时回门洞中央。
	var park_z := (SLIDE_PARKED_WALL_INSET_M * _slide_inward_sign()) if opened else 0.0
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	if immediate or not is_inside_tree() or not changed:
		_transitioning = false
		if _panel != null:
			_panel.position = Vector3(left_target, y, park_z)
		if _panel_right != null:
			_panel_right.position = Vector3(
				right_target, y, park_z + SLIDE_PANEL_DEPTH_OFFSET_M
			)
		if _collision != null:
			_collision.set_deferred("disabled", opened)
		_refresh_prompt()
		return
	_transitioning = true
	if _collision != null:
		_collision.set_deferred("disabled", opened)
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_motion_tween.set_parallel(true)
	if _panel != null:
		_motion_tween.tween_property(
			_panel, "position", Vector3(left_target, y, park_z), _motion_duration_s
		)
	if _panel_right != null:
		_motion_tween.tween_property(
			_panel_right,
			"position",
			Vector3(right_target, y, park_z + SLIDE_PANEL_DEPTH_OFFSET_M),
			_motion_duration_s
		)
	_motion_tween.finished.connect(
		_on_slide_finished.bind(opened, left_target, right_target, park_z)
	)
	_refresh_prompt()
	if opened and AudioManager != null:
		AudioManager.play_sfx("door_open", -3.0)


## 门板"收进门墙内侧"的局部 z 符号。
##
## `_build_door()` / `_build_door_for_port()` 对 `west` / `east` 都设了
## `rotation.y = +90°`，于是「局部 +z」在世界里统一落到 ±x / ±z 两个方向之一；
## 再按门挂在哪面墙上判断哪边朝房间内：
##
## | 墙 | 门在房间的位置 | 房间内侧 | 局部 z 符号 |
## |---|---|---|---|
## | north | z = −half | +z | +1 |
## | south | z = +half | −z | −1 |
## | west  | x = −half（转 90°）| +x | +1 |
## | east  | x = +half（转 90°）| −x | −1 |
func _slide_inward_sign() -> float:
	match direction:
		"south", "east":
			return -1.0
		_:
			return 1.0


func _on_slide_finished(
	opened: bool, left_target: float, right_target: float, park_z: float
) -> void:
	if _target_open != opened:
		return
	_transitioning = false
	motion_finished.emit(opened)
	if _panel != null:
		_panel.position = Vector3(left_target, _panel.position.y, park_z)
	if _panel_right != null:
		_panel_right.position = Vector3(
			right_target, _panel_right.position.y, park_z + SLIDE_PANEL_DEPTH_OFFSET_M
		)
	if _collision != null:
		_collision.set_deferred("disabled", opened)
	_refresh_prompt()


func _on_motion_finished(opened: bool, target_y: float) -> void:
	if _target_open != opened:
		return
	_transitioning = false
	motion_finished.emit(opened)
	if _panel != null:
		_panel.position.y = target_y
	if _collision != null:
		if _collision_tracks_panel_motion:
			_collision.position.y = target_y
		_collision.set_deferred("disabled", opened)
	_refresh_prompt()


## 文字提示牌退役为纯文案载体（`_prompt.text` 仍被候选协议与多枚探针读取）。
## 可见反馈统一交给 PlayerInteractionController3D 的常驻圆点，圆点锚点取本牌位置。
func set_prompt_visible(_show_prompt: bool) -> void:
	pass


## 常驻圆点锚点：沿用原提示牌的位置。
func get_interaction_dot_anchor() -> Vector3:
	if _prompt != null and is_instance_valid(_prompt):
		return _prompt.global_position
	return global_position + Vector3.UP * (TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M + 0.62)


## 已开启且不允许手动关闭的门不再可交互 —— 圆点随之淡出，玩家一眼能看出哪扇门还能开。
func is_interaction_dot_visible() -> bool:
	if _transitioning:
		return true
	return not is_open or _manual_close_enabled



func get_interaction_prompt_text() -> String:
	return _prompt.text if _prompt != null else "[E] 开启通道"


func get_snapshot() -> Dictionary:
	return {
		"direction": direction,
		"target_room_id": target_room_id,
		"is_open": is_open,
		# 权限与位置分开报：`openable` 才是「可开启 / 不可开启」，
		# 只看 `is_open` 会把「关着但能开」和「关着且开不了」混成一件事。
		"openable": openable,
		"proximity_auto": _proximity_target != null,
		"requires_key": requires_key,
		"requires_clear": requires_clear,
		"triggers_fate": triggers_fate,
		"blocks_passage": _collision != null and not _collision.disabled,
		"transitioning": _transitioning,
		"target_open": _target_open,
		"motion_duration_s": _motion_duration_s,
		"collision_tracks_panel_motion": _collision_tracks_panel_motion,
		"collision_is_direct_body_child": _collision != null and _collision.get_parent() == self,
		"panel_y": _panel.position.y if _panel != null else 0.0,
		"collision_y": _collision.position.y if _collision != null else 0.0,
		"opening_style": _opening_style,
		"panel_x": _panel.position.x if _panel != null else 0.0,
		"second_panel_x": _panel_right.position.x if _panel_right != null else 0.0,
		# 门板沿门法线的偏移。`slide` 开到位时它等于 `SLIDE_PARKED_WALL_INSET_M`，
		# 是「门板没有埋进墙里、玩家看得见」的唯一可测判据。
		"panel_z": _panel.position.z if _panel != null else 0.0,
		"clear_width_m": TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
		"clear_height_m": TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
		"panel_size": Vector3(
			TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
			TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
			PANEL_THICKNESS_M
		),
		"visual_asset_id": str(get_meta("visual_asset_id", "")),
		"is_3d": true,
	}


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	if not _prompt_override.is_empty() and not _transitioning and not is_open:
		_prompt.text = _prompt_override
		_prompt.modulate = Color(1.0, 0.42, 0.28)
		return
	if _transitioning:
		_prompt.text = "通道开启中…" if _target_open else "通道关闭中…"
		_prompt.modulate = Color(0.52, 0.88, 1.0)
	elif not openable:
		# 不可开启：门扇落下、拒绝通行。文字只是数据载体（提示牌已退役），
		# 但 `get_interaction_prompt_text()` 仍被探针读取，语义要如实。
		_prompt.text = "门扇已落下 · 无法开启"
		_prompt.modulate = Color(1.0, 0.42, 0.28)
	elif is_open and _manual_close_enabled:
		_prompt.text = "[E] 关闭通道"
		_prompt.modulate = Color(0.52, 0.88, 1.0)
	elif is_open:
		_prompt.text = "通道已开启"
		_prompt.modulate = Color(0.42, 0.92, 0.68)
	elif requires_key:
		_prompt.text = "[E] 使用房间钥匙"
		_prompt.modulate = Color(1.0, 0.72, 0.22)
	elif triggers_fate:
		_prompt.text = "[E] 开启入口 · 选择命运"
		_prompt.modulate = Color(0.44, 0.88, 1.0)
	else:
		_prompt.text = "[E] 开启通道"
		_prompt.modulate = Color(0.52, 0.94, 0.80)


func _build(accent: Color) -> void:
	if _panel != null:
		return
	name = "Door_%s" % direction.capitalize()
	collision_layer = 1
	collision_mask = 0
	var clear_width := _presentation_clear_width_m
	var clear_height := _presentation_clear_height_m
	if _opening_style == OPENING_STYLE_SLIDE:
		# 双扇对开：两扇各覆盖半个门洞，中心分居两侧。
		# 每扇的可视宽度故意比半个门洞宽（SLIDE_PANEL_WIDTH_SCALE），
		# 于是中间有真实重叠、不会露出那条竖缝（见该常量的注释）。
		var quarter := clear_width * 0.25
		var slide_scale := 0.5 * SLIDE_PANEL_WIDTH_SCALE
		_panel = Node3D.new()
		_panel.name = "DoorPanel"
		_panel.position = Vector3(-quarter, clear_height * 0.5, 0.0)
		add_child(_panel)
		_attach_panel_visual(_panel, slide_scale, accent)
		_panel_right = Node3D.new()
		_panel_right.name = "DoorPanelRight"
		_panel_right.position = Vector3(
			quarter, clear_height * 0.5, SLIDE_PANEL_DEPTH_OFFSET_M
		)
		add_child(_panel_right)
		_attach_panel_visual(_panel_right, slide_scale, accent)
	else:
		_panel = Node3D.new()
		_panel.name = "DoorPanel"
		_panel.position.y = clear_height * 0.5
		add_child(_panel)
		_attach_panel_visual(_panel, 1.0, accent)
	var shape := BoxShape3D.new()
	shape.size = Vector3(clear_width, clear_height, COLLISION_DEPTH_M)
	_collision = CollisionShape3D.new()
	_collision.name = "DoorCollision"
	_collision.position.y = clear_height * 0.5
	_collision.shape = shape
	add_child(_collision)
	_prompt = Label3D.new()
	_prompt.name = "DoorPrompt"
	_prompt.position = Vector3(0, clear_height + 0.62, 0)
	_prompt.text = "[E] 使用房间钥匙"
	_prompt.font_size = 38
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 8
	_prompt.visible = false
	add_child(_prompt)
	set_open(false, true)
	# 默认不跑感应：塔楼 / 基地 / 远征01-02 的门永远拿不到 `_proximity_target`，
	# 关掉 process 以免几百扇门每帧各跑一次判空。flow 门由 `set_proximity_target()` 打开。
	set_process(false)


## 给一扇门板挂视觉。`width_scale` < 1 用于双扇对开：把整扇门压成半宽。
##
## 压扁是刻意的取舍：美术包只有"一整扇 2.2m 门"，没有左右半扇的版本。
## 换成"裁剪一半"需要给美术材质加 discard（会丢掉 PaletteUV 色盘），
## 而"两扇各用完整视觉并重叠"会在关闭时互相穿模。压扁 50% 后门的横条与灯点略窄，
## 但在游戏视角（10m 高俯视）几乎看不出来，且不引入任何穿模/色盘风险。
func _attach_panel_visual(panel: Node3D, width_scale: float, accent: Color) -> void:
	if _panel_visual_scene != null:
		var visual := _panel_visual_scene.instantiate() as Node3D
		visual.name = "ImportedDoorVisual"
		# 导入门以底边中心为原点；DoorPanel 动画根仍以门中心为基准。
		visual.position.y = -_presentation_clear_height_m * 0.5
		if not is_equal_approx(width_scale, 1.0):
			visual.scale = Vector3(width_scale, 1.0, 1.0)
		# 门板宽 2.2m 是美术包的名义尺寸；缩放后碰撞仍是完整的半个门洞。
		panel.add_child(visual)
		_set_geometry_shadow_casting(visual, true)
		set_meta("visual_asset_id", str(visual.get_meta("asset_id", "")))
		set_meta("shadow_policy", "cast_and_receive")
	else:
		_build_procedural_panel(accent, width_scale)


## 降级门板：只剩一块深色实心板。形参保留 `configure(accent) → _build(accent)` 的
## 调用契约，本函数已不再消费它。
## 2026-09-19 起两条运行时调用点（DungeonRoom3D._build_door、
## TowerDescent3D._install_base_rooftop_transit_door）都传正式门扇 prefab，
## 因此本路径只能由「显式传 null」触发，不是「prefab 加载失败」的兜底
## ——prefab 路径走的是编译期 preload，缺文件会直接编译失败，不会静默降级到这里。
## 保留它是为了让「本局不要门板」这种明确诉求有一个出口。
func _build_procedural_panel(_accent: Color, width_scale := 1.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.13, 0.13)
	material.metallic = 0.78
	material.roughness = 0.34
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(
		_presentation_clear_width_m * width_scale,
		_presentation_clear_height_m,
		PANEL_THICKNESS_M
	)
	panel_mesh.material = material
	var panel_visual := MeshInstance3D.new()
	panel_visual.name = "ProceduralDoorPanel"
	panel_visual.mesh = panel_mesh
	_panel.add_child(panel_visual)
	# 原先这里还有一对 LockStripeFront / LockStripeBack（1.584×0.11×0.035m、
	# 离地 1.25m 的亮青色自发光横条）。它只是程序门板的点缀，不挂任何游戏逻辑
	# （无 meta、无碰撞、无外部引用），按需求已整体移除。


func _set_geometry_shadow_casting(root: Node, enabled: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in root.get_children():
		_set_geometry_shadow_casting(child, enabled)
