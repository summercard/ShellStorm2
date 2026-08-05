class_name ItemModelIcon3D
extends Control
## 将世界道具的同一 3D 模型投射为背包图标；配置后只渲染一次。

@export_range(64, 160, 8) var icon_resolution := 96

var _item_data: Dictionary = {}
var _viewport: SubViewport
var _preview_rect: TextureRect
var _camera: Camera3D
var _model_anchor: Node3D
var _model: Node3D
var _configured := false
var _camera_size_multiplier := 1.0
var _rebuild_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_studio()
	if _configured:
		_rebuild_model()


func configure(item: Dictionary) -> void:
	_item_data = item.duplicate(true)
	_configured = true
	if is_node_ready():
		_rebuild_model()


func set_camera_size_multiplier(multiplier: float) -> void:
	_camera_size_multiplier = clampf(multiplier, 0.45, 1.5)
	if _camera != null and not _item_data.is_empty():
		_apply_camera_size(ItemModelFactory3D.get_model_kind(_item_data))
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func clear_model() -> void:
	_item_data.clear()
	_configured = false
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	visible = false


func get_snapshot() -> Dictionary:
	return {
		"item_id": str(_item_data.get("id", "")),
		"model_kind": ItemModelFactory3D.get_model_kind(_item_data) if not _item_data.is_empty() else "",
		"mesh_count": ItemModelFactory3D.count_mesh_instances(_model) if _model != null else 0,
		"viewport_size": _viewport.size if _viewport != null else Vector2i.ZERO,
		"camera_size": _camera.size if _camera != null else 0.0,
		"camera_size_multiplier": _camera_size_multiplier,
		"rebuild_count": _rebuild_count,
		"update_once": _viewport != null and _viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"uses_world_model_factory": true,
	}


func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ItemPreviewViewport"
	_viewport.size = Vector2i(icon_resolution, icon_resolution)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_preview_rect = TextureRect.new()
	_preview_rect.name = "ProjectedTexture"
	_preview_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_rect.texture = _viewport.get_texture()
	add_child(_preview_rect)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.018, 0.026, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.80, 0.86)
	environment.ambient_light_energy = 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.18
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.65
	_camera.position = Vector3(3.2, 2.65, 4.1)
	_camera.look_at_from_position(_camera.position, Vector3(0, 0.10, 0), Vector3.UP)
	_camera.current = true
	_viewport.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	key.light_color = Color(0.90, 0.96, 1.0)
	key.light_energy = 2.2
	key.shadow_enabled = false
	_viewport.add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.8, 2.4)
	fill.light_color = Color(0.56, 0.76, 1.0)
	fill.light_energy = 2.0
	fill.omni_range = 8.0
	fill.shadow_enabled = false
	_viewport.add_child(fill)

	_model_anchor = Node3D.new()
	_model_anchor.name = "ModelAnchor"
	_model_anchor.rotation_degrees = Vector3(-8, 18, 0)
	_viewport.add_child(_model_anchor)


func _rebuild_model() -> void:
	if _viewport == null or _model_anchor == null:
		return
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	if _item_data.is_empty():
		visible = false
		return
	_rebuild_count += 1
	_model = ItemModelFactory3D.create_model(_item_data, _item_tint(_item_data))
	_model.name = "ProjectedItemModel"
	_model_anchor.add_child(_model)
	var kind := ItemModelFactory3D.get_model_kind(_item_data)
	# 图标槽只有 56px，模型应占据大部分轮廓，避免“有3D模型但看不清”。
	_apply_camera_size(kind)
	_model.position = Vector3(0, 0.05 if kind == "weapon" else 0.0, 0)
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _apply_camera_size(kind: String) -> void:
	if _camera == null:
		return
	_camera.size = (1.82 if kind == "weapon" else 1.62) * _camera_size_multiplier


func _item_tint(item: Dictionary) -> Color:
	match str(item.get("rarity", "common")):
		"legendary":
			return Color(1.0, 0.54, 0.12)
		"epic":
			return Color(0.72, 0.38, 1.0)
		"rare":
			return Color(0.28, 0.68, 1.0)
		"uncommon":
			return Color(0.34, 0.92, 0.56)
		_:
			return Color(0.72, 0.80, 0.84)
