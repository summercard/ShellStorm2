class_name MapThemeProfile
extends Resource

@export var theme_id := "default"
@export var display_name := "未命名区域"
@export_multiline var fantasy := ""
@export_range(1, 99, 1) var difficulty_rank := 1
@export var visual_floor := 1

@export_group("Layout Rules")
@export var layout_rules: Dictionary = {}
@export var path_room_weights: Dictionary = {}
@export var branch_room_weights: Dictionary = {}
@export var required_branch_types: Array[String] = []

@export_group("Content Rules")
@export var enemy_rules: Dictionary = {}
@export var content_rules: Dictionary = {}
@export var npc_rules: Array[Dictionary] = []


func get_layout_rule(key: String, fallback: Variant) -> Variant:
	return layout_rules.get(key, fallback)


func get_content_rule(key: String, fallback: Variant) -> Variant:
	return content_rules.get(key, fallback)


func get_enemy_rule(key: String, fallback: Variant) -> Variant:
	return enemy_rules.get(key, fallback)


func choose_room_type(
	rng: RandomNumberGenerator, weights: Dictionary, fallback: RoomData.RoomType
) -> RoomData.RoomType:
	var total := 0.0
	for value in weights.values():
		total += maxf(0.0, float(value))
	if total <= 0.0:
		return fallback
	var roll := rng.randf_range(0.0, total)
	for room_name in weights:
		roll -= maxf(0.0, float(weights[room_name]))
		if roll <= 0.0:
			return room_type_from_name(str(room_name), fallback)
	return fallback


func validate_profile() -> Array[String]:
	var errors: Array[String] = []
	if theme_id.is_empty():
		errors.append("theme_id is empty")
	if display_name.is_empty():
		errors.append("display_name is empty")
	if int(get_layout_rule("path_length", 0)) < 4:
		errors.append("path_length must be at least 4")
	if path_room_weights.is_empty():
		errors.append("path_room_weights is empty")
	if branch_room_weights.is_empty():
		errors.append("branch_room_weights is empty")
	if get_enemy_rule("enemy_pool", []).is_empty():
		errors.append("enemy_pool is empty")
	return errors


static func room_type_from_name(
	room_name: String, fallback: RoomData.RoomType = RoomData.RoomType.COMBAT
) -> RoomData.RoomType:
	var normalized := room_name.strip_edges().to_upper()
	if RoomData.RoomType.has(normalized):
		return int(RoomData.RoomType[normalized])
	return fallback
