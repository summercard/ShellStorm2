class_name ForgeMeltVeil
extends Control
## 熔炼表现层：投料与炉心充能。
##
## 业主口径（2026-11-10）：「把熔炼这块按钮修了。过一遍设计文档和项目框架。
## 然后把熔炼的表现也一起做了。整套流程要完整。」
##
## ## 它补的是哪一环
##
## 2026-10-19 做的是**后半段**（兔子闸门：关闸 → 眼睛红 → 开闸 → 揭晓）。
## 前半段一直是空的：点下熔炼，`WorkbenchPanel._execute_forge` 直接调
## `SynthesisGateVeil.play()`，盘面上一动没动 —— 玩家看不到"我放进去的东西被吃掉了"，
## 只看到画面突然被一块板盖住。这是"做了动画但没做表现"的另一种形态。
##
## 本层就是那一段：**盘面投入物向炉心汇聚 → 炉心充能 → 淡出 → 交给闸门**。
##
## ## 边界（与闸门同一条纪律）
## - **纯表现层**：只读几何与配方标识，不写背包、不扣金币、不改盘面。
## - 轮到本层时**事务已经全部落地**（钱扣了、产物进包了、`_tray` 已清）；
##   本层播完只发一次 `finished`，由面板接着起闸门。
## - **不设不透明底板**：盘面必须透过来可见 —— "东西从盘上被吸走"这个读法
##   依赖玩家还能看见它们原来的格子。底板一盖，就变成"东西凭空没了"。
## - **不用 Tween / await**：面板可能在动画中途被关掉（`queue_free`），
##   await 链会落在已释放对象上。状态机随节点一起消失，天然安全。
##
## ## 时间轴（合计 1.45s）
## ```
## 0.00 ── 投料 0.75 ──┬── 充能 0.45 ──┬── 淡出 0.25 ──┐ 交给闸门
##                     └── 0.75        └── 1.20        └── 1.45
## ```
## **为什么不能更长**：这是"过渡"不是"演出"。业主为闸门定的节拍是闭合后 3 秒，
## 那 3 秒才是等待的主体。投料段若超过 1.5s，一次熔炼要等 6.5s 以上，
## 连续熔炼时会变成负担。

signal finished

const PHASE_IDLE := "idle"
const PHASE_INTAKE := "intake"
const PHASE_CHARGE := "charge"
const PHASE_FADE := "fade"

## 三段时长（秒）。改动这里等于改整段的节拍，验收按这些常量驱动时间轴。
const INTAKE_SECONDS := 0.75
const CHARGE_SECONDS := 0.45
const FADE_SECONDS := 0.25

## 投料段结束时吸入物的尺度（相对原尺寸）。
##
## 不收到 0：收到 0 读起来是"原地消失"；收到 0.18 再淡出，才是"被吸进炉口"。
const INTAKE_END_SCALE := 0.18

## 前 45% 的充能发生在投料段（炉心一边吃一边亮），剩下 55% 在充能段。
const INTAKE_CHARGE_SHARE := 0.45

## 一屏最多给几件物品建吸入 actor。超出的不再建 ——
## 本层是氛围，不是清单；25 格全满时建 25 个 3D 图标纯属浪费。
const MAX_ACTORS := 12

const ICON_SCENE := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")

## 炉心的基准半径系数（相对矩形短边）。
const CORE_RADIUS_RATIO := 0.16

var _phase := PHASE_IDLE
var _time := 0.0
## 充能度：0 = 熄灭，1 = 满。驱动炉心半径与亮度。
var _charge := 0.0
var _recipe := ""

var _actors: Array[Control] = []
var _actor_from: Array[Vector2] = []
var _actor_size: Array[Vector2] = []
## 所有吸入物的终点 = 盘面矩形的中心。由 `play` 传入，不在本层猜。
var _home := Vector2.ZERO

