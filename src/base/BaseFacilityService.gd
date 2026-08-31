class_name BaseFacilityService
extends RefCounted
## 无场景依赖的基地设施查询与命令规划。持久化仍由 BaseManager 统一提交。

const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")
const EnergyService = preload("res://src/base/BaseEnergyService.gd")


static func get_snapshot(facility_id: String, data: BaseData) -> Dictionary:
	var snapshot := FacilityCatalog.get_definition(facility_id)
	if snapshot.is_empty():
		return {
			"facility_id": facility_id,
			"available": false,
			"availability_reason": "未知设施",
			"summary": "配置缺失",
			"attention": true,
		}
	if data == null:
		snapshot.merge({
			"available": false,
			"availability_reason": "基地存档尚未就绪",
			"level": 0,
			"summary": "数据未就绪",
			"attention": true,
		}, true)
		return snapshot

	var level_property := str(snapshot.get("level_property", ""))
	var level := int(data.get(level_property)) if not level_property.is_empty() else 0
	snapshot["available"] = true
	snapshot["availability_reason"] = ""
	snapshot["level"] = level
	snapshot["attention"] = false

	match facility_id:
		"mission_operations":
			snapshot["summary"] = "4条路线 · 外部入口"
		"training_range":
			snapshot["summary"] = "全武器测试 · 不保存"
		"weapon_workshop":
			snapshot["summary"] = "蓝图 %d/%d/%d · Lv.%d" % [
				data.blueprint_gunbody_tier,
				data.blueprint_bullet_tier,
				data.blueprint_attachment_tier,
				level,
			]
		"vault":
			var capacity := 2 + data.vault_level
			snapshot["summary"] = "仓储 %d/%d · 带入 %d" % [
				data.vault_items.size(), capacity, data.pending_loadout_items.size()
			]
			snapshot["attention"] = not data.extraction_loot.is_empty()
		"monster_archive":
			snapshot["summary"] = "精英档案 · Lv.%d" % level
		"fate_collection":
			snapshot["summary"] = "48张牌 · 正/逆位"
		"base_vending":
			var vending_capacity := 2 + data.vault_level
			snapshot["summary"] = "6类常备货（含电池）· 仓储 %d/%d" % [
				data.vault_items.size(), vending_capacity
			]
			snapshot["attention"] = data.vault_items.size() >= vending_capacity
		"base_recovery":
			var energy := EnergyService.get_snapshot(
				data, data.world_time_elapsed_game_seconds
			)
			snapshot["summary"] = "基地电量 %.0f/%.0f · +%.0f/游戏时" % [
				float(energy.get("current", 0.0)),
				float(energy.get("capacity", 100.0)),
				float(energy.get("regen_per_game_hour", 0.0)),
			]
			snapshot["attention"] = float(energy.get("ratio", 0.0)) <= 0.25
		"avatar_wardrobe":
			snapshot["summary"] = "6类外观组件 · 每类至少3款"
			snapshot["attention"] = false
		_:
			snapshot["summary"] = str(snapshot.get("description", "设施可用"))
	return snapshot


static func get_all_snapshots(data: BaseData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in FacilityCatalog.all_definitions():
		result.append(get_snapshot(str(definition.get("facility_id", "")), data))
	return result


static func apply_upgrade(facility_id: String, data: BaseData, upgrade_cost: int) -> Dictionary:
	var definition := FacilityCatalog.get_definition(facility_id)
	if definition.is_empty():
		return {"success": false, "reason": "未知设施"}
	var level_property := str(definition.get("level_property", ""))
	if level_property.is_empty():
		return {"success": false, "reason": "该设施没有等级升级"}
	if upgrade_cost <= 0:
		return {"success": false, "reason": "升级费用配置无效"}
	if data.extraction_points < upgrade_cost:
		return {"success": false, "reason": "魂不足"}

	var old_level := int(data.get(level_property))
	var old_points := data.extraction_points
	data.extraction_points -= upgrade_cost
	data.set(level_property, old_level + 1)
	return {
		"success": true,
		"facility_id": facility_id,
		"level_property": level_property,
		"old_level": old_level,
		"new_level": old_level + 1,
		"old_points": old_points,
		"new_points": data.extraction_points,
		"cost": upgrade_cost,
	}


static func rollback_upgrade(result: Dictionary, data: BaseData) -> void:
	if not bool(result.get("success", false)) or data == null:
		return
	data.extraction_points = int(result.get("old_points", data.extraction_points))
	var level_property := str(result.get("level_property", ""))
	if not level_property.is_empty():
		data.set(level_property, int(result.get("old_level", 0)))
