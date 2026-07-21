class_name TrainingRackItem
extends Area2D

signal proximity_changed(station: TrainingRackItem, inside: bool)

enum ItemKind {
	GUN,
	AMMO,
}

const INTERACTION_SIZE := Vector2(164.0, 112.0)

var item_id := ""
var display_name := ""
var tier := 0
var tags: Array[String] = []
var item_kind: ItemKind = ItemKind.GUN
var visual_key := ""

var _focused := false
var _selected := false
var _accent := Color(0.3, 0.78, 0.82)


func configure(entry: Dictionary, kind: ItemKind, weapon_visual_key := "") -> void:
	item_id = str(entry.get("item_id", ""))
	display_name = str(entry.get("display_name", item_id))
	tier = int(entry.get("tier", 0))
	tags.assign(entry.get("tags", []))
	item_kind = kind
	visual_key = weapon_visual_key
	_accent = _resolve_accent()
	queue_redraw()


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	z_index = 4

	var collision := CollisionShape2D.new()
	collision.name = "InteractionZone"
	var shape := RectangleShape2D.new()
	shape.size = INTERACTION_SIZE
	collision.shape = shape
	add_child(collision)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	queue_redraw()


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	queue_redraw()


func is_selected() -> bool:
	return _selected


func get_prompt_text() -> String:
	return "[E] 取用枪械" if item_kind == ItemKind.GUN else "[E] 装填弹药"


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		proximity_changed.emit(self, true)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		proximity_changed.emit(self, false)


func _resolve_accent() -> Color:
	if item_kind == ItemKind.AMMO:
		if tags.has("explosive"):
			return Color(1.0, 0.43, 0.2)
		if tags.has("piercing"):
			return Color(0.92, 0.78, 0.28)
		if tags.has("blackhole"):
			return Color(0.7, 0.38, 0.94)
		if tags.has("homing"):
			return Color(0.48, 0.92, 0.54)
		if tags.has("sticky") or tags.has("slow"):
			return Color(0.42, 0.86, 0.68)
		if tags.has("bounce"):
			return Color(0.38, 0.74, 1.0)
		return Color(0.68, 0.86, 0.94)
	match tier:
		0:
			return Color(0.42, 0.78, 0.82)
		1:
			return Color(0.38, 0.68, 0.94)
		2:
			return Color(0.78, 0.5, 0.94)
		_:
			return Color(1.0, 0.62, 0.28)


func _draw() -> void:
	var half := INTERACTION_SIZE * 0.5
	var background := Color(0.035, 0.055, 0.064, 0.96)
	var border := _accent
	if _selected:
		background = _accent.darkened(0.72)
		border = _accent.lightened(0.28)
	elif _focused:
		background = _accent.darkened(0.82)
		border = Color.WHITE.lerp(_accent, 0.45)

	draw_rect(Rect2(-half, INTERACTION_SIZE), background, true)
	draw_rect(Rect2(-half, INTERACTION_SIZE), border, false, 2.0 if _focused or _selected else 1.0)
	draw_line(Vector2(-half.x + 8.0, 26.0), Vector2(half.x - 8.0, 26.0), border.darkened(0.35), 2.0)

	if item_kind == ItemKind.GUN:
		_draw_gun()
	else:
		_draw_ammo()

	draw_string(
		ThemeDB.fallback_font,
		Vector2(-half.x + 8.0, 45.0),
		display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		INTERACTION_SIZE.x - 16.0,
		14,
		Color(0.84, 0.92, 0.94)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-half.x + 8.0, 62.0),
		"T%d  %s" % [tier, "枪身" if item_kind == ItemKind.GUN else "弹药"],
		HORIZONTAL_ALIGNMENT_CENTER,
		INTERACTION_SIZE.x - 16.0,
		11,
		_accent.lightened(0.18)
	)

	if _selected:
		draw_circle(Vector2(half.x - 13.0, -half.y + 13.0), 7.0, _accent)
		draw_circle(Vector2(half.x - 13.0, -half.y + 13.0), 3.0, Color.WHITE)
	if _focused:
		var prompt_width := 124.0
		draw_rect(Rect2(-prompt_width * 0.5, -half.y - 31.0, prompt_width, 24.0), Color(0.02, 0.04, 0.05, 0.96), true)
		draw_rect(Rect2(-prompt_width * 0.5, -half.y - 31.0, prompt_width, 24.0), _accent, false, 1.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-prompt_width * 0.5, -half.y - 14.0),
			get_prompt_text(),
			HORIZONTAL_ALIGNMENT_CENTER,
			prompt_width,
			13,
			Color.WHITE
		)


func _draw_gun() -> void:
	var shape: Dictionary = WeaponDisplay.GUN_SHAPES.get(visual_key, WeaponDisplay.DEFAULT_SHAPE)
	var source: PackedVector2Array = shape.get("polygon", PackedVector2Array())
	var points := PackedVector2Array()
	for point in source:
		points.append(point * 2.15 + Vector2(0.0, -15.0))
	if points.is_empty():
		return
	draw_colored_polygon(points, shape.get("color", _accent).lerp(_accent, 0.34))
	draw_polyline(PackedVector2Array(Array(points) + [points[0]]), _accent.lightened(0.3), 2.0, true)
	draw_line(Vector2(-48.0, 10.0), Vector2(48.0, 10.0), Color(0.22, 0.28, 0.29), 5.0)
	draw_line(Vector2(-36.0, 10.0), Vector2(-36.0, 22.0), Color(0.18, 0.22, 0.23), 4.0)
	draw_line(Vector2(36.0, 10.0), Vector2(36.0, 22.0), Color(0.18, 0.22, 0.23), 4.0)


func _draw_ammo() -> void:
	var center := Vector2(0.0, -14.0)
	draw_rect(Rect2(-48.0, -37.0, 96.0, 46.0), Color(0.08, 0.105, 0.11), true)
	draw_rect(Rect2(-48.0, -37.0, 96.0, 46.0), _accent.darkened(0.2), false, 2.0)
	for i in range(5):
		var x := -34.0 + i * 17.0
		draw_rect(Rect2(x, center.y - 12.0, 8.0, 24.0), _accent.darkened(0.16), true)
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(x, center.y - 12.0),
				Vector2(x + 4.0, center.y - 19.0),
				Vector2(x + 8.0, center.y - 12.0),
			]),
			_accent.lightened(0.2)
		)
	draw_circle(Vector2(0.0, 5.0), 4.0, _accent.lightened(0.3))
