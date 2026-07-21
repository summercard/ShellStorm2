class_name BaseFacility3D
extends Area3D

signal activated(facility: BaseFacility3D)

enum ActivationType {
	OPEN_MENU,
	LOAD_SCENE,
	SHOW_INFO,
}

@export var display_name := "基地设施"
@export_multiline var description := ""
@export var activation_type: ActivationType = ActivationType.OPEN_MENU
@export_file("*.tscn") var menu_scene_path := ""
@export_file("*.tscn") var target_scene_path := ""
@export_range(0, 99, 1) var target_floor := 0
@export var facility_color := Color(0.28, 0.55, 0.78)

@onready var base_mesh: MeshInstance3D = $Visual/Base
@onready var roof_mesh: MeshInstance3D = $Visual/Roof
@onready var beacon_mesh: MeshInstance3D = $Visual/Beacon
@onready var beacon_light: OmniLight3D = $Visual/BeaconLight
@onready var name_label: Label3D = $NameLabel
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range := false


func _ready() -> void:
	add_to_group("base_facility")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	name_label.text = display_name
	prompt_label.text = "[E] %s" % display_name
	prompt_label.visible = false
	_apply_material(base_mesh, facility_color.darkened(0.52), 0.58, 0.62)
	_apply_material(roof_mesh, facility_color.darkened(0.20), 0.42, 0.70)
	_apply_material(beacon_mesh, facility_color, 0.18, 0.38, true)
	beacon_light.light_color = facility_color
	beacon_light.light_energy = 1.15


func _process(delta: float) -> void:
	$Visual/Beacon.rotation.y += delta * (1.8 if _player_in_range else 0.55)
	beacon_light.light_energy = 2.1 if _player_in_range else 1.15 + sin(Time.get_ticks_msec() * 0.002) * 0.08


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
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
