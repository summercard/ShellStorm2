extends Node3D
## 换角色（clip 装配）**真渲染取证** · 只读工程。
##
## 数据探针能证明「骨骼在动」，证明不了**看起来对不对**：枪是否握在手里、
## 脚是否踩在地上、环/挂件位置是否合理、缩放是否差一档。这一张网格图就是目视证据。
##
## ⚠ **必须不加 `--headless`**：headless 下 SubViewport 没有可读渲染目标，
## `get_texture().get_image()` 返回 null。正确命令：
##   godot --path . --scene res://tools/ss2_clip_avatar_render.tscn
## 因此它不进 CI 门禁，只是需要人眼确认时的取证工具。
##
## 为什么直接实例化 `Player3D.tscn` 而不是复用 `Player3DStateGallery`：
## 画廊的 `_physics_process` 每帧把 `player.global_position` 锚回世界原点，
## 多格并排会被全部拉回同一处重叠；它还会自带 NPC 与 UI 面板。这里只要角色。

const OUT_PATH := "res://outputs/verification/ss2_clip_avatar_lineup.png"
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const CELL_W := 430
const CELL_H := 640
const CELL_PX_PER_M := 100.0

## 每格一组状态脚本。`settle` = 先让动画自己跑多少帧再拍（取有代表性的相位）。
## 字段：
##   move   —— 非空则 set_test_move_direction 朝该方向走
##   equip  —— 先装这把武器（gun_id 或近战 assembly_id）
##   action —— 额外动作，取值见下方 _apply_action
const SHOTS := [
	{"label": "1_idle_unarmed", "move": Vector3.ZERO, "equip": "", "action": "", "settle": 50},
	{"label": "2_walk_sidearm", "move": Vector3(0, 0, -1), "equip": "bp_pistol", "action": "", "settle": 70},
	{"label": "3_run_sidearm", "move": Vector3(0, 0, -1), "equip": "bp_pistol", "action": "", "settle": 130},
	{"label": "4_fire_sidearm", "move": Vector3(0, 0, -1), "equip": "bp_pistol", "action": "fire", "settle": 84},
	{"label": "5_reload_sidearm", "move": Vector3.ZERO, "equip": "bp_pistol", "action": "reload", "settle": 30},
	{"label": "6_idle_longgun", "move": Vector3.ZERO, "equip": "bp_rifle", "action": "", "settle": 50},
	{"label": "7_walk_longgun", "move": Vector3(0, 0, -1), "equip": "bp_rifle", "action": "", "settle": 70},
	{"label": "8_melee_bat", "move": Vector3.ZERO, "equip": "bp_baseball_bat", "action": "melee", "settle": 26},
	{"label": "9_hurt", "move": Vector3.ZERO, "equip": "bp_pistol", "action": "hurt", "settle": 14},
	{"label": "10_dead", "move": Vector3.ZERO, "equip": "bp_pistol", "action": "dead", "settle": 40},
	{"label": "11_dash", "move": Vector3(0, 0, -1), "equip": "bp_pistol", "action": "dash", "settle": 9},
	{"label": "12_locked", "move": Vector3.ZERO, "equip": "bp_pistol", "action": "locked", "settle": 50},
]

const CAM_HEIGHT := 0.95
const CAM_DISTANCE := 9.0
const CAM_PITCH_DEG := -5.0
const SLOT_SPACING := 2.05
const VIEW_H_M := 2.60

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _players: Array[Node3D] = []
var _lines: Array[String] = []
var _cell_index := 0
var _settle_left := 0
var _frames := 0
var _done := false


func _say(line: String) -> void:
	_lines.append(line)
	print("SSCR| " + line)


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(CELL_W * SHOTS.size(), CELL_H)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.own_world_3d = true
	add_child(_viewport)

	_stage = Node3D.new()
	_viewport.add_child(_stage)

	_build_environment()
	_build_camera()
	_build_cells()
	if _players.is_empty():
		_say("FAIL 没有建出任何格子")
		get_tree().quit(1)
		return
	_say("格子数=%d" % _players.size())
	_settle_left = int(SHOTS[0]["settle"])


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0d1218")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c2d6ec")
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_stage.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 22.0, 0.0)
	key.light_energy = 1.30
	key.light_color = Color("#fff4e4")
	_stage.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14.0, 200.0, 0.0)
	rim.light_energy = 0.90
	rim.light_color = Color("#8ec5ff")
	_stage.add_child(rim)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(SHOTS.size()) * SLOT_SPACING + 20.0, 30.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.075, 0.115, 0.135)
	mat.roughness = 0.85
	plane.material = mat
	ground.mesh = plane
	_stage.add_child(ground)

	## 每格脚下一个橙色方块（边长 0.30 m）：脚是否踩地、是否陷进地面，一眼可读。
	for index in range(SHOTS.size()):
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.30, 0.010, 0.30)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.95, 0.42, 0.12)
		mm.emission_enabled = true
		mm.emission = Color(0.9, 0.35, 0.06)
		mm.emission_energy_multiplier = 1.2
		box.material = mm
		marker.mesh = box
		marker.position = Vector3(_slot_x(index), 0.005, 0.0)
		_stage.add_child(marker)


