extends Node
## 收租转移独立验收：不启动整张关卡，只验证资源、模型工厂和纯视觉事务边界。

const TRANSFER_SCRIPT := preload("res://src/world3d/EliteRentTransfer3D.gd")
const TRAIL_SCRIPT := preload("res://src/world3d/EliteRentTransferTrail3D.gd")
const TRANSFER_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_elite_rent_transfer_trail_root_top3d.tscn")

var _failures: Array[String] = []

func _ready() -> void:
	_check(TRANSFER_SCRIPT != null, "EliteRentTransfer3D 脚本可加载")
	_check(TRAIL_SCRIPT != null, "EliteRentTransferTrail3D 脚本可加载")
	_check(TRANSFER_SCENE != null, "正式拖尾 Prefab 可加载")
	_check(TRANSFER_SCRIPT.TRANSFER_ASSET_ID == "VFX-ELITE-RENT-TRANSFER-3D", "转移实体 AssetID 固定")
	_check(TRAIL_SCRIPT.TRAIL_ASSET_ID == "VFX-ELITE-RENT-TRANSFER-TRAIL-3D", "拖尾 AssetID 固定")
	_check(not TRANSFER_SCRIPT.TRANSFER_ASSET_ID.is_empty(), "转移实体 AssetID 非空")
	_check(not TRAIL_SCRIPT.TRAIL_ASSET_ID.is_empty(), "拖尾 AssetID 非空")
	var item := {
		"id": "item_health_potion",
		"type": "consumable",
		"use_action": "heal",
		"name": "治疗药剂",
		"count": 1,
		"stack_max": 4,
	}
	var model := ItemModelFactory3D.create_model(item, ItemModelFactory3D.get_item_color(item), ItemModelFactory3D.MODEL_ROLE_GROUND)
	_check(model != null, "真实 ItemModelFactory3D 可创建转移物品模型")
	_check(ItemModelFactory3D.count_mesh_instances(model) > 0, "转移物品模型包含网格")
	var transfer := TRANSFER_SCRIPT.new() as Node
	_check(transfer != null and transfer is Node3D, "转移实体是独立 Node3D")
	_check(transfer != null and not transfer.has_method("accept_pickup"), "转移实体不复用 GroundLoot 拾取事务")
	_check(transfer != null and transfer.has_method("get_visual_snapshot"), "转移实体提供视觉快照")
	if transfer != null:
		add_child(transfer)
		transfer.call("configure", item, Vector3.ZERO, Vector3(1.5, 1.0, 0.0))
		transfer.call("begin")
		await get_tree().process_frame
		var snapshot: Dictionary = transfer.call("get_visual_snapshot")
		_check(bool(snapshot.get("is_pure_visual", false)), "运行时转移实体标记为纯视觉")
		_check(not bool(snapshot.get("uses_ground_loot_transaction", true)), "运行时转移实体不启用地面拾取事务")
		_check(transfer.get_node_or_null("PrivateRentTransferTrail") != null, "运行时转移实体挂载私有拖尾")
		transfer.queue_free()
	model.free()
	if _failures.is_empty():
		print("ELITE_RENT_TRANSFER_VERIFY_PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("ELITE_RENT_TRANSFER_VERIFY_FAIL count=%d" % _failures.size())
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
	else:
		print("PASS %s" % message)
