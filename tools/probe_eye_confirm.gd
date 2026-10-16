extends Node3D
## 眼睛绑点标定的**最终版**：按怪种分别取景 + 候选档，渲染后落成常量。
##
## 为什么按怪种分开取景：胖子僵尸 3.14m 高，而它的头在模型最顶部；
## 用同一比例窗口（0.42~0.70）会拍到衬衫与领带（实测踩过）。
##
## 用法：godot --path . res://tools/probe_eye_confirm.tscn -- <out.png>

## 每只怪：取景窗口（占模型总高）+ 候选高度列表（ratio, 颜色, 名称）。
const PLAN := {
	"melee_chaser": {
		"scene": "res://assets/art/enemies/normal_enemy_3d/melee_chaser/runtime/enm_melee_fungboar01_root_top3d.tscn",
		"view": [0.38, 0.64],
		"candidates": [
			{"ratio": 0.470, "color": Color(1.0, 0.12, 0.12), "name": "红"},
			{"ratio": 0.490, "color": Color(0.15, 1.0, 0.25), "name": "绿"},
			{"ratio": 0.510, "color": Color(0.30, 0.50, 1.0), "name": "蓝"},
			{"ratio": 0.530, "color": Color(1.0, 0.90, 0.10), "name": "黄"},
		],
	},
	"ranged_caster": {
		"scene": "res://assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn",
		"view": [0.38, 0.64],
		"candidates": [
			{"ratio": 0.470, "color": Color(1.0, 0.12, 0.12), "name": "红"},
			{"ratio": 0.490, "color": Color(0.15, 1.0, 0.25), "name": "绿"},
			{"ratio": 0.510, "color": Color(0.30, 0.50, 1.0), "name": "蓝"},
			{"ratio": 0.530, "color": Color(1.0, 0.90, 0.10), "name": "黄"},
		],
	},
	"fat_zombie03": {
		"scene": "res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn",
		"view": [0.66, 0.94],
		"candidates": [
			{"ratio": 0.740, "color": Color(1.0, 0.12, 0.12), "name": "红"},
			{"ratio": 0.780, "color": Color(0.15, 1.0, 0.25), "name": "绿"},
			{"ratio": 0.820, "color": Color(0.30, 0.50, 1.0), "name": "蓝"},
			{"ratio": 0.860, "color": Color(1.0, 0.90, 0.10), "name": "黄"},
		],
	},
}

## 横向半宽（模型根空间 x）。
const HALF_X := 0.085
## 刻度线步长（占模型总高）。
const TICK_STEP := 0.02

var _cam: Camera3D
var _out := "res://outputs/eye_confirm.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_build_env()
	var shots: Array[Image] = []

	for kind in PLAN:
		var plan: Dictionary = PLAN[kind]
		var inst := (load(str(plan["scene"])) as PackedScene).instantiate() as Node3D
		add_child(inst)
		var pts := _raw(inst)
		var box := _bounds(pts)
		var bottom := box.position.y
		var height := box.size.y
		var view: Array = plan["view"]
		var v_lo := float(view[0])
		var v_hi := float(view[1])

		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = (v_hi - v_lo) * height
		var cam_y := bottom + height * (v_lo + v_hi) * 0.5
		_cam.position = Vector3(0.0, cam_y, box.position.z - 2.0)
		_cam.look_at(Vector3(0.0, cam_y, 0.0), Vector3.UP)

		var head_front := _head_front_z(pts, height)
		var marker_root := Node3D.new()
		inst.add_child(marker_root)
		print("[confirm] ======== %s h=%.4f head_front_z=%.4f" % [kind, height, head_front])
		for c in (plan["candidates"] as Array):
			var ratio := float(c["ratio"])
			var y := bottom + height * ratio
			_marker(marker_root, Vector3(-HALF_X, y, head_front - 0.06), c["color"])
			_marker(marker_root, Vector3(HALF_X, y, head_front - 0.06), c["color"])
			print("[confirm]   %s ratio=%.3f y=%.4f" % [str(c["name"]), ratio, y])

		var img := await _shot()
		# 烧刻度线
		var mid := img.get_width() / 2
		var half_w := int(float(img.get_width()) * 0.30)
		var tick := v_lo
		while tick <= v_hi + 0.0001:
			var px := _cam.unproject_position(Vector3(0.0, bottom + height * tick, 0.0))
			_draw_hline(img, int(round(px.y)), mid - half_w, mid + half_w, Color(1.0, 1.0, 1.0, 0.6), 1)
			tick += TICK_STEP
		shots.append(img)
		inst.queue_free()
		await get_tree().process_frame

	var sheet := _compose(shots, 3, 470)
	var path := ProjectSettings.globalize_path(_out)
	var err := sheet.save_png(path)
	print("[confirm] saved err=%d -> %s" % [err, path])
	get_tree().quit(0 if err == OK else 3)


func _draw_hline(img: Image, row: int, x0: int, x1: int, color: Color, thickness: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for t in range(thickness):
		var y := row + t
		if y < 0 or y >= h:
			continue
		for x in range(maxi(0, x0), mini(w - 1, x1) + 1):
			img.set_pixel(x, y, color)


## 头部范围内（顶部 45% 高度、|x|<0.45）的全局最前 z。
func _head_front_z(pts: PackedVector3Array, height: float) -> float:
	var box := _bounds(pts)
	var lo := box.position.y + box.size.y * 0.55
	var front := INF
	for p in pts:
		if p.y < lo or absf(p.x) > 0.45:
			continue
		front = minf(front, p.z)
	return -0.48 if front == INF else front


func _raw(inst: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var root_inv := inst.global_transform.affine_inverse()
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or str(mi.name).begins_with("ProbeMarker"):
			continue
		var xform := root_inv * mi.global_transform
		for surface in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			for v in (verts as PackedVector3Array):
				out.append(xform * v)
	return out


func _marker(parent: Node3D, position: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.014
	mesh.height = 0.028
	mesh.radial_segments = 12
	mesh.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.name = "ProbeMarker"
	node.mesh = mesh
	parent.add_child(node)
	node.position = position


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.87, 0.92)
	env.ambient_light_energy = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-88.0, 0.0, 0.0)
	light.light_energy = 1.0
	add_child(light)
	_cam = Camera3D.new()
	add_child(_cam)


func _shot() -> Image:
	for i in range(3):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _compose(shots: Array[Image], columns: int, cell: int) -> Image:
	if shots.is_empty():
		return Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rows := int(ceil(float(shots.size()) / float(columns)))
	var sheet := Image.create(cell * columns, cell * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.06, 0.08))
	for index in range(shots.size()):
		var img := shots[index]
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var s := minf(float(cell) / float(img.get_width()), float(cell) / float(img.get_height()))
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_BILINEAR)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(
			(index % columns) * cell + (cell - img.get_width()) / 2,
			(index / columns) * cell + (cell - img.get_height()) / 2
		))
	return sheet


func _bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box
