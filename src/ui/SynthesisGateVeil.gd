class_name SynthesisGateVeil
extends Control
## 合成表现层：兔子闸门。
##
## 业主口径（2026-10-19）：
## 「点击合成后 一个带有兔子 logo 的闸门关下，遮住中间的界面，这个闸门就在中间界面范围里，
##   然后兔子眼睛发红，过了约 3 秒 闸门打开 里头的东西被替换成合成的东西」
##
## ## 边界
## - **纯表现层**：只读产物字典，不写背包、不扣金币、不改盘面 —— 事务由 `WorkbenchPanel` 先做完。
## - **不越界**：本控件的矩形就是炼炉那一栏，闸门盖不到背包与页脚。
## - **不用 Tween / await**：整个动画是一个 `_process` 状态机。
##   面板可能在动画中途被关掉（`queue_free`），await 链会落在已释放对象上；
##   状态机随节点一起消失，天然安全。
##
## ## 时间轴（合计 4.8s，闸门在 3.0s 处开始上升，3.6s 升到底）
## ```
## 0.00 ─ 关闸 0.60 ─┐ 2.40 保持（0.12 后眼睛点亮并脉动）┌─ 开闸 0.60 ─┐ 停留 1.40 ┐ 结束
##                   └──────────── 3.00 ─────────────────┘            3.60       5.00
## ```
## 业主说的「约 3 秒」是**闭合后到开始上升**这一段，不是整段动画 ——
## 玩家感知里"卡在那儿等它开"的就是这 3 秒。
## 开闸后还留 1.4s：那才是"里头的东西被替换了"的展示时间。

signal closed
signal revealed
signal finished

const CLOSE_SECONDS := 0.60
const HOLD_SECONDS := 2.40
const OPEN_SECONDS := 0.60
## 开闸之后台面继续停留的时长。
##
## 没有这一段时，产物只在闸门上升的 0.6 秒里被瞥见一眼，随即台面收掉、
## 露出一块空盘面 —— 玩家根本来不及看清"换来的是什么枪"。
## 业主的规格是「闸门打开，里头的东西被替换成合成的东西」，
## 那个"替换结果"必须给够时间读。
const LINGER_SECONDS := 1.40
## 闸门落到底之后多久点亮眼睛。留一拍停顿，让「落下」与「亮起」读成两件事。
const EYE_DELAY := 0.12
## 眼睛从熄灭到全亮的时长。
const EYE_RAMP := 0.22

const PHASE_IDLE := "idle"
const PHASE_CLOSING := "closing"
const PHASE_HOLD := "hold"
const PHASE_OPENING := "opening"
const PHASE_LINGER := "linger"

const ICON_SCENE := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
## 一屏最多展示几件产物。R3 上限 3 把，超出只报总数。
const MAX_PLATES := 3

var _phase := PHASE_IDLE
var _time := 0.0
## 闭合度：0 = 完全收起（看不见），1 = 完全盖住中间区域。
var _progress := 0.0
## 眼睛亮度：0 = 熄灭，1 = 全红。
var _eyes := 0.0
## 落地余震强度。落下瞬间置 1，随后衰减。
var _land := 0.0

var _stage: Control = null
var _shutter: ShutterLayer = null
var _plate_row: HBoxContainer = null
var _extra_label: Label = null
var _plate_names: Array[String] = []
## 眼睛的点亮音只响一次。`_eyes` 到 1 之后每帧都满足条件，不设闸会连响几十次。
var _eye_cue_played := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 闸门滑下来时顶边在矩形上方，超出的部分必须裁掉，否则会盖到页头。
	clip_contents = true
	visible = false
	set_process(false)
	_build_stage()
	_build_shutter()


## 开始播放。`entries` 是产物字典数组（与 `forge_completed` 的 `outputs` 同源）。
##
## 重复调用先复位：宁可重播，也不能让上一轮的残留产物留在台上。
func play(entries: Array) -> void:
	_fill_stage(entries)
	_phase = PHASE_CLOSING
	_time = 0.0
	_progress = 0.0
	_eyes = 0.0
	_land = 0.0
	_eye_cue_played = false
	visible = true
	set_process(true)
	# 台面透明度会被上一轮的淡出改过，每次开播都要复位。
	if _stage != null:
		_stage.modulate.a = 1.0
	_sync_shutter()
	_play_cue("door_close", -3.0, 0.80)


func abort() -> void:
	_phase = PHASE_IDLE
	set_process(false)
	visible = false
	_progress = 0.0
	_eyes = 0.0
	_sync_shutter()


