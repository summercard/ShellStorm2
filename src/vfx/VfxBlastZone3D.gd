class_name VfxBlastZone3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-18 / VFX-BLAST-ZONE-3D 自爆地面残留伤害场（视觉层，远征01 关卡级）
##
## 用途：胖子僵尸死亡自爆后**留在地上的持续伤害范围**（业主 2026-10-14：
## 「在地上留一个持续伤害的范围效果，持续3秒」）。默认 `lifetime = 3.0s`，
## 由调用方 `context.zone_seconds` 决定，必须与玩法节点 `DeathBlastZone3D` 的持续时长一致。
##
## ⚠ 分工（与 14.6 §1「Prefab 是特效的唯一出口」一致）：
##   本 Prefab **只画视觉**，不含任何碰撞体、不结算任何伤害。
##   伤害由玩法节点 `src/enemy3d/DeathBlastZone3D.gd` 按周期结算；
##   本件只负责「地上有一片还在烧、还在脉冲的伤害区」这个读法。
##
## 地面朝向契约：整个视觉**平铺在 XZ 平面**（TorusMesh 的环轴是 Y ⇒ 环面天然躺在 XZ）。
##   调用方在**地面高度**（怪物的脚底 y）activate，且**不做任何旋转**；
##   验收有「平铺」断言 + 反向对照（故意倾斜 90° 必须变红）。
##
## 视觉：半透明场底面（CylinderMesh 薄片）+ 外缘定环 + 3 层错峰脉冲环 + 6 枚上升余烬 + ZoneLight。
## 资源：mesh / material 首次生成后复用；所有子节点 cast_shadow OFF；
##       所有可变状态由 `_on_tick` 按 `elapsed` 重算，复借天然复位。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

const _ASSET_ID := "VFX-BLAST-ZONE-3D"
const _ASSET_VERSION := "v001"

## 默认持续时长（秒）。业主口径 3 秒；调用方可用 `context.zone_seconds` 覆盖。
const DEFAULT_ZONE_SECONDS := 3.0

## 淡入 / 淡出（秒）—— 不让场地突然出现 / 突然消失（观感上更顺）
const FADE_IN_SEC := 0.16
const FADE_OUT_SEC := 0.42

## 脉冲环：3 层错峰，周期 PULSE_PERIOD；每层从 RING_PULSE_MIN 扩到 1.0
const PULSE_RING_COUNT := 3
const PULSE_PERIOD_SEC := 0.90
const RING_PULSE_MIN := 0.45

## 上升余烬
const EMBER_COUNT := 6
const EMBER_PERIOD_SEC := 1.50
const EMBER_RISE_RATIO := 0.55
const EMBER_ALPHA := 0.85

## 灯光真源：范围随 size 线性、能量按包络 + 慢脉冲、寿命末端必须归零
const LIGHT_RANGE_BASE := 4.5
const LIGHT_ENERGY := 3.4
const LIGHT_PULSE_HZ := 7.0
const LIGHT_COLOR := Color(1.0, 0.58, 0.22)

var _field: MeshInstance3D
var _edge: MeshInstance3D
var _pulses: Array[MeshInstance3D] = []
var _embers: Array[MeshInstance3D] = []

var _mat_field: StandardMaterial3D
var _mat_edge: StandardMaterial3D
var _mat_pulse: StandardMaterial3D
var _mat_ember: StandardMaterial3D

var _zone_light: OmniLight3D

var _ember_dirs: Array[Vector3] = []
var _ember_radius_ratio: Array[float] = []


