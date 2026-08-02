extends CharacterBody2D

const EnemyModifierScript := preload("res://src/enemy/EnemyModifier.gd")
const ENEMY_PROJECTILE_SCENE := preload("res://scenes/EnemyProjectile.tscn")

signal hp_changed(current: int, maximum: int)
signal enemy_died()
signal enemy_hit(hit_from: Vector2, damage: int, is_crit: bool)
## 当敌人进入 CHASE 追击状态时，向房间的区域刷怪控制器发送警觉信号
signal enemy_entered_chase(enemy: Node, last_known_pos: Vector2)
## 精英怪专属：进入 CHASE 时触发相邻房间 AI 联动（v0.1 P2）
signal elite_entered_chase(enemy: Node, last_known_pos: Vector2)

## AI状态机枚举（v0.1 警觉AI核心）
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

## 形状类型（0=三角/chaser, 1=菱形/ranged, 2=五角星/summoner, 3=六边形/tank, 4=圆形/bomber, 5=倒三角/trapper）
## 在 _ready() 中根据 enemy_shape 渲染 Polygon2D
var enemy_shape: int = 0

var shoot_interval: float = 1.7
var summon_interval: float = 5.0
var explosion_radius: float = 82.0
var explosion_damage: int = 25
var trigger_radius: float = 120.0
var has_shield: bool = false
var shield_rate: float = 0.0

var _shoot_timer: float = 0.0
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _triggered: bool = false
var _exploded: bool = false
var _bomber_charging: bool = false
var _bomber_charge_timer: float = 0.0
var _trapper_revealing: bool = false
var _trapper_reveal_timer: float = 0.0
var _ranged_windup_active: bool = false
var _summon_telegraph_active: bool = false

## 远程敌人侧翼机动（v0.1强化）
var _ranged_flank_dir: int = 1          # 1=右侧翼绕后, -1=左侧翼绕后
var _ranged_flank_timer: float = 0.0    # 侧翼切换倒计时
var _ranged_flank_interval: float = 3.8  # 默认3.8秒切换一次侧翼方向
var _ranged_tangent_dir: int = 1        # 切向移动方向（每次绕圈后反转）
var _ranged_tangent_speed_bonus: float = 1.0
var _ranged_minion_spawn_timer: float = 0.0  # 远程召唤型小怪生成计时（独立于summon_interval）
var _is_dead: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO
var _modifiers: Array = []
var _enemy_data: Dictionary = {}
var _damage_multiplier: float = 1.0  # 伤害倍率（由环境命运触发器设置）
var _is_elite: bool = false          # 是否为精英怪（v0.1 P2: 精英进入CHASE时触发相邻房间AI联动）
var _elite_gun_modules: Array[Dictionary] = []   # 精英偷取的GunBody模块（用于挂枪射击）
var _elite_bullet_modules: Array[Dictionary] = []  # 精英偷取的Bullet模块（用于子弹行为）
var _elite_attachment_modules: Array[Dictionary] = []  # 精英偷取的Attachment模块（用于修饰射击参数）
var _elite_shoot_timer: float = 0.0   # 精英挂枪射击计时器
var _elite_shoot_interval: float = 1.8  # 精英挂枪射击间隔（秒）
var _charge_immune: bool = false
var _shield_reflect_active: bool = false
var _shield_reflect_chance: float = 0.0
var _shield_wall_active: bool = false
var _shield_wall_effectiveness: float = 0.0
var _barrier_active: bool = false
var _barrier_until: float = 0.0
var _enraged: bool = false
var _rally_speed_base: float = 0.0
var _rally_speed: float = 0.0
var _rally_damage_base: int = 0
var _rally_damage: int = 0
var _rally_buff_until: float = 0.0
var counter_strike_until: float = 0.0
var regional_controller_ref: Node = null
var _base_emoji: String = "👾"
var _base_color: Color = Color.WHITE
var _base_scale: float = 1.0
var _current_scale: float = 1.0  # 当前综合缩放（原始 * 词缀增幅）
var _state_marker_label: Label = null
var _state_marker_offset_y: float = -58.0  # 名字标签 Y 偏移（位于 emoji 上方）

## DOT/冰冻状态（命运卡片元素子弹）
var _fuse_dot_active: bool = false
var _fuse_dot_type: String = ""        # fire / ice / poison
var _fuse_dot_dps: float = 0.0         # 每秒伤害（真实值，非倍率）
var _fuse_dot_timer: float = 0.0       # DOT 持续计时
var _fuse_dot_duration: float = 0.0   # DOT 总持续时间
var _fuse_dot_last_hp: int = 0        # 用于计算真实伤害
var _fuse_dot_original_speed: float = 80.0  # 记录原始速度（冰冻后恢复）

## 冰冻状态
var _frozen: bool = false
var _freeze_timer: float = 0.0        # 冰冻剩余时间
var _freeze_original_modulate: Color = Color.WHITE

