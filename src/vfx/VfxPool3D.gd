class_name VfxPool3D
extends Node3D
## FX01-01~05 等战斗反馈特效的全局对象池（autoload 单例）

const VfxEffectBase3D = preload("res://src/vfx/VfxEffectBase3D.gd")
## 规范见 docs/v0.1/14.6_特效系统与制作规范.md §5
## 调用方按 AssetID（如 "VFX-MUZZLE-FLASH-3D"）路由到对应 bucket

const FX01_FATE_FIRE := "VFX-FATE-FIRE-3D"
const FX01_FATE_FROST := "VFX-FATE-FROST-3D"
const FX01_FATE_POISON := "VFX-FATE-POISON-3D"
const FX01_FATE_LIGHTNING := "VFX-FATE-LIGHTNING-3D"

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

const FX01_FATE_ROCK_SHATTER := "VFX-FATE-ROCK-SHATTER-3D"

## 暗门木板被打碎时飞出的**大块木碎片**（FX01-33）——由 `SecretDoor3D._break_open()` 借出。
##
## ⚠ 与 FX01-01~05 的区别：它是**事件型**（一整扇门板被轰开），不是高频件
##   ⇒ 带一盏 0.55s 的短灯（塔内夜间光下没灯就看不见碎块），成本可以接受。
## 抛出物同族：**不绑 follow**、无碰撞体、程序化落地（见 `VfxBoardDebris3D`）。
const FX01_BOARD_DEBRIS := "VFX-BOARD-DEBRIS-3D"

## 瞬移「消失 / 出现」配对特效（FX01-34 / FX01-35）。由 `Enemy3D` 的
## `_play_teleport_fx()` 在 blink 位移的两端（原点 + 落点）与 `_vanish()` 时借出。
##
## 两件**必须成对**理解：它们回答的是同一个问题「它刚才去了哪」，
## 只有「消失」会让玩家以为怪跑掉了，只有「出现」会让人以为怪是凭空刷的。
const FX01_TELEPORT_OUT := "VFX-TELEPORT-OUT-3D"
const FX01_TELEPORT_IN := "VFX-TELEPORT-IN-3D"

const FX01_AXE_CHARGE := "VFX-MELEE-AXE-CHARGE-3D"
const FX01_AXE_CLEAVE := "VFX-MELEE-AXE-CLEAVE-3D"
const FX01_AXE_IMPACT := "VFX-MELEE-AXE-IMPACT-3D"
const FX01_BLADE_SWEEP := "VFX-MELEE-BLADE-SWEEP-3D"
const FX01_BLADE_WHIRLWIND := "VFX-MELEE-BLADE-WHIRLWIND-3D"

