extends Node

const VISIBILITY_LIGHT_SCRIPT := preload("res://src/fx/VisibilityLight2D.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var vision := VisionSystem.new()
	var room_bounds := Rect2(Vector2(900.0, -384.0), Vector2(960.0, 768.0))
	var wall_rects: Array[Rect2] = [Rect2(Vector2(1140.0, -32.0), Vector2(64.0, 64.0))]
	vision.build_room_occlusion(room_bounds, wall_rects)
	vision.set_view_direction(Vector2.RIGHT)

	if not vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(1100.0, 0.0)):
		failures.append("A nearby unobstructed target should be visible")
	if vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(1250.0, 0.0)):
		failures.append("A wall between player and target should block vision")
	if vision.is_point_visible(Vector2(1000.0, 100.0), Vector2(1370.0, 100.0)):
		failures.append("A target outside the view radius should be hidden")
	if not vision.is_point_visible(Vector2(1000.0, 100.0), Vector2(1250.0, 100.0)):
		failures.append("An offset sight line that misses the wall should remain visible")
	if not vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(950.0, 0.0)):
		failures.append("The near player light should reveal nearby points in every direction")
	if vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(900.0, 0.0)):
		failures.append("A target behind the player's view cone should be hidden")
	vision.set_view_direction(Vector2.LEFT)
	if not vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(900.0, 0.0)):
		failures.append("Turning the player should reveal targets inside the new cone")
	vision.set_view_direction(Vector2.RIGHT)
	vision.set_static_light_sources([{"position": Vector2(1000.0, 180.0), "radius": 96.0}])
	if not vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(1000.0, 180.0)):
		failures.append("A line-of-sight target lit by a room fixture should be observable")
	vision.set_static_light_sources([{"position": Vector2(1250.0, 0.0), "radius": 96.0}])
	if vision.is_point_visible(Vector2(1000.0, 0.0), Vector2(1250.0, 0.0)):
		failures.append("A room fixture must not reveal a target hidden behind a wall")
	_verify_cone_light_texture(failures)
	_verify_runtime_lighting_nodes(failures)

	if failures.is_empty():
		print("VISION_SYSTEM_FLOW_OK: cone direction, radius limiting, and wall occlusion are coherent")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_cone_light_texture(failures: Array[String]) -> void:
	var light: PointLight2D = VISIBILITY_LIGHT_SCRIPT.new() as PointLight2D
	light.configure_flashlight(
		VisionSystem.DEFAULT_VIEW_RADIUS, VisionSystem.DEFAULT_VIEW_ANGLE, VisionSystem.NEAR_VIEW_RADIUS
	)
	light.call("refresh_light")
	var texture: ImageTexture = light.texture as ImageTexture
	var image: Image = texture.get_image()
	var center := image.get_width() / 2
	if image.get_pixel(center + 24, center).a < 0.5:
		failures.append("Cone light texture does not illuminate its forward center")
	if image.get_pixel(center - 100, center).a > 0.01:
		failures.append("Cone light texture illuminates behind the player")
	if image.get_pixel(center, center + 100).a > 0.01:
		failures.append("Cone light texture illuminates outside its angular bounds")
	if image.get_pixel(center - 12, center).a < 0.25:
		failures.append("Near player light does not illuminate behind the character")
	light.free()


func _verify_runtime_lighting_nodes(failures: Array[String]) -> void:
	var layout := RoomLayout.new()
	add_child(layout)
	var room := RoomData.new(RoomData.RoomType.COMBAT, 1)
	room.size = Vector2(960.0, 768.0)
	layout.configure(0, room, [])
	if _count_light_occluders(layout) < 4:
		failures.append("Runtime room walls do not create light occluders")
	layout.queue_free()

	var authored_light: PointLight2D = VISIBILITY_LIGHT_SCRIPT.new() as PointLight2D
	layout.add_child(authored_light)
	authored_light.light_radius = 230.0
	authored_light.refresh_light()
	var lighting := RoomLightingSystem.new()
	layout.add_child(lighting)
	lighting.configure(RoomData.RoomType.MERCHANT, Vector2(960.0, 768.0))
	lighting.activate()
	var wall_switch := layout.get_node_or_null("RoomLightSwitch")
	if wall_switch != null:
		wall_switch.call("_set_light_state", true, true)
	var sources := lighting.get_visibility_light_sources()
	if sources.is_empty():
		failures.append("A switched-on room fixture does not expose a visibility light source")
	else:
		if not authored_light.shadow_enabled:
			failures.append("Room fixtures must cast shadows")


func _count_light_occluders(node: Node) -> int:
	var count := 1 if node is LightOccluder2D else 0
	for child in node.get_children():
		count += _count_light_occluders(child)
	return count
