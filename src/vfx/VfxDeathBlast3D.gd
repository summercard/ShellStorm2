class_name VfxDeathBlast3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-17 / VFX-DEATH-BLAST-3D 胖子僵尸死亡自爆特效（远征01 关卡级）
##
## 用途：`Enemy3D._detonate_death_explosion()` 在胖子僵尸被打死瞬间生成的一次性爆炸视觉。
## 与 FX01-03 `VFX-EXPLOSION-3D` 的分工（**刻意各做一份，不复用**）：
##   - FX01-03 是「通用 / 弹药类」小爆点：lifetime 0.46s、核心约 0.42m、无灯；
##   - 本件是「大体位怪」的死亡自爆：lifetime 0.62s、核心约 1.3m、冲击环外缘≈规格半径、
##     放射星芒 + 飞散碎屑 + 一盏 `BlastLight` 提供瞬时照明。
##     （业主 2026-10-14：「胖子僵尸被打死后自爆没有特效，需要增加一个」。）
##
## 视觉：SphereMesh 亮芯 + 2 层冲击环（错峰扩散）+ 9 道放射星芒 + 8 块飞散碎屑 + BlastLight。
## 行为：**全向对称**——刻意不消费 `context.forward` / `context.normal`（爆炸没有朝向）；
##       调用方按 `size ≈ 规格半径 × 0.6` 传尺寸，冲击环外缘即落在规格半径附近
##       （5.0m 半径 ⇒ size 3.0 ⇒ 内环 0.72 × 3.0 × 2.20 ≈ 4.75m、外环 × 2.45 ≈ 5.29m）。
## 纯视觉：Prefab 内无任何碰撞体（验收有断言盯着）。
## 资源：mesh / material 首次生成后复用；所有子节点 cast_shadow OFF；
##       所有可变状态（scale / position / rotation / material alpha / 灯能量）在每次
##       `_on_tick` 里由 `elapsed` 重算，故复借时天然复位，不残留上一轮的形态。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

const _ASSET_ID := "VFX-DEATH-BLAST-3D"
const _ASSET_VERSION := "v001"

## 寿命与包络时间点（秒）
const BLAST_LIFETIME := 0.62
const RING1_END_SEC := 0.34
const RING2_START_SEC := 0.08
const RING2_END_SEC := 0.42

## 亮芯：以 ToonVfx.core_mesh()（半径 0.18m）为基准的倍率
const CORE_SCALE_START := 0.55
const CORE_SCALE_END := 2.40

## 冲击环：以 ToonVfx.ring_mesh()（outer_radius = 0.72m）为基准的倍率
const RING1_SCALE_START := 0.30
const RING1_SCALE_END := 2.20
const RING2_SCALE_START := 0.20
const RING2_SCALE_END := 2.45

## 放射星芒 / 飞散碎屑
const SPIKE_COUNT := 9
const DEBRIS_COUNT := 8
const SPIKE_LENGTH_BASE := 0.55
const DEBRIS_DISTANCE_START := 0.35
const DEBRIS_DISTANCE_END := 2.15
const DEBRIS_HOP_HEIGHT := 0.85
const DEBRIS_SPIN_SPEED := 7.5

## 灯光真源：范围随 size 线性（`omni_range = LIGHT_RANGE_BASE × effect_size`）、
## 能量按包络衰减且**不随 size 缩放**、寿命末端必须归零（否则池化复借会长明）。
const LIGHT_RANGE_BASE := 6.0
const LIGHT_ENERGY := 9.0
const LIGHT_COLOR := Color(1.0, 0.72, 0.34)

var _core: MeshInstance3D
var _ring1: MeshInstance3D
var _ring2: MeshInstance3D
var _spikes: Array[MeshInstance3D] = []
var _debris: Array[MeshInstance3D] = []

var _mat_core: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _mat_spike: StandardMaterial3D
var _mat_debris: StandardMaterial3D

var _blast_light: OmniLight3D

## 逐项确定性常量（构建期算一次；tick 只按 elapsed 插值，避免随机与残留）
var _spike_dirs: Array[Vector3] = []
var _spike_len_ratio: Array[float] = []
var _spike_phase: Array[float] = []
var _debris_dirs: Array[Vector3] = []
var _debris_base_euler: Array[Vector3] = []
var _debris_spin_axis: Array[Vector3] = []


func _on_activate(_world_pos: Vector3, color: Color, _size: float, _context: Dictionary) -> void:
	lifetime = BLAST_LIFETIME
	var ammo := color
	if ammo.a < 0.001:
		ammo = Color(1.0, 0.52, 0.18, 1.0)
	if _core == null:
		_build()
	_reset_state(ammo)
	_on_tick(0.0, lifetime)