## 投料铭牌：配方名 + 投入量。用 Label 而不是 `draw_string`，
## 才能吃到棱镜排版（宽字距、两级字号），与面板其它文字同源。
var _plate_label: Label = null
## 铭牌矩形。底衬由本层的 `_draw` 画（父节点画在子节点之前，正好压在铭牌下面），
## 铭牌本身是 Label。两者共用 `_plate_rect`，分开算迟早会错位。
var _plate_rect := Rect2()
## 盘面矩形（本层局部坐标）。由 `play` 传入 —— 铭牌与吸入终点都锚在它上面，
## 不在本层猜列高行高。缺省时退化为整个矩形。
var _board_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 吸入物会从盘面最外格里往外飘一点点，超出炼炉栏的部分必须裁掉，
	# 否则会盖到页头标题上（与闸门同一条理由）。
	clip_contents = true
	visible = false
	set_process(false)
	_build_plate()


## 开始播放。`spec`：
##   recipe      命中的配方 ID（决定配色与铭牌）
##   weapons     投入武器数（铭牌用）
##   materials   投入材料件数（铭牌用）
##   items       [{ "rect": Rect2, "item": Dictionary }, …]，rect 是**本层局部坐标**
##   home        吸入物起点中心（一般 = 盘面矩形中心，本层局部坐标）
func play(spec: Dictionary) -> void:
	_recipe = str(spec.get("recipe", ""))
	_home = spec.get("home", Vector2.ZERO)
	_board_rect = spec.get("board", Rect2(Vector2.ZERO, size))
	_build_actors(spec.get("items", []) as Array)
	_refresh_plate(spec)
	_phase = PHASE_INTAKE
	_time = 0.0
	_charge = 0.0
	modulate.a = 1.0
	visible = true
	set_process(true)
	_sync_charge_visual()
	# "倒进炉子"的一下。闸门段用的是 door_close / facility_activate，
	# 这里刻意换两个键，整条链才听得出一段一段的动作。
	_play_cue("special_pour", -8.0, 1.0)


## 立刻收起，**不发** `finished` —— 它表示"播完了"，不是"收掉了"。
##
## 切页与关闭面板都走这条：面板随后自己把欠着的收尾补上。
func abort() -> void:
	_phase = PHASE_IDLE
	set_process(false)
	visible = false
	modulate.a = 1.0
	_charge = 0.0
	_clear_actors()
	queue_redraw()


func is_playing() -> bool:
	return _phase != PHASE_IDLE


## 供验收读取的快照：不看画面也能判"吸到哪一步、炉心亮没亮"。
func get_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"clock": _time,
		"charge": _charge,
		"playing": is_playing(),
		"visible": visible,
		"actors": _actors.size(),
		"recipe": _recipe,
		"accent": accent_for(_recipe).to_html(false),
	}


## ————————————————————————————————
## 配方配色与文案
## ————————————————————————————————

## 配方配色。**必须有依据，不能随手挑**：
##   remelt    蓝 —— 同一把枪重掷品质，枪身不变，冷色表示"低烈度"
##   fusion    紫 —— 两把合一，介于冷与暖之间（与史诗品质色同源）
##   synthesis 金 —— 从无到有凭空造枪，与产出物的贵重感一致
##   directed  翠 —— 定向 = 已知目标，复用既有的成功/确认色 `NEON_MINT`
##
## 四色互不重复，且落在既有调色板上 —— 不新增颜色常量，避免"炼炉有自己一套色"。
static func accent_for(recipe: String) -> Color:
	match recipe:
		WeaponForge.RECIPE_REMELT:
			return UIPalette.PRISM_ACCENT
		WeaponForge.RECIPE_FUSION:
			return UIPalette.PRISM_EPIC
		WeaponForge.RECIPE_SYNTHESIS:
			return UIPalette.SOUL_GOLD
		WeaponForge.RECIPE_DIRECTED:
			return UIPalette.NEON_MINT
	return UIPalette.PRISM_TEXT


static func recipe_label(recipe: String) -> String:
	match recipe:
		WeaponForge.RECIPE_REMELT:
			return "重　铸"
		WeaponForge.RECIPE_FUSION:
			return "融　合"
		WeaponForge.RECIPE_SYNTHESIS:
			return "合　成"
		WeaponForge.RECIPE_DIRECTED:
			return "定向合成"
	return "熔　炼"


