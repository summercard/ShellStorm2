extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const PERSISTENCE = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const TEST_SAVE_PATH := "user://avatar_return_persistence_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_save_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	var original_force_failure: bool = BaseManager.force_save_failure_for_test
	_cleanup()
	BaseManager.save_path = TEST_SAVE_PATH
	BaseManager.force_save_failure_for_test = false
	BaseManager.data = BaseData.new()
	var expected := PlayerAvatar3D.DEFAULT_CUSTOMIZATION.duplicate(true)
	expected["body"] = "suit_cobalt"
	expected["hat"] = "hard_hat"
	expected["glasses"] = "dual_goggles"
	if not PERSISTENCE.persist_loadout(expected):
		failures.append("cannot persist wardrobe loadout into the isolated profile")

	# 不创建主入口/衣柜界面，直接模拟死亡或撤离后的玩法场景重建。
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.run_seed_override = 8312027
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	var restored := dungeon.player.get_avatar_customization()
	for slot_id in expected:
		if str(restored.get(slot_id, "")) != str(expected[slot_id]):
			failures.append("gameplay scene did not restore wardrobe slot %s on hot return" % slot_id)
	dungeon.queue_free()
	await get_tree().process_frame

	BaseManager.save_path = original_save_path
	BaseManager.data = original_data
	BaseManager.force_save_failure_for_test = original_force_failure
	_cleanup()
	if failures.is_empty():
		print("AVATAR_RETURN_PERSISTENCE_FLOW_OK: gameplay scene hot-return restores the saved wardrobe without relying on a game restart")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = TEST_SAVE_PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
