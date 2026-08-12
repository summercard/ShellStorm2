class_name BaseFacility3D
extends Area3D

const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")

signal activated(facility: BaseFacility3D)

enum ActivationType {
	OPEN_MENU,
	LOAD_SCENE,
	SHOW_INFO,
}

@export var facility_id := ""
@export var display_name := "基地设施"
@export_multiline var description := ""
@export var activation_type: ActivationType = ActivationType.OPEN_MENU
@export_file("*.tscn") var menu_scene_path := ""
@export_file("*.tscn") var target_scene_path := ""
@export_range(0, 99, 1) var target_floor := 0
@export var facility_color := Color(0.28, 0.55, 0.78)

@onready var base_mesh: MeshInstance3D = get_node_or_null("Visual/Base") as MeshInstance3D
@onready var roof_mesh: MeshInstance3D = get_node_or_null("Visual/Roof") as MeshInstance3D
@onready var beacon_mesh: MeshInstance3D = get_node_or_null("Visual/Beacon") as MeshInstance3D
@onready var beacon_light: OmniLight3D = get_node_or_null("Visual/BeaconLight") as OmniLight3D
@onready var name_label: Label3D = $NameLabel
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range := false
var _available := true
var _snapshot: Dictionary = {}


func _ready() -> void:
	add_to_group("base_facility")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_catalog_definition()
	name_label.text = display_name
	name_label.font_size = 38
	prompt_label.text = "[E] 使用 %s" % display_name
	prompt_label.visible = false
	if base_mesh != null:
		_apply_material(base_mesh, facility_color.darkened(0.52), 0.58, 0.62)
	if roof_mesh != null:
		_apply_material(roof_mesh, facility_color.darkened(0.20), 0.42, 0.70)
	if beacon_mesh != null:
		_apply_material(beacon_mesh, facility_color, 0.18, 0.38, true)
	if beacon_light != null:
		beacon_light.light_color = facility_color
		beacon_light.light_energy = 1.15
		beacon_light.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		beacon_light.set_meta("gameplay_light_kind", "omni")
	if not facility_id.is_empty() and BaseManager != null:
		apply_snapshot(BaseManager.get_facility_snapshot(facility_id))


func _process(delta: float) -> void:
	if beacon_mesh != null:
		beacon_mesh.rotation.y += delta * (1.8 if _player_in_range else 0.55)
	if beacon_light != null:
		beacon_light.light_energy = 2.1 if _player_in_range else 1.15 + sin(Time.get_ticks_msec() * 0.002) * 0.08


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	if not _available:
		return
	activated.emit(self)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = true
	prompt_label.visible = true


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
