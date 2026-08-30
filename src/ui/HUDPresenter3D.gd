class_name HUDPresenter3D
extends RefCounted
## 3D HUD 的只读快照 Presenter。它不持有 Control/Node，也不访问 Autoload。

signal weapon_hud_command_ready(command: Dictionary)

var _presented_weapon_instance_id := ""


func present_weapon(
	presentation: Dictionary,
	runtime_weapon: Dictionary,
	active_slot: int,
	current_ammo: int,
	maximum_ammo: int,
	weapon_item: Dictionary,
	force_model_refresh := false
) -> Dictionary:
	var instance_id := str(weapon_item.get("weapon_instance_id", ""))
	var model_action := "keep"
	if weapon_item.is_empty():
		model_action = "clear" if force_model_refresh or not _presented_weapon_instance_id.is_empty() else "keep"
		_presented_weapon_instance_id = ""
	elif force_model_refresh or instance_id != _presented_weapon_instance_id:
		model_action = "replace"
		_presented_weapon_instance_id = instance_id
	var command := {
		"ammo_text": (
			"近战 · 三段"
			if bool(runtime_weapon.get("melee", false))
			else "%d / %d" % [current_ammo, maximum_ammo]
		),
		"weapon_meta_text": "[%d] %s · %s" % [
			active_slot + 1,
			presentation.get("display_name", "未装备武器"),
			"主武器" if active_slot == 0 else "副武器",
		],
		"weapon_fate_text": "实例 #%s · 命运 %d/%d · K 详情" % [
			presentation.get("instance_suffix", "------"),
			presentation.get("fate_slot_used", 0),
			presentation.get("fate_slot_capacity", 0),
		],
		"model_action": model_action,
		"weapon_item": weapon_item.duplicate(true),
		"weapon_instance_id": instance_id,
	}
	weapon_hud_command_ready.emit(command.duplicate(true))
	return command


func reset() -> void:
	_presented_weapon_instance_id = ""