## AI状态机变量
var _ai_state: AIState = AIState.IDLE
var _alert_timer: float = 0.0       # ALERT状态剩余时间
var _search_timer: float = 0.0       # SEARCH状态剩余时间
var _last_known_player_pos: Vector2 = Vector2.ZERO  # 玩家最后被看到的位置
var _noise_accumulator: float = 0.0  # 声音累积（玩家移动/射击时增加）

## 巡逻变量（v0.1 区域AI核心）
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

@onready var shape: Polygon2D = $Shape
@onready var emoji_label: Label = get_node_or_null("Emoji") as Label
@onready var hp_bar: ProgressBar = get_node_or_null("HPBarBG/HPBar") as ProgressBar
@onready var avatar_renderer: EnemyAvatarRenderer = get_node_or_null("AvatarRenderer") as EnemyAvatarRenderer

func set_enemy_data(data: Dictionary) -> void:
	_enemy_data = data.duplicate(true)
	_is_elite = data.get("is_elite", false)
	enemy_shape = EnemyShape.shape_for_kind(str(data.get("enemy_type", "")), str(data.get("ai_type", ai_type)))
	if enemy_shape == EnemyShape.ShapeType.TANK:
		has_shield = true
		shield_rate = maxf(shield_rate, 0.18)
	if data.has("emoji") or data.has("color"):
		set_visuals(data.get("emoji", "👾"), data.get("color", Color(1.0, 0.25, 0.25, 1.0)), float(data.get("scale", 1.0)))
	if is_node_ready():
		_apply_enemy_shape()
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
	if not _enemy_data.is_empty():
		_base_emoji = str(_enemy_data.get("emoji", _base_emoji))
		_base_color = _enemy_data.get("color", shape.color) as Color
		_base_scale = float(_enemy_data.get("scale", _base_scale))
		_current_scale = _base_scale
		shape.color = _base_color
	elif shape != null:
		_base_color = shape.color
	if shape != null:
		shape.visible = false
	if emoji_label != null:
		emoji_label.visible = false
	_ensure_state_marker()
	_apply_enemy_shape()
	_fire_timers()
	_update_hp_bar(true)
	_update_z_index()
	_init_state_machine()


## 应用 enemy_shape 到 shape Polygon2D
func _apply_enemy_shape() -> void:
	if shape == null:
		return
	shape.polygon = EnemyShape.make_polygon(enemy_shape, 18.0)
	shape.visible = false
	if emoji_label != null:
		emoji_label.visible = false
	if avatar_renderer != null:
		avatar_renderer.configure(enemy_shape, shape.color, _current_scale)
	_apply_collision_profile()


func _apply_collision_profile() -> void:
	var profile := EnemyShape.get_profile(enemy_shape)
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is CircleShape2D:
		(collision.shape as CircleShape2D).radius = float(profile.get("collision_radius", 20.0)) * _current_scale
	contact_radius = float(profile.get("contact_radius", 31.0)) * _current_scale
	var extent := float(profile.get("visual_extent", 32.0)) * _current_scale
	_state_marker_offset_y = -(extent + 24.0)
	var hp_background := get_node_or_null("HPBarBG") as Control
	if hp_background != null:
		var half_width := maxf(24.0, extent * 0.72)
		hp_background.offset_left = -half_width
		hp_background.offset_right = half_width
		hp_background.offset_top = -(extent + 14.0)
		hp_background.offset_bottom = -(extent + 5.0)

func _fire_timers() -> void:
	_shoot_timer = randf_range(0.25, shoot_interval)
	_summon_timer = summon_interval


func _tick_skill_components(delta: float) -> void:
	for child in get_children():
		if child.has_method("tick") and (child.has_signal("skill_triggered") or child.has_signal("elite_skill_triggered")):
			child.tick(delta)


