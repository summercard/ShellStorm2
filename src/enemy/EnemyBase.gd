extends CharacterBody2D

const EnemyModifierScript := preload("res://src/enemy/EnemyModifier.gd")
const ENEMY_PROJECTILE_SCENE := preload("res://scenes/EnemyProjectile.tscn")

signal hp_changed(current: int, maximum: int)
signal enemy_died()
signal enemy_hit(hit_from: Vector2, damage: int, is_crit: bool)
## 当敌人进入 CHASE 追击状态时，向房间的区域刷怪控制器发送警觉信号
signal enemy_entered_chase(enemy: Node, last_known_pos: Vector2)
## 精英怪专属：进入 CHASE 时触发相邻房间 AI 联动（PH11 P2）
signal elite_entered_chase(enemy: Node, last_known_pos: Vector2)

## AI状态机枚举（PH11 警觉AI核心）
enum AIState {
	IDLE = 0,    # 空闲：原地小范围移动，不主动攻击，眼睛正常
	ALERT = 1,   # 警觉：停止、看向玩家方向、头上出现 ❓，计时中
	CHASE = 2,   # 追击：全速追击玩家，头上出现 ❗
	SEARCH = 3,  # 搜索：在最后看到玩家的位置徘徊，眼睛黄+问号
	PATROL = 4,  # 巡逻：沿固定路线巡逻
}

## 警觉感知配置
@export var awareness_enabled: bool = true  # 是否启用警觉AI（false=旧行为，直接chase）
@export var visual_range: float = 350.0    # 视觉感知范围 px
@export var hearing_range: float = 250.0    # 听觉感知范围 px
@export var alert_duration: float = 3.0     # ALERT状态持续时间（秒）
@export var search_duration: float = 5.0    # SEARCH状态持续时间（秒）

@export var max_hp: int = 30
@export var speed: float = 80.0
@export var damage: int = 10
@export var contact_radius: float = 31.0
@export var contact_damage_interval: float = 0.62

var current_hp: int = 30
var player_ref: Node2D = null

var ai_type: String = "chase"       # chase / ranged / summoner / bomber / trapper
var use_default_chase: bool = true

var shoot_interval: float = 1.7
var summon_interval: float = 5.0
var explosion_radius: float = 82.0
var explosion_damage: int = 25
var trigger_radius: float = 120.0

var _shoot_timer: float = 0.0
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _triggered: bool = false
var _exploded: bool = false
var _is_dead: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO
var _modifiers: Array = []
var _enemy_data: Dictionary = {}
var _damage_multiplier: float = 1.0  # 伤害倍率（由环境命运触发器设置）
var _is_elite: bool = false          # 是否为精英怪（PH11 P2: 精英进入CHASE时触发相邻房间AI联动）
var _elite_gun_modules: Array[Dictionary] = []   # 精英偷取的GunBody模块（用于挂枪射击）
var _elite_bullet_modules: Array[Dictionary] = []  # 精英偷取的Bullet模块（用于子弹行为）
var _elite_attachment_modules: Array[Dictionary] = []  # 精英偷取的Attachment模块（用于修饰射击参数）
var _elite_shoot_timer: float = 0.0   # 精英挂枪射击计时器
var _elite_shoot_interval: float = 1.8  # 精英挂枪射击间隔（秒）
var regional_controller_ref: Node = null
var _base_emoji: String = "👾"
var _base_color: Color = Color.WHITE
var _base_scale: float = 1.0
var _state_marker_label: Label = null
var _state_marker_offset_y: float = -58.0  # 名字标签 Y 偏移（位于 emoji 上方）

## AI状态机变量
var _ai_state: AIState = AIState.IDLE
var _alert_timer: float = 0.0       # ALERT状态剩余时间
var _search_timer: float = 0.0       # SEARCH状态剩余时间
var _last_known_player_pos: Vector2 = Vector2.ZERO  # 玩家最后被看到的位置
var _noise_accumulator: float = 0.0  # 声音累积（玩家移动/射击时增加）

## 巡逻变量（PH11 区域AI核心）
var _patrol_waypoints: Array[Vector2] = []  # 当前巡逻路径点列表
var _current_patrol_idx: int = 0             # 当前目标路径点索引
var _patrol_reach_threshold: float = 28.0   # 到达路径点的判定距离
var _patrol_idle_duration: float = 0.0       # 路径点间停顿计时
var _patrol_idle_max: float = 1.2           # 路径点间最大停顿时间
var _room_bounds: Rect2 = Rect2(-GridConstants.ROOM_PIXEL_WIDTH * 0.5, -GridConstants.ROOM_PIXEL_HEIGHT * 0.5, GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)  # 房间边界（居原点）
var _is_in_patrol_mode: bool = false         # 是否正在执行巡逻路径
var _patrol_cooldown: float = 0.0            # 巡逻冷却（防止频繁重新规划）

