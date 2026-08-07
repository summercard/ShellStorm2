class_name SoulOrb
extends Node2D

## 魂魄掉落物 — 敌人死亡后从尸体位置生成
## 自动漂浮展示，有吸附动画，被玩家靠近时自动拾取并飘向玩家

## 信号
signal collected(amount: int, orb: SoulOrb)

## 配置
const COLLECT_RADIUS := 68.0   # 玩家靠近此距离即自动拾取
const ATTRACT_SPEED := 380.0   # 吸附速度（像素/秒）
const BOB_SPEED := 2.2         # 上下漂浮频率
const BOB_AMOUNT := 5.0        # 漂浮幅度（像素）
const SCALE_IN := 0.45         # 入场缩放
const SCALE_NORMAL := 1.0

var amount: int = 5
var _player: Node2D = null
var _orb_body: Polygon2D
var _orb_glow: Polygon2D
var _pulse_ring: Polygon2D  ## 呼吸光圈
var _pulse_tween: Tween = null
var _amount_label: Label
var _base_y: float = 0.0
var _time: float = 0.0
var _collected: bool = false
var _tween: Tween = null

func _init() -> void:
	z_index = 150
	process_mode = Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	_setup_visuals()
	_spawn_animation()
	# 通知GameManager有新的魂魄掉落（用于统计）
	if GameManager and GameManager.has_method("on_soul_orb_spawned"):
		GameManager.on_soul_orb_spawned(self)

## 构建视觉：绿色发光球体 + 魂数量
func _setup_visuals() -> void:
	# 呼吸光圈（持续脉动，让魂更容易被注意到）
	_pulse_ring = Polygon2D.new()
	_pulse_ring.name = "PulseRing"
	_pulse_ring.color = Color(0.3, 1.0, 0.5, 0.45)
	_pulse_ring.polygon = _make_circle_polygon(10.0)
	_pulse_ring.z_index = z_index - 2
	add_child(_pulse_ring)
	_start_pulse_animation()

	# 外发光圈
	_orb_glow = Polygon2D.new()
	_orb_glow.name = "OrbGlow"
	_orb_glow.color = Color(0.2, 1.0, 0.5, 0.35)
	_orb_glow.polygon = _make_circle_polygon(12.0)
	_orb_glow.z_index = z_index - 1
	add_child(_orb_glow)

	# 主体球
	_orb_body = Polygon2D.new()
	_orb_body.name = "OrbBody"
	_orb_body.color = Color(0.35, 1.0, 0.5, 1.0)
	_orb_body.polygon = _make_circle_polygon(8.0)
	_orb_body.z_index = z_index
	add_child(_orb_body)

	# 魂数量标签
	_amount_label = Label.new()
	_amount_label.name = "AmountLabel"
	_amount_label.text = "+%d" % amount
	_amount_label.add_theme_color_override("font_color", Color(0.15, 1.0, 0.4, 1.0))
	_amount_label.add_theme_font_size_override("font_size", 11)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount_label.z_index = z_index + 1
	_amount_label.position = Vector2(-14.0, -20.0)
	add_child(_amount_label)

func _make_circle_polygon(radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(12):
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

## 入场缩放动画
func _spawn_animation() -> void:
	scale = Vector2(SCALE_IN, SCALE_IN)
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "scale", Vector2.ONE * SCALE_NORMAL, 0.22)

## 每帧：漂浮动画 + 吸附逻辑
func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	# 漂浮
	var bob_offset := sin(_time * BOB_SPEED) * BOB_AMOUNT
	if has_node("OrbBody"):
		_orb_body.position.y = bob_offset
	if has_node("OrbGlow"):
		_orb_glow.position.y = bob_offset * 0.8

	# 找玩家
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	var to_player := _player.global_position - global_position
	var dist := to_player.length()

	# 吸附
	if dist < COLLECT_RADIUS:
		var dir := to_player.normalized()
		global_position += dir * ATTRACT_SPEED * delta
		if dist < 18.0:
			_collect()
	else:
		# 轻微向玩家方向倾斜（视觉提示）
		rotation = to_player.normalized().angle() * 0.15

## 拾取
func _collect() -> void:
	if _collected:
		return
	_collected = true
	# 拾取涟漪（魂用紫色）
	SparkParticles.spawn_pickup_ripple(global_position, "soul")
	if AudioManager != null:
		AudioManager.play_sfx("soul_pickup", -4.0, randf_range(0.97, 1.03))
	collected.emit(amount, self)
	# 收集动画：快速缩小+淡出
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2(0.2, 0.2), 0.12)
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	t.chain().tween_callback(queue_free)

## 设置魂魄数量（生成后调用）
func set_amount(val: int) -> void:
	amount = val
	if _amount_label:
		_amount_label.text = "+%d" % amount


## 启动呼吸光圈动画（0.8s 循环：scale 0.9->1.5, alpha 0.6->0）
func _start_pulse_animation() -> void:
	if _pulse_ring == null:
		return
	_pulse_ring.scale = Vector2(0.9, 0.9)
	_pulse_ring.modulate = Color(1, 1, 1, 0.7)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(_pulse_ring, "scale", Vector2(1.6, 1.6), 0.8)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_pulse_ring, "modulate:a", 0.0, 0.8)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.chain().tween_callback(func():
		if _pulse_ring and is_instance_valid(_pulse_ring):
			_pulse_ring.scale = Vector2(0.9, 0.9)
			_pulse_ring.modulate = Color(1, 1, 1, 0.7)
	)
