extends Node3D
## 保安僵尸眼高扫描（用已修正的渲染方式：关物理、排除枪网格、烧入刻度线）。
## 用法：godot --path . res://tools/probe_ranged_eye_scan.tscn -- <out.png>

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const KIND := "ranged_caster_strong"
const MODEL_HEIGHT := 1.857143

## 候选高度比例 + 颜色。
const CANDIDATES := [
	{"ratio": 0.52, "color": Color(1.0, 0.12, 0.12), "name": "红0.52"},
	{"ratio": 0.56, "color": Color(1.0, 0.55, 0.05), "name": "橙0.56"},
	{"ratio": 0.60, "color": Color(1.0, 1.0, 0.10), "name": "黄0.60"},
	{"ratio": 0.64, "color": Color(0.15, 1.0, 0.25), "name": "绿0.64"},
	{"ratio": 0.68, "color": Color(0.15, 0.90, 1.0), "name": "青0.68"},
	{"ratio": 0.72, "color": Color(0.30, 0.50, 1.0), "name": "蓝0.72"},
]
const HALF_X := 0.155

var _cam: Camera3D
var _out := "res://outputs/ranged_eye_scan.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_build_env()

	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.apply_profile(KIND)
	await get_tree().process_frame
	await get_tree().process_frame

	# 用已生效的配方算头部最前 z（作为眼点的 z 基准）。
	var socket := MonsterVariants.eye_socket_for(KIND)
	var front := -0.6389  # 实测值（同上一次探针读数）
	var eye_z := front
	var total := enemy.scale.y

	var marker_root := Node3D.new()
	enemy.add_child(marker_root)
	var v_lo := 0.44
	var v_hi := 0.80
	for c in CANDIDATES:
		var ratio := float(c["ratio"])
		var y := float(MODEL_HEIGHT) * ratio
		_marker(marker_root, Vector3(-HALF_X, y, eye_z), c["color"])
		_marker(marker_root, Vector3(HALF_X, y, eye_z), c["color"])
		print("[scan] %s y=%.4f" % [str(c["name"]), y])

	# 正交相机取景（怪局部 → 世界只需乘 scale 并加怪位置）。
	var focus_local := Vector3(0.0, float(MODEL_HEIGHT) * 0.60, eye_z)
	var focus := enemy.global_transform * focus_local
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = (v_hi - v_lo) * float(MODEL_HEIGHT) * total
	_cam.position = Vector3(focus.x, focus.y, focus.z - 2.0)
	_cam.look_at(Vector3(focus.x, focus.y, focus.z), Vector3.UP)

	var img := await _shot()
	# 烧刻度线（每 0.04 一条，怪局部空间）。
	var mid := img.get_width() / 2
	var half_w := int(float(img.get_width()) * 0.28)
	var tick := v_lo
	while tick <= v_hi + 0.0001:
		var world := enemy.global_transform * Vector3(0.0, float(MODEL_HEIGHT) * tick, eye_z)
		var px := _cam.unproject_position(world)
		_draw_hline(img, int(round(px.y)), mid - half_w, mid + half_w, Color(1.0, 1.0, 1.0, 0.7), 1)
		print("[scan] 刻度 ratio=%.2f y=%.4f row=%d" % [tick, float(MODEL_HEIGHT) * tick, int(round(px.y))])
		tick += 0.04

	var path := ProjectSettings.globalize_path(_out)
	var err := img.save_png(path)
	print("[scan] saved err=%d -> %s" % [err, path])
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


func _marker(parent: Node3D, position: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.017
	mesh.height = 0.034
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
	env.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.ambient_light_energy = 1.0
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
	for i in range(4):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
