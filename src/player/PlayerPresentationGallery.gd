class_name PlayerPresentationGallery
extends Node2D
## 玩家六态与叠加状态的代码原生验收板；正式资产可直接替换 AvatarRenderer。

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const CASES: Array[Dictionary] = [
	{"state": "idle", "title": "IDLE · 待命", "note": "呼吸 / 稳定核心", "position": Vector2(220, 235)},
	{"state": "moving", "title": "MOVING · 机动", "note": "方向倾斜 / 两步步态", "position": Vector2(640, 235)},
	{"state": "dashing", "title": "DASHING · 突进", "note": "轮廓拉伸 / 推进尾迹", "position": Vector2(1060, 235)},
	{"state": "hurt", "title": "HURT · 受创", "note": "冲击压缩 / CRITICAL", "position": Vector2(220, 520), "low": true},
	{"state": "locked", "title": "LOCKED · 交互锁定", "note": "保险圆环 / JAMMED", "position": Vector2(640, 520), "silenced": true},
	{"state": "dead", "title": "DEAD · 生命终止", "note": "倾倒 / 面罩熄灭", "position": Vector2(1060, 520)},
]

var _players: Array[Player] = []


func _ready() -> void:
	for case in CASES:
		var player := PLAYER_SCENE.instantiate() as Player
		player.position = case["position"]
		player.scale = Vector2.ONE * 1.65
		add_child(player)
		player.set_physics_process(false)
		var aim := player.get_node_or_null("Aim") as CanvasItem
		var weapon := player.get_node_or_null("WeaponAnchor") as CanvasItem
		if aim != null:
			aim.visible = false
		if weapon != null:
			weapon.visible = false
		if bool(case.get("low", false)):
			player.current_hp = 24
			player.call("_update_low_health_state")
		if bool(case.get("silenced", false)):
			player.set("_is_silenced", true)
			player.set("_silence_timer", 9.9)
		var state_machine := player.get("_state_machine") as StateMachine
		state_machine.transition_to(str(case["state"]), true)
		if str(case["state"]) == "dead":
			player.set_combat_enabled(false)
		_players.append(player)
		_add_caption(case)
	queue_redraw()


func get_display_count() -> int:
	return _players.size()


func _add_caption(case: Dictionary) -> void:
	var center: Vector2 = case["position"]
	var title := Label.new()
	title.position = center + Vector2(-165, 54)
	title.size = Vector2(330, 30)
	title.text = str(case["title"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.78, 0.91, 0.98))
	add_child(title)
	var note := Label.new()
	note.position = center + Vector2(-165, 84)
	note.size = Vector2(330, 24)
	note.text = str(case["note"])
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.46, 0.58, 0.68))
	add_child(note)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.018, 0.027, 0.041), true)
	draw_rect(Rect2(0, 0, 1280, 76), Color(0.028, 0.047, 0.065), true)
	draw_line(Vector2(38, 76), Vector2(1242, 76), Color(0.20, 0.55, 0.66, 0.72), 2.0)
	for case in CASES:
		var center: Vector2 = case["position"]
		var panel := Rect2(center + Vector2(-182, -112), Vector2(364, 220))
		draw_rect(panel, Color(0.035, 0.052, 0.070, 0.88), true)
		draw_rect(panel, Color(0.20, 0.33, 0.40, 0.72), false, 1.0)
		draw_line(center + Vector2(-154, 38), center + Vector2(154, 38), Color(0.12, 0.25, 0.31), 1.0)
	# 标题在程序化对照板中保持固定，便于未来资产替换前后做同构截图。
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, 39), "PLAYER PRESENTATION MATRIX", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.82, 0.94, 1.0))
	draw_string(font, Vector2(40, 64), "SEMANTIC AVATAR SLOT / SIX-STATE CONTRACT / OVERLAY READABILITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.40, 0.65, 0.72))
