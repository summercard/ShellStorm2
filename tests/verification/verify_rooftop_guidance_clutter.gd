extends Node

var failures: Array[String] = []
var tower: Node3D
var clutter: Node3D

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("ROOFTOP_GUIDANCE: " + message)

func _ready() -> void:
	tower = load("res://scenes/TowerDescent3D.tscn").instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", 100990)
	add_child(tower)
	for i in 40:
		await get_tree().process_frame
		await get_tree().physics_frame
	var stages: Dictionary = tower.get("_floor_stages")
	clutter = (stages.get(0) as Node).get_node_or_null("RooftopGuidanceClutter")
	check(clutter != null, "formal 100F clutter missing")
	if clutter == null:
		get_tree().quit(1)
		return
	var ids := {}
	var count := 0
	var tilted := 0
	var collision_count := 0
	var foliage_count := 0
	var grass_material: ShaderMaterial
	var grass_clock := 0.0
	for zone in clutter.get_children():
		for item in zone.get_children():
			count += 1
			var id := str(item.get_meta("scene_content_id", ""))
			check(not id.is_empty() and not ids.has(id), "missing/duplicate content id " + id)
			ids[id] = true
			check(item.is_in_group("scene_interactive_content"), "content group missing " + id)
			check(item.get_meta("interaction_status", "") == "planned_locked", "interaction falsely enabled " + id)
			check(item.scale.is_equal_approx(Vector3.ONE), "non-unit scale " + id)
			if absf(item.rotation.x) > 0.05 or absf(item.rotation.z) > 0.05:
				tilted += 1
			var shapes := item.find_children("*", "CollisionShape3D", true, false)
			if item.get_meta("nonblocking_foliage", false):
				foliage_count += 1
				check(shapes.is_empty(), "grass unexpectedly blocks player " + id)
				check(item is PlantSway3D, "grass missing shared flowerbox wind " + id)
				var grass_mesh := item.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
				grass_material = grass_mesh.get_active_material(0) as ShaderMaterial
				check(grass_material != null, "grass wind material missing " + id)
			else:
				check(not shapes.is_empty(), "missing individual collision " + id)
			for shape in shapes:
				check(not shape.disabled and shape.get_parent().collision_layer == 1, "inactive collision " + id)
			collision_count += shapes.size()
			var world_bounds := mesh_vertex_bounds(item.get_node("ImportedModel/Wall") if id == "roof_clutter_193" else item)
			check(world_bounds.position.y >= -0.03, "sunk visual " + id)
			check(world_bounds.position.y <= 0.04, "floating visual " + id)
			check(world_bounds.position.x >= -50.05 and world_bounds.end.x <= 50.05 and world_bounds.position.z >= -35.05 and world_bounds.end.z <= 45.05, "outside rooftop " + id + " " + str(world_bounds))
	check(count == 194, "authored count mismatch " + str(count))
	var ivy_wall := clutter.get_node_or_null("IvyWall/roof_clutter_193")
	check(ivy_wall != null, "ivy low wall missing")
	if ivy_wall != null:
		check(ivy_wall.get_node("ImportedModel/Foliage") is PlantSway3D, "ivy wall foliage wind missing")
		var wall_mesh := ivy_wall.get_node("ImportedModel/Wall") as MeshInstance3D
		check(wall_mesh.get_active_material(0) is BaseMaterial3D, "solid wall must not sway")
		var leaves := ivy_wall.get_node("ImportedModel/Foliage/Ivy") as MeshInstance3D
		check(leaves.get_active_material(0) is ShaderMaterial, "ivy leaves missing wind shader")
		var hanging_bounds := mesh_vertex_bounds(leaves)
		check(hanging_bounds.position.y >= -4.8 and hanging_bounds.position.y <= -3.5, "ivy hanging length outside designed envelope")
		check(hanging_bounds.end.y >= 4.7 and hanging_bounds.end.y <= 5.5, "ivy crest coverage mismatch")
		check(hanging_bounds.position.x < -30.5, "hanging ivy must clear inner face of stairwell enclosure")
		check(wall_mesh.mesh.get_aabb().size.z <= 0.36, "wall thickness must match adjacent 0.30m enclosure")
	var generator := clutter.get_node_or_null("EastDoorGenerator/roof_clutter_194") as Node3D
	check(generator != null, "east door generator missing")
	if generator != null:
		check(generator.global_position.distance_to(Vector3(18, 0.015, 4.5)) < 0.01, "generator placement drift")
		var body := generator.get_node("ImportedModel/GeneratorBody") as MeshInstance3D
		var body_bounds := mesh_vertex_bounds(body)
		check(absf(body_bounds.size.x-1.5) < 0.02 and absf(body_bounds.size.z-2.0) < 0.02, "generator 1.5x2 footprint mismatch")
		check(generator.find_children("*", "CollisionShape3D", true, false).size() == 1, "ground cable must not block player")
		check(generator.get_meta("cable_count", 0) == 4, "generator cable revision missing")
		var wires := mesh_vertex_bounds(generator.get_node("ImportedModel/GroundCable"))
		check(wires.position.x >= 14.94 and wires.position.x < 15.10, "cables must stop inside east wall, not emerge indoors")
		for entry_name in ["WallEntry1", "WallEntry2", "WallEntry3"]:
			var entry := generator.get_node(entry_name) as Node3D
			check(entry.global_position.x > 14.85 and entry.global_position.x < 15.15, "wire end outside wall slab")
			var ray := PhysicsRayQueryParameters3D.create(entry.global_position + Vector3(1, 0, 0), entry.global_position - Vector3(0.4, 0, 0), 1)
			var hit := get_viewport().world_3d.direct_space_state.intersect_ray(ray)
			check(not hit.is_empty(), "wire end misses solid wall " + entry_name)
			if not hit.is_empty():
				check(absf(hit.position.x - 15.15) < 0.06, "wire enters unexpected obstacle " + entry_name)
		var door := tower.get("_base_rooftop_transit_door") as Node3D
		check(door != null, "central east door missing")
		if door != null:
			check(generator.global_position.z > door.global_position.z+2.5, "generator must be south of central east door")
			for dx in [1.5, 2.0, 3.0, 4.0]:
				check(capsule_hits(door.global_position + Vector3(dx, 0, 0)).is_empty(), "generator obstructs east door approach")
		var overlap := PhysicsShapeQueryParameters3D.new()
		var footprint := BoxShape3D.new()
		footprint.size = Vector3(1.46, 1.30, 1.96)
		overlap.shape = footprint
		overlap.transform.origin = generator.global_position + Vector3(0, 0.75, 0)
		overlap.collision_mask = 1
		overlap.exclude = [(generator.get_node("Body") as StaticBody3D).get_rid()]
		check(get_viewport().world_3d.direct_space_state.intersect_shape(overlap).is_empty(), "generator overlaps existing collision")
	check(foliage_count == 48, "grass patch count mismatch")
	if grass_material != null:
		grass_clock = float(grass_material.get_shader_parameter("wind_time"))
		for i in 8:
			await get_tree().process_frame
		check(float(grass_material.get_shader_parameter("wind_time")) > grass_clock, "grass wind clock frozen")
		grass_clock = float(grass_material.get_shader_parameter("wind_time"))
		get_tree().paused = true
		for i in 4:
			await get_tree().process_frame
		check(is_equal_approx(float(grass_material.get_shader_parameter("wind_time")), grass_clock), "grass wind ignores pause")
		get_tree().paused = false
	check(tilted >= 20, "insufficient toppled/tilted content")
	for key in stages:
		if int(key) != 0:
			check((stages[key] as Node).get_node_or_null("RooftopGuidanceClutter") == null, "clutter leaked to floor " + str(key))
	var expedition_stage := TowerFloorStage3D.new()
	expedition_stage.configure(0, "rooftop", [], [], true, Rect2())
	check(not expedition_stage._uses_rooftop_profile(), "expedition inherited rooftop profile")
	expedition_stage.free()
	var exit_point: Vector3 = tower.call("narrative_anchor", "rooftop_stair_exit")
	check(exit_point.distance_to(Vector3(-28, 0, 2.5)) < 0.05, "exit anchor moved")
	var route: Array[Vector3] = [exit_point, Vector3(-22,0,2.5), Vector3(-22,0,-16.5), Vector3(5.4,0,-16.5), Vector3(12,0,-23.5), Vector3(20,0,-28), Vector3(20,0,-32.5)]
	var trigger: Vector3 = tower.call("narrative_anchor", "rooftop_bridge_approach")
	var trigger_crossed := false
	for index in range(route.size()-1):
		var steps := ceili(route[index].distance_to(route[index+1]) / 0.35)
		for step in range(steps+1):
			var point := route[index].lerp(route[index+1], float(step)/float(steps))
			var hits := capsule_hits(point)
			check(hits.is_empty(), "route obstructed " + str(point) + " " + hit_names(hits))
			if Vector2(point.x-trigger.x,point.z-trigger.z).length() < 13.5:
				trigger_crossed = true
	check(trigger_crossed, "route misses existing narrative trigger")
	check(not capsule_hits(Vector3(-22,0,12.5)).is_empty(), "west-to-south shortcut not blocked")
	check(not capsule_hits(Vector3(24,0,11.5)).is_empty(), "east-to-south shortcut not blocked")
	check(not capsule_hits(Vector3(30,0,-14.5)).is_empty(), "east barrier seam open")
	# User-marked gaps: sample the middle and both ends of each added crate.
	for center in [Vector3(-30.4,0,-10.5), Vector3(31,0,-11.5)]:
		for offset in [-1.5, 0.0, 1.5]:
			check(not capsule_hits(center + Vector3(0,0,offset)).is_empty(), "marked gap open " + str(center) + " offset=" + str(offset))
	check(capsule_hits(Vector3(18,0,-2.5)).is_empty(), "central east door obstructed")
	for z in [5.7, 7.7, 9.7]:
		check(not capsule_hits(Vector3(-29.4,0,z)).is_empty(), "ivy wall collision missing " + str(z))
	print("ROOFTOP_GUIDANCE_COUNTS items=%d tilted=%d shapes=%d route_trigger=%s" % [count,tilted,collision_count,str(trigger_crossed)])
	if DisplayServer.get_name() != "headless":
		await screenshots()
	tower.queue_free()
	for i in 5:
		await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_GUIDANCE_OK")
	get_tree().quit(0 if failures.is_empty() else 1)

