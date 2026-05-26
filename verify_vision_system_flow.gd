extends Node


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
	_verify_cone_light_texture(failures)

	if failures.is_empty():
		print("VISION_SYSTEM_FLOW_OK: cone direction, radius limiting, and wall occlusion are coherent")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_cone_light_texture(failures: Array[String]) -> void:
	var light_sync := LightSync.new()
	var texture: ImageTexture = light_sync.call("_make_vision_texture") as ImageTexture
	var image: Image = texture.get_image()
	var center := image.get_width() / 2
	if image.get_pixel(center + 100, center).a < 0.9:
		failures.append("Cone light texture does not illuminate its forward center")
	if image.get_pixel(center - 100, center).a > 0.01:
		failures.append("Cone light texture illuminates behind the player")
	if image.get_pixel(center, center + 100).a > 0.01:
		failures.append("Cone light texture illuminates outside its angular bounds")
	if image.get_pixel(center - 32, center).a < 0.9:
		failures.append("Near player light does not illuminate behind the character")
	light_sync.free()
