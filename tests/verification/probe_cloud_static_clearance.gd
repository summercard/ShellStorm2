extends "res://tests/verification/probe_landscape_perf_20261003.gd"

var failures: Array[String] = []
var checks := 0
var legacy_shader: Shader
var static_shader: Shader
var cloud_materials: Array[ShaderMaterial] = []
var output := OS.get_environment("CLOUD_STATIC_OUTPUT")
var gpu_points: Array[Vector3] = []
var production := OS.get_environment("CLOUD_STATIC_PRODUCTION") == "1"

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("图像与性能禁止headless")
		get_tree().quit(2)
		return
	out_dir = output
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	RuntimePerformanceManager.set_verification_frame_budget_override(2147483647)
	Engine.max_fps = 0
	get_window().size = Vector2i(1280, 720)
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	tower = packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	foundation = tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
	city = foundation.get_node("ProceduralCity500")
	while not city.get("binding_complete"):
		await get_tree().process_frame
	clouds = tower.get_node("OutdoorClouds")
	if production:
		_expect(clouds.get_procedural_city_cache_snapshot().get("valid", false), "正式城市入口必须自动生成缓存，不允许测试显式启用")
	else:
		clouds.set_procedural_static_clearance_enabled(true)
		clouds.set_procedural_city_layout(city.get("placements"), city.get("parameters"))
	await _wait_seconds(2.0)
	GameTimeManager.set_clock_running(false)
	GameTimeManager.set_elapsed_game_seconds(17.7 * 3600.0, false)
	tower._atmosphere.call("_apply_time_of_day")
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	GameTimeManager.process_mode = Node.PROCESS_MODE_DISABLED
	clouds.set_process(false)
	clouds.set("_flow_time", 24.0)
	clouds.apply_performance_quality("high")
	for layer in tower.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	for volume in clouds.get_cloud_volumes():
		cloud_materials.append((volume["node"] as MeshInstance3D).material_override as ShaderMaterial)
	static_shader = cloud_materials[0].shader
	if production:
		_expect(static_shader.resource_path == "res://src/vfx/CloudStaticClearance.gdshader", "正式ready必须实际绑定静态Shader资源")
		for profile in ["low", "balanced", "high"]:
			clouds.apply_performance_quality(profile)
			for material in cloud_materials:
				_expect(material.shader == static_shader and material.get_shader_parameter("procedural_static_enabled") == true, "quality重验不能丢掉正式静态Shader和缓存")
		_validate_standalone()
	legacy_shader = Shader.new()
	legacy_shader.code = FileAccess.get_file_as_string(output.path_join("stylized_cloud.gdshader.before.txt"))
	_expect(not legacy_shader.code.is_empty(), "必须使用独立旧Shader快照")
	viewport_timing_supported = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	profile_supported = RenderingServer.has_method("set_frame_profiling_enabled")
	if profile_supported:
		RenderingServer.call("set_frame_profiling_enabled", true)
	report["metadata"] = {"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info(), "appdata": OS.get_environment("APPDATA"), "user_data_dir": OS.get_user_data_dir(), "seed": 990095, "flow_time": 24.0, "cloud_profile": "high", "cloud_snapshot": clouds.get_presentation_snapshot(), "sun_energy": tower.get_node("DirectionalLight3D").light_energy, "sun_transform": var_to_str(tower.get_node("DirectionalLight3D").global_transform), "graphics": GraphicsSettingsManager.get_settings_snapshot()}
	# 固定整帧时域噪声；仅测试副本关闭雾时域重投影，正式环境不写回。
	if RenderingServer.has_method("set_shader_time_scale"):
		RenderingServer.call("set_shader_time_scale", 0.0)
	var world := tower.get_node("WorldEnvironment") as WorldEnvironment
	var controlled := world.environment.duplicate() as Environment
	controlled.volumetric_fog_temporal_reprojection_enabled = false
	if not production:
		# 云材质unshaded，以下只隔离背景时域GI，不改变云内解析光照。
		controlled.sdfgi_enabled = false
		controlled.ssil_enabled = false
		controlled.ssao_enabled = false
		controlled.ssr_enabled = false
	world.environment = controlled
	Engine.time_scale = 0.0
	get_viewport().use_taa = false
	get_viewport().use_debanding = false
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	get_viewport().use_hdr_2d = OS.get_environment("CLOUD_STATIC_HDR") == "1"
	report["metadata"]["temporal_control"] = "测试视口关闭TAA/去色带/屏幕AA与雾时域重投影，Engine.time_scale=0；保真矩阵另关闭背景SDFGI/SSIL/SSAO/SSR（云unshaded且自身光照不变）；production保留背景GI。正式资源不写回"
	report["metadata"]["background_gi_isolated"] = not production
	report["metadata"]["production_default_entry"] = production
	report["metadata"]["hdr_requested"] = OS.get_environment("CLOUD_STATIC_HDR") == "1"
	report["cache"] = clouds.get_procedural_city_cache_snapshot()
	_validate_art_contract()
	_validate_cache()
	_validate_invalidation()
	await _validate_gpu_distance()
	if OS.get_environment("CLOUD_STATIC_NEGATIVE") == "1":
		_expect(false, "负向测试强制失败，证明断言出口会红")
		report["checks"] = checks
		report["failures"] = failures
		_save()
		get_tree().quit(1)
		return
	var camera := Camera3D.new()
	tower.add_child(camera)
	camera.far = 520.0
	camera.fov = 58.0
	camera.make_current()
	var buildings := clouds.get_procedural_city_exclusion_bounds()
	var focus := buildings[0]
	for box in buildings:
		if box.get_center().distance_to(Vector3(-90, -40, -155)) < focus.get_center().distance_to(Vector3(-90, -40, -155)):
			focus = box
	var views := [
		{"name": "main", "pos": Vector3(78, 37, 88), "target": Vector3(0, -28, -15), "size": Vector2i(1280, 720)},
		{"name": "tower3", "pos": Vector3(-95, 18, -90), "target": Vector3(-12, -42, -153.925626), "size": Vector2i(1280, 720)},
		{"name": "roof_edge", "pos": focus.end + Vector3(15, 12, 15), "target": Vector3(focus.end.x, focus.end.y, focus.end.z), "size": Vector2i(1280, 720)},
		{"name": "street", "pos": Vector3(focus.end.x + 6, -58, focus.end.z + 10), "target": focus.get_center() + Vector3(15, 5, -12), "size": Vector2i(1280, 720)},
		{"name": "tower3_high", "pos": Vector3(-95, 18, -90), "target": Vector3(-12, -42, -153.925626), "size": Vector2i(1920, 1080)}
	]
	if OS.get_environment("CLOUD_STATIC_SMOKE") == "1":
		views.resize(1)
	if production:
		views.resize(2)
	for view in views:
		get_window().size = view["size"]
		camera.position = view["pos"]
		camera.look_at(view["target"], Vector3.UP)
		var projected := camera.unproject_position(view["target"])
		_expect(Rect2(Vector2.ZERO, Vector2(view["size"])).has_point(projected), "目标必须在机位视口内")
		var times := [0.0, 12.0, 60.0]
		var lights := ["day", "night"]
		if production or OS.get_environment("CLOUD_STATIC_SMOKE") == "1":
			times = [12.0]
			lights = ["day"]
		for light: String in lights:
			GameTimeManager.set_elapsed_game_seconds((19.0 if light == "day" else 7.0) * 3600.0, false)
			tower._atmosphere.call("_apply_time_of_day")
			var hour := float(GameTimeManager.get_time_snapshot()["hour_float"])
			_expect(absf(hour - (12.0 if light == "day" else 0.0)) < 0.001, "昼夜标签必须对应真实12点/0点，不可把elapsed误当钟点")
			for flow: float in times:
				clouds.set("_flow_time", flow)
				clouds.call("_sync_dynamic_materials")
				var pair: Dictionary = {}
				var order := ["legacy", "static"] if int(flow) != 12 else ["static", "legacy"]
				for mode: String in order:
					_set_mode(mode)
					print("CLOUD_AB_BEGIN ", view["name"], " ", light, " ", flow, " ", mode)
					await _wait_seconds(3.0)
					await _warm_frames(30)
					var result: Dictionary = await _sample(4.0) if production else {"samples": []}
					await RenderingServer.frame_post_draw
					var image := get_viewport().get_texture().get_image()
					var name := "%s_%s_t%d_%s.png" % [view["name"], light, int(flow), mode]
					_expect(image.save_png(output.path_join(name)) == OK, "图片必须保存")
					pair[mode] = image
					await _warm_frames(30)
					await RenderingServer.frame_post_draw
					var repeated := get_viewport().get_texture().get_image()
					repeated.save_png(output.path_join(name.replace(".png", "_repeat.png")))
					if image.get_format() in [Image.FORMAT_RGBF, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBAH]:
						var raw := FileAccess.open(output.path_join(name + ".float.bin"), FileAccess.WRITE)
						raw.store_buffer(image.get_data())
						image.save_exr(output.path_join(name + ".exr"))
					result.merge({"view": view["name"], "repeat": 0, "mode": mode, "flow_time": flow, "light": light, "sun_energy": tower.get_node("DirectionalLight3D").light_energy, "resolution": [image.get_width(), image.get_height()], "image_format": image.get_format(), "camera": var_to_str(camera.global_transform), "fov": camera.fov, "far": camera.far, "screenshot": name})
					report["runs"].append(result)
					_save()
				_validate_image_pair(pair["legacy"], pair["static"], "%s_%s_t%d" % [view["name"], light, int(flow)])
	_set_mode("static")
	report["checks"] = checks
	report["failures"] = failures
	_save()
	print("CLOUD_STATIC_COMPLETE checks=", checks, " failures=", failures)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _set_mode(mode: String) -> void:
	for material in cloud_materials:
		if production:
			material.shader = legacy_shader if mode == "legacy" else static_shader
		else:
			_expect(material.shader == static_shader, "严格A/B不得更换Shader资源")
		material.set_shader_parameter("procedural_static_enabled", mode == "static")

func _validate_standalone() -> void:
	var prefab := load("res://assets/art/vfx/environment_3d/cloud_sea/vfx_env_cloud_sea_root_top3d.tscn") as PackedScene
	var standalone := prefab.instantiate() as VfxCloudSea3D
	add_child(standalone)
	_expect(standalone.get("_procedural_candidates") == null, "无city的独立Prefab不得生成缓存")
	for volume in standalone.get_cloud_volumes():
		var material := (volume["node"] as MeshInstance3D).material_override as ShaderMaterial
		_expect(material.get_shader_parameter("procedural_city_enabled") == false, "无city的独立Prefab仍走原旧场/fallback")
	standalone.queue_free()

func _warm_frames(count: int) -> void:
	for frame in range(count):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _validate_art_contract() -> void:
	var old := FileAccess.get_file_as_string("res://assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader")
	var optimized := FileAccess.get_file_as_string("res://src/vfx/CloudStaticClearance.gdshader")
	var old_bytes := FileAccess.get_file_as_bytes("res://assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader")
	var new_bytes := FileAccess.get_file_as_bytes("res://src/vfx/CloudStaticClearance.gdshader")
	var old_start := old_bytes.get_string_from_utf8().split("vec3 field")[0].to_utf8_buffer().size()
	var new_start := new_bytes.get_string_from_utf8().split("vec3 field")[0].to_utf8_buffer().size()
	_expect(old_bytes.slice(old_start) == new_bytes.slice(new_start), "艺术函数段必须从vec3 field到末尾逐字节一致")
	var defaults := 0
	for line: String in old.split("\n"):
		if line.begins_with("uniform "):
			_expect(optimized.split("\n").has(line), "所有原艺术uniform声明和默认值必须一致：" + line)
			defaults += 1
	var mutated := optimized.replace("flow_time * 0.18", "flow_time * 0.19")
	_expect(old.substr(old.find("vec3 field")) != mutated.substr(mutated.find("vec3 field")), "艺术段篡改必须被一致性门禁检出")
	_expect(not optimized.replace("uniform int ray_steps = 96;", "uniform int ray_steps = 95;").split("\n").has("uniform int ray_steps = 96;"), "艺术默认值篡改必须检出")
	report["art_contract"] = {"tail_byte_identical": old_bytes.slice(old_start) == new_bytes.slice(new_start), "uniform_declarations": defaults, "negative_art_and_uniform_detected": true}
	_expect(FileAccess.get_file_as_bytes("res://assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader") == FileAccess.get_file_as_bytes(output.path_join("stylized_cloud.gdshader.before.txt")), "原Shader和旧场不得更改")

func _validate_image_pair(a: Image, b: Image, label: String) -> void:
	var changed := 0
	var peak := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var error := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b)))
			peak = maxf(peak, error)
			if error > 0.0:
				changed += 1
	if a.get_format() in [Image.FORMAT_RGBF, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBAH]:
		_expect(peak <= 0.001, "HDR半精度门禁失败：" + label)
	else:
		_expect(peak <= 1.0001 / 255.0 and changed < a.get_width() * a.get_height() * 0.001, "稀疏量化门禁失败：" + label)
	if not report.has("visual"):
		report["visual"] = []
	report["visual"].append({"label": label, "changed_pixels": changed, "peak": peak, "format": a.get_format(), "pixel_exact": changed == 0})

