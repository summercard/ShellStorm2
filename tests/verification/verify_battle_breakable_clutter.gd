extends Node3D
## Real prefabs, real Projectile3D hits, real CharacterBody3D movement and room streaming.

const SLUGS := ["breakable_jar", "breakable_book_stack", "breakable_vase", "breakable_chair", "breakable_crate"]
const PREFAB_ROOT := "res://assets/art/environments/tower_zones/battle/runtime/common_components/"
var failures: Array[String] = []
var report := {"assets": [], "projectile_direction_verified": false, "player_contact_verified": false}
var gallery: Node3D
var projectile_hit_count := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("BREAKABLE_CLUTTER: " + message)


func _ready() -> void:
	await _verify_isolated_assets()
	await _verify_formal_room_and_projectiles()
	if DisplayServer.get_name() != "headless":
		await _capture_gallery()
	var out := OS.get_environment("BREAKABLE_CLUTTER_QA_DIR")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out + "/verification.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"failures": failures, "report": report}, "\t"))
		file.close()
	report["failures"] = failures
	if failures.is_empty():
		print("BATTLE_BREAKABLE_CLUTTER_OK")
	get_tree().quit(0 if failures.is_empty() else 1)


func _prefab(slug: String) -> BreakableClutter3D:
	return (load("%s%s/%s_root_top3d.tscn" % [PREFAB_ROOT, slug, slug]) as PackedScene).instantiate() as BreakableClutter3D


func _mesh_triangles(root: Node) -> int:
	var count := 0
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var instance := value as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			count += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count


func _verify_isolated_assets() -> void:
	for index in range(SLUGS.size()):
		var clutter := _prefab(SLUGS[index])
		add_child(clutter)
		var triangles := _mesh_triangles(clutter)
		var receiver := clutter.get_node("HitReceiver") as StaticBody3D
		var contact := clutter.get_node("PlayerContact") as Area3D
		check(triangles <= 100 and triangles > 0, SLUGS[index] + " triangle budget")
		# 尺寸上限按件声明：椅子按用户 2026-10-29 指定 +50% 后为 1.29m，
		# 已超过 1m；其余四件仍守 1m。
		var size_limit := 1.30 if SLUGS[index] == "breakable_chair" else 1.00
		var max_edge := maxf(clutter.bounds_size.x, maxf(clutter.bounds_size.y, clutter.bounds_size.z))
		check(max_edge <= size_limit + 0.001, "%s size budget %0.3f > %0.2f" % [SLUGS[index], max_edge, size_limit])
		check(receiver.collision_layer == 4 and receiver.collision_mask == 0, SLUGS[index] + " projectile nonblocking layer")
		check(contact.collision_layer == 0 and contact.collision_mask == 1, SLUGS[index] + " player nonblocking layer")
		check(clutter.scale.is_equal_approx(Vector3.ONE), SLUGS[index] + " unit scale")
		await get_tree().physics_frame
		await get_tree().process_frame
		var isolated_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 0.28, 1), Vector3(0, 0.28, -1), 4)
		check(not get_viewport().world_3d.direct_space_state.intersect_ray(isolated_ray).is_empty(), SLUGS[index] + " isolated layer 4 ray")
		for mesh_value in clutter.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_value as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
				check(material != null and material.albedo_texture != null and material.albedo_texture.resource_path.ends_with("设施低亮多巴胺色盘_10x10_512.png"), SLUGS[index] + " shared palette")
				check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, SLUGS[index] + " nearest palette filter")
		check(clutter.shatter(Vector3.RIGHT), SLUGS[index] + " initial break")
		check(not clutter.shatter(Vector3.LEFT), SLUGS[index] + " idempotent break")
		check(clutter.fragment_total() <= 5, SLUGS[index] + " fragment limit")
		# 飞行段逐帧采峰值：业主 2026-10-29 要求「范围至少高一点，力道足一些」，
		# 只看落点看不出弧高，必须实测飞起来的最高点。
		var peak := 0.0
		var remnants := clutter.get_node("GroundRemnants")
		for step in range(56):
			await get_tree().physics_frame
			for fragment_value in remnants.get_children():
				peak = maxf(peak, (fragment_value as MeshInstance3D).position.y)
		await get_tree().create_timer(0.45).timeout
		var settled := clutter.fragment_positions()
		check(clutter.is_settled(), SLUGS[index] + " settled")
		check(peak >= 0.55, "%s 破碎弧线太低 peak=%0.2f" % [SLUGS[index], peak])
		await get_tree().create_timer(0.2).timeout
		check(settled == clutter.fragment_positions(), SLUGS[index] + " persistent stationary remnants")
		for point in settled:
			check(point.y >= 0.0 and point.y <= 0.25, SLUGS[index] + " ground remnants")
		# 落地必须「贴地」而不是「穿地」：逐块取最低顶点，允许 ±2cm。
		for fragment_value in remnants.get_children():
			var shard := fragment_value as MeshInstance3D
			var lowest := INF
			for surface in shard.mesh.get_surface_count():
				for vertex in shard.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					lowest = minf(lowest, (shard.transform * (vertex as Vector3)).y)
			check(absf(lowest) <= 0.02, SLUGS[index] + " shard not resting on the floor %0.3f" % lowest)
		# 散开范围：既要有足够半径（业主嫌小），又不能飞出房间级尺度。
		var spread := 0.0
		var min_gap := INF
		for first in range(settled.size()):
			spread = maxf(spread, settled[first].length())
			for second in range(first + 1, settled.size()):
				min_gap = minf(min_gap, Vector2(
					settled[first].x - settled[second].x,
					settled[first].z - settled[second].z
				).length())
		check(spread >= 0.75, "%s 散落范围太小 %0.2f" % [SLUGS[index], spread])
		check(spread <= 2.80, "%s 散落范围过大 %0.2f" % [SLUGS[index], spread])
		check(min_gap >= 0.26, "%s 碎块黏在一起 min_gap=%0.2f" % [SLUGS[index], min_gap])
		_check_shard_identity(clutter, remnants)
		report["assets"].append({
			"slug": SLUGS[index], "triangles": triangles,
			"bounds_m": str(clutter.bounds_size), "fragments": clutter.fragment_total(),
			"peak_m": snappedf(peak, 0.01), "spread_m": snappedf(spread, 0.01),
			"min_gap_m": snappedf(min_gap, 0.01),
		})
		clutter.queue_free()
		await get_tree().process_frame


