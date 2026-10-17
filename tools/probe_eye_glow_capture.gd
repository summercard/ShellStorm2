extends Node3D
## 一次性工具：实拍强化怪发光眼（原怪 | 强化怪同框对照）。
## 环境开启与游戏一致的辉光（`GraphicsSettingsManager` 的 bloom），否则自发光看不出「发光」。
## 用法：godot --path . res://tools/probe_eye_glow_capture.tscn -- <out.png>

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)

## (基类, 变种)。左原怪、右强化怪。
const PAIRS := [
	["melee_chaser", "melee_chaser_strong"],
	["ranged_caster", "ranged_caster_strong"],
	["fat_zombie03", "fat_zombie03_strong"],
]
## 模型高处（用于取景与比例换算）。
const MODEL_HEIGHT := {
	"melee_chaser": 1.857143,
	"melee_chaser_strong": 1.857143,
	"ranged_caster": 1.857143,
	"ranged_caster_strong": 1.857143,
	"fat_zombie03": 3.142857,
	"fat_zombie03_strong": 3.142857,
}

var _cam: Camera3D
var _game_view := false
var _attack_view := false
var _out := "res://outputs/eye_glow_capture.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_attack_view = args.size() > 1 and args[1] == "attack"
	_game_view = args.size() > 1 and args[1] == "game"
	_build_env()
	var shots: Array[Image] = []

	for pair in PAIRS:
		if _attack_view and pair[0] != "ranged_caster":
			continue
		var base_kind := str(pair[0])
		var variant_kind := str(pair[1])
		# 各按自身眼位取景；攻击模式使用共同世界尺度对比发射高度。
		var glance := await _shoot_one(variant_kind, Vector3.ZERO, 0.0)
		var variant_img: Image = glance["image"]
		var base_shot := await _shoot_one(base_kind, Vector3.ZERO, 0.0)
		shots.append(base_shot["image"])
		shots.append(variant_img)

	var sheet := _compose(shots, 2, 440)
	var path := ProjectSettings.globalize_path(_out)
	var err := sheet.save_png(path)
	print("[glow] saved err=%d -> %s" % [err, path])
	get_tree().quit(0 if err == OK else 3)


## 拍一只怪。`focus` 为零向量时按配方自行定焦点，并把焦点/视野一并返回供第二张复用。
func _shoot_one(kind: String, focus: Vector3, ortho_size: float) -> Dictionary:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy)
	# ⚠ 必须关掉物理：探针场景没有地板，Enemy3D 会一直受重力自由下落。
	# 实测踩过 —— 眼球跟着怪一起落（行为正确），但用「绝对世界高度」去算眼位比例
	# 就会得出 ratio=0.057 这种假故障，白追了几轮。
	enemy.set_physics_process(false)
	enemy.apply_profile(kind)
	await get_tree().process_frame
	await get_tree().process_frame

	var total := enemy.scale.y
	var socket := MonsterVariants.eye_socket_for_base(
		MonsterVariants.base_of(kind) if MonsterVariants.is_variant(kind) else kind
	)
	var eyes := _find_eyes(enemy)
	var snap: Dictionary = enemy.avatar.get_component_snapshot()
	var glow: Dictionary = snap.get("eye_glow", {})
	print("[glow] %-24s 眼=%d 骨=%s emission=%s 灯=%s" % [
		kind, eyes.size(), str(snap.get("eye_socket_bone", "")),
		str(glow.get("emission_enabled", false)), str(glow.get("has_light", false)),
	])
	# 一律换算到**怪自身坐标系**再判定 —— 世界坐标会被下落/位移污染。
	var to_local := enemy.global_transform.affine_inverse()
	var local_eyes: Array[Vector3] = []
	for eye in eyes:
		local_eyes.append(to_local * eye.global_position)
	if local_eyes.size() == 2:
		var l := local_eyes[0]
		var r := local_eyes[1]
		print("[glow]   眼皮(怪局部) L=%s R=%s" % [_v(l), _v(r)])
		print("[glow]   对称性 |L.x+R.x|=%.4f（骨锚点可非对称） 高度差=%.4f" % [
			absf(l.x + r.x), absf(l.y - r.y)
		])
		print("[glow]   眼高比例=%.4f（配方 %.4f）" % [
			(l.y + r.y) * 0.5 / float(MODEL_HEIGHT[kind]), float(socket.get("y_ratio", 0.0))
		])

	if focus == Vector3.ZERO:
		if local_eyes.size() == 2:
			focus = enemy.global_transform * ((local_eyes[0] + local_eyes[1]) * 0.5)
		else:
			var ratio := float(socket.get("y_ratio", 0.55)) if not socket.is_empty() else 0.55
			focus = Vector3(0.0, float(MODEL_HEIGHT[kind]) * total * ratio, 0.0)
		ortho_size = 0.62 * total * (2.2 if kind.begins_with("fat_zombie03") else 1.6)

	var attack_pool: ProjectilePool3D
	if _attack_view:
		attack_pool = ProjectilePool3D.new()
		add_child(attack_pool)
		enemy._perform_attack(Vector3.FORWARD, 4.0)
		for bullet in attack_pool.get_children():
			bullet.set_physics_process(false)
			bullet.global_position += bullet.direction * 1.6
		focus = Vector3(0, 1.0, -0.7)
		ortho_size = 4.8
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ortho_size
	_cam.position = focus + (Vector3(0, 4.5, -7.0) if _game_view or _attack_view else Vector3(0, 0, -2.0))
	_cam.look_at(focus, Vector3.UP)
	var img := await _shot()
	if attack_pool != null:
		attack_pool.queue_free()
	enemy.queue_free()
	await get_tree().process_frame
	return {"image": img, "focus": focus, "size": ortho_size}


func _find_eyes(enemy: Enemy3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if enemy.avatar == null:
		return out
	for node in enemy.avatar.find_children("*", "MeshInstance3D", true, false):
		if str((node as MeshInstance3D).name) in ["EyeGlowL", "EyeGlowR"]:
			out.append(node as Node3D)
	return out


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# 与游戏一致的辉光（`GraphicsSettingsManager` bloom → glow_intensity 0.72）：
	# game 模式故意关闭辉光，核验独立柔光晕。
	env.glow_enabled = not _game_view
	env.glow_intensity = 0.72
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-88.0, 0.0, 0.0)
	light.light_energy = 0.9
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


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
