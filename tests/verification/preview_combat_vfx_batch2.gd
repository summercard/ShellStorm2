extends Node3D
## 真渲染预览：本批特效（业主 2026-10-14 命中分流 / 两件僵尸死亡 / 僵尸受击件改版 + 落点修正）。
##
## 分五组抓「游戏原生帧」，逐组存一个目录，供业主亲眼看节奏、配色与**落点**：
##   A. `goo_hit`        FX01-20 v002 僵尸受击（绿）落在**贴肉点**（已经 `hit_effect_anchor()` 收 0.2m）
##   B. `goo_hit_float`  同一件的**对照**：落在**碰撞壳表面**（未收）⇒ 直接看出差在哪
##   C. `pair`           同屏对照：FX01-20（绿，0.374）与 FX01-21（金，0.34）同形、只差色板与 10%
##   D. `death_blast`    FX01-17 胖子僵尸死亡 = 小僵尸死亡表现 ×2 + 3 层绿色冲击波
##   E. `goo_death`      FX01-19 小僵尸死亡（v001 未改版，无冲击波）
##
## ⚠ A / B 用的是**真的怪**（`Enemy3D` + `configure_from_enemy_data`）与**真的**落点函数
## （`Enemy3D.hit_effect_anchor()`）—— 不是摆一个坐标假装。碰撞壳半径也从怪的
## `collision_shape.shape` 现读并画成半透明柱，所以「壳」与「贴肉点」是同一套几何。
## 侧视角 + 两个线框标记（青 = 壳表面、品红 = 贴肉点）是刻意的：第一版用了斜前机位，
## 0.2m 的深度差正好落在视线方向 ⇒ 两张图**肉眼看不出区别**（等于没验）。侧视把这条
## 0.2m 摆到屏幕横轴上，差多少一眼可读。
##
## 只做「看」，不含任何断言；断言在 verify_hit_routing_vfx / verify_death_blast_vfx /
## verify_zombie_goo_death_vfx。

const OUTPUT_ROOT := "res://outputs/combat_vfx_batch2"
const GOO_HIT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_goo_hit_root_top3d.tscn")
const METAL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_metal_spark_hit_root_top3d.tscn")
const BLAST_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_death_blast_root_top3d.tscn")
const GOO_DEATH_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_zombie_goo_death_root_top3d.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

## 小僵尸死亡特效尺寸：业主「不要改变」⇒ 保持 1.0（与 `Enemy3D.GOO_DEATH_EFFECT_SIZE` 同值）
const GOO_DEATH_SIZE := 1.0
## 胖子僵尸死亡视觉尺寸：业主「把小僵尸的特效放大两倍给胖子僵尸用」⇒ 2.0
const BLAST_SIZE := 2.0
## 尺寸**现读调用方常量**，不手写 —— 业主每次调档（如「放大 50%」）都会让手写的数立刻过期，
## 而预览图一旦过期就会给出与实机不符的判断（本项目已经吃过一次「读数对、画面错」的亏）。
const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const ZOMBIE_HIT_SIZE := PROJECTILE_SCRIPT.GOO_HIT_SIZE_TARGET
const METAL_HIT_SIZE := PROJECTILE_SCRIPT.METAL_SPARK_SIZE_TARGET
const FLOOR_Y := 0.0
const SPAWN_LIFT := 0.65
const WALL_X := 2.2
## 受击高度（胸口）与朝向：法线指向 +Z ⇒ 「怪的正面」朝 +Z（侧视机位看在屏幕右侧）
const HIT_Y := 1.05
const HIT_NORMAL := Vector3(0.0, 0.0, 1.0)
## 侧视机位：沿 +X 看回原点 ⇒ 世界 Z 轴映射到屏幕横轴，0.2m 直接读得出来
const SIDE_CAM_POS := Vector3(4.9, 1.55, 0.0)
const SIDE_CAM_AT := Vector3(0.0, 1.02, 0.0)

var _camera: Camera3D
var _wall: MeshInstance3D
var _ruler: MeshInstance3D
var _enemy: Enemy3D = null
var _hull: MeshInstance3D
var _old_hull: MeshInstance3D
var _marker_hull: MeshInstance3D
var _marker_anchor: MeshInstance3D
var _hull_radius := 1.02
var _raw_point := Vector3.ZERO
var _anchored_point := Vector3.ZERO