## 投料铭牌正文：`1 枪 · 3 材料`。
##
## 一定要把"投了几把枪"说出来 —— 融合与重铸的区别全在这个数字上，
## 而玩家按下去的那一刻正是他最需要确认"我投对了没有"的时候。
static func payload_label(weapons: int, materials: int) -> String:
	var parts: Array[String] = []
	if weapons > 0:
		parts.append("%d 枪" % weapons)
	if materials > 0:
		parts.append("%d 材料" % materials)
	if parts.is_empty():
		return "—"
	return " · ".join(parts)


## ————————————————————————————————
## 时间轴
## ————————————————————————————————

func _process(delta: float) -> void:
	_time += delta
	match _phase:
		PHASE_INTAKE:
			var p := clampf(_time / INTAKE_SECONDS, 0.0, 1.0)
			_charge = INTAKE_CHARGE_SHARE * p
			_sync_actors(p)
			if p >= 1.0:
				_phase = PHASE_CHARGE
				# 充能到位的确认音。与闸门的眼睛点亮音（facility_activate）分开，
				# 否则整段听下来是同一个声音响两次。
				_play_cue("facility_confirm", -7.0, 1.02)
		PHASE_CHARGE:
			var c := clampf((_time - INTAKE_SECONDS) / CHARGE_SECONDS, 0.0, 1.0)
			_charge = INTAKE_CHARGE_SHARE + (1.0 - INTAKE_CHARGE_SHARE) * c
			_sync_actors(1.0)
			if c >= 1.0:
				_phase = PHASE_FADE
		PHASE_FADE:
			var f := clampf((_time - INTAKE_SECONDS - CHARGE_SECONDS) / FADE_SECONDS, 0.0, 1.0)
			_charge = 1.0
			_sync_actors(1.0)
			# 整层淡出：露出**已被清空**的盘面，闸门紧接着落下盖住它。
			modulate.a = 1.0 - f
			if f >= 1.0:
				_finish()
	_sync_charge_visual()
	queue_redraw()


func _finish() -> void:
	_phase = PHASE_IDLE
	set_process(false)
	visible = false
	modulate.a = 1.0
	_charge = 0.0
	_clear_actors()
	queue_redraw()
	finished.emit()


## 投料铭牌。位置固定在矩形**底边偏上**，不跟炉心走 ——
## 炉心在中心、铭牌在下方，两者的关系才读成"炉子在烧，铭牌在报"。
##
## 但底边正是盘面说明文字（「拖回右侧＝取回…」）所在地，两者会叠。
## 所以铭牌往上抬到盘面内部的空白带，并由一条暗底衬把字托出来。
func _build_plate() -> void:
	_plate_label = Label.new()
	_plate_label.name = "MeltPlate"
	_plate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_label.visible = false
	UIStyleFactory.apply_prism_label(_plate_label, "value", 3, 13)
	add_child(_plate_label)
	_place_plate()


## 铭牌矩形。底衬在 `_draw` 里按同一个 `_plate_rect` 画 —— 单一数据源。
##
## 锚在**盘面内部**（不是整层底部）：盘面下方还有一行说明文字，
## 落在整层底部就会压在那行字上（实测截图可见「合成 · 6 材料」与
## 「拖回右侧＝取回…」叠成一团）。锚在盘内则天然让开它，且换分辨率不漂。
func _place_plate() -> void:
	if _plate_label == null:
		return
	var height := 24.0
	var text_width := 180.0
	var font := _plate_label.get_theme_default_font()
	if font != null:
		text_width = font.get_string_size(
			_plate_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13
		).x
	var max_width := maxf(120.0, size.x - 24.0)
	var width := clampf(text_width + 36.0, 120.0, max_width)
	# 贴盘面底边往上 8px，并夹进本层的有效范围。
	var board := _board_rect if _board_rect.size.y > 0.0 else Rect2(Vector2.ZERO, size)
	var top := clampf(
		board.position.y + board.size.y - height - 8.0,
		6.0,
		maxf(6.0, size.y - height - 6.0)
	)
	_plate_rect = Rect2(Vector2((size.x - width) * 0.5, top), Vector2(width, height))
	_plate_label.position = _plate_rect.position
	_plate_label.size = _plate_rect.size


