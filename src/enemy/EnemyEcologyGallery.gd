class_name EnemyEcologyGallery
extends Node2D

const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const DISPLAY_CASES: Array[Dictionary] = [
	{"kind": "melee_chaser", "ai": "chase", "name": "小菌猪", "role": "近战追击", "color": Color(0.95, 0.28, 0.24), "position": Vector2(-410, -140)},
	{"kind": "ranged_caster", "ai": "ranged", "name": "孢子射手", "role": "侧翼远程", "color": Color(0.62, 0.35, 1.0), "position": Vector2(0, -140)},
	{"kind": "summoner", "ai": "summoner", "name": "蜂巢怪", "role": "召唤支援", "color": Color(0.95, 0.70, 0.16), "position": Vector2(410, -140)},
	{"kind": "shielded", "ai": "chase", "name": "壳甲卫兵", "role": "重甲前排", "color": Color(0.35, 0.62, 0.95), "position": Vector2(-410, 190)},
	{"kind": "exploder", "ai": "bomber", "name": "炸弹果", "role": "近距自爆", "color": Color(1.0, 0.58, 0.14), "position": Vector2(0, 190)},
	{"kind": "ambusher", "ai": "trapper", "name": "地刺虫", "role": "破土伏击", "color": Color(0.78, 0.28, 0.88), "position": Vector2(410, 190)},
]


func _ready() -> void:
	for case in DISPLAY_CASES:
		var enemy := ENEMY_SCENE.instantiate() as CharacterBody2D
		enemy.name = str(case["kind"]).to_pascal_case()
		enemy.set("awareness_enabled", false)
		enemy.set("ai_type", case["ai"])
		enemy.call("set_enemy_data", {
			"enemy_type": case["kind"],
			"ai_type": case["ai"],
			"emoji": "legacy",
			"color": case["color"],
			"scale": 1.0,
		})
		add_child(enemy)
		enemy.position = case["position"]
		enemy.set_physics_process(false)
		enemy.call("_update_hp_bar", true)
		_add_caption(case)
	queue_redraw()


func get_display_count() -> int:
	return DISPLAY_CASES.size()


func _add_caption(case: Dictionary) -> void:
	var label := Label.new()
	label.position = (case["position"] as Vector2) + Vector2(-110, 74)
	label.size = Vector2(220, 55)
	label.text = "%s\n%s  ·  %s" % [case["name"], case["role"], case["kind"]]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.94))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.03, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)


func _draw() -> void:
	draw_rect(Rect2(-640, -360, 1280, 720), Color(0.025, 0.045, 0.052), true)
	for case in DISPLAY_CASES:
		var pos: Vector2 = case["position"]
		draw_rect(Rect2(pos - Vector2(175, 120), Vector2(350, 255)), Color(0.045, 0.073, 0.08, 0.92), true)
		draw_rect(Rect2(pos - Vector2(175, 120), Vector2(350, 255)), Color(0.17, 0.35, 0.39, 0.72), false, 2.0)
		draw_line(pos + Vector2(-145, 54), pos + Vector2(145, 54), Color(0.2, 0.42, 0.44, 0.38), 2.0)
		for tick in range(-120, 121, 30):
			draw_line(pos + Vector2(tick, 48), pos + Vector2(tick, 60), Color(0.34, 0.58, 0.58, 0.4), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-600, -318), "HOSTILE ECOLOGY / SILHOUETTE BOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(0.68, 0.92, 0.96))
	draw_string(ThemeDB.fallback_font, Vector2(-600, -286), "体型、重心、轮廓和战术职责对照  ·  可直接替换 AvatarRenderer", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.42, 0.64, 0.68))
