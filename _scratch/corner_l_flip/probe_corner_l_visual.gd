extends Node
## A 套 L 墙角（ENV-TOWER-CORNER-L-5M）的**画面**核对（非 headless，真渲染器）。
##
## 为什么逻辑门禁不够：L 角已有数值覆盖 —— verify_tower_module_prefabs 的 8 项
## prefab 契约（恒等 TRS / 包络 / 原点约定 / 材质角色）与
## verify_door_passability / verify_common_wall_door_components_v004 的房间装配回归。
## 但都答不了「拼出来到底像不像两面墙」：两臂装反、装饰面朝内、转角错开半米、
## 或者干脆退化成空白块 —— 在数值断言里全都合法。只有真渲染一张图才看得出来。
##
## 本件的形状契约（探针独立复算，不读 prefab metadata，以免自证）：
##   · 原点在**转角**（bottom_corner），两臂向 +X 与 -Z 伸出，底面 Y=0；
##   · 可视包络 = 5.15 × 11.9 × 5.3175，最小角 (-0.15, 0, -5.0)；
##   · 两条臂的装饰面朝外：长臂 +Z、短臂 +X；
##   · 两个碰撞体必须还在，且名字是 WallCollisionLong / WallCollisionShort
##     （DungeonRoom3D 的镜头下压契约按名字认臂，改名即回归）。
##
## 机位（3 张，全部只拍 L 本体，不带房间背景）：
##   1) 外角 +X+Z —— 两条臂的装饰面：看出来应当是「两面墙在角上相接」；
##   2) 内角 -X-Z —— 凹侧结构面：应当看到两面平整的墙背，不应看到装饰件；
##   3) 俯视 —— 直接读 L 形占地（长臂 +X 5m、短臂 -Z 5m）。
##
## 三处**诊断性偏离**（只服务判读，不代表游戏内观感）：自建天空环境 + 一盏平行光
## （L 本体没有光源与房间灯）、相机独立于玩家、固定机距 17m。
##
## 判据：CORNER_L_VISUAL_OK。图落 res://outputs/verification/。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

const PREFAB_PATH := "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"
## 对照用的直墙模块。L 由两份它拼成，所以「一模一样」最直接的证据就是把它和 L
## 摆在同一个光照下同框渲染：两块面板应当看不出差别。
const WALL_PREFAB_PATH := "res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
const WALL_REFERENCE_POSITION := Vector3(-8.0, 0.0, 0.0)
const OUTPUT_DIR := "res://outputs/verification"
const EXTERIOR_PATH := OUTPUT_DIR + "/corner_l_exterior_plus_x_plus_z.png"
const INTERIOR_PATH := OUTPUT_DIR + "/corner_l_interior_minus_x_minus_z.png"
const TOP_PATH := OUTPUT_DIR + "/corner_l_top.png"
const PAIR_PATH := OUTPUT_DIR + "/corner_l_pair_with_wall_plus_z.png"

## prefab metadata 声明的契约包络（visual_bounds_size_m），独立复算。
const EXPECTED_SIZE := Vector3(5.15, 11.9, 5.3175)
## 包络最小角 = 转角起算：长臂装饰面凸到 +X 0.3175、反向结构面 -0.15；
## 短臂同理落在 Z 轴；底面 Y=0。
const EXPECTED_POSITION := Vector3(-0.15, 0.0, -5.0)
## 01_精工金属_紫色骨架 / 02_细腻哑光_青绿大面 / 04_柔和自发光_UI灯光
const EXPECTED_MATERIAL_ROLES := 3
const EXPECTED_COLLISION_BODIES: Array[String] = ["WallCollisionLong", "WallCollisionShort"]

const SIZE_TOLERANCE_M := 0.02
const POSITION_TOLERANCE_M := 0.02
## 亮度分层下限。门扇探针用 6，因为那三张全是竖立面特写；本件不行：俯视机位刻意
## 只看平顶与地面，实测同一机位两轮落在 4~7 层之间（还受渲染时序影响）。空白帧
## （纯天空或全黑）只有 1~3 层，所以 4 仍能挡掉「什么都没渲染出来」，而 6 会误报。
const MIN_LUMA_BUCKETS := 4
const CAMERA_DISTANCE_M := 17.0

