extends Node3D
## 一次性工具：把 BOSS 002（MONITOR.EXE）的全部 17 段动画录成一条展示视频。
##
## 用法（录制，交给 Godot 的 Movie Maker 逐帧出片）：
##   godot --path . --resolution 1920x1080 --write-movie I:/.../boss.avi \
##         --fixed-fps 30 res://tools/boss_anim_showreel.tscn
##
## 用法（只出静帧，用来核对机位/朝向/打光）：
##   godot --path . res://tools/boss_anim_showreel.tscn -- --probe
##
## 为什么不用 `--script`：和 `monster_startup_capture.gd` 同一个坑 —— `-s` 不挂
## autoload，而表现脚本依赖项目单例编译。
##
## 姿态来源：`MonitorBossPresentation.sync_context()`，也就是运行时**真正**走的
## 那条采样路径（monitor_motion.json 的 30Hz 骨矩阵 + 表情/屏幕/特效同一时间轴）。
## 本工具只负责「逐帧按时间推 clip」和「摆机位」，不碰任何动画数值。

const BOSS_SCENE: PackedScene = preload(
	"res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn"
)
const MOTION_PATH := "res://assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/monitor_motion.json"

const FPS := 30
const OUT_W := 1920
const OUT_H := 1080
const INTRO_FRAMES := 45
const OUTRO_FRAMES := 45

## 展示顺序按「出场 → 移动 → 攻击 → 特殊 → 受击/眩晕 → 死亡」排，
## 不按 JSON 字典序 —— 后者会把死亡排在中间，看着莫名其妙。
## cycles：循环段播两轮，让循环接缝看得见；一次性动作播一遍。
const ORDER := [
	{"id": "activate", "cycles": 1, "tag": "ACTIVATION / 激活出场"},
	{"id": "idle", "cycles": 2, "tag": "IDLE / 待机"},
	{"id": "move", "cycles": 2, "tag": "MOVE / 移动"},
	{"id": "turn_left", "cycles": 1, "tag": "TURN LEFT / 左转"},
	{"id": "turn_right", "cycles": 1, "tag": "TURN RIGHT / 右转"},
	{"id": "melee_keyboard", "cycles": 1, "tag": "ATTACK / 键盘砸击", "skill": "monitor_keyboard"},
	{"id": "melee_cable", "cycles": 1, "tag": "ATTACK / 数据线甩击", "skill": "monitor_cable"},
	{"id": "heavy_spin_slam", "cycles": 1, "tag": "HEAVY / 旋转三周砸地", "skill": "monitor_spin_slam"},
	{"id": "special_prepare", "cycles": 1, "tag": "SPECIAL / 蓄力"},
	{"id": "special_insert", "cycles": 1, "tag": "SPECIAL / 插头插入"},
	{"id": "special_channel", "cycles": 2, "tag": "SPECIAL / 通电持续", "electric": true},
	{"id": "special_recover", "cycles": 1, "tag": "SPECIAL / 收招"},
	{"id": "hurt", "cycles": 1, "tag": "HURT / 受击"},
	{"id": "stun_enter", "cycles": 1, "tag": "STUN / 进入眩晕"},
	{"id": "stun_loop", "cycles": 2, "tag": "STUN / 眩晕循环"},
	{"id": "stun_exit", "cycles": 1, "tag": "STUN / 起身"},
	{"id": "dead", "cycles": 1, "tag": "DEAD / 死亡"},
]

var _motion: Dictionary = {}
var _font: FontFile = null
var _schedule: Array[Dictionary] = []
var _total := 0
var _frame := 0
var _boss: MonitorBossPresentation
var _cam: Camera3D
var _phase: Label
var _meta: Label
var _frame_label: Label
var _clip_bar_bg: ColorRect
var _clip_bar: ColorRect
var _reel_bar: ColorRect
var _idle_only := false