func _slot_x(index: int) -> float:
	return (float(index) - float(SHOTS.size() - 1) * 0.5) * SLOT_SPACING


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = VIEW_H_M
	_camera.near = 0.05
	_camera.far = 60.0
	_camera.position = Vector3(0.0, CAM_HEIGHT, -CAM_DISTANCE)
	_camera.rotation_degrees = Vector3(CAM_PITCH_DEG, 180.0, 0.0)
	_camera.current = true
	_stage.add_child(_camera)
	_say("相机 正交高=%.2f m 可见宽=%.2f m" % [
		VIEW_H_M, VIEW_H_M * float(CELL_W * SHOTS.size()) / float(CELL_H)])


func _build_cells() -> void:
	for index in range(SHOTS.size()):
		var shot: Dictionary = SHOTS[index]
		## 每格一块**实体地板**。只放视觉地面的话，角色永远「不在着地」⇒
		## 状态机一直停在 falling，所有格子拍出来都是同一个下坠姿势（首版实测）。
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 1
		floor_body.collision_mask = 0
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(SLOT_SPACING * 0.94, 0.4, 3.0)
		floor_shape.shape = floor_box
		floor_shape.position = Vector3(_slot_x(index), -0.2, 0.0)
		floor_body.add_child(floor_shape)
		_stage.add_child(floor_body)

		var player: Node3D = PLAYER_SCENE.instantiate()
		player.position = Vector3(_slot_x(index), 0.05, 0.0)
		_stage.add_child(player)
		## 关掉玩法：不参与战斗。放在入树之后设，避免被 `_ready()` 的默认值顶掉。
		player.set("combat_enabled", false)
		var inner_cam := _find_first(player, "Camera3D") as Camera3D
		if inner_cam != null:
			inner_cam.current = false
		_players.append(player)
		_apply_setup(index)
		_say("格 %d [%s] equip=%s move=%s action=%s settle=%d" % [
			index, str(shot["label"]),
			str(shot["equip"]) if not str(shot["equip"]).is_empty() else "(默认)",
			str(shot["move"]), str(shot["action"]) if not str(shot["action"]).is_empty() else "-",
			int(shot["settle"])])


func _apply_setup(index: int) -> void:
	var shot: Dictionary = SHOTS[index]
	var player := _players[index]
	player.call("set_input_locked", false)
	var equip := str(shot["equip"])
	if not equip.is_empty():
		var ok: bool = player.call("equip_weapon", equip, "mod_bullet_standard")
		_say("   格 %d equip_weapon(%s) -> %s" % [index, equip, str(ok)])
	var move: Vector3 = shot["move"]
	if move != Vector3.ZERO:
		player.call("set_test_move_direction", move)
	var action := str(shot["action"])
	if not action.is_empty():
		_apply_action(index, action)


func _apply_action(index: int, action: String) -> void:
	var player := _players[index]
	var machine := player.get("_state_machine") as StateMachine
	match action:
		"fire":
			var weapon: Variant = player.get("weapon")
			if weapon != null:
				var reloading: bool = weapon.call("is_reloading")
				if reloading:
					weapon.call("cancel_reload")
				var fired: Variant = weapon.call("try_fire", player.get("aim_direction"), player)
				_say("   格 %d try_fire -> %s" % [index, str(fired)])
		"reload":
			var weapon2: Variant = player.get("weapon")
			if weapon2 != null:
				var magazine: int = int(weapon2.get("magazine_size"))
				weapon2.set("current_ammo", maxi(0, magazine - 3))
				weapon2.emit_signal("ammo_changed", maxi(0, magazine - 3), magazine)
				var started: Variant = weapon2.call("request_reload")
				_say("   格 %d request_reload -> %s" % [index, str(started)])
		"melee":
			player.set("combat_enabled", true)
			var started_melee: Variant = player.call("request_melee_attack")
			_say("   格 %d request_melee_attack -> %s" % [index, str(started_melee)])
		"hurt":
			player.set("is_invincible", false)
			player.set("_invincible_remaining", 0.0)
			player.call("take_damage", 12)
		"dead":
			player.set("is_invincible", false)
			player.set("_invincible_remaining", 0.0)
			player.call("take_damage", int(player.get("max_hp")) + 1)
		"dash":
			player.set("dash_cooldown_timer", 0.0)
			var dashed: Variant = player.call("request_dash")
			_say("   格 %d request_dash -> %s" % [index, str(dashed)])
		"locked":
			player.call("set_input_locked", true)
			if machine != null:
				machine.call("transition_to", "locked", true)


