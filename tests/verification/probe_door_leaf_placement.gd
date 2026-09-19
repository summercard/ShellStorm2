extends Node
## 门扇在**关卡内实际落位**的画面核对（非 headless，真渲染器）。
##
## 与 probe_door_leaf_visual 的分工（两者不可互相替代）：
##   · probe_door_leaf_visual  只拍资产本身 —— 回答「门扇长什么样、包络对不对」；
##   · 本探针加载真关卡再拍 —— 回答「门扇装进门洞后，位置对不对」。
##
## 为什么必须补这一条：门扇 prefab 以**底边中心**为原点，而 RoomDoor3D 的
## 动画根 DoorPanel 以**门中心**为基准，两者靠一句
## `visual.position.y = -DOOR_CLEAR_HEIGHT_M * 0.5` 对齐。这句话写错
## （漏掉、写成 +、或被后人改掉）不会让任何数值门禁失败：
## 门扇包络仍是对的、门洞仍可通行、节点数也不变 —— 只有一张正对门洞的图
## 能看出「门扇半悬在空中」或「砍进地面一半」。
##
## 机位：站在门洞正前方 5.6m、离地 1.35m（约玩家平视高度）正对门扇中心。
## 这是玩家推门时真实看到的画面，不接管相机、不调关卡状态。
##
## 判据：DOOR_LEAF_PLACEMENT_OK。图落 res://outputs/verification/。

const SCENE_PATH := "res://scenes/ExpeditionLevel99_3D.tscn"
const OUTPUT_DIR := "res://outputs/verification"
const PLACEMENT_PATH := OUTPUT_DIR + "/door_leaf_placement_in_frame.png"

const RUN_SEED := 77199999
## 相机沿门法线方向退开距离（门扇宽 2.2m，5.6m 时纵向恰好装下 2.5m 门洞并留边）。
const CAMERA_BACK_M := 5.6
## 相机离地高度：玩家平视门扇中段，而不是俯视地面。
const CAMERA_HEIGHT_M := 1.35
## 门扇底边到地面的最大允许间隙（美术意图 8mm，留 4mm 容差）。
const MAX_BOTTOM_GAP_M := 0.012
const MIN_LUMA_BUCKETS := 6

var _skipped_headless := 0
var _captured := 0
## 世界包围盒累加器。探针单线程使用，故用成员变量而非临时数组传参
## （GDScript 里通过 Array 传盒子再 `as Variant` 取回会引入不必要的类型体操）。
var _bounds_acc := AABB()
var _bounds_has := false


func _ready() -> void:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		failures.append("测试关卡99 场景加载失败：%s" % SCENE_PATH)
		_report(failures)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()

	# 流送全部房间，让每道门都真的建出来。
	for room_id in (tower._room_by_id as Dictionary).keys():
		tower.force_enter_room_for_test(str(room_id))
		await get_tree().process_frame
	tower.player.set_physics_process(false)
	tower.player.set_process(false)

	var doors := _collect_room_doors(tower)
	if doors.is_empty():
		failures.append("关卡里找不到任何 RoomDoor3D，无法核对门扇落位")
		_report(failures)
		return
	print("[door_placement] doors=%d" % doors.size())

	# —— 数值部分：逐门核对门扇底边贴合地面（几何事实，与出图同源）——
	_verify_placement(doors, failures)

	# —— 渲染部分：取第一道**战斗房**门（即 A 套门扇，非 FACILITY 滑升门）特写 ——
	var subject := _pick_subject(tower, doors, failures)
	if subject == null:
		_report(failures)
		return
	var environment_setting := _install_environment()
	var light := _install_light()
	var camera := _install_camera()
	var door_position := subject.global_position
	var forward := _door_forward(subject)
	var target := door_position + Vector3(0.0, 1.35, 0.0)
	var eye := target + forward * CAMERA_BACK_M
	_aim(camera, Vector3(eye.x, target.y, eye.z), target)
	print(
		"[door_placement] subject=%s at=%s forward=%s eye=%s"
		% [subject.name, str(door_position), str(forward), str(camera.global_position)]
	)
	await _settle()
	_capture(PLACEMENT_PATH, "门扇落位特写采样失败", failures)

	if light != null and is_instance_valid(light):
		light.queue_free()
	if environment_setting != null and is_instance_valid(environment_setting):
		environment_setting.queue_free()
	_report(failures)


