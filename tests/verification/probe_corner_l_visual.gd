extends Node
## A 套 L 墙角（ENV-TOWER-CORNER-L-5M）的**画面**核对（非 headless，真渲染器）。
##
## 为什么逻辑门禁不够：L 角已有数值覆盖 —— verify_tower_module_prefabs 的 8 项
## prefab 契约（恒等 TRS / 包络 / 原点约定 / 材质角色）与
## verify_door_passability / verify_common_wall_door_components_v004 的房间装配回归。
## 但都答不了「拼出来到底像不像两面墙」：两臂装反、装饰面朝错了一侧（本次就
## 发生过 —— 长臂朝外、房内看到结构背）、转角错开半米、或者干脆退化成空白块
## —— 在数值断言里全都合法。只有真渲染一张图才看得出来。
##
## 本件的形状契约（探针独立复算，不读 prefab metadata，以免自证）：
##   · 原点在**转角**（bottom_corner），两臂向 +X 与 -Z 伸出，底面 Y=0；
##   · 可视包络 = 5.15 × 11.9 × 5.15，最小角 (-0.15, 0, -5.0)；
##   · **房间内侧 = 两臂之间的凹象限（+X / -Z）**，两条臂的装饰面都朝该侧
##     （长臂 -Z、短臂 +X）—— 与运行时直墙口径一致（_build_corner_aware_wall_run
##     里南墙 rotation_y=PI、西墙 +PI/2，装饰面永远朝房内）；
##   · 两个碰撞体必须还在，且名字是 WallCollisionLong / WallCollisionShort
##     （DungeonRoom3D 的镜头下压契约按名字认臂，改名即回归）。
##
## 机位（4 张，全部只拍 L 本体，不带房间背景）：
##   1) 房内侧 +X-Z —— 玩家站位：应当看到**两条臂的装饰面**在角上相接；
##   2) 外侧 -X+Z —— 包络外壳面：应当看到两条臂平整的结构背，不应看到装饰件；
##   3) 俯视 —— 直接读 L 形占地（长臂 +X 5m、短臂 -Z 5m）；
##   4) 与直墙并排对照 —— 同一光照、同一朝向、同框，见 PAIR_PATH 注释。
##
## ⚠️ 2026-09-19 修正（两处，互为因果）：本探针原先跟着 prefab 注释把「凹侧」
##   标成 -X/-Z，机位 1/2 实际拍反了；而那时长臂的装饰面朝 +Z（朝 L 外侧），
##   玩家在房内看到的正是结构背。现在机位按真实房间内侧取景，L 已重派生重导出。
##
## 三处**诊断性偏离**（只服务判读，不代表游戏内观感）：自建天空环境 + 一盏平行光
## （L 本体没有光源与房间灯）、相机独立于玩家、固定机距 17m。
##
## 判据：CORNER_L_VISUAL_OK。除「图不是空白」外，还含一条**逐面朝向**判据（见 FACE_GAUGES）：
## 把长臂的装饰面与结构背在同一批图里各自投影裁出来量局部对比度（高通能量，半径 6，
## 与离线脚本 panel_check3 同口径），要求房内面明显更"花"。首版长臂漏了 Rz(180°) 时，
## 包络/面数/材质/原点四类断言全绿，只有这个比值会翻过来。
## 本机实测 room/outer = 3.22（0.02099 / 0.00652；离线同口径 4.99/1.54 ≈ 3.2）；
## 反向对照（把两个取样面互换机位）得 0.15 → 立刻退 1，判别力约 21×。
## 图落 res://outputs/verification/。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

