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
	# 2026-09-28 主人要求：HUD 武器栏精简为「枪械图标 + 当前子弹 · N备弹 + 命运卡槽 0/4」，
	# 不再显示弹匣容量与武器名/实例行。上面三个 *_text 是**既有只读投影契约**
	# （verify_hud_presenter_3d 逐字断言 `17 / 30`、`[2] 突击步枪 · 副武器`、`命运 2/5`），
	# 保持逐字不变；显示层要用的原始数值改为**随命令一起下发**，由 Dungeon3D 决定怎么排。
	var melee_weapon := bool(runtime_weapon.get("melee", false))
	var command := {
		"ammo_text": (
			"近战 · 三段"
			if melee_weapon
			else "%d / %d" % [current_ammo, maximum_ammo]
		),
		"ammo_current": current_ammo,
		"ammo_capacity": maximum_ammo,
		"ammo_is_melee": melee_weapon,
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
		"fate_slot_used": int(presentation.get("fate_slot_used", 0)),
		"fate_slot_capacity": int(presentation.get("fate_slot_capacity", 0)),
		"model_action": model_action,
		"weapon_item": weapon_item.duplicate(true),
		"weapon_instance_id": instance_id,
	}
	weapon_hud_command_ready.emit(command.duplicate(true))
	return command


func reset() -> void:
	_presented_weapon_instance_id = ""
