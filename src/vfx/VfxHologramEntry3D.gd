class_name VfxHologramEntry3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## 99F 入场：A 贴着角色扫出轮廓，B 方块从外向内凝实。
## 正式入场由叙事时钟驱动；独立播放/预热仍可自行计时退池。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")
const ASSET_SCAN := "VFX-HOLOGRAM-ENTRY-SCAN-3D"
const ASSET_MATERIALIZE := "VFX-HOLOGRAM-ENTRY-MATERIALIZE-3D"
const MODE_SCAN := "scan"
const MODE_MATERIALIZE := "materialize"
const SHARD_COUNT := 12
const SHARD_LIGHT := [0.36, 0.68, 0.96]
const SHARD_SIZE := [0.070, 0.094, 0.120]
const SHARD_WHITEN := [0.0, 0.20, 0.70]
const SHARD_ORDER := [1, 0, 2, 0, 1, 2, 1, 0, 2, 0, 1, 2]
const SCAN_PAD := 0.065
const SCAN_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 scan_color : source_color = vec4(0.2, 0.86, 1.0, 1.0);
uniform float opacity = 1.0;
void fragment() {
    float d = abs(UV.y * 2.0 - 1.0);
    float core = 1.0 - smoothstep(0.13, 0.35, d);
    float halo = 1.0 - smoothstep(0.22, 1.0, d);
    float ends = smoothstep(0.0, 0.10, min(UV.x, 1.0 - UV.x));
    ALBEDO = mix(scan_color.rgb * 1.25, vec3(0.88, 1.0, 1.0) * 1.8, core);
    ALPHA = opacity * ends * (0.21 * halo + 0.79 * core);
}
"""

@export_enum("scan", "materialize") var mode: String = MODE_SCAN

static var _scan_shader: Shader
var _ring_high: MeshInstance3D
var _scan_bar: MeshInstance3D
var _core: MeshInstance3D
var _shards: Array[MeshInstance3D] = []
var _ring_material: StandardMaterial3D
var _bar_material: ShaderMaterial
var _core_material: StandardMaterial3D
var _shard_materials: Array[StandardMaterial3D] = []


func _on_activate(_world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	lifetime = float(context.get("duration", 1.55 if mode == MODE_SCAN else 1.75))
	if color.a < 0.001:
		color = Color(0.20, 0.86, 1.0, 1.0)
	if _ring_high == null:
		_build()
	_apply_color(color)
	global_rotation = Vector3.ZERO
	scale = Vector3.ONE * size
	# Reset processing on every borrow, including replay as a standalone visual.
	set_process(not bool(context.get("timeline_driven", false)))
	_on_tick(0.0, lifetime)


func _build() -> void:
	_ring_material = ToonVfx.toon_material(Color.WHITE, 1.8)
	_ring_high = _make_part("EntryRingHigh", ToonVfx.ring_mesh(), _ring_material)
	_core_material = ToonVfx.toon_material(Color.WHITE, 2.5)
	_core = _make_part("EntryCore", ToonVfx.core_mesh(), _core_material)

	if mode == MODE_SCAN:
		if _scan_shader == null:
			_scan_shader = Shader.new()
			_scan_shader.code = SCAN_SHADER_CODE
		_bar_material = ShaderMaterial.new()
		_bar_material.shader = _scan_shader
		_bar_material.render_priority = 2
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_scan_bar = _make_part("EntryScanBar", quad, _bar_material)
	else:
		for energy in SHARD_LIGHT:
			var material := ToonVfx.toon_material(Color.WHITE, energy)
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			_shard_materials.append(material)
		for i in SHARD_COUNT:
			_shards.append(_make_part("EntryShard%d" % i, ToonVfx.unit_cube_mesh(), _shard_materials[SHARD_ORDER[i]]))


func _make_part(part_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.material_override = material
	add_child(part)
	return part


func _apply_color(color: Color) -> void:
	_ring_material.albedo_color = color
	_ring_material.emission = color
	_core_material.albedo_color = color.lightened(0.72)
	_core_material.emission = color.lightened(0.72)
	if _bar_material != null:
		_bar_material.set_shader_parameter("scan_color", color)
	for i in _shard_materials.size():
		var tint := color.lightened(SHARD_WHITEN[i])
		# Distinct base values as well as emission, so all three tiers survive tonemapping.
		_shard_materials[i].albedo_color = tint * minf(float(SHARD_LIGHT[i]), 1.0)
		_shard_materials[i].emission = tint


func _on_tick(elapsed: float, total: float) -> void:
	# Generic pool preview has no avatar, so supply small default bounds.
	var t := clampf(elapsed / maxf(total, 0.001), 0.0, 1.0)
	var unit := effect_size
	var bounds := AABB(global_position - Vector3(0.55, 0.0, 0.38) * unit, Vector3(1.10, 1.50, 0.76) * unit)
	apply_entry_frame(t, bounds, [bounds], lerpf(bounds.position.y, bounds.end.y, t))


## The host supplies the exact world-Y used by the avatar shader, not a second timer.
func apply_entry_frame(t: float, bounds: AABB, parts: Array[AABB], scan_y: float) -> void:
	if not _active:
		return
	var center := bounds.get_center()
	global_position = Vector3(center.x, bounds.position.y, center.z)
	var height := maxf(bounds.size.y, 0.001)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	_ring_high.position.y = height - 0.02
	_core.position.y = height * 0.55
	var alpha: float
	if mode == MODE_SCAN:
		_ring_high.scale = Vector3.ONE * (0.18 + eased * 0.62)
		_core.scale = Vector3.ONE * (0.12 + sin(t * PI) * 0.32)
		alpha = 1.0 - smoothstep(0.78, 1.0, t)
		_update_scan_bar(parts, center, scan_y, alpha)
	else:
		_ring_high.scale = Vector3.ONE * lerpf(0.26, 0.68, eased)
		_core.scale = Vector3.ONE * (0.12 + sin(clampf(t / 0.76, 0.0, 1.0) * PI) * 0.34)
		_update_shards(t, height)
		alpha = 1.0 - smoothstep(0.82, 1.0, t)
	_ring_material.albedo_color.a = alpha
	_core_material.albedo_color.a = alpha


func _update_scan_bar(parts: Array[AABB], center: Vector3, scan_y: float, alpha: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var near := INF
	var far := -INF
	var toward := Vector3(-right.z, 0.0, right.x)
	var depth_min := INF
	var depth_max := -INF
	for part in parts:
		if scan_y < part.position.y or scan_y > part.end.y:
			continue
		var offset := part.get_center() - center
		var half_width := 0.5 * (part.size.x * absf(right.x) + part.size.z * absf(right.z))
		var half_depth := 0.5 * (part.size.x * absf(toward.x) + part.size.z * absf(toward.z))
		near = minf(near, offset.dot(right) - half_width)
		far = maxf(far, offset.dot(right) + half_width)
		depth_min = minf(depth_min, offset.dot(toward) - half_depth)
		depth_max = maxf(depth_max, offset.dot(toward) + half_depth)
	_scan_bar.visible = near <= far and alpha > 0.001
	if not _scan_bar.visible:
		return
	var origin := Vector3(center.x, scan_y, center.z) + right * ((near + far) * 0.5) + toward * ((depth_min + depth_max) * 0.5)
	var forward := camera.global_basis.z if camera != null else Vector3.BACK
	var up := forward.cross(right).normalized()
	var width := far - near + 2.0 * SCAN_PAD
	# Keep the line horizontal in world space but face its glow toward the camera.
	_scan_bar.global_transform = Transform3D(Basis(right * width, up * 0.082, right.cross(up)), origin)
	_bar_material.set_shader_parameter("opacity", alpha)


func _update_shards(t: float, height: float) -> void:
	for i in _shards.size():
		var tier: int = SHARD_ORDER[i]
		var start := 0.06 + float(i % 4) * 0.036
		var converge := clampf((t - start) / (0.84 - start), 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - converge, 2.0)
		var angle := float(i) / SHARD_COUNT * TAU + eased * (0.22 + float(i % 3) * 0.045)
		var radius := lerpf(1.35 + float(i % 4) * 0.045, 0.20, eased)
		var lift := height * lerpf(0.14 + float(i % 5) * 0.10, 0.44 + float(i % 4) * 0.12, eased)
		var edge := float(SHARD_SIZE[tier]) * lerpf(1.0, 0.60, smoothstep(0.63, 0.90, t))
		var shard := _shards[i]
		shard.visible = t < 0.90
		shard.position = Vector3(cos(angle) * radius, lift, sin(angle) * radius)
		shard.rotation = Vector3(0.21 + 0.16 * i + eased * 0.85, angle, eased * 0.58)
		shard.scale = Vector3.ONE * edge
	var alpha := 1.0 - smoothstep(0.69, 0.90, t)
	for material in _shard_materials:
		material.albedo_color.a = alpha


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
