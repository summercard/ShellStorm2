class_name RoomKeyPickup
extends Area2D
## 房间钥匙拾取物：清理房间后掉落，拾取后允许开启一个未开启的门。

var _game_mode: Node = null
var _room_id: int = -1
var _picked := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_build_visuals()

func setup(game_mode: Node, room_id: int) -> void:
	_game_mode = game_mode
	_room_id = room_id

func _build_visuals() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 34.0
	shape.shape = circle
	add_child(shape)

	var body := Polygon2D.new()
	body.name = "KeyBody"
	body.color = Color(1.0, 0.78, 0.22, 1.0)
	body.polygon = PackedVector2Array([
		Vector2(-14, -5), Vector2(7, -5), Vector2(7, -12), Vector2(18, -12),
		Vector2(18, -3), Vector2(11, -3), Vector2(11, 5), Vector2(-14, 5)
	])
	body.z_index = 180
	add_child(body)

	var ring := Polygon2D.new()
	ring.name = "KeyRing"
	ring.color = Color(1.0, 0.92, 0.45, 0.9)
	ring.polygon = _make_circle_polygon(10.0)
	ring.position = Vector2(-20, 0)
	ring.z_index = 181
	add_child(ring)

	var label := Label.new()
	label.text = "钥匙"
	label.position = Vector2(-22, -42)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
	label.z_index = 182
	add_child(label)

	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(self, "position:y", position.y - 8.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", position.y + 8.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _make_circle_polygon(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _on_body_entered(body: Node2D) -> void:
	if _picked or not body.is_in_group("player"):
		return
	_picked = true
	if _game_mode != null and _game_mode.has_method("collect_room_key"):
		_game_mode.call("collect_room_key", _room_id)
	queue_free()
