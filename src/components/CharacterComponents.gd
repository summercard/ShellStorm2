## CharacterComponents - 角色组件集中管理（2026-06-10）
##
## 一个角色持有一个 CharacterComponents 实例，集中管理：
## - body 组件（必须）
## - head 组件（可选，但实际角色一般都有）
## - hand / right_hand 主手组件（默认创建）；left_hand 仅供明确需要双手的角色选配
##
## 提供：
## - 统一构造：在角色 _ready 里 create_default_layout() 一次性建好 body/head/hand
## - 反馈广播：apply_feedback_all() 同时让所有组件响应一个事件
## - 武器挂载入口：attach_weapon_to_hand() 自动挂到 hand 上
## - 反馈 tick：tick_feedbacks(delta) 推进所有组件的反馈计时

class_name CharacterComponents
extends Node2D

const HAND_SOCKET_X := 19.0
const FACING_DEADZONE := 0.15

## 身体组件（构造后自动有）
var body: BodyComponent = null
## 头部组件
var head: HeadComponent = null
## 手部组件
var hand: HandComponent = null
var left_hand: HandComponent = null
var right_hand: HandComponent = null
var _visual_facing_sign: float = 1.0

## 构造默认布局：body 包含 head 包含 hand
## body_visual_path: 身体视觉节点的路径（相对 body 组件，例 NodePath("Shape")）
## head_visual_path: 头部视觉节点的路径（相对 head 组件）
## hand_visual_path: 手部视觉节点的路径（相对 hand 组件）
func create_default_layout(body_visual_path: NodePath, head_visual_path: NodePath, hand_visual_path: NodePath) -> void:
	if body == null:
		body = BodyComponent.new()
		body.name = "Body"
		body.visual_node_path = body_visual_path
		add_child(body)
	if head == null:
		head = HeadComponent.new()
		head.name = "Head"
		head.visual_node_path = head_visual_path
		body.add_child(head)
	if right_hand == null:
		right_hand = HandComponent.new()
		right_hand.name = "HandR"
		right_hand.visual_node_path = hand_visual_path
		body.attach_hand(right_hand, "right")
		hand = right_hand

## 只构造身体和头部（不构造手）—— 给没有手的角色用（例：怪物）
func create_layout_no_hand(body_visual_path: NodePath, head_visual_path: NodePath) -> void:
	if body == null:
		body = BodyComponent.new()
		body.name = "Body"
		body.visual_node_path = body_visual_path
		add_child(body)
	if head == null:
		head = HeadComponent.new()
		head.name = "Head"
		head.visual_node_path = head_visual_path
		body.add_child(head)

## 武器挂到手上（手组件必须存在）
func attach_weapon_to_hand(weapon_node: Node, side: String = "right") -> bool:
	var target_hand := left_hand if side == "left" else right_hand
	if target_hand == null:
		push_warning("CharacterComponents.attach_weapon_to_hand: 角色没有手组件")
		return false
	target_hand.attach_weapon(weapon_node)
	return true


func set_aim_direction(direction: Vector2) -> void:
	if absf(direction.x) > FACING_DEADZONE:
		_visual_facing_sign = -1.0 if direction.x < 0.0 else 1.0
	if right_hand != null:
		right_hand.position.x = HAND_SOCKET_X * _visual_facing_sign
		right_hand.set_aim_direction(direction)

## 广播反馈事件给所有组件（同时播放）
func apply_feedback_all(feedback_type: int, duration: float = 0.15, intensity: float = 1.0) -> void:
	if body != null:
		body.call("apply_feedback", feedback_type, duration, intensity)
	if head != null:
		head.call("apply_feedback", feedback_type, duration, intensity)
	if hand != null:
		hand.call("apply_feedback", feedback_type, duration, intensity)
	if left_hand != null:
		left_hand.call("apply_feedback", feedback_type, duration, intensity)

## 广播反馈给指定组件
func apply_feedback_to(target: String, feedback_type: int, duration: float = 0.15, intensity: float = 1.0) -> void:
	# target: "body" / "head" / "hand"
	match target:
		"body":
			if body != null: body.call("apply_feedback", feedback_type, duration, intensity)
		"head":
			if head != null: head.call("apply_feedback", feedback_type, duration, intensity)
		"hand":
			if hand != null: hand.call("apply_feedback", feedback_type, duration, intensity)
		"hand_l", "left_hand":
			if left_hand != null: left_hand.call("apply_feedback", feedback_type, duration, intensity)
		"hand_r", "right_hand":
			if right_hand != null: right_hand.call("apply_feedback", feedback_type, duration, intensity)
		_:
			push_warning("CharacterComponents.apply_feedback_to: 未知目标 '%s'" % target)

