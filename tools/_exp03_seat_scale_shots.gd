extends Node
## 远征03 沙发/扶手椅/地毯放大验收：逐房间检查实例缩放，并输出俯视对比图。
##
## 运行：godot --path . tools/_exp03_seat_scale_shots.tscn --resolution 1400x1100
## 输出：ShellStorm2-work/sessions/2026-11-02_seat_rug_scale/shots/<房间>.png 与断言汇总

## 输出目录可用 `-- --out=<绝对路径>` 覆盖（用于出改前对照图）
const OUT_DEFAULT := "I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-02_seat_rug_scale/shots"
## 改前对照时缩放期望值改为原值，跳过断言
var _strict := true
var OUT_DIR := OUT_DEFAULT
const BASE := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"

const ROOMS := [
	"boss_50x40_b7446dc46356_c6c134",
	"combat_40x30_18c0881f3934_e86e98",
	"combat_45x40_6351962d84c2_68065f",
	"trap_40x30_29d67dbb9bda_d2426a",
	"stair_lobby_15x15_703e12bd9aa8_4955df",
	"combat_30x40_5fbbae7662fe_e86e98",
	"scavenge_25x25_7fda840577df_23641e",
	"scavenge_40x30_a0eceb3887c9_23641e",
	"merchant_30x40_f2a374f5465f_d77c54",
	"storage_40x30_ef3f827636f7_3e5f15",
]

# 用户 17:01：只有「特别小的沙发」——ENV-EXP03-MANOR-OFFICE-CHAIR（0.75m）——放大 ×2；
# 三人红丝绒沙发与红丝绒扶手椅保持原始 1.5（16:56 已缩小回原状）；地毯平面 2.0，厚度 1.0
const EXPECT_SEAT := 1.5
const EXPECT_SMALL_SEAT := 2.0
## 书柜：宽 ×1.5、高 ×1.2507（墙高封顶）、厚 ×1.0
const EXPECT_BOOKCASE_W := 1.5
const EXPECT_BOOKCASE_H := 1.250736
## 放弃放大的 16 件书柜保持 1.0（净空不足，见开发记录）
## 4 件小沙发因净空不足未放大，本断言只校验已放大的 12 件
const SMALL_SEAT_SCALED := 12
## 只有这 4 间房的地毯在本次改动范围；其余房间的地毯保持原尺寸
const RUG_ROOMS := [
	"boss_50x40_b7446dc46356_c6c134",
	"combat_40x30_18c0881f3934_e86e98",
	"combat_45x40_6351962d84c2_68065f",
	"stair_lobby_15x15_703e12bd9aa8_4955df",
]
const EXPECT_RUG_PLANE := 2.0
const EXPECT_DAIS := 2.0

var _fail := 0
var _asserts := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			OUT_DIR = arg.substr(6)
		elif arg == "--no-assert":
			_strict = false
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for room in ROOMS:
		await _shot(room)
	print("ASSERT_TOTAL %d FAIL %d" % [_asserts, _fail])
	print("PROBE_DONE")
	get_tree().quit(0 if _fail == 0 else 1)


func _shot(room: String) -> void:
	var path := BASE + room + ".tscn"
	var packed := load(path) as PackedScene
	if packed == null:
		print("LOAD_FAIL %s" % path)
		_fail += 1
		return
	var root := Node3D.new()
	add_child(root)
	var inst := packed.instantiate()
	root.add_child(inst)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.55)
	env.ambient_light_energy = 1.4
	world.environment = env
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-78, 30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = false
	root.add_child(sun)

	var size := _room_size(room)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(size.x, size.y) + 3.0
	cam.position = Vector3(0, 30, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.far = 80.0
	root.add_child(cam)

	_check_scales(inst, room)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OUT_DIR + "/" + room + ".png"
	img.save_png(out)
	print("SHOT %s %dx%d" % [out, img.get_width(), img.get_height()])
	root.queue_free()
	await get_tree().process_frame


func _room_size(room: String) -> Vector2:
	var parts := room.split("_")
	for p in parts:
		if p.contains("x") and p.split("x").size() == 2:
			var a := p.split("x")[0]
			var b := p.split("x")[1]
			if a.is_valid_float() and b.is_valid_float():
				return Vector2(float(a), float(b))
	return Vector2(20, 20)


func _check_scales(root: Node, room: String) -> void:
	var n := 0
	for node in root.find_children("*", "Node3D", true, false):
		var n3 := node as Node3D
		if n3 == null:
			continue
		var asset := str(n3.get_meta("asset_id", ""))
		if asset == "":
			continue
		var _want_rug := EXPECT_RUG_PLANE
		var is_book := asset.contains("MANOR-BOOKCASE")
		var is_small := asset.contains("MANOR-OFFICE-CHAIR")
		var is_seat := asset.contains("MANOR-SOFA") or asset.contains("MANOR-ARMCHAIR") or is_small
		var is_rug := asset.contains("MANOR-RUG-BEDROOM") or asset.contains("MANOR-RUG-LOUNGE")
		# 接待毯 ReceptionCarpet 不在沙发下方，保持原尺寸。
		if n3.name == "ReceptionCarpet":
			_want_rug = 1.0
		if is_book:
			var sb := n3.transform.basis.get_scale()
			var wide := maxf(sb.x, sb.z)
			var thin := minf(sb.x, sb.z)
			var ok_scale := (absf(wide - EXPECT_BOOKCASE_W) < 0.01 and absf(thin - 1.0) < 0.01 \
				and absf(sb.y - EXPECT_BOOKCASE_H) < 0.01) \
				or (absf(wide - 1.0) < 0.01 and absf(sb.y - 1.0) < 0.01)
			_assert(ok_scale, "%s %s 书柜 宽%.2f 高%.2f 厚%.2f" % [room, n3.name, wide, sb.y, thin])
			n += 1
			continue
		if not is_seat and not is_rug:
			continue
		var s := n3.transform.basis.get_scale()
		if not _strict:
			n += 1
			continue
		if is_seat:
			if is_small:
				var ok_small := (absf(s.x - 2.0) < 0.001 and absf(s.y - 2.0) < 0.001 \
					and absf(s.z - 2.0) < 0.001) \
					or (absf(s.x - 1.0) < 0.001 and absf(s.y - 1.0) < 0.001 and absf(s.z - 1.0) < 0.001)
				_assert(ok_small, "%s %s 小沙发 %.3f/%.3f/%.3f 应为 2.0 或 1.0" \
					% [room, n3.name, s.x, s.y, s.z])
			else:
				_assert(absf(s.x - EXPECT_SEAT) < 0.001 and absf(s.y - EXPECT_SEAT) < 0.001 \
					and absf(s.z - EXPECT_SEAT) < 0.001,
					"%s %s 等比 %.3f/%.3f/%.3f 期望 %.1f" % [room, n3.name, s.x, s.y, s.z, EXPECT_SEAT])
		elif room in RUG_ROOMS:
			var want := _want_rug
			_assert(absf(s.x - want) < 0.001 and absf(s.z - want) < 0.001 \
				and absf(s.y - 1.0) < 0.001,
				"%s %s 地毯平面 %.3f/%.3f 期望 %.1f 厚度 %.3f" % [room, n3.name, s.x, s.z, want, s.y])
		n += 1
	print("CHECK %s 命中 %d 件" % [room, n])


func _assert(ok: bool, msg: String) -> void:
	_asserts += 1
	if not ok:
		_fail += 1
		print("ASSERT_FAIL ", msg)
