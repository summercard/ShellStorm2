class_name AvatarCustomizationPersistence
extends RefCounted
## 把纯表现换装写入现有 BaseData/ProfileSaveService 存档封套。
## 服务不持有 Player3D，也不接触碰撞、武器、生命或战斗数据。

const PROFILE_FIELD := "avatar_customization"


static func normalize_loadout(loadout: Dictionary) -> Dictionary:
	var normalized := PlayerAvatar3D.DEFAULT_CUSTOMIZATION.duplicate(true)
	for slot_id in PlayerAvatar3D.DEFAULT_CUSTOMIZATION:
		var variant_id := str(loadout.get(slot_id, normalized[slot_id]))
		if PlayerAvatar3D.has_customization_variant(slot_id, variant_id):
			normalized[slot_id] = variant_id
	return normalized


static func get_saved_loadout() -> Dictionary:
	var data := _get_profile_data()
	if data == null or not _has_property(data, PROFILE_FIELD):
		return PlayerAvatar3D.DEFAULT_CUSTOMIZATION.duplicate(true)
	var stored: Variant = data.get(PROFILE_FIELD)
	return normalize_loadout(stored as Dictionary if stored is Dictionary else {})


static func apply_saved_to_player(player: Player3D) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var loadout := get_saved_loadout()
	player.set_avatar_customization_loadout(loadout)
	return loadout


static func persist_from_player(player: Player3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return persist_loadout(player.get_avatar_customization())


static func persist_loadout(loadout: Dictionary) -> bool:
	var data := _get_profile_data()
	if data == null or not _has_property(data, PROFILE_FIELD):
		push_warning("[AvatarCustomizationPersistence] BaseData is missing avatar_customization")
		return false
	var previous: Variant = data.get(PROFILE_FIELD)
	var previous_copy := (previous as Dictionary).duplicate(true) if previous is Dictionary else {}
	data.set(PROFILE_FIELD, normalize_loadout(loadout))
	if BaseManager.save_base("avatar_customization"):
		return true
	data.set(PROFILE_FIELD, previous_copy)
	return false


static func _get_profile_data() -> Object:
	if BaseManager == null:
		return null
	if BaseManager.data == null:
		BaseManager.load_base()
	return BaseManager.data


static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
