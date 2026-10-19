extends Node

## 一次性视觉探针：**真实远征流程**下打碎暗门木板，连拍木块碎块飞出的瞬间。
##
## 为什么必须带窗口：`--headless` 走 dummy 渲染驱动，`get_viewport().get_texture()`
## 拿不到像素 ⇒ 截图全黑。用法：
##   godot --path . res://tests/verification/probe_board_debris_shot.tscn
## 产物：`outputs/board_debris_shots/*.png`
##
## 三张图各回答一个问题：
##   `before`  打碎前的门板（对照：碎片从这面板上崩出来）
##   `real`    破板 0.30s，**不加任何补光** —— 业主真正会看到的样子
##   `geom`    破板 0.12s，加拍照补光 —— 看清碎块的大小与散开方向
##
## `SS2_BD_SEED` 可换种子；`SS2_BD_NOFILL=1` 连 `geom` 那张也不补光。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const DEFAULT_SEED := 1122239949
const OUT_DIR := "res://outputs/board_debris_shots"
const SHOT_W := 1280
const SHOT_H := 720

## 机位：退到房间里 7.0m（2.38×2.51m 的门在 3.4m 处会顶满画面，看不出碎块散布）、
## 人眼略高 1.90m、看向门洞中部 1.10m。
const EYE_BACK_M := 7.0
const EYE_Y_M := 1.90
const LOOK_Y_M := 1.10

var _branch: Node = null
var _cam: Camera3D = null
var _fill: Array[Light3D] = []


func _ready() -> void:
	get_window().size = Vector2i(SHOT_W, SHOT_H)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		print("BOARD_DEBRIS_SHOT_MISS 远征场景加载失败")
		get_tree().quit(0)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		print("BOARD_DEBRIS_SHOT_MISS 远征场景实例化失败")
		get_tree().quit(0)
		return
	# 真实流程（不是 test_mode）：业主进游戏走的就是这条，门的锁与房间清空状态才作数。
	tower.test_mode = false
	var seed_env := OS.get_environment("SS2_BD_SEED")
	tower.run_seed_override = int(seed_env) if not seed_env.is_empty() else DEFAULT_SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_branch = tower.get_node_or_null("SecretBranches")
	if _branch == null:
		print("BOARD_DEBRIS_SHOT_MISS 没有 SecretBranches 节点")
		get_tree().quit(0)
		return

	var door := _find_door()
	if door == null:
		print("BOARD_DEBRIS_SHOT_MISS 本次种子没刷出暗门")
		get_tree().quit(0)
		return
	var site_id := str(door.get("site_id"))
	door.call("set_locked", false)

	_hide_ui(tower)
	_release_cameras(tower)
	_report_geometry(door, site_id)
	_setup_camera(door)

	print("目标门 site=%s 位置=%s 凸出=%.2fm" % [
		site_id, str(door.global_position), float(_protrude_of(site_id)),
	])
	await _shoot("before")
	_set_fill(false)

	# 打碎：走真实的受击入口（不是直接调 `_break_open`）。
	door.call("take_damage", int(door.get("max_hp")) + 999, false, Vector3.ZERO, 0.0)
	print("已破板：state=%s" % str(door.get("state")))

	await _shoot_at("geom", 0.08, OS.get_environment("SS2_BD_NOFILL") != "1")
	await _shoot_at("real", 0.16, false)
	await _shoot_at("late", 0.55, false)

	print("")
	print("BOARD_DEBRIS_SHOT_OK site=%s 目录=%s" % [site_id, OUT_DIR])
	get_tree().quit(0)


## 优先 S1（业主报的就是 3 号房那扇），没有就取第一扇还在的。
func _find_door() -> Node3D:
	for site_id in ["S1", "S2", "S3", "S4"]:
		var door := _branch.get_node_or_null("SecretDoor_%s" % site_id) as Node3D
		if door != null:
			return door
	return null


func _protrude_of(site_id: String) -> float:
	var snapshot := _branch.call("debug_snapshot") as Dictionary
	for value in snapshot.get("sites", []) as Array:
		var site := value as Dictionary
		if str(site.get("site_id", "")) == site_id:
			return float(site.get("protrude_m", 0.0))
	return 0.0


