extends Node
## 远征03 全部房间白模 · 顶视角截图（开发期拍摄工具，不写回任何正式场景）
##
## 运行：
##   godot --path . --scene res://tools/_exp03_whitebox_views_render.tscn
##
## 输出：outputs/expedition03_whitebox_views_20261030/
##       {序号}_{shell_id}_top.png   正俯视 90°（读轮廓 / 门洞 / 地面格）
##       {序号}_{shell_id}_iso.png   45° 俯视（读墙高 / 进深 / 内岛体积）
##       capture_metadata.json、index.html
##
## ## 拍的是哪一份几何
## 直接实例化 `assets/.../room_instances/expedition_03/rt_*_static_layout.tscn`
## （`scripts/build_whitebox_room_tscn.py` 按模板契约生成的白盒壳）。
##
## **它不是远征03 运行时加载的节点。** 运行时 `TowerDescent3D` 对 flow 关卡走
## **程序化壳体**（`DungeonRoom3D` 按 lane 挖门洞；见 `_append_plan_room_record()` 里
## `procedural_shell` 那段注释：5m 模块壳一墙只能一门，会让 26 条门洞里的 15 条被封死）。
## 两条链共用同一份契约（`size_m` / `variant_footprints` / `wall_lane_table` / 门宽 2.2 m），
## 几何等价；但「运行时一定长这样」本图集**不替它担保** —— 那要跑真关卡验。
## 本图集只回答「白盒壳的形状对不对」。通道壳 `cr_*` 不算房间，不在其中。
##
## ## 为什么两套视角都要
## 一套不够：正俯视没有高度信息（墙在画面上只是 0.3 m 的细条），
## 45° 又必然被前景墙遮住地面。两张并排才能同时回答「轮廓对不对」和「墙在哪」。
##
## ## 为什么 45° 必须裁掉前景墙（南 / 东）
## 墙高 11.9 m、房间进深 25~45 m。45° 俯视时，靠近相机那面墙会遮住自己身后
## `墙高 / tan(45°) = 11.9 m` 进深的地面 —— 25 m 的房间有近一半拍不到。
## 与 `tests/verification/capture_floor98_rooms_45.gd` 同一做法：只隐藏**南 / 东**
## 墙与它们头上的过梁，北 / 西墙保留全高。U 形内岛的墙方向是 `inner`，**不隐藏** ——
## 那正是要看的东西。正俯视不需要裁剪：垂直向下看没有遮挡。
##
## ## 为什么用正交而不是透视
## 正交下各边等比例，缺角 / 内岛能直接用眼睛量；透视会把远端压小，
## 40 m 与 45 m 的差别看不出来。取景尺寸按几何包围盒在相机平面上的实测投影算，
## 大房间不裁、小房间不空。
##
## ## 已知不表达的东西
## 门扇不在房间 TSCN 里（README §四：门由运行时按策略落上去），所以图上看到的是
## **门洞缺口 + 洞上方的过梁**，不是关着的门。这是契约本身的样子，不是漏拍。
## 白盒也不含灯、陈设、陷阱（TSCN `metadata/whitebox_excludes` 明写），图上不会有。

const SHELL_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03"
const OUT_DIR := "res://outputs/expedition03_whitebox_views_20261030"
const VIEW_W := 1600
const VIEW_H := 1200
const MARGIN := 1.10
const CAM_DIST := 200.0

## 两套视角。pitch=90 走固定朝下的旋转（look_at 在正下方会退化，UP 与视线共线），
## pitch=45 走 look_at，水平方向取东南，使房间的西北角朝画面深处。
const VIEWS := [
	{"suffix": "top", "pitch": 90.0, "cutaway": false, "label": "正俯视 90°"},
	{"suffix": "iso", "pitch": 45.0, "cutaway": true, "label": "45° 俯视（南/东墙裁切）"},
]