func _on_activate(_world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	lifetime = maxf(0.2, float(context.get("zone_seconds", DEFAULT_ZONE_SECONDS)))
	var ammo := color
	if ammo.a < 0.001:
		ammo = Color(1.0, 0.52, 0.18, 1.0)
	if _field == null:
		_build()
	_reset_state(ammo, size)
	_on_tick(0.0, lifetime)


func _build() -> void:
	# 场底面：薄圆片（半径基准 1.0m，按 size 摊到规格半径）
	_field = MeshInstance3D.new()
	_field.name = "Field"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	_field.mesh = disc
	_mat_field = ToonVfx.toon_material(Color(1.0, 0.45, 0.16, 1.0), 0.55)
	_field.material_override = _mat_field
	_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_field.position.y = 0.02
	add_child(_field)

	# 外缘定环：把「范围边界」钉死，玩家能一眼读出杀伤半径
	_edge = MeshInstance3D.new()
	_edge.name = "Edge"
	var edge_mesh := TorusMesh.new()
	edge_mesh.inner_radius = 0.960
	edge_mesh.outer_radius = 1.0
	edge_mesh.rings = 40
	edge_mesh.ring_segments = 6
	_edge.mesh = edge_mesh
	_mat_edge = ToonVfx.toon_material(Color(1.0, 0.68, 0.28, 1.0), 0.85)
	_edge.material_override = _mat_edge
	_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge.position.y = 0.05
	add_child(_edge)

	# 脉冲环：3 层错峰向外扫
	_mat_pulse = ToonVfx.toon_material(Color(1.0, 0.72, 0.32, 1.0), 0.95)
	for index in PULSE_RING_COUNT:
		var ring := MeshInstance3D.new()
		ring.name = "Pulse%d" % index
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.93
		ring_mesh.outer_radius = 0.975
		ring_mesh.rings = 32
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		ring.material_override = _mat_pulse
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.07
		add_child(ring)
		_pulses.append(ring)

	# 上升余烬：确定性角分布 + 三段半径，读作「场上还在冒」
	_mat_ember = ToonVfx.toon_material(Color(1.0, 0.86, 0.46, 1.0), 1.0)
	for index in EMBER_COUNT:
		var ember := MeshInstance3D.new()
		ember.name = "Ember%d" % index
		ember.mesh = ToonVfx.debris_mesh()
		var angle := float(index) / float(EMBER_COUNT) * TAU + 0.35
		_ember_dirs.append(Vector3(cos(angle), 0.0, sin(angle)))
		_ember_radius_ratio.append(0.22 + 0.52 * float(index % 3) / 2.0)
		ember.material_override = _mat_ember
		ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ember)
		_embers.append(ember)

	# 灯光：贴地一盏，给场地一点呼吸感；无阴影
	_zone_light = OmniLight3D.new()
	_zone_light.name = "ZoneLight"
	_zone_light.shadow_enabled = false
	_zone_light.light_color = LIGHT_COLOR
	_zone_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	_zone_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	_zone_light.position = Vector3(0.0, 0.40, 0.0)
	add_child(_zone_light)


func _reset_state(ammo: Color, size: float) -> void:
	_mat_field.albedo_color = ammo
	_mat_field.albedo_color.a = 0.20
	_mat_edge.albedo_color = Color(1.0, 0.68, 0.28, 1.0).lerp(ammo, 0.5)
	_mat_pulse.albedo_color = Color(1.0, 0.72, 0.32, 1.0).lerp(ammo, 0.4)
	_mat_ember.albedo_color = Color(1.0, 0.86, 0.46, 1.0)
	# 地面平面（薄片 / 定环 / 脉冲环）只摊 XZ，不缩放 Y —— 保持「平铺在地上」
	_field.scale = Vector3(size, 1.0, size)
	_edge.scale = Vector3.ONE * size
	for ring in _pulses:
		ring.scale = Vector3.ONE * size
	_zone_light.omni_range = LIGHT_RANGE_BASE * size
	_zone_light.position = Vector3(0.0, 0.40, 0.0)
	_zone_light.light_energy = LIGHT_ENERGY