func is_playing() -> bool:
	return _phase != PHASE_IDLE


## 供验收读取的快照：不看画面也能判「闸门关没关、眼睛亮没亮、台上是不是那件东西」。
func get_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"progress": _progress,
		"eyes": _eyes,
		"playing": is_playing(),
		"visible": visible,
		"plates": _plate_names.duplicate(),
	}


func _process(delta: float) -> void:
	_time += delta
	_land = maxf(0.0, _land - delta * 7.0)
	match _phase:
		PHASE_CLOSING:
			var p := clampf(_time / CLOSE_SECONDS, 0.0, 1.0)
			# smoothstep：起步加速、落底前收住 —— 读起来是"机械下压"而不是匀速滑动。
			_progress = p * p * (3.0 - 2.0 * p)
			if p >= 1.0:
				_progress = 1.0
				_land = 1.0
				_phase = PHASE_HOLD
				# 落地重击：只响一次，是"门到底了"的那一下。
				_play_cue("melee_heavy_impact", -5.0, 0.55)
				closed.emit()
		PHASE_HOLD:
			_progress = 1.0
			var held := _time - CLOSE_SECONDS
			_eyes = clampf((held - EYE_DELAY) / EYE_RAMP, 0.0, 1.0)
			if _eyes >= 1.0 and not _eye_cue_played:
				_eye_cue_played = true
				_play_cue("facility_activate", -8.0, 0.86)
			if held >= HOLD_SECONDS:
				_phase = PHASE_OPENING
				_play_cue("door_open", -4.0, 1.02)
				revealed.emit()
		PHASE_OPENING:
			var elapsed := _time - CLOSE_SECONDS - HOLD_SECONDS
			var p := clampf(elapsed / OPEN_SECONDS, 0.0, 1.0)
			# 开闸用 ease-in：先慢后快，像被卷上去，而不是"弹开"。
			_progress = 1.0 - p * p
			_eyes = clampf(1.0 - p * 1.6, 0.0, 1.0)
			if p >= 1.0:
				_progress = 0.0
				_eyes = 0.0
				# 不在这里收尾：台面还要留着让玩家看清产物（见 LINGER_SECONDS）。
				_phase = PHASE_LINGER
				_play_cue("item_pickup", -7.0, 1.05)
				revealed.emit()
		PHASE_LINGER:
			_progress = 0.0
			_eyes = 0.0
			var linger := _time - CLOSE_SECONDS - HOLD_SECONDS - OPEN_SECONDS
			# 最后 35% 淡出台面：硬切回空盘面会有一下"东西凭空消失"的突兀。
			var fade_from := LINGER_SECONDS * 0.65
			if _stage != null:
				_stage.modulate.a = clampf((LINGER_SECONDS - linger) / (LINGER_SECONDS - fade_from), 0.0, 1.0)
			if linger >= LINGER_SECONDS:
				_phase = PHASE_IDLE
				set_process(false)
				visible = false
				finished.emit()
	_sync_shutter()


## 保持段点击可以提前开闸 —— 玩家不想等 3 秒时有个出口。
##
## **关闸段不给跳**：那一瞬间画面还没被盖住，跳过会露出揭底的半帧。
## **停留段可以点掉**：那时产物已经看清了，它只是"还想再看一眼"的余地。
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not (mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT):
		return
	if _phase == PHASE_HOLD:
		_eyes = 1.0
		_phase = PHASE_OPENING
		_time = CLOSE_SECONDS + HOLD_SECONDS
		_play_cue("door_open", -4.0, 1.02)
		revealed.emit()
		accept_event()
	elif _phase == PHASE_LINGER:
		_phase = PHASE_IDLE
		set_process(false)
		visible = false
		finished.emit()
		accept_event()


func _sync_shutter() -> void:
	if _shutter == null:
		return
	_shutter.progress = _progress
	_shutter.eyes = _eyes
	_shutter.land = _land
	_shutter.clock = _time
	_shutter.closing_motion = _closing_motion()
	_shutter.queue_redraw()


## 只在**下滑中**才算"在动"。停下就熄余辉，闸门静止还在发光是很廉价的观感。
func _closing_motion() -> float:
	if _phase != PHASE_CLOSING:
		return 0.0
	return clampf(1.0 - absf(2.0 * _progress - 1.0), 0.0, 1.0)