## 顺序即页码。role 只用于图注 —— 中文角色名是设计页的说法，不进资产契约；
## 尺寸 / 面积 / 端口数一律读 TSCN 根节点 metadata，不在这里重算。
const SHOTS := [
	{"shell": "rt_safe_15x15", "role": "入口安全屋", "group": "房间壳"},
	{"shell": "rt_std_25x25", "role": "标准房", "group": "房间壳"},
	{"shell": "rt_office_60x70", "role": "商店 / 办公房", "group": "房间壳"},
	{"shell": "rt_db_70x50_db_01", "role": "宝箱房 变体 01", "group": "房间壳"},
	{"shell": "rt_db_70x50_db_02", "role": "宝箱房 变体 02", "group": "房间壳"},
	{"shell": "rt_corridor_45x40_l_turn", "role": "枢纽房 L 形", "group": "房间壳"},
	{"shell": "rt_corridor_45x40_u_turn", "role": "枢纽房 U 形", "group": "房间壳"},
	{"shell": "rt_boss_50x40", "role": "首领房", "group": "房间壳"},
	{"shell": "rt_extraction_25x25", "role": "撤离房", "group": "房间壳"},
	{"shell": "rt_bridge_60x50", "role": "跨桥房（本关不接入）", "group": "房间壳"},
	{"shell": "rt_connector_10x30", "role": "连接件 10×30", "group": "连接件"},
	{"shell": "rt_connector_30x10", "role": "连接件 30×10", "group": "连接件"},
]

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _failures: Array[String] = []
var _records: Array = []
## 本关 16 个房间位（`data/level_plans/expedition_03/floors/floor_00.json` 的 `rooms`）。
##
## 为什么不写死在脚本里：房间位是随平面表变的产物。写死一次就是第二个真源 ——
## 表里加了房间，图注还写着 16；表里换了模板，图注仍指向旧壳，且没有任何东西会报错。
var _level_rooms: Array = []
## template_id -> 该模板在本关占用的房间位列表
var _usage_by_template: Dictionary = {}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("需要真实渲染器（headless 拍不到画面）")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_load_level_rooms()
	_build_stage()
	for i in range(SHOTS.size()):
		await _shoot_shell(i, SHOTS[i])
	_finish()


## 读平面表，建立「模板 → 本关房间位」的对照。
func _load_level_rooms() -> void:
	var path := "res://data/level_plans/expedition_03/floors/floor_00.json"
	if not FileAccess.file_exists(path):
		_failures.append("平面表缺失：%s" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_failures.append("平面表解析失败：%s" % path)
		return
	_level_rooms = (parsed as Dictionary).get("rooms", []) as Array
	for room_value in _level_rooms:
		var room := room_value as Dictionary
		var template_id := str(room.get("template_id", ""))
		if not _usage_by_template.has(template_id):
			_usage_by_template[template_id] = []
		(_usage_by_template[template_id] as Array).append({
			"key": str(room.get("key", "")),
			"room_id": str(room.get("room_id", "")),
			"room_type": str(room.get("room_type", "")),
			"size_m": str(room.get("size_m", [])).replace("[", "").replace("]", ""),
			"center_m": str(room.get("center_m", [])).replace("[", "").replace("]", ""),
		})
	print("EXP03_VIEW level_rooms=%d templates=%d" % [_level_rooms.size(), _usage_by_template.size()])


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.115, 0.135)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.74)
	# 白模地面 albedo 0.76 本来就亮。环境光给到 1.0 会把它推到纯白，
	# 于是地面与墙没有明暗差、门洞与过梁全糊成一片（第一版出图就是这个毛病）。
	e.ambient_light_energy = 0.34
	env.environment = e
	_vp.add_child(env)

	# 主光开阴影：墙在地面上的投影是唯一能表达「墙有多高」的线索。
	# 单光会让 90° 阴角全黑，所以补一盏低能量填充光压暗部。
	var key := DirectionalLight3D.new()
	key.light_energy = 0.9
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 260.0
	key.rotation_degrees = Vector3(-52, -38, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-20, 145, 0)
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.5
	_cam.far = 800.0
	_vp.add_child(_cam)
	_cam.current = true