func _on_tick(elapsed: float, total: float) -> void:
	var size: float = effect_size
	# 总包络：淡入 → 稳态 → 淡出（末尾必须真的收干净，否则池化/复用会留残影）
	var appear: float = clampf(elapsed / FADE_IN_SEC, 0.0, 1.0)
	var vanish: float = clampf((total - elapsed) / FADE_OUT_SEC, 0.0, 1.0)
	var env: float = minf(appear, vanish)

	# 场底面与外缘：整场恒定，只吃包络
	_mat_field.albedo_color.a = 0.20 * env
	_mat_edge.albedo_color.a = 0.90 * env

	# 脉冲环：3 层错峰，周期 PULSE_PERIOD_SEC
	var pulse_alpha := 0.0
	for index in _pulses.size():
		var ring := _pulses[index]
		var phase: float = fmod(elapsed / PULSE_PERIOD_SEC + float(index) / float(PULSE_RING_COUNT), 1.0)
		var grow: float = RING_PULSE_MIN + (1.0 - RING_PULSE_MIN) * phase
		ring.scale = Vector3.ONE * size * grow
		# 取最亮的那层写公共材质（三层共材质 ⇒ alpha 取最大值，避免互相覆盖）
		pulse_alpha = maxf(pulse_alpha, (1.0 - phase) * 0.85)
	_mat_pulse.albedo_color.a = pulse_alpha * env

	# 上升余烬
	var ember_alpha := 0.0
	for index in _embers.size():
		var ember := _embers[index]
		var phase: float = fmod(elapsed / EMBER_PERIOD_SEC + float(index) / float(EMBER_COUNT), 1.0)
		ember.position = (
			_ember_dirs[index] * (size * _ember_radius_ratio[index])
			+ Vector3.UP * (size * EMBER_RISE_RATIO * phase)
		)
		ember.scale = Vector3.ONE * size * 0.55 * (1.0 - phase * 0.7)
		ember.rotation.y = phase * TAU * 0.5 + float(index)
		ember_alpha = maxf(ember_alpha, (1.0 - phase) * 0.9)
	_mat_ember.albedo_color.a = ember_alpha * EMBER_ALPHA * env

	# 呼吸灯：包络 × 慢脉冲；末端归零
	var breathe: float = 0.72 + 0.28 * (0.5 + 0.5 * sin(elapsed * LIGHT_PULSE_HZ))
	_zone_light.light_energy = LIGHT_ENERGY * env * breathe


func _on_lifetime_expired() -> void:
	if is_instance_valid(_zone_light):
		_zone_light.light_energy = 0.0


## 供验收 / 巡检读取的呈现快照（不写入 res://）。
func get_presentation_snapshot() -> Dictionary:
	var light_valid := is_instance_valid(_zone_light)
	# 地面平面各件相对世界 UP 的对齐度（1.0 = 完全平铺；故意倾斜会掉下来）
	var plane_dot_min := 1.0
	for node in _ground_plane_nodes():
		plane_dot_min = minf(plane_dot_min, node.global_basis.y.normalized().dot(Vector3.UP))
	return {
		"asset_id": get_meta("asset_id", _ASSET_ID),
		"asset_version": get_meta("asset_version", _ASSET_VERSION),
		"node_count": get_child_count(),
		"lifetime": lifetime,
		"zone_radius": effect_size,
		"has_zone_light": light_valid,
		"light_name": _zone_light.name if light_valid else "",
		"light_energy": _zone_light.light_energy if light_valid else 0.0,
		"light_range": _zone_light.omni_range if light_valid else 0.0,
		"light_shadows": _zone_light.shadow_enabled if light_valid else false,
		"pulse_ring_count": _pulses.size(),
		"ember_count": _embers.size(),
		"field_scale_x": _field.scale.x if is_instance_valid(_field) else 0.0,
		"edge_scale_x": _edge.scale.x if is_instance_valid(_edge) else 0.0,
		"ground_plane_dot_min": plane_dot_min,
	}


## 属于「地面平面」的子节点（薄片 + 定环 + 脉冲环）——余烬是立体件，不参与平铺断言。
func _ground_plane_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	if is_instance_valid(_field):
		nodes.append(_field)
	if is_instance_valid(_edge):
		nodes.append(_edge)
	for ring in _pulses:
		nodes.append(ring)
	return nodes
