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
const FX01_SHELL_CASING := "VFX-SHELL-CASING-3D"
## 胖子僵尸死亡自爆（FX01-17）——由 `Enemy3D._detonate_death_explosion()` 经本池借出。
##
## ⚠ 它的**地面残留伤害场**（FX01-18 `VFX-BLAST-ZONE-3D`）**刻意不进本注册表**：
## 那片场地由 `DeathBlastZone3D` 作为**长期子实例**持有（时长 = 场地持续时长），
## 池化的瞬时计时语义与它冲突；与 FX01-16 头顶吼叫图标、FX03-03 收音机音符同一口径。
## 场地侧的 AssetID 常量见 `src/enemy3d/DeathBlastZone3D.gd` 的 `ZONE_VFX_ASSET_ID`。
const FX01_DEATH_BLAST := "VFX-DEATH-BLAST-3D"
## 小僵尸 / 警察僵尸死亡「绿色方块爆开」特效（FX01-19）——由 `Enemy3D._die()`
## 经 `_spawn_goo_death_burst()` 借出。一次性、1.35s、纯视觉、无朝向契约。
const FX01_ZOMBIE_GOO_DEATH := "VFX-ZOMBIE-GOO-DEATH-3D"
## 僵尸命中爆点（FX01-20）——打中「僵尸三兄弟」（小僵尸 / 警察僵尸 / 胖子僵尸）时的受击反馈。
## 由 `Projectile3D._spawn_hit_effect()` 与 `PlayerMeleeCombat3D._spawn_hit_feedback()` 借出。
const FX01_GOO_HIT := "VFX-GOO-HIT-3D"
## 金属打击火星（FX01-21）——击中**非**僵尸目标（墙面 / 掩体 / 地面 / 其它怪种）时的反馈。
## 与 FX01-02 `VFX-IMPACT-3D` 刻意是两件：后者保留了「非僵尸怪种死亡爆点 / 护盾弹开」等用途。
const FX01_METAL_SPARK_HIT := "VFX-METAL-SPARK-HIT-3D"
const FX02_DAMAGE_NUMBER := "VFX-DAMAGE-NUMBER-3D"
const FX02_HEAL_NUMBER := "VFX-HEAL-NUMBER-3D"

const _REGISTRY := {
	FX01_MUZZLE_FLASH: preload("res://assets/art/vfx/combat_3d/vfx_muzzle_flash_root_top3d.tscn"),
	FX01_IMPACT: preload("res://assets/art/vfx/combat_3d/vfx_impact_root_top3d.tscn"),
	FX01_EXPLOSION: preload("res://assets/art/vfx/combat_3d/vfx_explosion_root_top3d.tscn"),
	FX01_MELEE_SLASH: preload("res://assets/art/vfx/combat_3d/vfx_melee_slash_root_top3d.tscn"),
	FX01_MELEE_IMPACT: preload("res://assets/art/vfx/combat_3d/vfx_melee_impact_root_top3d.tscn"),
	FX01_SHELL_CASING: preload("res://assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn"),
	FX01_DEATH_BLAST: preload("res://assets/art/vfx/combat_3d/vfx_death_blast_root_top3d.tscn"),
	FX01_ZOMBIE_GOO_DEATH: preload("res://assets/art/vfx/combat_3d/vfx_zombie_goo_death_root_top3d.tscn"),
	FX01_GOO_HIT: preload("res://assets/art/vfx/combat_3d/vfx_goo_hit_root_top3d.tscn"),
	FX01_METAL_SPARK_HIT: preload("res://assets/art/vfx/combat_3d/vfx_metal_spark_hit_root_top3d.tscn"),
	FX02_DAMAGE_NUMBER: preload("res://assets/art/vfx/combat_3d/vfx_damage_number_root_top3d.tscn"),
	FX02_HEAL_NUMBER: preload("res://assets/art/vfx/combat_3d/vfx_heal_number_root_top3d.tscn"),
}


static func create_unpooled(asset_id: StringName) -> VfxEffectBase3D:
	if not _REGISTRY.has(asset_id):
		return null
	var packed: PackedScene = _REGISTRY[asset_id]
	return packed.instantiate() as VfxEffectBase3D


static func has_effect(asset_id: StringName) -> bool:
	return _REGISTRY.has(asset_id)

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
		eff = create_unpooled(asset_id)
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
