class_name FateCardDropPickup3D
extends GroundLootPickup3D
## 命运卡专用世界凭据。
## 复用普通地面物的落地、漂浮与回收动画，但只允许统一交互控制器主动执行。

const INTERACTION_PRIORITY := 65
const INTERACTION_ID_PREFIX := "fate_card_drop:"
const FATE_CARD_ROTATION_SPEED := 0.55
const GROUND_LOOT_ROTATION_SPEED := 1.35

## Dungeon3D 注入 `_on_fate_pickup_interacted`；返回 true 才表示凭据已被主事务成功认领。
## 本类不会在成功后自行 accept_pickup()，认领、offer 与回收由 Dungeon3D 同步收口。
var interaction_handler: Callable


func configure(data: Dictionary, color := Color(0.72, 0.34, 1.0)) -> void:
	if not is_fate_pickup_data(data):
		item_data = data.duplicate(true)
		return
	item_data = data.duplicate(true)
	_build_visual(color)


func requires_manual_interaction() -> bool:
	return true


func _process(delta: float) -> void:
	super._process(delta)
	if not _accepted and _visual != null and not _spawn_animating and not _collecting:
		_visual.rotation.y += delta * (FATE_CARD_ROTATION_SPEED - GROUND_LOOT_ROTATION_SPEED)


static func is_fate_pickup_data(data: Dictionary) -> bool:
	return str(data.get("type", "")) == "fate_pickup" \
		and str(data.get("id", "")) == "item_fate_card_drop"


func get_fate_pickup_id() -> String:
	return str(item_data.get("fate_pickup_id", ""))


func _ready() -> void:
	super._ready()
	add_to_group("interaction_provider_3d")


func get_interaction_candidate(player: Node3D) -> Dictionary:
	if not _can_interact_with(player):
		return {}
	return {
		"available": true,
		"interaction_id": "%s%s" % [INTERACTION_ID_PREFIX, get_fate_pickup_id()],
		"fate_pickup_id": get_fate_pickup_id(),
		"position": global_position,
		"priority": INTERACTION_PRIORITY,
		"prompt": "[E] 获取命运卡",
	}


func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func perform_interaction(player: Node3D, candidate: Dictionary) -> bool:
	if not _can_interact_with(player):
		return false
	if str(candidate.get("fate_pickup_id", "")) != get_fate_pickup_id():
		return false
	if str(candidate.get("interaction_id", "")) != "%s%s" % [INTERACTION_ID_PREFIX, get_fate_pickup_id()]:
		return false
	if not interaction_handler.is_valid():
		return false
	return bool(interaction_handler.call(self))


func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3.UP * (LABEL_HEIGHT_M + 0.45)


func is_interaction_dot_visible() -> bool:
	return not is_pickup_accepted() and not get_fate_pickup_id().is_empty()


func get_interaction_progress() -> Dictionary:
	return {"active": false, "progress": 0.0}


func _can_interact_with(player: Node3D) -> bool:
	if not is_fate_pickup_data(item_data):
		return false
	if get_fate_pickup_id().is_empty() or is_pickup_accepted():
		return false
	if _spawn_animating or not is_pickup_available():
		return false
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var offset := player.global_position - global_position
	offset.y = 0.0
	return offset.length() <= get_pickup_distance_m()