func _notify_skill_components(method_name: String, args: Array = []) -> void:
	for child in get_children():
		if child.has_method(method_name):
			child.callv(method_name, args)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	# === DOT 持续伤害 ===
	if _fuse_dot_active and _fuse_dot_timer < _fuse_dot_duration:
		_fuse_dot_timer += delta
		# 每秒造成一次伤害（DOT DPS 是 "每秒"）
		var tick_interval: float = 0.5  # 每0.5秒tick一次
		var tick_damage: int = maxi(1, int(_fuse_dot_dps * tick_interval))
		current_hp = max(0, current_hp - tick_damage)
		_spawn_damage_number(global_position, tick_damage, false)
		if shape:
			match _fuse_dot_type:
				"fire":
					shape.color = Color(1.0, clampf(0.4 + _fuse_dot_timer * 0.1, 0.0, 0.8), 0.1, 1.0)
				"poison":
					shape.color = Color(0.1, clampf(0.7 - _fuse_dot_timer * 0.05, 0.1, 0.8), 0.1, 1.0)
				"ice":
					# 冰霜DOT每帧蓝色增强，颜色随DOT持续时间从淡蓝→亮蓝
					var ice_tick_intensity := clampf(_fuse_dot_timer * 0.05, 0.0, 1.0)
					shape.color = Color(0.3 + 0.2 * ice_tick_intensity, 0.6 + 0.15 * ice_tick_intensity, 1.0, 1.0)
		if current_hp <= 0:
			die()
			return
	# === 冰冻 ===
	if _frozen:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_frozen = false
			if shape:
				shape.modulate = _freeze_original_modulate
				shape.scale = Vector2.ONE
	# === 常规逻辑 ===
	if _contact_timer > 0.0:
		_contact_timer -= delta
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node2D
		if player_ref == null:
			return

	if _frozen:
		# 冰冻时停止移动，不执行AI
		velocity = velocity.move_toward(Vector2.ZERO, 999.0 * delta)
		move_and_slide()
		return

	if awareness_enabled:
		_ai_tick(delta)
	else:
		# 兼容旧行为：直接走 ai_type 派发的行为。_dispatch_behavior() 内部已经负责移动和碰撞，
		# 这里必须直接返回，避免同一帧 move_and_slide() 被执行两次。
		_dispatch_behavior(delta)
		return

	#精英主动技能组件每帧Tick（awareness_enabled=true时由AI状态机驱动，false时由_dispatch_behavior返回前驱动）
	#用 has_signal 判断：只有真正挂载了技能组件的节点才会触发 tick
	_tick_skill_components(delta)

	velocity += _separation_velocity()
	velocity += _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_try_contact_damage()
	_update_z_index()

## AI状态机主循环（2026-06-10 改造：通用状态机框架接入）
## 原硬编码 5 状态逻辑已拆到 src/enemy/states/ 下 5 个独立 State 类。
## 这里只保留共享逻辑（声音衰减 + 累积 + 转发到状态机）。
func _ai_tick(delta: float) -> void:
	if _state_machine == null or not _state_machine_initialized:
		return

	# 声音衰减（所有状态共享）
	_noise_accumulator = maxf(0.0, _noise_accumulator - _NOISE_DECAY_RATE * delta)

	# 声音累积：玩家移动时持续增加
	var player_moving: bool = false
	if player_ref and is_instance_valid(player_ref):
		if player_ref.has_method("is_moving"):
			player_moving = bool(player_ref.call("is_moving"))
		else:
			var player_velocity = player_ref.get("velocity")
			if player_velocity is Vector2:
				player_moving = player_velocity.length() > 10.0
		if player_moving:
			_noise_accumulator = min(_noise_accumulator + delta * 30.0, hearing_range)

	# 转发给状态机，由当前状态决定具体行为和切换
	_state_machine.physics_update(delta)

## 状态转换（2026-06-10 改造：转发到状态机）
## 保留这个函数是让外部调用（比如 force_alert）不需改：
##   _transition_to(AIState.ALERT) 还是会调，底层走状态机
func _transition_to(new_state: AIState) -> void:
	if _state_machine == null or not _state_machine_initialized:
		# 状态机未启动：降级到原来的直接赋值，保留 1:1 行为
		_ai_state = new_state
		match new_state:
			AIState.ALERT: _alert_timer = alert_duration
			AIState.SEARCH: _search_timer = search_duration
			AIState.IDLE: _noise_accumulator = 0.0
			AIState.PATROL: _noise_accumulator = 0.0
		return
	_state_machine.transition_to(_state_name_for(new_state))

## AIState 枚举到状态机字符串的双向映射（兼容旧调用）
func _state_name_for(s: AIState) -> String:
	match s:
		AIState.IDLE: return "idle"
		AIState.ALERT: return "alert"
		AIState.CHASE: return "chase"
		AIState.SEARCH: return "search"
		AIState.PATROL: return "patrol"
	return "idle"  # fallback

## 初始化状态机（_ready 末尾调一次）
func _init_state_machine() -> void:
	if _state_machine_initialized:
		return
	_state_machine = StateMachine.new()
	_state_machine.name = "StateMachine"
	_state_machine.owner_node = self
	add_child(_state_machine)
	# 注册 5 个状态
	_state_machine.register("idle", EnemyIdleState.new())
	_state_machine.register("alert", EnemyAlertState.new())
	_state_machine.register("chase", EnemyChaseState.new())
	_state_machine.register("search", EnemySearchState.new())
	_state_machine.register("patrol", EnemyPatrolState.new())
	# 启动到 IDLE（保留原默认行为）
	_state_machine.start("idle")
	_state_machine_initialized = true


## IDLE状态：原地轻微徘徊（每帧微小随机位移）
func _idle_wander(_delta: float) -> void:
	var jitter: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 12.0
	velocity += jitter

