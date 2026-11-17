extends Node3D
## 独立真运行入口；runner 必须在启动 Godot（含 Autoload）前隔离用户目录。
const FORMAL := "res://assets/art/enemies/normal_enemy_3d/fat_zombie21/runtime/enm_normal_fat_zombie21_root_top3d.tscn"
const BASELINE := "res://baseline/enm_normal_fat_zombie21_root_top3d.tscn"
const PRELOCK := "res://prelock/enm_normal_fat_zombie21_root_top3d.tscn"
var output := "user://"
var results: Dictionary = {"checks": [], "cases": [], "mapping": [], "limitations": []}
var failures := 0
var references: Dictionary
var capture := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		if arg == "--render":
			capture = true
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	results.checks.append({"name": label, "pass": passed, "detail": detail})
	if not passed:
		failures += 1
		print("FAIL ", label, " ", detail)

func rig(path: String, multiplier := 1.0) -> Dictionary:
	var body := CharacterBody3D.new()
	body.scale = Vector3.ONE * 0.7 * multiplier
	add_child(body)
	var visual := (load(path) as PackedScene).instantiate() as Node3D
	body.add_child(visual)
	visual.set_process(false)
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		for n in visual.find_children("*", "Skeleton3D", true, false):
			skeleton = n
	var meshes: Array = []
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		if n.skin != null:
			meshes.append(n)
	return {"body": body, "visual": visual, "skeleton": skeleton, "meshes": meshes, "points": []}

func sync(r: Dictionary, state: String, t: float, speed: float) -> Dictionary:
	r.visual.sync_state(state, t, speed, 1.2, 1.3, 0.51)
	r.skeleton.force_update_all_bone_transforms()
	return r.visual.get_presentation_snapshot()

func skin_point(r: Dictionary, point: Dictionary) -> Vector3:
	var mesh: MeshInstance3D = point.mesh
	var skeleton: Skeleton3D = r.skeleton
	var local := Vector3.ZERO
	for k in point.weights.size():
		var weight: float = point.weights[k]
		if weight <= 0.0:
			continue
		var bind: int = point.bones[k]
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		local += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * point.rest) * weight
	return skeleton.global_transform * local

func map_contacts(r: Dictionary) -> void:
	sync(r, "idle", 0.0, 0.0)
	var all: Array = []
	for mesh in r.meshes:
		for s in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var count := weights.size() / verts.size()
			for i in verts.size():
				var p := {"mesh": mesh, "surface": s, "index": i, "rest": verts[i], "bones": [], "weights": []}
				for k in int(count):
					p.bones.append(bones[i * int(count) + k])
					p.weights.append(weights[i * int(count) + k])
				all.append(p)
	var glb: Node3D = r.visual.get_node("VisualGLB")
	var max_error := 0.0
	var mapping: Array = []
	for group in references:
		for source_id in references[group]:
			var xyz: Array = references[group][source_id]
			var target := Vector3(float(xyz[0]), float(xyz[2]), -float(xyz[1]))
			var nearest: Dictionary = {}
			var error := INF
			for p in all:
				var d := glb.to_local(skin_point(r, p)).distance_to(target)
				if d < error:
					error = d
					nearest = p
			nearest = nearest.duplicate()
			nearest["group"] = group
			nearest["source_vertex"] = int(source_id)
			r.points.append(nearest)
			mapping.append({"source_vertex": int(source_id), "group": group, "surface": nearest.surface, "godot_vertex": nearest.index, "reference_error_source_m": error})
			max_error = maxf(max_error, error)
	results.mapping.append({"points": r.points.size(), "godot_uv_split_vertices": all.size(), "max_reference_error_source_m": max_error, "source_to_godot": mapping})
	check("48点源idle坐标映射GLB实际蒙皮", r.points.size() == 48 and max_error < 0.0001, max_error)