## 推进所有组件的反馈计时（由角色 _process 调用）
func tick_feedbacks(delta: float) -> void:
	if body != null: body.call("tick_feedback", delta)
	if head != null: head.call("tick_feedback", delta)
	if hand != null: hand.call("tick_feedback", delta)
	if left_hand != null: left_hand.call("tick_feedback", delta)

## 强制清空所有反馈
func reset_feedbacks() -> void:
	if body != null: body.call("reset")
	if head != null: head.call("reset")
	if hand != null: hand.call("reset")
	if left_hand != null: left_hand.call("reset")
# ========== 组件摆动动画 (2026-06-10) ==========
## 待机时身体轻微上下浮动；移动时身体轻微左右倾斜 + 头/手跟随
## 由 Player._physics_process 在末尾调一次

## 当前摆动相位（统一推进）
var _anim_phase: float = 0.0
## 当前移动方向（用于倾斜计算）
var _last_move_dir: Vector2 = Vector2.ZERO
## 当前是否在移动（外部传进来）
var _anim_is_moving: bool = false

## 摆动参数（可调）
@export var idle_bob_amplitude: float = 1.5       ## 待机上下浮动幅度（像素）
@export var idle_bob_frequency: float = 1.8       ## 待机浮动频率（Hz × 2π）
@export var move_tilt_amplitude: float = 0.08      ## 移动左右倾斜角度（弧度，~4.5度）
@export var move_tilt_frequency: float = 6.0       ## 移动倾斜频率
@export var move_bob_amplitude: float = 2.5       ## 移动时身体上下浮动幅度（更大）
@export var move_bob_frequency: float = 5.5       ## 移动时浮动频率
@export var head_phase_offset: float = 0.35        ## 头部相对身体的相位延迟
@export var hand_phase_offset: float = 0.55        ## 手部相对身体的相位延迟

## 推进摆动（由 Player._physics_process 调）
## delta: 帧间隔
## move_dir: 移动方向（用于倾斜方向）。ZERO 表示待机
func tick_animations(delta: float, move_dir: Vector2) -> void:
	_anim_phase += delta
	_anim_is_moving = move_dir.length_squared() > 0.0001
	_last_move_dir = move_dir
	if body == null:
		return
	# 身体：待机浮动 vs 移动浮动
	var body_offset: Vector2 = _compute_body_offset()
	var body_tilt: float = _compute_body_tilt()
	body.position = body_offset
	body.rotation = body_tilt
	# 头：跟随 body 浮动 + 一点点相位延迟
	if head != null:
		var head_phase: float = _anim_phase - head_phase_offset / max(0.5, idle_bob_frequency)
		var head_offset: Vector2 = _compute_body_offset_at(head_phase, body_offset)
		head.position = Vector2(0, head_offset.y)
		# 头倾斜略小于身体
		head.rotation = body_tilt * 0.6
	# 默认主手随身体朝向在左右固定插槽换边；只有武器挂点读取完整瞄准方向。
	if right_hand != null:
		var hand_phase: float = _anim_phase - hand_phase_offset / max(0.5, idle_bob_frequency)
		var hand_offset: Vector2 = _compute_body_offset_at(hand_phase, body_offset)
		right_hand.position = Vector2(HAND_SOCKET_X * _visual_facing_sign, hand_offset.y * 0.55)
		right_hand.rotation = 0.0
	if left_hand != null:
		var left_phase: float = _anim_phase - (hand_phase_offset + 0.2) / max(0.5, idle_bob_frequency)
		var left_offset: Vector2 = _compute_body_offset_at(left_phase, body_offset)
		left_hand.position = Vector2(-HAND_SOCKET_X * _visual_facing_sign, left_offset.y * 0.55)
		left_hand.rotation = 0.0

## 计算身体的偏移
func _compute_body_offset() -> Vector2:
	if _anim_is_moving:
		var y: float = sin(_anim_phase * move_bob_frequency * 2.0 * PI) * move_bob_amplitude
		return Vector2(0, y)
	else:
		var y: float = sin(_anim_phase * idle_bob_frequency * 2.0 * PI) * idle_bob_amplitude
		return Vector2(0, y)

## 计算在指定相位下的偏移（用基线插值）
func _compute_body_offset_at(phase: float, fallback: Vector2) -> Vector2:
	if _anim_is_moving:
		var y: float = sin(phase * move_bob_frequency * 2.0 * PI) * move_bob_amplitude
		return Vector2(0, y)
	else:
		var y: float = sin(phase * idle_bob_frequency * 2.0 * PI) * idle_bob_amplitude
		return Vector2(0, y)

## 计算身体倾斜角度（移动时左右摇摆）
func _compute_body_tilt() -> float:
	if not _anim_is_moving:
		return 0.0
	# 倾斜方向：根据 _last_move_dir.x 决定
	var sign: float = 1.0 if _last_move_dir.x >= 0.0 else -1.0
	return sin(_anim_phase * move_tilt_frequency * 2.0 * PI) * move_tilt_amplitude * sign