func _shoot_shell(index: int, shot: Dictionary) -> void:
	var shell := str(shot["shell"])
	var scene_path := "%s/%s_static_layout.tscn" % [SHELL_DIR, shell]
	if not ResourceLoader.exists(scene_path):
		_failures.append("缺少壳文件：%s" % scene_path)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("加载失败：%s" % scene_path)
		return

	_holder = Node3D.new()
	_vp.add_child(_holder)
	var room := packed.instantiate() as Node3D
	_holder.add_child(room)
	await _settle(4)

	# 先登记记录再拍。**顺序不能反**：第一版在拍完之后才 append，
	# 而 `_shoot_view` 用 `_records.back()` 回填视图数据 —— 第一个壳时数组还是空的，
	# 于是它的两张图数据全丢，之后每个壳的数据都被写到**上一个**壳名下，整体错位一格
	# （2026-10-30 实测：metadata 里 rt_safe_15x15 的包围盒写着 25.6 m）。
	var base := _record_base(shot, room)
	_records.append(base)
	for view in VIEWS:
		await _shoot_view(index, shot, room, view, base)

	print("EXP03_VIEW shell=%s done=%d" % [shell, _records.size()])
	_holder.queue_free()
	await _settle(2)


func _shoot_view(index: int, shot: Dictionary, room: Node3D, view: Dictionary, rec: Dictionary) -> void:
	var suffix := str(view["suffix"])
	var pitch_target := float(view["pitch"])
	var cutaway := bool(view["cutaway"])

	_restore(room)
	var hidden := 0
	if cutaway:
		hidden = _apply_cutaway(room)
	await _settle(2)

	var box := _visible_bounds(room)
	if box.size == Vector3.ZERO:
		_failures.append("可见几何为空：%s/%s" % [str(shot["shell"]), suffix])
		return

	var aim := box.get_center()
	if pitch_target >= 89.9:
		# 正俯视：用固定旋转。look_at 在视线与 UP 共线时会退化成 NaN。
		# R_x(-90) 把相机局部 +Y 映到世界 -Z，于是画面正上方＝北（-Z）、右侧＝东（+X）。
		_cam.global_position = aim + Vector3(0.0, CAM_DIST, 0.0)
		_cam.rotation_degrees = Vector3(-90, 0, 0)
	else:
		# 45°：水平位移长度 = 竖直位移 ⇒ 俯角正好 45°，方向取东南。
		var horiz := Vector3(1.0, 0.0, 1.0).normalized()
		var up_amount := tan(deg_to_rad(pitch_target))
		_cam.global_position = aim + (horiz * 1.0 / up_amount + Vector3.UP) * CAM_DIST
		_cam.look_at(aim, Vector3.UP)
	await _settle(2)

	# 取景：把包围盒八个角投到相机平面，按实测跨度定正交尺寸。
	# 不用「房间尺寸 ÷ 某系数」硬算 —— 那样大房间会被裁、小房间一半是空。
	var min_uv := Vector2(INF, INF)
	var max_uv := Vector2(-INF, -INF)
	for i in range(8):
		var local := _cam.to_local(box.get_endpoint(i))
		min_uv = min_uv.min(Vector2(local.x, local.y))
		max_uv = max_uv.max(Vector2(local.x, local.y))
	var span_h := max_uv.y - min_uv.y
	var span_w := (max_uv.x - min_uv.x) / (float(VIEW_W) / float(VIEW_H))
	# 正俯视留白更紧：墙厚 0.3 m、门洞 2.2 m 都靠"墙顶断口"表达，
	# 每米像素多一点，断口才看得出来。45° 需要更多留白容纳墙高投影。
	var margin := 1.04 if pitch_target >= 89.9 else MARGIN
	_cam.size = maxf(maxf(span_h, span_w) * margin, 8.0)
	# 包围盒中心未必在投影中心（裁剪后尤其偏），把相机沿自身右/上方向平移补正
	var mid := (min_uv + max_uv) * 0.5
	_cam.global_position += _cam.global_transform.basis.x * mid.x + _cam.global_transform.basis.y * mid.y

	# 参考底板：比包围盒大一圈、压在最低点下方。
	#
	# ## 为什么必须有（第一版出图才看出来）
	# 非矩形壳的缺角与 U 形内岛**本来就没有地面**，正俯视时那里直接透出画布背景色 ——
	# 与「房间出画了」是同一个颜色，看图的人无法区分"这块没有地面"和"这张图裁掉了"。
	# 垫一块明显比背景亮的灰底板后，三种状态各有颜色：地面（浅）/ 无地面（中灰）/ 画布外（深）。
	# 底板只是拍摄道具，不是房间几何 —— 它挂在 `_holder` 上、不在 `room` 下，
	# 不参与包围盒计算，也不会被写回任何资产。
	#
	# **只给正俯视加**：45° 视角里墙本身就把轮廓画清楚了，没有歧义，
	# 多一块底板反而在画面边缘切出大块灰面，抢掉主体的注意力。
	if pitch_target >= 89.9:
		var plate := MeshInstance3D.new()
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(box.size.x + 20.0, 0.4, box.size.z + 20.0)
		plate.mesh = plate_mesh
		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = Color(0.36, 0.40, 0.46)
		plate_mat.roughness = 1.0
		# **必须 unshaded**：有光照时，墙在底板上的投影会把缺角区压到接近纯黑，
		# 读起来和"空洞"没区别 —— 那正是加底板要解决的事，用受光材质等于自毁目的
		# （2026-10-30 第二版出图踩过）。
		plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plate.material_override = plate_mat
		plate.position = Vector3(box.get_center().x, box.position.y - 0.6, box.get_center().z)
		_holder.add_child(plate)

	await _settle(5)

	var image := _vp.get_texture().get_image()
	if image == null:
		_failures.append("viewport 取图为空：%s/%s" % [str(shot["shell"]), suffix])
		return
	var file := "%02d_%s_%s.png" % [index + 1, str(shot["shell"]), suffix]
	var abs_path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file])
	if image.save_png(abs_path) != OK:
		_failures.append("保存失败：%s" % abs_path)
		return

	var forward := -_cam.global_transform.basis.z
	var pitch := rad_to_deg(asin(absf(forward.normalized().y)))
	if absf(pitch - pitch_target) > 0.5:
		_failures.append("俯角偏离 %.0f°：%s/%s → %.2f°" % [pitch_target, str(shot["shell"]), suffix, pitch])

	(rec)["views"][suffix] = {
		"file": file,
		"image_size": "%dx%d" % [image.get_width(), image.get_height()],
		"pitch_degrees": snappedf(pitch, 0.01),
		"ortho_size_m": snappedf(_cam.size, 0.01),
		"cutaway_walls": hidden,
		"bounds_size_m": str(box.size),
	}
	print("EXP03_VIEW %s/%s pitch=%.2f ortho=%.1f cut=%d" % [
		str(shot["shell"]), suffix, pitch, _cam.size, hidden])


