class_name DungeonEntrance3D
extends Area3D

signal activated(entrance: DungeonEntrance3D)

@export var entrance_id := "dungeon_01"
@export var display_name := "副本入口"
@export_multiline var description := ""
@export_file("*.tscn") var target_scene_path := ""
@export_range(1, 99, 1) var target_floor := 1
@export var entrance_color := Color(0.72, 0.34, 0.20)

@onready var frame_mesh: MeshInstance3D = $Visual/Frame
@onready var door_mesh: MeshInstance3D = $Visual/Door
@onready var beacon_mesh: MeshInstance3D = $Visual/Beacon
@onready var beacon_light: OmniLight3D = $Visual/BeaconLight
@onready var name_label: Label3D = $NameLabel
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range := false


func _ready() -> void:
	add_to_group("dungeon_entrance")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	name_label.text = display_name
	prompt_label.text = "[E] 进入 %s" % display_name
	prompt_label.visible = false
	_apply_material(frame_mesh, entrance_color.darkened(0.38), 0.64, 0.52)
	_apply_material(door_mesh, entrance_color.darkened(0.70), 0.42, 0.62)
	_apply_material(beacon_mesh, entrance_color, 0.18, 0.34, true)
	beacon_light.light_color = entrance_color


func _process(delta: float) -> void:
	$Visual/Beacon.rotation.y -= delta * (1.9 if _player_in_range else 0.45)
	beacon_light.light_energy = 3.0 if _player_in_range else 1.8 + sin(Time.get_ticks_msec() * 0.0023) * 0.14


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
		material.emission_energy_multiplier = 2.0
	mesh_instance.material_override = material