func _legacy_distance(w: Vector3, boxes: Image, grid: Vector4) -> float:
	var cell := Vector2i(Vector2((w.x - grid.x) / grid.z, (w.z - grid.y) / grid.z).floor())
	var answer := 16.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var slot := cell + Vector2i(dx, dz)
			if slot.x < 0 or slot.y < 0 or slot.x >= int(grid.w) or slot.y >= int(grid.w):
				continue
			var h := boxes.get_pixel(slot.x, slot.y + int(grid.w))
			if h.b < 0.5:
				continue
			answer = minf(answer, _slot_distance(w, slot, boxes, int(grid.w)))
	return answer

func _slot_distance(w: Vector3, slot: Vector2i, boxes: Image, grid: int) -> float:
	var f := boxes.get_pixel(slot.x, slot.y)
	var h := boxes.get_pixel(slot.x, slot.y + grid)
	return (Vector3(f.r, h.r, f.g) - w).max(w - Vector3(f.b, h.g, f.a)).max(Vector3.ZERO).length()

func _cached_distance(w: Vector3, boxes: Image, grid: Vector4, slices: Array[Image], origin: Vector3, step: Vector3) -> float:
	var cell := Vector3i(((w - origin) / step).floor())
	var old := Vector2i(Vector2((w.x - grid.x) / grid.z, (w.z - grid.y) / grid.z).floor())
	if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.z >= slices.size() or cell.x >= slices[0].get_width() or cell.y >= slices[0].get_height() or Vector2i((cell.x >> 2) - 1, (cell.z >> 2) - 1) != old:
		return _legacy_distance(w, boxes, grid)
	var ids := slices[cell.z].get_pixel(cell.x, cell.y)
	if ids.r < 0:
		return _legacy_distance(w, boxes, grid)
	var answer := 16.0
	for index in range(4):
		var id := int(ids[index])
		if id == 0:
			break
		var slot := Vector2i((id - 1) % int(grid.w), int((id - 1) / grid.w))
		answer = minf(answer, _slot_distance(w, slot, boxes, int(grid.w)))
	return answer

