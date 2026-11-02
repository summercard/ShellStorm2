extends Node
## 斜视角检查：放大后的沙发/扶手椅是否高出 2.8m 墙顶。
##
## 运行：godot --path . tools/_exp03_seat_oblique.tscn

const OUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-02_seat_rug_scale/oblique"
const BASE := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"
const ROOMS := [
	"storage_40x30_ef3f827636f7_3e5f15",
	"combat_30x40_5fbbae7662fe_e86e98",
]

const WALL_TOP := 2.8


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for room in ROOMS:
		await _shot(room)
	print("OBLIQUE_DONE")
	get_tree().quit(0)


func _shot(room: String) -> void:
	var packed := load(BASE + room + ".tscn") as PackedScene
	var root := Node3D.new()
	add_child(root)
	root.add_child(packed.instantiate())

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.66)
	env.ambient_light_energy = 1.5
	world.environment = env
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = false
	root.add_child(sun)

	var size := _room_size(room)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(size.x * 0.42, size.x * 0.52, size.y * 0.62)
	cam.look_at_from_position(cam.position, Vector3(0, 0.8, 0))
	cam.far = 200.0
	root.add_child(cam)

	_report(room, root)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + room + ".png")
	print("SHOT ", OUT_DIR + "/" + room + ".png")
	root.queue_free()
	await get_tree().process_frame


func _report(room: String, root: Node) -> void:
	var tallest := 0.0
	var who := ""
	for node in root.find_children("*", "Node3D", true, false):
		var n3 := node as Node3D
		if n3 == null:
			continue
		var asset := str(n3.get_meta("asset_id", ""))
		if not (asset.contains("MANOR-SOFA") or asset.contains("MANOR-ARMCHAIR") \
			or asset.contains("MANOR-OFFICE-CHAIR")):
			continue
		var top := n3.global_position.y + 1.09 * n3.transform.basis.get_scale().y
		if top > tallest:
			tallest = top
			who = n3.name
	print("HEIGHT %s 最高 %s = %.3f m（墙顶 %.1f m，%s）"
		% [room, who, tallest, WALL_TOP, "超高" if tallest > WALL_TOP + 0.001 else "正常"])


func _room_size(room: String) -> Vector2:
	for p in room.split("_"):
		var s := p.split("x")
		if s.size() == 2 and s[0].is_valid_float() and s[1].is_valid_float():
			return Vector2(float(s[0]), float(s[1]))
	return Vector2(20, 20)