## 诊断：门的三个轴、位点法线、房间中心在法线的哪一侧、碎块该往哪飞。
##
## 这一层是给"图里看不到东西"兜底的 —— 之前靠猜「碎片飞反了」花了两轮，
## 现在直接把 `-global_basis.z / +global_basis.z` 与房间中心的方向关系打出来。
func _report_geometry(door: Node3D, site_id: String) -> void:
	var basis := door.global_basis
	var room_side := -basis.z
	print("[几何] 门 origin=%s" % str(door.global_position))
	print("[几何] basis.x=%s basis.y=%s basis.z(朝外/墙内?) =%s" % [
		str(basis.x.snapped(Vector3.ONE * 0.001)),
		str(basis.y.snapped(Vector3.ONE * 0.001)),
		str(basis.z.snapped(Vector3.ONE * 0.001)),
	])
	print("[几何] 探针把房间侧当作 -basis.z = %s" % str(room_side.snapped(Vector3.ONE * 0.001)))
	var snapshot := _branch.call("debug_snapshot") as Dictionary
	for value in snapshot.get("sites", []) as Array:
		var site := value as Dictionary
		if str(site.get("site_id", "")) != site_id:
			continue
		print("[几何] 位点 normal=%s wall=%s protrude=%s" % [
			str(site.get("normal", Vector3.ZERO)), str(site.get("wall", "")), str(site.get("protrude_m", 0.0)),
		])
	# 房间中心落在门的哪一侧：门 → 房间中心的方向与 -basis.z 同向 ⇒ 房间在 -Z 侧。
	var rooms: Variant = _branch.get("_room_nodes")
	var room_id := ""
	for value in snapshot.get("sites", []) as Array:
		var site := value as Dictionary
		if str(site.get("site_id", "")) == site_id:
			room_id = str(site.get("room_id", ""))
	if rooms is Dictionary and (rooms as Dictionary).has(room_id):
		var room := (rooms as Dictionary)[room_id] as Node3D
		if room != null:
			var toward_room := room.global_position - door.global_position
			toward_room.y = 0.0
			print("[几何] 房间 %s 中心=%s，门→房间中心=%s，与 -basis.z 点积=%.3f（>0 ⇒ 房间在 -Z 侧）" % [
				room_id, str(room.global_position),
				str(toward_room.snapped(Vector3.ONE * 0.01)),
				toward_room.normalized().dot(room_side.normalized()),
			])


func _setup_camera(door: Node3D) -> void:
	_cam = Camera3D.new()
	_cam.fov = 68.0
	_cam.near = 0.05
	_cam.far = 400.0
	add_child(_cam)
	# 房间侧 = 门局部 -Z（`basis.z` = 位点 outward 法线，房间在它的反侧）。
	# ⚠ 机位必须是 **+ room_side**：写 `- room_side` 会把相机摆到墙外，
	#   拍到的就是"墙外面凸出来一块"，而碎块全飞进房间里被墙挡住（第一版就这么错）。
	var room_side := -door.global_basis.z
	room_side.y = 0.0
	if room_side.length_squared() < 0.0001:
		room_side = Vector3.FORWARD
	room_side = room_side.normalized()
	var target := door.global_position + Vector3(0.0, LOOK_Y_M, 0.0)
	var eye := target + room_side * EYE_BACK_M
	eye.y = door.global_position.y + EYE_Y_M
	_cam.global_position = eye
	_cam.look_at(target, Vector3.UP)
	_cam.current = true
	print("机位=(%.1f, %.1f, %.1f) 房间侧=%s（相机在房间内，退 %.1fm）" % [
		eye.x, eye.y, eye.z, str(room_side), EYE_BACK_M,
	])