func _validate_cache() -> void:
	var texture: ImageTexture3D = clouds.get("_procedural_candidates")
	_expect(texture != null, "缓存必须有效")
	if texture == null:
		return
	var slices := texture.get_data()
	var boxes: Image = clouds.get("_procedural_city_texture").get_image()
	var grid: Vector4 = clouds.get("_procedural_city_grid")
	var origin: Vector3 = clouds.get("_candidate_origin")
	var step: Vector3 = clouds.get("_candidate_step")
	var points: Array[Vector3] = []
	for box in clouds.get_procedural_city_exclusion_bounds():
		for corner in range(8):
			for epsilon in [-0.01, 0.0, 0.01, 3.0, 7.0, 16.0]:
				points.append(box.get_endpoint(corner) + Vector3.ONE * epsilon)
		points.append(box.get_center())
		points.append(Vector3(box.get_center().x, box.end.y + 5.0, box.get_center().z))
	var rng := RandomNumberGenerator.new()
	rng.seed = 990095
	for index in range(20000):
		points.append(origin + Vector3(rng.randf_range(-10, 570), rng.randf_range(-10, 186), rng.randf_range(-10, 570)))
	# 空间缓存边界两侧、旧九格切换边界必须保真。
	for z in range(0, slices.size(), 4):
		for x in range(0, slices[0].get_width(), 4):
			for epsilon in [-0.0001, 0.0, 0.0001]:
				points.append(origin + Vector3(x * step.x + epsilon, 64.0, z * step.z + epsilon))
	# 对面法向精确覆盖3/7/16m阈值及两侧，不只沿角点对角线采样。
	for box in clouds.get_procedural_city_exclusion_bounds():
		for distance in [2.9999, 3.0, 3.0001, 6.9999, 7.0, 7.0001, 15.9999, 16.0, 16.0001]:
			points.append(Vector3(box.end.x + distance, box.get_center().y, box.get_center().z))
			points.append(Vector3(box.get_center().x, box.end.y + distance, box.get_center().z))
	gpu_points = points
	var maximum := 0.0
	for w in points:
		var a := _legacy_distance(w, boxes, grid)
		var b := _cached_distance(w, boxes, grid, slices, origin, step)
		maximum = maxf(maximum, absf(a - b))
	_expect(maximum < 0.00001, "楼边/屋顶/街道/候选切换的解析距离误差必须小于1e-5，实际=" + str(maximum))
	# 刻意清空一个楼内单元，必须测出失败而非假绿。
	var detected := false
	for box in clouds.get_procedural_city_exclusion_bounds():
		var point := box.get_center()
		var c := Vector3i(((point - origin) / step).floor())
		if c.y < 0 or c.y >= slices[0].get_height():
			continue
		var saved := slices[c.z].get_pixel(c.x, c.y)
		slices[c.z].set_pixel(c.x, c.y, Color(0, 0, 0, 0))
		detected = _cached_distance(point, boxes, grid, slices, origin, step) - _legacy_distance(point, boxes, grid) > 10.0
		slices[c.z].set_pixel(c.x, c.y, saved)
		if detected:
			break
	_expect(detected, "清空候选的负向对照必须检出距离错误")
	# 线性距离场在楼角处不等价：一个6m二维切片的双线性插值反例。
	var exact_corner := Vector2(3, 3).length()
	var interpolated_corner := (0.0 + 6.0 + 6.0 + Vector2(6, 6).length()) * 0.25
	_expect(absf(interpolated_corner - exact_corner) > 0.8, "楼角线性插值的负向对照必须检出大于0.8m误差")
	report["numeric"] = {"sample_count": points.size(), "max_distance_error_m": maximum, "corrupt_candidate_detected": detected, "linear_corner_negative_error_m": interpolated_corner - exact_corner}