func _ready() -> void:
	# ⚠️ Movie Maker 的帧尺寸取的是 **root viewport** 尺寸，不是 `--resolution` 的窗口尺寸。
	# 项目 `window/stretch/mode=canvas_items` + viewport 1280×720，所以即使命令行给了
	# --resolution 1920x1080，第一版还是录出 1280×720。这里改 content_scale_size 才生效。
	if Engine.get_write_movie_path() != "":
		get_window().content_scale_size = Vector2i(OUT_W, OUT_H)
		DisplayServer.window_set_size(Vector2i(OUT_W, OUT_H))
	_motion = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH)) as Dictionary
	assert(not _motion.is_empty(), "monitor_motion.json 读不到")
	_build_schedule()
	_build_stage()
	_build_hud()

	_boss = BOSS_SCENE.instantiate() as MonitorBossPresentation
	assert(_boss != null, "Boss 预制体实例化失败")
	add_child(_boss)

	var args := OS.get_cmdline_user_args()
	var probe := "--probe" in args

	if probe:
		_probe_shots()
		return

	# 录制前先让材质/着色器/环境各画几帧，避免片头是空帧。
	for i in range(6):
		await RenderingServer.frame_post_draw
	print("[showreel] clips=%d total_frames=%d (%.2fs @ %dfps)" % [
		_schedule.size(), _total, float(_total) / FPS, FPS
	])


## 逐帧推进。Movie Maker 模式下 delta 恒为 1/FPS，所以这里直接用帧号算时间，
## 不靠累加浮点 —— 40 秒整数帧，末帧不会因为误差漂掉半帧。
func _process(_delta: float) -> void:
	if Engine.get_write_movie_path() == "" or _boss == null:
		return
	if _frame >= _total:
		print("[showreel] done: %d frames" % _frame)
		get_tree().quit(0)
		return
	_apply_frame(_frame)
	_frame += 1


func _apply_frame(index: int) -> void:
	var entry := _entry_at(index)
	if entry.is_empty():
		# 片头/片尾定格在 idle 第一帧，别让模型停在上一段动作的中途。
		_push_pose("idle", 0.0, {})
		_set_caption("", "BOSS 002", "MONITOR.EXE  ·  17 CLIPS  ·  %d fps" % FPS, 0.0, 1.0, 0.0, 1.0)
		return
	var local: int = index - int(entry["start"])
	var t: float = float(local) / FPS
	var clip: Dictionary = _motion.clips[entry["id"]]
	if bool(clip.loop):
		t = fmod(t, float(clip.duration))
	_push_pose(str(entry["id"]), t, entry)
	var normal := clampf(t / maxf(float(clip.duration), 0.001), 0.0, 1.0)
	_set_caption(
		"%02d / %02d" % [int(entry["no"]), _schedule.size()],
		str(entry["id"]),
		str(entry["tag"]) + "   ·   %.2fs%s" % [float(clip.duration), "  ·  LOOP ×%d" % int(entry["cycles"]) if bool(clip.loop) else ""],
		normal,
		float(index) / float(maxi(_total - 1, 1)),
		t,
		float(clip.duration)
	)


func _push_pose(clip: String, t: float, entry: Dictionary) -> void:
	var context := {"action_id": clip, "time": t}
	if entry.has("skill"):
		context["skill_id"] = str(entry["skill"])
		# contact_point 决定特效圆心；两个近战技能打身前地面，砸地打脚下。
		context["contact_point"] = Vector3(0.0, 0.0, 2.2) if str(entry["skill"]) != "monitor_spin_slam" else Vector3.ZERO
	if entry.get("electric", false):
		context["electric_active"] = true
	_boss.sync_context(context, false)


func _entry_at(index: int) -> Dictionary:
	for e in _schedule:
		var start := int(e["start"])
		if index >= start and index < start + int(e["frames"]):
			return e
	return {}


func _build_schedule() -> void:
	var cursor := INTRO_FRAMES
	var no := 0
	for item in ORDER:
		var id := str(item["id"])
		if not _motion.clips.has(id):
			push_warning("monitor_motion.json 缺 clip: " + id)
			continue
		no += 1
		var clip: Dictionary = _motion.clips[id]
		var frames := maxi(2, roundi(float(clip.duration) * FPS * int(item["cycles"])))
		var entry := {
			"id": id, "tag": str(item["tag"]), "cycles": int(item["cycles"]),
			"frames": frames, "start": cursor, "no": no,
		}
		if item.has("skill"):
			entry["skill"] = str(item["skill"])
		if item.get("electric", false):
			entry["electric"] = true
		_schedule.append(entry)
		cursor += frames
	_total = cursor + OUTRO_FRAMES