const _REGISTRY := {
	FX01_AXE_CHARGE: preload("res://assets/art/vfx/combat_3d/vfx_axe_charge_root_top3d.tscn"),
	FX01_AXE_CLEAVE: preload("res://assets/art/vfx/combat_3d/vfx_axe_cleave_root_top3d.tscn"),
	FX01_AXE_IMPACT: preload("res://assets/art/vfx/combat_3d/vfx_axe_impact_root_top3d.tscn"),
	FX01_BLADE_SWEEP: preload("res://assets/art/vfx/combat_3d/vfx_blade_sweep_root_top3d.tscn"),
	FX01_BLADE_WHIRLWIND: preload("res://assets/art/vfx/combat_3d/vfx_blade_whirlwind_root_top3d.tscn"),

	FX01_FATE_FIRE: preload("res://assets/art/vfx/combat_3d/vfx_fate_fire_root_top3d.tscn"),
	FX01_FATE_FROST: preload("res://assets/art/vfx/combat_3d/vfx_fate_frost_root_top3d.tscn"),
	FX01_FATE_POISON: preload("res://assets/art/vfx/combat_3d/vfx_fate_poison_root_top3d.tscn"),
	FX01_FATE_LIGHTNING: preload("res://assets/art/vfx/combat_3d/vfx_fate_lightning_root_top3d.tscn"),
	FX01_FATE_ROCK_SHATTER: preload("res://assets/art/vfx/combat_3d/vfx_fate_rock_shatter_root_top3d.tscn"),
	FX01_BOARD_DEBRIS: preload("res://assets/art/vfx/combat_3d/vfx_board_debris_root_top3d.tscn"),
	FX01_TELEPORT_OUT: preload("res://assets/art/vfx/combat_3d/vfx_teleport_out_root_top3d.tscn"),
	FX01_TELEPORT_IN: preload("res://assets/art/vfx/combat_3d/vfx_teleport_in_root_top3d.tscn"),
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

## 预热件的尺寸（世界米）。**亚像素**：1.5 m 处约 0.8 mm，任何分辨率下都不足一个像素，
## 所以哪怕遮挡没跟上也出不了可见的闪点。见 `prewarm()`。
const PREWARM_SIZE := 0.0008
## 预热件摆在相机前多远。必须**在视锥内** —— 视锥外会被裁掉，裁掉就不绘制，
## 不绘制就不编译管线，预热等于没做（这是本函数唯一容易写错的地方）。
const PREWARM_DISTANCE := 1.5

var _active: Dictionary = {}    # asset_id -> Array[VfxEffectBase3D]
var _inactive: Dictionary = {}  # asset_id -> Array[VfxEffectBase3D]
var _spawn_parent: Node3D
## 待预热队列。每帧只取一个 —— 单个特效的首次绘制要 20~65 ms，
## 一次全做等于在加载末尾塞一个 120 ms 的硬冻结。
var _prewarm_queue: Array[StringName] = []

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
	set_process(false)

## 把一批特效「提前造一次」，把首次装配的编译代价挪到加载期。
##
## ## 为什么必须有
##
## 2026-10-31 实测（`tools/_vfx_cold_start_probe`，真渲染 / `--disable-vsync`）：
##
## | 特效 | 第一次借出 | 第二次 |
## |---|---:|---:|
## | VFX-IMPACT-3D | **64.97 ms** | 0.39 ms |
## | VFX-MELEE-IMPACT-3D | **32.87 ms** | — |
## | VFX-MELEE-SLASH-3D | **20.75 ms** | — |
## | 其余 5 种 | 0.3~1.3 ms | — |
##
## 8 种合计 **121.8 ms**，同批第二次只要 2.8 ms ⇒ 差价是**首次装配时的着色器/管线准备**。
## 它每局只发生一次，所以"平均帧时"永远看不见它；玩家感受是「进关卡后第一枪顿一下」。
##
## ## 代价到底落在哪一步（拆过，别猜）
##
## ```
## instantiate 0.04ms / add_child 0.01ms / activate 64.36ms / 首帧渲染 14.68ms
## 把第一次摆在相机**背后**（必然被视锥剔除、根本不绘制）⇒ activate 仍 64.65ms，第二次 0.37ms
## 单独 new 一个同款 StandardMaterial3D ⇒ 0.03ms
## ```
##
## ⇒ 贵的是「**节点带材质实例化进渲染场景**」这一下，不是 `new` 材质、也不是"画"。
## 所以预热只需要让它进一次场景树；`draw` 不是必要条件。
##
## 仍摆在镜头前（有相机时）是**保险**：万一将来某个驱动/版本把编译推迟到首绘，
## 这里已经覆盖到。没有相机就退回池自身位置，照样能省 —— 不因为"没相机"就什么都不做。
##
## ## 为什么尺寸是 0.0008
##
## 亚像素（1.5 m 处约 0.8 mm）。预热发生在加载过场背后，玩家看不到；万一遮挡没跟上，
## 这个尺寸也出不了可见的闪点。**它是"以防万一"，不是"必需"**。
##
## ## 队列而不是一把梭
##
## 单个首次装配 20~65 ms，8 个一次做完就是一个 120 ms 的硬冻结。
## 每帧只做一个，把同样的总代价摊到 8 帧，加载末尾不会突然卡死。
func prewarm(asset_ids: Array) -> void:
	for value in asset_ids:
		var asset_id := StringName(value)
		if not _REGISTRY.has(asset_id) or _prewarm_queue.has(asset_id):
			continue
		_prewarm_queue.append(asset_id)
	if not _prewarm_queue.is_empty():
		set_process(true)


func _process(_delta: float) -> void:
	if _prewarm_queue.is_empty():
		set_process(false)
		return
	var asset_id: StringName = _prewarm_queue.pop_front()
	# 有相机就摆在它前方（覆盖"编译推迟到首绘"的可能）；没有就用池自身位置。
	var origin := global_position
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		origin = camera.global_position - camera.global_basis.z * PREWARM_DISTANCE
	acquire(asset_id, origin, Color.WHITE, PREWARM_SIZE)
	if _prewarm_queue.is_empty():
		set_process(false)


## 还有没有排队中的预热件。给加载页判断"能不能开圈"用。
func has_pending_prewarm() -> bool:
	return not _prewarm_queue.is_empty()


## 进关卡后第一批战斗反馈会用到的那批。顺序按"最先被撞上"的概率排。
##
## 只暖这 11 个，不暖全表：全表里另一半是低频事件件（暗门碎片、命运元素、收音机音符），
## 把它们的首次装配也塞进加载期只会拉长过场，而它们第一次出现时玩家本来就在看别的地方。
##
## 三个死亡件必须算进来：第一次打死怪就在第一次命中后几秒内，
## 实测 `ZOMBIE-GOO-DEATH` 33.1 / `EXPLOSION` 31.9 / `DEATH-BLAST` 33.9 ms ——
## 不预热的话「第一杀」会连顿三下（复刻怪的死亡就是换这三个里的一个）。
const COMBAT_PREWARM := [
	FX01_IMPACT,
	FX01_METAL_SPARK_HIT,
	FX01_GOO_HIT,
	FX02_DAMAGE_NUMBER,
	FX01_MUZZLE_FLASH,
	FX01_SHELL_CASING,
	FX01_MELEE_SLASH,
	FX01_MELEE_IMPACT,
	FX01_ZOMBIE_GOO_DEATH,
	FX01_EXPLOSION,
	FX01_DEATH_BLAST,
]

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