func _ready() -> void:
	get_window().size = Vector2i(960, 600)
	_build_stage()
	_build_enemy()
	await get_tree().process_frame

	var plan: Array = [
		{
			"dir": "goo_hit", "scene": GOO_HIT_SCENE, "total": 0.32, "size": ZOMBIE_HIT_SIZE,
			"times": [0.0, 0.06, 0.12, 0.22, 0.32],
			"pos": _anchored_point, "normal": HIT_NORMAL, "stage": "body",
			"cam_pos": SIDE_CAM_POS, "cam_at": SIDE_CAM_AT,
		},
		{
			"dir": "goo_hit_float", "scene": GOO_HIT_SCENE, "total": 0.32, "size": ZOMBIE_HIT_SIZE,
			"times": [0.0, 0.06, 0.12, 0.22, 0.32],
			"pos": _raw_point, "normal": HIT_NORMAL, "stage": "body",
			"cam_pos": SIDE_CAM_POS, "cam_at": SIDE_CAM_AT,
		},
		{
			"dir": "pair", "scene": GOO_HIT_SCENE, "total": 0.32, "size": ZOMBIE_HIT_SIZE,
			"times": [0.0, 0.06, 0.12, 0.22, 0.32], "pair": true,
			"pos": Vector3(-0.62, 1.10, 0.0), "normal": Vector3(0.0, 0.0, -1.0),
			"stage": "pair",
			"cam_pos": Vector3(0.0, 1.42, -3.05), "cam_at": Vector3(0.0, 1.02, 0.0),
		},
		{
			"dir": "death_blast", "scene": BLAST_SCENE, "total": 0.72, "size": BLAST_SIZE,
			"times": [0.0, 0.08, 0.20, 0.36, 0.60], "normal": null, "stage": "none",
			"pos": Vector3(0.0, FLOOR_Y + SPAWN_LIFT, 0.0),
			"cam_pos": Vector3(4.6, 3.2, -5.2), "cam_at": Vector3(0.0, 0.9, 0.0),
		},
		{
			"dir": "goo_death", "scene": GOO_DEATH_SCENE, "total": 1.35, "size": GOO_DEATH_SIZE,
			"times": [0.0, 0.10, 0.30, 0.50, 0.85, 1.15], "normal": null, "stage": "none",
			"pos": Vector3(0.0, FLOOR_Y + SPAWN_LIFT, 0.0),
			"cam_pos": Vector3(5.4, 3.6, -6.0), "cam_at": Vector3(0.0, 0.9, 0.0),
		},
	]

	for entry in plan:
		await _capture_group(entry)
	print("PREVIEW_COMBAT_VFX_BATCH2_DONE")
	get_tree().quit(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.70, 0.80)
	env.ambient_light_energy = 0.9
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	shape.shape = box
	ground.add_child(shape)
	var ground_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = box.size
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.21, 0.22, 0.24)
	ground_mat.roughness = 0.95
	ground_mesh.material_override = ground_mat
	ground.add_child(ground_mesh)
	ground.position.y = FLOOR_Y - 0.1
	add_child(ground)

	_wall = MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.3, 2.8, 4.2)
	_wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.52, 0.54, 0.58)
	wall_mat.metallic = 0.75
	wall_mat.roughness = 0.38
	_wall.material_override = wall_mat
	_wall.position = Vector3(WALL_X, 1.4, 0.0)
	_wall.visible = false
	add_child(_wall)

	# 参考标尺：1.857m 中性立柱（小僵尸的高度），让「粒子多大」有可读尺度
	_ruler = MeshInstance3D.new()
	var ruler_mesh := BoxMesh.new()
	ruler_mesh.size = Vector3(0.10, 1.857, 0.10)
	_ruler.mesh = ruler_mesh
	var ruler_mat := StandardMaterial3D.new()
	ruler_mat.albedo_color = Color(0.80, 0.78, 0.68)
	ruler_mat.roughness = 0.8
	_ruler.material_override = ruler_mat
	add_child(_ruler)

	_camera = Camera3D.new()
	_camera.fov = 52.0
	add_child(_camera)
	_camera.current = true