## 三类碎片的形态与配色必须真的不同，不是同一套白块换色。
## 判据取「每片三角数 + 取的色盘格 + 碎块是否够大」三项，都是可机验的硬事实。
func _check_shard_identity(clutter: BreakableClutter3D, remnants: Node) -> void:
	var slug := clutter.name
	var shards := remnants.get_children()
	check(shards.size() == 5, slug + " 碎片数不是 5")
	var body_edge := maxf(clutter.bounds_size.x, maxf(clutter.bounds_size.y, clutter.bounds_size.z))
	var largest := 0.0
	for fragment_value in shards:
		var shard := fragment_value as MeshInstance3D
		var arrays := shard.mesh.surface_get_arrays(0)
		var tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var uv := (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[0]
		var extent := shard.mesh.get_aabb().size
		largest = maxf(largest, maxf(extent.x, maxf(extent.y, extent.z)))
		match clutter.clutter_kind:
			"jar", "vase":
				check(tris == 20, "%s 陶片三角数异常 %d" % [slug, tris])
				# 陶片按件在自己的两格里轮转：罐 (6,3)/(8,4)、瓶 (2,6)/(8,4)。
				var ceramic_ok := (
					(absf(uv.y - 0.65) < 0.04 and clutter.clutter_kind == "jar")
					or (absf(uv.y - 0.35) < 0.04 and clutter.clutter_kind == "vase")
					or absf(uv.y - 0.55) < 0.04
				)
				check(ceramic_ok, "%s 陶片没取本体陶色 uv=%s" % [slug, uv])
			"book_stack":
				check(tris == 12, "%s 书页三角数异常 %d" % [slug, tris])
				check(uv.x > 0.80 and uv.y < 0.30, "%s 书页不是浅色格 uv=%s" % [slug, uv])
			_:
				check(tris == 12, "%s 木板三角数异常 %d" % [slug, tris])
				check(absf(uv.y - 0.75) < 0.04, "%s 木板没取木色格 uv=%s" % [slug, uv])
	# 碎块要「够大」：业主嫌之前的碎块太小。取最大碎块最长边 ≥ 本体最长边 12%。
	check(largest >= body_edge * 0.12, "%s 碎块偏小 %0.3f vs body %0.3f" % [slug, largest, body_edge])


func _new_room() -> DungeonRoom3D:
	var room := DungeonRoom3D.new()
	room.configure({"room_id": "qa_breakable_clutter", "room_type": "STAIR_LOBBY", "size_class": "tower_cell", "doors": ["south"], "door_targets": {"south": "next"}, "custom_dimensions": Vector2(15, 15), "tower_module_shell": true})
	add_child(room)
	room.ensure_shell_built()
	room.ensure_detail_built()
	# 正式游戏里房间由流送置为 ACTIVE 后才解除 DISABLED 并进入物理空间；
	# 测试必须走同一条入口，否则受击体不会注册到物理空间。
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return room


func _verify_formal_room_and_projectiles() -> void:
	var room: DungeonRoom3D = await _new_room()
	check(int(room.get_room_snapshot().get("breakable_clutter_count", 0)) == 5, "five formal room instances")
	if DisplayServer.get_name() != "headless":
		await _capture_room(room, "godot_safe_room_intact")
	var direction := Vector3(0, 0, -1)
	for slug in SLUGS:
		var clutter := room.find_child("InteractiveClutter_" + slug, true, false) as BreakableClutter3D
		check(clutter != null, "formal placement " + slug)
		if clutter == null:
			continue
		var projectile := Projectile3D.new()
		add_child(projectile)
		projectile.position = clutter.global_position - direction * 1.0 + Vector3(0, 0.28, 0)
		projectile.activate({"direction": direction, "speed": 20.0, "damage": 1, "hostile": false}, projectile.position)
		await get_tree().process_frame
		await get_tree().physics_frame
		for step in range(24):
			await get_tree().physics_frame
			await get_tree().process_frame
			if clutter.is_broken():
				break
		check(clutter.is_broken(), "real Projectile3D hit " + slug)
		check(clutter.break_direction().dot(direction) > 0.99, "real shot direction " + slug)
		if clutter.is_broken():
			projectile_hit_count += 1
		if is_instance_valid(projectile):
			projectile.queue_free()
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout
	report["projectile_direction_verified"] = projectile_hit_count == 5
	report["projectile_hit_count"] = projectile_hit_count
	room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	for step in range(3):
		await get_tree().process_frame
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	var restored := 0
	for slug in SLUGS:
		var clutter := room.find_child("InteractiveClutter_" + slug, true, false) as BreakableClutter3D
		if clutter != null and clutter.is_broken() and clutter.is_settled() and clutter.fragment_total() <= 5:
			restored += 1
	check(restored == 5, "room streaming restores persistent remnants")
	report["stream_restore_count"] = restored
	if DisplayServer.get_name() != "headless":
		await _capture_room(room, "godot_safe_room_remnants")
	room.queue_free()
	await get_tree().process_frame
	await _verify_player_contact()


## 真实入口安全房内的落位与残留截图：使用房间自身的灯光与墙体，不另搭摄影棚。
func _capture_room(room: DungeonRoom3D, shot_name: String) -> void:
	var out := OS.get_environment("BREAKABLE_CLUTTER_QA_DIR")
	if out.is_empty():
		return
	# 房间自身有 WastelandLight3D 顶灯，但验收场景没有 WorldEnvironment；
	# 不补环境就等于把房间拍在全黑里（首版即此问题）。
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.11, 0.14, 0.18)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.8, 0.86, 1.0)
	world.environment.ambient_light_energy = 0.55
	world.environment.fog_enabled = false
	add_child(world)
	var lit := 0
	for value in room.find_children("*", "WastelandLight3D", true, false):
		(value as WastelandLight3D).set_light_enabled(true)
		lit += 1
	report["room_light_count"] = lit
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 200.0
	camera.position = room.to_global(Vector3(0.0, 1.55, 4.6))
	camera.look_at(room.to_global(Vector3(0.0, 0.12, 1.5)))
	camera.make_current()
	for step in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out + "/" + shot_name + ".png")
	var buckets := {}
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			var pixel := image.get_pixel(x, y)
			buckets[int((pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722) * 31)] = true
	check(buckets.size() >= 6, "safe room capture is not blank (%d luma buckets)" % buckets.size())
	camera.position = room.to_global(Vector3(0.0, 1.05, 3.5))
	camera.look_at(room.to_global(Vector3(0.0, 0.05, 1.5)))
	for step in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + shot_name + "_close.png")
	camera.queue_free()
	world.queue_free()
	print("BATTLE_BREAKABLE_CLUTTER_ROOM_RENDER_OK lights=%d buckets=%d" % [lit, buckets.size()])