func _refresh_plate(spec: Dictionary) -> void:
	if _plate_label == null:
		return
	var recipe_text := recipe_label(_recipe)
	var payload := payload_label(
		int(spec.get("weapons", 0)), int(spec.get("materials", 0))
	)
	_plate_label.text = "%s　·　%s" % [recipe_text, payload]
	# 铭牌用配方色：玩家在等待时一眼看到"这次熔的是哪一类"，
	# 不需要回头读页脚的 RECIPE 读数。
	_plate_label.add_theme_color_override("font_color", accent_for(_recipe))
	_plate_label.visible = true
	_place_plate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_plate()
		queue_redraw()


## 音效。没有音频的环境（纯逻辑验收）必须静默通过，不能当成错误。
func _play_cue(sfx_name: String, volume_db: float, pitch: float) -> void:
	if not is_inside_tree():
		return
	if AudioManager == null:
		return
	AudioManager.play_sfx(sfx_name, volume_db, pitch)


## ————————————————————————————————
## 吸入物
## ————————————————————————————————

## 为盘面上每一组物品建一个"被吸走"的替身，位置与原格**逐像素重合**。
##
## 用 `ItemModelIcon3D` 而不是贴图标：玩家一眼认出"被吸走的就是我刚放的那把枪"，
## 这与闸门台上用同一个模型是同一个理由。
func _build_actors(items: Array) -> void:
	_clear_actors()
	var built := 0
	for value in items:
		if built >= MAX_ACTORS:
			break
		if not value is Dictionary:
			continue
		var spec := value as Dictionary
		var item := spec.get("item", {}) as Dictionary
		if item.is_empty():
			continue
		var rect: Rect2 = spec.get("rect", Rect2())
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var icon := ICON_SCENE.instantiate() as Control
		if icon == null:
			continue
		icon.name = "MeltActor_%d" % built
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2.ZERO
		icon.set("icon_resolution", 256)
		# 先挂在矩形上再 configure：`ItemModelIcon3D` 需要真实尺寸才能定相机。
		icon.position = rect.position
		icon.size = rect.size
		add_child(icon)
		if icon.has_method("configure"):
			icon.call("configure", item)
		_actors.append(icon)
		_actor_from.append(rect.position + rect.size * 0.5)
		_actor_size.append(rect.size)
		built += 1


func _clear_actors() -> void:
	for actor in _actors:
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	_actor_from.clear()
	_actor_size.clear()


## `p` 是投料进度（0→1，充能段固定传 1）。
##
## 位移用 ease-in-cubic：起步慢、末端快 —— 读起来是"被炉心拉进去"，
## 线性位移会像"自己均匀飘过去"，没有吸力感。
func _sync_actors(p: float) -> void:
	var eased := p * p * p
	var scale := lerpf(1.0, INTAKE_END_SCALE, eased)
	# 后 45% 才开始淡：先看清它离开原位，再消失。全程淡出会闪一下。
	var alpha := 1.0 - smoothstep(0.55, 1.0, p)
	for index in range(_actors.size()):
		var actor := _actors[index]
		if actor == null or not is_instance_valid(actor):
			continue
		var center := _actor_from[index].lerp(_home, eased)
		var size := _actor_size[index] * scale
		actor.size = size
		actor.position = center - size * 0.5
		if actor is CanvasItem:
			(actor as CanvasItem).modulate = Color(1.0, 1.0, 1.0, alpha)


func _sync_charge_visual() -> void:
	pass


## ————————————————————————————————
## 绘制：炉心
## ————————————————————————————————