func measure_case(label: String, state: String, speed: float, multiplier := 1.0, old := false, variable := false, turning := false, path_override := "") -> void:
	var r := rig(path_override if not path_override.is_empty() else (BASELINE if old else FORMAL), multiplier)
	map_contacts(r)
	var stride := (0.6 if state == "patrol" else 0.72) * multiplier
	var duration := (3.0 if variable else 2.15) * stride / speed
	var steps := int(ceil(duration * 120.0))
	var dt := duration / steps
	var previous: Dictionary = {}
	var windows: Dictionary = {}
	var maximum := 0.0
	var per_contact := {}
	var travelled := 0.0
	var unwrapped := 0.0
	var previous_phase := 0.0
	var total_samples := 0
	sync(r, state, 0.0, speed)
	for i in range(steps + 1):
		var t := i * dt
		var v := speed
		if variable:
			v *= 0.0 if i > steps / 3 and i < steps / 2 else (0.2 + 1.6 * float(i) / steps)
		if i > 0:
			var direction := Vector3.FORWARD
			if turning:
				r.body.rotation.y = sin(float(i) / steps * TAU) * 0.35
				direction = -r.body.basis.z.normalized()
			r.body.global_position += direction * v * dt
			travelled += v * dt
		var snap := sync(r, state, t, v)
		var clip: String = snap.clip
		if clip not in ["walking", "running"]:
			continue
		var player := r.visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var phase := float(snap.sample_time) / player.get_animation(clip).length
		var step_phase := phase - previous_phase
		if step_phase < -0.5:
			step_phase += 1.0
		unwrapped += step_phase
		previous_phase = phase
		var duty := 0.60 if clip == "walking" else 0.61
		for p in r.points:
			var group: String = p.group
			var offset := 0.5 if group in ["Rfoot", "Lhand"] else 0.0
			var active := fposmod(phase + offset, 1.0) < duty
			var key := str(p.source_vertex)
			if not active:
				previous.erase(key)
				windows.erase(key)
				continue
			var world := skin_point(r, p)
			if not previous.has(key):
				previous[key] = world
				windows[key] = []
			var drift := 0.0
			for earlier in windows[key]:
				drift = maxf(drift, world.distance_to(earlier))
			windows[key].append(world)
			maximum = maxf(maximum, drift)
			per_contact[group] = maxf(float(per_contact.get(group, 0.0)), drift)
			total_samples += 1
	var record := {"name": label, "baseline": old, "speed_mps": speed, "scale_multiplier": multiplier, "cycles": unwrapped, "travel_m": travelled, "samples": total_samples, "max_pairwise_contact_drift_m": maximum, "per_contact_m": per_contact, "variable_speed": variable, "turning": turning}
	results.cases.append(record)
	if not old:
		check(label + "接触点漂移<=1cm", maximum <= 0.01, record)
		if not variable:
			check(label + "覆盖两循环与接缝", unwrapped >= 2.0, unwrapped)
	print(JSON.stringify(record))
	r.body.free()

func boundary_checks() -> void:
	var pool := (load("res://src/vfx/VfxPool3D.gd") as GDScript).new() as Node3D
	add_child(pool)
	var r := rig(FORMAL)
	var s := sync(r, "patrol", 0.0, 0.255)
	r.body.global_position.z -= 0.03
	s = sync(r, "patrol", 0.1, 0.255)
	check("起步立即distance gait不被move_start覆盖", s.clip == "walking" and float(s.sample_time) > 0.0, s)
	var phase: float = s.gait_phase
	for i in 60:
		s = sync(r, "patrol", 4.0 + i, 9.0)
	check("堵墙/刹停/重复sync无位移不推进", absf(float(s.gait_phase) - phase) < 0.000001, s)
	for state in ["chase", "search", "return", "patrol"]:
		s = sync(r, state, 0.0, 0.51)
		check("切换" + state + "相位连续", absf(float(s.gait_phase) - phase) < 0.000001, s)
	r.body.position.z -= 20.0
	s = sync(r, "chase", 0.1, 0.51)
	check("瞬移不累计", absf(float(s.gait_phase) - phase) < 0.000001, s)
	for i in 20:
		r.visual.sync_death_warning(i * 0.02, 1.0)
		sync(r, "death_warning", i * 0.02, 0.0)
	s = sync(r, "chase", 0.0, 0.51)
	check("死亡颤抖不制造distance", absf(float(s.gait_phase) - phase) < 0.000001, s)
	remove_child(r.body)
	r.body.position.z -= 20.0
	add_child(r.body)
	s = sync(r, "chase", 0.0, 0.51)
	check("离树重入锚点重置", absf(float(s.gait_phase) - phase) < 0.000001, s)
	var material: StandardMaterial3D = r.meshes[0].get_active_material(0)
	var color := material.albedo_color
	var emission := material.emission_energy_multiplier
	r.visual.flash_hit()
	check("flash峰值保留", float(r.visual.get_presentation_snapshot().flash_time) > 0.0)
	r.visual._process(0.2)
	check("flash恢复不改albedo", material.albedo_color == color and absf(material.emission_energy_multiplier - emission) < 0.00001)
	var count: int = s.slam_fx_count
	s = sync(r, "telegraph", 0.0, 0.0)
	s = sync(r, "telegraph", 0.6, 0.0)
	check("攻击0.6秒映射F39", absf(float(s.source_attack_frame) - 39.0) < 0.001 and int(s.slam_fx_count) == count, s)
	s = sync(r, "telegraph", 1.2, 0.0)
	check("玩法1.2秒映射源F78", absf(float(s.source_attack_frame) - 78.0) < 0.001 and int(s.slam_fx_count) == count, s)
	for i in 5:
		s = sync(r, "attack", 0.0, 0.0)
		s = sync(r, "recovery", i * 0.1, 0.0)
	check("attack/recovery重复调用VFX恰好一次", int(s.slam_fx_count) == count + 1, s)
	check("正式VFX池真实借出一次", pool.active_count("VFX-FAT-ZOMBIE-SLAM-3D") == 1, pool.active_count("VFX-FAT-ZOMBIE-SLAM-3D"))
	r.visual.sync_death_warning(0.5, 1.0)
	check("死亡预警能量保留", material.emission_energy_multiplier > emission)
	sync(r, "idle", 0.0, 0.0)
	check("退出死亡预警恢复材质", material.albedo_color == color and absf(material.emission_energy_multiplier - emission) < 0.00001)
	r.body.free()
	pool.free()

