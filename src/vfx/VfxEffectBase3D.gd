class_name VfxEffectBase3D
extends Node3D
## 所有 VFX Prefab 的根节点基类（FX01-01~05 等战斗反馈特效共用）。
## 调用方只看见本基类暴露的接口；特效私有逻辑在子类中实现。
## 规范见 docs/v0.1/14.6_特效系统与制作规范.md §3.1

signal retired(effect: VfxEffectBase3D)

@export var effect_color: Color = Color(1, 1, 1, 1)
@export_range(0.1, 8.0, 0.1) var effect_size: float = 1.0
@export var lifetime: float = 0.34

var _elapsed: float = 0.0
var _active: bool = false
# 可选跟随：context.follow 传挂点（Node3D），context.follow_local_offset 传挂点本地空间的偏移。
# 供"必须贴着移动挂点"的表现使用（枪口花火等）；不绑定时退化为生成瞬间的世界锚定。
var _follow: Node3D = null
var _follow_local_offset: Vector3 = Vector3.ZERO

# 子类可注册这些回调
func _on_configure(_context: Dictionary) -> void:
	pass

func _on_activate(_world_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	pass

func _on_tick(_elapsed: float, _total: float) -> void:
	pass

func _on_lifetime_expired() -> void:
	pass

# 公共 API（调用方只能使用这些）
func configure(color: Color, size: float = 1.0, context: Dictionary = {}) -> void:
	effect_color = color
	effect_size = size
	_on_configure(context)

func activate(world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	_bind_follow(context)
	configure(color, size, context)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = follow_position() if has_follow_target() else world_position
	_on_activate(world_position, color, size, context)
	_elapsed = 0.0

func _process(delta: float) -> void:
	if not _active:
		return
	# 跟随挂点：挂点移动/转身时特效必须一直贴着它，而不是留在生成瞬间的世界坐标。
	if has_follow_target():
		global_position = follow_position()
	_elapsed += delta
	_on_tick(_elapsed, lifetime)
	if _elapsed >= lifetime:
		_retire()

func _retire() -> void:
	_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_on_lifetime_expired()
	if retired.get_connections().is_empty():
		queue_free()
	else:
		retired.emit(self)

# 跟随契约实现
func _bind_follow(context: Dictionary) -> void:
	_follow = context.get("follow") as Node3D
	if _follow != null and not is_instance_valid(_follow):
		_follow = null
	var offset: Variant = context.get("follow_local_offset", Vector3.ZERO)
	_follow_local_offset = (offset as Vector3) if offset is Vector3 else Vector3.ZERO

## 是否绑定了仍然可用的跟随挂点（挂点被移出树时自动退化为世界锚定）。
func has_follow_target() -> bool:
	return _follow != null and is_instance_valid(_follow) and _follow.is_inside_tree()

## 特效当前应处的世界坐标：按挂点本地偏移换算；无挂点时保持现状。
func follow_position() -> Vector3:
	if not has_follow_target():
		return global_position
	return _follow.to_global(_follow_local_offset)

## 挂点前向（挂点 local -Z，归一化），供子类在 tick 中重算朝向。
func follow_forward() -> Vector3:
	if not has_follow_target():
		return Vector3.FORWARD
	var dir := -_follow.global_basis.z
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()