## 声音累积衰减（每帧减少）
const _NOISE_DECAY_RATE: float = 15.0       # 声音累积每秒衰减量

@onready var shape: ColorRect = $Shape
@onready var emoji_label: Label = get_node_or_null("Emoji") as Label
@onready var hp_bar: ProgressBar = get_node_or_null("HPBarBG/HPBar") as ProgressBar

func set_enemy_data(data: Dictionary) -> void:
	_enemy_data = data.duplicate(true)
	_is_elite = data.get("is_elite", false)
	if data.has("emoji") or data.has("color"):
		set_visuals(data.get("emoji", "👾"), data.get("color", Color(1.0, 0.25, 0.25, 1.0)), float(data.get("scale", 1.0)))
	_set_elite_name_label(data)
	_set_elite_equipment_visual(data)

func get_enemy_data() -> Dictionary:
	return _enemy_data

## 兼容旧调用：部分房间增援逻辑曾把 EnemyBase 当 Dictionary 调用 `.has()`。
func has(property_name: String) -> bool:
	return property_name in [
		"regional_controller_ref",
		"enemy_data",
		"is_elite",
		"ai_type",
		"max_hp",
		"current_hp",
		"damage",
		"speed",
	]

## 确保 _state_marker_label 已创建（延迟创建，避免 _ready 顺序问题）
## _state_marker_label 用于显示精英名字、❓/❗ 警觉标记
func _ensure_state_marker() -> void:
	if _state_marker_label != null and is_instance_valid(_state_marker_label):
		return
	_state_marker_label = Label.new()
	_state_marker_label.name = "StateMarker"
	_state_marker_label.z_index = 3
	_state_marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_marker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_state_marker_label.add_theme_font_size_override("font_size", 13)
	_state_marker_label.modulate = Color(1.0, 0.88, 0.15, 1.0)
	_state_marker_label.visible = false
	add_child(_state_marker_label)

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemy")
	z_as_relative = false
	_ensure_state_marker()
	_fire_timers()
	_update_hp_bar(true)
	_update_z_index()

func _fire_timers() -> void:
	_shoot_timer = randf_range(0.25, shoot_interval)
	_summon_timer = summon_interval

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _contact_timer > 0.0:
		_contact_timer -= delta
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node2D
		if player_ref == null:
			return

	if awareness_enabled:
		_ai_tick(delta)
	else:
		# 兼容旧行为：直接走 ai_type 派发的行为。_dispatch_behavior() 内部已经负责移动和碰撞，
		# 这里必须直接返回，避免同一帧 move_and_slide() 被执行两次。
		_dispatch_behavior(delta)
		return

	velocity += _separation_velocity()
	velocity += _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_try_contact_damage()
	_update_z_index()

## AI状态机主循环
func _ai_tick(delta: float) -> void:
	var dist_to_player: float = global_position.distance_to(player_ref.global_position)
	var can_see_player: bool = _line_of_sight_check(global_position, player_ref.global_position)
	var can_hear_player: bool = dist_to_player <= hearing_range

	# 声音衰减（所有状态共享）
	_noise_accumulator = maxf(0.0, _noise_accumulator - _NOISE_DECAY_RATE * delta)

	# 声音累积：玩家移动时持续增加
	var player_moving: bool = false
	if player_ref.has_method("is_moving"):
		player_moving = bool(player_ref.call("is_moving"))
	else:
		var player_velocity = player_ref.get("velocity")
		if player_velocity is Vector2:
			player_moving = player_velocity.length() > 10.0
	if player_moving:
		_noise_accumulator = min(_noise_accumulator + delta * 30.0, hearing_range)

	match _ai_state:
		AIState.IDLE:
			velocity = Vector2.ZERO
			_update_emoji_display("👾", Color.WHITE)
			if can_see_player:
				_transition_to(AIState.ALERT)
			elif can_hear_player and _noise_accumulator > hearing_range * 0.6:
				_transition_to(AIState.SEARCH)
			else:
				_idle_wander(delta)

		AIState.ALERT:
			velocity = Vector2.ZERO  # 停止，原地警戒
			_update_emoji_display("❓", Color(1.0, 0.85, 0.0, 1.0))  # 黄色问号
			_alert_timer -= delta
			if can_see_player:
				_alert_timer = alert_duration  # 持续看到目标，重置计时
			if _alert_timer <= 0.0:
				if can_see_player:
					_transition_to(AIState.CHASE)
				else:
					_last_known_player_pos = player_ref.global_position
					_transition_to(AIState.SEARCH)

		AIState.CHASE:
			var dir: Vector2 = (player_ref.global_position - global_position).normalized()
			# PH11 P3: 房间边界拦截——靠近边界时减速并折返，不冲出去
			velocity = _apply_boundary_on_dir(dir, speed)
			_update_emoji_display("❗", Color(1.0, 0.15, 0.15, 1.0))  # 红色感叹号
			if not can_see_player:
				_last_known_player_pos = player_ref.global_position
				_transition_to(AIState.SEARCH)

		AIState.SEARCH:
			var to_last: Vector2 = _last_known_player_pos - global_position
			if to_last.length() > 15.0:
				velocity = _apply_boundary_on_dir(to_last.normalized(), speed * 0.6)
			else:
				velocity = Vector2.ZERO
			_update_emoji_display("❓", Color(0.9, 0.75, 0.0, 1.0))  # 暗黄色
			_search_timer -= delta
			if can_see_player:
				_transition_to(AIState.CHASE)
			elif _search_timer <= 0.0:
				_transition_to(AIState.PATROL)

		AIState.PATROL:
			# 声音衰减（每帧独立衰减）
			_noise_accumulator = maxf(0.0, _noise_accumulator - _NOISE_DECAY_RATE * delta)
			_patrol_cooldown -= delta
			_update_emoji_display("👾", Color(0.6, 0.6, 0.6, 1.0))  # 灰白色
			# 在房间边界内巡逻
			_patrol_tick(delta)
			# 检测玩家：看到就进入ALERT
			if can_see_player:
				_transition_to(AIState.ALERT)
			elif can_hear_player and _noise_accumulator > hearing_range * 0.5:
				_last_known_player_pos = player_ref.global_position
				_transition_to(AIState.SEARCH)

