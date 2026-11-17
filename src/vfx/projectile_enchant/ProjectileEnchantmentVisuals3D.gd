extends Node3D
## 仅路由独立附件；不读取卡牌文案，不接管弹种或战斗状态。

const PREFABS := {
	"fire": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_fire_root_top3d.tscn"),
	"ice": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_ice_root_top3d.tscn"),
	"poison": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_poison_root_top3d.tscn"),
	"lightning": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_lightning_root_top3d.tscn"),
	"bounce": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_bounce_root_top3d.tscn"),
	"homing": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_homing_root_top3d.tscn"),
	"return": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_return_root_top3d.tscn"),
}
const LIGHT_PREFABS := {
	"fire": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_fire_root_top3d.tscn"),
	"ice": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_ice_root_top3d.tscn"),
	"poison": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_poison_root_top3d.tscn"),
	"lightning": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_lightning_root_top3d.tscn"),
	"bounce": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_bounce_root_top3d.tscn"),
	"homing": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_homing_root_top3d.tscn"),
	"return": preload("res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_return_root_top3d.tscn"),
}
const BODY_PALETTE := {
	"fire": Color(1.0, 0.22, 0.06),
	"ice": Color(0.52, 0.86, 1.0),
	"poison": Color(0.42, 0.90, 0.26),
	"lightning": Color(0.52, 0.78, 1.0),
	"bounce": Color(1.0, 0.66, 0.30),
	"homing": Color(0.36, 1.0, 0.78),
	"return": Color(0.78, 0.56, 1.0),
}
var _instances: Dictionary = {}
var _light_instances: Dictionary = {}
var _active_light_key := ""
var _selected: Array[String] = []
var _emitting := false


static func selected_attributes(behavior: Dictionary) -> Array[String]:
	var selected: Array[String] = []
	var elements: Dictionary = behavior.get("fate_elements", {})
	for element in ["fire", "ice", "poison", "lightning"]:
		if elements.has(element):
			selected.append(element)
	if bool(behavior.get("chain_lightning", false)) and int(behavior.get("chain_count", 3)) > 0 and not selected.has("lightning"):
		selected.append("lightning")
	if int(behavior.get("bounce_count", 0)) > 0:
		selected.append("bounce")
	if bool(behavior.get("homing", false)):
		selected.append("homing")
	if bool(behavior.get("return_on_hit", false)) or bool(behavior.get("return_to_player", false)) or bool(behavior.get("home_on_land", false)):
		selected.append("return")
	return selected


static func body_tint(attributes: Array[String]) -> Color:
	var unique: Array[String] = []
	var rgb := Vector3.ZERO
	for key in attributes:
		if unique.has(key) or not BODY_PALETTE.has(key):
			continue
		unique.append(key)
		var tint: Color = BODY_PALETTE[key]
		rgb += Vector3(tint.r, tint.g, tint.b)
	if unique.is_empty():
		return Color.WHITE
	rgb /= float(unique.size())
	return Color(rgb.x, rgb.y, rgb.z)


func configure(behavior: Dictionary, size: float, context: Dictionary) -> void:
	reset()
	_selected = selected_attributes(behavior)
	for key in _selected:
		if not _instances.has(key):
			var instance: VfxEffectBase3D = (PREFABS[key] as PackedScene).instantiate() as VfxEffectBase3D
			instance.name = "Enchant_" + key
			add_child(instance)
			_instances[key] = instance
		var attachment: VfxEffectBase3D = _instances[key]
		var parameters := context.duplicate(true)
		parameters["attribute_count"] = _selected.size()
		attachment.configure(Color.WHITE, size, parameters)
	if not _selected.is_empty():
		# 第一属性决定灯对象与宿主，最终灯色混合全部去重属性。
		_active_light_key = _selected[0]
		if not _light_instances.has(_active_light_key):
			var light = (LIGHT_PREFABS[_active_light_key] as PackedScene).instantiate()
			light.name = "EnchantLight_" + _active_light_key
			light.reset()
			_instances[_active_light_key].add_child(light)
			_light_instances[_active_light_key] = light
	_sync_light()


func _sync_light() -> void:
	var mixed_color := body_tint(_selected)
	for key in _light_instances:
		_light_instances[key].set_enabled(
			_emitting and key == _active_light_key,
			mixed_color if key == _active_light_key else BODY_PALETTE[key]
		)


func set_emitting(enabled: bool) -> void:
	_emitting = enabled and not _selected.is_empty()
	for key in _selected:
		_instances[key].set_emitting(_emitting)
	visible = _emitting
	_sync_light()


func reset() -> void:
	for light in _light_instances.values():
		light.reset()
	_active_light_key = ""
	for attachment in _instances.values():
		attachment.reset()
	_selected.clear()
	_emitting = false
	visible = false


func get_enchantment_snapshot() -> Dictionary:
	var attachments: Array[Dictionary] = []
	var cached: Array[Dictionary] = []
	var total := 0
	var cached_lights: Array[Dictionary] = []
	var enchantment_light: Dictionary = {}
	var active_light_count := 0
	for key in _light_instances:
		var light_entry: Dictionary = _light_instances[key].get_light_snapshot()
		cached_lights.append(light_entry)
		if bool(light_entry["active"]):
			active_light_count += 1
		if key == _active_light_key:
			enchantment_light = light_entry.duplicate(true)
	for key in _instances:
		var entry: Dictionary = _instances[key].get_enchantment_snapshot()
		entry["attribute"] = key
		cached.append(entry)
		if _selected.has(key):
			attachments.append(entry.duplicate(true))
			total += int(entry["amount"])
	return {
		"attributes": _selected.duplicate(), "selected": _selected.duplicate(),
		"attribute_count": _selected.size(),
		"body_tint": body_tint(_selected),
		"attachments": attachments, "cached_attachments": cached,
		"total_amount": total, "emitting": _emitting,
		"cached_count": _instances.size(),
		"enchantment_light": enchantment_light,
		"cached_lights": cached_lights,
		"active_light_count": active_light_count,
	}
