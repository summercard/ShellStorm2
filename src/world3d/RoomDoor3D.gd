class_name RoomDoor3D
extends StaticBody3D
## 一条地图边在房间侧的实体门。地图边状态由 Dungeon3D 统一管理，门只负责表现、阻挡和提示。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const PANEL_THICKNESS_M := 0.18
const COLLISION_DEPTH_M := 0.42
const OPEN_LIFT_CLEARANCE_M := 0.32
const DEFAULT_MOTION_DURATION_S := 0.24

var direction := "east"
var target_room_id := ""
var is_open := false
var requires_key := true
var requires_clear := true
var triggers_fate := true
var _panel: Node3D
var _collision: CollisionShape3D
var _prompt: Label3D
var _panel_visual_scene: PackedScene
var _motion_duration_s := DEFAULT_MOTION_DURATION_S
var _collision_tracks_panel_motion := false
var _manual_close_enabled := false
var _motion_tween: Tween
var _transitioning := false
var _target_open := false


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
	var closed_y := TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
	var open_y := TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 1.5 + OPEN_LIFT_CLEARANCE_M
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


func _on_motion_finished(opened: bool, target_y: float) -> void:
	if _target_open != opened:
		return
	_transitioning = false
	if _panel != null:
		_panel.position.y = target_y
	if _collision != null:
		if _collision_tracks_panel_motion:
			_collision.position.y = target_y
		_collision.set_deferred("disabled", opened)
	_refresh_prompt()


func set_prompt_visible(show_prompt: bool) -> void:
	if _prompt != null:
		_prompt.visible = show_prompt


func get_snapshot() -> Dictionary:
	return {
		"direction": direction,
		"target_room_id": target_room_id,
		"is_open": is_open,
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
	if _transitioning:
		_prompt.text = "通道开启中…" if _target_open else "通道关闭中…"
		_prompt.modulate = Color(0.52, 0.88, 1.0)
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
	_panel = Node3D.new()
	_panel.name = "DoorPanel"
	_panel.position.y = TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
	add_child(_panel)
	if _panel_visual_scene != null:
		var visual := _panel_visual_scene.instantiate() as Node3D
		visual.name = "ImportedDoorVisual"
		# 导入门以底边中心为原点；DoorPanel动画根仍以门中心为基准。
		visual.position.y = -TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
		_panel.add_child(visual)
		_set_geometry_shadow_casting(visual, true)
		set_meta("visual_asset_id", str(visual.get_meta("asset_id", "")))
		set_meta("shadow_policy", "cast_and_receive")
	else:
		_build_procedural_panel(accent)
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
		COLLISION_DEPTH_M
	)
	_collision = CollisionShape3D.new()
	_collision.name = "DoorCollision"
	_collision.position.y = TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
	_collision.shape = shape
	add_child(_collision)
	_prompt = Label3D.new()
	_prompt.name = "DoorPrompt"
	_prompt.position = Vector3(
		0,
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M + 0.62,
		0
	)
	_prompt.text = "[E] 使用房间钥匙"
	_prompt.font_size = 38
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 8
	_prompt.visible = false
	add_child(_prompt)
	set_open(false, true)


func _build_procedural_panel(accent: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.13, 0.13)
	material.metallic = 0.78
	material.roughness = 0.34
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
		PANEL_THICKNESS_M
	)
	panel_mesh.material = material
	var panel_visual := MeshInstance3D.new()
	panel_visual.name = "ProceduralDoorPanel"
	panel_visual.mesh = panel_mesh
	_panel.add_child(panel_visual)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = accent
	stripe_material.emission_enabled = true
	stripe_material.emission = accent
	stripe_material.emission_energy_multiplier = 1.5
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.72,
		0.11,
		0.035
	)
	stripe_mesh.material = stripe_material
	for z in [-0.17, 0.17]:
		var stripe := MeshInstance3D.new()
		stripe.name = "LockStripeFront" if z < 0.0 else "LockStripeBack"
		stripe.position.z = z
		stripe.mesh = stripe_mesh
		_panel.add_child(stripe)


func _set_geometry_shadow_casting(root: Node, enabled: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in root.get_children():
		_set_geometry_shadow_casting(child, enabled)