## 视线检测：两点之间是否有掩体遮挡（简化检测：中间有墙返回false）
func _line_of_sight_check(from: Vector2, to: Vector2) -> bool:
	var dist: float = from.distance_to(to)
	if dist > visual_range:
		return false
	# 基础射线检测：检测路径上是否有 StaticBody2D 障碍物
	var space_state: PhysicsDirectSpaceState2D = get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1  # 与 BoundaryCollision layer 对应
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return true  # 无障碍，视线通
	# 有障碍物在路径上。检查距离：如果障碍物很近（<60px），才遮挡
	# 这是为了避免房间边界（距敌人几百像素）被误判为遮挡
	var obstacle_dist: float = from.distance_to(result["position"])
	if obstacle_dist < 60.0:
		return false  # 近距离障碍物遮挡视线
	return true  # 远距离障碍物不遮挡（可能是边界）

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

## ========== 状态机改造 (2026-06-10 PHxx 通用状态机框架接入) ==========
## 5 个状态（IDLE/ALERT/CHASE/SEARCH/PATROL）已拆为独立 State 子类：
##   src/enemy/states/EnemyIdleState.gd / EnemyAlertState.gd / EnemyChaseState.gd
##   / EnemySearchState.gd / EnemyPatrolState.gd
## 状态机本体：
##   src/core/StateMachine.gd
## 状态基类：
##   src/core/State.gd
##
## 对外行为完全不变，emoji、计时器、警觉信号、精英联动全部按原逻辑搬迁。
## _ai_state 字段保留并由各 State.enter() 同步更新，兼容旧代码里的判断。
## _transition_to() 保留为薄包装，转发到 _state_machine.transition_to()，
## 让外部调用（比如 force_alert()）不用改。

## 状态机节点（_ready 里 add_child 挂上）
var _state_machine: StateMachine = null

## 状态机启动标志（防止重复 init）
var _state_machine_initialized: bool = false

## ========== 房间边界 & 巡逻系统（v0.1 区域AI核心）==========

## 设置所属房间的边界（由 RoomWaveSpawner 在生成敌人时调用）
## bounds: Rect2 — 房间矩形区域（世界坐标）
func set_room_bounds(bounds: Rect2) -> void:
	_room_bounds = bounds

## 获取当前房间边界
func get_room_bounds() -> Rect2:
	return _room_bounds

## v0.1 P2: 查询是否为精英怪
func is_elite() -> bool:
	return _is_elite

## v0.1 P2: 强制唤醒敌人进入 ALERT 状态（由相邻房间精英触发）
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

## v0.1 P3: 房间边界方向拦截+减速
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
	# 旧 AI 分支也统一驱动技能组件，每帧只 tick 一次。
	_tick_skill_components(delta)
	velocity += _separation_velocity()
	velocity += _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_try_contact_damage()
	_update_z_index()

func _behavior_chase(_delta: float) -> void:
	var direction := (player_ref.global_position - global_position).normalized()
	# v0.1: elite chase 略微带侧翼感（不是直线追，略有弧线）
	if _is_elite:
		var tangent := Vector2(-direction.y, direction.x) * _ranged_flank_dir * 0.25
		velocity = (direction + tangent) * speed
	else:
		velocity = direction * speed

func _behavior_ranged(delta: float) -> void:
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()
	var preferred_dist := 310.0

	# --- 侧翼机动增强（v0.1强化） ---
	# 远程敌人不是简单切向移动，而是主动绕到玩家侧后方
	# 侧翼方向 _ranged_flank_dir 控制绕向哪一侧
	# 绕到一定角度后切入，保持与玩家间距，同时造成压迫感
	_ranged_flank_timer -= delta
	if _ranged_flank_timer <= 0.0:
		_ranged_flank_dir *= -1  # 定期反转侧翼方向，打破规律
		_ranged_flank_timer = _ranged_flank_interval
		_ranged_tangent_dir *= -1  # 切向方向也反转，增加不规则感

	# 计算垂直于玩家方向的切向分量（用于侧翼绕行）
	# 防止零向量：dir 接近零向量时（玩家在敌人正上方/下方），使用上一帧方向
	var tangent := Vector2(-dir.y, dir.x) * _ranged_tangent_dir
	if tangent.length_squared() < 0.01:
		tangent = Vector2.LEFT * _ranged_tangent_dir  # fallback 水平向
	# 限制 tangent 的最大侧向速度比例，避免纯侧向运动（让敌人始终有朝向玩家的分量）
	var tangent_speed_ratio: float = 0.72 * _ranged_tangent_speed_bonus  # 侧翼时 tangent 最大占比
	if dist > preferred_dist + 120.0:
		# 远离时，朝向玩家为主（tangent 只占 25%）
		tangent_speed_ratio = 0.25
	elif dist < preferred_dist - 55.0:
		# 太近时，后退为主（tangent 占 35%）
		tangent_speed_ratio = 0.35

	if dist < preferred_dist - 55.0:
		# 太近：向后退（但用后退+侧翼结合，而非直线后退）
		# 后退时同时侧向移动，让退路更多变
		velocity = (-dir * 0.8 + tangent * _ranged_flank_dir * tangent_speed_ratio * 0.45) * speed
	elif dist > preferred_dist + 120.0:
		# 太远：前进追击
		velocity = (dir * 0.6 + tangent * _ranged_flank_dir * tangent_speed_ratio) * speed
	else:
		# 在最佳射程附近：侧翼绕行（绕到玩家侧后方）
		# 侧翼速度比主方向快，让敌人有弧线感而非原地切圈
		velocity = (dir * 0.28 + tangent * _ranged_flank_dir * tangent_speed_ratio) * speed

	# 射击（保持原有逻辑）
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
	if _summon_timer <= 0.62 and not _summon_telegraph_active:
		_summon_telegraph_active = true
		play_combat_telegraph("summon", 0.62, 74.0)
	if _summon_timer <= 0.0:
		_summon_timer = summon_interval
		_summon_telegraph_active = false
		_spawn_minion()