# ── 舞台 ────────────────────────────────────────────────────────────────
func _build_stage() -> void:
	_cam = Camera3D.new()
	# 模型局部边界 x[-3.63,3.25] y[-0.60,3.49] z[-0.50,0.67]（双臂展开宽度约 6.9m）。
	# ⚠️ 屏幕面朝 **-Z**（和 Enemy3D 的前方约定一致）。机位必须放在 -Z 侧，
	# 放到 +Z 拍到的是显示器背板和支架 —— 探针第一版就是这么拍反的。
	# 距离取 8.55 而不是贴到 6.5：`heavy_spin_slam` 甩臂时手会伸出一次静息包围盒，
	# 贴太近就在画外（探针实测被切掉半只手）。
	_cam.position = Vector3(-2.05, 2.60, -8.55)
	_cam.fov = 44.0
	_cam.current = true
	add_child(_cam)
	_cam.look_at(Vector3(0.0, 1.72, 0.0), Vector3.UP)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	key.light_energy = 1.45
	key.shadow_enabled = true
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22.0, -140.0, 0.0)
	rim.light_energy = 0.85
	rim.light_color = Color(0.42, 0.72, 1.0)
	add_child(rim)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.6, 2.2, 3.4)
	fill.light_energy = 1.1
	fill.omni_range = 12.0
	fill.light_color = Color(0.55, 0.72, 1.0)
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.038, 0.045, 0.062, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.40, 0.45, 0.56, 1.0)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	# 地面：带一点自发光网格感的深色板，让「脚有没有踩地、砸地有没有贴身」看得出来。
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.115, 0.125, 0.152, 1.0)
	mat.roughness = 0.88
	mat.metallic = 0.0
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	var grid := MeshInstance3D.new()
	grid.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.45, 0.72, 1.0, 0.28)
	gmat.albedo_texture = _make_grid_texture()
	gmat.uv1_scale = Vector3(30.0, 30.0, 1.0)
	grid.material_override = gmat
	grid.position = Vector3(0.0, 0.004, 0.0)
	add_child(grid)


## 1m 一格的淡网格，纯程序生成，不引外部贴图。
func _make_grid_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.0))
	for i in range(size):
		img.set_pixel(i, 0, Color(1, 1, 1, 1.0))
		img.set_pixel(0, i, Color(1, 1, 1, 1.0))
	return ImageTexture.create_from_image(img)


# ── 叠加层（画面内的自解释信息）─────────────────────────────────────────
func _build_hud() -> void:
	_font = _load_system_font()
	var layer := CanvasLayer.new()
	layer.name = "ShowreelHud"
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# 上下两条压暗带，保证白字在任何背景上都读得清。
	var top := ColorRect.new()
	top.color = Color(0.02, 0.025, 0.035, 0.64)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 178.0
	root.add_child(top)

	var bottom := ColorRect.new()
	bottom.color = Color(0.02, 0.025, 0.035, 0.55)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -96.0
	root.add_child(bottom)

	_phase = _label(root, 54, Color(0.96, 0.98, 1.0), Vector2(48, 20))
	_meta = _label(root, 23, Color(0.55, 0.82, 1.0), Vector2(50, 108))
	_frame_label = _label(root, 20, Color(0.62, 0.70, 0.82), Vector2(1490, 24), 390.0)

	# 本段进度条
	_clip_bar_bg = ColorRect.new()
	_clip_bar_bg.color = Color(1, 1, 1, 0.14)
	_clip_bar_bg.position = Vector2(50, 158)
	_clip_bar_bg.size = Vector2(560, 5)
	root.add_child(_clip_bar_bg)
	_clip_bar = ColorRect.new()
	_clip_bar.color = Color(0.35, 0.78, 1.0, 1.0)
	_clip_bar.position = Vector2(50, 158)
	_clip_bar.size = Vector2(0, 5)
	root.add_child(_clip_bar)

	# 整条片的进度条
	var reel_bg := ColorRect.new()
	reel_bg.color = Color(1, 1, 1, 0.12)
	reel_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	reel_bg.offset_top = -70.0
	reel_bg.offset_bottom = -67.0
	reel_bg.offset_left = 48.0
	reel_bg.offset_right = -48.0
	root.add_child(reel_bg)
	_reel_bar = ColorRect.new()
	_reel_bar.color = Color(0.35, 0.78, 1.0, 0.85)
	_reel_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_reel_bar.offset_top = -70.0
	_reel_bar.offset_bottom = -67.0
	_reel_bar.offset_left = 48.0
	_reel_bar.size = Vector2(0, 3)
	root.add_child(_reel_bar)


