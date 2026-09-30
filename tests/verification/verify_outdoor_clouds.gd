extends Node
## OUTDOOR-CLOUDS: verify mounted render volumes against independent building bounds.
## Launch with an isolated APPDATA before Autoload startup; test_mode alone is insufficient.

const CLOUD_SCENE := "res://assets/art/vfx/environment_3d/cloud_sea/vfx_env_cloud_sea_root_top3d.tscn"
const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const CLEARANCE_M := 1.5
const FLOOR_99_Y := -12.0
const SEA_TOP_MAX_Y := -13.5
const EPSILON := 0.001

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	var packed := load(CLOUD_SCENE) as PackedScene
	_expect(packed != null, "cloud Prefab must load independently")
	if packed == null:
		_finish()
		return
	var standalone := packed.instantiate() as VfxEffectBase3D
	_expect(standalone != null, "cloud root must extend VfxEffectBase3D")
	if standalone == null:
		_finish()
		return
	add_child(standalone)
	_expect(standalone.get_script().get_global_name() == "VfxCloudSea3D", "cloud root class must be VfxCloudSea3D")
	_expect(str(standalone.get_meta("asset_id", "")).begins_with("VFX-"), "independent Prefab must register a VFX AssetID")
	_expect(not str(standalone.get_meta("asset_version", "")).is_empty(), "independent Prefab must register its asset version")
	_expect(standalone.get_node_or_null("CloudSea") is Node3D, "Prefab must author CloudSea children")
	_expect(standalone.get_node_or_null("AirWisps") is Node3D, "Prefab must author AirWisps children")
	_expect(_collision_nodes(standalone).is_empty(), "pure visual Prefab must contain no collision nodes")
	standalone.queue_free()
	await get_tree().process_frame

	var tower_packed := load(TOWER_SCENE) as PackedScene
	_expect(tower_packed != null, "production tower scene must load")
	if tower_packed == null:
		_finish()
		return
	var tower := tower_packed.instantiate() as TowerDescent3D
	_expect(tower != null, "production tower must instantiate")
	if tower == null:
		_finish()
		return
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for _frame in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	var clouds := tower.get_node_or_null("OutdoorClouds") as VfxEffectBase3D
	var atmosphere := tower.get_node_or_null("TowerAtmosphere3D")
	_expect(clouds != null, "production tower must mount OutdoorClouds Prefab")
	_expect(atmosphere != null and atmosphere.has_method("get_city_layout"), "production atmosphere must expose oriented city layout")
	if clouds == null or atmosphere == null:
		tower.queue_free()
		await get_tree().process_frame
		_finish()
		return
	_expect(clouds.scene_file_path == CLOUD_SCENE, "production cloud scene must use independent registered Prefab")
	for method in ["get_presentation_snapshot", "get_cloud_volumes", "get_exclusion_bounds"]:
		_expect(clouds.has_method(method), "cloud query is missing: " + method)
	if not clouds.has_method("get_presentation_snapshot") or not clouds.has_method("get_cloud_volumes") or not clouds.has_method("get_exclusion_bounds"):
		tower.queue_free()
		await get_tree().process_frame
		_finish()
		return
	var city_layout: Array = atmosphere.call("get_city_layout")
	var context := {
		"world_root": tower,
		"city_layout": city_layout,
		"main_tower_rect": Rect2(-50.0, -35.0, 100.0, 80.0),
		"floor_99_y": FLOOR_99_Y,
		"enabled": true,
	}
	var obstacles := _independent_building_bounds(tower, city_layout)
	var initial: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(bool(initial.get("enabled", false)), "production tower clouds must be enabled after installation")
	_expect(is_equal_approx(float(initial.get("floor_99_y", INF)), FLOOR_99_Y), "99F height must use real world Y=-12m")
	_validate_mounted_volumes(clouds, obstacles)
	_validate_keepout_coverage(clouds, obstacles)
	_validate_baked_exterior_mask(clouds, obstacles)
	await _validate_flow_and_persistence(clouds)
	_validate_rejection_and_restore(clouds, context)
	_validate_disabled_context(clouds, context)
	_validate_quality_and_stale_geometry(clouds, tower, context)
	await _validate_player_camera_render(clouds, tower)
	await _validate_user_corner_render(clouds, tower)
	print("OUTDOOR_CLOUDS_METRICS sea=", initial.get("sea_count", -1), " wisps=", initial.get("wisp_count", -1), " obstacles=", obstacles.size(), " rejected=", initial.get("rejected_count", -1))
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _validate_mounted_volumes(clouds: Node3D, obstacles: Array[AABB]) -> void:
	var volumes: Array = clouds.call("get_cloud_volumes")
	var actual_meshes := _mesh_nodes(clouds)
	_expect(not actual_meshes.is_empty(), "cloud Prefab must mount actual MeshInstance3D volumes")
	_expect(volumes.size() == actual_meshes.size(), "cloud query must report every authored render volume")
	_expect(_collision_nodes(clouds).is_empty(), "production cloud Prefab must not introduce physics")
	var sea_count := 0
	var wisp_count := 0
	var wisp_heights: Dictionary = {}
	var wisp_sizes: Dictionary = {}
	var wisp_min_y := INF
	var wisp_max_y := -INF
	for mesh_node in actual_meshes:
		_expect(mesh_node.mesh is BoxMesh, "cloud bounds must be authored BoxMesh: " + str(mesh_node.name))
		if mesh_node.mesh == null:
			continue
		var actual_bounds := _transformed_aabb(mesh_node.mesh.get_aabb(), mesh_node.global_transform)
		var query_match := false
		for raw_entry in volumes:
			var entry: Dictionary = raw_entry
			if entry.get("node") == mesh_node:
				query_match = true
				_expect(entry.get("bounds") is AABB, "cloud query bounds must be a world-space AABB")
				if entry.get("bounds") is AABB:
					_expect(_same_bounds(actual_bounds, entry["bounds"]), "query bounds must match mounted mesh: " + str(mesh_node.name))
				_expect(bool(entry.get("enabled", false)) == mesh_node.is_visible_in_tree(), "query enabled must match actual visibility: " + str(mesh_node.name))
		_expect(query_match, "authored cloud mesh missing from query: " + str(mesh_node.name))
		_validate_mounted_material(mesh_node)
		if not mesh_node.is_visible_in_tree():
			continue
		if str(mesh_node.get_parent().name) == "AirWisps":
			for obstacle in obstacles:
				_expect(not actual_bounds.intersects(obstacle.grow(CLEARANCE_M)), "air wisp enters building clearance: " + str(mesh_node.name))
		if str(mesh_node.get_parent().name) == "CloudSea":
			sea_count += 1
			_expect(actual_bounds.end.y <= SEA_TOP_MAX_Y + EPSILON, "main cloud sea must remain below 99F by 1.5m: " + str(mesh_node.name))
		elif str(mesh_node.get_parent().name) == "AirWisps":
			wisp_count += 1
			wisp_heights[snappedf(actual_bounds.get_center().y, 0.1)] = true
			wisp_sizes[str(actual_bounds.size.snapped(Vector3.ONE * 0.1))] = true
			wisp_min_y = minf(wisp_min_y, actual_bounds.get_center().y)
			wisp_max_y = maxf(wisp_max_y, actual_bounds.get_center().y)
		else:
			_expect(false, "cloud render mesh must belong to CloudSea or AirWisps")
	var snapshot: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(int(snapshot.get("sea_count", -1)) == sea_count, "sea count must equal visible mounted meshes")
	_expect(int(snapshot.get("wisp_count", -1)) == wisp_count, "wisp count must equal visible mounted meshes")
	_expect(sea_count > 0, "main cloud sea must contain visible volumes")
	_expect(sea_count == 1, "v002 must use a continuous world density volume, avoiding overlapping bank seams")
	_expect(wisp_count >= 10 and wisp_count <= 30, "air wisps must remain sparse: 10..30 visible volumes")
	_expect(wisp_heights.size() >= 3 and wisp_max_y - wisp_min_y >= 10.0, "air wisps need at least three staggered heights across 10m")
	_expect(wisp_sizes.size() >= 3, "air wisps need at least three visibly different volume sizes")
	var player_camera := (clouds.get_parent().get("player") as Node3D).get_node("Camera3D") as Camera3D
	_expect(is_equal_approx(player_camera.far, 520.0), "actual rooftop camera clip must retain TowerDescent3D's 520m contract")
	_expect(sea_count != 1 or (actual_meshes[0].scale.x > 400 and actual_meshes[0].scale.z > 500), "continuous cloud field must fill the established outdoor extent")


