class_name VfxHologramEntry3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## 99F 基地出发后的远征入场仪式全息成形。
##
## 两个独立 AssetID 共用本脚本：
## - scan：从脚底向上扫描，像投影仪逐层写入角色轮廓；
## - materialize：环场碎片向内收束，角色在最后一拍凝实。
## 只负责表现，不负责输入、相机、玩家可见性或关卡状态。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

const ASSET_SCAN := "VFX-HOLOGRAM-ENTRY-SCAN-3D"
const ASSET_MATERIALIZE := "VFX-HOLOGRAM-ENTRY-MATERIALIZE-3D"
const MODE_SCAN := "scan"
const MODE_MATERIALIZE := "materialize"

@export_enum("scan", "materialize") var mode: String = MODE_SCAN

var _ring_low: MeshInstance3D
var _ring_high: MeshInstance3D
var _scan_bar: MeshInstance3D
var _core: MeshInstance3D
var _shards: Array[MeshInstance3D] = []
var _ring_material: StandardMaterial3D
var _bar_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _shard_material: StandardMaterial3D
var _shard_angles: Array[float] = []
var _height_min := 0.0
var _height_max := 1.5

func _on_activate(_world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	lifetime = float(context.get("duration", 1.55 if mode == MODE_SCAN else 1.75))
	_height_min = float(context.get("height_min", 0.0))
	_height_max = float(context.get("height_max", 1.5))
	if color.a < 0.001:
		color = Color(0.20, 0.86, 1.0, 1.0)
	if _ring_low == null:
		_build()
	_apply_color(color)
	global_rotation = Vector3.ZERO
	scale = Vector3.ONE * size
	_on_tick(0.0, lifetime)

func _build() -> void:
	_ring_low = MeshInstance3D.new()
	_ring_low.name = "EntryRingLow"
	_ring_low.mesh = ToonVfx.ring_mesh()
	_ring_low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring_low)

	_ring_high = MeshInstance3D.new()
	_ring_high.name = "EntryRingHigh"
	_ring_high.mesh = ToonVfx.ring_mesh()
	_ring_high.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring_high)

	_ring_material = ToonVfx.toon_material(Color(0.20, 0.86, 1.0, 1.0), 2.4)
	_ring_low.material_override = _ring_material
	_ring_high.material_override = _ring_material

	_scan_bar = MeshInstance3D.new()
	_scan_bar.name = "EntryScanBar"
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.35, 0.035, 0.055)
	_scan_bar.mesh = bar_mesh
	_scan_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_scan_bar)
	_bar_material = ToonVfx.toon_material(Color(0.72, 0.98, 1.0, 1.0), 3.0)
	_scan_bar.material_override = _bar_material

	_core = MeshInstance3D.new()
	_core.name = "EntryCore"
	_core.mesh = ToonVfx.core_mesh()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_core_material = ToonVfx.toon_material(Color(0.88, 1.0, 1.0, 1.0), 3.4)
	_core.material_override = _core_material

	_shard_material = ToonVfx.toon_material(Color(0.34, 0.92, 1.0, 1.0), 2.1)
	for i in 12:
		var shard := MeshInstance3D.new()
		shard.name = "EntryShard%d" % i
		shard.mesh = ToonVfx.streak_mesh()
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.material_override = _shard_material
		add_child(shard)
		_shards.append(shard)
		_shard_angles.append(float(i) / 12.0 * TAU)

func _apply_color(color: Color) -> void:
	_ring_material.albedo_color = color
	_ring_material.emission = color
	_bar_material.albedo_color = color.lightened(0.38)
	_bar_material.emission = color.lightened(0.38)
	_core_material.albedo_color = color.lightened(0.72)
	_core_material.emission = color.lightened(0.72)
	_shard_material.albedo_color = color.lightened(0.18)
	_shard_material.emission = color.lightened(0.18)

func _on_tick(elapsed: float, total: float) -> void:
	var t := clampf(elapsed / maxf(total, 0.001), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var alpha := 1.0
	if mode == MODE_SCAN:
		# 根节点已经按 effect_size 缩放，子节点只做相对动画，不再重复乘 size。
		_scan_bar.visible = true
		_scan_bar.position = Vector3(0.0, lerpf(_height_min, _height_max, t), 0.0)
		_scan_bar.scale = Vector3.ONE
		_ring_low.position = Vector3(0.0, 0.04, 0.0)
		_ring_high.position = Vector3(0.0, 1.48, 0.0)
		_ring_low.scale = Vector3.ONE * (0.44 + eased * 0.38)
		_ring_high.scale = Vector3.ONE * (0.18 + eased * 0.62)
		_core.position = Vector3(0.0, 0.82, 0.0)
		_core.scale = Vector3.ONE * (0.12 + sin(t * PI) * 0.32)
		alpha = clampf(1.0 - maxf(0.0, t - 0.78) / 0.22, 0.0, 1.0)
		for shard in _shards:
			shard.visible = false
	else:
		# 凝实阶段：碎片先远后近，末拍收束成一圈“成形”的边界。
		_scan_bar.visible = false
		var converge := clampf((t - 0.10) / 0.78, 0.0, 1.0)
		var converge_eased := 1.0 - pow(1.0 - converge, 2.0)
		_ring_low.position = Vector3(0.0, 0.04, 0.0)
		_ring_high.position = Vector3(0.0, 1.48, 0.0)
		_ring_low.scale = Vector3.ONE * lerpf(1.32, 0.78, eased)
		_ring_high.scale = Vector3.ONE * lerpf(0.26, 0.68, eased)
		_core.position = Vector3(0.0, 0.82, 0.0)
		_core.scale = Vector3.ONE * (0.12 + sin(clampf(t / 0.76, 0.0, 1.0) * PI) * 0.34)
		for i in _shards.size():
			var angle := _shard_angles[i]
			var radius := lerpf(1.35, 0.24, converge_eased)
			var lift := lerpf(0.20, 0.72 + float(i % 3) * 0.12, converge_eased)
			_shards[i].visible = t < 0.92
			_shards[i].position = Vector3(cos(angle) * radius, lift, sin(angle) * radius)
			_shards[i].rotation = Vector3(-PI / 2.0, angle, 0.0)
			_shards[i].scale = Vector3(0.38, lerpf(0.12, 0.28, converge_eased), 0.38)
		alpha = clampf(1.0 - maxf(0.0, t - 0.82) / 0.18, 0.0, 1.0)

	_ring_material.albedo_color.a = alpha
	_bar_material.albedo_color.a = alpha
	_core_material.albedo_color.a = alpha
	_shard_material.albedo_color.a = alpha

func get_presentation_snapshot() -> Dictionary:
	return {
		"asset_id": get_meta("asset_id", ASSET_SCAN if mode == MODE_SCAN else ASSET_MATERIALIZE),
		"asset_version": get_meta("asset_version", "v001"),
		"mode": mode,
		"node_count": get_child_count(),
		"shard_count": _shards.size(),
		"has_collision": find_children("*", "CollisionObject3D", true, false).size() > 0,
		"has_light": find_children("*", "Light3D", true, false).size() > 0,
		"lifetime": lifetime,
	}
