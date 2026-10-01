class_name CharacterExpressionCatalog
extends RefCounted
## Generated from the Blender pixel-art plan; stable scene IDs, no gameplay authority.
const ENTRIES := {
	"neutral": {"asset_id": "CHR-PLY-BUNNY01-EXPR-NEUTRAL", "name": "平静", "kind": "emotion", "color": Color("#21bfff"), "blink_enabled": true, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_neutral/runtime/chr_bunny01_expression_neutral_root_top3d.tscn")},
	"happy": {"asset_id": "CHR-PLY-BUNNY01-EXPR-HAPPY", "name": "开心", "kind": "emotion", "color": Color("#29e9ff"), "blink_enabled": true, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_happy/runtime/chr_bunny01_expression_happy_root_top3d.tscn")},
	"sad": {"asset_id": "CHR-PLY-BUNNY01-EXPR-SAD", "name": "难过", "kind": "emotion", "color": Color("#777bff"), "blink_enabled": true, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_sad/runtime/chr_bunny01_expression_sad_root_top3d.tscn")},
	"angry": {"asset_id": "CHR-PLY-BUNNY01-EXPR-ANGRY", "name": "生气", "kind": "emotion", "color": Color("#ff3028"), "blink_enabled": true, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_angry/runtime/chr_bunny01_expression_angry_root_top3d.tscn")},
	"surprised": {"asset_id": "CHR-PLY-BUNNY01-EXPR-SURPRISED", "name": "惊讶", "kind": "emotion", "color": Color("#ffe45c"), "blink_enabled": true, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_surprised/runtime/chr_bunny01_expression_surprised_root_top3d.tscn")},
	"love": {"asset_id": "CHR-PLY-BUNNY01-EXPR-LOVE", "name": "爱心", "kind": "emotion", "color": Color("#ff6abb"), "blink_enabled": true, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_love/runtime/chr_bunny01_expression_love_root_top3d.tscn")},
	"question": {"asset_id": "CHR-PLY-BUNNY01-EXPR-QUESTION", "name": "疑问", "kind": "symbol", "color": Color("#ffd24a"), "blink_enabled": false, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_question/runtime/chr_bunny01_expression_question_root_top3d.tscn")},
	"alert": {"asset_id": "CHR-PLY-BUNNY01-EXPR-ALERT", "name": "警示", "kind": "symbol", "color": Color("#a1fff2"), "blink_enabled": false, "scene": preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/expressions/chr_bunny01_expression_alert/runtime/chr_bunny01_expression_alert_root_top3d.tscn")},
}

static func has_expression(id: String) -> bool:
	return ENTRIES.has(id)

static func get_definition(id: String) -> Dictionary:
	return (ENTRIES.get(id, {}) as Dictionary).duplicate()

static func get_ids() -> Array[String]:
	var result: Array[String] = []
	for id in ENTRIES:
		result.append(str(id))
	return result
