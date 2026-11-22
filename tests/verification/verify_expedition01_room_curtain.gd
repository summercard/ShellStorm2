extends Node

const EXPEDITION := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SIDES := ["north", "south", "west", "east"]

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	var world := EXPEDITION.instantiate() as TowerDescent3D
	world.test_mode = true
	add_child(world)
	await get_tree().process_frame
	world.set_physics_process(false)
	world.set_process(false)
	world.player.set_physics_process(false)

	var entry := world._room_by_id.get("start") as DungeonRoom3D
	var corridor := world._room_by_id.get("room_01") as DungeonRoom3D
	var boss := world._room_by_id.get("boss") as DungeonRoom3D
	_expect(world._rooms.size() == 13 and entry != null and corridor != null and boss != null, "formal layout: 13 rooms")
	if entry == null or corridor == null or boss == null:
		_finish()
		return
	var original := _check_room(world, entry)
	world.player.global_position = corridor.global_position
	world._on_room_entered(corridor)
	var next := _check_room(world, corridor)
	_expect(world._current_room_id == corridor.room_id and next != original, "room entry replaces the curtain immediately")
	_expect(original == null or not original.is_inside_tree(), "previous curtain removed before building the next")
	for room: DungeonRoom3D in world._rooms:
		world._current_room_id = room.room_id
		world._refresh_flow_view_mask()
		_check_room(world, room)

	world._current_room_id = boss.room_id
	world._refresh_flow_view_mask()
	var boss_walls := world.get_node_or_null("FlowViewWalls") as Node3D
	if boss_walls != null:
		var art_back := boss.get_authored_layout_world_transform() * Vector3(0.0, 0.0, -70.0)
		var bounds := boss_walls.get_meta("view_wall_rect") as Rect2
		_expect(bounds.has_point(Vector2(art_back.x, art_back.z)), "boss curtain encompasses rotated back shell")
		_expect(float(boss_walls.get_meta("view_wall_bottom")) < boss.global_position.y - 36.4, "boss curtain covers shaft depth")
	world._current_room_id = entry.room_id
	world._refresh_flow_view_mask()
	if DisplayServer.get_name() != "headless":
		await _check_rendered_curtain(world, entry)
	_finish()


func _check_room(world: TowerDescent3D, room: DungeonRoom3D) -> Node3D:
	var root := world.get_node_or_null("FlowViewWalls") as Node3D
	var label := room.room_id
	_expect(root != null, label + ": missing curtain")
	if root == null:
		return null
	_expect(root.get_meta("view_wall_room_id", "") == label, label + ": follows active room")
	_expect(root.top_level and root.is_visible_in_tree() and root.get_child_count() == 4, label + ": four visible world-space panels")
	_expect(root.find_children("*", "CollisionObject3D", true, false).is_empty(), label + ": no collision")
	var rect := root.get_meta("view_wall_rect") as Rect2
	_expect(rect.has_point(Vector2(room.global_position.x, room.global_position.z)), label + ": room center inside")
	var top := float(root.get_meta("view_wall_top"))
	_expect(top > room.global_position.y + 20.0, label + ": extends above high camera")
	for side: String in SIDES:
		var panel := root.get_node_or_null("FlowViewWalls" + side.capitalize()) as MeshInstance3D
		if panel == null:
			_expect(false, label + ": " + side + " missing")
			continue
		var material := panel.mesh.surface_get_material(0) as StandardMaterial3D
		_expect(
			panel.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and material != null
			and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and material.disable_fog and material.albedo_color == Color.BLACK,
			label + ": " + side + " opaque black with no shadow"
		)
		for opening: Rect2 in panel.get_meta("view_wall_openings"):
			var point := opening.get_center()
			_expect(not _panel_covers(panel, side, point), label + ": " + side + " aperture clear")
			_expect(_panel_covers(panel, side, Vector2(point.x, top - 0.25)), label + ": " + side + " stays black above opening")
			if opening.position.y > float(root.get_meta("view_wall_bottom")) + 1.0:
				_expect(_panel_covers(panel, side, Vector2(point.x, opening.position.y - 0.5)), label + ": " + side + " stays black below door sill")
	for port: Dictionary in room.connection_ports:
		if not world._room_by_id.has(str(port.get("target_room_id", ""))):
			continue
		var side := str(port.get("side"))
		var door := room.get_door_node_by_port(str(port.get("port_id", "")))
		var raw := port.get("position_m", []) as Array
		var position := room.to_global(Vector3(float(raw[0]), float(port.get("height_m", 0.0)), float(raw[1])))
		if is_instance_valid(door):
			position = door.global_position
		var axis := position.x if side in ["north", "south"] else position.z
		var panel := root.get_node_or_null("FlowViewWalls" + side.capitalize()) as MeshInstance3D
		if panel != null:
			_expect(not _panel_covers(panel, side, Vector2(axis, position.y + 1.25)), label + ": " + side + " actual connected door stays clear")

	var camera := world.player.camera
	camera.global_position = Vector3(rect.end.x + 3.0, room.global_position.y + 12.5, rect.end.y + 3.0)
	world._clamp_flow_camera_into_room(room.global_position + Vector3.UP)
	var local := camera.global_position
	_expect(rect.has_point(Vector2(local.x, local.z)), label + ": camera stays inside curtain")
	_expect(is_equal_approx(local.y, room.global_position.y + 12.5), label + ": clamp preserves camera height")
	return root


