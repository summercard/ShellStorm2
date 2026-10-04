extends SceneTree

## 只读交接：命令行用 --script 执行；不挂到总场景，不保存任何场景或云资源。
## 编辑器内可 load 本脚本并调用 collect_layout(当前总场景根, config)，读取未保存实例。
## CLI 只读磁盘已保存版本；用户确认五楼区及独立地表摆位前，任何输出均不得应用到云。
const FOLDER := "res://scenes/open_world_layout_edit/"
const SCENE := FOLDER + "open_world_chunk_layout_edit.tscn"
const CONFIG := "res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/city_generation_parameters.json"
const OUTPUT := "res://outputs/open_world_chunk_layout_20261004/chunk_handoff.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var loaded: Array[String] = []
	for index: int in range(5):
		var path: String = FOLDER + "open_world_chunk_%02d.tscn" % (index + 1)
		var chunk_scene: PackedScene = load(path) as PackedScene
		if chunk_scene == null or not chunk_scene.can_instantiate():
			push_error("区块加载失败：" + path)
			quit(1)
			return
		var standalone: Node = chunk_scene.instantiate()
		standalone.free()
		loaded.append(path)
	var ground_path: String = FOLDER + "open_world_ground_500x500.tscn"
	var ground_scene: PackedScene = load(ground_path) as PackedScene
	if ground_scene == null or not ground_scene.can_instantiate():
		push_error("地表加载失败：" + ground_path)
		quit(1)
		return
	var standalone_ground: Node = ground_scene.instantiate()
	standalone_ground.free()
	loaded.append(ground_path)
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		push_error("总场景加载失败。")
		quit(1)
		return
	var layout: Node3D = packed.instantiate() as Node3D
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if layout == null or not parsed is Dictionary:
		if layout != null:
			layout.free()
		push_error("总场景根或城市配置无效。")
		quit(1)
		return
	# 不进场景树，避免触发参照场景脚本；世界变换由完整父链累乘。
	var report: Dictionary = collect_layout(layout, parsed as Dictionary)
	if "--verify-transforms" in OS.get_cmdline_user_args():
		report["transform_regression"] = _verify_transforms(packed, parsed as Dictionary)
		if not bool(report["transform_regression"]["passed"]):
			report["passed"] = false
	layout.free()
	loaded.append(SCENE)
	report["loaded_scenes"] = loaded
	report["capture_mode"] = "已保存TSCN只读快照；未触发场景_ready或正式Autoload"
	report["warning_as_error"] = bool(ProjectSettings.get_setting("debug/gdscript/warnings/treat_warnings_as_errors", false))
	var hashes: Dictionary = {}
	for path: String in loaded + [FOLDER + "open_world_layout_edit.tscn", FOLDER + "open_world_chunk_shared_unit_box.tres", FOLDER + "read_chunk_layout.gd", CONFIG, "res://src/vfx/VfxCloudSea3D.gd", "res://src/vfx/CloudStaticClearance.gdshader"]:
		hashes[path] = FileAccess.get_sha256(path)
	report["source_sha256"] = hashes
	var output_path: String = OS.get_environment("CHUNK_HANDOFF_OUTPUT")
	if output_path.is_empty():
		output_path = OUTPUT
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("交接JSON写入失败，请先确认输出父目录存在：" + output_path)
		quit(2)
		return
	file.store_string((JSON.stringify(report, "  ") + "\n").replace("\n", "\r\n"))
	file.close()
	print("CHUNK_HANDOFF passed=", report["passed"], " chunks=", report["chunk_count"], " ground=", report["ground_count"], " buildings=", report["building_count"], " cloud_applied=false")
	print("ground world_aabb=", report["ground"].get("world_aabb", {}))
	for entry: Dictionary in report["chunks"]:
		print(entry["chunk_id"], " origin=", entry["root_world_transform"]["origin"], " buildings=", entry["building_count"], " world_aabb=", entry["world_aabb"])
	quit(0 if bool(report["passed"]) else 1)