const PREFAB_PATH := "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"
## 对照用的直墙模块。L 由两份它拼成，所以「一模一样」最直接的证据就是把它和 L
## 摆在同一个光照下同框渲染：两块面板应当看不出差别。
const WALL_PREFAB_PATH := "res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
const WALL_REFERENCE_POSITION := Vector3(-8.0, 0.0, 0.0)
## 直墙默认装饰面朝 +Z，而 L 的长臂装饰面朝 -Z（房内）。要「同朝向同框」比较，
## 就得把对照直墙绕 Y 转 180° —— 转完它与长臂是同一种刚性朝向，两块面板在
## 同一光照下应当渲染成同样的画面。
const WALL_REFERENCE_ROTATION_Y := PI
const OUTPUT_DIR := "res://outputs/verification"
const EXTERIOR_PATH := OUTPUT_DIR + "/corner_l_exterior_minus_x_plus_z.png"
const INTERIOR_PATH := OUTPUT_DIR + "/corner_l_interior_plus_x_minus_z.png"
const TOP_PATH := OUTPUT_DIR + "/corner_l_top.png"
const PAIR_PATH := OUTPUT_DIR + "/corner_l_pair_with_wall_minus_z.png"

## prefab metadata 声明的契约包络（visual_bounds_size_m），独立复算。
const EXPECTED_SIZE := Vector3(5.15, 11.9, 5.15)
## 包络最小角 = 转角起算：两臂装饰面都朝房内（长臂 -Z 0.3175 / 短臂 +X 0.3175，
## 落在包络内部），包络外壳面是两条臂的结构背（长臂 +Z 0.15、短臂 -X 0.15）；
## 长臂远端 X=+5、短臂远端 Z=-5；底面 Y=0。
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

## 逐面朝向判据的取样面（世界四角，探针自算，不读 prefab metadata）：长臂的
## 装饰面（房内侧 z=-0.3175）与结构背（外侧 z=+0.15）。两者的 X/Y 跨度**完全相同**，
## 只差一个 Z —— 所以「两侧整块对调」会毫厘不差地反映到能量比上。
## 装饰面有装甲凸起与色带边 → 局部对比度高；结构背是平整大面 → 几乎只有低频渐变。
const FACE_GAUGES: Array = [
	{
		"label": "long_arm_room_side",
		"shot": "interior(+X-Z)",
		"corners": [
			Vector3(0.5, 0.6, -0.3175),
			Vector3(5.0, 0.6, -0.3175),
			Vector3(0.5, 10.4, -0.3175),
			Vector3(5.0, 10.4, -0.3175),
		],
	},
	{
		"label": "long_arm_outer_side",
		"shot": "exterior(-X+Z)",
		"corners": [
			Vector3(0.5, 0.6, 0.15),
			Vector3(5.0, 0.6, 0.15),
			Vector3(0.5, 10.4, 0.15),
			Vector3(5.0, 10.4, 0.15),
		],
	},
]
## 高通用的盒式模糊半径（像素），与离线对照脚本 panel_check3 同口径。
const FACE_BLUR_RADIUS_PX := 6
## 房内面细节能量 / 外侧细节能量 的下限。同口径离线实测 ≈ 4.99 : 1.54 ≈ 3.2×（0~255 灰度），
## 换算到本件 0~1 尺度即 ≈ 0.0196 : 0.0060。阈值取 1.6 —— 只挡「两侧翻了个个儿」
## （会 < 1），不追求精确数值，避免光照/驱动差异造成抖动误报。
const FACE_ENERGY_RATIO_MIN := 1.6

const SHOTS: Array = [
	{
		"name": "interior(+X-Z)",
		"eye_offset": Vector3(1.0, 0.42, -1.0),
		"path": INTERIOR_PATH,
	},
	{
		"name": "exterior(-X+Z)",
		"eye_offset": Vector3(-1.0, 0.42, 1.0),
		"path": EXTERIOR_PATH,
	},
	{
		"name": "top",
		"eye_offset": Vector3(0.18, 2.4, 0.18),
		"path": TOP_PATH,
	},
	# 与直墙并排对照：直墙绕 Y 转 180°（装饰面同样朝 -Z，与 L 的长臂同向同高），
	# 摆在 -X 侧留出间隔，机位在 -Z。这张是「一模一样」的直接证据 —— 同一光照下
	# 两块应当渲染成同样的画面。画面中部那条窄竖板是 L 自己的短臂（它朝 +X 那侧
	# 才有装饰，本机位看到的是它的结构背），只压住长臂面板最左一线，不影响对照。
	{
		"name": "pair(-Z)",
		"eye_offset": Vector3(0.0, 0.16, -1.0),
		"path": PAIR_PATH,
		"target": Vector3(-2.75, 5.95, -0.08),
		"distance": 26.0,
		"with_wall": true,
	},
]