func _panel_covers(panel: MeshInstance3D, side: String, sample: Vector2) -> bool:
	var vertices := panel.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var along_x := side in ["north", "south"]
	var fixed := vertices[0].z if along_x else vertices[0].x
	var origin := Vector3(sample.x, sample.y, fixed - 1.0) if along_x else Vector3(fixed - 1.0, sample.y, sample.x)
	var direction := Vector3.BACK if along_x else Vector3.RIGHT
	for i in range(0, vertices.size(), 3):
		if Geometry3D.ray_intersects_triangle(origin, direction, vertices[i], vertices[i + 1], vertices[i + 2]) != null:
			return true
	return false


func _check_rendered_curtain(world: TowerDescent3D, room: DungeonRoom3D) -> void:
	var root := world.get_node_or_null("FlowViewWalls") as Node3D
	if root == null:
		return
	var rect := root.get_meta("view_wall_rect") as Rect2
	# 用实际场景渲染。探针块在墙的另一侧，射线跨过实际墙顶且避开门洞。
	var target := Vector3(room.global_position.x - 3.0, room.global_position.y + 16.0, rect.position.y - 6.0)
	var camera := world.player.camera
	camera.make_current()
	camera.global_position = Vector3(target.x, room.global_position.y + 22.0, rect.position.y + 5.0)
	camera.look_at(target, Vector3.UP)
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 2.0
	marker.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	material.albedo_color = Color(1.0, 0.0, 1.0)
	marker.material_override = material
	world.add_child(marker)
	marker.global_position = target
	var uv := camera.unproject_position(target) / get_viewport().get_visible_rect().size
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var covered := get_viewport().get_texture().get_image()
	var pixel := Vector2i(uv * Vector2(covered.get_size()))
	root.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var uncovered := get_viewport().get_texture().get_image()
	root.show()
	marker.queue_free()
	_expect(Rect2i(Vector2i.ZERO, covered.get_size()).has_point(pixel), "probe sample in viewport")
	if Rect2i(Vector2i.ZERO, covered.get_size()).has_point(pixel):
		var black := covered.get_pixelv(pixel)
		var magenta := uncovered.get_pixelv(pixel)
		print("ROOM_CURTAIN_RENDER covered=", black, " uncovered=", magenta)
		_expect(maxf(maxf(black.r, black.g), black.b) < 0.08, "curtain makes the adjacent sample black")
		_expect(magenta.r > 0.45 and magenta.b > 0.45 and magenta.g < 0.20, "outside marker is visible when the curtain is removed")
	var output := OS.get_environment("SHELLSTORM_CURTAIN_QA_DIR")
	if not output.is_empty():
		covered.save_png(output.path_join("curtain_enabled.png"))
		uncovered.save_png(output.path_join("curtain_disabled_control.png"))


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("EXPEDITION01_ROOM_CURTAIN_OK checks=%d renderer=%s" % [_checks, DisplayServer.get_name()])
	else:
		for failure in _failures:
			push_error("EXPEDITION01_ROOM_CURTAIN_FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
