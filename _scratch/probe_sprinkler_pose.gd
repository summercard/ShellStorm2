extends Node

## 一次性探针（_scratch）：套件里的姿势门禁被并行改动挡住时，单独确认
## 花洒机枪走的是长枪姿势与机枪抖动风格，而不是掉进 unarmed 或 sidearm。

func _ready() -> void:
	var scene := load("res://scenes/Player3D.tscn") as PackedScene
	if scene == null:
		push_error("Player3D.tscn 无法加载（依赖链编译失败）")
		get_tree().quit(1)
		return
	var player := scene.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	if not player.equip_weapon("bp_sprinkler", "mod_bullet_standard"):
		push_error("equip_weapon(bp_sprinkler) 失败")
		get_tree().quit(1)
		return
	for _frame in 3:
		await get_tree().process_frame
	var snapshot: Dictionary = player.avatar.get_component_snapshot()
	var style := str(snapshot.get("weapon_fire_style", ""))
	var gun_id := str(player.get_weapon_snapshot().get("gun_id", ""))
	print("PROBE pose gun_id=", gun_id, " fire_style=", style)
	if gun_id != "bp_sprinkler":
		push_error("装备后 gun_id 是 %s" % gun_id)
		get_tree().quit(1)
		return
	if style != "machinegun_rattle":
		push_error("花洒机枪的 fire_style 是 %s，期望 machinegun_rattle" % style)
		get_tree().quit(1)
		return
	print("SCRATCH_SPRINKLER_POSE_OK: 花洒机枪装备后走长枪姿势，fire_style 与蜂窝机枪同为 machinegun_rattle")
	get_tree().quit(0)