## 状态转换
func _transition_to(new_state: AIState) -> void:
	var was_chasing: bool = _ai_state == AIState.CHASE
	_ai_state = new_state
	match new_state:
		AIState.ALERT:
			_alert_timer = alert_duration
		AIState.SEARCH:
			_search_timer = search_duration
		AIState.IDLE:
			_noise_accumulator = 0.0
		AIState.PATROL:
			_noise_accumulator = 0.0
		AIState.CHASE:
			# PH11 P1: 追击时向区域刷怪控制器发送警觉信号（相邻房间增援）
			if not was_chasing:
				enemy_entered_chase.emit(self, _last_known_player_pos)
			# PH11 P2: 精英怪进入追击时触发相邻房间 AI 联动
			if _is_elite and not was_chasing:
				elite_entered_chase.emit(self, _last_known_player_pos)

## IDLE状态：原地轻微徘徊（每帧微小随机位移）
func _idle_wander(_delta: float) -> void:
	var jitter: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 12.0
	velocity += jitter

## 视线检测：两点之间是否有掩体遮挡（简化检测：中间有墙返回false）
func _line_of_sight_check(from: Vector2, to: Vector2) -> bool:
	var dist: float = from.distance_to(to)
	if dist > visual_range:
		return false
	# 简化版：检测路径中是否有障碍物节点（后续接入房间碰撞几何）
	# 目前先用距离判定
	return true

## emoji 显示文字 + 颜色更新
func _update_emoji_display(text: String, color: Color) -> void:
	_ensure_state_marker()
	if text in ["❓", "❗"]:
		if emoji_label:
			emoji_label.text = _base_emoji
			emoji_label.modulate = Color.WHITE
		if _state_marker_label:
			_state_marker_label.text = text
			_state_marker_label.modulate = color
			_state_marker_label.position = Vector2(-_state_marker_label.size.x * 0.5, _state_marker_offset_y)
			_state_marker_label.visible = true
		return
	if emoji_label:
		emoji_label.text = _base_emoji if text == "👾" else text
		emoji_label.modulate = Color.WHITE if text == "👾" else color
	if _state_marker_label:
		_state_marker_label.visible = false

## ========== 房间边界 & 巡逻系统（PH11 区域AI核心）==========

## 设置所属房间的边界（由 RoomWaveSpawner 在生成敌人时调用）
## bounds: Rect2 — 房间矩形区域（世界坐标）
func set_room_bounds(bounds: Rect2) -> void:
	_room_bounds = bounds

## 获取当前房间边界
func get_room_bounds() -> Rect2:
	return _room_bounds

## PH11 P2: 查询是否为精英怪
func is_elite() -> bool:
	return _is_elite

## PH11 P2: 强制唤醒敌人进入 ALERT 状态（由相邻房间精英触发）
## pos: 玩家最后被看到的位置（作为 SEARCH 的起点）
func force_alert(pos: Vector2) -> void:
	if _ai_state == AIState.CHASE:
		return  # 已经在追击，不用强制唤醒
	if _ai_state == AIState.PATROL or _ai_state == AIState.IDLE:
		_last_known_player_pos = pos
		_transition_to(AIState.ALERT)

