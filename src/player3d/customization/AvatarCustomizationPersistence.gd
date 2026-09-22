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
	if BaseManager == null:
		return PlayerAvatar3D.DEFAULT_CUSTOMIZATION.duplicate(true)
	return normalize_loadout(BaseManager.get_avatar_customization_snapshot())


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
	if BaseManager == null:
		return false
	return BaseManager.commit_avatar_customization(normalize_loadout(loadout))
