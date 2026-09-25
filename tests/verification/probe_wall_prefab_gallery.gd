extends Node
## 探针：把项目内**所有已导出为 prefab 的墙面件**逐件实拍，用于肉眼挑选/核对。
##
## 口径：
##   · 每件摆到原点，按 prefab 根节点的 metadata/forward_axis 把**装饰面统一转到朝 -Z**
##     （+Z 的件绕 Y 转 180°），相机固定在 -Z 侧 ⇒ 每件拍到的都是「装饰面」。
##   · 每件拍两张：① 正面漫射（看整体外观）② 掠射侧光（光几乎平行墙面，凸显浮雕厚度）。
##   · 取景按实例化后的世界 AABB 自动算，尺寸差异大的件也不会出画。
##   · 末尾加一组「同镜对照」：battle 通用直墙 vs tower A 套实墙，同机位同光各一张。
##
## 运行（**非 headless**，headless 的 dummy 渲染驱动拿不到真图）：
##   export APPDATA=I:/ss2_iso/wall_gallery
##   $GODOT --path . --resolution 1280x720 --scene res://tests/verification/probe_wall_prefab_gallery.tscn

const OUT_DIR := "I:/ss2_iso/wall_prefab_shots"

const P_BATTLE_WALL := "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"
const P_TOWER_WALL := "res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"