var _skipped_headless := 0
var _captured := 0
## label -> 局部对比度，由 _measure_faces() 填。
var _face_energy := {}


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
		var image := _capture(
			str(shot["path"]), "L 墙角 %s 采样失败" % str(shot["name"]), failures
		)
		_measure_faces(camera, str(shot["name"]), image)

	if light != null and is_instance_valid(light):
		light.queue_free()
	if environment_setting != null and is_instance_valid(environment_setting):
		environment_setting.queue_free()
	if wall_reference != null and is_instance_valid(wall_reference):
		wall_reference.queue_free()
	corner.queue_free()
	await get_tree().process_frame
	_verify_face_facing(failures)
	_report(failures)


## 对照直墙：绕 Y 转 180°（装饰面朝 -Z，与 L 的长臂同向），摆在 -X 侧留出间隔。
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
	wall.rotation.y = WALL_REFERENCE_ROTATION_Y
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
			"CORNER_L_VISUAL_OK: interior/exterior/top/pair previews saved under res://outputs/verification/ "
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


func _capture(path: String, failure: String, failures: Array[String]) -> Image:
	if DisplayServer.get_name() == "headless":
		_skipped_headless += 1
		return null
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append(failure + "（视口纹理为空）")
		return null
	var buckets := _luma_buckets(image)
	var mid := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	print(
		"[corner_l] diag %s size=%dx%d center_pixel=%s"
		% [path.get_file(), image.get_width(), image.get_height(), str(mid)]
	)
	if buckets < MIN_LUMA_BUCKETS:
		failures.append("%s（画面只有 %d 层亮度，疑似没渲染出内容）" % [failure, buckets])
		return null
	if image.save_png(path) != OK:
		failures.append(failure + "（PNG 写入失败）")
		return null
	_captured += 1
	print(
		"[corner_l] saved %s %dx%d luma_buckets=%d"
		% [path.get_file(), image.get_width(), image.get_height(), buckets]
	)
	return image


## 逐面朝向判据的取样：把 FACE_GAUGES 里属于本机位的面投影到屏幕、裁出来量细节能量。
## 只在对应机位取样（另两张图看不到这些面，取出来是背景）。
func _measure_faces(camera: Camera3D, shot_name: String, image: Image) -> void:
	if image == null:
		return
	for gauge in FACE_GAUGES:
		if String(gauge["shot"]) != shot_name:
			continue
		var rect := _project_face_rect(camera, gauge["corners"] as Array, image)
		if rect.size.x < 4 or rect.size.y < 4:
			print(
				"[corner_l] face %s 取样矩形无效，跳过：rect=%s"
				% [String(gauge["label"]), str(rect)]
			)
			continue
		var energy := _highpass_energy(image.get_region(rect))
		_face_energy[String(gauge["label"])] = energy
		print(
			"[corner_l] face %s shot=%s rect=%s px=%d energy=%.5f"
			% [
				String(gauge["label"]),
				shot_name,
				str(rect),
				rect.size.x * rect.size.y,
				energy,
			]
		)