func _behavior_bomber(delta: float) -> void:
	if _exploded:
		return
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()
	if _bomber_charging:
		velocity = Vector2.ZERO
		_bomber_charge_timer -= delta
		if _bomber_charge_timer <= 0.0:
			_exploded = true
			_bomber_charging = false
			_trigger_explosion()
		return
	velocity = dir * speed
	if dist < 62.0:
		_bomber_charging = true
		_bomber_charge_timer = 0.62
		velocity = Vector2.ZERO
		play_combat_telegraph("bomber_detonate", 0.62, explosion_radius)

func _behavior_trapper(delta: float) -> void:
	if _trapper_revealing:
		velocity = Vector2.ZERO
		_trapper_reveal_timer -= delta
		if _trapper_reveal_timer <= 0.0:
			_trapper_revealing = false
			_triggered = true
		return
	if _triggered:
		var direction := (player_ref.global_position - global_position).normalized()
		velocity = direction * speed * 2.6
		return
	var to_player := player_ref.global_position - global_position
	if to_player.length() < trigger_radius:
		_trapper_revealing = true
		_trapper_reveal_timer = 0.38
		velocity = Vector2.ZERO
		play_combat_telegraph("trapper_emerge", 0.38, trigger_radius)
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
			var final_dmg := int(float(damage) * _damage_multiplier)
			# counter_strike buff：被攻击触发后，下次攻击伤害×1.4（持续3秒）
			var cs_until: float = get("counter_strike_until") if get("counter_strike_until") != null else 0.0
			var now: float = Time.get_ticks_msec() * 0.001
			if now < cs_until:
				final_dmg = int(float(final_dmg) * 1.4)
			player_ref.take_damage(final_dmg)
		_contact_timer = contact_damage_interval

func _ranged_shoot(dir: Vector2) -> void:
	if _ranged_windup_active:
		return
	_ranged_windup_active = true
	play_combat_telegraph("ranged_shot", 0.28, 0.0)
	await get_tree().create_timer(0.22).timeout
	if _is_dead or not is_instance_valid(self):
		return
	if player_ref != null and is_instance_valid(player_ref):
		dir = (player_ref.global_position - global_position).normalized()
	var projectile: Node = ENEMY_PROJECTILE_SCENE.instantiate()
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(projectile)
	var spawn_pos := global_position + dir * 28.0
	if projectile.has_method("launch"):
		projectile.launch(spawn_pos, dir, 315.0, int(float(damage) * _damage_multiplier))
	_ranged_windup_active = false


func play_combat_telegraph(kind: String, duration: float, radius: float = 0.0) -> void:
	if avatar_renderer != null:
		avatar_renderer.play_telegraph(kind, duration, radius)


func get_visual_profile() -> Dictionary:
	return EnemyShape.get_profile(enemy_shape)