func _decode_gpu_bytes(image: Image) -> PackedByteArray:
	var raw := image.get_data()
	var decoded := PackedByteArray()
	decoded.resize(gpu_points.size() * 4)
	for index in range(gpu_points.size()):
		for byte in range(3):
			decoded[index * 4 + byte] = raw[index * 8 + byte]
		decoded[index * 4 + 3] = raw[index * 8 + 4]
	return decoded

func _validate_gpu_distance() -> void:
	# 从实际Shader抽取原函数，不复制另一套距离实现；RGBA8打包32位float位模式。
	var source := static_shader.code
	var uniforms := ""
	for line: String in source.split("\n"):
		if line.begins_with("uniform ") and not "scene_depth" in line:
			uniforms += line.replace(" : source_color", "") + "\n"
	var function := source.substr(source.find("float building_clearance"), source.find("vec3 field") - source.find("float building_clearance"))
	var shader := Shader.new()
	shader.code = "#define STATIC_CITY_CLEARANCE\nshader_type canvas_item;\nrender_mode unshaded, blend_disabled;\n" + uniforms + "uniform sampler2D sample_points : filter_nearest, repeat_disable;\n" + function + "\nvoid fragment(){ vec3 w=texelFetch(sample_points,ivec2(int(FRAGCOORD.x)/2,int(FRAGCOORD.y)),0).xyz; uint bits=floatBitsToUint(building_clearance(w)); vec3 bytes=vec3(float(bits & 255u),float((bits>>8u)&255u),float((bits>>16u)&255u)); if(int(FRAGCOORD.x)%2==1){bytes=vec3(float((bits>>24u)&255u));} COLOR=vec4(bytes/255.0,1.0); }"
	var size := Vector2i(256, ceili(gpu_points.size() / 256.0))
	var points := Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	for index in range(gpu_points.size()):
		var w := gpu_points[index]
		points.set_pixel(index % size.x, index >> 8, Color(w.x, w.y, w.z, 1.0))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size.x * 2, size.y)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(viewport.size)
	var material := ShaderMaterial.new()
	material.shader = shader
	for item: Dictionary in static_shader.get_shader_uniform_list():
		var name: String = item["name"]
		if not name == "scene_depth":
			material.set_shader_parameter(name, cloud_materials[0].get_shader_parameter(name))
	material.set_shader_parameter("sample_points", ImageTexture.create_from_image(points))
	rect.material = material
	viewport.add_child(rect)
	var captures: Array[PackedByteArray] = []
	for enabled in [false, true]:
		material.set_shader_parameter("procedural_static_enabled", enabled)
		await _warm_frames(30)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		captures.append(_decode_gpu_bytes(image))
		image.save_png(output.path_join("gpu_distance_static.png" if enabled else "gpu_distance_legacy.png"))
	var maximum := 0.0
	var different := 0
	for index in range(gpu_points.size()):
		var a := captures[0].decode_float(index * 4)
		var b := captures[1].decode_float(index * 4)
		_expect(is_finite(a) and is_finite(b) and a >= 0.0 and a <= 16.001, "GPU编码读回必须是有效米制距离")
		maximum = maxf(maximum, absf(a - b))
		if a != b:
			different += 1
	_expect(maximum <= 0.00001, "GPU实际building_clearance误差必须<=1e-5m")
	# 真GPU负向对照：清空全部候选；旧场不动，新增楼中至少一处应检出。
	var corrupt: Array[Image] = clouds.get("_procedural_candidates").get_data()
	for slice in corrupt:
		slice.fill(Color(0, 0, 0, 0))
	var bad := ImageTexture3D.new()
	bad.create(Image.FORMAT_RGBAF, corrupt[0].get_width(), corrupt[0].get_height(), corrupt.size(), false, corrupt)
	material.set_shader_parameter("procedural_candidates", bad)
	await _warm_frames(30)
	await RenderingServer.frame_post_draw
	var negative := viewport.get_texture().get_image()
	negative.convert(Image.FORMAT_RGBA8)
	var data := _decode_gpu_bytes(negative)
	var detected := 0
	var maximum_negative := 0.0
	for index in range(gpu_points.size()):
		maximum_negative = maxf(maximum_negative, absf(data.decode_float(index * 4) - captures[0].decode_float(index * 4)))
		if absf(data.decode_float(index * 4) - captures[0].decode_float(index * 4)) > 0.1:
			detected += 1
	_expect(detected > 0, "GPU损坏候选必须检出，防止编码空图假绿")
	var cached_samples := 0
	var fallback_samples := 0
	var cache_slices: Array[Image] = clouds.get("_procedural_candidates").get_data()
	var cache_origin: Vector3 = clouds.get("_candidate_origin")
	var cache_step: Vector3 = clouds.get("_candidate_step")
	for point in gpu_points:
		var cell := Vector3i(((point - cache_origin) / cache_step).floor())
		if cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < cache_slices[0].get_width() and cell.y < cache_slices[0].get_height() and cell.z < cache_slices.size() and cache_slices[cell.z].get_pixel(cell.x, cell.y).r >= 0:
			cached_samples += 1
		else:
			fallback_samples += 1
	report["gpu_numeric"] = {"samples": gpu_points.size(), "inside_candidate_cache": cached_samples, "fallback_or_outside": fallback_samples, "encoding": "RGBA8 floatBitsToUint无损32位float位模式；整云窗口读回格式另录", "maximum_error_m": maximum, "different_samples": different, "corrupt_detected_samples": detected, "maximum_corrupt_error_m": maximum_negative, "function_from_actual_shader": true}
	viewport.queue_free()
	await get_tree().process_frame