func _build() -> void:
	# 亮芯：热白偏弹药色
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = ToonVfx.core_mesh()
	_mat_core = ToonVfx.toon_material(Color(1.0, 0.95, 0.82, 1.0), 0.9)
	_core.material_override = _mat_core
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	# 冲击环：两层错峰扩散（ring_mesh 默认沿 Y 轴 ⇒ 环面躺在 XZ，读作地面冲击波）
	_mat_ring = ToonVfx.toon_material(Color(1.0, 0.62, 0.24, 1.0), 0.5)
	_ring1 = MeshInstance3D.new()
	_ring1.name = "ShockwaveA"
	_ring1.mesh = ToonVfx.ring_mesh()
	_ring1.material_override = _mat_ring
	_ring1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring1)
	_ring2 = MeshInstance3D.new()
	_ring2.name = "ShockwaveB"
	_ring2.mesh = ToonVfx.ring_mesh()
	_ring2.material_override = _mat_ring
	_ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring2)

	# 放射星芒：长轴沿本地 Y（spike_mesh 契约）⇒ 用 Quaternion(UP, dir) 对齐水平放射方向
	_mat_spike = ToonVfx.toon_material(Color(1.0, 0.78, 0.34, 1.0), 0.6)
	for index in SPIKE_COUNT:
		var spike := MeshInstance3D.new()
		spike.name = "Spike%d" % index
		spike.mesh = ToonVfx.spike_mesh()
		var direction := _radial_direction(index, SPIKE_COUNT)
		_spike_dirs.append(direction)
		# 相位让星芒长短错峰（0.6~1.0），不是一圈等长的齿轮
		_spike_len_ratio.append(0.60 + 0.40 * float((index * 5) % SPIKE_COUNT) / float(SPIKE_COUNT))
		_spike_phase.append(float(index) / float(SPIKE_COUNT))
		spike.quaternion = Quaternion(Vector3.UP, direction)
		spike.material_override = _mat_spike
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spike)
		_spikes.append(spike)

	# 飞散碎屑：外抛 + 小幅上抛后落下，带自旋
	_mat_debris = ToonVfx.toon_material(Color(0.62, 0.58, 0.52, 1.0))
	for index in DEBRIS_COUNT:
		var chunk := MeshInstance3D.new()
		chunk.name = "Debris%d" % index
		chunk.mesh = ToonVfx.debris_mesh()
		var direction := _radial_direction(index, DEBRIS_COUNT)
		_debris_dirs.append(direction)
		_debris_base_euler.append(Vector3(
			float((index * 3) % DEBRIS_COUNT) * 0.31,
			float(index) * 0.47,
			float((index * 7) % DEBRIS_COUNT) * 0.23
		))
		_debris_spin_axis.append(Vector3(
			0.3 + float(index % 3) * 0.35,
			0.8 - float(index % 4) * 0.15,
			0.2 + float(index % 5) * 0.16
		).normalized())
		chunk.material_override = _mat_debris
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(chunk)
		_debris.append(chunk)

	# 灯光：无阴影、范围按 size 缩放、能量按包络衰减
	_blast_light = OmniLight3D.new()
	_blast_light.name = "BlastLight"
	_blast_light.shadow_enabled = false
	_blast_light.light_color = LIGHT_COLOR
	_blast_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	_blast_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	add_child(_blast_light)


## 水平放射方向（等角分布 + 交替俯仰，避免全在同一平面显得单薄）
func _radial_direction(index: int, count: int) -> Vector3:
	var angle := float(index) / float(count) * TAU
	var pitch := -0.22 + 0.44 * float(index % 3) / 2.0
	return Vector3(cos(angle) * cos(pitch), sin(pitch), sin(angle) * cos(pitch)).normalized()


func _reset_state(ammo: Color) -> void:
	# 亮芯保持热白偏色，环/星芒/碎屑吃弹药色（每只怪的爆色自洽）
	_mat_core.albedo_color = Color(1.0, 0.95, 0.82, 1.0).lerp(ammo, 0.25)
	_mat_ring.albedo_color = ammo
	_mat_spike.albedo_color = Color(1.0, 0.78, 0.34, 1.0).lerp(ammo, 0.45)
	_mat_debris.albedo_color = Color(0.62, 0.58, 0.52, 1.0)
	_mat_core.albedo_color.a = 1.0
	_mat_ring.albedo_color.a = 1.0
	_mat_spike.albedo_color.a = 1.0
	_mat_debris.albedo_color.a = 1.0
	# 所有子节点形态由 `_on_tick(0.0, lifetime)` 重算，这里只兜底复位灯的范围/位置
	_blast_light.position = Vector3(0.0, 0.30, 0.0)
	_blast_light.omni_range = LIGHT_RANGE_BASE * effect_size
	_blast_light.light_energy = LIGHT_ENERGY