## 巡逻主循环（PATROL 状态时每帧调用）
func _patrol_tick(delta: float) -> void:
	# 初始化巡逻路径（如尚未建立或被清空）
	if _patrol_waypoints.is_empty() or _current_patrol_idx >= _patrol_waypoints.size():
		_build_patrol_path()

	# 路径点间停顿
	if _patrol_idle_duration > 0.0:
		_patrol_idle_duration -= delta
		velocity = velocity.move_toward(Vector2.ZERO, speed * 2.5 * delta)
		return

	# 移动到当前目标路径点
	var target: Vector2 = _patrol_waypoints[_current_patrol_idx]
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()

	if dist < _patrol_reach_threshold:
		# 到达路径点，停顿后前往下一个
		_current_patrol_idx = (_current_patrol_idx + 1) % _patrol_waypoints.size()
		_patrol_idle_duration = randf_range(0.5, _patrol_idle_max)
		velocity = velocity.move_toward(Vector2.ZERO, speed * 3.0 * delta)
	else:
		# 向路径点移动（减速靠近）
		var dir: Vector2 = to_target.normalized()
		var speed_factor: float = 0.55 if dist < 90.0 else 0.75
		velocity = dir * speed * speed_factor

	# 限制在房间边界内（超出时强力推回）
	_apply_room_bounds()

## 构建随机巡逻路径点（在房间边界内生成若干随机路径点）
func _build_patrol_path() -> void:
	_patrol_waypoints.clear()
	_current_patrol_idx = 0

	# 生成 3~5 个随机路径点，均匀分布在房间内
	var count: int = randi() % 3 + 3  # 3~5 个点
	var room_center: Vector2 = _room_bounds.position + _room_bounds.size * 0.5
	var half: Vector2 = _room_bounds.size * 0.5 - Vector2(60, 60)  # 留60px边距

	for i in range(count):
		var angle: float = (TAU / count) * i + randf_range(-0.3, 0.3)
		var radius: float = randf_range(0.35, 0.9) * minf(half.x, half.y)
		var wp: Vector2 = room_center + Vector2(cos(angle), sin(angle)) * radius
		_patrol_waypoints.append(wp)

## 将敌人限制在房间边界内（超出时施加反向推力）
func _apply_room_bounds() -> void:
	if not _room_bounds.has_area():
		return
	# 检查并推回
	var pos: Vector2 = global_position
	var margin: float = 22.0
	var pushback: Vector2 = Vector2.ZERO
	if pos.x < _room_bounds.position.x + margin:
		pushback.x = ( (_room_bounds.position.x + margin) - pos.x ) * 8.0
	if pos.x > _room_bounds.position.x + _room_bounds.size.x - margin:
		pushback.x = ( (_room_bounds.position.x + _room_bounds.size.x - margin) - pos.x ) * 8.0
	if pos.y < _room_bounds.position.y + margin:
		pushback.y = ( (_room_bounds.position.y + margin) - pos.y ) * 8.0
	if pos.y > _room_bounds.position.y + _room_bounds.size.y - margin:
		pushback.y = ( (_room_bounds.position.y + _room_bounds.size.y - margin) - pos.y ) * 8.0
	velocity += pushback

## PH11 P3: 房间边界方向拦截+减速
## 给定方向向量和速度，在即将撞墙时折返而非被推回
## 返回值：安全的速度向量
func _apply_boundary_on_dir(base_dir: Vector2, base_speed: float) -> Vector2:
	if not _room_bounds.has_area():
		return base_dir * base_speed
	var margin: float = 22.0
	var safe_margin: float = 80.0  # 提前80px开始减速
	var pos: Vector2 = global_position
	# 检查各方向是否接近边界
	var near_left: bool = pos.x < _room_bounds.position.x + safe_margin
	var near_right: bool = pos.x > _room_bounds.position.x + _room_bounds.size.x - safe_margin
	var near_top: bool = pos.y < _room_bounds.position.y + safe_margin
	var near_bottom: bool = pos.y > _room_bounds.position.y + _room_bounds.size.y - safe_margin
	if not (near_left or near_right or near_top or near_bottom):
		return base_dir * base_speed
	# 计算剩余安全空间
	var space_left: float = pos.x - (_room_bounds.position.x + margin)
	var space_right: float = (_room_bounds.position.x + _room_bounds.size.x - margin) - pos.x
	var space_top: float = pos.y - (_room_bounds.position.y + margin)
	var space_bottom: float = (_room_bounds.position.y + _room_bounds.size.y - margin) - pos.y
	# 决定折返方向：朝空间更大的方向
	var alt_dir: Vector2 = Vector2.ZERO
	if space_left > space_right and space_left > space_top and space_left > space_bottom:
		alt_dir = Vector2.LEFT
	elif space_right > space_left and space_right > space_top and space_right > space_bottom:
		alt_dir = Vector2.RIGHT
	elif space_top > space_bottom:
		alt_dir = Vector2.UP
	else:
		alt_dir = Vector2.DOWN
	# 计算方向与边界的冲突成分：0表示方向朝向边界，1表示方向背向边界
	var dot: float = base_dir.dot(alt_dir)
	var speed_factor: float = 0.3 if dot < -0.3 else (0.7 if dot < 0.0 else 1.0)
	return base_dir * base_speed * speed_factor