func _validate_invalidation() -> void:
	var layout: Array[Dictionary] = city.get("placements")
	var config: Dictionary = city.get("parameters")
	var key: String = clouds.get_procedural_city_cache_snapshot()["key"]
	clouds.set_procedural_city_layout(layout, config)
	var hit := clouds.get_procedural_city_cache_snapshot()
	_expect(hit["cache_hit"], "完全相同配置应命中进程内缓存")
	var changed: Array[Dictionary] = layout.duplicate(true)
	var transform: Transform3D = changed[0]["transform"]
	transform.origin += Vector3(9, 3, 0)
	changed[0]["transform"] = transform
	clouds.set_procedural_city_layout(changed, config)
	var moved := clouds.get_procedural_city_cache_snapshot()
	_expect(moved["key"] != key and not moved["cache_hit"], "移动楼必须失效重建，禁止用旧场")
	var changed_config := config.duplicate(true)
	changed_config["seed"] = int(config["seed"]) + 1
	clouds.set_procedural_city_layout(layout, changed_config)
	var reseeded := clouds.get_procedural_city_cache_snapshot()
	_expect(reseeded["key"] != key, "完整配置种子变化必须失效")
	clouds.set_procedural_city_layout(layout, config)
	report["invalidation"] = {"original_key": key, "cache_hit": hit, "moved": moved, "config_changed": reseeded, "restored": clouds.get_procedural_city_cache_snapshot()}
	var count_before: String = clouds.get_procedural_city_cache_snapshot()["key"]
	for index in range(20):
		clouds.call("_process", 0.0)
	_expect(clouds.get_procedural_city_cache_snapshot()["key"] == count_before, "动态更新不能重烘缓存")
