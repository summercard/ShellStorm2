extends Node

const REQUIRED_ROOM_SCENES := [
	"res://scenes/RoomSpawn.tscn",
	"res://scenes/RoomCombat.tscn",
	"res://scenes/RoomElite.tscn",
	"res://scenes/RoomScavenge.tscn",
	"res://scenes/RoomMerchant.tscn",
	"res://scenes/RoomUpgrade.tscn",
	"res://scenes/RoomEvent.tscn",
	"res://scenes/RoomExtraction.tscn",
	"res://scenes/RoomBoss.tscn",
	"res://scenes/RoomStorage.tscn",
	"res://scenes/RoomTrap.tscn",
]


func _ready() -> void:
	var failures: Array[String] = []
	for path in REQUIRED_ROOM_SCENES:
		if not ResourceLoader.exists(path):
			failures.append("%s is missing" % path)
	var spawn: Node = (load("res://scenes/RoomSpawn.tscn") as PackedScene).instantiate()
	add_child(spawn)
	var authored_sources: Array[Node] = []
	_collect_visibility_lights(spawn, authored_sources)
	if authored_sources.size() != 1:
		failures.append("Spawn room should explicitly author exactly one fixture")
	else:
		var light := authored_sources[0] as PointLight2D
		if light == null or not light.shadow_enabled or light.texture == null:
			failures.append("Spawn fixture is not configured as a rendered shadow light")
	spawn.queue_free()
	await get_tree().process_frame

	var dark_room: Node = (load("res://scenes/RoomCombat.tscn") as PackedScene).instantiate()
	add_child(dark_room)
	var default_sources: Array[Node] = []
	_collect_visibility_lights(dark_room, default_sources)
	if not default_sources.is_empty():
		failures.append("Combat room should remain dark until a fixture is authored")
	dark_room.queue_free()
	await get_tree().process_frame

	var managed_room := Node2D.new()
	add_child(managed_room)
	var lighting := RoomLightingSystem.new()
	managed_room.add_child(lighting)
	lighting.configure(RoomData.RoomType.COMBAT, Vector2(960.0, 768.0), 4)
	if managed_room.get_node_or_null("RoomLightSwitch") != null:
		failures.append("A concealed room creates a rendered switch before it is revealed")
	lighting.activate()
	var wall_switch := managed_room.get_node_or_null("RoomLightSwitch")
	if wall_switch == null:
		failures.append("Managed room does not receive a wall light switch")
	elif not lighting.get_visibility_light_sources().is_empty():
		failures.append("Unswitched room fixture contributes visibility while powered off")
	else:
		wall_switch.call("_set_light_state", true, true)
		if lighting.get_visibility_light_sources().is_empty():
			failures.append("Wall switch does not activate the managed room fixture")
		var switch_pos: Vector2 = (wall_switch as Node2D).position
		if not (
			absf(absf(switch_pos.x) - 480.0 + 34.0) < 1.0
			or absf(absf(switch_pos.y) - 384.0 + 34.0) < 1.0
		):
			failures.append("Room light switch was not placed along a room wall")
	managed_room.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("ROOM_LIGHTING_FLOW_OK: dark rooms, wall switches, and rendered shadow fixtures are coherent")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _collect_visibility_lights(root: Node, result: Array[Node]) -> void:
	for child in root.get_children():
		if child.has_method("get_visibility_descriptor"):
			result.append(child)
		_collect_visibility_lights(child, result)