## 派发旧行为（awareness_enabled=false 时使用）
func _dispatch_behavior(delta: float) -> void:
	match ai_type:
		"chase":
			_behavior_chase(delta)
		"ranged":
			_behavior_ranged(delta)
		"summoner":
			_behavior_summoner(delta)
		"bomber":
			_behavior_bomber(delta)
		"trapper":
			_behavior_trapper(delta)
		_:
			_behavior_chase(delta)
	velocity += _separation_velocity()
	velocity += _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_try_contact_damage()
	_update_z_index()

func _behavior_chase(_delta: float) -> void:
	var direction := (player_ref.global_position - global_position).normalized()
	velocity = direction * speed

func _behavior_ranged(delta: float) -> void:
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()
	var preferred_dist := 310.0
	var tangent := Vector2(-dir.y, dir.x)
	if dist < preferred_dist - 55.0:
		velocity = -dir * speed
	elif dist > preferred_dist + 120.0:
		velocity = dir * speed * 0.55
	else:
		velocity = tangent * speed * 0.34
	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_shoot_timer = shoot_interval
		_ranged_shoot(dir)
	# 精英挂枪射击（偷来的枪身模块自己也会开火）
	if _is_elite and not _elite_gun_modules.is_empty():
		_elite_shoot_timer -= delta
		if _elite_shoot_timer <= 0.0:
			_elite_shoot_timer = _elite_shoot_interval
			_do_elite_gun_shoot()

func _behavior_summoner(delta: float) -> void:
	var direction := (player_ref.global_position - global_position).normalized()
	velocity = direction * speed * 0.65
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_summon_timer = summon_interval
		_spawn_minion()

func _behavior_bomber(_delta: float) -> void:
	if _exploded:
		return
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()
	velocity = dir * speed
	if dist < 28.0:
		_exploded = true
		_trigger_explosion()

func _behavior_trapper(_delta: float) -> void:
	if _triggered:
		var direction := (player_ref.global_position - global_position).normalized()
		velocity = direction * speed * 2.6
		return
	var to_player := player_ref.global_position - global_position
	if to_player.length() < trigger_radius:
		_triggered = true
		velocity = to_player.normalized() * speed * 2.6
	else:
		velocity = Vector2.ZERO

func _separation_velocity() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var delta: Vector2 = global_position - other.global_position
		var d: float = delta.length()
		if d > 0.01 and d < 42.0:
			push += delta.normalized() * (42.0 - d)
	return push * 0.8  # 降低分离强度，避免挤压时弹飞 + 减少粘附

func _try_contact_damage() -> void:
	if _contact_timer > 0.0 or player_ref == null or not is_instance_valid(player_ref):
		return
	if global_position.distance_to(player_ref.global_position) <= contact_radius:
		if player_ref.has_method("take_damage"):
			player_ref.take_damage(int(float(damage) * _damage_multiplier))
		_contact_timer = contact_damage_interval

func _ranged_shoot(dir: Vector2) -> void:
	var projectile: Node = ENEMY_PROJECTILE_SCENE.instantiate()
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(projectile)
	var spawn_pos := global_position + dir * 28.0
	if projectile.has_method("launch"):
		projectile.launch(spawn_pos, dir, 315.0, int(float(damage) * _damage_multiplier))

func _spawn_minion() -> void:
	# Load at summon time; preloading this script's own scene creates a cyclic editor load.
	var minion_scene: PackedScene = load("res://scenes/Enemy.tscn") as PackedScene
	var minion = minion_scene.instantiate()
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(minion)
	var offset := Vector2(randf_range(-48, 48), randf_range(-48, 48))
	minion.global_position = global_position + offset
	minion.max_hp = max(10, int(max_hp * 0.35))
	minion.current_hp = minion.max_hp
	minion.damage = max(4, int(damage * 0.65))
	minion.speed = speed * 1.08
	if minion.has_method("set_visuals"):
		minion.set_visuals("🦇", Color(0.85, 0.25, 0.95, 1.0), 0.82)

func _trigger_explosion() -> void:
	if player_ref and is_instance_valid(player_ref):
		var to_player := player_ref.global_position - global_position
		if to_player.length() < explosion_radius and player_ref.has_method("take_damage"):
			player_ref.take_damage(explosion_damage)
	_spawn_explosion_flash()
	die()

