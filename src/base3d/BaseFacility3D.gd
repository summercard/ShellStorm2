class_name BaseFacility3D
extends Area3D

const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")
const DEFAULT_BASE_SIZE_MULTIPLIER := 0.70
## 头顶常驻名字牌（设施名 + 实时摘要）已于 2026-09-29 按业主口径退役：
## 99F 基地设施头顶不再有常驻漂浮文字，设施可用时靠近出现的黄色交互提示是
## 头顶唯一的文字。NameLabel 节点仍保留在场景里 —— 快照 text/modulate 契约与
## 离线验收仍读它 —— 但运行时一律不显示。
const NAME_LABEL_VISIBLE := false
## 黄色交互提示接管原名字牌的位置：字号放大到 34（原资产 26），
## 锚点整体抬高 0.6 米。业主 2026-09-29：「那个黄色的字体放大一点，位置高一点」。
const PROMPT_LABEL_FONT_SIZE := 34
const PROMPT_LABEL_HEIGHT_LIFT_M := 0.6

signal activated(facility: BaseFacility3D)

enum ActivationType {
	OPEN_MENU,
	LOAD_SCENE,
	SHOW_INFO,
}

const FRONT_INTERACTION_PROFILES := {
	# 这三件大型设施贴墙摆放，交互区必须落在模型正面可站立区域，
	# 不能继续沿用包住整个模型的中心方盒。
	# 情报终端和枪械工坊的可操作面均朝向房间中心；只移动热区，禁止改设施Transform。
	"mission_operations": {"width": 5.4, "depth": 3.8, "height": 3.4, "overlap": 0.30},
	"weapon_workshop": {"width": 5.4, "depth": 3.8, "height": 3.4, "overlap": 0.30},
	"base_vending": {"width": 5.0, "depth": 4.4, "height": 3.4, "overlap": 0.30},
}

@export var facility_id := ""
@export var display_name := "基地设施"
@export_multiline var description := ""
@export var activation_type: ActivationType = ActivationType.OPEN_MENU
@export_file("*.tscn") var menu_scene_path := ""
@export_file("*.tscn") var target_scene_path := ""
@export_range(0, 99, 1) var target_floor := 0
@export var facility_color := Color(0.28, 0.55, 0.78)
@export var beacon_light_enabled := true
@export_range(0.1, 2.0, 0.05) var base_size_multiplier := DEFAULT_BASE_SIZE_MULTIPLIER

@onready var base_mesh: MeshInstance3D = get_node_or_null("Base") as MeshInstance3D
@onready var roof_mesh: MeshInstance3D = get_node_or_null("Roof") as MeshInstance3D
@onready var beacon_mesh: MeshInstance3D = get_node_or_null("Beacon") as MeshInstance3D
@onready var beacon_light: OmniLight3D = get_node_or_null("BeaconLight") as OmniLight3D
@onready var name_label: Label3D = $NameLabel
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range := false
var _available := true
var _snapshot: Dictionary = {}
var _base_size_applied := false


func configure_front_interaction_toward(world_target: Vector3) -> bool:
	if has_meta("interaction_shape_locked"):
		var locked_interaction := get_node_or_null("InteractionShape") as CollisionShape3D
		var locked_body := _find_primary_body_shape()
		return (
			locked_interaction != null
			and locked_interaction.shape != null
			and locked_body != null
			and locked_body.shape != null
		)
	var profile := FRONT_INTERACTION_PROFILES.get(facility_id, {}) as Dictionary
	if profile.is_empty():
		return false
	var interaction_shape := get_node_or_null("InteractionShape") as CollisionShape3D
	var body_shape_node := _find_primary_body_shape()
	if interaction_shape == null or body_shape_node == null:
		push_warning("[BaseFacility3D] Missing interaction/body shape: %s" % facility_id)
		return false
	var body_box := body_shape_node.shape as BoxShape3D
	if body_box == null:
		push_warning("[BaseFacility3D] Front interaction requires BoxShape3D body: %s" % facility_id)
		return false

	var local_target := to_local(world_target)
	var toward_target := Vector2(local_target.x, local_target.z)
	if toward_target.length_squared() < 0.0001:
		return false
	var width := float(profile.get("width", 5.0))
	var depth := float(profile.get("depth", 3.8))
	var height := float(profile.get("height", 3.4))
	var overlap := float(profile.get("overlap", 0.3))
	var front_side_multiplier := float(profile.get("front_side_multiplier", 1.0))
	var front_box := BoxShape3D.new()
	var front_offset := Vector3.ZERO
	if absf(toward_target.x) > absf(toward_target.y):
		var side := signf(toward_target.x) * front_side_multiplier
		front_box.size = Vector3(depth, height, width)
		front_offset.x = body_shape_node.position.x + side * (body_box.size.x * 0.5 + depth * 0.5 - overlap)
		front_offset.z = body_shape_node.position.z
	else:
		var side := signf(toward_target.y) * front_side_multiplier
		front_box.size = Vector3(width, height, depth)
		front_offset.x = body_shape_node.position.x
		front_offset.z = body_shape_node.position.z + side * (body_box.size.z * 0.5 + depth * 0.5 - overlap)
	front_offset.y = height * 0.5
	interaction_shape.position = front_offset
	interaction_shape.rotation = Vector3.ZERO
	interaction_shape.shape = front_box
	interaction_shape.set_meta("front_interaction_profile", facility_id)
	interaction_shape.set_meta("front_interaction_side_multiplier", front_side_multiplier)
	return true