static func collect_layout(layout: Node3D, config: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var chunks: Array[Dictionary] = []
	var cloud_layout: Array[Dictionary] = []
	var ids: Dictionary = {}
	var grid_slots: Dictionary = {}
	var grid_issues: Array[String] = []
	var grid_size: int = int(float(config["extent_m"]) / float(config["spacing_m"]))
	var spacing: float = float(config["spacing_m"])
	var center: Array = config["center_xz"]
	var grid_min: Vector2 = Vector2(float(center[0]), float(center[1])) - Vector2.ONE * float(config["extent_m"]) * 0.5
	var ground_entry: Dictionary = {}
	var ground_count: int = 0
	for child: Node in layout.get_children():
		if child.has_meta("ground_id"):
			ground_count += 1
	var ground_root: Node3D = layout.get_node_or_null("open_world_ground_500x500") as Node3D
	var ground: MeshInstance3D = layout.get_node_or_null("open_world_ground_500x500/ground") as MeshInstance3D
	if ground_count != 1 or ground_root == null or ground == null or ground.mesh == null:
		failures.append("应包含一个独立500x500地表")
	else:
		var ground_world: Transform3D = _world_transform(ground_root)
		if absf(ground_world.basis.determinant()) < 0.000001:
			failures.append("地表根变换不可逆")
		else:
			var ground_local: AABB = ground_world.affine_inverse() * _world_transform(ground) * ground.mesh.get_aabb()
			var ground_box: AABB = _world_transform(ground) * ground.mesh.get_aabb()
			var ground_visibility: AABB = ground_root.get_meta("visibility_bounds", AABB())
			if not _same_box(ground_local, ground_root.get_meta("local_bounds", AABB())) or not _same_box(ground_local, ground_visibility):
				failures.append("地表局部/可见包络与实测不一致")
			if ground.mesh.get_aabb().size.distance_to(Vector3(500, 0.2, 500)) > 0.001:
				failures.append("地表网格应为500x0.2x500米")
			var ground_baseline: Transform3D = ground_root.get_meta("baseline_world_transform", Transform3D.IDENTITY)
			ground_entry = {"ground_id": str(ground_root.get_meta("ground_id")), "scene_path": ground_root.scene_file_path, "root_local_transform": _transform(ground_root.transform), "root_world_transform": _transform(ground_world), "changed_from_baseline": not ground_world.is_equal_approx(ground_baseline), "world_aabb": _box(ground_box), "measured_bounds_local": _box(ground_local), "visibility_bounds_local": _box(ground_visibility), "visibility_bounds_world": _box(ground_world * ground_visibility), "baseline_world_bounds": _box(ground_root.get_meta("world_bounds", AABB())), "root_visible": ground_root.visible}
	for child: Node in layout.get_children():
		if not child is Node3D or not child.has_meta("chunk_id"):
			continue
		var chunk: Node3D = child as Node3D
		var label: String = str(chunk.get_meta("chunk_id"))
		var buildings: Node = chunk.get_node_or_null("buildings")
		if chunk.get_node_or_null("ground") != null:
			failures.append(label + " 不应包含地表节点")
		if buildings == null:
			failures.append(label + " 缺少楼栋容器")
			continue
		var world: Transform3D = _world_transform(chunk)
		if absf(world.basis.determinant()) < 0.000001:
			failures.append(label + " 根变换不可逆")
			continue
		var measured_world: AABB = AABB()
		var measured_local: AABB = AABB()
		var bounds_found: bool = false
		var declared: AABB = chunk.get_meta("visibility_bounds", AABB())
		var entries: Array[Dictionary] = []
		var source_cells: Array[Vector2i] = []
		var current_cells: Array[Vector2i] = []
		for node: Node in buildings.get_children():
			var building: MeshInstance3D = node as MeshInstance3D
			if building == null or building.mesh == null:
				failures.append(label + " 存在非网格楼栋")
				continue
			var building_id: int = int(building.get_meta("source_building_index", -1))
			var source_grid: Vector2i = building.get_meta("source_grid", Vector2i(-1, -1))
			if building_id < 0 or ids.has(building_id) or source_grid.x < 0 or source_grid.y < 0:
				failures.append(label + " 楼栋ID或来源网格无效/重复")
			ids[building_id] = true
			var transform: Transform3D = _world_transform(building)
			var mesh_box: AABB = building.mesh.get_aabb()
			if not _same_box(mesh_box, AABB(Vector3.ONE * -0.5, Vector3.ONE)):
				failures.append(label + " 云接口需要单位BoxMesh，当前楼栋网格不符合")
			var box: AABB = transform * mesh_box
			var local_box: AABB = world.affine_inverse() * transform * mesh_box
			measured_world = measured_world.merge(box) if bounds_found else box
			measured_local = measured_local.merge(local_box) if bounds_found else local_box
			bounds_found = true
			var cell: Vector2i = Vector2i(floori((transform.origin.x - grid_min.x) / spacing), floori((transform.origin.z - grid_min.y) / spacing))
			var key: String = "%d,%d" % [cell.x, cell.y]
			if cell.x < 0 or cell.y < 0 or cell.x >= grid_size or cell.y >= grid_size:
				grid_issues.append("楼%d 超出现有云网格：%s" % [building_id, key])
			if grid_slots.has(key):
				grid_issues.append("楼%d 与楼%d 同格：%s；接口每格只保留一栋" % [building_id, int(grid_slots[key]), key])
			grid_slots[key] = building_id
			# 保守充分条件：含1.5m净距的足迹在本格内，3×3邻域外楼距至少25m。
			var cell_rect: Rect2 = Rect2(grid_min + Vector2(cell.x, cell.y) * spacing, Vector2.ONE * spacing).grow(0.0001)
			var clearance: AABB = box.grow(1.5)
			if not cell_rect.encloses(Rect2(clearance.position.x, clearance.position.z, clearance.size.x, clearance.size.z)):
				grid_issues.append("楼%d 扩张足迹越格，现有邻格查询需后续审查" % building_id)
			source_cells.append(source_grid)
			current_cells.append(cell)
			var placement: Dictionary = {"building_id": building_id, "chunk_id": label, "grid_x": cell.x, "grid_z": cell.y, "transform": _transform(transform), "world_aabb": _box(box)}
			cloud_layout.append(placement)
			entries.append({"node_path": str(layout.get_path_to(building)), "source_building_index": building_id, "source_grid": [source_grid.x, source_grid.y], "current_grid": [cell.x, cell.y], "local_transform": _transform(building.transform), "chunk_local_transform": _transform(world.affine_inverse() * transform), "world_transform": _transform(transform), "world_aabb": _box(box)})
		if not bounds_found or not _same_box(declared, measured_local) or not _same_box(chunk.get_meta("local_bounds", AABB()), measured_local):
			failures.append(label + " local/visibility_bounds 与楼群实测网格并集不一致")
		if entries.size() != int(chunk.get_meta("building_count", -1)):
			failures.append(label + " 楼数元数据不一致")
		if not chunk.has_meta("cloud_handoff") or not chunk.has_meta("visibility_control"):
			failures.append(label + " 缺少交接/可见性说明")
		var baseline: Transform3D = chunk.get_meta("baseline_world_transform", Transform3D.IDENTITY)
		chunks.append({"chunk_id": label, "scene_path": chunk.scene_file_path, "root_local_transform": _transform(chunk.transform), "root_world_transform": _transform(world), "changed_from_baseline": not world.is_equal_approx(baseline), "world_aabb": _box(measured_world), "local_bounds": _box(chunk.get_meta("local_bounds", AABB())), "baseline_world_bounds": _box(chunk.get_meta("world_bounds", AABB())), "visibility_bounds_local": _box(declared), "visibility_bounds_world": _box(world * declared), "measured_bounds_local": _box(measured_local), "building_count": entries.size(), "source_grid_range": _grid_range(source_cells), "current_grid_range": _grid_range(current_cells), "root_visible": chunk.visible, "visibility_control": str(chunk.get_meta("visibility_control", "")), "cloud_handoff": str(chunk.get_meta("cloud_handoff", "")), "buildings": entries})
	if chunks.size() != 5 or ids.size() != 200:
		failures.append("应读取五个区块及200栋楼")
	return {
		"schema": "shellstorm2.chunk_handoff.v2", "scene": SCENE,
		"snapshot_notice": "仅代表采集时刻；任何父级/区块/楼栋重摆或场景重存后需重新采集。来源网格不是移动后的世界网格。",
		"coordinate_space": "Godot世界坐标，米；basis_x/y/z是基矩阵列向量，不是欧拉角",
		"chunk_count": chunks.size(), "ground_count": ground_count, "ground": ground_entry, "building_count": ids.size(), "chunks": chunks,
		"passed": failures.is_empty(), "failures": failures,
		"user_layout_confirmed": false, "cloud_apply_allowed": false,
		"formal_scene_modified": false, "cloud_modified": false, "runtime_culling_added": false,
		"visibility_contract": {"bounds": "根metadata.visibility_bounds为根局部AABB，随实际完整世界变换转换；世界AABB是保守包络", "control": "Node3D.visible / show() / hide()控制整块后代，仅视觉，不停脚本、物理或玩法", "future_culling": "仅预留说明：后续单独授权实现相机视锥与世界AABB测试；metadata本身不会自动剔除，不创建Notifier或每帧逻辑"},
		"cloud_handoff": {
			"interface": "VfxCloudSea3D.set_procedural_city_layout(layout: Array[Dictionary], config: Dictionary)",
			"config_source": CONFIG, "config_reference_only": config.duplicate(true), "layout_candidate": cloud_layout,
			"candidate_grid_compatible": grid_issues.is_empty(), "candidate_grid_issues": grid_issues,
			"transform_decode": "Transform3D(Basis(Vector3(basis_x), Vector3(basis_y), Vector3(basis_z)), Vector3(origin))；数组先逐分量转Vector3",
			"next_step": "用户确认五楼区与独立地表最终摆位后重新采集；审查或重建世界网格config并保证每格一栋及邻域覆盖，再另行授权应用。不得用区块/地表大AABB替代逐楼避让，不把隐藏楼从云layout移除。云体边缘本轮不调整。"
		}
	}

static func _verify_transforms(packed: PackedScene, config: Dictionary) -> Dictionary:
	# 仅变动另一个未入树的测试实例，不改采集实例，更不保存TSCN。
	var parent: Node3D = Node3D.new()
	parent.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.4, 0.0)), Vector3(40, 3, -20))
	var sample: Node3D = packed.instantiate() as Node3D
	parent.add_child(sample)
	sample.position = Vector3(5, 2, -8)
	var chunk: Node3D = sample.get_node("open_world_chunk_01") as Node3D
	chunk.transform = Transform3D(Basis.from_euler(Vector3(0.2, -0.6, 0.1)).scaled(Vector3(1.2, 0.8, 1.1)), chunk.position + Vector3(7, 4, -9))
	chunk.visible = false
	var ground_root: Node3D = sample.get_node("open_world_ground_500x500") as Node3D
	var ground: MeshInstance3D = ground_root.get_node("ground") as MeshInstance3D
	var ground_before: Transform3D = _world_transform(ground)
	chunk.position += Vector3(2, 0, 3)
	var ground_independent: bool = ground_before.is_equal_approx(_world_transform(ground))
	ground_root.position += Vector3(-4, 2, 6)
	var ground_expected: Transform3D = parent.transform * sample.transform * ground_root.transform * ground.transform
	var building: MeshInstance3D = chunk.get_node("buildings").get_child(0) as MeshInstance3D
	var container: Node3D = building.get_parent() as Node3D
	var expected: Transform3D = parent.transform * sample.transform * chunk.transform * container.transform * building.transform
	var expected_box: AABB = AABB(expected * building.mesh.get_aabb().get_endpoint(0), Vector3.ZERO)
	for index: int in range(1, 8):
		expected_box = expected_box.expand(expected * building.mesh.get_aabb().get_endpoint(index))
	var capture: Dictionary = collect_layout(sample, config)
	var first: Dictionary = capture["chunks"][0]["buildings"][0]
	var values: Dictionary = first["world_transform"]
	var encoded: Transform3D = Transform3D(Basis(_decode_vector(values["basis_x"]), _decode_vector(values["basis_y"]), _decode_vector(values["basis_z"])), _decode_vector(values["origin"]))
	var box_values: Dictionary = first["world_aabb"]
	var encoded_box: AABB = AABB(_decode_vector(box_values["position"]), _decode_vector(box_values["size"]))
	var ground_values: Dictionary = capture["ground"]["world_aabb"]
	var ground_encoded: AABB = AABB(_decode_vector(ground_values["position"]), _decode_vector(ground_values["size"]))
	var ok: bool = bool(capture["passed"]) and expected.is_equal_approx(encoded) and _same_box(expected_box, encoded_box) and int(capture["building_count"]) == 200 and int(capture["ground_count"]) == 1 and ground_independent and _same_box(ground_expected * ground.mesh.get_aabb(), ground_encoded) and not bool(capture["cloud_apply_allowed"])
	parent.free()
	return {"passed": ok, "tested": "独立测试实例：非identity祖先、父级偏移、区块平移/旋转/非等比缩放、隐藏仍保留200栋、八角点独立AABB核对；移动楼区不带动地表，独立地表移动与完整父链AABB核对", "source_modified": false}

static func _decode_vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func _world_transform(node: Node3D) -> Transform3D:
	if node.is_inside_tree():
		return node.global_transform
	if node.is_set_as_top_level():
		return node.transform
	var parent: Node = node.get_parent()
	while parent != null and not parent is Node3D:
		parent = parent.get_parent()
	return _world_transform(parent as Node3D) * node.transform if parent != null else node.transform

static func _same_box(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < 0.001 and a.size.distance_to(b.size) < 0.001

static func _grid_range(cells: Array[Vector2i]) -> Dictionary:
	if cells.is_empty():
		return {}
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = low.min(cell)
		high = high.max(cell)
	return {"min_inclusive": [low.x, low.y], "max_inclusive": [high.x, high.y]}

static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _vector(value.origin), "basis_x": _vector(value.basis.x), "basis_y": _vector(value.basis.y), "basis_z": _vector(value.basis.z)}

static func _box(value: AABB) -> Dictionary:
	return {"position": _vector(value.position), "size": _vector(value.size), "end": _vector(value.end)}