func take_damage(amount: int, is_crit: bool = false, hit_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	current_hp = max(0, current_hp - amount)
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * (95.0 if not is_crit else 150.0)
	_update_hp_bar()
	flash_damage(is_crit)
	enemy_hit.emit(global_position, amount, is_crit)
	_spawn_damage_number(global_position, amount, is_crit)
	if current_hp <= 0:
		die()

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	enemy_died.emit()
	_spawn_death_flash()
	emit_death_screen_effect()
	if hp_bar:
		hp_bar.visible = false
	var target: CanvasItem = emoji_label if emoji_label != null else shape
	if target:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(target, "scale", Vector2(0.1, 0.1), 0.22).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(target, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func set_visuals(emoji: String, color: Color, scale_mult: float = 1.0) -> void:
	_base_emoji = emoji
	_base_color = color
	_base_scale = scale_mult
	if emoji_label:
		emoji_label.text = emoji
		emoji_label.scale = Vector2.ONE * scale_mult
	if shape:
		shape.color = color
		shape.scale = Vector2.ONE * scale_mult
	_update_hp_bar(true)

func _set_elite_name_label(data: Dictionary) -> void:
	if not data.get("is_elite", false):
		return
	var name: String = data.get("name", "")
	if name.is_empty():
		return
	_ensure_state_marker()
	if _state_marker_label:
		_state_marker_label.text = name
		_state_marker_label.modulate = Color(1.0, 0.88, 0.15, 1.0)  # 金黄色，与暴击主题一致
		_state_marker_label.size = Vector2(max(name.length() * 10, 24), 22)
		_state_marker_label.position = Vector2(-_state_marker_label.size.x * 0.5, _state_marker_offset_y)
		_state_marker_label.visible = true

## 设置精英挂载装备的视觉表现（视觉化显示精英偷走的枪械模块）
## 精英身上会显示一个枪械标记，表示它偷走了玩家的武器
func _set_elite_equipment_visual(data: Dictionary) -> void:
	if not data.get("is_elite", false):
		return
	var stolen_modules: Array = data.get("stolen_modules", [])
	if stolen_modules.is_empty():
		return

	# 查找是否有 GunBody 类型装备
	var has_gun: bool = false
	for m in stolen_modules:
		if m is Dictionary and m.get("module_type") == "GunBody":
			has_gun = true
			break

	if not has_gun:
		return

	# 获取精英缩放比例，用于同步放大装备标记
	var elite_scale: float = data.get("scale", 1.0)
	elite_scale = max(1.0, elite_scale)

	# 在精英头顶（名字上方）创建一个装备标记 Label
	var gun_badge := Label.new()
	gun_badge.name = "GunBadge"
	gun_badge.text = "🔫"
	gun_badge.position = Vector2(-8, -72)  # 在名字标签下方
	gun_badge.size = Vector2(16, 16)
	gun_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gun_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gun_badge.add_theme_font_size_override("font_size", 14)
	gun_badge.modulate = Color(1.0, 0.88, 0.15, 0.9)  # 金黄色，带透明度
	gun_badge.z_index = 2
	gun_badge.scale = Vector2.ONE * elite_scale
	gun_badge.visible = true
	add_child(gun_badge)

	# 保存GunBody、Bullet和Attachment模块用于挂枪射击和子弹行为
	_elite_gun_modules.clear()
	_elite_bullet_modules.clear()
	_elite_attachment_modules.clear()
	for m in stolen_modules:
		if m is Dictionary:
			match m.get("module_type"):
				"GunBody":
					_elite_gun_modules.append(m)
				"Bullet":
					_elite_bullet_modules.append(m)
				"Attachment":
					_elite_attachment_modules.append(m)

## 执行精英偷来的枪身模块射击
## 精英用 Bullet.tscn 发射子弹，从偷来的 GunBody 模块获取伤害参数
## 如果偷了 Bullet 模块，则应用行为修饰（追踪弹/落地炮台/乱射/火力暴食等命运行为生效）
func _do_elite_gun_shoot() -> void:
	if _elite_gun_modules.is_empty() or player_ref == null or not is_instance_valid(player_ref):
		return
	var dir := (player_ref.global_position - global_position).normalized()

	# 多GunBody多角度射击：每把枪从精英周围略微不同的方向发射
	# 而非全部重叠在一个 spawn_pos，造成"扇形交叉火力"效果
	var gun_count: int = _elite_gun_modules.size()
	var spread_rad: float = 0.18  # 每把枪之间的角度偏移（弧度），≈10度

	for i in _elite_gun_modules.size():
		var gun_module: Dictionary = _elite_gun_modules[i]
		var gun_damage: int = int(gun_module.get("damage", 8))
		# bullet_speed from WeaponPresets: if < 10 it's a multiplier (1.0=normal, 2.0=fast), need absolute speed
		var raw_bullet_speed: float = float(gun_module.get("bullet_speed", 280.0))
		var bullet_speed: float = raw_bullet_speed if raw_bullet_speed > 10.0 else 280.0 * raw_bullet_speed
		# fire_rate from WeaponPresets: if < 10 it's a multiplier, compute absolute interval
		var raw_fire_rate: float = float(gun_module.get("fire_rate", 3.5))
		var fire_rate: float = raw_fire_rate if raw_fire_rate > 10.0 else raw_fire_rate
		_elite_shoot_interval = 1.0 / fire_rate if fire_rate > 0.0 else 1.8

		# 为每把枪计算略微不同的发射方向（扇形散布）
		var offset_rad: float = (float(i) - float(gun_count - 1) * 0.5) * spread_rad
		var base_angle: float = dir.angle()
		var gun_dir: Vector2 = Vector2.from_angle(base_angle + offset_rad)
		# 每把枪的 spawn_pos 也随角度偏移，在精英周围形成一个扇形发射圈
		var spawn_pos := global_position + gun_dir * 28.0

		# 判断是否偷了子弹模块：有则使用 Bullet.tscn 并应用行为修饰
		# Bullet.tscn 才有 apply_fate_stats_from_node()，使追踪弹/落地炮台/乱射等命运行为生效
		var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
		var projectile: Node = bullet_scene.instantiate()
		var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		parent.add_child(projectile)
		projectile.z_as_relative = false
		projectile.z_index = 890

		# 应用精英偷取的Attachment模块修饰效果
		# Attachment模块修饰射击参数：spread减少（更精准）、damage加成、命中触发等
		if not _elite_attachment_modules.is_empty():
			var combined_attachment_stats: Dictionary = {}
			for att_module in _elite_attachment_modules:
				for key in att_module.keys():
					if key in ["spread", "damage", "fate_attachment_hit_trigger", "trigger_on_hit", "ricochet_count", "homing", "explosion_radius"]:
						combined_attachment_stats[key] = att_module.get(key)
			if not combined_attachment_stats.is_empty():
				var att_node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "EliteAttachment")
				att_node.set_base_stats(combined_attachment_stats)
				if projectile.has_method("apply_fate_stats_from_node"):
					projectile.apply_fate_stats_from_node(att_node)
				att_node.free()

		if projectile.has_method("fire"):
			projectile.fire(spawn_pos, gun_dir, bullet_speed, gun_damage, false)

		# 如果偷了Bullet模块，对第一颗子弹应用行为修饰
		if i == 0 and not _elite_bullet_modules.is_empty():
			var bullet_module: Dictionary = _elite_bullet_modules[0]
			var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, bullet_module.get("module_id", "EliteBullet"))
			node.set_base_stats(bullet_module)
			if projectile.has_method("apply_fate_stats_from_node"):
				projectile.apply_fate_stats_from_node(node)
			node.free()

