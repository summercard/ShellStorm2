extends SceneTree

const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"
const EDIT := "res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn"
const ASSET := "res://assets/art/environments/open_world/runtime/landscape_skyline20/env_landscape_skyline20_root_top3d.tscn"
const OUT := "res://outputs/skyline20_placement/"
var report: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for value: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func data(n: Node3D) -> Dictionary:
	var b := bounds(n)
	return {"node": str(n.get_path()), "position": [n.global_position.x, n.global_position.y, n.global_position.z], "min": [b.position.x,b.position.y,b.position.z], "max": [b.end.x,b.end.y,b.end.z], "size": [b.size.x,b.size.y,b.size.z]}

func require(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var route: Node3D = load(ROUTE).instantiate()
	root.add_child(route)
	var edit: Node3D = load(EDIT).instantiate()
	root.add_child(edit)
	var standalone: Node3D = load(ASSET).instantiate()
	root.add_child(standalone)
	await process_frame
	report["tower3"] = data(route.get_node("Tower3"))
	var tile: Node3D = route.get_node("Tower3").find_child("lower_tile_00_00", true, false)
	report["tower3_roof_tile"] = data(tile)
	report["skyline20_local"] = data(standalone)
	report["skyline20_roof_support"] = data(standalone.get_node("roof_service_hut"))
	var city: Array[Dictionary] = []
	for child: Node in edit.get_children():
		if child is Node3D and ("chunk" in str(child.name).to_lower()):
			city.append(data(child))
	report["editor_chunks"] = city
	if not baseline:
		var placed: Node3D = route.get_node("Skyline20Placement/Skyline20")
		var edited: Node3D = edit.get_node("Skyline20Placement/Skyline20")
		report["formal"] = data(placed)
		report["editor"] = data(edited)
		var roof_y := bounds(placed.get_node("roof_service_hut")).position.y
		var tower_roof := bounds(tile).end.y
		report["roof_y"] = roof_y
		report["tower_roof_y"] = tower_roof
		report["roof_delta_m"] = tower_roof-roof_y
		require(absf((tower_roof-roof_y)-10.0)<0.001, "roof delta exactly 10m")
		require(placed.global_transform.is_equal_approx(edited.global_transform), "formal/editor transforms equal")
		require(placed.global_basis.is_equal_approx(Basis.IDENTITY), "unit scale, no rotation")
		require(placed.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual only zero collisions")
		require(placed.find_children("*", "CollisionShape3D", true, false).is_empty(), "zero collision shapes")
		require(bounds(placed).position.x > bounds(route.get_node("Tower3")).end.x, "east of tower3, no overlap")
		for c: Dictionary in city:
			var lo: Array = c["min"]
			var hi: Array = c["max"]
			var cb := AABB(Vector3(lo[0],lo[1],lo[2]),Vector3(hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]))
			require(not bounds(placed).intersects(cb), "no overlap with "+str(c["node"]))
		var tower: Node3D = load("res://scenes/TowerDescent3D.tscn").instantiate()
		tower.set("test_mode",true)
		root.add_child(tower)
		for i: int in 30:
			await physics_frame
		var live: Node3D = tower.get_node("Blocks/Rooftop/CrossTowerRoute/Skyline20Placement/Skyline20")
		report["live"] = data(live)
		require(live.global_transform.is_equal_approx(placed.global_transform), "live game transform matches")
		var count := 0
		for n: Node in tower.find_children("*", "Node3D", true, false):
			if str(n.get_meta("asset_id", "")) == "ENV-OPENWORLD-LANDSCAPE-SKYLINE20":
				count += 1
		report["live_instance_count"] = count
		require(count==1,"live exactly one building")
		# Hide independent comparison scenes; capture only the real game tree.
		route.visible = false
		edit.visible = false
		standalone.visible = false
		if DisplayServer.get_name() != "headless":
			root.size = Vector2i(1440, 1000)
			for ui: Node in tower.find_children("*", "CanvasLayer", true, false):
				(ui as CanvasLayer).visible = false
			var player: Node3D = tower.get("player") as Node3D
			if player != null:
				player.process_mode = Node.PROCESS_MODE_DISABLED
			var cam := Camera3D.new()
			tower.add_child(cam)
			cam.global_position = Vector3(115, 135, 10)
			cam.look_at(Vector3(25, -7, -137))
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 220
			cam.current = true
			for i: int in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+"placement_native.png")
			var world_env := tower.get_node("WorldEnvironment") as WorldEnvironment
			var env := world_env.environment.duplicate() as Environment
			env.fog_enabled = false
			env.volumetric_fog_enabled = false
			env.ambient_light_energy = 0.6
			world_env.environment = env
			for i: int in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+"placement_overview.png")
			cam.global_position = Vector3(90, 83, -84)
			cam.look_at(Vector3(35, -8, -187))
			cam.size = 155
			for i: int in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+"placement_roofs.png")
			report["capture"] = {"renderer": DisplayServer.get_name(), "native": "placement_native.png", "diagnostic": ["placement_overview.png", "placement_roofs.png"], "diagnostic_only": "fog disabled, ambient 0.6; no scene settings saved"}
		tower.free()
	report["failures"] = failures
	var f := FileAccess.open(OUT + ("baseline_runtime.json" if baseline else "placement_runtime.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	f.close()
	print("SKYLINE20_PLACEMENT ",JSON.stringify(report))
	route.free()
	edit.free()
	standalone.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