## 收集关卡里全部 RoomDoor3D。只认容器类型，不认房间种类 ——
## 安全房/战斗房/BOSS 房的门都要在这一条上成立。
func _collect_room_doors(tower: TowerDescent3D) -> Array[RoomDoor3D]:
	var found: Array[RoomDoor3D] = []
	var seen := {}
	for room_id in (tower._room_by_id as Dictionary).keys():
		var room := (tower._room_by_id as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			continue
		for candidate in _all_doors_in(room):
			var instance_id := candidate.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			found.append(candidate)
	return found


func _all_doors_in(root: Node) -> Array[RoomDoor3D]:
	var found: Array[RoomDoor3D] = []
	if root is RoomDoor3D:
		found.append(root as RoomDoor3D)
	for child in root.get_children():
		found.append_array(_all_doors_in(child))
	return found


## 逐门核对：门扇（ImportedDoorVisual）底边的**世界高度**必须贴合地面。
##
## 为什么用世界坐标而不是局部 position：预制的原点约定是「底边中心」，
## 装配侧靠一句取反的 y 偏移把它对到门中心。只查局部值等于在查那句话本身，
## 而真正会出问题的是「两句话加起来」的结果 —— 必须落到世界高度上验。
func _verify_placement(doors: Array[RoomDoor3D], failures: Array[String]) -> void:
	var checked := 0
	var worst_gap := 0.0
	var worst_label := ""
	for door in doors:
		var visual := door.get_node_or_null("DoorPanel/ImportedDoorVisual") as Node3D
		if visual == null:
			continue
		var bounds := _visual_world_bounds(visual)
		if bounds.size.length() <= 0.001:
			continue
		checked += 1
		var gap := absf(bounds.position.y)
		if gap > worst_gap:
			worst_gap = gap
			worst_label = door.name
		print(
			"[door_placement] %s bottom_y=%.4f size=%s"
			% [door.name, bounds.position.y, str(bounds.size)]
		)
	if checked == 0:
		failures.append("没有任何门带 ImportedDoorVisual（门扇装配路径没生效）")
		return
	if worst_gap > MAX_BOTTOM_GAP_M:
		failures.append(
			"门扇未贴合地面：最差 %.4f（门 %s），允许上限 %.4f —— 门扇会悬空或砍进地面"
			% [worst_gap, worst_label, MAX_BOTTOM_GAP_M]
		)
	print(
		"[door_placement] checked=%d worst_bottom_gap=%.4f (%s)" % [checked, worst_gap, worst_label]
	)


## 把 Node3D 子树里全部可见网格的 AABB 并成**世界空间**包围盒。
func _visual_world_bounds(root: Node3D) -> AABB:
	_bounds_acc = AABB()
	_bounds_has = false
	_accumulate(root)
	if not _bounds_has:
		return AABB()
	return _bounds_acc


func _accumulate(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			var box := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
			_bounds_acc = box if not _bounds_has else _bounds_acc.merge(box)
			_bounds_has = true
	for child in node.get_children():
		_accumulate(child)


## 选一道**战斗房**门当拍摄对象。
##
## 为什么不拍任意一道：FACILITY 与「入口→基地」的门走的是 99F 滑升门
## （BASE99_DOOR_LIFT_PREFAB），是另一套资产；拍错了等于验错了对象。
## 战斗房门才走本次接入的 A 套门扇，故按房间种类排除 FACILITY 后取第一道。
func _pick_subject(
	tower: TowerDescent3D, doors: Array[RoomDoor3D], failures: Array[String]
) -> RoomDoor3D:
	for door in doors:
		var room := _owning_room(tower, door)
		if room == null:
			continue
		if room.room_type == "FACILITY":
			continue
		if door.get_node_or_null("DoorPanel/ImportedDoorVisual") == null:
			continue
		var asset_id := str(door.get_meta("visual_asset_id", ""))
		if asset_id != "ENV-TOWER-DOOR-LEAF-5M":
			# 安全房若仍指到别处会在这里暴露，比在图上肉眼找线索早得多。
			failures.append(
				"战斗房/安全房门扇资产不是 A 套门扇：门 %s asset_id=%s" % [door.name, asset_id]
			)
			continue
		return door
	failures.append("找不到任何带 A 套门扇的战斗房/安全房门，无法采样落位")
	return null


func _owning_room(tower: TowerDescent3D, door: Node) -> DungeonRoom3D:
	for room_id in (tower._room_by_id as Dictionary).keys():
		var room := (tower._room_by_id as Dictionary).get(room_id) as DungeonRoom3D
		if room != null and room.is_ancestor_of(door):
			return room
	return null


## 门法线方向（世界水平方向）：门沿 direction 面向房间外部，用它把相机退到门外。
## forward = 门的本地 +Z 在世界系的水平投影；退化时退回 +Z，避免把机位打到原点。
func _door_forward(door: RoomDoor3D) -> Vector3:
	var basis := door.global_transform.basis
	var forward := basis.z
	forward.y = 0.0
	if forward.length() <= 0.001:
		return Vector3(0.0, 0.0, 1.0)
	return forward.normalized()


func _install_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "DoorPlacementProbeEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.55, 0.62, 0.74)
	sky_material.sky_horizon_color = Color(0.66, 0.70, 0.76)
	sky_material.ground_horizon_color = Color(0.66, 0.70, 0.76)
	sky_material.ground_bottom_color = Color(0.34, 0.36, 0.40)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.15
	world_environment.environment = environment
	add_child(world_environment)
	return world_environment


func _install_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "DoorPlacementProbeSun"
	light.light_energy = 1.6
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-38.0, -120.0, 0.0)
	add_child(light)
	return light


func _install_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "DoorPlacementProbeCamera"
	camera.fov = 64.0
	camera.near = 0.05
	camera.far = 300.0
	# 必须先入树再摆位：look_at 依赖 global_transform。
	add_child(camera)
	camera.make_current()
	return camera


func _aim(camera: Camera3D, from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) <= 0.01:
		return
	camera.global_position = from
	camera.look_at(to, Vector3.UP)


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"DOOR_LEAF_PLACEMENT_OK: in-frame closeup saved under res://outputs/verification/ "
			+ "(captured=%d skipped_headless=%d)" % [_captured, _skipped_headless]
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.24).timeout


