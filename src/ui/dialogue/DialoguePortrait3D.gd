class_name DialoguePortrait3D
extends TextureRect
## 独立世界中的纯几何半身像；所有角色外壳均在进树前释放。

const Catalog = preload("res://src/ui/dialogue/DialoguePortraitCatalog.gd")
const HOLOGRAM_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform bool hologram = false;
uniform bool reduced_motion = false;
uniform float clock = 0.0;
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	vec4 tint = vertex_tint;
	vec2 uv = UV;
	float band = hologram && !reduced_motion ? step(0.985, sin(uv.y * 43.0 + clock * 1.4)) : 0.0;
	uv.x += band * 0.004 * sin(clock * 2.0);
	vec4 src = texture(TEXTURE, uv);
	if (hologram) {
		float scan = 0.94 + 0.06 * sin(uv.y * 330.0 + clock * 2.5);
		vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
		float around = max(max(texture(TEXTURE, uv + vec2(px.x, 0.0)).a, texture(TEXTURE, uv - vec2(px.x, 0.0)).a), max(texture(TEXTURE, uv + vec2(0.0, px.y)).a, texture(TEXTURE, uv - vec2(0.0, px.y)).a));
		float edge = max(0.0, around - src.a);
		src.rgb = mix(src.rgb, src.rgb * vec3(0.48, 1.1, 1.22) + vec3(0.02, 0.10, 0.14), 0.38) * scan;
		src.rgb = mix(src.rgb, vec3(0.12, 0.65, 0.85), edge * 0.8);
		src.a = max(src.a * (0.9 - band * 0.18), edge * 0.38);
	}
	COLOR = src * tint;
}
"""

@export var default_speaker_id := "player"
@export var default_mode := "normal"
var speaker_id := ""
var mode := "normal"
var source_path := ""
var mesh_count := 0
var entering := false
var exiting := false
var _viewport: SubViewport
var _pivot: Node3D
var _visual: Node3D
var _camera: Camera3D
var _head: Node3D
var _head_base := Vector3.ZERO
var _pixels: MeshInstance3D
var _expression := ""
var _config: Dictionary = {}
var _focused := false
var _reduced := false
var _frozen := false
var _clock := 0.0
var _tick_left := 0.0
var _shader: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	var shader := Shader.new()
	shader.code = HOLOGRAM_SHADER
	_shader = ShaderMaterial.new()
	_shader.shader = shader
	material = _shader
	resized.connect(_resize_viewport)
	visibility_changed.connect(_visibility_changed)
	set_process(false)
	if not default_speaker_id.is_empty():
		configure(Catalog.resolve({"speaker_id": default_speaker_id, "portrait_mode": default_mode}))


func configure(config: Dictionary) -> bool:
	if config.is_empty():
		return false
	var geometry_changed: bool = _visual == null or str(config.get("source_path", "")) != source_path or config.get("skin_color") != _config.get("skin_color") or str(config.get("source_node", "")) != str(_config.get("source_node", ""))
	_config = config.duplicate(true)
	speaker_id = str(config.get("speaker_id", ""))
	mode = "normal" if speaker_id == "player" else str(config.get("portrait_mode", "normal"))
	_shader.set_shader_parameter("hologram", mode == "hologram")
	if geometry_changed and not _build_geometry(config):
		return false
	_apply_expression(str(config.get("expression", "neutral")))
	_request_frame()
	_refresh_processing()
	return mesh_count > 0


func set_focus(focused: bool) -> void:
	_focused = focused
	self_modulate = Color.WHITE if focused else Color(0.61, 0.65, 0.70, 1.0)
	_request_frame()


func set_motion(reduced: bool, frozen: bool) -> void:
	_reduced = reduced
	_frozen = frozen
	_shader.set_shader_parameter("reduced_motion", reduced)
	if reduced and _pivot != null:
		_pivot.position.y = 0.0
		_pivot.scale = Vector3.ONE
		if _head != null:
			_head.rotation = _head_base
		_request_frame()
	_refresh_processing()


func stop_rendering() -> void:
	hide()
	entering = false
	exiting = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)


func get_snapshot() -> Dictionary:
	return {
		"speaker_id": speaker_id, "visible": is_visible_in_tree(), "mode": mode,
		"entering": entering, "exiting": exiting, "rect": get_global_rect(),
		"mesh_count": mesh_count, "source_path": source_path,
		"expression": _expression, "viewport_count": 1 if _viewport != null else 0,
		"rendering": _viewport != null and _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED,
	}


func _build_geometry(config: Dictionary) -> bool:
	source_path = str(config.get("source_path", ""))
	if not ResourceLoader.exists(source_path):
		_clear_geometry()
		return false
	var packed := load(source_path) as PackedScene
	if packed == null:
		_clear_geometry()
		return false
	var shell := packed.instantiate()
	var source_node := str(config.get("source_node", ""))
	var visual := (shell if source_node.is_empty() else shell.get_node_or_null(source_node)) as Node3D
	if visual == null or visual.get_class() not in ["Node3D", "MeshInstance3D"]:
		shell.free()
		_clear_geometry()
		return false
	if visual != shell:
		visual.get_parent().remove_child(visual)
		shell.free()
	_sanitize(visual)
	_clear_geometry()
	_ensure_viewport()
	_visual = visual
	if source_path == Catalog.PLAYER_SOURCE:
		var head := visual.get_node_or_null("BunnyRig/HeadJoint") as Node3D
		if head != null and ResourceLoader.exists(Catalog.FACE_MASK_SOURCE):
			var mask_scene := load(Catalog.FACE_MASK_SOURCE) as PackedScene
			if mask_scene != null:
				var mask := mask_scene.instantiate() as Node3D
				if mask != null:
					_sanitize(mask)
					mask.name = "ElectronicMask"
					head.add_child(mask)
	var skin: StandardMaterial3D
	if config.has("skin_color"):
		skin = StandardMaterial3D.new()
		var color_value: Variant = config["skin_color"]
		skin.albedo_color = color_value if color_value is Color else Color.from_string(str(color_value), Color.WHITE)
		skin.metallic = 0.04
		skin.roughness = 0.74
	_pivot.position = Vector3.ZERO
	_pivot.scale = Vector3.ONE
	_pivot.add_child(visual)
	mesh_count = 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		mesh_count += 1
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if skin != null and not _under_mask(mesh):
			mesh.material_override = skin
	_head = visual.get_node_or_null("BunnyRig/HeadJoint") as Node3D
	if _head != null:
		_head_base = _head.rotation
		_pixels = _head.get_node_or_null("ElectronicMask/Visual/ExpressionPixels") as MeshInstance3D
	_frame_upper_body()
	return mesh_count > 0


# 白名单清理，排除相机、物理、声音、粒子、交互和动画控制器。
func _sanitize(node: Node) -> void:
	node.set_script(null)
	for group in node.get_groups():
		node.remove_from_group(group)
	for child in node.get_children():
		if child.get_class() not in ["Node3D", "MeshInstance3D", "Marker3D", "Skeleton3D", "BoneAttachment3D"]:
			node.remove_child(child)
			child.free()
		else:
			_sanitize(child)


func _under_mask(node: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null and cursor != _visual:
		if cursor.name == "ElectronicMask":
			return true
		cursor = cursor.get_parent()
	return false


func _clear_geometry() -> void:
	if _visual != null:
		_visual.get_parent().remove_child(_visual)
		_visual.free()
	_visual = null
	_head = null
	_pixels = null
	_expression = ""
	mesh_count = 0


func _ensure_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "PortraitViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	_viewport.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, -35, 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, 145, 0)
	fill.light_color = Color(0.65, 0.80, 1.0)
	fill.light_energy = 0.65
	_viewport.add_child(fill)
	texture = _viewport.get_texture()
	_resize_viewport()


func _frame_upper_body() -> void:
	if _visual == null or _camera == null:
		return
	var bounds := AABB()
	var first := true
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var relative := _pivot.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	# 裁脚至腰部，顶部保留双耳与呼吸余量；不依赖源模型绝对尺寸。
	var waist := bounds.position.y + bounds.size.y * 0.30
	var top := bounds.end.y + bounds.size.y * 0.045
	var height := top - waist
	var center := Vector3(bounds.get_center().x, (waist + top) * 0.5, bounds.get_center().z)
	var aspect := float(_viewport.size.x) / float(_viewport.size.y)
	_camera.size = maxf(height, bounds.size.x / aspect * 1.06)
	_camera.position = center + Vector3(0.0, 0.0, -maxf(3.0, bounds.size.z * 4.0))
	_camera.look_at(center, Vector3.UP)
	_request_frame()


func _apply_expression(expression: String) -> void:
	if _pixels == null or expression == _expression:
		return
	var definition := CharacterExpressionCatalog.get_definition(expression)
	if definition.is_empty():
		definition = CharacterExpressionCatalog.get_definition("neutral")
		expression = "neutral"
	var face := (definition["scene"] as PackedScene).instantiate()
	var meshes := face.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() == 1:
		_pixels.mesh = (meshes[0] as MeshInstance3D).mesh
		var source_material := _pixels.mesh.surface_get_material(0)
		if source_material != null:
			_pixels.material_override = source_material.duplicate()
		_expression = expression
	face.free()


func _resize_viewport() -> void:
	if _viewport == null:
		return
	var height := clampi(int(size.y), 192, 640)
	var aspect := size.x / maxf(size.y, 1.0)
	_viewport.size = Vector2i(maxi(96, int(height * aspect)), height)
	_frame_upper_body()


func _request_frame() -> void:
	if _viewport != null and is_visible_in_tree():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _visibility_changed() -> void:
	if not is_visible_in_tree() and _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_request_frame()
	_refresh_processing()


func _refresh_processing() -> void:
	set_process(is_visible_in_tree() and not _frozen and not _reduced and mesh_count > 0)


func _process(delta: float) -> void:
	_clock += delta
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = 1.0 / (15.0 if _focused else 8.0)
	_pivot.position.y = sin(_clock * 1.7) * 0.006
	_pivot.scale = Vector3.ONE * (1.012 if _focused else 1.0)
	if _head != null:
		_head.rotation = _head_base + Vector3(sin(_clock * 3.8) * 0.018 if _focused else 0.0, 0.0, sin(_clock * 1.3) * 0.008)
	_shader.set_shader_parameter("clock", _clock)
	_request_frame()