func collision_and_transition_checks() -> void:
	var r := rig(FORMAL)
	map_contacts(r)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.0
	collider.shape = capsule
	r.body.add_child(collider)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position.z = -1.0
	add_child(wall)
	await get_tree().physics_frame
	sync(r, "chase", 0.0, 0.51)
	var blocked_phase := -1.0
	var collisions := 0
	for i in 150:
		var hit: KinematicCollision3D = r.body.move_and_collide(Vector3(0, 0, -0.02))
		if hit != null:
			collisions += 1
		var s := sync(r, "chase", i / 60.0, 0.51)
		if i == 100:
			blocked_phase = float(s.gait_phase)
		if i == 149:
			check("真实物理墙阻挡后不空走", collisions > 50 and absf(float(s.gait_phase) - blocked_phase) < 0.00001, {"collisions": collisions, "phase": s.gait_phase, "blocked_phase": blocked_phase})
	var before: Array = []
	for p in r.points:
		before.append(skin_point(r, p))
	var s := sync(r, "patrol", 0.0, 0.255)
	var jump := 0.0
	for i in r.points.size():
		jump = maxf(jump, before[i].distance_to(skin_point(r, r.points[i])))
	results["transition_pose_jump_m"] = jump
	check("堵墙后走跑切换实际48点跳变<=1cm", jump <= 0.01, jump)
	r.body.free()
	wall.free()

func transition_checks(path: String, old := false) -> void:
	var records: Array = []
	for multiplier in [1.0, 1.5]:
		for start in ["patrol", "chase"]:
			for target_phase in [0.0, 0.05, 0.105, 0.25, 0.50, 0.55, 0.605, 0.75, 0.958]:
				var r := rig(path, multiplier)
				map_contacts(r)
				var stride: float = (0.6 if start == "patrol" else 0.72) * multiplier
				sync(r, start, 0.0, 0.51)
				var steps := int(ceil((1.0 + target_phase) * 150.0))
				for k in steps:
					r.body.position += Vector3.FORWARD * stride * (1.0 + target_phase) / steps
					r.body.rotation.y = 0.15 * sin(float(k) / steps * TAU)
					sync(r, start, k / 120.0, 0.51)
				var before: Array = []
				for p in r.points:
					before.append(skin_point(r, p))
				var target := "chase" if start == "patrol" else "patrol"
				var snap := sync(r, target, 0.0, 0.51)
				var support := 0.0
				var swing := 0.0
				var common := 0
				for i in r.points.size():
					var p: Dictionary = r.points[i]
					var offset := 0.5 if p.group in ["Rfoot", "Lhand"] else 0.0
					var lp := fposmod(float(snap.gait_phase) + offset, 1.0)
					var d: float = before[i].distance_to(skin_point(r, p))
					if lp < 0.60:
						support = maxf(support, d)
						common += 1
					else:
						swing = maxf(swing, d)
				var max_scale_error := 0.0
				for b in r.skeleton.get_bone_count():
					max_scale_error = maxf(max_scale_error, (r.skeleton.get_bone_pose_scale(b) - Vector3.ONE).length())
				var record := {"baseline": old, "from": start, "to": target, "phase": snap.gait_phase, "multiplier": multiplier, "common_support_points": common, "support_jump_m": support, "swing_jump_m": swing, "bone_scale_error": max_scale_error}
				records.append(record)
				if not old:
					check("双向走跑同相位实际支撑点<=1cm", support <= 0.01, record)
					check("切换瞬间摆动点短混合连续", swing <= 0.01, record)
					check("骨pose缩放保持1", max_scale_error < 0.00001, record)
				# 切换后继续运动，所有自然支撑窗口按全pairwise测量，不能只验证切换一帧。
				var windows: Dictionary = {}
				var max_drift := 0.0
				var next_stride: float = (0.72 if target == "chase" else 0.6) * multiplier
				for k in 330:
					if k > 0:
						r.body.rotation.y = sin(k / 329.0 * TAU) * 0.35
						r.body.global_position += -r.body.basis.z.normalized() * next_stride / 150.0
					snap = sync(r, target, k / 120.0, 0.51)
					var duty := 0.61 if target == "chase" else 0.60
					for p in r.points:
						var offset := 0.5 if p.group in ["Rfoot", "Lhand"] else 0.0
						var key := str(p.source_vertex)
						if fposmod(float(snap.gait_phase) + offset, 1.0) >= duty:
							windows.erase(key)
							continue
						var world := skin_point(r, p)
						if not windows.has(key):
							windows[key] = []
						for earlier in windows[key]:
							max_drift = maxf(max_drift, world.distance_to(earlier))
						windows[key].append(world)
				record["post_switch_pairwise_drift_m"] = max_drift
				if not old:
					check("切换后转弯2.19循环支撑<=1cm", max_drift <= 0.01, record)
				r.body.free()
	results["prelock_transitions" if old else "contact_lock_transitions"] = records

