class_name VfxPool3D
extends Node3D
## FX01-01~05 等战斗反馈特效的全局对象池（autoload 单例）

const VfxEffectBase3D = preload("res://src/vfx/VfxEffectBase3D.gd")
## 规范见 docs/v0.1/14.6_特效系统与制作规范.md §5
## 调用方按 AssetID（如 "VFX-MUZZLE-FLASH-3D"）路由到对应 bucket

const FX01_MUZZLE_FLASH := "VFX-MUZZLE-FLASH-3D"
const FX01_IMPACT := "VFX-IMPACT-3D"
const FX01_EXPLOSION := "VFX-EXPLOSION-3D"
const FX01_MELEE_SLASH := "VFX-MELEE-SLASH-3D"
const FX01_MELEE_IMPACT := "VFX-MELEE-IMPACT-3D"
const FX02_DAMAGE_NUMBER := "VFX-DAMAGE-NUMBER-3D"
const FX02_HEAL_NUMBER := "VFX-HEAL-NUMBER-3D"

const _REGISTRY := {
	FX01_MUZZLE_FLASH: preload("res://assets/art/vfx/combat_3d/vfx_muzzle_flash_root_top3d_v001.tscn"),
	FX01_IMPACT: preload("res://assets/art/vfx/combat_3d/vfx_impact_root_top3d_v001.tscn"),
	FX01_EXPLOSION: preload("res://assets/art/vfx/combat_3d/vfx_explosion_root_top3d_v001.tscn"),
	FX01_MELEE_SLASH: preload("res://assets/art/vfx/combat_3d/vfx_melee_slash_root_top3d_v001.tscn"),
	FX01_MELEE_IMPACT: preload("res://assets/art/vfx/combat_3d/vfx_melee_impact_root_top3d_v001.tscn"),
	FX02_DAMAGE_NUMBER: preload("res://assets/art/vfx/combat_3d/vfx_damage_number_root_top3d_v001.tscn"),
	FX02_HEAL_NUMBER: preload("res://assets/art/vfx/combat_3d/vfx_heal_number_root_top3d_v001.tscn"),
}

@export var max_per_kind: int = 32
@export var spawn_parent_path: NodePath

var _active: Dictionary = {}    # asset_id -> Array[VfxEffectBase3D]
var _inactive: Dictionary = {}  # asset_id -> Array[VfxEffectBase3D]
var _spawn_parent: Node3D

func _ready() -> void:
	add_to_group("vfx_pool_3d")
	if spawn_parent_path.is_empty():
		_spawn_parent = self
	else:
		_spawn_parent = get_node_or_null(spawn_parent_path) as Node3D
		if _spawn_parent == null:
			_spawn_parent = self
	for asset_id in _REGISTRY.keys():
		_active[asset_id] = []
		_inactive[asset_id] = []

## 按 AssetID 借出特效
func acquire(asset_id: StringName, world_pos: Vector3, color: Color, size: float = 1.0, context: Dictionary = {}) -> VfxEffectBase3D:
	if not _REGISTRY.has(asset_id):
		push_error("VfxPool3D: unknown asset_id '%s'" % asset_id)
		return null
	var eff: VfxEffectBase3D = null
	var inactive_bucket: Array = _inactive[asset_id]
	if not inactive_bucket.is_empty():
		eff = inactive_bucket.pop_back()
	else:
		var packed: PackedScene = _REGISTRY[asset_id]
		eff = packed.instantiate() as VfxEffectBase3D
		if eff == null:
			push_error("VfxPool3D: instantiate failed for '%s'" % asset_id)
			return null
		_spawn_parent.add_child(eff)
	eff.activate(world_pos, color, size, context)
	_active[asset_id].append(eff)
	# 监听 retired 信号，retire 时回收到 inactive
	# retired 已经携带 effect；这里只绑定 asset_id，避免把同一实例作为第三个参数重复传入。
	var retire_callback := _on_effect_retired.bind(asset_id)
	if not eff.retired.is_connected(retire_callback):
		eff.retired.connect(retire_callback)
	return eff

## 按 AssetID 归还特效（通常由 retired 信号自动调用）
func retire(asset_id: StringName, effect: VfxEffectBase3D) -> void:
	if not _active.has(asset_id):
		return
	_active[asset_id].erase(effect)
	if not _inactive.has(asset_id):
		_inactive[asset_id] = []
	if _inactive[asset_id].size() >= max_per_kind:
		# bucket 已满，直接 free
		effect.queue_free()
		return
	_inactive[asset_id].append(effect)

## 清理某 AssetID 的所有 active 实例（场景卸载时调用）
func clear_kind(asset_id: StringName) -> void:
	if not _active.has(asset_id):
		return
	for eff in _active[asset_id]:
		if is_instance_valid(eff):
			eff.queue_free()
	_active[asset_id].clear()

## 清理所有特效
func clear_all() -> void:
	for asset_id in _active.keys():
		clear_kind(asset_id)
	for asset_id in _inactive.keys():
		for eff in _inactive[asset_id]:
			if is_instance_valid(eff):
				eff.queue_free()
		_inactive[asset_id].clear()

## 当前激活的某 AssetID 数量（测试用）
func active_count(asset_id: StringName) -> int:
	if not _active.has(asset_id):
		return 0
	return _active[asset_id].size()


func inactive_count(asset_id: StringName) -> int:
	if not _inactive.has(asset_id):
		return 0
	return _inactive[asset_id].size()

func _on_effect_retired(effect: VfxEffectBase3D, asset_id: StringName) -> void:
	retire(asset_id, effect)