## 契约字段一律读 TSCN 根节点 metadata —— 图注不许自己再算一遍尺寸 / 面积，
## 否则图注与关卡读到的数会各说各话（本工程反复踩过「第二真源」这个坑）。
## 本关占用情况则来自平面表，同样不在这里手写。
func _record_base(shot: Dictionary, room: Node3D) -> Dictionary:
	var template_id := str(room.get_meta("template_id", ""))
	var uses: Array = _usage_by_template.get(template_id, [])
	return {
		"shell_id": str(room.get_meta("shell_id", "")),
		"template_id": template_id,
		"variant": str(room.get_meta("variant", "")),
		"role": str(shot["role"]),
		"group": str(shot["group"]),
		"size_m": str(room.get_meta("size_m", Vector2.ZERO)).replace("[", "").replace("]", ""),
		"footprint_area_m2": str(room.get_meta("footprint_area_m2", "")),
		"footprint_is_rect": str(room.get_meta("footprint_is_rect", "")),
		"connection_port_count": str(room.get_meta("connection_port_count", "")),
		"layout_instance_total": str(room.get_meta("layout_instance_total", "")),
		"level_slot_count": uses.size(),
		"level_slots": uses,
		"views": {},
	}


## 裁掉相机侧（南 / 东）墙与它们头上的过梁；U 形内岛（`inner`）保留。
func _apply_cutaway(room: Node3D) -> int:
	var hidden := 0
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var side := str(mesh_node.get_meta("tower_wall_direction", ""))
		var name_lower := String(mesh_node.name).to_lower()
		var is_side_wall := side == "south" or side == "east"
		var is_side_lintel := name_lower.begins_with("lintel_south") or name_lower.begins_with("lintel_east")
		if is_side_wall or is_side_lintel:
			mesh_node.visible = false
			hidden += 1
	return hidden


