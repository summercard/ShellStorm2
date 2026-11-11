class_name ExpeditionEntryPresentation3D
extends RefCounted
## 仅负责角色几何与特效；输入和相机由适配器持有。

const VFX_SCAN := "VFX-HOLOGRAM-ENTRY-SCAN-3D"
const VFX_MATERIALIZE := "VFX-HOLOGRAM-ENTRY-MATERIALIZE-3D"
const HOLOGRAM_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_prepass_alpha;
uniform float reveal_progress = 0.0;
uniform float world_min = 0.0;
uniform float world_max = 1.0;
uniform float opacity = 1.0;
uniform vec4 hologram_color : source_color = vec4(0.20, 0.86, 1.0, 1.0);
varying float world_height;
void vertex() {
    world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
    float height = (world_height - world_min) / max(world_max - world_min, 0.001);
    float scan_height = mix(-0.07, 1.07, reveal_progress);
    float body = 1.0 - smoothstep(scan_height - 0.025, scan_height + 0.025, height);
    float scan = 1.0 - smoothstep(0.0, 0.045, abs(scan_height - height));
    float stripes = 0.82 + 0.18 * sin(world_height * 145.0);
    ALBEDO = hologram_color.rgb;
    EMISSION = hologram_color.rgb * (0.65 + scan * 1.8);
    ALPHA = opacity * body * (0.38 * stripes + scan * 0.5);
    if (ALPHA < 0.002) { discard; }
}
"""

static var _shader: Shader
var _player: Node3D
var _expression: Object
var _expression_was_held := false
var _materials: Array[Dictionary] = []
var _hologram: ShaderMaterial
var _vfx: VfxEffectBase3D
var _mode := "scan"
var _active := false
var _elapsed := 0.0
var _rebuild_seconds := 1.55
var _solidify_seconds := 0.25
var _solidifying := false
var _solid := false
var _world_min := 0.0
var _world_max := 1.0


func prepare(player: Node3D, params: Dictionary = {}) -> bool:
	restore()
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	_player = player
	_expression = player.get("expression_system") as Object
	if is_instance_valid(_expression):
		_expression_was_held = bool(_expression.get("presentation_held"))
		_expression.set("presentation_held", true)
	_mode = str(params.get("mode", "scan"))
	_rebuild_seconds = maxf(0.05, float(params.get("rebuild_seconds", 1.55)))
	_solidify_seconds = maxf(0.05, float(params.get("solidify_seconds", 0.25)))
	var avatar: Variant = player.get("avatar")
	if not is_instance_valid(avatar):
		restore()
		return false
	var root := (avatar as Object).get("visual_root") as Node3D
	if not is_instance_valid(root) or not root.is_visible_in_tree():
		restore()
		return false
	var state_ring := (avatar as Object).get("lock_ring") as Node3D
	var state_root := state_ring.get_parent() if is_instance_valid(state_ring) else null
	var meshes: Array[MeshInstance3D] = []
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if state_root != null and state_root.is_ancestor_of(mesh):
			continue
		if mesh.is_visible_in_tree() and mesh.mesh != null and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			meshes.append(mesh)
	if meshes.is_empty():
		restore()
		return false
	_world_min = INF
	_world_max = -INF
	for mesh in meshes:
		var bounds := mesh.get_aabb()
		for corner in 8:
			var height := (mesh.global_transform * bounds.get_endpoint(corner)).y
			_world_min = minf(_world_min, height)
			_world_max = maxf(_world_max, height)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = HOLOGRAM_SHADER_CODE
	_hologram = ShaderMaterial.new()
	_hologram.shader = _shader
	_hologram.set_shader_parameter("world_min", _world_min)
	_hologram.set_shader_parameter("world_max", _world_max)
	for mesh in meshes:
		_materials.append({
			"mesh": mesh, "material_override": mesh.material_override,
			"material_overlay": mesh.material_overlay, "cast_shadow": mesh.cast_shadow,
			"transparency": mesh.transparency, "ghost": null,
		})
		mesh.material_overlay = null
		mesh.material_override = _hologram
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true


func start(_params: Dictionary = {}) -> bool:
	if not is_instance_valid(_player) or _materials.is_empty():
		return false
	if _active:
		return true
	_active = true
	_elapsed = 0.0
	if DisplayServer.get_name() != "headless":
		_vfx = VfxPool.acquire(VFX_SCAN if _mode == "scan" else VFX_MATERIALIZE,
			_player.global_position, Color(0.20, 0.86, 1.0), 1.0, {
				"follow": _player, "duration": _rebuild_seconds,
				"height_min": _world_min - _player.global_position.y,
				"height_max": _world_max - _player.global_position.y,
			})
	return true


func tick(delta: float) -> void:
	if not _active:
		return
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		restore()
		return
	_elapsed += maxf(delta, 0.0)
	if _solid:
		return
	_hologram.set_shader_parameter("reveal_progress", clampf(_elapsed / _rebuild_seconds, 0.0, 1.0))
	if _elapsed < _rebuild_seconds:
		return
	if not _solidifying:
		_begin_solidify()
	var weight := smoothstep(0.0, 1.0, clampf((_elapsed - _rebuild_seconds) / _solidify_seconds, 0.0, 1.0))
	_hologram.set_shader_parameter("opacity", 1.0 - weight)
	for entry in _materials:
		var mesh := entry["mesh"] as MeshInstance3D
		var ghost := entry["ghost"] as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.transparency = lerpf(1.0, float(entry["transparency"]), weight)
			if is_instance_valid(ghost):
				ghost.transform = mesh.transform
	if weight >= 1.0:
		_restore_materials()
		_solid = true


func _begin_solidify() -> void:
	_solidifying = true
	# 独立全息副层逐渐消退；真实几何使用原材质和原shader渐入，不近似重建原材质。
	for entry in _materials:
		var mesh := entry["mesh"] as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		var ghost := MeshInstance3D.new()
		ghost.mesh = mesh.mesh
		ghost.skin = mesh.skin
		ghost.skeleton = mesh.skeleton
		ghost.layers = mesh.layers
		ghost.material_override = _hologram
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.get_parent().add_child(ghost)
		ghost.transform = mesh.transform
		for index in mesh.get_blend_shape_count():
			ghost.set_blend_shape_value(index, mesh.get_blend_shape_value(index))
		entry["ghost"] = ghost
		mesh.transparency = 1.0
		mesh.material_override = entry["material_override"]
		mesh.material_overlay = entry["material_overlay"]


func restore() -> void:
	if is_instance_valid(_vfx):
		_vfx.finish()
	_vfx = null
	_restore_materials()
	if is_instance_valid(_expression):
		_expression.set("presentation_held", _expression_was_held)
	_expression = null
	_player = null
	_hologram = null
	_active = false
	_solidifying = false
	_solid = false
	_elapsed = 0.0


func _restore_materials() -> void:
	for entry in _materials:
		var mesh: Variant = entry["mesh"]
		if is_instance_valid(mesh):
			mesh.material_override = entry["material_override"]
			mesh.material_overlay = entry["material_overlay"]
			mesh.cast_shadow = entry["cast_shadow"]
			mesh.transparency = entry["transparency"]
		var ghost: Variant = entry["ghost"]
		if is_instance_valid(ghost):
			ghost.visible = false
			ghost.queue_free()
	_materials.clear()


func is_active() -> bool:
	return _active


func get_snapshot() -> Dictionary:
	return {"active": _active, "mode": _mode, "mesh_count": _materials.size(),
		"progress": clampf(_elapsed / _rebuild_seconds, 0.0, 1.0),
		"solid": _solid, "solidifying": _solidifying, "world_min": _world_min, "world_max": _world_max}