const SHOTS: Array = [
	{
		"name": "exterior(+X+Z)",
		"eye_offset": Vector3(1.0, 0.42, 1.0),
		"path": EXTERIOR_PATH,
	},
	{
		"name": "interior(-X-Z)",
		"eye_offset": Vector3(-1.0, 0.42, -1.0),
		"path": INTERIOR_PATH,
	},
	{
		"name": "top",
		"eye_offset": Vector3(0.18, 2.4, 0.18),
		"path": TOP_PATH,
	},
	# 与直墙并排对照：直墙摆在 -X 侧，装饰面同样朝 +Z，与 L 的长臂同向同高。
	# 这张是「一模一样」的直接证据 —— 同一光照下两块应当渲染成同样的画面。
	{
		"name": "pair(+Z)",
		"eye_offset": Vector3(0.0, 0.16, 1.0),
		"path": PAIR_PATH,
		"target": Vector3(-1.5, 5.95, 0.08),
		"distance": 26.0,
		"with_wall": true,
	},
]

var _skipped_headless := 0
var _captured := 0


func _ready() -> void:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var prefab := load(PREFAB_PATH) as PackedScene
	if prefab == null:
		failures.append("L 墙角 prefab 加载失败：%s" % PREFAB_PATH)
		_report(failures)
		return
	var corner := prefab.instantiate() as Node3D
	if corner == null:
		failures.append("L 墙角 prefab 实例化失败（根节点不是 Node3D）")
		_report(failures)
		return
	add_child(corner)
	# 对照直墙按需挂载（见 shot 的 with_wall）：只有 pair 机位需要它，
	# 其它机位居高临下会把它一起拍进去，污染那几张的证据力。
	var wall_reference: Node3D = null
	await get_tree().process_frame

	var bounds := TOWER_GEOMETRY.resolve_visual_bounds(corner)
	if bounds.size.length() <= 0.001:
		failures.append("resolve_visual_bounds 返回退化包围盒：%s" % str(bounds))
		_report(failures)
		return
	_verify_bounds(bounds, failures)
	_verify_materials(corner, failures)
	_verify_collision_contract(corner, failures)
	print(
		"[corner_l] bounds min=%s size=%s center=%s"
		% [str(bounds.position), str(bounds.size), str(bounds.get_center())]
	)

	var environment_setting := _install_environment()
	var light := _install_light(bounds.get_center())
	var camera := _install_camera(bounds.get_center())
	await _settle()
	for shot in SHOTS:
		var wants_wall := bool(shot.get("with_wall", false))
		if wants_wall and wall_reference == null:
			wall_reference = _install_wall_reference()
		elif not wants_wall and wall_reference != null and is_instance_valid(wall_reference):
			wall_reference.queue_free()
			wall_reference = null
		var offset := (shot["eye_offset"] as Vector3).normalized()
		var target := bounds.get_center()
		if shot.has("target"):
			target = shot["target"] as Vector3
		var distance := CAMERA_DISTANCE_M
		if shot.has("distance"):
			distance = float(shot["distance"])
		_aim(camera, target + offset * distance, target)
		print("[corner_l] shot=%s eye=%s" % [str(shot["name"]), str(camera.global_position)])
		await _settle()
		_capture(str(shot["path"]), "L 墙角 %s 采样失败" % str(shot["name"]), failures)

	if light != null and is_instance_valid(light):
		light.queue_free()
	if environment_setting != null and is_instance_valid(environment_setting):
		environment_setting.queue_free()
	if wall_reference != null and is_instance_valid(wall_reference):
		wall_reference.queue_free()
	corner.queue_free()
	await get_tree().process_frame
	_report(failures)


## 对照直墙：装饰面朝 +Z，与 L 的长臂同向同高，摆在 -X 侧留出间隔。
func _install_wall_reference() -> Node3D:
	var prefab := load(WALL_PREFAB_PATH) as PackedScene
	if prefab == null:
		push_error("对照直墙加载失败：%s" % WALL_PREFAB_PATH)
		return null
	var wall := prefab.instantiate() as Node3D
	if wall == null:
		push_error("对照直墙实例化失败")
		return null
	wall.name = "WallReferenceForPairShot"
	add_child(wall)
	wall.position = WALL_REFERENCE_POSITION
	return wall


