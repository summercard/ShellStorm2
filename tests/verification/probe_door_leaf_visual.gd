extends Node
## A 套门扇（ENV-TOWER-DOOR-LEAF-5M）的**画面**核对（非 headless，真渲染器）。
##
## 为什么逻辑门禁不够：门扇正确性已有两条数值门禁覆盖 ——
##   · verify_tower_module_prefabs 断言 8 项 prefab 契约（恒等 TRS / 包络 / 材质角色）；
##   · verify_door_passability 断言 2.2m 门洞可通行。
## 但这两条都回答不了「渲染出来到底长什么样」：一坨没有调色盘的灰白方块、
## 法线朝里导致整面翻黑、原点没归零导致门扇飘在半空 —— 在数值断言里全都合法。
## 只有真渲染一张图才看得出来，故本项目每个换过视觉的组件都配一张采样图。
##
## 机位（3 张，全部正对门扇本体，不带任何房间背景）：
##   1) +Z 正面 —— 门扇在门墙同侧的那一面（A 套约定 forward_axis="+Z"）；
##   2) −Z 背面 —— 若正面/背面差异很大，说明 180° 偏航烘焙没做或做反了；
##   3) +X 侧视 —— 看厚度方向（0.18m）有没有把装饰件切掉。
##
## 三处**诊断性偏离**（只服务判读，不代表游戏内观感）：
##   · 自建中灰环境 + 一盏平行光 —— 门扇本体没有光源，不加光是全黑图；
##   · 相机独立于玩家 —— 本探针根本不加载关卡，只拍资产本身；
##   · 固定机距 6.2m —— 门扇高 2.5m，这个距离下纵向恰好占画面约 2/3。
##
## 判据：DOOR_LEAF_VISUAL_OK。图落 res://outputs/verification/。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

const PREFAB_PATH := "res://assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn"
const OUTPUT_DIR := "res://outputs/verification"
const FRONT_PATH := OUTPUT_DIR + "/door_leaf_front_plus_z.png"
const BACK_PATH := OUTPUT_DIR + "/door_leaf_back_minus_z.png"
const SIDE_PATH := OUTPUT_DIR + "/door_leaf_side_plus_x.png"

## prefab metadata 声明的契约包络（visual_bounds_size_m）。探针独立复算，不读 metadata，
## 这样「声明值」与「实际几何」不符时探针会红，而不是自证。
const EXPECTED_SIZE := Vector3(2.2, 2.492, 0.18)
## 门扇底边悬在原点上方 8mm（美术意图：关闭的门不该擦地），见 prefab panel_bottom_clearance_m。
const EXPECTED_BOTTOM_Y := 0.008
## prefab metadata 声明的材质角色数（01_精工金属_紫色骨架 / 02_细腻哑光_青绿大面 /
## 03_清漆反光_紫粉点缀 / 04_柔和自发光_UI灯光）。
const EXPECTED_MATERIAL_ROLES := 4

const SIZE_TOLERANCE_M := 0.012
const BOTTOM_TOLERANCE_M := 0.004
const MIN_LUMA_BUCKETS := 6
const CAMERA_DISTANCE_M := 6.2

## 机位：以门扇包围盒中心为注视点，机距固定，绕竖直轴换方位。
## eye_offset 已归一化，乘 CAMERA_DISTANCE_M 后落位。
const SHOTS: Array = [
	{
		"name": "front(+Z)",
		"eye_offset": Vector3(0.0, 0.06, 1.0),
		"path": FRONT_PATH,
	},
	{
		"name": "back(-Z)",
		"eye_offset": Vector3(0.0, 0.06, -1.0),
		"path": BACK_PATH,
	},
	{
		"name": "side(+X)",
		"eye_offset": Vector3(1.0, 0.22, 0.16),
		"path": SIDE_PATH,
	},
]

## headless 下无渲染器，采样被静默跳过的帧数（仅日志诊断，不参与成败判定）。
var _skipped_headless := 0
## 真渲染器下成功落盘的图数。
var _captured := 0


func _ready() -> void:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var prefab := load(PREFAB_PATH) as PackedScene
	if prefab == null:
		failures.append("门扇 prefab 加载失败：%s" % PREFAB_PATH)
		_report(failures)
		return
	var leaf := prefab.instantiate() as Node3D
	if leaf == null:
		failures.append("门扇 prefab 实例化失败（根节点不是 Node3D）")
		_report(failures)
		return
	add_child(leaf)
	await get_tree().process_frame

	# —— 数值部分：让「出图」与「契约」落在同一份日志里 ——
	var bounds := TOWER_GEOMETRY.resolve_visual_bounds(leaf)
	if bounds.size.length() <= 0.001:
		failures.append("resolve_visual_bounds 返回退化包围盒：%s" % str(bounds))
		_report(failures)
		return
	_verify_bounds(bounds, failures)
	_verify_materials(leaf, failures)
	print(
		"[door_leaf] bounds min=%s size=%s center=%s"
		% [str(bounds.position), str(bounds.size), str(bounds.get_center())]
	)

	# —— 渲染部分 ——
	var environment_setting := _install_environment()
	var light := _install_light(bounds.get_center())
	var camera := _install_camera(bounds.get_center())
	await _settle()
	for shot in SHOTS:
		var offset := (shot["eye_offset"] as Vector3).normalized()
		_aim(camera, bounds.get_center() + offset * CAMERA_DISTANCE_M, bounds.get_center())
		print("[door_leaf] shot=%s eye=%s" % [str(shot["name"]), str(camera.global_position)])
		await _settle()
		_capture(str(shot["path"]), "门扇 %s 采样失败" % str(shot["name"]), failures)

	if light != null and is_instance_valid(light):
		light.queue_free()
	if environment_setting != null and is_instance_valid(environment_setting):
		environment_setting.queue_free()
	leaf.queue_free()
	await get_tree().process_frame
	_report(failures)


