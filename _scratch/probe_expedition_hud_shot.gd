extends Node
## 临时探针：跑远征关卡 01，等 HUD 就绪后打印关键节点状态并截图存证。
## 用于核对「去掉头像格 / 任务卡背板 / 状态栏 / 雷达 / 状态块背板 / 底栏框 / 世界时间背板」。

const MAIN_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_S := 12.0

var _elapsed := 0.0
var _captured := false
var _main: Node = null


func _ready() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	if _captured:
		return
	_elapsed += delta
	if _elapsed < WAIT_S:
		return
	_captured = true
	_report()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://outputs/hud_weapon_bar_after_r5_20260928.png")
	print("PROBE_HUD_SHOT_OK size=", img.get_size())
	get_tree().quit()


## 打印一个 Control 的几何与 stylebox 透明度。alpha 是「背板是否还在」的唯一硬判据：
## 全透明外壳 alpha=0.0，任何残留深色底都会 > 0。
func _dump_panel(tag: String, panel: Control) -> void:
	if panel == null:
		print("PROBE_", tag, "=0")
		return
	var alpha := -1.0
	var border := -1
	var shadow := -1
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		alpha = style.bg_color.a
		border = style.border_width_left
		shadow = style.shadow_size
	print(
		"PROBE_", tag,
		" visible=", panel.visible,
		" pos=", panel.global_position,
		" size=", panel.size,
		" bg_alpha=", alpha,
		" border_w=", border,
		" shadow=", shadow
	)


func _report() -> void:
	var ref_root := _main.get_node_or_null("HUD/ReferenceCombatHUD") as Control
	if ref_root == null:
		print("PROBE_REF_ROOT=0")
	else:
		print("PROBE_REF_ROOT=1")
		# 全量扫描：ReferenceCombatHUD 下每一个 PanelContainer 的背板透明度。
		# 漏一个就是「背板没去干净」，比逐个人肉列名字可靠。
		for child in ref_root.get_children():
			var panel := child as PanelContainer
			if panel == null:
				continue
			_dump_panel("PANEL_" + str(panel.name), panel)
		var ps := ref_root.find_child("PlayerStatusBlock", true, false) as Control
		if ps == null:
			print("PROBE_PLAYER_STATUS=0")
		else:
			print("PROBE_PLAYER_STATUS=1 visible=", ps.visible, " size=", ps.size)
			for g in ps.find_children("*", "", true, false):
				if g is CodeHUDGlyph:
					print("PROBE_PORTRAIT_GLYPH visible=", (g as Control).visible)
		var wt := ref_root.get_node_or_null("WorldDateTimeHUD") as Control
		_dump_panel("WORLD_TIME", wt)
		if wt != null:
			for l in wt.find_children("*", "Label", true, false):
				print("PROBE_WORLD_TIME_TEXT=", (l as Label).text)
		# 计时栏已显式命名 SessionTimerPanel，直接按名字取；再用「按内容猜」的旧办法
		# 交叉验证一次 —— 两种方式若指向同一块，说明命名生效且没有第二块含糊的面板。
		_dump_panel("TIMER_BY_NAME", ref_root.get_node_or_null("SessionTimerPanel") as Control)
		_dump_panel("TIMER_BY_CONTENT", _find_timer_panel(ref_root))
		# 第五轮：武器栏精简 + 挪右下角。逐 Label 打印可见性与字号（字号是「字体放大」的硬判据），
		# 并给出面板右/下边到 canvas 边缘的距离（=0 附近才算「右下角」）。
		var wp := ref_root.get_node_or_null("CurrentWeaponPanel") as Control
		_dump_panel("WEAPON_PANEL", wp)
		if wp != null:
			var r := wp.get_global_rect()
			print(
				"PROBE_WEAPON_CORNER canvas=", ref_root.size, " rect=", r,
				" right_gap=", ref_root.size.x - r.end.x,
				" bottom_gap=", ref_root.size.y - r.end.y
			)
			for l in wp.find_children("*", "Label", true, false):
				var wl := l as Label
				print(
					"PROBE_WEAPON_LABEL name=", wl.name,
					" visible=", wl.visible,
					" font=", wl.get_theme_font_size("font_size"),
					" text=[", wl.text, "]"
				)
			for g in wp.find_children("*", "HBoxContainer", true, false):
				print("PROBE_WEAPON_ROW alignment=", (g as HBoxContainer).alignment)
			var ico := wp.find_child("CurrentWeaponModelIcon3D", true, false) as Control
			print("PROBE_WEAPON_ICON=", ("1 size=" + str(ico.size) if ico != null else "0"))
	var mm := _main.get_node_or_null("HUD/DungeonMinimap3D") as Control
	if mm == null:
		print("PROBE_MINIMAP=0")
	else:
		print("PROBE_MINIMAP=1 visible=", mm.visible, " size=", mm.size)
	var tower_info := _main.get_node_or_null("HUD/TowerCurrentInfoHUD") as Control
	if tower_info == null:
		print("PROBE_TOWER_INFO=0")
	else:
		print("PROBE_TOWER_INFO=1")
		for l in tower_info.find_children("*", "Label", true, false):
			print("PROBE_TOWER_LABEL=", (l as Label).text)


func _find_timer_panel(ref_root: Control) -> Control:
	var digits := RegEx.new()
	digits.compile("^\\d\\d:\\d\\d$")
	for child in ref_root.get_children():
		var panel := child as PanelContainer
		if panel == null:
			continue
		for l in panel.find_children("*", "Label", true, false):
			if digits.search((l as Label).text) != null:
				return panel
	return null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