## 包络断言：尺寸 + 最小角。原点约定是 bottom_corner，所以「最小角」本身就是
## 契约的一部分 —— 若几何被重新居中，position 会立刻偏离。
func _verify_bounds(bounds: AABB, failures: Array[String]) -> void:
	var delta := (bounds.size - EXPECTED_SIZE).abs()
	if (
		delta.x > SIZE_TOLERANCE_M
		or delta.y > SIZE_TOLERANCE_M
		or delta.z > SIZE_TOLERANCE_M
	):
		failures.append(
			"L 墙角可视包络与契约不符：实际 %s，契约 %s" % [str(bounds.size), str(EXPECTED_SIZE)]
		)
	var pos_delta := (bounds.position - EXPECTED_POSITION).abs()
	if (
		pos_delta.x > POSITION_TOLERANCE_M
		or pos_delta.y > POSITION_TOLERANCE_M
		or pos_delta.z > POSITION_TOLERANCE_M
	):
		failures.append(
			"L 墙角包络最小角与 bottom_corner 契约不符：实际 %s，契约 %s"
			% [str(bounds.position), str(EXPECTED_POSITION)]
		)


func _verify_materials(corner: Node, failures: Array[String]) -> void:
	var role_count := 0
	var mesh_instance_count := 0
	for node in _all_mesh_instances(corner):
		mesh_instance_count += 1
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			role_count = maxi(role_count, mesh.get_surface_count())
	if mesh_instance_count == 0:
		failures.append("L 墙角子树里没有任何 MeshInstance3D")
		return
	if role_count < EXPECTED_MATERIAL_ROLES:
		failures.append(
			"L 墙角材质角色数不足：实际 %d，契约 %d（疑似退回单色占位件）"
			% [role_count, EXPECTED_MATERIAL_ROLES]
		)
	print("[corner_l] mesh_instances=%d surface_roles=%d" % [mesh_instance_count, role_count])


## 碰撞契约：两个 StaticBody3D 必须还在，且名字不变 ——
## DungeonRoom3D._configure_corner_camera_collisions() 按名字决定哪条臂是南墙，
## 从而决定镜头是否下压。名字或数量一变，镜头行为就静默改变。
func _verify_collision_contract(corner: Node, failures: Array[String]) -> void:
	var names: Array[String] = []
	for value in corner.find_children("*", "StaticBody3D", true, false):
		names.append(String((value as StaticBody3D).name))
	names.sort()
	var expected := EXPECTED_COLLISION_BODIES.duplicate()
	expected.sort()
	if names != expected:
		failures.append(
			"L 墙角碰撞体与镜头契约不符：实际 %s，契约 %s" % [str(names), str(expected)]
		)
	for value in corner.find_children("*", "CollisionShape3D", true, false):
		var shape := (value as CollisionShape3D).shape as BoxShape3D
		if shape == null:
			failures.append("L 墙角碰撞体 %s 不是 BoxShape3D" % String((value as Node).name))
			continue
		print(
			"[corner_l] collision=%s size=%s"
			% [String((value as Node).name), str(shape.size)]
		)


func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root as MeshInstance3D)
	for child in root.get_children():
		found.append_array(_all_mesh_instances(child))
	return found


## 诊断性环境：程序化天空 + 天光。金属角色靠环境反射才有亮度，纯色背景会拍成近黑。
func _install_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "CornerLProbeEnvironment"
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


func _install_light(target: Vector3) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "CornerLProbeSun"
	light.light_energy = 2.1
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-42.0, -128.0, 0.0)
	add_child(light)
	return light


func _install_camera(target: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "CornerLProbeCamera"
	camera.fov = 60.0
	camera.near = 0.05
	camera.far = 400.0
	# 必须先入树再摆位：look_at 依赖 global_transform，树外会静默返回恒等。
	add_child(camera)
	camera.global_position = target + Vector3(0.0, 4.0, CAMERA_DISTANCE_M)
	camera.look_at(target, Vector3.UP)
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
			"CORNER_L_VISUAL_OK: exterior/interior/top previews saved under res://outputs/verification/ "
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
	await get_tree().create_timer(0.35).timeout


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
		"[corner_l] diag %s size=%dx%d center_pixel=%s"
		% [path.get_file(), image.get_width(), image.get_height(), str(mid)]
	)
	if buckets < MIN_LUMA_BUCKETS:
		failures.append("%s（画面只有 %d 层亮度，疑似没渲染出内容）" % [failure, buckets])
		return
	if image.save_png(path) != OK:
		failures.append(failure + "（PNG 写入失败）")
		return
	_captured += 1
	print(
		"[corner_l] saved %s %dx%d luma_buckets=%d"
		% [path.get_file(), image.get_width(), image.get_height(), buckets]
	)


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
