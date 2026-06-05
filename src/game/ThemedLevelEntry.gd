class_name ThemedLevelEntry
extends Node2D

const DEFAULT_RUNTIME_SCENE: PackedScene = preload("res://scenes/Main.tscn")

@export var theme_profile: Resource
@export var runtime_scene: PackedScene = DEFAULT_RUNTIME_SCENE

var runtime: Node2D = null


func _ready() -> void:
	if runtime_scene == null:
		push_error("[ThemedLevelEntry] Runtime scene is missing")
		return
	runtime = runtime_scene.instantiate() as Node2D
	if runtime == null:
		push_error("[ThemedLevelEntry] Runtime scene root must be Node2D")
		return
	var room_mode := runtime.get_node_or_null("RoomGameMode")
	if room_mode == null:
		push_error("[ThemedLevelEntry] Runtime scene has no RoomGameMode")
		runtime.free()
		runtime = null
		return
	room_mode.set("theme_profile", theme_profile)
	if theme_profile != null:
		room_mode.set("initial_floor", int(theme_profile.get("difficulty_rank")))
	add_child(runtime)


func get_room_game_mode() -> Node:
	if runtime == null:
		return null
	return runtime.get_node_or_null("RoomGameMode")
