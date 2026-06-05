class_name ThemedNPC
extends Area2D

@export var npc_id := "npc"
@export var display_name := "区域居民"
@export var role := "情报提供者"
@export_multiline var interaction_text := "这片区域仍有许多秘密。"
@export var accent_color := Color(0.35, 0.75, 0.9, 1.0)

@onready var body_visual: Polygon2D = $Body
@onready var name_label: Label = $NameLabel
@onready var role_label: Label = $RoleLabel
@onready var prompt_label: Label = $PromptLabel
@onready var dialogue_label: Label = $DialogueLabel

var _player_in_range := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh_presentation()
	prompt_label.visible = false
	dialogue_label.visible = false
	add_to_group("themed_npc")


func _refresh_presentation() -> void:
	body_visual.color = accent_color
	name_label.text = display_name
	role_label.text = role


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed("interact"):
		return
	dialogue_label.text = interaction_text
	dialogue_label.visible = not dialogue_label.visible
	get_viewport().set_input_as_handled()


func configure(config: Dictionary) -> void:
	npc_id = str(config.get("id", npc_id))
	display_name = str(config.get("name", display_name))
	role = str(config.get("role", role))
	interaction_text = str(config.get("text", interaction_text))
	accent_color = config.get("color", accent_color)
	if is_node_ready():
		_refresh_presentation()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		prompt_label.visible = false
		dialogue_label.visible = false
