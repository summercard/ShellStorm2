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
	configure(color, size, context)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = world_position
	_on_activate(world_position, color, size, context)
	_elapsed = 0.0

func _process(delta: float) -> void:
	if not _active:
		return
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