## 音效。表现层的一部分 —— 但没有音频的环境（纯逻辑验收）必须静默通过，不能当成错误。
func _play_cue(sfx_name: String, volume_db: float, pitch: float) -> void:
	if not is_inside_tree():
		return
	if AudioManager == null:
		return
	AudioManager.play_sfx(sfx_name, volume_db, pitch)


# ————————————————————————————————
# 台面（闸门后面的产物）
# ————————————————————————————————

func _build_stage() -> void:
	_stage = Control.new()
	_stage.name = "RevealStage"
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	var backdrop := ColorRect.new()
	backdrop.name = "StageBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	# **必须不透明**。0.95 时底下那块还带着材料的盘面会透上来，
	# 台面上就同时有"新材料"和"旧材料残影"，看起来像没换干净。
	# 这一层要表达的是"里头已经换成别的东西了"，它就得能盖住。
	backdrop.color = Color(0.011, 0.017, 0.026, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(backdrop)

	var column := VBoxContainer.new()
	column.name = "StageColumn"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12.0
	column.offset_top = 12.0
	column.offset_right = -12.0
	column.offset_bottom = -12.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(column)

	var caption := Label.new()
	caption.name = "StageCaption"
	caption.text = "SYNTHESIS COMPLETE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(caption, "label", 5, 11)
	column.add_child(caption)

	_plate_row = HBoxContainer.new()
	_plate_row.name = "StagePlates"
	_plate_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_plate_row.add_theme_constant_override("separation", 8)
	_plate_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_plate_row)

	_extra_label = Label.new()
	_extra_label.name = "StageExtra"
	_extra_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(_extra_label, "faint", 1, 11)
	_extra_label.visible = false
	column.add_child(_extra_label)


## 闸门必须是**后加的兄弟节点**：同一层里后加的子节点画在上层。
## 若在本控件的 `_draw` 里画，会被台面这个子节点盖住 —— 那样闸门等于关不上。
func _build_shutter() -> void:
	_shutter = ShutterLayer.new()
	_shutter.name = "ShutterLayer"
	_shutter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shutter)


func _fill_stage(entries: Array) -> void:
	_plate_names.clear()
	if _plate_row == null:
		return
	for child in _plate_row.get_children():
		_plate_row.remove_child(child)
		child.queue_free()
	for index in range(entries.size()):
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			continue
		if index >= MAX_PLATES:
			break
		_plate_row.add_child(_build_plate(entry as Dictionary))
	var extra := entries.size() - MAX_PLATES
	_extra_label.visible = extra > 0
	if extra > 0:
		_extra_label.text = "另有 %d 件已入包" % extra