func _spawn_explosion_flash() -> void:
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 950
	flash.size = Vector2(explosion_radius * 2.0, explosion_radius * 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.color = Color(1.0, 0.45, 0.12, 0.42)
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(flash)
	flash.global_position = global_position - flash.size * 0.5
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.25, 0.25), 0.18)
	t.tween_property(flash, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(flash.queue_free)

func _spawn_death_flash() -> void:
	# 颜色随敌人类型变化：从 _enemy_data.color 或当前 shape.color 读取
	var flash_color: Color = Color(1.0, 1.0, 0.8, 0.85)  # 默认淡黄白
	if _enemy_data.has("color") and _enemy_data["color"] is Color:
		flash_color = _enemy_data["color"]
	elif shape and shape.color != Color.WHITE:
		flash_color = shape.color
	# 略微提亮、增强饱和度，让死亡爆炸更醒目
	flash_color = Color(
		min(flash_color.r * 1.2, 1.0),
		min(flash_color.g * 1.2, 1.0),
		min(flash_color.b * 1.2, 1.0),
		0.85
	)
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 960
	flash.size = Vector2(46, 46)
	flash.pivot_offset = flash.size * 0.5
	flash.color = flash_color
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(flash)
	flash.global_position = global_position - flash.size * 0.5
	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.12).set_trans(Tween.TRANS_QUAD)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_LINEAR)
	flash_tween.chain().tween_callback(flash.queue_free)

func emit_death_screen_effect() -> void:
	var shake := get_tree().root.find_child("ScreenShake", true, false) as Node
	if shake and shake.has_method("trigger"):
		var intensity := 4.0
		if max_hp >= 80:
			intensity = 11.0
		elif max_hp >= 40:
			intensity = 7.0
		shake.trigger(intensity, 0.12)
	var audio: Node = get_node_or_null("/root/AudioManager") as Node
	if audio and audio.has_method("play_enemy_die_sfx"):
		audio.play_enemy_die_sfx()

func _update_hp_bar(force: bool = false) -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
		hp_bar.visible = force or current_hp < max_hp
	hp_changed.emit(current_hp, max_hp)

