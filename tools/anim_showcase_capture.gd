extends Node3D
## 一次性工具：把角色全部动画剪辑铺进同一张画面，逐帧渲染，供外部脚本贴标签并合成视频/总览图。
##
## 只读：读 `anim_bunny01_library.json` + bunny01 变体场景，把骨骼帧采样到场景节点后渲染。
## 不进 PlayerAvatar3D 状态机、不写存档、不改玩法。
##
## 用法：
##   godot --path . res://tools/anim_showcase_capture.tscn -- \
##       --layout <layout.json> --out <目录> [--frames 240 --fps 30] [--still] \
##       [--yaw 42 --pitch 8] [--phase 0.4] [--no-weapons]
##
## layout.json：
##   { "cols": 12, "rows": 14, "cell_px": [320, 300],
##     "slots": [ {"row": 0, "col": 0, "clip": "idle"}, ... ] }
##
## 输出：`<out>/f####.jpg`（视频帧）或 `<out>/still.jpg`（静帧），并回写 layout 副本。

const AVATAR_SCENE: PackedScene = preload(
	"res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v008.tscn"
)
const LIBRARY_PATH := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_bunny01_motion/anim_bunny01_library.json"
## 角色视觉高度实测 = 1.50 m（含兔耳；visual_root 不额外缩放时）。
const CHAR_HEIGHT := 1.50
## 角色占格子高度的比例，其余留给动作幅度与标签。
const CELL_FILL := 0.62
## 脚底离格子底边的余量（占格高比例）。
const FOOT_MARGIN := 0.06
## 与 PlayerAvatar3D.BUNNY_LINEAR_SCALE 同值。挂载武器按它缩放，保证与游戏内一致。
const BUNNY_LINEAR_SCALE := 1.5 / 2.475
## 静帧取样相位：一次性动作取中段，循环动作取代表性相位。
const STILL_PHASE_ONESHOT := 0.42
const STILL_PHASE_LOOP := 0.30
const GUNS := {
	"sidearm": "res://assets/art/weapons/weapon_3d/runtime/hair_dryer/wpn_hair_dryer_root_top3d_v001.tscn",
	"longgun": "res://assets/art/weapons/weapon_3d/runtime/broom_rifle/wpn_broom_rifle_root_top3d_v001.tscn",
	"machinegun": "res://assets/art/weapons/weapon_3d/runtime/water_tank_blaster/wpn_water_tank_blaster_root_top3d.tscn",
}
const GUN_FALLBACK := "res://assets/art/weapons/weapon_3d/runtime/broom_rifle/wpn_broom_rifle_root_top3d_v001.tscn"
const MELEE := {
	"axe": "res://assets/art/weapons/melee_3d/wpn_melee_waraxe_root_top3d_v001.tscn",
	"bat": "res://assets/art/weapons/melee_3d/wpn_melee_baseball_bat_root_top3d_v001.tscn",
	"blade": "res://assets/art/weapons/melee_3d/wpn_melee_greatblade_root_top3d_v001.tscn",
}
const WEAPON_SOCKET_REST := Vector3(0.0, 0.3939394, -0.2181818)

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _library: Dictionary
var _layout: Dictionary
var _entries: Array[Dictionary] = []
var _out_dir := "user://anim_showcase"
var _layout_path := ""
var _frames := 240
var _fps := 30
var _still := false
var _still_phase := -1.0
var _use_weapons := false
var _avatar_yaw := 26.0
var _yaw := 0.0
var _pitch := 0.0
var _cols := 1
var _rows := 1
var _cell_px := Vector2i(320, 300)
var _cell_h := 2.0
var _cell_w := 2.0