## 摆一只真的小僵尸，按它的**真实碰撞柱半径**画半透明碰撞壳，并在「壳表面」与
## 「贴肉点」各放一个线框标记 —— A/B 两组的差别就是「特效生在哪个标记上」。
func _build_enemy() -> void:
	_enemy = ENEMY_SCENE.instantiate() as Enemy3D
	if _enemy == null:
		push_error("enemy prefab failed to instantiate")
		return
	add_child(_enemy)
	_enemy.set_physics_process(false)
	_enemy.global_position = Vector3.ZERO
	_enemy.configure_from_enemy_data({"enemy_type": "melee_chaser", "name": "小僵尸"})

	var shape: Shape3D = null
	if _enemy.collision_shape != null:
		shape = _enemy.collision_shape.shape
	var hull_height := 1.30
	if shape is CylinderShape3D:
		# ⚠ 必须乘怪的缩放（`_apply_presentation_scale()` 的 0.7）——`shape.radius` 是**局部**口径，
		# 画成世界尺寸的壳会比真实碰撞柱粗 43%，看着就像「特效在壳里面」。
		_hull_radius = (shape as CylinderShape3D).radius * _enemy.scale.x
		hull_height = (shape as CylinderShape3D).height * _enemy.scale.y

	_hull = MeshInstance3D.new()
	var hull_mesh := CylinderMesh.new()
	hull_mesh.top_radius = _hull_radius
	hull_mesh.bottom_radius = _hull_radius
	hull_mesh.height = hull_height
	hull_mesh.radial_segments = 28
	_hull.mesh = hull_mesh
	_hull.material_override = _wire_material(Color(0.35, 0.78, 1.0, 0.14))
	_hull.position = Vector3(0.0, hull_height * 0.5, 0.0)
	add_child(_hull)

	# 「旧口径」参考圈：半径 = 现半径 ÷ 0.8（业主 2026-10-15「直径缩小到现在的 80%」）。
	# 两层同屏 ⇒ 缩了多少肉眼可读；只看新圈的话「80%」是个没有参照的数字。
	_old_hull = MeshInstance3D.new()
	var old_mesh := CylinderMesh.new()
	old_mesh.top_radius = _hull_radius / 0.8
	old_mesh.bottom_radius = _hull_radius / 0.8
	old_mesh.height = hull_height
	old_mesh.radial_segments = 28
	_old_hull.mesh = old_mesh
	_old_hull.material_override = _wire_material(Color(1.0, 0.45, 0.35, 0.16))
	_old_hull.position = Vector3(0.0, hull_height * 0.5, 0.0)
	add_child(_old_hull)

	_raw_point = Vector3(0.0, HIT_Y, 0.0) + HIT_NORMAL * _hull_radius
	_anchored_point = _enemy.hit_effect_anchor(_raw_point, HIT_NORMAL)
	var half := _visual_half_width(_enemy.avatar)
	print("PREVIEW hull_now=%.3f hull_before=%.3f (x0.8)" % [_hull_radius, _hull_radius / 0.8])
	print(
		"PREVIEW derived_inset=%.3f (壳半径 %.3f → 落点 %.3f) 模型半宽 %.3f 落点距模型 %.3f"
		% [
			(_raw_point - _anchored_point).length(), _hull_radius,
			_anchored_point.z, half, maxf(0.0, absf(_anchored_point.z) - half),
		]
	)
	print(
		"PREVIEW sizes metal=%.3f zombie=%.3f (scale=%.2f)"
		% [METAL_HIT_SIZE, ZOMBIE_HIT_SIZE, PROJECTILE_SCRIPT.HIT_EFFECT_SIZE_SCALE]
	)

	_marker_hull = _build_marker(Color(0.30, 0.85, 1.0), _raw_point)
	_marker_anchor = _build_marker(Color(1.0, 0.30, 0.85), _anchored_point)
	var sink := (_raw_point - _anchored_point).length()
	print("PREVIEW hull_radius=%.3f raw=%s anchored=%s sink=%.3f" % [
		_hull_radius, str(_raw_point), str(_anchored_point), sink
	])
	# 量一下「模型到底有多宽」——用来判断这 0.2m 是不是真的贴到身上了。
	# 碰撞柱是**玩法口径**（`FOOTPRINT_PROFILES`，为避免穿模刻意放宽），比模型胖不少：
	# 特效从壳表面往里退了 0.2m 之后，离模型表面还有多远，就等于下面这个 gap_after_inset。
	var half_width := _visual_half_width(_enemy)
	print(
		"PREVIEW model_half_width=%.3f gap_after_inset=%.3f"
		% [half_width, maxf(0.0, _hull_radius - sink - half_width)]
	)


## 怪体可视件的半宽（世界 AABB 的 X/Z 取大者的一半）。
## `EnemyAvatar3D` 是 Node3D、没有 `get_aabb()` ⇒ 只能自己遍历 MeshInstance3D 求包围盒，
## 每个都按自己的 `global_transform` 变换后再合并（怪可能有缩放 / 旋转）。
func _visual_half_width(root: Node) -> float:
	var box := AABB()
	var has := false
	for node in _mesh_instances(root):
		var mesh_node := node as MeshInstance3D
		# ⚠ 必须滤掉没在画的件：`EnemyAvatar3D` 的占位件（_core/_shell/_appendages）在挂上
		# 正式模型后会被隐藏，网格数据还在 —— 不滤会把包围盒撑到 2.6 倍。
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		var local := mesh_node.get_aabb()
		var world := mesh_node.global_transform * local
		if not has:
			box = world
			has = true
		else:
			box = box.merge(world)
	if not has:
		return 0.0
	return maxf(box.size.x, box.size.z) * 0.5


