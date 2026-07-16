class_name SparkParticles
## SparkParticles — 程序生成粒子爆发（火花）
## 用途：击中时 8 颗 0.2s 火星；死亡时 16 颗 0.4s 大颗粒
## 所有 API 静态，调用方无需关心生命周期

extends RefCounted


## 全局最大并发数（避免性能问题）
const MAX_CONCURRENT := 32
var _active_count: int = 0


## 在 pos 位置生成击中火花
## is_crit=true 时颜色为金色；否则按 damage_type 区分
## damage_type: ""=normal白, "fire"=红, "ice"=蓝, "poison"=紫
static func spawn_hit_spark(pos: Vector2, is_crit: bool = false, damage_type: String = "") -> void:
	if _instance == null:
		_instance = SparkParticles.new()
	_instance._spawn_burst(pos, 8, 0.2, _hit_color(is_crit, damage_type), 2.5)


## 死亡爆发（火花数量更多、尺寸更大、颜色为敌人色）
static func spawn_death_burst(pos: Vector2, enemy_color: Color, is_boss: bool = false) -> void:
	if _instance == null:
		_instance = SparkParticles.new()
	var count: int = 32 if is_boss else 16
	var lifetime: float = 0.5 if is_boss else 0.4
	_instance._spawn_burst(pos, count, lifetime, enemy_color, 4.0 if is_boss else 3.0)


## 拾取涟漪（8 颗向外扩散的圆环）
## pickup_type: "soul"=紫, "gold"=金, "item"=白
static func spawn_pickup_ripple(pos: Vector2, pickup_type: String = "item") -> void:
	if _instance == null:
		_instance = SparkParticles.new()
	var ripple_color: Color
	match pickup_type:
		"soul": ripple_color = Color(0.5, 0.3, 0.9, 0.85)
		"gold": ripple_color = Color(1.0, 0.85, 0.30, 0.85)
		_: ripple_color = Color(0.95, 0.85, 0.70, 0.85)
	_instance._spawn_ripple(pos, ripple_color)


# ========== 单例（用于全局计数） ==========
static var _instance: SparkParticles = null


# ========== 内部：核心 burst 生成器 ==========
func _spawn_burst(pos: Vector2, count: int, lifetime: float, color: Color, speed: float) -> void:
	# 限制并发数
	if _active_count >= MAX_CONCURRENT:
		return
	_active_count += 1
	# 创建一个父节点托管（添加到当前场景 root，避免被敌人/玩家释放带走）
	var scene := _get_current_scene()
	if scene == null:
		_active_count -= 1
		return
	var host := Node2D.new()
	host.position = pos
	host.z_index = 200
	scene.add_child(host)
	for i in count:
		var spark := _make_spark(color, speed, lifetime)
		host.add_child(spark)
	# 自我清理
	var tween := host.create_tween()
	tween.tween_interval(lifetime + 0.1)
	tween.tween_callback(func():
		_active_count = maxi(0, _active_count - 1)
		if is_instance_valid(host):
			host.queue_free()
	)


## 内部：涟漪扩散
func _spawn_ripple(pos: Vector2, color: Color) -> void:
	if _active_count >= MAX_CONCURRENT:
		return
	_active_count += 1
	var scene := _get_current_scene()
	if scene == null:
		_active_count -= 1
		return
	var host := Node2D.new()
	host.position = pos
	host.z_index = 195
	scene.add_child(host)
	for i in 8:
		var angle: float = TAU * i / 8.0
		var spark := _make_spark(color, 90.0, 0.5)
		spark.scale = Vector2.ONE * 1.4
		host.add_child(spark)
	var tween := host.create_tween()
	tween.tween_interval(0.6)
	tween.tween_callback(func():
		_active_count = maxi(0, _active_count - 1)
		if is_instance_valid(host):
			host.queue_free()
	)


# ========== 内部工具 ==========

func _make_spark(color: Color, speed: float, lifetime: float) -> Polygon2D:
	var spark := Polygon2D.new()
	spark.color = color
	# 4px 半径的小三角（朝随机方向运动）
	spark.polygon = PackedVector2Array([
		Vector2(0, -3),
		Vector2(2.5, 1.5),
		Vector2(-2.5, 1.5),
	])
	# 随机方向 + 速度
	var angle := randf() * TAU
	var vel := Vector2(cos(angle), sin(angle)) * speed * randf_range(0.6, 1.0)
	# 直接用 process 模式移动 + 淡出
	spark.set_script(_SparkScript)
	spark.set("_lifetime", lifetime)
	spark.set("_velocity", vel)
	return spark


static func _hit_color(is_crit: bool, damage_type: String) -> Color:
	if is_crit:
		return Color(1.0, 0.85, 0.30, 0.95)  # 暴击金
	match damage_type:
		"fire": return Color(1.0, 0.45, 0.15, 0.95)
		"ice": return Color(0.5, 0.85, 1.0, 0.95)
		"poison": return Color(0.55, 0.30, 0.85, 0.95)
		_: return Color(1.0, 1.0, 0.85, 0.95)  # 普通白


static func _get_current_scene() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene


# ========== 内嵌脚本：火花移动+淡出 ==========

const _SparkScript := preload("res://src/fx/_SparkScript.gd")
