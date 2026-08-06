class_name BaseFacilityCatalog
extends RefCounted
## 正式基地设施的唯一静态目录。场景和菜单只保存 facility_id。

const ACTION_INFO := "info"
const ACTION_MENU := "menu"
const ACTION_SCENE := "scene"

const DEFINITIONS: Array[Dictionary] = [
	{
		"facility_id": "mission_operations",
		"display_name": "远征情报室",
		"description": "查看野外道路情报；副本必须从基地外入口进入",
		"action_kind": ACTION_INFO,
		"action_path": "",
		"legacy_building_type": -1,
		"level_property": "",
		"color": Color(0.88, 0.48, 0.18),
	},
	{
		"facility_id": "training_range",
		"display_name": "地下训练靶场",
		"description": "隔离测试枪身、弹药与组合；离场不保留配置",
		"action_kind": ACTION_SCENE,
		"action_path": "res://scenes/TrainingRange3D.tscn",
		"legacy_building_type": -1,
		"level_property": "",
		"color": Color(0.28, 0.76, 0.70),
	},
	{
		"facility_id": "weapon_workshop",
		"display_name": "枪械工坊",
		"description": "解锁枪身、弹药与配件蓝图",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/WorkshopMenu.tscn",
		"legacy_building_type": 0,
		"level_property": "workshop_level",
		"color": Color(0.75, 0.42, 0.16),
	},
	{
		"facility_id": "fate_divination",
		"display_name": "命运占卜屋",
		"description": "为下一次行动准备命运预兆",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/DivinationMenu.tscn",
		"legacy_building_type": 3,
		"level_property": "divination_level",
		"color": Color(0.55, 0.31, 0.78),
	},
	{
		"facility_id": "vault",
		"display_name": "保险柜",
		"description": "管理撤离物资与下局带入",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/VaultMenu.tscn",
		"legacy_building_type": 4,
		"level_property": "vault_level",
		"color": Color(0.24, 0.58, 0.72),
	},
	{
		"facility_id": "monster_archive",
		"display_name": "怪物档案室",
		"description": "查看成长中的精英与悬赏情报",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/MonsterArchiveMenu.tscn",
		"legacy_building_type": 6,
		"level_property": "archive_level",
		"color": Color(0.48, 0.65, 0.26),
	},
	{
		"facility_id": "fate_collection",
		"display_name": "命运卡收藏室",
		"description": "浏览已发现的命运卡片与正逆位",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/FateCardCollectionMenu.tscn",
		"legacy_building_type": -1,
		"level_property": "",
		"color": Color(0.72, 0.28, 0.58),
	},
	{
		"facility_id": "base_console",
		"display_name": "基地管理终端",
		"description": "处理战利品、设施升级与长期总览",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/BaseMenu.tscn",
		"legacy_building_type": -1,
		"level_property": "",
		"color": Color(0.28, 0.52, 0.68),
	},
	{
		"facility_id": "base_vending",
		"display_name": "自动贩卖机",
		"description": "购买基础枪械、初级背包与药水；出售保险柜物品",
		"action_kind": ACTION_MENU,
		"action_path": "res://scenes/BaseVendingMenu.tscn",
		"legacy_building_type": -1,
		"level_property": "",
		"color": Color(0.16, 0.78, 0.88),
	},
]


static func all_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in DEFINITIONS:
		result.append(definition.duplicate(true))
	return result


static func get_definition(facility_id: String) -> Dictionary:
	for definition in DEFINITIONS:
		if str(definition.get("facility_id", "")) == facility_id:
			return definition.duplicate(true)
	return {}


static func has_facility(facility_id: String) -> bool:
	return not get_definition(facility_id).is_empty()
