extends Node

const PRESENTER_SCRIPT = preload("res://src/ui/HUDPresenter3D.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var presenter: HUDPresenter3D = PRESENTER_SCRIPT.new()
	var emitted: Array[Dictionary] = []
	presenter.weapon_hud_command_ready.connect(func(command: Dictionary) -> void:
		emitted.append(command)
	)
	var item := {
		"id": "weapon_rifle",
		"type": "weapon",
		"weapon_instance_id": "presenter-instance-001",
	}
	var command := presenter.present_weapon(
		{
			"display_name": "突击步枪",
			"instance_suffix": "CE-001",
			"fate_slot_used": 2,
			"fate_slot_capacity": 5,
		},
		{"melee": false},
		1,
		17,
		30,
		item
	)
	_expect(str(command.get("ammo_text", "")) == "17 / 30", "Ranged ammo text is incorrect", failures)
	_expect(str(command.get("weapon_meta_text", "")).begins_with("[2] 突击步枪 · 副武器"), "Slot metadata text is incorrect", failures)
	_expect(str(command.get("weapon_fate_text", "")).contains("命运 2/5"), "Fate metadata text is incorrect", failures)
	_expect(str(command.get("model_action", "")) == "replace", "First weapon snapshot did not request model replacement", failures)
	var repeated := presenter.present_weapon({}, {"melee": true}, 0, 0, 0, item)
	_expect(str(repeated.get("ammo_text", "")) == "近战 · 三段", "Melee HUD mode is incorrect", failures)
	_expect(str(repeated.get("model_action", "")) == "keep", "Unchanged instance rebuilt the HUD model", failures)
	var cleared := presenter.present_weapon({}, {}, 0, 0, 0, {})
	_expect(str(cleared.get("model_action", "")) == "clear", "Empty weapon snapshot did not clear the model", failures)
	_expect(emitted.size() == 3, "Presenter did not publish exactly one command per snapshot", failures)
	_finish(failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("HUD_PRESENTER_3D_OK: read-only weapon snapshots produce stable text and model commands")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