func _find_first(root_node: Node, cls: String) -> Node:
	if root_node == null:
		return null
	if root_node.is_class(cls):
		return root_node
	for child in root_node.get_children():
		var found := _find_first(child, cls)
		if found != null:
			return found
	return null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	## 每帧把角色钉回自己那一格的水平位置：玩家有移动输入，不钉会走飞出画面。
	## **但 Y 必须交给物理** —— 直接写 global_position.y 会把角色每帧从地面拽回 0.05，
	## 状态机读到的落地判定反复失效，角色会一直卡在下坠姿势（首版实测）。
	##
	## 朝向也一并锁成「面朝相机」（aim_yaw = 0 ⇒ visual_root.rotation.y = 0 ⇒ 面朝 -Z，
	## 而相机就在 -Z 侧朝 +Z 看）。不锁的话角色会被移动输入或准星系统转向，
	## 拍出来是侧脸，读不出「枪口是否指向正前方」——那正是本图要回答的问题之一。
	for index in range(_players.size()):
		var player := _players[index]
		var position := player.global_position
		player.global_position = Vector3(_slot_x(index), position.y, 0.0)
		player.set("aim_yaw", 0.0)
		var avatar := player.get_node_or_null("Avatar3D") as Node3D
		if avatar != null:
			var visual_root := avatar.get_node_or_null("VisualRoot") as Node3D
			if visual_root != null:
				visual_root.rotation.y = 0.0
	if _settle_left > 0:
		_settle_left -= 1
		if _settle_left == 0:
			_snapshot_cell(_cell_index)
		return
	if _cell_index < _players.size():
		_snapshot_cell(_cell_index)
		_advance_cell()


func _advance_cell() -> void:
	_cell_index += 1
	if _cell_index < _players.size():
		_settle_left = int(SHOTS[_cell_index]["settle"])
	else:
		_finish()


func _snapshot_cell(index: int) -> void:
	var player := _players[index]
	var avatar := player.get_node_or_null("Avatar3D")
	var clip := ""
	var fallback := ""
	var rate := 0.0
	if avatar != null:
		var motion: Variant = avatar.get("_authored_motion")
		if motion != null:
			clip = str(motion.get("active_clip"))
			fallback = str(motion.get("fallback_reason"))
			rate = float(motion.get("playback_rate"))
	_say("   格 %d 拍前快照 active_clip=%s fallback=%s rate=%.2f" % [index, clip, fallback, rate])


func _finish() -> void:
	if _done:
		return
	_done = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	if image == null:
		printerr("SSCR| FAIL viewport texture 为空（是否误加了 --headless？）")
		get_tree().quit(1)
		return
	var error := image.save_png(OUT_PATH)
	if error != OK:
		printerr("SSCR| FAIL save_png err=%d -> %s" % [error, OUT_PATH])
		get_tree().quit(1)
		return
	_say("SAVED %s (%dx%d)" % [OUT_PATH, image.get_width(), image.get_height()])
	for index in range(_players.size()):
		var shot: Dictionary = SHOTS[index]
		var player := _players[index]
		var avatar := player.get_node_or_null("Avatar3D")
		var height := 0.0
		if avatar != null:
			var motion: Variant = avatar.get("_authored_motion")
			height = float(avatar.get("scale").y)
			_say("格 %d [%s] avatar_scale_y=%.4f motion=%s" % [
				index, str(shot["label"]), height,
				"clip" if motion != null and motion.get_class() == "ClipMotionLibrary3D" else str(motion)])
	_say("==== 结论：出图完成 ====")
	get_tree().quit(0)