func _capture(path: String, failure: String, failures: Array[String]) -> void:
	if DisplayServer.get_name() == "headless":
		_skipped_headless += 1
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append(failure + "（视口纹理为空）")
		return
	var buckets := _luma_buckets(image)
	var mid := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	print(
		"[door_placement] diag %s center_pixel=%s buckets=%d"
		% [path.get_file(), str(mid), buckets]
	)
	if buckets < MIN_LUMA_BUCKETS:
		failures.append("%s（画面只有 %d 层亮度，疑似没渲染出内容）" % [failure, buckets])
		return
	if image.save_png(path) != OK:
		failures.append(failure + "（PNG 写入失败）")
		return
	_captured += 1
	print("[door_placement] saved %s %dx%d" % [path.get_file(), image.get_width(), image.get_height()])


func _luma_buckets(image: Image) -> int:
	var buckets := {}
	var width := image.get_width()
	var height := image.get_height()
	var step_x := maxi(width / 48, 1)
	var step_y := maxi(height / 27, 1)
	for y in range(0, height, step_y):
		for x in range(0, width, step_x):
			var color := image.get_pixel(x, y)
			var luma := int((color.r * 0.299 + color.g * 0.587 + color.b * 0.114) * 16.0)
			buckets[luma] = true
	return buckets.size()
