extends Node3D
## 宿主持有的独立灯对象；只管理本实例，不进入特效池。

@export var preset_key := ""
var _light: OmniLight3D
var _preset_color := Color.WHITE
var _active := true


func _ready() -> void:
	_ensure_light()


func _ensure_light() -> void:
	if _light == null:
		_light = get_node("EnchantmentLight") as OmniLight3D
		# 保留宿主的位置和旋转继承，只去掉粒子尺寸及生长带来的世界缩放。
		_light.set_disable_scale(true)
		_preset_color = _light.light_color


func set_enabled(enabled: bool, color: Color) -> void:
	_ensure_light()
	_active = enabled
	visible = enabled
	_light.visible = enabled
	_light.light_color = color
	_light.light_energy = 1.15 if enabled else 0.0


func reset() -> void:
	_ensure_light()
	set_enabled(false, _preset_color)
	transform = Transform3D.IDENTITY


func get_light_snapshot() -> Dictionary:
	_ensure_light()
	var attachment := get_parent()
	return {
		"preset_key": preset_key,
		"scene_path": scene_file_path,
		"asset_id": String(get_meta("asset_id", "")),
		"asset_version": String(get_meta("asset_version", "")),
		"lifecycle_owner": String(get_meta("lifecycle_owner", "")),
		"color": _light.light_color, "preset_color": _preset_color,
		"energy": _light.light_energy, "range": _light.omni_range,
		"visible": visible and _light.visible,
		"visible_in_tree": _light.is_visible_in_tree() if is_inside_tree() else false,
		"active": _active, "instance_id": get_instance_id(),
		"parent_attachment": String(attachment.name) if attachment != null else "",
		"parent_attachment_instance_id": attachment.get_instance_id() if attachment != null else 0,
		"shadow_enabled": _light.shadow_enabled,
		"light_cull_mask": _light.light_cull_mask,
		"shadow_caster_mask": _light.shadow_caster_mask,
		"distance_fade_enabled": _light.distance_fade_enabled,
		"distance_fade_begin": _light.distance_fade_begin,
		"distance_fade_length": _light.distance_fade_length,
		"scale_disabled": _light.is_scale_disabled(),
		"local_transform": transform,
		"world_transform": _light.global_transform if is_inside_tree() else _light.transform,
	}