## 炉心。纯几何绘制，不用贴图（理由同闸门：贴图缩放会糊，还多一份资源要跟美术对版本）。
##
## 它要同时说三件事，缺一件就读不懂：
##   ① 这是**一个口**（同心环 + 内凹的暗膛）—— 不是一团光
##   ② 它在**吃**（旋转辐条 + 内收的刻度环）
##   ③ 它**吃饱了**（半径与亮度随 charge 上升，末端提亮到近白）
func _draw() -> void:
	if _charge <= 0.001:
		return
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var accent := accent_for(_recipe)

	# ⓪ 铭牌底衬。**必须在炉心之前画** —— 否则它会盖住炉心的辉光下半部。
	#
	# 这条底衬不是装饰：铭牌落在盘面内部，那里可能正有被吸走的物品图标，
	# 没它的话「合成　·　6 材料」会和一格物品的名字叠成一团（实测截图可见）。
	# 上下各 1px 亮线、中间一条极暗带 —— 仍是棱镜语言，不是实心卡片。
	if _plate_label != null and _plate_label.visible and _plate_rect.size.x > 0.0:
		draw_rect(_plate_rect, Color(0.008, 0.014, 0.024, 0.88))
		draw_line(
			_plate_rect.position,
			_plate_rect.position + Vector2(_plate_rect.size.x, 0.0),
			Color(accent, 0.42), 1.0
		)
		draw_line(
			_plate_rect.position + Vector2(0.0, _plate_rect.size.y),
			_plate_rect.position + _plate_rect.size,
			Color(accent, 0.20), 1.0
		)

	var base_radius := minf(w, h) * CORE_RADIUS_RATIO
	var radius := base_radius * (0.55 + 0.75 * _charge)
	var center := size * 0.5

	# ① 暗膛：炉口先是一个吃掉光的洞。不画它，后面的辉光会像"贴了一片亮斑"。
	draw_circle(center, radius * 1.32, Color(0.008, 0.012, 0.020, 0.92 * _charge))
	draw_circle(center, radius * 1.10, Color(0.014, 0.020, 0.031, 0.96 * _charge))

	# ② 收束刻度环：24 段弧，留缺口 —— 实心圆环读起来是"装饰"，断弧才读得出"在转"。
	var ring_radius := radius * 1.18
	var segments := 24
	for index in segments:
		if index % 3 == 2:
			continue
		var from := TAU * float(index) / float(segments) + _time * 1.1
		var to := TAU * float(index + 1) / float(segments) + _time * 1.1
		draw_arc(center, ring_radius, from, to, 6, Color(accent, 0.34 * _charge), 1.5, true)

	# ③ 交互弧：颜色更深的一圈，逆着转 —— 两圈反向才像"两个部件在咬合"。
	var inner_segments := 16
	for index in inner_segments:
		if index % 2 == 1:
			continue
		var from := TAU * float(index) / float(inner_segments) - _time * 0.7
		var to := TAU * float(index + 1) / float(inner_segments) - _time * 0.7
		draw_arc(center, radius * 0.86, from, to, 6, Color(accent, 0.26 * _charge), 1.0, true)

	# ④ 辉光：多层同心圆，各层透明度按 1/layer 衰减（与闸门兔子眼睛同一套做法）。
	#    没有这个梯度，红光/蓝光会脏成一个暗点。
	for layer in range(5, 0, -1):
		var glow_radius := radius * (1.0 + 0.42 * float(layer))
		draw_circle(center, glow_radius, Color(accent, 0.030 * _charge / float(layer)))

	# ⑤ 亮核：末端提亮到近白。这是"吃饱了"的唯一视觉证据。
	var pulse := 1.0 + 0.10 * sin(_time * 22.0)
	var core := accent.lerp(Color(1.0, 0.97, 0.92, 1.0), _charge * 0.6)
	draw_circle(center, radius * 0.42 * pulse, Color(core, 0.92 * _charge))
	draw_circle(center, radius * 0.20 * pulse, Color(1.0, 1.0, 1.0, 0.75 * _charge))