func _restore(room: Node3D) -> void:
	for node in room.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = true


func _visible_bounds(room: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if not mesh_node.visible:
			continue
		var aabb := mesh_node.get_aabb()
		for i in range(8):
			var p := mesh_node.global_transform * aabb.get_endpoint(i)
			if not found:
				result = AABB(p, Vector3.ZERO)
				found = true
			else:
				result = result.expand(p)
	return result


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


## 断言：平面表里每一间房都必须能找到对应壳。
##
## 这条会失败才有意义 —— 若模板表新增了房型而白盒壳没跟着生成，
## 图集仍会"全绿出图"，只是悄悄少拍几间房，看的人不会发现。
func _check_every_room_has_shell() -> void:
	for room_value in _level_rooms:
		var room := room_value as Dictionary
		var template_id := str(room.get("template_id", ""))
		var found := false
		for rec in _records:
			if str(rec["template_id"]) == template_id:
				found = true
				break
		if not found:
			_failures.append(
				"房间位 %s 的模板 %s 没有对应白盒壳（漏拍）" % [str(room.get("key", "")), template_id])


func _finish() -> void:
	_check_every_room_has_shell()
	_write_metadata()
	_write_index()
	print("EXP03_WHITEBOX_VIEWS_DONE shells=%d images=%d failures=%d" % [
		_records.size(), _records.size() * VIEWS.size(), _failures.size()])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _write_metadata() -> void:
	var f := FileAccess.open("%s/capture_metadata.json" % OUT_DIR, FileAccess.WRITE)
	if f == null:
		_failures.append("清单写入失败")
		return
	f.store_string(JSON.stringify({
		"level_id": "expedition_03",
		"kind": "whitebox_room_topview_capture",
		"source_scenes": "%s/rt_*_static_layout.tscn" % SHELL_DIR,
		"camera": "orthographic; top = pitch 90° (north up, east right, no cutaway); "
			+ "iso = pitch 45° from south-east with south/east walls and lintels hidden",
		"shells": _records,
		"failures": _failures,
	}, "\t"))
	f.close()


## 第一屏：本关 16 个房间位逐条对照到壳。回答「我数得出 16 间房，图上怎么只有 12 张」——
## 因为壳按 (模板 × 轮廓变体) 去重，8 间标准房共用同一份壳。这个映射不能靠人脑记。
func _slot_table_html() -> String:
	var rows := ""
	var index := 0
	for room_value in _level_rooms:
		var room := room_value as Dictionary
		index += 1
		var template_id := str(room.get("template_id", ""))
		# 找该模板对应的壳（可能两份：变体）；变体在本关不入平面表，由装配器按开门方向选
		var shells: Array[String] = []
		for rec in _records:
			if str(rec["template_id"]) == template_id:
				shells.append(str(rec["shell_id"]))
		var shell_html := ""
		for shell_id in shells:
			shell_html += "<code>%s</code> " % shell_id
		if shells.is_empty():
			shell_html = '<b class="warn">无对应壳</b>'
		rows += (
			"<tr><td class=\"num\">%d</td><td><code>%s</code></td><td>%s</td>"
			+ "<td>%s</td><td class=\"num\">%s</td><td class=\"num\">%s</td><td>%s</td></tr>"
		) % [
			index, str(room.get("key", "")), str(room.get("room_type", "")),
			template_id,
			str(room.get("size_m", [])).replace("[", "").replace("]", ""),
			str(room.get("center_m", [])).replace("[", "").replace("]", ""),
			shell_html,
		]
	var shell_count := _records.size()
	# 真正被 16 间房用到的壳有多少份。图和表要能对上账，这个数不能手写。
	var used_shell_count := 0
	var spare_names: Array[String] = []
	for rec in _records:
		if int(rec["level_slot_count"]) > 0:
			used_shell_count += 1
		else:
			spare_names.append(str(rec["shell_id"]))
	var spare_text := ""
	if not spare_names.is_empty():
		spare_text = "<br>此外，剩 %d 份本关未接入：%s" % [
			spare_names.size(), ", ".join(spare_names)]
	# 分段拼接：GDScript 的 `%` 是按字符串片段各自生效的，把 %d 和 %s 分散在
	# 不同片段再只在最后一段取参数，会报 "not all arguments converted"。
	var head := "<h2>本关房间位（%d 间）</h2>" % _level_rooms.size()
	var cap := (
		'<p class="cap">数据源 <code>data/level_plans/expedition_03/floors/floor_00.json</code> 的 '
		+ "<code>rooms</code>。<b>%d 间房只用得到 %d 份壳</b>（按「模板 × 轮廓变体」去重），"
		+ "所以下面图集少于房间数不是漏拍。"
		+ "带两个变体的模板（<code>db_70x50</code>、<code>corridor_45x40</code>）平面表不写变体，"
		+ "由装配器按开门方向选，两份都拍。</p>"
	) % [_level_rooms.size(), used_shell_count]
	cap = cap.replace("</p>", "%s</p>" % spare_text)
	var table := (
		"<table><thead><tr><th>#</th><th>房间位 key</th><th>room_type</th><th>模板</th>"
		+ "<th>尺寸 m</th><th>中心 m</th><th>对应壳</th></tr></thead><tbody>%s</tbody></table>"
	) % rows
	return head + cap + table


func _write_index() -> void:
	var groups := ["房间壳", "连接件"]
	var body := _slot_table_html()
	for group in groups:
		var cards := ""
		var count := 0
		for rec in _records:
			if str(rec["group"]) != group:
				continue
			count += 1
			var views: Dictionary = rec["views"]
			var top: Dictionary = views.get("top", {})
			var iso: Dictionary = views.get("iso", {})
			if top.is_empty() or iso.is_empty():
				continue
			var is_rect := str(rec["footprint_is_rect"]) == "true"
			var shape := "矩形" if is_rect else "非矩形轮廓"
			var shape_cls := "" if is_rect else ' class="warn"'
			var variant := str(rec["variant"])
			var variant_html := "" if variant.is_empty() else " · 变体 <code>%s</code>" % variant
			var slot_count := int(rec["level_slot_count"])
			var use_html := (
				'<span class="tag used">本关 %d 间</span>' % slot_count
				if slot_count > 0
				else '<span class="tag spare">本关未使用</span>'
			)
			# GDScript 的 `%` 只认位置参数（Array），不认 printf 的 `%(name)s`；
			# 这里用 token 替换，避免图注字段一多就数不清顺序。
			var card := (
				'<figure><div class="pair">'
				+ '<a href="{tf}" target="_blank"><img src="{tf}" alt="{shell} 正俯视"></a>'
				+ '<a href="{if}" target="_blank"><img src="{if}" alt="{shell} 45 度"></a>'
				+ "</div>"
				+ "<figcaption><b>{role}</b>"
				+ '<span class="tag">{size} m · {area} m²</span>'
				+ '<span class="tag">{ports} 端口</span>'
				+ "{use}"
				+ "<p{class}>{shape}</p>"
				+ "{variant}<code>{shell}</code></figcaption></figure>"
			)
			card = card.replace("{tf}", str(top["file"]))
			card = card.replace("{if}", str(iso["file"]))
			card = card.replace("{shell}", str(rec["shell_id"]))
			card = card.replace("{role}", str(rec["role"]))
			card = card.replace("{size}", str(rec["size_m"]))
			card = card.replace("{area}", str(rec["footprint_area_m2"]))
			card = card.replace("{ports}", str(rec["connection_port_count"]))
			card = card.replace("{use}", use_html)
			card = card.replace("{class}", shape_cls)
			card = card.replace("{shape}", shape)
			card = card.replace("{variant}", variant_html)
			cards += card
		body += '<h2>%s（%d 份 · 每份两张）</h2><div class="grid">%s</div>' % [group, count, cards]

	var html := """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>远征03 房间白模 · 顶视角（正俯视 + 45°）</title>
<style>
:root{--ink:#16181A;--sub:#5F6569;--line:#D8DBDC;--bg:#EFF0F0;--paper:#fff;--accent:#0E9C86}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.7 "PingFang SC","Microsoft YaHei",system-ui,sans-serif}
header{padding:28px 40px 20px;background:var(--paper);border-bottom:1px solid var(--line)}
h1{margin:0 0 8px;font-size:24px}
.sub{color:var(--sub);font-size:13px;max-width:1080px}
.wrap{padding:6px 40px 70px;max-width:1600px;margin:0 auto}
h2{font-size:17px;margin:34px 0 12px;padding-left:10px;border-left:3px solid var(--accent)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(400px,1fr));gap:18px}
figure{margin:0;background:var(--paper);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--line)}
.pair img{display:block;width:100%;height:auto;background:#1A1E24}
figcaption{padding:10px 12px;font-size:12px;color:var(--sub);line-height:1.9}
figcaption b{color:var(--ink);font-weight:600;display:block;font-size:13px}
.tag{display:inline-block;background:#F1EFE8;border:1px solid var(--line);border-radius:20px;padding:0 7px;font-size:11px;color:#444441;margin:0 4px 0 0}
figcaption p{margin:2px 0;line-height:1.5}
figcaption code{font-size:10.5px;color:#9AA0A4;word-break:break-all}
.warn{color:#B4531F;font-weight:600}
.note{background:#FAEEDA;border:1px solid #EFC98A;border-radius:10px;padding:12px 16px;font-size:12.5px;line-height:1.8;margin:14px 0 0}
.note b{color:#7A3E0B}
.legend{display:flex;gap:22px;margin:12px 0 0;font-size:12px;color:var(--sub);flex-wrap:wrap}
.tag.used{background:#E4F4EF;border-color:#A9D9CC;color:#0B6E5E}
.tag.spare{background:#F6EDE6;border-color:#E3C7B3;color:#8A4B27}
table{width:100%;border-collapse:collapse;background:var(--paper);font-size:12.5px}
th,td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:left}
th{background:#F7F8F9;font-weight:600;font-size:12px;color:#3A3F43}
td code{font-size:11px;color:#7A8085}
td.num{font-variant-numeric:tabular-nums}
tr:last-child td{border-bottom:none}
.cap{font-size:12px;color:var(--sub);margin:0 0 10px}
</style></head><body>
<header><h1>远征03 房间白模 · 顶视角</h1>
<div class="sub">白盒舞台：<code>scripts/build_whitebox_room_tscn.py</code> 按
<code>data/level_plans/expedition_03/</code> 的模板契约生成的 <code>rt_*_static_layout.tscn</code>，
共 12 份壳 × 2 视角，正交相机、取景按几何包围盒实测适配。</div>
<div class="legend"><span><b>左：正俯视 90°</b> — 北朝上、东朝右，无遮挡，读轮廓与门洞</span>
<span><b>右：45° 俯视</b> — 东南取景，南/东墙已裁切，读墙高与内岛体积</span></div>
<div class="note"><b>读图要点：</b>橙字「非矩形轮廓」的几份是缺角与内岛 —— 轮廓问题一眼可辨。<br>
门扇不在房间壳里（由运行时按策略落上去），所以看到的是<b>门洞缺口 + 洞上方过梁</b>，不是关着的门。
白盒也不含灯、陈设、陷阱（TSCN 的 <code>whitebox_excludes</code> 明写）。<br>
<b>一条边界必须说清楚：</b>这些壳是白盒阶段的产物，<b>运行时并不加载它们</b> —— 远征03 走
<code>DungeonRoom3D</code> 的程序化壳体（5m 模块壳一墙只能一门，会把 26 条门洞里的 15 条封死）。
两条链共用同一份契约，几何等价；但「运行时一定长这样」这张图不能担保，那要跑真关卡验。</div>
</header>
<div class="wrap">
{BODY}
</div></body></html>
""".replace("{BODY}", body)
	var f := FileAccess.open("%s/index.html" % OUT_DIR, FileAccess.WRITE)
	if f == null:
		_failures.append("index.html 写入失败")
		return
	f.store_string(html)
	f.close()
