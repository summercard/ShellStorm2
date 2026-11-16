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
var _instances: Dictionary = {}
var _selected: Array[String] = []
var _emitting := false


func configure(behavior: Dictionary, size: float, context: Dictionary) -> void:
	reset()
	var elements: Dictionary = behavior.get("fate_elements", {})
	for element in ["fire", "ice", "poison", "lightning"]:
		if elements.has(element):
			_selected.append(element)
	if bool(behavior.get("chain_lightning", false)) and int(behavior.get("chain_count", 3)) > 0 and not _selected.has("lightning"):
		_selected.append("lightning")
	if int(behavior.get("bounce_count", 0)) > 0:
		_selected.append("bounce")
	if bool(behavior.get("homing", false)):
		_selected.append("homing")
	if bool(behavior.get("return_on_hit", false)) or bool(behavior.get("return_to_player", false)) or bool(behavior.get("home_on_land", false)):
		_selected.append("return")
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


func set_emitting(enabled: bool) -> void:
	_emitting = enabled and not _selected.is_empty()
	for key in _selected:
		_instances[key].set_emitting(_emitting)
	visible = _emitting


func reset() -> void:
	for attachment in _instances.values():
		attachment.reset()
	_selected.clear()
	_emitting = false
	visible = false


func get_enchantment_snapshot() -> Dictionary:
	var attachments: Array[Dictionary] = []
	var cached: Array[Dictionary] = []
	var total := 0
	for key in _instances:
		var entry: Dictionary = _instances[key].get_enchantment_snapshot()
		entry["attribute"] = key
		cached.append(entry)
		if _selected.has(key):
			attachments.append(entry.duplicate(true))
			total += int(entry["amount"])
	return {
		"attributes": _selected.duplicate(), "attribute_count": _selected.size(),
		"attachments": attachments, "cached_attachments": cached,
		"total_amount": total, "emitting": _emitting,
		"cached_count": _instances.size(),
	}