func contact_boundary_checks() -> void:
	var r := rig(FORMAL)
	map_contacts(r)
	sync(r, "chase", 0.0, 0.51)
	r.body.position.z -= 0.72 * 0.55
	var a := sync(r, "chase", 0.1, 0.51)
	var segment: int = a.contact_segments.Lfoot.segment
	r.body.position.z -= 0.72 * 1.01
	var b := sync(r, "chase", 1.0, 0.51)
	check("大帧跨整周期重锚非沿用旧支撑", int(b.contact_segments.Lfoot.segment) != segment, b.gait_phase)
	var rest_before: Array = []
	for bone in r.skeleton.get_bone_count():
		rest_before.append(r.skeleton.get_bone_rest(bone))
	r.body.velocity.y = 1.0
	var airborne := sync(r, "chase", 0.0, 0.51)
	check("垂直离地清锚", airborne.contact_lock.is_empty(), airborne.contact_lock)
	r.body.velocity.y = 0.0
	sync(r, "chase", 0.0, 0.51)
	for state in ["telegraph", "attack", "recovery", "idle", "dead", "death_warning"]:
		sync(r, "chase", 0.0, 0.51)
		var snap := sync(r, state, 0.0, 0.0)
		check("非移动清锚" + state, snap.contact_lock.is_empty(), snap.contact_lock)
	var rest_equal := true
	for bone in r.skeleton.get_bone_count():
		rest_equal = rest_equal and r.skeleton.get_bone_rest(bone) == rest_before[bone]
	check("原41骨rest未修改", rest_equal and r.skeleton.get_bone_count() == 41)
	if ResourceLoader.exists(PRELOCK):
		var original := rig(PRELOCK)
		for item in [["telegraph", 0.6], ["telegraph", 1.2], ["attack", 0.0], ["recovery", 0.4]]:
			sync(r, item[0], item[1], 0.0)
			sync(original, item[0], item[1], 0.0)
			var error := 0.0
			for bone in r.skeleton.get_bone_count():
				var a_pose: Transform3D = r.skeleton.get_bone_pose(bone)
				var b_pose: Transform3D = original.skeleton.get_bone_pose(bone)
				error = maxf(error, a_pose.origin.distance_to(b_pose.origin))
				for axis in 3:
					error = maxf(error, a_pose.basis[axis].distance_to(b_pose.basis[axis]))
			check("攻击源骨曲线保持" + str(item), error < 0.00001, error)
		original.body.free()
	r.body.free()

func stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.055, 0.065, 0.09)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.87, 1.0)
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	add_child(light)
	for x in range(-6, 7):
		for z in range(-15, 5):
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.493, 0.025, 0.493)
			tile.mesh = box
			tile.position = Vector3(x * 0.5, -0.016, z * 0.5)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.27, 0.30, 0.34) if (x + z) % 2 == 0 else Color(0.39, 0.42, 0.46)
			m.roughness = 0.9
			tile.material_override = m
			add_child(tile)