## 把面的四角投影到屏幕取外接矩形，并裁剪到视口内。任一角落在相机背后即判无效
## （unproject_position 对背后点是未定义行为）。
func _project_face_rect(camera: Camera3D, corners: Array, image: Image) -> Rect2i:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for corner in corners:
		var world := corner as Vector3
		if camera.is_position_behind(world):
			return Rect2i()
		var screen := camera.unproject_position(world)
		min_x = minf(min_x, screen.x)
		min_y = minf(min_y, screen.y)
		max_x = maxf(max_x, screen.x)
		max_y = maxf(max_y, screen.y)
	if not is_finite(min_x) or not is_finite(min_y):
		return Rect2i()
	var x0 := clampi(int(floor(min_x)), 0, image.get_width() - 1)
	var y0 := clampi(int(floor(min_y)), 0, image.get_height() - 1)
	var x1 := clampi(int(ceil(max_x)), x0 + 1, image.get_width())
	var y1 := clampi(int(ceil(max_y)), y0 + 1, image.get_height())
	return Rect2i(Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0))


## 朝向判据：房内侧（装饰面）的局部对比度必须明显高于外侧（结构背）。
## 长臂若漏了 Rz(180°)，两侧能量会整块对调、比值 < 1，立刻失败 ——
## 而包络 / 面数 / 材质 / 原点四类断言对这种缺陷一律全绿。
func _verify_face_facing(failures: Array[String]) -> void:
	if _skipped_headless > 0 and _face_energy.is_empty():
		print("[corner_l] headless：逐面朝向判据跳过（无渲染图）")
		return
	var room := float(_face_energy.get("long_arm_room_side", -1.0))
	var outer := float(_face_energy.get("long_arm_outer_side", -1.0))
	if room < 0.0 or outer < 0.0:
		failures.append(
			"逐面朝向判据取样缺失：room_side=%.5f outer_side=%.5f（取景或投影失效）" % [room, outer]
		)
		return
	if outer <= 0.0 or room <= 0.0:
		failures.append(
			"逐面朝向判据取样面细节能量退化：room=%.5f outer=%.5f（两侧都应是可见面）"
			% [room, outer]
		)
		return
	var ratio := room / outer
	print("[corner_l] face ratio room/outer=%.3f (room=%.5f outer=%.5f)" % [ratio, room, outer])
	if ratio < FACE_ENERGY_RATIO_MIN:
		failures.append(
			"L 墙角长臂装饰面疑似朝外：房内面/外侧细节能量=%.2f，应 ≥ %.2f（room=%.5f outer=%.5f）"
			% [ratio, FACE_ENERGY_RATIO_MIN, room, outer]
		)


## 高通能量（局部对比度）：灰度 → 积分图盒式模糊 → 平均 |灰度 - 邻域均值|，
## 与离线对照脚本 panel_check3 同口径（半径 6，0~1 灰度尺度）。
func _highpass_energy(image: Image) -> float:
	var width := image.get_width()
	var height := image.get_height()
	if width < 3 or height < 3:
		return 0.0
	var gray := PackedFloat64Array()
	gray.resize(width * height)
	for y in range(height):
		for x in range(width):
			gray[y * width + x] = _luma(image.get_pixel(x, y))
	var stride := width + 1
	var prefix := PackedFloat64Array()
	prefix.resize(stride * (height + 1))
	for y in range(height):
		var row_sum := 0.0
		for x in range(width):
			row_sum += gray[y * width + x]
			prefix[(y + 1) * stride + (x + 1)] = prefix[y * stride + (x + 1)] + row_sum
	var total := 0.0
	var count := 0
	for y in range(height):
		var y0 := maxi(y - FACE_BLUR_RADIUS_PX, 0)
		var y1 := mini(y + FACE_BLUR_RADIUS_PX, height - 1)
		for x in range(width):
			var x0 := maxi(x - FACE_BLUR_RADIUS_PX, 0)
			var x1 := mini(x + FACE_BLUR_RADIUS_PX, width - 1)
			var sum := (
				prefix[(y1 + 1) * stride + (x1 + 1)]
				- prefix[y0 * stride + (x1 + 1)]
				- prefix[(y1 + 1) * stride + x0]
				+ prefix[y0 * stride + x0]
			)
			var area := float((x1 - x0 + 1) * (y1 - y0 + 1))
			total += absf(gray[y * width + x] - sum / area)
			count += 1
	return total / float(maxi(count, 1))


func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


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