func _find_primary_body_shape() -> CollisionShape3D:
	# 正式资产允许按美术语义命名 StaticBody3D/CollisionShape3D；运行契约只要求
	# 「StaticBody3D 下存在启用的 BoxShape3D」，不把玩法绑定到某个旧节点名。
	var legacy := get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if legacy != null and not legacy.disabled and legacy.shape is BoxShape3D:
		return legacy
	for body_value in find_children("*", "StaticBody3D", true, false):
		var body := body_value as StaticBody3D
		if body == null:
			continue
		for shape_value in body.find_children("*", "CollisionShape3D", true, false):
			var shape_node := shape_value as CollisionShape3D
			if shape_node != null and not shape_node.disabled and shape_node.shape is BoxShape3D:
				return shape_node
	return null


func _ready() -> void:
	add_to_group("base_facility")
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_default_base_size()
	_apply_catalog_definition()
	name_label.text = display_name
	name_label.font_size = 38
	name_label.visible = NAME_LABEL_VISIBLE
	prompt_label.text = "[E] 使用 %s" % display_name
	prompt_label.visible = false
	_apply_prompt_label_presentation()
	if base_mesh != null:
		_apply_material(base_mesh, facility_color.darkened(0.52), 0.58, 0.62)
	if roof_mesh != null:
		_apply_material(roof_mesh, facility_color.darkened(0.20), 0.42, 0.70)
	if beacon_mesh != null:
		_apply_material(beacon_mesh, facility_color, 0.18, 0.38, true)
	if beacon_light != null:
		beacon_light.light_color = facility_color
		beacon_light.visible = beacon_light_enabled
		beacon_light.light_energy = 1.15 if beacon_light_enabled else 0.0
		if beacon_light_enabled:
			beacon_light.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
			beacon_light.set_meta("gameplay_light_kind", "omni")
	if not facility_id.is_empty() and BaseManager != null:
		apply_snapshot(BaseManager.get_facility_snapshot(facility_id))


func _apply_default_base_size() -> void:
	if _base_size_applied:
		return
	_base_size_applied = true
	# 根节点和InteractionShape保持原尺寸，避免改变设施摆放与可用距离。
	# 视觉、实体碰撞及其局部高度缩到旧资产的70%；标签只降低锚点，不缩字。
	var interaction_shape := get_node_or_null("InteractionShape") as CollisionShape3D
	for child in get_children():
		if child == interaction_shape or not child is Node3D:
			continue
		var spatial := child as Node3D
		spatial.position *= base_size_multiplier
		if child is Label3D:
			continue
		spatial.scale *= base_size_multiplier
	set_meta("base_size_multiplier", base_size_multiplier)


## 名字牌退役后，黄色交互提示是设施头顶唯一的文字：字号放大、锚点抬高。
## 必须在 _apply_default_base_size() 之后调用 —— 抬升量是最终米数，不参与
## base_size_multiplier 缩放；且此时名字牌与提示牌都已按同一倍数换算过位置，
## 两者不会被二次缩放。幂等：重复调用不会再叠一次抬升。
func _apply_prompt_label_presentation() -> void:
	if prompt_label == null or has_meta("prompt_label_presentation_applied"):
		return
	set_meta("prompt_label_presentation_applied", true)
	prompt_label.font_size = PROMPT_LABEL_FONT_SIZE
	prompt_label.position.y += PROMPT_LABEL_HEIGHT_LIFT_M


