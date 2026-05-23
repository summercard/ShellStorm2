class_name WeaponRecoil
extends Node2D
## 武器后坐力动画
## 挂载在武器节点上，通过 recoil_signal 信号与 WeaponController 联动
## 每次 fire() 时播放反向抖动动画，高后坐力武器（霰弹/狙击）幅度更大

## 信号
signal recoil_finished()

## 配置
@export var enabled: bool = true
@export var recoil_intensity: float = 8.0   # 基础后坐力强度（像素）
@export var recoil_duration: float = 0.12    # 后坐力持续时间（秒）
@export var kick_intensity: float = 6.0      # 枪口上扬幅度（像素）

## 内部
var _host: Node2D = null
var _is_recoiling: bool = false
var _recoil_tween: Tween = null

## 武器类型 → 后坐力倍率映射（来自 WeaponAssemblyTree 的 tags 判断）
## 高后坐力: shotgun(1.8x), sniper(1.5x), grenade_launcher(2.0x)
## 中后坐力: rifle(1.0x), smg(0.8x)
## 低后坐力: pistol(0.5x)
var _recoil_multiplier: float = 1.0

func _ready() -> void:
	_host = get_parent()
	if _host and _host.has_signal("weapon_fired"):
		_host.weapon_fired.connect(_on_weapon_fired)

func _on_weapon_fired(spawn_pos: Vector2, direction: Vector2, count: int) -> void:
	if not enabled:
		return
	_trigger_recoil()

## 触发后坐力动画（外部调用）
func trigger(weapon_tags: Array[String] = []) -> void:
	if not enabled:
		return
	_apply_weapon_multiplier(weapon_tags)
	_trigger_recoil()

## 根据武器标签调整后坐力倍率
func _apply_weapon_multiplier(tags: Array[String]) -> void:
	if tags.is_empty():
		_recoil_multiplier = 1.0
		return
	if "shotgun" in tags or "grenade" in tags:
		_recoil_multiplier = 1.8
	elif "sniper" in tags or "precision" in tags:
		_recoil_multiplier = 1.5
	elif "rifle" in tags or "assault" in tags:
		_recoil_multiplier = 1.0
	elif "smg" in tags or "automatic" in tags:
		_recoil_multiplier = 0.8
	elif "pistol" in tags or "semi_auto" in tags:
		_recoil_multiplier = 0.5
	else:
		_recoil_multiplier = 1.0

## 核心后坐力动画：反向射击方向抖动 + 枪口上扬
func _trigger_recoil() -> void:
	if not is_instance_valid(_host) or _recoil_tween != null:
		return
	
	# 停止之前的动画
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	
	_recoil_tween = _host.create_tween()
	_recoil_tween.set_parallel(true)
	
	var actual_intensity := recoil_intensity * _recoil_multiplier
	var actual_kick := kick_intensity * _recoil_multiplier
	
	# 后坐力：往射击反方向抖动
	# _host.rotation 方向的反向
	_recoil_tween.tween_property(_host, "position:x", _host.position.x - actual_intensity, recoil_duration * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(_host, "position:x", _host.position.x + actual_intensity * 0.3, recoil_duration * 0.5) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# 枪口上扬（Y轴正向 = 往下，实际是旋转补偿）
	_recoil_tween.tween_property(_host, "position:y", _host.position.y - actual_kick, recoil_duration * 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(_host, "position:y", _host.position.y, recoil_duration * 0.7) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	_recoil_tween.chain().tween_callback(_on_recoil_done)

func _on_recoil_done() -> void:
	_recoil_tween = null
	recoil_finished.emit()