func capsule_hits(point: Vector3) -> Array[Dictionary]:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = point + Vector3(0, 0.95, 0)
	query.collision_mask = 1
	return get_viewport().world_3d.direct_space_state.intersect_shape(query, 8)

func mesh_vertex_bounds(item: Node3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var meshes := item.find_children("*", "MeshInstance3D", true, false)
	if item is MeshInstance3D:
		meshes.append(item)
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = mesh.global_transform * vertex
				lo = lo.min(point)
				hi = hi.max(point)
	return AABB(lo, hi-lo)

func hit_names(hits: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for hit in hits:
		names.append(str(hit.collider.get_path()))
	return ",".join(names)

func screenshots() -> void:
	var out := OS.get_environment("ROOFTOP_GUIDANCE_QA_DIR")
	if out.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(out)
	var hud := tower.get_node_or_null("HUD")
	if hud is CanvasLayer:
		hud.visible = false
	var environment := tower.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var atmosphere := tower.find_child("TowerAtmosphere3D", true, false)
	if atmosphere != null:
		atmosphere.set_process(false)
	if environment != null:
		environment.environment = environment.environment.duplicate()
		environment.environment.fog_enabled = false
		environment.environment.volumetric_fog_enabled = false
		environment.environment.ambient_light_energy = 0.25
		environment.environment.tonemap_exposure = 0.85
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 103
	camera.position = Vector3(0, 130, 5)
	camera.look_at(Vector3(0,0,5),Vector3.FORWARD)
	camera.make_current()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/rooftop_guidance_top.png")
	camera.size = 53
	camera.position = Vector3(-47,34,25)
	camera.look_at(Vector3(-18,0,-9))
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/rooftop_guidance_exit.png")
	var ivy_wall := clutter.get_node_or_null("IvyWall/roof_clutter_193") as Node3D
	if ivy_wall != null:
		camera.size = 15.0
		camera.position = ivy_wall.global_position + Vector3(-11, 9, 12)
		camera.look_at(ivy_wall.global_position + Vector3(0, 0.5, -1))
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/rooftop_ivy_wall_close.png")
	var generator := clutter.get_node_or_null("EastDoorGenerator/roof_clutter_194") as Node3D
	if generator != null:
		camera.size = 11.0
		camera.position = generator.global_position + Vector3(8, 8, -10)
		camera.look_at(generator.global_position + Vector3(-0.25, 0.5, 1.4))
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/rooftop_generator_close.png")
	var grass := clutter.get_node_or_null("GroundGrass/roof_clutter_175") as Node3D
	if grass != null:
		camera.size = 5.0
		camera.position = grass.global_position + Vector3(3, 3, 4)
		camera.look_at(grass.global_position + Vector3(0, 0.25, 0))
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/rooftop_grass_a.png")
		await get_tree().create_timer(0.65).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/rooftop_grass_b.png")
	print("ROOFTOP_GUIDANCE_RENDER_OK " + out)