func _validate_player_camera_render(clouds: Node3D, tower: Node3D) -> void:
	var player := tower.get("player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(48, 0.05, 39)
	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	(tower.get_node("HUD") as CanvasLayer).hide()
	GameTimeManager.set_clock_running(false)
	GameTimeManager.set_elapsed_game_seconds(19.0 * 3600.0, false)
	clouds.set_process(false)
	clouds.visible = false
	for _frame in range(15):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var without := get_viewport().get_texture().get_image()
	clouds.visible = true
	for _frame in range(15):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var with_clouds := get_viewport().get_texture().get_image()
	var difference := 0.0
	var count := 0
	var peak := 0.0
	for y in range(int(with_clouds.get_height() * 0.2), int(with_clouds.get_height() * 0.85), 4):
		for x in range(int(with_clouds.get_width() * 0.70), int(with_clouds.get_width() * 0.94), 4):
			var a := with_clouds.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			peak = maxf(peak, maxf(a.r, maxf(a.g, a.b)))
			count += 3
	var mean_difference := difference / maxf(count, 1)
	_expect(mean_difference > 0.012, "clouds must visibly render in the actual player camera, not only inspection cameras")
	_expect(peak < 0.99, "player outdoor cloud region must retain highlight headroom instead of clipping white")
	print("OUTDOOR_CLOUDS_PLAYER_RENDER mean_rgb_difference=", mean_difference, " peak=", peak)
	var authored_far := camera.far
	# 99F uses 145m. Exercise the same near-face renderer with that authoritative shorter clip.
	camera.far = 145.0
	clouds.visible = false
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	without = get_viewport().get_texture().get_image()
	clouds.visible = true
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	with_clouds = get_viewport().get_texture().get_image()
	difference = 0.0
	count = 0
	for y in range(int(with_clouds.get_height() * 0.2), int(with_clouds.get_height() * 0.85), 4):
		for x in range(int(with_clouds.get_width() * 0.70), int(with_clouds.get_width() * 0.94), 4):
			var a := with_clouds.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			count += 3
	var short_clip_difference := difference / maxf(count, 1)
	_expect(short_clip_difference > 0.012, "clouds must remain visible with 99F's 145m clip distance")
	print("OUTDOOR_CLOUDS_SHORT_CLIP_RENDER far=145 mean_rgb_difference=", short_clip_difference)
	camera.far = authored_far
	clouds.set_process(true)


func _validate_user_corner_render(clouds: Node3D, tower: Node3D) -> void:
	var player := tower.get("player") as Node3D
	player.global_position = Vector3(-48, 0.05, -31)
	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	GameTimeManager.set_elapsed_game_seconds(17.7 * 3600.0, false)
	clouds.set_process(false)
	clouds.call("_process", 0.0)
	clouds.visible = false
	for _frame in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var without := get_viewport().get_texture().get_image()
	clouds.visible = true
	for _frame in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var with_clouds := get_viewport().get_texture().get_image()
	var difference := 0.0
	var count := 0
	for y in range(int(with_clouds.get_height() * 0.10), int(with_clouds.get_height() * 0.75), 4):
		for x in range(int(with_clouds.get_width() * 0.06), int(with_clouds.get_width() * 0.38), 4):
			var a := with_clouds.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			count += 3
	var mean_difference := difference / maxf(count, 1)
	_expect(mean_difference > 0.012, "the reported northwest player corner must actually display clouds in the formal environment")
	print("OUTDOOR_CLOUDS_USER_CORNER_RENDER mean_rgb_difference=", mean_difference)
	clouds.set_process(true)


func _validate_mounted_material(mesh_node: MeshInstance3D) -> void:
	var material := mesh_node.material_override as ShaderMaterial
	_expect(material != null and material.shader != null, "actual cloud meshes must use mounted ShaderMaterial")
	if material == null or material.shader == null:
		return
	var code := material.shader.code
	_expect(code.contains("flow_time"), "mounted cloud shader must consume flow_time")
	_expect(code.contains("ALPHA"), "mounted cloud shader must output alpha for layered translucency")
	var opacity_found := false
	for uniform_entry in material.shader.get_shader_uniform_list():
		var uniform_name := str((uniform_entry as Dictionary).get("name", ""))
		if uniform_name in ["opacity", "cloud_opacity", "base_opacity"]:
			opacity_found = true
			var opacity: Variant = material.get_shader_parameter(uniform_name)
			_expect(opacity is float or opacity is int, "cloud opacity must be explicitly mounted on material")
			if opacity is float or opacity is int:
				_expect(float(opacity) > 0.0 and float(opacity) < 1.0, "cloud opacity must remain translucent")
	_expect(opacity_found, "mounted shader must expose explicit cloud opacity")
	_expect(material.get_shader_parameter("flow_time") is float, "mounted material must receive flow_time")


func _validate_keepout_coverage(clouds: Node3D, obstacles: Array[AABB]) -> void:
	var supplied: Array = clouds.call("get_exclusion_bounds")
	_expect(not supplied.is_empty(), "runtime must retain exclusion bounds for auditing")
	var snapshot: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(int(snapshot.get("keepout_count", -1)) == supplied.size(), "keepout query must match snapshot count")
	for obstacle in obstacles:
		var covered := false
		for raw_bounds in supplied:
			if raw_bounds is AABB and (raw_bounds as AABB).encloses(obstacle.grow(CLEARANCE_M - EPSILON)):
				covered = true
				break
		_expect(covered, "reported keepouts must cover independently measured building bounds plus clearance: " + str(obstacle))


func _validate_baked_exterior_mask(clouds: Node3D, obstacles: Array[AABB]) -> void:
	var first := _mesh_nodes(clouds)[0]
	var material := first.material_override as ShaderMaterial
	var fallback_count := int(material.get_shader_parameter("fallback_count"))
	var fallback_regions: PackedVector4Array = material.get_shader_parameter("fallback_regions")
	_expect(fallback_regions.size() == 32, "mounted material must receive a bounded complete fallback region array")
	var texture := material.get_shader_parameter("building_distance") as Texture3D
	_expect(texture != null, "cloud material must mount a native 3D exclusion texture")
	if texture == null:
		return
	_expect(texture.resource_path.ends_with("cloud_keepout.res"), "material must use the audited exclusion field")
	_expect(texture.get_width() == 256 and texture.get_height() == 80 and texture.get_depth() == 288, "3D mask must retain conservative baked resolution")
	var slices := texture.get_data()
	_expect(slices.size() == 288, "actual GPU exclusion texture must be readable: run with a real renderer")
	if slices.is_empty():
		return
	var origin := Vector3(-240, -110, -320)
	var extent := Vector3(480, 160, 540)
	var dims := Vector3(256, 80, 288)
	# Independent sample reconstruction matches sampler3D trilinear coordinates.
	for obstacle in obstacles:
		var box := obstacle.grow(1.5)
		var lo := box.position.max(Vector3(-239, -85, -319))
		var hi := box.end.min(Vector3(239, 40, 219))
		if hi.x < lo.x or hi.y < lo.y or hi.z < lo.z:
			continue
		var clipped := AABB(lo, hi - lo)
		var points: Array[Vector3] = [clipped.get_center()]
		for corner in range(8):
			points.append(clipped.get_endpoint(corner))
		for point in points:
			var pixel := (point - origin) / extent * dims - Vector3.ONE * 0.5
			var cell := Vector3i(pixel.floor())
			var f := pixel - pixel.floor()
			var sample := 0.0
			for dz in range(2):
				for dy in range(2):
					for dx in range(2):
						var x := clampi(cell.x + dx, 0, 255)
						var y := clampi(cell.y + dy, 0, 79)
						var z := clampi(cell.z + dz, 0, 287)
						var weight := (f.x if dx == 1 else 1.0 - f.x) * (f.y if dy == 1 else 1.0 - f.y) * (f.z if dz == 1 else 1.0 - f.z)
						sample += slices[z].get_pixel(x, y).r * weight * 16.0
			for region in range(fallback_count):
				var region_lo := Vector3(fallback_regions[region * 2].x, fallback_regions[region * 2].y, fallback_regions[region * 2].z)
				var region_hi := Vector3(fallback_regions[region * 2 + 1].x, fallback_regions[region * 2 + 1].y, fallback_regions[region * 2 + 1].z)
				var outside := (region_lo - point).max(point - region_hi).max(Vector3.ZERO)
				sample = minf(sample, outside.length())
			_expect(sample <= 3.0, "GPU mask plus actual fallback uniforms must erase density at independently measured model + clearance, distance=" + str(sample))
	_expect(material.shader.code.contains("smoothstep(3.0, 7.0, distance_to_building)"), "shader must apply conservative masked density with feathered clearance")
	_expect(material.shader.code.contains("far_t = min(far_t, dot(local_depth"), "volume march must stop at opaque geometry")


func _validate_flow_and_persistence(clouds: Node3D) -> void:
	var meshes := _mesh_nodes(clouds)
	var initial_bounds: Dictionary = {}
	for mesh_node in meshes:
		initial_bounds[mesh_node] = _transformed_aabb(mesh_node.mesh.get_aabb(), mesh_node.global_transform)
	var before: Dictionary = clouds.call("get_presentation_snapshot")
	var before_time := float(before.get("flow_time", -1.0))
	await get_tree().create_timer(0.12, true).timeout
	var live: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(float(live.get("flow_time", -1.0)) > before_time, "real unpaused process must advance cloud flow")
	get_tree().paused = true
	var paused_before: Dictionary = clouds.call("get_presentation_snapshot")
	await get_tree().create_timer(0.12, true).timeout
	var paused_after: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(is_equal_approx(float(paused_before.get("flow_time", -1.0)), float(paused_after.get("flow_time", -2.0))), "cloud flow must respect pause")
	get_tree().paused = false
	var manual_before: Dictionary = clouds.call("get_presentation_snapshot")
	for _step in 600:
		clouds.call("_process", 0.1)
	var after: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(is_instance_valid(clouds) and not clouds.is_queued_for_deletion(), "persistent environment clouds must survive 60s")
	_expect(bool(after.get("enabled", false)) and clouds.visible, "clouds must not retire after inherited VFX lifetime")
	_expect(absf(float(after.get("flow_time", -1.0)) - float(manual_before.get("flow_time", -1.0)) - 60.0) < 0.05, "cloud flow must advance by real delta seconds")
	for mesh_node in meshes:
		_expect(_same_bounds(initial_bounds[mesh_node], _transformed_aabb(mesh_node.mesh.get_aabb(), mesh_node.global_transform)), "flow must remain bounded without world drift: " + str(mesh_node.name))
		var material := mesh_node.material_override as ShaderMaterial
		if material != null:
			_expect(absf(float(material.get_shader_parameter("flow_time")) - float(after.get("flow_time", -1.0))) < 0.05, "actual shader must receive advanced flow_time: " + str(mesh_node.name))
	_expect(int(before.get("sea_count", -1)) == int(after.get("sea_count", -2)), "persistent cloud sea must retain volume count")
	_expect(int(before.get("wisp_count", -1)) == int(after.get("wisp_count", -2)), "persistent air wisps must retain volume count")


func _validate_rejection_and_restore(clouds: VfxEffectBase3D, context: Dictionary) -> void:
	var test_mesh: MeshInstance3D = null
	for mesh_node in _mesh_nodes(clouds):
		if mesh_node.is_visible_in_tree() and str(mesh_node.get_parent().name) == "AirWisps":
			test_mesh = mesh_node
			break
	_expect(test_mesh != null, "negative control requires a visible authored cloud")
	if test_mesh == null:
		return
	var authored_transform := test_mesh.transform
	var before: Dictionary = clouds.call("get_presentation_snapshot")
	test_mesh.global_position = Vector3(0.0, -20.0, 0.0)
	clouds.configure(Color.WHITE, 1.0, context)
	var rejected: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(not test_mesh.is_visible_in_tree(), "negative control: cloud moved inside main tower must be rejected")
	_expect(int(rejected.get("rejected_count", -1)) > int(before.get("rejected_count", -1)), "negative control must increase rejection count")
	test_mesh.transform = authored_transform
	clouds.configure(Color.WHITE, 1.0, context)
	var restored: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(test_mesh.is_visible_in_tree(), "reconfiguring a restored outdoor cloud must restore visibility")
	_expect(int(restored.get("rejected_count", -1)) == int(before.get("rejected_count", -2)), "reconfiguration must clear stale rejection state")
	print("OUTDOOR_CLOUDS_NEGATIVE_CONTROL moved_inside=rejected restored=visible")


func _validate_disabled_context(clouds: VfxEffectBase3D, context: Dictionary) -> void:
	var disabled_context := context.duplicate()
	disabled_context["enabled"] = false
	clouds.configure(Color.WHITE, 1.0, disabled_context)
	var disabled: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(not bool(disabled.get("enabled", true)), "expedition/disabled context must disable clouds")
	for mesh_node in _mesh_nodes(clouds):
		_expect(not mesh_node.is_visible_in_tree(), "disabled context must hide actual mounted cloud volumes")
	clouds.configure(Color.WHITE, 1.0, context)
	var restored: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(bool(restored.get("enabled", false)), "enabled reconfiguration must recover from disabled context")


func _validate_quality_and_stale_geometry(clouds: VfxEffectBase3D, tower: Node3D, context: Dictionary) -> void:
	for profile in ["low", "balanced", "high"]:
		clouds.call("apply_performance_quality", profile)
		var snap: Dictionary = clouds.call("get_presentation_snapshot")
		_expect(int(snap["wisp_count"]) == (12 if profile == "low" else 24), "low quality must halve wisps without reducing the continuous sea")
		_expect(int(snap["sea_count"]) == 1, "all quality levels must retain continuous cloud sea")
		var expected_steps := 40 if profile == "low" else 64 if profile == "balanced" else 96
		for mesh_node in _mesh_nodes(clouds):
			var material := mesh_node.material_override as ShaderMaterial
			_expect(int(material.get_shader_parameter("ray_steps")) == expected_steps, "quality must change mounted GPU ray budget")
			_expect(int(material.get_shader_parameter("light_steps")) == (2 if profile == "low" else 3 if profile == "balanced" else 4), "quality must update actual directional self-shadow samples")
			var billow := material.get_shader_parameter("billow_density") as Texture2D
			_expect(billow != null and billow.get_width() >= 1024, "quality cloud must mount the image-2 density source at native resolution")
			var structure := material.get_shader_parameter("shape_noise") as Texture3D
			_expect(structure != null and structure.get_width() == 128 and structure.get_depth() == 128, "quality cloud must mount periodic volumetric structure")
	var building := tower.get_node("Blocks/Rooftop/CrossTowerRoute/Tower2") as Node3D
	var geometry_before: Dictionary = clouds.call("get_presentation_snapshot")
	var authored := building.transform
	building.position.x += 10.0
	clouds.configure(Color.WHITE, 1.0, context)
	var rejected: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(not bool(rejected["mask_valid"]), "negative control: changed building geometry must invalidate the old mask")
	_expect(int(rejected["fallback_count"]) > 0, "changed building must receive a conservative fallback region")
	_expect(int(rejected["sea_count"]) == 1, "moving one building must retain the continuous cloud sea")
	_validate_baked_exterior_mask(clouds, _independent_building_bounds(tower, context["city_layout"]))
	building.transform = authored
	clouds.configure(Color.WHITE, 1.0, context)
	var restored: Dictionary = clouds.call("get_presentation_snapshot")
	_expect(bool(restored["mask_valid"]) == bool(geometry_before["mask_valid"]) and int(restored["sea_count"]) == 1, "restored geometry must recover its original baked/fallback state with clouds visible")
	_expect(int(restored["fallback_count"]) == int(geometry_before["fallback_count"]), "restoration must clear only the temporary building fallback")
	print("OUTDOOR_CLOUDS_NEGATIVE_CONTROL moved_building=analytic_exclusion sea=retained restored=visible quality_steps=40,64,96")


func _independent_building_bounds(tower: Node3D, city_layout: Array) -> Array[AABB]:
	# Hard-coded outside feature implementation: main tower footprint is excluded at all relevant heights.
	var bounds: Array[AABB] = [AABB(Vector3(-50.0, -100000.0, -35.0), Vector3(100.0, 200000.0, 80.0))]
	for tower_name in ["Tower2", "Tower3", "Skyline08"]:
		var building := tower.get_node_or_null("Blocks/Rooftop/CrossTowerRoute/" + tower_name)
		_expect(building != null, "production exclusion test must include " + tower_name)
		if building == null:
			continue
		var measured := _mesh_nodes(building)
		_expect(not measured.is_empty(), tower_name + " must contain actual render geometry")
		for mesh_node in measured:
			if mesh_node.mesh != null:
				bounds.append(_transformed_aabb(mesh_node.mesh.get_aabb(), mesh_node.global_transform))
	_expect(not city_layout.is_empty(), "production exclusion test must include remote city buildings")
	for raw_placement in city_layout:
		var placement: Dictionary = raw_placement
		var transform: Transform3D = placement["transform"]
		bounds.append(_transformed_aabb(AABB(Vector3.ONE * -0.5, Vector3.ONE), transform))
	return bounds


func _transformed_aabb(local_bounds: AABB, transform: Transform3D) -> AABB:
	# Eight corners retain rotated city footprints and descendant mesh transforms.
	var first := transform * local_bounds.get_endpoint(0)
	var minimum := first
	var maximum := first
	for corner_index in range(1, 8):
		var point := transform * local_bounds.get_endpoint(corner_index)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)


func _mesh_nodes(root_node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D:
		meshes.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		meshes.append_array(_mesh_nodes(child))
	return meshes


func _collision_nodes(root_node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	if root_node is CollisionObject3D or root_node is CollisionShape3D or root_node is CollisionPolygon3D:
		nodes.append(root_node)
	for child in root_node.get_children():
		nodes.append_array(_collision_nodes(child))
	return nodes


func _same_bounds(left: AABB, right: AABB) -> bool:
	return left.position.is_equal_approx(right.position) and left.size.is_equal_approx(right.size)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("OUTDOOR_CLOUDS_OK checks=", _checks, " exclusions=independent bounds=stable flow=persistent negative_controls=2")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("OUTDOOR_CLOUDS_FAIL: " + failure)
	print("OUTDOOR_CLOUDS_FAILED count=", _failures.size(), " checks=", _checks)
	get_tree().quit(1)