func _mesh_instances(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root is MeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(_mesh_instances(child))
	return found


func _wire_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


## 标记：一个线框小球 + 一条向上的细指针 —— 侧视时能明确指到「就是这个高度、这个深度」。
## 比摆一个实心球更容易读出精确位置（实心球会盖住它要指的东西）。
func _build_marker(color: Color, at: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	mesh.radial_segments = 12
	mesh.rings = 6
	marker.mesh = mesh
	marker.material_override = _wire_material(Color(color.r, color.g, color.b, 0.9))
	var stem := MeshInstance3D.new()
	var stem_mesh := BoxMesh.new()
	stem_mesh.size = Vector3(0.016, 0.42, 0.016)
	stem.mesh = stem_mesh
	stem.material_override = _wire_material(Color(color.r, color.g, color.b, 0.85))
	stem.position = Vector3(0.0, 0.21, 0.0)
	marker.add_child(stem)
	marker.position = at
	add_child(marker)
	return marker


func _capture_group(entry: Dictionary) -> void:
	var dir_name := String(entry["dir"])
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUTPUT_ROOT, dir_name])
	var stage := String(entry["stage"])
	var show_body := stage == "body"
	_enemy.visible = show_body
	_hull.visible = show_body
	_old_hull.visible = show_body
	_marker_hull.visible = show_body
	_marker_anchor.visible = show_body
	var fx_pos: Vector3 = entry["pos"]
	# 标尺放在特效外侧（不挡镜头，也不与标记重叠）
	if show_body:
		_ruler.position = Vector3(0.0, 1.857 * 0.5, -1.60)
	elif stage == "pair":
		_ruler.position = Vector3(0.0, 1.857 * 0.5, 1.20)
	else:
		_ruler.position = Vector3(fx_pos.x - 1.30, 1.857 * 0.5, fx_pos.z + 1.30)
	_camera.position = entry["cam_pos"]
	_camera.look_at(entry["cam_at"])

	if bool(entry.get("pair", false)):
		await _capture_pair(entry)
		return

	var fx := _instantiate_fx(entry, fx_pos, float(entry["size"]))
	if fx == null:
		return
	var total := float(entry["total"])
	var index := 0
	for elapsed in entry["times"]:
		fx.call("_on_tick", float(elapsed), total)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/%s/frame_%02d_t%0.2f.png" % [OUTPUT_ROOT, dir_name, index, float(elapsed)]
		)
		print("saved %s frame %d at t=%.2f" % [dir_name, index, float(elapsed)])
		index += 1
	fx.queue_free()
	await get_tree().process_frame


## 同屏对照：左边 FX01-20（绿，0.374）、右边 FX01-21（金，0.34），同一时刻、同一机位。
## 业主说的「使用击中其它物体的那个特效，然后改成绿色即可，放大大概 10%」——
## 这一张就是那句话的字面读法：形状一模一样，颜色一绿一金，绿的那个大一圈。
func _capture_pair(entry: Dictionary) -> void:
	var left_pos: Vector3 = entry["pos"]
	var right_pos := left_pos + Vector3(1.24, 0.0, 0.0)
	var normal: Vector3 = entry["normal"]
	var green := GOO_HIT_SCENE.instantiate() as VfxEffectBase3D
	var metal := METAL_SCENE.instantiate() as VfxEffectBase3D
	if green == null or metal == null:
		push_error("pair prefabs failed to instantiate")
		return
	var pairs: Array = [
		[green, left_pos, ZOMBIE_HIT_SIZE], [metal, right_pos, METAL_HIT_SIZE]
	]
	for pair in pairs:
		var node := pair[0] as VfxEffectBase3D
		add_child(node)
		node.set_process(false)
		node.activate(pair[1], Color(0.58, 0.19, 0.12), float(pair[2]), {
			"floor_y": FLOOR_Y, "normal": normal,
		})
	await get_tree().process_frame
	var total := float(entry["total"])
	var index := 0
	for elapsed in entry["times"]:
		green.call("_on_tick", float(elapsed), total)
		metal.call("_on_tick", float(elapsed), total)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/pair/frame_%02d_t%0.2f.png" % [OUTPUT_ROOT, index, float(elapsed)]
		)
		print("saved pair frame %d at t=%.2f" % [index, float(elapsed)])
		index += 1
	green.queue_free()
	metal.queue_free()
	await get_tree().process_frame


func _instantiate_fx(entry: Dictionary, fx_pos: Vector3, size: float) -> VfxEffectBase3D:
	var packed: PackedScene = entry["scene"]
	var fx := packed.instantiate() as VfxEffectBase3D
	if fx == null:
		push_error("prefab failed to instantiate: %s" % entry["dir"])
		return null
	add_child(fx)
	fx.set_process(false)
	var context: Dictionary = {"floor_y": FLOOR_Y}
	var normal: Variant = entry["normal"]
	if normal != null:
		context["normal"] = normal
	# 调用方本色用小僵尸的暗红（与实机一致），验证「绿色读法不被冲掉」
	fx.activate(fx_pos, Color(0.58, 0.19, 0.12), size, context)
	return fx
