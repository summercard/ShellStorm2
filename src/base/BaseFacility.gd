class_name BaseFacility
extends Area2D

signal activated(facility: BaseFacility)

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
@export var facility_color := Color(0.28, 0.55, 0.78, 1.0)

@onready var _outer_visual: Polygon2D = $Visual
@onready var _inner_visual: Polygon2D = $Visual/Inner
@onready var _name_label: Label = $NameLabel
@onready var _description_label: Label = $DescriptionLabel
@onready var _prompt_label: Label = $PromptLabel

var _player_in_range := false


func _ready() -> void:
	add_to_group("base_facility")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh_presentation()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	activated.emit(self)


func _refresh_presentation() -> void:
	_name_label.text = display_name
	_description_label.text = description
	_prompt_label.text = "[E] 使用 %s" % display_name
	_prompt_label.visible = _player_in_range
	_outer_visual.color = facility_color
	_inner_visual.color = facility_color.lightened(0.22)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_prompt_label.visible = false