func get_attack_windup_state() -> Dictionary:
	return {
		"ranged": _ranged_windup_active,
		"bomber": _bomber_charging,
		"bomber_remaining": _bomber_charge_timer,
		"trapper": _trapper_revealing,
		"trapper_remaining": _trapper_reveal_timer,
	}

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
	if _barrier_active:
		if Time.get_ticks_msec() * 0.001 <= _barrier_until:
			_barrier_active = false
			_barrier_until = 0.0
			_spawn_block_effect()
			return
		_barrier_active = false
		_barrier_until = 0.0
	if _shield_wall_active and randf() < _shield_wall_effectiveness:
		_spawn_block_effect()
		return
	if _shield_reflect_active and randf() < _shield_reflect_chance:
		_spawn_block_effect()
		return
	# === 护盾格挡（Tank类精英/护盾型敌人）===
	var shield_rate_val: float = 0.0
	var shield_rate_variant = get("shield_rate")
	if shield_rate_variant != null:
		shield_rate_val = float(shield_rate_variant)
	if shield_rate_val > 0.0 and randf() < shield_rate_val:
		_spawn_block_effect()
		return  # 完全抵挡本次伤害
	# 记录是否刚跨过低血线
	var was_above_low_hp := float(current_hp) / maxf(1.0, float(max_hp)) > 0.4
	current_hp = max(0, current_hp - amount)
	if not _charge_immune and hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * (95.0 if not is_crit else 150.0)
	_update_hp_bar()
	if avatar_renderer != null:
		avatar_renderer.play_hit(is_crit, hit_dir)
	flash_damage(is_crit)
	enemy_hit.emit(global_position, amount, is_crit)
	_spawn_damage_number(global_position, amount, is_crit)
	# HitStop：命中停顿感（2-4帧短暂停顿，增强打击感）
	Global.trigger_hitstop(is_crit)
	# 通知技能组件受击
	var attacker_pos := global_position - hit_dir.normalized() * 64.0 if hit_dir.length_squared() > 0.0001 else global_position
	_notify_skill_components("on_taken_damage", [amount, attacker_pos])
	if _is_dead:
		return
	# 检查是否刚跨过低血线
	if current_hp > 0 and was_above_low_hp and float(current_hp) / maxf(1.0, float(max_hp)) <= 0.4:
		_notify_skill_components("on_low_hp")
		if _is_dead:
			return
	# DOT 每次直接扣血也触发死亡检查
	if current_hp <= 0:
		die()

## 命运卡片元素DOT入口（火焰/冰霜/剧毒子弹调用）
func apply_dot(dot_type: String, dps: float, duration: float) -> void:
	if _is_dead:
		return
	if not _fuse_dot_active or _fuse_dot_type != dot_type:
		# 新类型DOT，重置叠加
		_fuse_dot_active = true
		_fuse_dot_type = dot_type
		_fuse_dot_dps = dps
		_fuse_dot_duration = duration
		_fuse_dot_timer = 0.0
		_fuse_dot_last_hp = current_hp
	else:
		# 同类型DOT，刷新持续时间并叠加伤害
		_fuse_dot_duration = duration
		_fuse_dot_dps += dps * 0.5  # 叠加时每秒伤害略微增加
	_fuse_dot_timer = 0.0
	# 视觉：敌人身上显示DOT状态颜色
	_apply_dot_visual(dot_type)

func _apply_dot_visual(dot_type: String) -> void:
	if shape == null:
		return
	match dot_type:
		"fire":
			# 火焰：橙红色叠加
			var fire_intensity := clampf(_fuse_dot_dps / 10.0, 0.0, 1.0)
			shape.color = Color(1.0, 0.4 * (1.0 - fire_intensity), 0.1, 1.0)
		"poison":
			# 毒素：绿色叠加
			var poison_intensity := clampf(_fuse_dot_dps / 10.0, 0.0, 1.0)
			shape.color = Color(0.1 + 0.3 * poison_intensity, 0.7, 0.1, 1.0)
		"ice":
			# 冰霜DOT：淡蓝色叠加（与冰冻视觉互补，冰冻走 apply_freeze 通道）
			var ice_intensity := clampf(_fuse_dot_dps / 10.0, 0.0, 1.0)
			shape.color = Color(0.3 + 0.15 * ice_intensity, 0.6 + 0.15 * ice_intensity, 1.0, 1.0)

## 冰冻入口（冰霜子弹命中时调用）
func apply_freeze(freeze_dur: float) -> void:
	if _is_dead:
		return
	if _frozen:
		# 已冰冻则刷新时间（不叠加）
		_freeze_timer = maxf(_freeze_timer, freeze_dur)
	else:
		_freeze_timer = freeze_dur
		_freeze_original_modulate = shape.modulate if shape else Color.WHITE
	_frozen = true
	_fuse_dot_active = false  # 冰冻同时结束DOT
	# 冰冻视觉：蓝白色，敌人停止移动
	if shape:
		shape.modulate = Color(0.5, 0.8, 1.0, 0.85)
		# 冰晶效果用缩放表现（稍微放大）
		shape.scale = Vector2.ONE * _current_scale * 1.15

func die() -> void:
	if _is_dead:
		return
	_notify_skill_components("on_death")
	_is_dead = true
	if avatar_renderer != null:
		avatar_renderer.play_death()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	enemy_died.emit()
	_spawn_death_flash()
	_spawn_death_spark_burst()
	emit_death_screen_effect()
	if hp_bar:
		hp_bar.visible = false