## ⚠️ Label 必须显式给 size：Godot 4 的 Label 按自身 rect 排版，
## size 为 (0,0) 时一个字都不画（第一版探针就是这么得到一张「只有色块没有字」的图）。
func _label(parent: Control, size: int, color: Color, pos: Vector2, width := 1500.0) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, float(size) * 1.7)
	l.add_theme_font_size_override("font_size", size)
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025, 1.0))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 中文字形：项目本身不带字体（Godot 内置 Open Sans 没有 CJK 字形，中文会变成方块）。
## 这里按顺序找系统里存在的无衬线中文字体，找到就用；一个都没有就把标题退回纯英文。
const SYSTEM_FONTS := [
	"C:/Windows/Fonts/NotoSansSC-VF.ttf",
	"C:/Windows/Fonts/msyh.ttc",
	"C:/Windows/Fonts/simhei.ttf",
	"C:/Windows/Fonts/Deng.ttf",
]

func _load_system_font() -> FontFile:
	for path in SYSTEM_FONTS:
		if not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		if font.load_dynamic_font(path) == OK:
			print("[showreel] font -> %s" % path)
			return font
	printerr("[showreel] 没有可用中文字体，标题只用英文")
	return null


func _set_caption(title: String, name: String, meta: String, clip_t: float, reel_t: float, t: float, dur: float) -> void:
	if _phase == null:
		return
	_phase.text = ("%s   %s" % [title, name]) if title != "" else name
	_meta.text = meta
	if _frame_label != null:
		_frame_label.text = "t = %05.2fs / %05.2fs      frame %04d / %04d" % [
			t, maxf(dur, 0.001), _frame + 1, _total
		]
	if _clip_bar != null:
		_clip_bar.size = Vector2(520.0 * clampf(clip_t, 0.0, 1.0), 5)
	if _reel_bar != null:
		_reel_bar.size = Vector2(1824.0 * clampf(reel_t, 0.0, 1.0), 3)


# ── 静帧核对模式 ────────────────────────────────────────────────────────
## 只用来确认「正面是不是正面、机位够不够、打光死不死黑」。
## 出片前跑一次，比录 40 秒再发现拍反了省事。
func _probe_shots() -> void:
	var dir := "res://outputs/boss_showreel_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var poses := [
		{"clip": "idle", "t": 0.5, "name": "front"},
		{"clip": "heavy_spin_slam", "t": 1.0, "name": "spin"},
		{"clip": "heavy_spin_slam", "t": 2.2, "name": "spin_slam"},
		{"clip": "melee_cable", "t": 0.95, "name": "cable"},
		{"clip": "activate", "t": 6.0, "name": "activate"},
		{"clip": "stun_enter", "t": 1.1, "name": "stun"},
		{"clip": "special_channel", "t": 0.4, "name": "channel"},
		{"clip": "dead", "t": 1.9, "name": "dead"},
	]
	for p in poses:
		# 走完整的取帧路径，确保 HUD 文字/进度条与成片一致。
		var idx := INTRO_FRAMES
		for e in _schedule:
			if str(e["id"]) == str(p["clip"]):
				idx = int(e["start"]) + roundi(float(p["t"]) * FPS)
				break
		_apply_frame(idx)
		for i in range(4):
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var out := "%s/%s.png" % [dir, str(p["name"])]
		img.save_png(ProjectSettings.globalize_path(out))
		print("[probe] saved -> %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)
