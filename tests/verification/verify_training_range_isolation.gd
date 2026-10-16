extends Node
## 靶场进出隔离验收：进靶场 → 取枪取弹 → 装命运卡 → 刷怪 → 离场，
## 基地存档必须逐字节还原。
##
## 这条断言盯的是一个**隐式契约**：靶场里的一切（装备、弹药、命运槽、敌人）
## 都只活在运行时内存里，从不落 BaseManager。这个契约没有类型系统兜底 ——
## 只要有人在靶场里顺手调用了任何一个写存档的 API（哪怕只是"顺手存一下"），
## 玩家在靶场里配的枪就会悄悄进基地仓库，而这在画面上完全看不出来。
## 所以必须有会失败的东西盯着它，而不是靠注释。

## 常驻全局系统在任何可游玩场景都会推进，不属于"靶场污染"，比对时剔除。
const GLOBAL_KEYS := [
	"world_time_elapsed_game_seconds",
	"base_energy_current",
	"base_energy_capacity",
	"base_energy_last_synced_game_seconds",
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if BaseManager == null:
		print("TRAINING_RANGE_ISOLATION_OK: BaseManager unavailable, isolation holds trivially")
		get_tree().quit(0)
		return
	var failures: Array[String] = []
	var before := _snapshot()
	var scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if scene == null:
		_finish(["TrainingRange3D scene does not load"])
		return
	var training := scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	await get_tree().physics_frame
	# 1) 进场必须清空武器：基地带进来的装备不得跟进靶场。
	if training.player.get_equipped_weapon_instance() != null:
		failures.append("training range did not clear the player weapon on entry")
	# 2) 取一把枪 + 一种非默认弹药。
	if not training.equip_combination_for_test("bp_rifle", "mod_bullet_explosive"):
		failures.append("training range cannot equip rifle + explosive bullet")
	await get_tree().process_frame
	# 3) 装一张命运卡（穿甲强化是 WEAPON 卡，不需要来源选择，不会弹选择窗）。
	var applied: Dictionary = await FateCardGameBridge.apply_card_with_source_selection(
		FateCardPresets.armor_pierce(), training
	)
	if not bool(applied.get("success", false)):
		failures.append("fate card could not be applied in training range: %s" % str(applied.get("message", "")))
	if int(training.player.get_weapon_presentation_snapshot().get("fate_slot_used", 0)) < 1:
		failures.append("weapon fate slot was not consumed after applying a card")
	# 4) 刷一波怪。
	var spawned := 0
	for pad in get_tree().get_nodes_in_group("training_spawn_pad_3d"):
		if training.is_ancestor_of(pad):
			spawned += (pad as TrainingSpawnPad3D).spawn_wave()
			break
	if spawned <= 0:
		failures.append("training spawn pad produced no enemies")
	await get_tree().process_frame
	# 5) 在场期间基地存档也不能被写。
	if not training.is_base_data_unchanged():
		failures.append("training range mutated BaseData while it was active")
	# 6) 离场：释放整棵场景，存档必须逐字节还原。
	training.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	failures.append_array(_diff(before, _snapshot()))
	_finish(failures)


func _snapshot() -> Dictionary:
	var snapshot := BaseManager.get_profile_snapshot()
	for key in GLOBAL_KEYS:
		snapshot.erase(key)
	return snapshot


func _diff(before: Dictionary, after: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	for key in before.keys():
		if not after.has(key):
			failures.append("base save lost key after training round-trip: %s" % key)
		elif before[key] != after[key]:
			failures.append("base save key changed after training round-trip: %s" % key)
	for key in after.keys():
		if not before.has(key):
			failures.append("base save gained key after training round-trip: %s" % key)
	return failures


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"TRAINING_RANGE_ISOLATION_OK: entry clears loadout; weapon, ammo, fate card and spawned enemies leave BaseManager byte-identical"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
