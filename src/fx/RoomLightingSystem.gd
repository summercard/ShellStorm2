class_name RoomLightingSystem
extends Node
## Owns a room fixture and its wall switch, and exposes active rendered lights to vision logic.

signal lighting_changed

const VISIBILITY_LIGHT_SCRIPT := preload("res://src/fx/VisibilityLight2D.gd")
const ROOM_LIGHT_SWITCH_SCRIPT := preload("res://src/game/RoomLightSwitch.gd")

var room_type: RoomData.RoomType = RoomData.RoomType.COMBAT
var room_size := Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
var room_id := -1
var _activated := false


func configure(p_room_type: RoomData.RoomType, p_room_size: Vector2, p_room_id: int = -1) -> void:
	room_type = p_room_type
	room_size = p_room_size
	room_id = p_room_id
	if _activated:
		_ensure_fixture_and_switch()


func activate() -> void:
	if _activated:
		return
	_activated = true
	_ensure_fixture_and_switch()


func _ensure_fixture_and_switch() -> void:
	var room_root := get_parent() as Node2D
	if room_root == null:
		return
	var fixture := _find_fixture(room_root)
	var starts_on := room_type == RoomData.RoomType.PLAYER_SPAWN
	if fixture == null:
		fixture = VISIBILITY_LIGHT_SCRIPT.new() as PointLight2D
		fixture.name = "RoomCeilingLight"
		fixture.energy = 1.35
		fixture.color = Color(0.92, 0.94, 0.84, 1.0)
		fixture.set("light_radius", minf(room_size.x, room_size.y) * 0.74)
		fixture.set("radial_falloff_power", 0.8)
		room_root.add_child(fixture)
	var wall_switch: Node = room_root.get_node_or_null("RoomLightSwitch")
	if wall_switch == null:
		wall_switch = ROOM_LIGHT_SWITCH_SCRIPT.new()
		wall_switch.name = "RoomLightSwitch"
		room_root.add_child(wall_switch)
	var position_seed := hash("%d:%d:%d" % [room_id, int(room_type), int(room_size.x + room_size.y)])
	wall_switch.call("configure", room_size, fixture, starts_on, position_seed)
	var toggled := Callable(self, "_on_light_toggled")
	if not wall_switch.is_connected("light_toggled", toggled):
		wall_switch.connect("light_toggled", toggled)


func _find_fixture(root: Node) -> PointLight2D:
	for child in root.get_children():
		if child == self or child.name == "PlayerVisionLight":
			continue
		if child is PointLight2D and child.has_method("get_visibility_descriptor"):
			return child as PointLight2D
	return null


func _on_light_toggled(_is_on: bool) -> void:
	lighting_changed.emit()


func get_visibility_light_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var room_root := get_parent()
	if room_root != null:
		_append_sources(room_root, sources)
	return sources


func _append_sources(root: Node, sources: Array[Dictionary]) -> void:
	for child in root.get_children():
		if child == self:
			continue
		if child.has_method("get_visibility_descriptor"):
			var descriptor: Dictionary = child.call("get_visibility_descriptor")
			if not descriptor.is_empty():
				sources.append(descriptor)
		_append_sources(child, sources)