## 包络断言：尺寸与底边。判据与 prefab metadata 同源但独立复算。
func _verify_bounds(bounds: AABB, failures: Array[String]) -> void:
	var size := bounds.size
	if not size.is_equal_approx(EXPECTED_SIZE):
		var delta := (size - EXPECTED_SIZE).abs()
		if delta.x > SIZE_TOLERANCE_M or delta.y > SIZE_TOLERANCE_M or delta.z > SIZE_TOLERANCE_M:
			failures.append(
				"门扇可视包络与契约不符：实际 %s，契约 %s" % [str(size), str(EXPECTED_SIZE)]
			)
	if absf(bounds.position.y - EXPECTED_BOTTOM_Y) > BOTTOM_TOLERANCE_M:
		failures.append(
			"门扇底边离地高度与契约不符：实际 %.4f，契约 %.4f（关闭的门应当悬空 8mm 不擦地）"
			% [bounds.position.y, EXPECTED_BOTTOM_Y]
		)
	# 厚度方向必须居中：偏轴会让门扇贴着门洞一侧，关闭时露出缝。
	var expect_min_z := -EXPECTED_SIZE.z * 0.5
	if absf(bounds.position.z - expect_min_z) > BOTTOM_TOLERANCE_M:
		failures.append(
			"门扇厚度未居中：z 起点 %.4f，期望 %.4f" % [bounds.position.z, expect_min_z]
		)


## 材质断言：必须有多角色材质，且不是「一个纯色占位」。
func _verify_materials(leaf: Node, failures: Array[String]) -> void:
	var role_count := 0
	var mesh_instance_count := 0
	for node in _all_mesh_instances(leaf):
		mesh_instance_count += 1
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			role_count = maxi(role_count, mesh.get_surface_count())
		# 诊断：surface 材质类型与可见性。PaletteUV 是 ShaderMaterial，
		# 若它渲染不出内容，这里能立刻看出是「材质没用上」还是「节点没渲染」。
		var mesh_instance := node as MeshInstance3D
		var surface_info: Array[String] = []
		if mesh != null:
			for index in range(mesh.get_surface_count()):
				var material := mesh_instance.get_surface_override_material(index)
				if material == null and mesh_instance.mesh != null:
					material = mesh.surface_get_material(index)
				surface_info.append(
					"%d:%s" % [
						index,
						"none" if material == null else material.get_class(),
					]
				)
		print(
			"[door_leaf] mesh=%s visible=%s layers=%d parent_visible=%s surfaces=[%s]"
			% [
				mesh_instance.name,
				str(mesh_instance.visible),
				mesh_instance.layers,
				str((mesh_instance.get_parent() as Node3D).visible if mesh_instance.get_parent() is Node3D else true),
				", ".join(surface_info),
			]
		)
	if mesh_instance_count == 0:
		failures.append("门扇子树里没有任何 MeshInstance3D")
		return
	if role_count < EXPECTED_MATERIAL_ROLES:
		failures.append(
			"门扇材质角色数不足：实际 %d，契约 %d（疑似退回单色占位件）"
			% [role_count, EXPECTED_MATERIAL_ROLES]
		)
	print(
		"[door_leaf] mesh_instances=%d surface_roles=%d" % [mesh_instance_count, role_count]
	)


func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root as MeshInstance3D)
	for child in root.get_children():
		found.append_array(_all_mesh_instances(child))
	return found


## 诊断性环境：程序化天空 + 天光。
##
## 为什么必须给天空而不是纯色背景：门扇的主角色是「01_精工金属_紫色骨架」，
## 金属材质几乎没有漫反射，亮度基本只由**环境反射**决定。纯色背景 + 环境色光
## 下金属渲染成接近背景的深蓝黑（实测中心像素仅 0.05~0.11），
## 看上去像「什么都没渲染出来」，实则是探针的照明不足 —— 不是资产缺陷。
## 天空既提供反射源，也提供天光，是本项目所有资产采样图的统一口径。
func _install_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "DoorLeafProbeEnvironment"
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


## 一盏平行光，从相机侧上方照向门扇 —— 门扇本体没有光源，需要诊断照明才看得见结构。
func _install_light(target: Vector3) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "DoorLeafProbeSun"
	light.light_energy = 2.1
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-42.0, -128.0, 0.0)
	add_child(light)
	return light


## 独立相机，位置由 SHOTS 逐张设定。
func _install_camera(target: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "DoorLeafProbeCamera"
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 200.0
	# 必须先入树再摆位：look_at 依赖 global_transform，节点在树外时
	# global_transform 无效（静默返回恒等），相机会停在原点拍不到东西。
	add_child(camera)
	camera.global_position = target + Vector3(0.0, 0.4, CAMERA_DISTANCE_M)
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
			"DOOR_LEAF_VISUAL_OK: front/back/side previews saved under res://outputs/verification/ "
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
	await get_tree().create_timer(0.22).timeout


## 存图 + 渲染守卫：图必须非空、且亮度确有分层（挡掉「全黑却报绿」）。
## headless 下视口纹理必然为空 —— 那是环境事实，不是回归，故静默跳过并计数。
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
		"[door_leaf] diag %s size=%dx%d center_pixel=%s"
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
		"[door_leaf] saved %s %dx%d luma_buckets=%d"
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