## 全部待拍件：fam = 家族分组（决定画廊分节），slug = 文件名，path = prefab。
const ITEMS: Array = [
	# ── A. battle 通用墙（远征01 现在在用的那一套） ──
	{"fam": "A battle 通用（远征在用）", "slug": "battle_wall_standard_5m", "path": P_BATTLE_WALL},
	{"fam": "A battle 通用（远征在用）", "slug": "battle_wall_door_5m", "path": "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d.tscn"},
	{"fam": "A battle 通用（远征在用）", "slug": "battle_wall_floor_facility_kit", "path": "res://assets/art/environments/tower_zones/battle/runtime/wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn"},
	# ── B. tower A 套（重装甲，167.5mm 浮雕） ──
	{"fam": "B tower A 套（重装甲）", "slug": "tower_wall_solid_5m", "path": P_TOWER_WALL},
	{"fam": "B tower A 套（重装甲）", "slug": "tower_wall_door_5m", "path": "res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn"},
	{"fam": "B tower A 套（重装甲）", "slug": "tower_corner_l_5m", "path": "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"},
	{"fam": "B tower A 套（重装甲）", "slug": "tower_wall_parapet_5m", "path": "res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m.tscn"},
	{"fam": "B tower A 套（重装甲）", "slug": "tower_wall_parapet_door_5m", "path": "res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m.tscn"},
	{"fam": "B tower A 套（重装甲）", "slug": "corner_l_parapet_5m", "path": "res://assets/art/props/dungeon_3d/prp_corner_l_parapet_5m.tscn"},
	{"fam": "B tower A 套（重装甲）", "slug": "corner_t_5m", "path": "res://assets/art/props/dungeon_3d/prp_corner_t_5m.tscn"},
	{"fam": "B tower A 套（重装甲）", "slug": "corner_x_5m", "path": "res://assets/art/props/dungeon_3d/prp_corner_x_5m.tscn"},
	# ── C. base99 设施墙（5x12 / 5x9） ──
	{"fam": "C base99 设施墙", "slug": "base99_wall_plain_5x12", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_plain_5x12/env_base99_wall_plain_5x12_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_wall_plain_5x9", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_plain_5x9/env_base99_wall_plain_5x9_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_wall_door_5x12", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x12/env_base99_wall_door_5x12_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_wall_door_5x9", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_wall_window_5x12", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_window_5x12/env_base99_wall_window_5x12_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_wall_window_5x9", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_window_5x9/env_base99_wall_window_5x9_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_wall_contents", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_contents/env_base99_wall_contents_root_top3d.tscn"},
	{"fam": "C base99 设施墙", "slug": "base99_corner_l_5m", "path": "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d.tscn"},
	# ── D. rooftop 屋顶墙 ──
	{"fam": "D rooftop 屋顶", "slug": "rooftop_room_wall_5x12", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_room_wall_5x12.tscn"},
	{"fam": "D rooftop 屋顶", "slug": "rooftop_room_wall_ivy_5x12", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_room_wall_ivy_5x12.tscn"},
	{"fam": "D rooftop 屋顶", "slug": "rooftop_room_doorwall_5x12", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_room_doorwall_5x12.tscn"},
	{"fam": "D rooftop 屋顶", "slug": "rooftop_room_doorwall_ivy_5x12", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_room_doorwall_ivy_5x12.tscn"},
	{"fam": "D rooftop 屋顶", "slug": "rooftop_parapet_5m", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_parapet_5m.tscn"},
	{"fam": "D rooftop 屋顶", "slug": "rooftop_parapet_outer_2p5m", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_parapet_outer_2p5m.tscn"},
	{"fam": "D rooftop 屋顶", "slug": "rooftop_roof_corner_5m", "path": "res://assets/art/props/dungeon_3d/prp_rooftop_roof_corner_5m.tscn"},
	# ── E. 旧地牢占位件（无 asset_id） ──
	{"fam": "E 旧地牢占位", "slug": "room_wall_segment(纯平面)", "path": "res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn"},
	{"fam": "E 旧地牢占位", "slug": "room_wall_door_segment", "path": "res://assets/art/props/dungeon_3d/prp_room_wall_door_segment.tscn"},
	{"fam": "E 旧地牢占位", "slug": "corridor_wall_segment", "path": "res://assets/art/props/dungeon_3d/prp_corridor_wall_segment.tscn"},
	{"fam": "E 旧地牢占位", "slug": "room_facility_base_wall", "path": "res://assets/art/props/dungeon_3d/prp_room_facility_base_wall.tscn"},
	{"fam": "E 旧地牢占位", "slug": "room_corner_post", "path": "res://assets/art/props/dungeon_3d/prp_room_corner_post.tscn"},
]

var _camera: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _stage: Node3D
var _shot_index := 0
var _fail: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_environment()
	await _phase_gallery()
	await _phase_head_to_head()
	print("\nDONE shots=%d fail=%d" % [_shot_index, _fail.size()])
	for f in _fail:
		print("  FAIL %s" % str(f))
	get_tree().quit(0)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.60, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.66)
	env.ambient_light_energy = 0.40
	var world_env := WorldEnvironment.new()
	world_env.name = "ProbeWorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	_key_light = DirectionalLight3D.new()
	_key_light.name = "ProbeKeyLight"
	_key_light.light_energy = 1.3
	_key_light.shadow_enabled = true
	add_child(_key_light)
	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "ProbeFillLight"
	_fill_light.light_energy = 0.5
	add_child(_fill_light)
	_camera = Camera3D.new()
	_camera.name = "ProbeCamera"
	_camera.fov = 45.0
	_camera.near = 0.05
	_camera.far = 500.0
	add_child(_camera)
	_stage = Node3D.new()
	_stage.name = "ProbeStage"
	add_child(_stage)


## 逐件实拍：正面漫射 + 掠射侧光。
func _phase_gallery() -> void:
	print("========== 墙面 prefab 画廊（%d 件） ==========" % ITEMS.size())
	var index := 0
	for item in ITEMS:
		index += 1
		var path := str(item["path"])
		var slug := str(item["slug"])
		var scene := load(path) as PackedScene
		if scene == null:
			print("  !! [%02d] %s 加载失败" % [index, path])
			_fail.append(path)
			continue
		_clear_stage()
		var root := scene.instantiate() as Node3D
		if root == null:
			print("  !! [%02d] %s 根不是 Node3D" % [index, path])
			_fail.append(path)
			continue
		_stage.add_child(root)
		# 装饰面统一朝 -Z（相机在 -Z 侧），这样每件拍到的都是装饰面。
		var fwd := str(root.get_meta("forward_axis", "-Z"))
		if fwd == "+Z":
			root.rotation.y = PI
		await get_tree().process_frame
		await get_tree().process_frame
		var box := _world_aabb(_stage)
		var center := box.get_center()
		var radius := maxf(box.size.length() * 0.5, 0.5)
		var aid := str(root.get_meta("asset_id", ""))
		var ver := str(root.get_meta("asset_version", ""))
		print("  [%02d/%d] %-34s aid=%-44s ver=%-5s fwd=%-3s aabb=(%.2f,%.2f,%.2f) mesh=%d" % [
			index, ITEMS.size(), slug, (aid if not aid.is_empty() else "(无 asset_id)"),
			(ver if not ver.is_empty() else "-"), fwd,
			box.size.x, box.size.y, box.size.z, _count_mesh(_stage),
		])
		# ① 正面漫射
		_set_diffuse_lighting()
		_frame(center, radius, Vector3(0.0, 0.02, -1.0), 45.0)
		await _capture("%02d_%s_正面" % [index, slug])
		# ② 掠射侧光：光几乎平行墙面自左侧掠来，浮雕的阴影对比最大。
		_set_grazing_lighting()
		_frame(center, radius, Vector3(-0.62, 0.20, -1.0), 40.0)
		await _capture("%02d_%s_掠射" % [index, slug])
	print("")


## 同镜对照：battle 通用直墙 vs tower A 套实墙，同机位、同光照。
func _phase_head_to_head() -> void:
	print("========== 同镜对照：battle 通用墙 vs tower A 套实墙 ==========")
	_clear_stage()
	var left := (load(P_BATTLE_WALL) as PackedScene).instantiate() as Node3D
	var right := (load(P_TOWER_WALL) as PackedScene).instantiate() as Node3D
	if left == null or right == null:
		print("  !! 对照件加载失败")
		_fail.append("head_to_head")
		return
	left.name = "HeadToHead_Battle"
	right.name = "HeadToHead_Tower"
	_stage.add_child(left)
	_stage.add_child(right)
	left.position = Vector3(-3.2, 0.0, 0.0)
	right.position = Vector3(3.2, 0.0, 0.0)
	# battle 是 -Z、tower 是 +Z ⇒ 把 tower 转 180° 让两件装饰面都朝相机（-Z）。
	if str(right.get_meta("forward_axis", "-Z")) == "+Z":
		right.rotation.y = PI
	await get_tree().process_frame
	await get_tree().process_frame
	var box := _world_aabb(_stage)
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.5)
	print("  两件并排 aabb=(%.2f,%.2f,%.2f)" % [box.size.x, box.size.y, box.size.z])
	_set_diffuse_lighting()
	_frame(center, radius, Vector3(0.0, 0.02, -1.0), 45.0)
	await _capture("99_对照_左battle右tower_正面")
	_set_grazing_lighting()
	_frame(center, radius, Vector3(0.0, 0.16, -1.0), 45.0)
	await _capture("99_对照_左battle右tower_掠射")
	# 贴脸特写：只看两块板的同一段高度，厚度差异最直观。
	_set_grazing_lighting()
	var near_center := Vector3(0.0, 3.2, 0.0)
	_frame(near_center, 2.6, Vector3(-0.30, 0.10, -1.0), 42.0)
	await _capture("99_对照_贴脸特写_掠射")
	print("")


func _clear_stage() -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()


func _set_diffuse_lighting() -> void:
	_key_light.rotation_degrees = Vector3(-28.0, -150.0, 0.0)
	_key_light.light_energy = 1.25
	_fill_light.rotation_degrees = Vector3(-18.0, 40.0, 0.0)
	_fill_light.light_energy = 0.55


## 光几乎平行墙面（沿 +X 掠射、极低仰角）⇒ 浮雕侧壁拉出长阴影，3mm 都能看出来。
func _set_grazing_lighting() -> void:
	_key_light.rotation_degrees = Vector3(-4.0, -172.0, 0.0)
	_key_light.light_energy = 1.05
	_fill_light.rotation_degrees = Vector3(-8.0, -8.0, 0.0)
	_fill_light.light_energy = 0.10


## 把相机摆到 center + dir*dist 看向中心，dist 由包围球半径与 FOV 反算。
func _frame(center: Vector3, radius: float, dir: Vector3, fov_deg: float) -> void:
	var fov := deg_to_rad(fov_deg)
	var dist := radius / tan(fov * 0.5) * 1.18
	_camera.fov = fov_deg
	_camera.position = center + dir.normalized() * dist
	_camera.look_at(center, Vector3.UP)


## 累加子树里所有 MeshInstance3D 的世界 AABB（Godot 的 Node3D 自身没有 get_aabb）。
func _world_aabb(root: Node) -> AABB:
	var result := AABB()
	var started := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var xf := mi.global_transform
		for corner_index in 8:
			var corner := box.get_endpoint(corner_index)
			var world := xf * corner
			if not started:
				result = AABB(world, Vector3.ZERO)
				started = true
			else:
				result = result.expand(world)
	return result


func _count_mesh(root: Node) -> int:
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			count += 1
	return count


func _capture(label: String) -> void:
	_camera.make_current()
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("     !! %s 截图失败" % label)
		return
	_shot_index += 1
	var path := "%s/%s.png" % [OUT_DIR, label]
	var err := image.save_png(path)
	if err != OK:
		print("     !! %s 存盘失败 err=%d" % [path, err])