func _ready() -> void:
	_parse_args()
	_library = _load_json(LIBRARY_PATH)
	_layout = _load_json(_layout_path)
	if _library.is_empty() or _layout.is_empty():
		printerr("[showcase] 动画库或布局文件读取失败")
		get_tree().quit(2)
		return
	_cols = int(_layout.get("cols", 1))
	_rows = int(_layout.get("rows", 1))
	var cell: Array = _layout.get("cell_px", [320, 300])
	_cell_px = Vector2i(int(cell[0]), int(cell[1]))
	_build_viewport()
	_build_environment()
	_build_grid()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute(_out_dir)
	var copy := FileAccess.open(_out_dir.path_join("layout.json"), FileAccess.WRITE)
	if copy != null:
		copy.store_string(JSON.stringify(_layout, "  "))
		copy.close()

	if _still:
		for entry in _entries:
			var phase := _still_phase if _still_phase >= 0.0 else (
				STILL_PHASE_ONESHOT if not bool(entry.loop) else STILL_PHASE_LOOP
			)
			entry.time = float(entry.duration) * phase
			_apply_pose(entry)
		for _warm in range(2):
			await RenderingServer.frame_post_draw
		image_save(_out_dir.path_join("still.jpg"))
		print("[showcase] still -> %s" % _out_dir)
		get_tree().quit(0)
		return

	var dt := 1.0 / float(_fps)
	for f in range(_frames):
		for entry in _entries:
			_advance(entry, dt)
			_apply_pose(entry)
		await RenderingServer.frame_post_draw
		image_save(_out_dir.path_join("f%04d.jpg" % f))
		if f % 30 == 0:
			print("[showcase] frame %d/%d" % [f, _frames])
	print("[showcase] DONE %d frames, %d clips" % [_frames, _entries.size()])
	get_tree().quit(0)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var key := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--out": _out_dir = value
			"--layout": _layout_path = value
			"--frames": _frames = int(value)
			"--fps": _fps = int(value)
			"--yaw": _yaw = float(value)
			"--pitch": _pitch = float(value)
			"--avatar-yaw": _avatar_yaw = float(value)
			"--phase": _still_phase = float(value)
			"--no-weapons": _use_weapons = false
			"--with-props": _use_weapons = true
			"--still": _still = true


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(_cols * _cell_px.x, _rows * _cell_px.y)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.own_world_3d = true
	add_child(_viewport)

	_stage = Node3D.new()
	_viewport.add_child(_stage)

	_cell_h = CHAR_HEIGHT / CELL_FILL
	_cell_w = _cell_h * (float(_cell_px.x) / float(_cell_px.y))

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 80.0
	_camera.size = float(_rows) * _cell_h
	_stage.add_child(_camera)
	# 纯正视正交：屏幕 x 与世界 X 一一对应、屏幕 y 与世界 Y 一一对应，
	# 格子间距才能与 cell_px 严格对齐（斜视会让世界 X 在屏幕上按 cos 压缩并产生行间漂移）。
	# 立体感由每格角色自身的 --avatar-yaw 提供。
	_camera.position = Vector3(0.0, 0.0, -34.0)
	# 朝 +Z 看（角色正面）。屏幕右 = 世界 -X，故下面列序号按世界 -X 递增。
	_camera.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_camera.current = true
	print("[showcase] viewport=%s cell=%.2fx%.2f m yaw=%.0f pitch=%.0f" % [
		str(_viewport.size), _cell_w, _cell_h, _yaw, _pitch
	])


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0d1218")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c2d6ec")
	env.ambient_light_energy = 0.70
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	we.environment = env
	_stage.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, 30.0, 0.0)
	key.light_energy = 1.25
	key.light_color = Color("#fff4e4")
	_stage.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18.0, 208.0, 0.0)
	rim.light_energy = 0.95
	rim.light_color = Color("#8ec5ff")
	_stage.add_child(rim)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(6.0, 120.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color("#ffdcc4")
	_stage.add_child(fill)


## 每格放一个小舞台；只实例化有 clip 的格子，空格留黑。
func _build_grid() -> void:
	var slots: Array = _layout.get("slots", [])
	for slot: Dictionary in slots:
		var clip_name := str(slot.get("clip", ""))
		if clip_name.is_empty() or not _library.clips.has(clip_name):
			continue
		var clip: Dictionary = _library.clips[clip_name]
		var col := int(slot.get("col", 0))
		var row := int(slot.get("row", 0))
		var wrapper := Node3D.new()
		# 格子中心：整体居中，脚底落在格子底边上方 FOOT_MARGIN 处。
		# 相机在角色正面（-Z 侧）朝 +Z 看，屏幕右 = 世界 -X；列序号按世界 -X 递增，
		# 这样 col 0 落在画面最左，标签顺序才与画面一致。
		wrapper.position = Vector3(
			(float(_cols) * 0.5 - float(col) - 0.5) * _cell_w,
			(float(_rows) * 0.5 - float(row) - 0.5) * _cell_h - _cell_h * 0.5 + _cell_h * FOOT_MARGIN,
			0.0
		)
		_stage.add_child(wrapper)

		var avatar: Node3D = AVATAR_SCENE.instantiate()
		wrapper.add_child(avatar)
		if absf(_avatar_yaw) > 0.01:
			avatar.rotation_degrees.y = _avatar_yaw
		# 保留 PlayerAvatar3D 脚本只为拿到它 _ready 的外观装配（面罩/配色）；
		# 随后停掉 _process，避免状态机每帧覆写手工采样的骨骼。
		avatar.set_process(false)
		avatar.set_physics_process(false)
		var visual_root: Node3D = avatar.get_node("VisualRoot")
		var bones := {
			"root": avatar,
			"body": _find_node(visual_root, "BodyJoint"),
			"head": _find_node(visual_root, "HeadJoint"),
			"ear_l": _find_node(visual_root, "EarSocketL"),
			"ear_r": _find_node(visual_root, "EarSocketR"),
			"hand_l": _find_node(visual_root, "HandJointL"),
			"hand_r": _find_node(visual_root, "HandJointR"),
			"foot_l": _find_node(visual_root, "FootJointL"),
			"foot_r": _find_node(visual_root, "FootJointR"),
			"weapon_socket": _find_node(visual_root, "WeaponSocket"),
		}
		if _use_weapons:
			_attach_prop(bones, clip_name)
		var entry := {
			"clip": clip_name,
			"bones": bones,
			"frames": clip.get("frames", []),
			"duration": float(clip.get("duration", 1.0)),
			"loop": bool(clip.get("loop", true)),
			"time": 0.0,
		}
		# 基线对齐：把该剪辑所有帧里骨骼的最低点拉到格子基线上。
		# 否则 dead/hurt 这类整体下沉的剪辑会比 idle 低半头，横向比较时读不出差异。
		wrapper.position.y -= _lowest_bone_y(clip.get("frames", []))
		_entries.append(entry)
		_apply_pose(entry)


## 该剪辑所有帧中骨骼位置的最低 Y（avatar 局部坐标，yaw 不影响 Y）。
func _lowest_bone_y(frames: Array) -> float:
	var lowest := 0.0
	var seen := false
	for frame: Dictionary in frames:
		for bone: String in frame:
			var position: Array = frame[bone].get("p", [])
			if position.size() < 3:
				continue
			var y := float(position[1])
			lowest = y if not seen else minf(lowest, y)
			seen = true
	return lowest if seen else 0.0


func image_save(path: String) -> void:
	var image := _viewport.get_texture().get_image()
	if image == null:
		printerr("[showcase] 取图失败: " + path)
		return
	image.save_jpg(path, 0.92)


## 按剪辑名前缀挂一个可见道具，让握持/挥击姿势读得出来。
func _attach_prop(bones: Dictionary, clip_name: String) -> void:
	var socket: Node3D = bones.weapon_socket
	if socket == null:
		return
	var path := ""
	# 与 PlayerAvatar3D._apply_bunny_attachment_scale 同口径：枪 = BUNNY_LINEAR_SCALE，
	# 近战 = 0.78（缩到原基准的 78%）。两者都相对于已定位的 weapon_socket。
	var prop_scale := BUNNY_LINEAR_SCALE
	if clip_name.begins_with("melee_"):
		for key: String in MELEE:
			if clip_name.begins_with("melee_" + key):
				path = MELEE[key]
				prop_scale = 0.78
				break
	elif clip_name.begins_with("sidearm"):
		path = GUNS.sidearm
	elif clip_name.begins_with("longgun"):
		path = GUNS.longgun
	elif clip_name.begins_with("machinegun"):
		path = GUNS.machinegun
	if path.is_empty():
		return
	var scene: PackedScene = load(path)
	if scene == null:
		scene = load(GUN_FALLBACK)
	if scene == null:
		return
	var prop := scene.instantiate() as Node3D
	if prop == null:
		return
	prop.name = "ShowcaseProp"
	socket.add_child(prop)
	prop.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	prop.scale = Vector3.ONE * prop_scale


func _advance(entry: Dictionary, dt: float) -> void:
	var duration: float = maxf(entry.duration, 0.001)
	var t: float = float(entry.time) + dt
	if bool(entry.loop):
		entry.time = fmod(t, duration)
	elif t > duration:
		entry.time = 0.0
	else:
		entry.time = t


func _apply_pose(entry: Dictionary) -> void:
	var frames: Array = entry.frames
	if frames.is_empty():
		return
	var bones: Dictionary = entry.bones
	var duration: float = maxf(entry.duration, 0.001)
	var phase: float = float(entry.time) / duration
	phase = fposmod(phase, 1.0) if bool(entry.loop) else clampf(phase, 0.0, 1.0)
	var cursor: float = phase * float(frames.size() - 1)
	var first: int = mini(int(cursor), frames.size() - 1)
	var second: int = mini(first + 1, frames.size() - 1)
	var blend: float = cursor - float(first)
	var a: Dictionary = frames[first]
	var b: Dictionary = frames[second]
	for bone: String in bones:
		var target: Node3D = bones[bone]
		if target == null or not a.has(bone) or not b.has(bone):
			continue
		target.position = _vec(a[bone].p).lerp(_vec(b[bone].p), blend)
		target.quaternion = _quat(a[bone].q).slerp(_quat(b[bone].q), blend)
		target.scale = _vec(a[bone].s).lerp(_vec(b[bone].s), blend)
	# 基础/空手剪辑没有 weapon_socket 轨道：把持物点跟到右手。
	if not a.has("weapon_socket"):
		var socket: Node3D = bones.weapon_socket
		var hand_r: Node3D = bones.hand_r
		if socket != null and hand_r != null:
			socket.position = WEAPON_SOCKET_REST
			socket.quaternion = Quaternion.IDENTITY
			socket.global_position = hand_r.global_position


func _find_node(root: Node, node_name: String) -> Node3D:
	if root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node(child, node_name)
		if found != null:
			return found
	return null


func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _quat(value: Array) -> Quaternion:
	return Quaternion(value[0], value[1], value[2], value[3]).normalized()


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		printerr("[showcase] 文件不存在: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
