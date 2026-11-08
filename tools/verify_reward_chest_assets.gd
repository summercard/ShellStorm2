extends Node
## 宝箱资产专用验证探针：只验 Blender Prefab 的运行时包装，不触碰奖励结算。

const VARIANTS := [
	{
		"name": "normal",
		"scene": "res://assets/art/items_weapons/props/reward_chests/runtime/prp_reward_chest_normal_root_top3d.tscn",
		"asset_id": "PRP-3D-REWARD-CHEST-NORMAL",
		"dimensions": Vector3(1.45, 1.18, 1.40),
	},
	{
		"name": "advanced",
		"scene": "res://assets/art/items_weapons/props/reward_chests/runtime/prp_reward_chest_advanced_root_top3d.tscn",
		"asset_id": "PRP-3D-REWARD-CHEST-ADVANCED",
		"dimensions": Vector3(1.74, 1.416, 1.68),
	},
]

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	for item in VARIANTS:
		await _verify_variant(item)
	_finish()


func _verify_variant(item: Dictionary) -> void:
	var packed := load(str(item["scene"])) as PackedScene
	_check(packed != null, "%s Prefab 无法加载" % item["name"])
	if packed == null:
		return
	var root := packed.instantiate() as RewardChestVisual3D
	_check(root != null, "%s 根节点不是 RewardChestVisual3D" % item["name"])
	if root == null:
		return
	add_child(root)
	await get_tree().process_frame
	root.refresh_handles()
	_check(root.get_meta("asset_id", "") == item["asset_id"], "%s AssetID 不匹配" % item["name"])
	_check(root.scale == Vector3.ONE, "%s 运行根 scale 不是 1" % item["name"])
	_check(root.visual_root != null, "%s 缺少 ChestVisual 句柄" % item["name"])
	_check(root.lid_pivot != null, "%s 缺少 LidPivot 句柄" % item["name"])
	_check(root.glow != null, "%s 缺少 ChestGlow 句柄" % item["name"])
	var dimensions: Vector3 = root.get_meta("dimensions_m", Vector3.ZERO)
	_check(dimensions.is_equal_approx(item["dimensions"]), "%s 包络尺寸不符：%s" % [item["name"], str(dimensions)])
	var model := root.get_node_or_null("ImportedModel")
	_check(model != null, "%s 缺少 ImportedModel" % item["name"])
	if model != null:
		var animation_player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_check(animation_player != null, "%s GLB 未导入 AnimationPlayer" % item["name"])
		if animation_player != null:
			var library := animation_player.get_animation_library("")
			_check(library != null, "%s 缺少默认动画库" % item["name"])
			if library != null:
				_check(library.has_animation("land"), "%s 缺少 land 动画" % item["name"])
				_check(library.has_animation("open"), "%s 缺少 open 动画" % item["name"])
	print("REWARD_CHEST_ASSET %s id=%s dimensions=%s root_scale=%s" % [item["name"], item["asset_id"], str(dimensions), str(root.scale)])
	root.queue_free()


func _finish() -> void:
	if failures.is_empty():
		print("REWARD_CHEST_ASSET_PROBE_OK 普通/高级 Prefab、节点句柄、尺寸、根缩放与 land/open 动画通过")
		get_tree().quit(0)
		return
	print("REWARD_CHEST_ASSET_PROBE_FAIL count=%d" % failures.size())
	for message in failures:
		print("  - %s" % message)
	get_tree().quit(1)