## 只给"看清几何"那张用的补光：一盏朝前的聚光 + 一盏近身补光。
## ⚠ 与游戏内真实照明无关；`real` 那张一张都不挂，业主看到的就是那张。
func _set_fill(enabled: bool) -> void:
	for light in _fill:
		if is_instance_valid(light):
			light.queue_free()
	_fill.clear()
	if not enabled or _cam == null:
		return
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.97, 0.92)
	lamp.light_energy = 8.0
	lamp.spot_range = 16.0
	lamp.spot_angle = 50.0
	lamp.spot_attenuation = 0.8
	lamp.shadow_enabled = false
	_cam.add_child(lamp)
	lamp.position = Vector3.ZERO
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.9, 0.93, 1.0)
	fill.light_energy = 2.4
	fill.omni_range = 10.0
	fill.shadow_enabled = false
	_cam.add_child(fill)
	fill.position = Vector3(0.0, 0.3, 0.4)
	_fill.append(lamp)
	_fill.append(fill)


## 破板后等到指定秒数再截（按真实时钟，不假设 60fps）。
## ⚠ 补光必须**提前**挂上：等到点再挂会多花 1~2 帧，而渲染帧率低时（Vulkan 首帧 + 大场景）
##    这两帧就够把 0.55s 的灯烧完 —— 第一版 `real` 那张因此拍成了「灯=0.00」。
func _shoot_at(label: String, seconds: float, with_fill: bool) -> void:
	_set_fill(with_fill)
	var start := Time.get_ticks_usec()
	while true:
		await get_tree().process_frame
		var elapsed := float(Time.get_ticks_usec() - start) / 1000000.0
		if elapsed >= seconds:
			break
	await _shoot("%s_%02dms%s" % [label, int(seconds * 1000.0), "_fill" if with_fill else ""])


func _shoot(label: String) -> void:
	if _cam == null:
		return
	_cam.current = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_width() == 0:
		print("  ✘ %s 取帧失败（渲染驱动拿不到画面）" % label)
		return
	var path := "%s/%s.png" % [OUT_DIR, label]
	var err := image.save_png(path)
	# 顺带报一次特效状态：这张图到底拍到了没。
	var report := _debris_report()
	print("  %s %s  (%dx%d)  %s" % [
		"✔" if err == OK else "✘", path, image.get_width(), image.get_height(), report,
	])


## 当前池里活跃的碎块实例：数量 / 灯能量 / 落地数 / 碎片最低点。
func _debris_report() -> String:
	var pool := get_node_or_null("/root/VfxPool") as VfxPool3D
	if pool == null:
		return "池=无"
	var active: Variant = pool.get("_active")
	if not (active is Dictionary):
		return "池=无"
	var bucket: Variant = (active as Dictionary).get(VfxPool3D.FX01_BOARD_DEBRIS, [])
	var rows := bucket as Array
	if rows.is_empty():
		return "碎块实例=0"
	var effect := rows.back() as VfxEffectBase3D
	if effect == null:
		return "碎块实例=无效"
	var snap: Dictionary = effect.call("get_presentation_snapshot")
	# 碎块世界包围盒 + 它们在不在相机视锥里：图里看不到东西时，这一行能立刻分辨
	# 「碎片飞反了 / 飞太远 / 被门板挡了 / 压根没生成」。
	var box := _piece_box(effect)
	var on_screen := 0
	for child in effect.get_children():
		if child is MeshInstance3D and _cam != null:
			var p := _cam.unproject_position((child as MeshInstance3D).global_position)
			if p.x >= 0.0 and p.x <= float(SHOT_W) and p.y >= 0.0 and p.y <= float(SHOT_H):
				on_screen += 1
	return "碎块实例=%d 灯=%.2f 落地=%d/%d 世界盒=%s 屏内=%d/%d 最大单片=%.2fm" % [
		rows.size(),
		float(snap.get("light_energy", 0.0)),
		int(snap.get("landed_count", 0)),
		int(snap.get("piece_count", 0)),
		box,
		on_screen,
		int(snap.get("piece_count", 0)),
		float(snap.get("max_piece_extent", 0.0)),
	]


func _piece_box(effect: Node3D) -> String:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var found := false
	for child in effect.get_children():
		if child is not MeshInstance3D:
			continue
		var p := (child as MeshInstance3D).global_position
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		found = true
	if not found:
		return "无"
	return "(%.1f,%.1f,%.1f)~(%.1f,%.1f,%.1f)" % [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]


func _hide_ui(root: Node) -> void:
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in root.find_children("*", "Control", true, false):
		(node as Control).visible = false


func _release_cameras(root: Node) -> void:
	for node in root.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