## 死亡时迸发火花
func _spawn_death_spark_burst() -> void:
	var burst_color: Color = shape.color if shape else Color(1.0, 0.4, 0.4, 1.0)
	SparkParticles.spawn_death_burst(global_position, burst_color, false)
	var target: CanvasItem = avatar_renderer if avatar_renderer != null else shape
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
	_current_scale = scale_mult
	if emoji_label:
		emoji_label.text = emoji
		emoji_label.scale = Vector2.ONE * scale_mult
		emoji_label.visible = false
	if shape:
		shape.color = color
		shape.scale = Vector2.ONE * scale_mult
		shape.visible = false
	if avatar_renderer:
		avatar_renderer.configure(enemy_shape, color, scale_mult)
	_apply_collision_profile()
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
	gun_badge.position = Vector2(-8, -45)  # 在名字标签下方（名字底部约-36，枪标底部约-37）
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

## 应用缩放倍率（巨大化词缀/命运卡片调用）
## 会同步放大碰撞半径和房间边界约束
## new_scale: 目标缩放值（基于原始1.0的倍率）
func apply_scale_factor(new_scale: float) -> void:
	if new_scale <= 0.01:
		return
	var old_scale: float = _current_scale
	_current_scale = new_scale
	_base_scale = new_scale

	# 同步放大碰撞半径
	contact_radius = 31.0 * _current_scale

	# 同步放大房间边界（按比例扩张安全区，让大型敌人不会被边界夹住）
	var margin: float = 22.0 * _current_scale
	var safe_margin: float = 80.0 * _current_scale
	# 房间边界扩张：保持中心不变，边际按比例放大
	var old_bounds: Rect2 = _room_bounds
	if old_bounds.has_area():
		var center: Vector2 = old_bounds.position + old_bounds.size * 0.5
		var new_size: Vector2 = old_bounds.size * _current_scale
		_room_bounds = Rect2(center - new_size * 0.5, new_size)

	# 传播到所有子节点视觉
	if emoji_label:
		emoji_label.scale = Vector2.ONE * _current_scale
	if shape:
		shape.scale = Vector2.ONE * _current_scale
		shape.visible = false
	if avatar_renderer:
		avatar_renderer.configure(enemy_shape, shape.color if shape else _base_color, _current_scale)
	_apply_collision_profile()
	# 装备标记也放大
	var gun_badge: Node = find_child("GunBadge", false, false)
	if gun_badge:
		gun_badge.scale = Vector2.ONE * _current_scale
	# 状态标签放大
	if _state_marker_label and is_instance_valid(_state_marker_label):
		_state_marker_label.scale = Vector2.ONE * _current_scale
	# HP条放大（但保持文字可读）
	if hp_bar:
		hp_bar.scale = Vector2.ONE

	print("[EnemyBase] apply_scale: %.2f (was %.2f), contact_radius=%.1f, room_bounds=%s"
		% [_current_scale, old_scale, contact_radius, _room_bounds])


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

		# 如果偷了Bullet模块，对当前子弹应用行为修饰
		if not _elite_bullet_modules.is_empty():
			var bullet_idx: int = mini(i, _elite_bullet_modules.size() - 1)
			var bullet_module: Dictionary = _elite_bullet_modules[bullet_idx]
			var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, bullet_module.get("module_id", "EliteBullet"))
			node.set_base_stats(bullet_module)
			if projectile.has_method("apply_fate_stats_from_node"):
				projectile.apply_fate_stats_from_node(node)
			node.free()

