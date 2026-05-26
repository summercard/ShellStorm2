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

## 核心后坐力动画：沿枪口反方向（局部 -X 轴）抖动 + 枪口上扬
## 修复：之前用世界坐标 X/Y 移动，不受枪口朝向影响。
## 现在把局部偏移（-X 方向=枪口反方向，-Y 方向=枪口上方）旋转到世界坐标，
## 让后坐力在任意朝向都正确表现为"枪口向后的反冲"。
func _trigger_recoil() -> void:
	if not is_instance_valid(_host) or _recoil_tween != null:
		return
	
	# 停止之前的动画
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	
	var actual_intensity := recoil_intensity * _recoil_multiplier
	var actual_kick := kick_intensity * _recoil_multiplier
	
	# 局部空间偏移：-X=枪口反方向，-Y=枪口上方
	var local_backward := Vector2(-actual_intensity, 0.0)
	var local_upward := Vector2(0.0, -actual_kick * 0.5)
	
	# 旋转到世界坐标（_host.rotation 是枪口朝向，-X 绕原点旋转后就是枪口向后）
	var world_backward := local_backward.rotated(_host.rotation)
	var world_upward := local_upward.rotated(_host.rotation)
	
	# 基准位置
	var origin_pos := _host.position
	
	# 最终回归位置
	var final_pos := origin_pos
	
	# 峰值位置（向后的偏移 + 枪口上扬）
	var peak_pos := origin_pos + world_backward + world_upward
	
	_recoil_tween = _host.create_tween()
	
	# 峰值（后坐力最大点）—— 快速
	_recoil_tween.tween_property(_host, "position", peak_pos, recoil_duration * 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 回弹（弹力回正）—— 较慢
	_recoil_tween.tween_property(_host, "position", final_pos, recoil_duration * 0.7) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	_recoil_tween.chain().tween_callback(_on_recoil_done)

func _on_recoil_done() -> void:
	_recoil_tween = null
	recoil_finished.emit()
