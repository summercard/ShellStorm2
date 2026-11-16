class_name DialoguePortraitCatalog
extends RefCounted
## 纯显示目录；不读取演员、领域状态或用户档。

const PLAYER_SOURCE := "res://scenes/Player3D.tscn"
const FACE_MASK_SOURCE := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/runtime/chr_bunny01_electronic_mask_root.tscn"
const MONITOR_SOURCE := "res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn"
const DISPLAY_IDS := {"主角": "player", "绿苔": "npc_base99_green"}
# 对齐 NpcCatalog → AvatarCustomizationCatalog 的 suit_green 实际色；不依赖玩法类。
const GREEN_SKIN := Color(0.16, 0.68, 0.30)


static func speaker_id(metadata: Dictionary) -> String:
	var explicit_id := str(metadata.get("speaker_id", ""))
	if not explicit_id.is_empty():
		return explicit_id
	return str(DISPLAY_IDS.get(str(metadata.get("speaker", "")), ""))


static func resolve(metadata: Dictionary) -> Dictionary:
	var id := speaker_id(metadata)
	if id.is_empty():
		return {}
	var result := metadata.duplicate(true)
	result["speaker_id"] = id
	result["side"] = "right" if id == "player" else "left"
	result["portrait_mode"] = "normal" if id == "player" else str(metadata.get("portrait_mode", "normal"))
	result["expression"] = str(metadata.get("expression", "neutral"))
	if id in ["player", "npc_base99_green"] or (metadata.has("skin_color") and str(metadata.get("source_path", "")).is_empty()):
		result["source_path"] = PLAYER_SOURCE
		result["source_node"] = "Avatar3D/VisualRoot"
	elif id == "boss_monitor002":
		# 借真实显示器Boss几何，不让其战斗/动画脚本进入UI场景树。
		result["source_path"] = MONITOR_SOURCE
		result["source_node"] = "Model"
	elif str(metadata.get("source_path", "")).is_empty():
		return {}
	if id == "npc_base99_green" and not metadata.has("skin_color"):
		result["skin_color"] = GREEN_SKIN
	return result