## 格挡效果：白色闪白 + "格挡" 文字弹出（Tank类护盾触发）
func _spawn_block_effect() -> void:
	# Shape 白光闪烁
	if shape:
		var orig_color: Color = shape.color
		shape.color = Color(1.0, 1.0, 1.0, 1.0)  # 纯白
		var t := create_tween()
		t.tween_property(shape, "color", orig_color, 0.12).set_trans(Tween.TRANS_QUAD)
	# 屏幕震动（intensity=2.0，格挡反馈）
	var shake := get_tree().root.find_child("ScreenShake", true, false) as Node
	if shake and shake.has_method("trigger"):
		shake.trigger(2.0, 0.08)
	# "格挡" 文字弹出
	var block_label := Label.new()
	block_label.text = "格挡"
	block_label.add_theme_font_size_override("font_size", 16)
	block_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # 白色
	block_label.add_theme_color_override("font_outline_color", Color(1.0, 0.85, 0.0, 1.0))  # 金色描边
	block_label.outline_size = 2
	block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block_label.z_index = 260
	# 在敌人头顶弹出
	var canvas_pos := _world_to_canvas_label(global_position + Vector2(0, -50))
	block_label.position = canvas_pos
	add_child(block_label)
	var shadow := Label.new()
	shadow.text = block_label.text
	shadow.add_theme_font_size_override("font_size", 16)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.6))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shadow.position = block_label.position + Vector2(1, 1)
	shadow.z_index = block_label.z_index - 1
	add_child(shadow)
	var end_y: float = block_label.position.y - 38.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(block_label, "position:y", end_y, 0.65).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(block_label, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(block_label, "scale", Vector2(0.8, 0.8), 0.65).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(shadow, "position:y", end_y + 1, 0.65).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(shadow, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(shadow, "scale", Vector2(0.8, 0.8), 0.65).set_trans(Tween.TRANS_LINEAR)
	tw.chain().tween_callback(
		func():
			if is_instance_valid(block_label):
				block_label.queue_free()
			if is_instance_valid(shadow):
				shadow.queue_free()
	)
	# 格挡次数打印（调试用）
	print("[EnemyBase] 格挡！ shield_rate=%.2f" % (get("shield_rate") if get("shield_rate") != null else 0.0))

## 世界坐标 → CanvasLayer 局部坐标（用于伤害/状态文字定位）
func _world_to_canvas_label(world_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return world_pos
	var cam := viewport.get_camera_2d()
	if cam == null:
		return world_pos
	return cam.get_global_transform().affine_inverse() * world_pos

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
	if DisplayServer.get_name() != "headless" and audio and audio.has_method("play_enemy_die_sfx"):
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
			scale_target = Vector2(1.18, 1.18)         # 加大暴击脉冲
		else:
			# 普通命中：轻微缩放脉冲（让每次命中都有"弹性"）
			scale_target = Vector2(1.06, 1.06)
		shape.color = flash_color
		# 缩放脉冲
		if scale_target != Vector2.ONE:
			var orig_scale := shape.scale
			shape.scale = scale_target
			var scale_tween := create_tween()
			scale_tween.tween_property(shape, "scale", orig_scale, flash_duration * 1.5)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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

## 注入精英主动技能（由 RoomWaveSpawner 在精英生成时调用）
## modifier_id: 词缀ID，用于 EliteActiveSkillComponent.inject_elite_skills() 路由技能
## tier: 1-3，影响技能强度
func _inject_elite_active_skills(modifier_id: String, tier: int) -> void:
	if not _is_elite:
		return
	if not has_method("add_child"):
		return
	var skill_comp_class: GDScript = load("res://src/enemy/components/EliteActiveSkillComponent.gd")
	if skill_comp_class == null:
		push_warning("[EnemyBase] EliteActiveSkillComponent script not found")
		return
	# 避免重复注入
	for child in get_children():
		if child.has_method("tick") and child.has_signal("elite_skill_triggered"):
			return
	var comp: Node = skill_comp_class.inject_elite_skills(self, modifier_id, tier)
	if comp == null:
		return
	if comp.has_signal("elite_skill_triggered") and not comp.elite_skill_triggered.is_connected(_on_elite_skill_triggered):
		comp.elite_skill_triggered.connect(_on_elite_skill_triggered)

## 精英技能触发回调（可由具体实现扩展）
func _on_elite_skill_triggered(skill_id: String, source: Node) -> void:
	pass

## 统一注入基础技能（由 RoomWaveSpawner / CoreCombatMode 调用）
func inject_basic_skill_for_kind(kind: String) -> void:
	var normalized := String(kind).to_lower()

	# 避免重复注入普通技能组件
	for child in get_children():
		if child.has_signal("skill_triggered") and not child.has_signal("elite_skill_triggered"):
			return

	var script_res := load("res://src/enemy/components/EnemySkillComponent.gd")
	if script_res == null:
		return

	var comp: Node = null

	match normalized:
		"chaser", "basic", "melee":
			comp = script_res.inject_chaser_skill(self)
		"ranged", "ranged_caster", "caster", "shooter":
			comp = script_res.inject_ranged_skill(self)
		"summoner":
			comp = script_res.inject_summoner_skill(self)
		"tank", "shielded", "brute":
			comp = script_res.inject_tank_skill(self)
		"bomber", "exploder", "suicide":
			comp = script_res.inject_bomber_skill(self)
		"trapper", "ambusher":
			comp = script_res.inject_trapper_skill(self)
		_:
			comp = script_res.inject_chaser_skill(self)

	if comp:
		add_child(comp)
		comp.set_component_owner(self)

## 设置伤害倍率（由环境命运触发器的 CURSE_ROOM_ENEMIES 调用）
## multiplier=1.15 表示伤害+15%
func apply_damage_multiplier(multiplier: float) -> void:
	_damage_multiplier = multiplier
	print("[EnemyBase] 伤害倍率设置为 %.2f（触发来源：环境命运-诅咒降临）" % multiplier)

func _spawn_damage_number(world_pos: Vector2, dmg: int, is_crit: bool = false) -> void:
	# 使用 DamageNumbers 静态方法，获得更好的视觉表现（字号/颜色分档 + 弹出动画 + 暴击震屏）
	DamageNumbers.spawn(world_pos, dmg, is_crit)
	return

## 治疗（由召唤者光环等调用）
func heal(amount: int) -> void:
	if _is_dead:
		return
	current_hp = min(max_hp, current_hp + amount)
	_update_hp_bar()
	_spawn_damage_number(global_position, -amount, false)
