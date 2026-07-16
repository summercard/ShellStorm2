class_name DungeonEntrance
extends Area2D

signal activated(entrance: DungeonEntrance)

@export var entrance_id := "dungeon_01"
@export var display_name := "副本入口"
@export_multiline var description := ""
@export_file("*.tscn") var target_scene_path := ""
@export_range(1, 99, 1) var target_floor := 1
@export var entrance_color := Color(0.72, 0.34, 0.2, 1.0)

@onready var _building_visual: Polygon2D = $Building
@onready var _roof_visual: Polygon2D = $Building/Roof
@onready var _door_visual: Polygon2D = $Building/Door
@onready var _name_label: Label = $NameLabel
@onready var _description_label: Label = $DescriptionLabel
@onready var _prompt_label: Label = $PromptLabel
@onready var _facade: Node2D = $Facade

var _player_in_range := false


func _ready() -> void:
	add_to_group("dungeon_entrance")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh_presentation()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	activated.emit(self)


func _refresh_presentation() -> void:
	_building_visual.color = entrance_color.darkened(0.25)
	_roof_visual.color = entrance_color
	_door_visual.color = entrance_color.lightened(0.28)
	_name_label.text = display_name
	_description_label.text = description
	_prompt_label.text = "[E] 进入 %s" % display_name
	_prompt_label.visible = _player_in_range
	_description_label.visible = _player_in_range
	if _facade != null and _facade.has_method("configure"):
		_facade.call("configure", entrance_color)
	if _facade != null and _facade.has_method("set_active"):
		_facade.call("set_active", _player_in_range)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_prompt_label.visible = true
	_description_label.visible = true
	if _facade != null and _facade.has_method("set_active"):
		_facade.call("set_active", true)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_prompt_label.visible = false
	_description_label.visible = false
	if _facade != null and _facade.has_method("set_active"):
		_facade.call("set_active", false)