## 一块产物：3D 模型图标 + 名字 + 「品质 · 弹种」。
##
## 走 `ItemModelIcon3D` 而不是贴图标，是为了让"里头的东西"和背包里那把枪
## 是同一个模型 —— 玩家一眼认出这就是刚造出来的那把。
func _build_plate(item: Dictionary) -> Control:
	var plate := VBoxContainer.new()
	plate.add_theme_constant_override("separation", 2)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := ICON_SCENE.instantiate() as Control
	if icon != null:
		icon.name = "PlateIcon"
		icon.custom_minimum_size = Vector2(104, 78)
		icon.set("icon_resolution", 256)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(icon)
		if icon.has_method("configure"):
			icon.call("configure", item)

	var name_label := Label.new()
	var display_name := str(item.get("name", "武器"))
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(104, 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var rarity_color := _rarity_color(str(item.get("rarity", "common")))
	name_label.add_theme_color_override("font_color", rarity_color)
	name_label.add_theme_font_size_override("font_size", 13)
	plate.add_child(name_label)

	var sub := Label.new()
	sub.text = _plate_subtitle(item)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(104, 0)
	sub.clip_text = true
	UIStyleFactory.apply_prism_label(sub, "faint", 1, 10)
	plate.add_child(sub)

	_plate_names.append(display_name)
	return plate


## 副行：品质 + 弹种。近战没有弹种，不写"无"。
func _plate_subtitle(item: Dictionary) -> String:
	var parts: Array[String] = []
	var grade := str(item.get("drop_grade", ""))
	if not grade.is_empty():
		parts.append(WeaponDropGrade.display_name(grade))
	var bullet := str(item.get("bullet_module_id", ""))
	if not bullet.is_empty():
		var definition := ItemRegistry.get_instance().get_item(bullet)
		var bullet_name := str(definition.get("name", bullet))
		if not bullet_name.is_empty():
			parts.append(bullet_name)
	return " · ".join(parts) if not parts.is_empty() else str(item.get("rarity", ""))


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"legendary":
			return UIPalette.SOUL_GOLD
		"epic":
			return UIPalette.PRISM_EPIC
		"rare":
			return UIPalette.PRISM_ACCENT
		"uncommon":
			return UIPalette.NEON_MINT
		_:
			return UIPalette.PRISM_TEXT


# ————————————————————————————————
# 绘制层
# ————————————————————————————————

## 闸门本体。单独一个节点是为了拿到「后加的子节点画在上层」这个顺序。
##
## 纯几何绘制，不用贴图：闸门是机器自带的面板标识，贴图缩放会糊，
## 还多一份资源要跟美术对版本。
class ShutterLayer extends Control:
	## 顶部铭牌条高度与左右导轨宽度。三处绘制共用，避免各自写死一套数字。
	const HEADER_H := 26.0
	const RAIL_W := 10.0
	## 底部警示条高度。
	const LIP_H := 13.0

	var progress := 0.0
	var eyes := 0.0
	var land := 0.0
	var clock := 0.0
	var closing_motion := 0.0

	func _draw() -> void:
		if progress <= 0.001:
			return
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		# 整块板从上方滑下来：闭合度 1 时顶边正好贴住 y=0。
		# 顶边 y = -h * (1 - 闭合度)，画出上边界的部分由父级 `clip_contents` 裁掉。
		var offset := -h * (1.0 - progress)
		# 落地余震只抖 1~2px；再大就不是"重"，是"UI 坏了"。
		if land > 0.0:
			offset += sin(clock * 92.0) * 2.0 * land
		_draw_panel(w, h, offset)
		_draw_emblem(Vector2(w * 0.5, offset + h * 0.47), minf(w, h) * 0.24)
		_draw_leading_edge(w, h, offset)

	func _draw_panel(w: float, h: float, offset: float) -> void:
		var top := Color(0.118, 0.137, 0.165, 1.0)
		var bottom := Color(0.031, 0.039, 0.052, 1.0)
		draw_polygon(
			PackedVector2Array([
				Vector2(0.0, offset), Vector2(w, offset),
				Vector2(w, offset + h), Vector2(0.0, offset + h),
			]),
			PackedColorArray([top, top, bottom, bottom])
		)

		# 斜向高光：一道很宽的浅色斜带。**不用等宽竖条** ——
		# 等宽竖条会和横节一起被读成"网格"，看起来像底下那块棋盘透上来了。
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(0.0, offset + h * 0.62), Vector2(0.0, offset + h * 0.10),
				Vector2(w * 0.55, offset), Vector2(w, offset + h * 0.06),
				Vector2(w, offset + h * 0.30),
			]),
			Color(1.0, 1.0, 1.0, 0.022)
		)

		# 徽标底座：一条横贯的加固带，把圆牌"装"在门上。
		# 不加这条，圆牌像浮在半空的贴纸；加了之后它是门上的一块结构件。
		var band_h := minf(h * 0.46, w * 0.62)
		var band_y := offset + h * 0.47 - band_h * 0.5
		draw_rect(Rect2(0.0, band_y, w, band_h), Color(0.0, 0.0, 0.0, 0.16))
		draw_line(Vector2(0.0, band_y), Vector2(w, band_y), Color(1.0, 1.0, 1.0, 0.07), 1.0)
		draw_line(
			Vector2(0.0, band_y + band_h), Vector2(w, band_y + band_h),
			Color(1.0, 1.0, 1.0, 0.05), 1.0
		)

		# 横向卷帘节：每 22px 一道「上亮下暗」，是闸门最容易被认出来的结构。
		# 不再画竖向拼板缝 —— 竖缝 + 横节 = 一眼看成网格，与底下那块棋盘混淆。
		var y := offset + HEADER_H + 22.0
		while y < offset + h - LIP_H - 6.0:
			draw_line(Vector2(0.0, y), Vector2(w, y), Color(1.0, 1.0, 1.0, 0.048), 1.0)
			draw_line(Vector2(0.0, y + 2.0), Vector2(w, y + 2.0), Color(0.0, 0.0, 0.0, 0.30), 2.0)
			y += 22.0

		# 左右导轨：10px 宽的亮边 + 内侧 1px 暗缝，闸门才像"卡在框里上下走"。
		for side in [0.0, 1.0]:
			var rail_x := 0.0 if side == 0.0 else w - RAIL_W
			draw_rect(Rect2(rail_x, offset, RAIL_W, h), Color(1.0, 1.0, 1.0, 0.035))
			var inner := rail_x + RAIL_W if side == 0.0 else rail_x - 1.0
			draw_line(
				Vector2(inner, offset), Vector2(inner, offset + h),
				Color(0.0, 0.0, 0.0, 0.55), 1.0
			)
			# 导轨上的螺栓：每 26px 一颗，是"机械结构"最便宜也最有效的信号。
			var bolt_y := offset + HEADER_H + 14.0
			while bolt_y < offset + h - LIP_H - 8.0:
				var bolt := Vector2(rail_x + RAIL_W * 0.5, bolt_y)
				draw_circle(bolt, 2.0, Color(0.62, 0.67, 0.75, 0.30))
				draw_circle(bolt + Vector2(-0.6, -0.6), 0.9, Color(0.86, 0.90, 0.96, 0.45))
				bolt_y += 26.0

		_draw_header(w, offset)
		draw_rect(Rect2(0.0, offset, w, h), Color(1.0, 1.0, 1.0, 0.11), false, 1.0)

	## 闸门顶部的铭牌条：一行机器编号 + 一颗状态灯。
	##
	## 状态灯在眼睛点亮时一起转红 —— 玩家盯的是兔子，但状态灯给了他
	## 「整台机器在通电」的第二处证据，只有眼睛亮会显得像贴图动效。
	func _draw_header(w: float, offset: float) -> void:
		draw_rect(Rect2(0.0, offset, w, HEADER_H), Color(0.055, 0.066, 0.082, 1.0))
		draw_line(
			Vector2(0.0, offset + HEADER_H), Vector2(w, offset + HEADER_H),
			Color(1.0, 1.0, 1.0, 0.16), 1.0
		)
		var font := ThemeDB.fallback_font
		if font == null:
			return
		var lamp := Vector2(RAIL_W + 16.0, offset + HEADER_H * 0.5)
		var lamp_color := Color(0.24, 0.34, 0.40, 0.9).lerp(Color(1.0, 0.20, 0.16, 1.0), eyes)
		if eyes > 0.02:
			draw_circle(lamp, 6.5, Color(1.0, 0.12, 0.10, 0.16 * eyes))
		draw_circle(lamp, 3.2, lamp_color)
		draw_string(
			font, Vector2(RAIL_W + 28.0, offset + HEADER_H * 0.5 + 4.0),
			"SYNTHESIS LOCK  ·  RABBIT SEAL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10,
			Color(0.62, 0.68, 0.78, 0.92)
		)
		draw_string(
			font, Vector2(0.0, offset + HEADER_H * 0.5 + 4.0),
			"№ 02", HORIZONTAL_ALIGNMENT_RIGHT, w - RAIL_W - 12.0, 10,
			Color(0.40, 0.45, 0.53, 0.85)
		)

	## 迎料边：闸门最下面那道黄黑警示条 + 下滑时的一条暖色余辉。
	##
	## 它是**下降的前沿**，位置一直在变 —— 有这条边，玩家才看得出"门在往下压"，
	## 否则一块匀速变大的深色矩形读不出方向。
	func _draw_leading_edge(w: float, h: float, offset: float) -> void:
		var lip_h := LIP_H
		var lip_y := offset + h - lip_h
		draw_rect(Rect2(0.0, lip_y, w, lip_h), Color(0.020, 0.020, 0.026, 1.0))
		var stripe := 15.0
		var x := -lip_h
		while x < w + lip_h:
			draw_line(
				Vector2(x, lip_y + lip_h), Vector2(x + lip_h, lip_y),
				Color(0.98, 0.72, 0.16, 0.82), 5.0
			)
			x += stripe
		draw_line(Vector2(0.0, lip_y), Vector2(w, lip_y), Color(1.0, 0.85, 0.45, 0.55), 1.0)
		# 迎料边下方的深色投影：门落到一半时，下面的东西该被"压出"一道暗边。
		draw_rect(Rect2(0.0, lip_y + lip_h, w, 6.0), Color(0.0, 0.0, 0.0, 0.55 * progress))
		if closing_motion > 0.02:
			draw_rect(
				Rect2(0.0, lip_y - 6.0, w, 6.0),
				Color(1.0, 0.72, 0.30, 0.16 * closing_motion)
			)

	## 徽标：一块铆死的金属圆牌，兔子铸在牌面中央。
	##
	## 为什么不把兔子画大：闸门是**机器**，标识只是它身上的一枚封印。
	## 把兔子直接铺满整块板会变成"一只大兔子贴纸"，失掉"这是一道门"的语义。
	func _draw_emblem(center: Vector2, plate_radius: float) -> void:
		var R := plate_radius
		draw_circle(center, R, Color(0.030, 0.037, 0.049, 1.0))
		# 牌面内侧一圈更暗的凹陷，让圆牌不是一块平盘。
		draw_circle(center, R * 0.90, Color(0.021, 0.026, 0.035, 1.0))
		draw_arc(center, R - 0.5, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.24), 2.0, true)
		draw_arc(center, R * 0.90, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.07), 1.0, true)
		# 八颗锁死螺栓：这是"封印"的具体形状。
		for index in 8:
			var angle := TAU * float(index) / 8.0 + PI / 8.0
			var bolt := center + Vector2(cos(angle), sin(angle)) * (R * 0.955)
			draw_circle(bolt, 2.6, Color(0.14, 0.16, 0.20, 1.0))
			draw_circle(bolt + Vector2(-0.7, -0.7), 1.2, Color(0.58, 0.63, 0.71, 0.55))

		# 眼睛亮起时牌面泛红：只亮两个红点会像贴上去的，整块牌要有反应。
		if eyes > 0.02:
			draw_circle(center, R * 0.90, Color(1.0, 0.10, 0.12, 0.075 * eyes))
			draw_arc(center, R * 0.92, 0.0, TAU, 96, Color(1.0, 0.16, 0.14, 0.30 * eyes), 2.0, true)

		var fur := Color(0.80, 0.84, 0.89, 0.94)
		var fur_shadow := Color(0.44, 0.49, 0.57, 0.92)

		# 兔子本体：耳长头圆，耳先画、头盖上去，接缝自然。
		var r := R * 0.50
		var body := center + Vector2(0.0, R * 0.05)
		for side in [-1.0, 1.0]:
			var ear_center := body + Vector2(side * r * 0.36, -r * 0.98)
			var rot := deg_to_rad(side * 10.0)
			draw_colored_polygon(_ellipse(ear_center, r * 0.17, r * 0.50, rot), fur)
			draw_colored_polygon(_ellipse(ear_center, r * 0.095, r * 0.34, rot), fur_shadow)

		var head := body
		draw_circle(head, r * 0.56, fur)
		# 下巴阴影：偏下的暗弧，给平面剪影一点体积。
		draw_arc(
			head + Vector2(0.0, r * 0.12), r * 0.48, deg_to_rad(20.0), deg_to_rad(160.0),
			32, Color(0.30, 0.34, 0.41, 0.30), 2.0, true
		)

		draw_colored_polygon(
			PackedVector2Array([
				head + Vector2(0.0, r * 0.17),
				head + Vector2(-r * 0.068, r * 0.07),
				head + Vector2(r * 0.068, r * 0.07),
			]),
			fur_shadow
		)
		for side in [-1.0, 1.0]:
			for tilt in [-0.12, 0.02, 0.16]:
				var from := head + Vector2(side * r * 0.19, r * 0.12)
				draw_line(
					from, from + Vector2(side * r * 0.30, r * tilt),
					Color(1.0, 1.0, 1.0, 0.22), 1.0
				)

		# 眼睛最后画：红光必须压在毛色之上。
		for side in [-1.0, 1.0]:
			_draw_eye(head + Vector2(side * r * 0.225, -r * 0.06), r, side)

	func _draw_eye(pos: Vector2, r: float, side: float) -> void:
		var socket := Color(0.10, 0.12, 0.16, 1.0)
		var hot := Color(1.0, 0.14, 0.16, 1.0)
		draw_circle(pos, r * 0.078, socket.lerp(hot, eyes))
		if eyes <= 0.02:
			return
		# 两只眼用不同相位，避免"整块板在闪"的廉价感。
		var pulse := 1.0 + 0.16 * sin(clock * 7.4 + side * 1.7)
		for layer in range(4, 0, -1):
			var glow_radius := r * (0.078 + 0.095 * float(layer)) * pulse
			draw_circle(pos, glow_radius, Color(1.0, 0.10, 0.12, 0.052 * eyes / float(layer)))
		# 芯部提亮到近白：红光没有芯会脏成"暗红点"。
		draw_circle(pos, r * 0.050, hot.lerp(Color(1.0, 0.94, 0.90, 1.0), eyes * 0.55))

	func _ellipse(center: Vector2, rx: float, ry: float, rot: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		var segments := 28
		for index in segments:
			var angle := TAU * float(index) / float(segments)
			points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry).rotated(rot))
		return points