func render_evidence() -> void:
	stage()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	camera.current = true
	add_child(camera)
	var label := Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 22)
	add_child(label)
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	for mode in ["before_turning", "after_turning", "before_transition", "after_transition"]:
		var state := "chase" if mode.ends_with("turning") else "patrol"
		var r := rig(PRELOCK if mode.begins_with("before") else FORMAL)
		map_contacts(r)
		var speed := 0.51
		var seconds := 2.15 * 0.72 / speed if mode.ends_with("turning") else 6.0
		var markers: Array = []
		for p in r.points:
			var marker := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.009
			sphere.height = 0.018
			marker.mesh = sphere
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(0.1, 1.0, 0.35)
			marker.material_override = material
			add_child(marker)
			markers.append(marker)
		var frames := int(ceil(seconds * 30))
		var dt := seconds / frames
		sync(r, state, 0.0, speed)
		for i in range(frames + 1):
			var actual_speed := speed
			var t := i * dt
			if mode.ends_with("transition"):
				state = "patrol" if t < 1.4 or t >= 4.0 else "chase"
				actual_speed = 0.255 if state == "patrol" else 0.51
			if i > 0:
				r.body.rotation.y = sin(float(i) / frames * TAU) * 0.35 if mode.ends_with("turning") else 0.0
				r.body.global_position += -r.body.basis.z.normalized() * actual_speed * dt
			var s := sync(r, state, t, actual_speed)
			var duty := 0.60 if state == "patrol" else 0.61
			for j in r.points.size():
				var p: Dictionary = r.points[j]
				var offset := 0.5 if p.group in ["Rfoot", "Lhand"] else 0.0
				markers[j].position = skin_point(r, p)
				markers[j].visible = fposmod(float(s.gait_phase) + offset, 1.0) < duty
			var center: Vector3 = r.body.global_position + Vector3(0, 0.85, 0)
			camera.position = center + Vector3(3.8, 2.3, 3.6)
			camera.look_at(center)
			label.text = "%s | %s %.3f m/s | phase %.3f\nForward+ / Vulkan | green = actual skinned support points" % [mode, state, actual_speed, float(s.gait_phase)]
			await RenderingServer.frame_post_draw
			var rc := get_viewport().get_texture().get_image().save_png(output.path_join("frames/%s_%04d.png" % [mode, i]))
			check("渲染帧写入", rc == OK, rc)
			await get_tree().process_frame
		for marker in markers:
			marker.free()
		r.body.free()
	results["renderer"] = RenderingServer.get_current_rendering_method()
	results["adapter"] = RenderingServer.get_video_adapter_name()
	check("真实Forward+渲染器", RenderingServer.get_current_rendering_method() == "forward_plus")

func _run() -> void:
	var reference_path := "res://contacts.json"
	if not FileAccess.file_exists(reference_path):
		push_error("请用工程外runner提供原48点reference坐标并隔离APPDATA/LOCALAPPDATA")
		get_tree().quit(2)
		return
	references = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	if capture:
		await render_evidence()
	else:
		for item in [["巡逻", "patrol", 0.255], ["追击", "chase", 0.51], ["人工光追击", "chase", 0.204], ["人工光巡逻", "patrol", 0.102], ["关卡覆盖", "chase", 1.5]]:
			measure_case(item[0], item[1], item[2])
		measure_case("强化1.5体型", "chase", 0.51, 1.5)
		measure_case("加速刹停", "chase", 0.51, 1.0, false, true)
		if ResourceLoader.exists(BASELINE):
			measure_case("v006旧脚本巡逻", "patrol", 0.255, 1.0, true)
			measure_case("v006旧脚本追击", "chase", 0.51, 1.0, true)
		measure_case("转弯严格验收", "chase", 0.51, 1.0, false, false, true)
		measure_case("巡逻转弯严格验收", "patrol", 0.255, 1.0, false, false, true)
		measure_case("强化转弯严格验收", "chase", 0.51, 1.5, false, false, true)
		if ResourceLoader.exists(PRELOCK):
			measure_case("v007锁锚前转弯", "chase", 0.51, 1.0, true, false, true, PRELOCK)
			transition_checks(PRELOCK, true)
		transition_checks(FORMAL)
		contact_boundary_checks()
		boundary_checks()
		await collision_and_transition_checks()
	results["limitations"].append("支撑为自然duty区间世界刚体锚定，不是等长IK；摆动采用源clip，走跑切换0.08phase混合及离地0.12phase纠偏消退，不承诺全身速度/加速度连续或极端转身无拉伸。")
	results["failures"] = failures
	var f := FileAccess.open(output.path_join("render.json" if capture else "verification.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print("FAT_ZOMBIE21_GAIT_RESULT failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
