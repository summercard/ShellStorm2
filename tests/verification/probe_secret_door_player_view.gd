extends Node

## 一次性探针：**用玩家自己的相机和手电**拍暗门 —— 复现主人"进游戏看不见"的真实观感。
##
## 与 `probe_secret_door_shot` 的区别：那个相机自带补光，只能证明"几何在那儿"；
## 这个不挂任何补光，只用玩家手电（`PlayerFlashlight3D`，默认 `start_enabled=false`），
## 因此能回答"玩家眼睛到底看不看得见"。
##
## 用法：
##   SS2_PV_FLASHLIGHT=1 godot --path . res://tests/verification/probe_secret_door_player_view.tscn
## 产物：`outputs/secret_door_shots/player_<site>_light<0|1>.png`

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
## 默认种子；`SS2_SEED` 可覆盖成**玩家那一局**的种子。
const DEFAULT_SEED := 77001199
const OUT_DIR := "res://outputs/secret_door_shots"
## 站在门前多远（m）。玩家实际就是这么看墙的。
var stand_back_m := 4.2  # 可用 SS2_PV_BACK 覆盖

var _branch: Node = null
var _tower: Node = null


func _ready() -> void:
	var back := OS.get_environment("SS2_PV_BACK")
	if not back.is_empty():
		stand_back_m = float(back)
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	var seed_env := OS.get_environment("SS2_SEED")
	tower.run_seed_override = int(seed_env) if not seed_env.is_empty() else DEFAULT_SEED
	print("探针种子=%d" % tower.run_seed_override)
	_tower = tower
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	_branch = tower.get_node_or_null("SecretBranches")
	var player := tower.get_node_or_null("Player3D")
	if _branch == null or player == null:
		print("PLAYER_VIEW_MISS branch=%s player=%s" % [str(_branch), str(player)])
		get_tree().quit(0)
		return
	_hide_ui(tower)
	# 对照用：`SS2_PV_NOLIGHT=1` 把板缝透光关掉 = 改造前的样子。
	if OS.get_environment("SS2_PV_NOLIGHT") == "1":
		var off := 0
		for node in tower.find_children("*", "OmniLight3D", true, false):
			if str(node.name) == "LeakLight":
				(node as OmniLight3D).visible = false
				off += 1
		print("对照：关掉 %d 盏板缝透光" % off)

	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		print("PLAYER_VIEW_MISS 玩家没有 Camera3D")
		get_tree().quit(0)
		return
	print("")
	print("=== 玩家手电：节点=%s 默认开启=%s 射程=%.1f 能量=%.1f 角=%.0f° ===" % [
		"有" if flashlight != null else "无",
		str(flashlight.get("start_enabled")) if flashlight != null else "-",
		float(flashlight.get("beam_range")) if flashlight != null else 0.0,
		float(flashlight.get("beam_energy")) if flashlight != null else 0.0,
		float(flashlight.get("beam_angle_degrees")) if flashlight != null else 0.0,
	])

	var snapshot := _branch.call("debug_snapshot") as Dictionary
	var sites: Array = snapshot.get("sites", []) as Array
	var only := OS.get_environment("SS2_PV_ONLY")
	for value in sites:
		var site := value as Dictionary
		var site_id := str(site.get("site_id", ""))
		if not only.is_empty() and site_id != only:
			continue
		var pos := site.get("position", Vector3.ZERO) as Vector3
		var normal := site.get("normal", Vector3.FORWARD) as Vector3
		if normal == Vector3.ZERO:
			continue
		var door_node := _branch.get_node_or_null("SecretDoor_%s" % site_id) as Node3D
		if door_node != null:
			var leak := door_node.get_node_or_null("LeakLight") as OmniLight3D
			print("  [门] %s pos=(%.1f, %.1f, %.1f) 透光灯=%s 能量=%.2f" % [
				site_id, door_node.global_position.x, door_node.global_position.y, door_node.global_position.z,
				"有" if leak != null else "无", leak.light_energy if leak != null else 0.0,
			])
		for want_light in [false, true]:
			if flashlight != null:
				flashlight.call("set_light_enabled", want_light)
			await _frame(player, camera, pos, normal, "%s_light%d" % [site_id, 1 if want_light else 0])

	print("")
	print("SECRET_DOOR_PLAYER_VIEW_OK 位点=%d" % sites.size())
	get_tree().quit(0)


## 把玩家挪到门前、面向墙，冻住它的逻辑（否则手电和相机每帧被重写），再抓一帧。
##
## 相机不自用玩家的那台：`Player3D` 的 Camera3D 在 freeze 后保留的是它自己的局部姿态
## （实测架得比人高得多，拍到的是俯视地板）。这里自己在**玩家眼睛位置**放一台，
## 视角与光都还是玩家的（手电挂在玩家身上）—— 观感一致，且不用跟相机装配打架。
func _frame(player: Node3D, camera: Camera3D, door_pos: Vector3, normal: Vector3, label: String) -> void:
	# `normal` 是**朝房间外**的法线，玩家站在房间里 = 往 -normal 退；
	# 看向门 = 朝 +normal 看。（第一次写成 +normal 退，直接站到墙外去了。）
	var look_dir := normal
	var yaw := atan2(-look_dir.x, -look_dir.z)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = door_pos - normal * stand_back_m
	player.global_position.y = 0.0
	player.global_rotation = Vector3(0.0, yaw, 0.0)
	camera.current = false

	var eye := Camera3D.new()
	eye.fov = 74.0
	eye.near = 0.05
	eye.far = 400.0
	add_child(eye)
	eye.global_position = player.global_position + Vector3(0.0, 1.62, 0.0)
	eye.look_at(door_pos + Vector3(0.0, 1.2, 0.0), Vector3.UP)
	eye.current = true
	print("    玩家=(%.1f, %.1f, %.1f) 眼=(%.1f, %.1f, %.1f) 门=(%.1f, %.1f, %.1f)" % [
		player.global_position.x, player.global_position.y, player.global_position.z,
		eye.global_position.x, eye.global_position.y, eye.global_position.z,
		door_pos.x, door_pos.y, door_pos.z,
	])

	for _i in range(4):
		eye.current = true
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var path := "%s/player_%s.png" % [OUT_DIR, label]
	var err := image.save_png(path)
	print("  %s %s" % ["✔" if err == OK else "✘", path])
	eye.queue_free()


func _hide_ui(root: Node) -> void:
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in root.find_children("*", "Control", true, false):
		(node as Control).visible = false