func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clampf(elapsed / total, 0.0, 1.0)
	var size: float = effect_size

	# 亮芯：快速膨胀（ease-out）+ 淡出
	var core_grow: float = 1.0 - pow(1.0 - t, 2.2)
	_core.scale = Vector3.ONE * size * (CORE_SCALE_START + (CORE_SCALE_END - CORE_SCALE_START) * core_grow)
	_mat_core.albedo_color.a = pow(1.0 - t, 0.85)

	# 冲击环 A / B：错峰扩散（外缘 ≈ 0.72 × scale，峰值对齐规格半径）
	var t1: float = clampf(elapsed / RING1_END_SEC, 0.0, 1.0)
	var t2: float = clampf((elapsed - RING2_START_SEC) / (RING2_END_SEC - RING2_START_SEC), 0.0, 1.0)
	var ring1_scale: float = size * (RING1_SCALE_START + (RING1_SCALE_END - RING1_SCALE_START) * t1)
	var ring2_scale: float = size * (RING2_SCALE_START + (RING2_SCALE_END - RING2_SCALE_START) * t2)
	_ring1.scale = Vector3.ONE * ring1_scale
	_ring2.scale = Vector3.ONE * ring2_scale
	# 两层共用一份材质 ⇒ alpha 取两者中更亮的那条，避免互相覆盖掉
	_mat_ring.albedo_color.a = maxf(0.92 * pow(1.0 - t1, 1.2), 0.72 * pow(1.0 - t2, 1.2))

	# 放射星芒：从中心向外顶出 + 缩短 + 淡出
	for index in _spikes.size():
		var spike := _spikes[index]
		var direction := _spike_dirs[index]
		var ratio := _spike_len_ratio[index]
		# 相位错峰：每条星芒的伸展进度略有超前/滞后
		var local_t: float = clampf((elapsed + _spike_phase[index] * 0.06) / maxf(0.001, RING1_END_SEC), 0.0, 1.0)
		var reach: float = size * (0.25 + 0.75 * (1.0 - pow(1.0 - local_t, 2.0)))
		spike.position = direction * (reach * (0.5 + ratio * 0.5))
		var girth: float = size * 0.85 * (1.0 - 0.45 * t)
		var length: float = size * SPIKE_LENGTH_BASE * ratio * (1.0 - 0.55 * t)
		spike.scale = Vector3(girth, length, girth)
	_mat_spike.albedo_color.a = pow(1.0 - t, 1.1)

	# 飞散碎屑：外抛 + 上抛弧线 + 自旋
	var debris_out: float = DEBRIS_DISTANCE_START + (DEBRIS_DISTANCE_END - DEBRIS_DISTANCE_START) * (1.0 - pow(1.0 - t, 1.8))
	for index in _debris.size():
		var chunk := _debris[index]
		var direction := _debris_dirs[index]
		var hop: float = DEBRIS_HOP_HEIGHT * sin(t * PI)
		chunk.position = direction * (debris_out * size) + Vector3.UP * (hop * size * 0.35)
		chunk.scale = Vector3.ONE * size * (0.95 - 0.42 * t)
		chunk.rotation = (
			_debris_base_euler[index]
			+ _debris_spin_axis[index] * (DEBRIS_SPIN_SPEED * elapsed)
		)
	_mat_debris.albedo_color.a = clampf(1.0 - t * 1.15, 0.0, 1.0)

	# 灯光：出生峰值 → 半程仍 > 0 → 寿命末端归零
	_blast_light.light_energy = LIGHT_ENERGY * pow(1.0 - t, 1.35)


func _on_lifetime_expired() -> void:
	if is_instance_valid(_blast_light):
		_blast_light.light_energy = 0.0


## 供验收 / 巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	var light_valid := is_instance_valid(_blast_light)
	var spread := Vector3.ZERO
	for direction in _spike_dirs:
		spread += direction
	return {
		"asset_id": get_meta("asset_id", _ASSET_ID),
		"asset_version": get_meta("asset_version", _ASSET_VERSION),
		"node_count": get_child_count(),
		"lifetime": lifetime,
		"effect_size": effect_size,
		"has_blast_light": light_valid,
		"light_name": _blast_light.name if light_valid else "",
		"light_energy": _blast_light.light_energy if light_valid else 0.0,
		"light_range": _blast_light.omni_range if light_valid else 0.0,
		"light_shadows": _blast_light.shadow_enabled if light_valid else false,
		"spike_count": _spikes.size(),
		"debris_count": _debris.size(),
		"core_scale_x": _core.scale.x if is_instance_valid(_core) else 0.0,
		# 环外缘世界半径（实测，取两层里更大的那层）
		"ring_outer_world_radius": maxf(
			ToonVfx.ring_mesh().outer_radius * _ring1.scale.x if is_instance_valid(_ring1) else 0.0,
			ToonVfx.ring_mesh().outer_radius * _ring2.scale.x if is_instance_valid(_ring2) else 0.0
		),
		# 放射方向和的模长：全向对称应 ≈ 0（最大 9，用于「真的散开」断言）
		"spread_sum_length": spread.length(),
	}