func get_size_contract_snapshot() -> Dictionary:
	var interaction := get_node_or_null("InteractionShape") as CollisionShape3D
	var body_shape := _find_primary_body_shape()
	var body := body_shape.get_parent() as StaticBody3D if body_shape != null else null
	var visual := get_node_or_null("Visual") as Node3D
	var visual_scale := visual.scale if visual != null else Vector3.ZERO
	if visual == null:
		for child in get_children():
			if child is GeometryInstance3D:
				visual_scale = (child as GeometryInstance3D).scale
				break
	return {
		"base_size_multiplier": base_size_multiplier,
		"root_scale": scale,
		"interaction_scale": interaction.scale if interaction != null else Vector3.ZERO,
		"body_scale": body.scale if body != null else Vector3.ZERO,
		"body_shape_path": str(body_shape.get_path()) if body_shape != null else "",
		"interaction_shape_locked": has_meta("interaction_shape_locked"),
		"visual_scale": visual_scale,
	}


func _process(delta: float) -> void:
	if beacon_mesh != null:
		beacon_mesh.rotation.y += delta * (1.8 if _player_in_range else 0.55)
	if beacon_light != null and beacon_light_enabled:
		beacon_light.light_energy = 2.1 if _player_in_range else 1.15 + sin(Time.get_ticks_msec() * 0.002) * 0.08


func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "base_facility:%s" % facility_id,
		"position": global_position,
		"priority": 60,
		"prompt": prompt_label.text if prompt_label != null else "[E] 使用 %s" % display_name,
	}


## 文字提示牌退役为纯文案载体（text 仍被候选协议读取）；可见反馈由常驻圆点承担。
func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func get_interaction_dot_anchor() -> Vector3:
	if prompt_label != null and is_instance_valid(prompt_label):
		return prompt_label.global_position
	return global_position + Vector3.UP * 2.0


func get_interaction_dot_accent() -> Color:
	return facility_color.lightened(0.25)


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if not _player_in_range:
		return false
	if _available:
		activated.emit(self)
	return true


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = false
	prompt_label.visible = false


func _apply_material(mesh_instance: MeshInstance3D, color: Color, metallic: float, roughness: float, emission := false) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	mesh_instance.material_override = material


func _apply_catalog_definition() -> void:
	if facility_id.is_empty():
		return
	var definition: Dictionary = FacilityCatalog.get_definition(facility_id)
	if definition.is_empty():
		push_warning("[BaseFacility3D] Unknown facility_id: %s" % facility_id)
		return
	display_name = str(definition.get("display_name", display_name))
	description = str(definition.get("description", description))
	facility_color = definition.get("color", facility_color) as Color
	var action_kind := str(definition.get("action_kind", FacilityCatalog.ACTION_INFO))
	var action_path := str(definition.get("action_path", ""))
	match action_kind:
		FacilityCatalog.ACTION_MENU:
			activation_type = ActivationType.OPEN_MENU
			menu_scene_path = action_path
		FacilityCatalog.ACTION_SCENE:
			activation_type = ActivationType.LOAD_SCENE
			target_scene_path = action_path
		_:
			activation_type = ActivationType.SHOW_INFO


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_available = bool(snapshot.get("available", false))
	display_name = str(snapshot.get("display_name", display_name))
	description = str(snapshot.get("description", description))
	# name_label 已不显示（见 NAME_LABEL_VISIBLE），这里继续维护它的文字与状态色：
	# 快照契约、离线验收和「随时可恢复常驻设施牌」都依赖这份数据。
	name_label.text = "%s\n%s" % [display_name, str(snapshot.get("summary", "状态未知"))]
	if not _available:
		name_label.modulate = Color(1.0, 0.38, 0.32)
	elif bool(snapshot.get("attention", false)):
		name_label.modulate = Color(1.0, 0.76, 0.24)
	else:
		name_label.modulate = Color(0.52, 0.94, 0.78)
	var verb := "使用"
	match str(snapshot.get("action_kind", "")):
		FacilityCatalog.ACTION_MENU: verb = "打开"
		FacilityCatalog.ACTION_SCENE: verb = "进入"
		FacilityCatalog.ACTION_INFO: verb = "查看"
	if _available:
		prompt_label.text = "[E] %s %s" % [verb, display_name]
	else:
		prompt_label.text = str(snapshot.get("availability_reason", "设施不可用"))


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)
