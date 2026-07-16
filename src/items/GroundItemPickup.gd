class_name GroundItemPickup
extends Node2D
## 怪物战利品地面拾取物：先留在战场上，玩家靠近后才尝试收入背包。

const COLLECT_RADIUS := 54.0
const BOB_SPEED := 2.0
const BOB_AMOUNT := 4.0

var item_data: Dictionary = {}
var _game_mode: Node = null
var _player: Node2D = null
var _time := 0.0
var _collect_retry_time := 0.0
var _collected := false
var _body: Polygon2D
var _label: Label
var _count_label: Label
var _pulse_ring: Polygon2D  ## 呼吸光圈（持续脉动）
var _pulse_tween: Tween = null


func setup(game_mode: Node, data: Dictionary) -> void:
	_game_mode = game_mode
	item_data = data.duplicate(true)


func _ready() -> void:
	z_index = 170
	_build_visuals()
	scale = Vector2(0.45, 0.45)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.2)


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	_collect_retry_time = maxf(0.0, _collect_retry_time - delta)
	if _body != null:
		_body.position.y = sin(_time * BOB_SPEED) * BOB_AMOUNT
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		return
	if global_position.distance_to(_player.global_position) <= COLLECT_RADIUS:
		_try_collect()


func _try_collect() -> void:
	if _collect_retry_time > 0.0 or _game_mode == null:
		return
	_collect_retry_time = 0.35
	if not _game_mode.has_method("collect_ground_item"):
		return
	var added := int(_game_mode.call("collect_ground_item", item_data))
	if added <= 0:
		return
	var remaining := int(item_data.get("count", 1)) - added
	if remaining > 0:
		item_data["count"] = remaining
		_update_count_label()
		return
	# 拾取涟漪（根据物品类型选颜色）
	_pickup_ripple()
	_collected = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.2, 0.2), 0.12)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(queue_free)


## 拾取时生成涟漪
func _pickup_ripple() -> void:
	var pickup_type: String = "item"
	match str(item_data.get("type", "")):
		"weapon": pickup_type = "gold"  # 武器用金色
		"key": pickup_type = "gold"
	SparkParticles.spawn_pickup_ripple(global_position, pickup_type)


func _build_visuals() -> void:
	var accent := _item_color()
	# 呼吸光圈（持续脉动，让物品更显眼）
	_pulse_ring = Polygon2D.new()
	_pulse_ring.color = Color(accent.r, accent.g, accent.b, 0.35)
	_pulse_ring.polygon = _make_diamond(15.0)
	_pulse_ring.z_index = z_index - 1
	add_child(_pulse_ring)
	# 启动呼吸动画
	_start_pulse_animation()

	var glow := Polygon2D.new()
	glow.color = Color(accent.r, accent.g, accent.b, 0.25)
	glow.polygon = _make_diamond(18.0)
	glow.z_index = z_index - 1
	add_child(glow)

	_body = Polygon2D.new()
	_body.color = accent
	_body.polygon = _make_diamond(11.0)
	_body.z_index = z_index
	add_child(_body)

	_label = Label.new()
	_label.text = _item_glyph()
	_label.position = Vector2(-12, -10)
	_label.size = Vector2(24, 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12, 1.0))
	_label.z_index = z_index + 1
	add_child(_label)

	var name_label := Label.new()
	name_label.text = str(item_data.get("name", "战利品"))
	name_label.position = Vector2(-48, -40)
	name_label.size = Vector2(96, 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", accent)
	name_label.z_index = z_index + 1
	add_child(name_label)

	_count_label = Label.new()
	_count_label.position = Vector2(14, 4)
	_count_label.add_theme_font_size_override("font_size", 10)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.z_index = z_index + 1
	add_child(_count_label)
	_update_count_label()


func _update_count_label() -> void:
	if _count_label == null:
		return
	var count := int(item_data.get("count", 1))
	_count_label.text = "x%d" % count if count > 1 else ""


## 启动呼吸光圈动画（0.9s 循环：scale 0.8->1.3, alpha 0.5->0）
func _start_pulse_animation() -> void:
	if _pulse_ring == null:
		return
	_pulse_ring.scale = Vector2(0.8, 0.8)
	_pulse_ring.modulate = Color(1, 1, 1, 0.7)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(_pulse_ring, "scale", Vector2(1.4, 1.4), 0.9)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_pulse_ring, "modulate:a", 0.0, 0.9)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.chain().tween_callback(_reset_pulse)


func _reset_pulse() -> void:
	if _pulse_ring == null:
		return
	_pulse_ring.scale = Vector2(0.8, 0.8)
	_pulse_ring.modulate = Color(1, 1, 1, 0.7)


func _item_color() -> Color:
	match str(item_data.get("type", "")):
		"weapon":
			return Color(0.35, 0.8, 1.0)
		"attachment", "module":
			return Color(0.5, 0.95, 0.75)
		"key":
			return Color(1.0, 0.78, 0.22)
		_:
			return Color(0.95, 0.7, 0.42)


func _item_glyph() -> String:
	match str(item_data.get("type", "")):
		"weapon":
			return "GUN"
		"attachment", "module":
			return "MOD"
		"key":
			return "KEY"
		_:
			return "ITM"


func _make_diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)]
	)