func _verify_player_contact() -> void:
	var clutter := _prefab("breakable_book_stack")
	add_child(clutter)
	var player := CharacterBody3D.new()
	player.collision_layer = 1
	player.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	player.add_child(shape)
	add_child(player)
	player.position = Vector3(0, 0, 1.6)
	for step in range(55):
		player.velocity = Vector3(0, 0, -4.0)
		player.move_and_slide()
		await get_tree().physics_frame
	check(clutter.is_broken(), "real CharacterBody3D contact")
	check(clutter.break_direction().dot(Vector3.FORWARD) > 0.99, "player velocity direction")
	check(player.position.z < -0.5, "intact/broken clutter never blocks player")
	report["player_contact_verified"] = clutter.is_broken()
	report["player_final_z_m"] = player.position.z
	player.queue_free()
	clutter.queue_free()
	await get_tree().process_frame


func _capture_gallery() -> void:
	gallery = Node3D.new()
	add_child(gallery)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202936")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e0e7ef")
	environment.environment.ambient_light_energy = 0.8
	gallery.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -28, 0)
	light.light_energy = 2.0
	gallery.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.4
	gallery.add_child(camera)
	camera.position = Vector3(2.9, 3.1, -6.6)
	camera.look_at(Vector3(0, 0.30, 0))
	camera.make_current()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(22, 16)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(0, 0, 0.8)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("3a4553")
	floor_material.roughness = 0.9
	floor_instance.material_override = floor_material
	gallery.add_child(floor_instance)
	# 间距按放大后的实际包络拉开，别让椅子（0.75 宽）跟木箱互相插进去。
	for index in range(SLUGS.size()):
		var clutter := _prefab(SLUGS[index])
		gallery.add_child(clutter)
		clutter.position = Vector3((index - 2) * 1.75, 0, 0)
	for step in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("BREAKABLE_CLUTTER_QA_DIR")
	if not out.is_empty():
		get_viewport().get_texture().get_image().save_png(out + "/godot_clutter_intact.png")
	for clutter_value in gallery.find_children("Breakable*", "BreakableClutter3D", true, false):
		(clutter_value as BreakableClutter3D).shatter(Vector3(0, 0, 1))
	# 抬升段中段抓一张：这是「力道」最直观的证据，落地图看不出弧高。
	await get_tree().create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	if not out.is_empty():
		get_viewport().get_texture().get_image().save_png(out + "/godot_clutter_breaking.png")
	await get_tree().create_timer(0.90).timeout
	await RenderingServer.frame_post_draw
	if not out.is_empty():
		get_viewport().get_texture().get_image().save_png(out + "/godot_clutter_remnants.png")
		camera.size = 3.2
		camera.position = Vector3(0.6, 1.5, -3.4)
		camera.look_at(Vector3(0, 0.08, 0.5))
		for step in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/godot_clutter_remnants_close.png")
		camera.position = Vector3(0.0, 1.15, -2.15)
		camera.size = 2.2
		camera.look_at(Vector3(0, 0.06, 0.35))
		for step in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/godot_clutter_remnants_close.png")
		print("BATTLE_BREAKABLE_CLUTTER_RENDER_OK")