func flash_damage(is_crit: bool = false) -> void:
	# 基础闪白（敌人受击的标准反馈）
	if shape:
		var original := shape.color
		var flash_color := Color(1.0, 1.0, 1.0, 1.0)  # 纯白闪
		var flash_duration := 0.045
		var scale_target := Vector2(1.0, 1.0)
		if is_crit:
			# 暴击：更亮、更久、伴随缩放脉冲
			flash_color = Color(1.0, 0.98, 0.6, 1.0)   # 亮黄白（暴击感）
			flash_duration = 0.10
			scale_target = Vector2(1.12, 1.12)          # 轻微放大脉冲
		shape.color = flash_color
		# 缩放脉冲（暴击时更明显）
		if scale_target != Vector2(1.0, 1.0):
			var orig_scale := shape.scale
			shape.scale = scale_target
			var scale_tween := create_tween()
			scale_tween.tween_property(shape, "scale", orig_scale, flash_duration * 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(flash_duration).timeout
		if shape and not _is_dead:
			shape.color = original
	if emoji_label:
		var old := emoji_label.modulate
		var emoji_flash := Color(1.0, 0.85, 0.85, 1.0) if not is_crit else Color(1.0, 0.98, 0.6, 1.0)
		var emoji_duration := 0.045 if not is_crit else 0.10
		emoji_label.modulate = emoji_flash
		await get_tree().create_timer(emoji_duration).timeout
		if emoji_label and not _is_dead:
			emoji_label.modulate = old

func _update_z_index() -> void:
	z_index = 1000 + int(global_position.y)  # 负Y区域也必须高于背景层

func add_modifier(modifier_id: String, tier: int = 1) -> void:
	var mod = EnemyModifierScript.Factory.create(modifier_id, tier)
	if mod:
		_modifiers.append(mod)
		mod.apply(self)

## 设置伤害倍率（由环境命运触发器的 CURSE_ROOM_ENEMIES 调用）
## multiplier=1.15 表示伤害+15%
func apply_damage_multiplier(multiplier: float) -> void:
	_damage_multiplier = multiplier
	print("[EnemyBase] 伤害倍率设置为 %.2f（触发来源：环境命运-诅咒降临）" % multiplier)

func _spawn_damage_number(world_pos: Vector2, dmg: int, is_crit: bool = false) -> void:
	get_tree().call_group("game_ui", "show_damage_popup", world_pos, dmg, is_crit)
	return
	var scene_path := "res://scenes/DamageNumber.tscn"
	var num_scene: PackedScene = load(scene_path)
	if num_scene:
		var label: Node = num_scene.instantiate()
		if label is Label:
			# 文本内容：暴击加 "!" 后缀
			label.text = str(dmg) + ("!" if is_crit else "")
			# 初始随机偏移，位置在敌人头顶
			var offset := Vector2(randf_range(-8, 8), -20)
			label.position = world_pos + offset
			label.z_index = 200
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			# --- 样式分层 ---
			var font_size := 18
			var base_color := Color(1.0, 0.35, 0.2, 1.0)   # 红橙
			var anim_duration := 0.8
			var float_range := 50.0

			if is_crit:
				# 暴击：金色，更大字号，更高飘幅
				font_size = 30
				base_color = Color(1.0, 0.92, 0.15, 1.0)   # 亮金
				float_range = 65.0
			elif dmg >= 50:
				# 大伤害：橙色，更大字号
				font_size = 24
				base_color = Color(1.0, 0.55, 0.1, 1.0)    # 橙红
				float_range = 58.0

			# 字号覆盖 & 颜色
			label.add_theme_font_size_override("font_size", font_size)
			label.modulate = base_color

			# 描边效果（通过暗色阴影模拟 Outline）
			# 在 label 下方叠加一个偏移暗色副本做描边
			var outline_label := Label.new()
			outline_label.text = label.text
			outline_label.add_theme_font_size_override("font_size", font_size)
			outline_label.modulate = Color(0.0, 0.0, 0.0, 0.7)
			outline_label.z_index = label.z_index - 1
			outline_label.position = label.position + Vector2(2, 2)
			outline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			outline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
			parent.add_child(outline_label)

			# --- 动画：飘字 + 透明度 + 缩放消失（与 DamageNumbers.gd 一致）---
			label.scale = Vector2(1.25, 1.25)   # 初始放大（弹入感）
			outline_label.scale = Vector2(1.25, 1.25)

			var tween := label.create_tween()
			tween.set_parallel(true)
			tween.tween_property(label, "position:y", world_pos.y - float_range + offset.y, anim_duration).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(label, "modulate:a", 0.0, anim_duration).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(label, "scale", Vector2(0.75, 0.75), anim_duration).set_trans(Tween.TRANS_LINEAR)

			var outline_tween := outline_label.create_tween()
			outline_tween.set_parallel(true)
			outline_tween.tween_property(outline_label, "position:y", world_pos.y - float_range + offset.y, anim_duration).set_trans(Tween.TRANS_LINEAR)
			outline_tween.tween_property(outline_label, "modulate:a", 0.0, anim_duration).set_trans(Tween.TRANS_LINEAR)
			outline_tween.tween_property(outline_label, "scale", Vector2(0.75, 0.75), anim_duration).set_trans(Tween.TRANS_LINEAR)

			# 弹入动画：快速收缩到正常大小
			var pop := label.create_tween()
			pop.tween_property(label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK)
			var outline_pop := outline_label.create_tween()
			outline_pop.tween_property(outline_label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK)

			# 完成后自毁
			tween.chain().tween_callback(label.queue_free)
			outline_tween.chain().tween_callback(outline_label.queue_free)
