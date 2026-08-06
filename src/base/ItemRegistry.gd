class_name ItemRegistry
extends RefCounted
## 物品注册表 — 全局游戏物品定义
## 提供所有可获取物品的数据模板，供掉落系统、背包、商人使用
## 不负责堆叠/格子等运行时数据，只提供静态物品定义

## 单例引用
static var _instance: ItemRegistry = null
static func get_instance() -> ItemRegistry:
	if _instance == null:
		_instance = ItemRegistry.new()
	return _instance

## 物品字典：item_id -> item_definition
var _items: Dictionary = {}

func _init() -> void:
	_register_all_items()

## 注册所有内置物品
func _register_all_items() -> void:
	_register_beacon_item()
	_register_room_key_item()
	_register_backpack_equipment()
	_register_weapon_modules()
	_register_consumables()

## 注册信标道具
func _register_beacon_item() -> void:
	_items["item_beacon"] = {
		"id": "item_beacon",
		"name": "撤离信标",
		"description": "消耗此道具召唤紧急撤离点。读条期间会刷出追击怪物。",
		"type": "consumable",
		"rarity": "rare",
		"stack_max": 3,
		"tags": ["extraction", "consumable", "beacon"],
		"use_action": "summon_beacon_extraction",
		"floor_loot_weights": {
			"loot_floor_1_2": 1.0,
			"loot_floor_3_4": 1.5,
			"loot_floor_5": 2.0,
			"loot_abyss": 2.5,
			"boss_floor_1": 3.0,
			"boss_floor_2": 4.0,
			"scavenge_floor_1": 0.8,
			"scavenge_floor_2": 1.0,
			"scavenge_floor_3": 1.2,
			"scavenge_floor_4": 1.5,
			"scavenge_floor_5": 1.8,
			"elite_floor_1": 1.5,
			"elite_floor_2": 1.5,
			"combat_floor_4": 0.8,
			"combat_floor_5": 1.2,
		},
		"merchant_tier": 2,
		"price": 150,
	}

func _register_room_key_item() -> void:
	_items["item_room_key"] = {
		"id": "item_room_key",
		"name": "房间钥匙",
		"description": "用于开启地图上的一扇房门。来自怪物掉落或房间搜索。",
		"type": "key",
		"rarity": "common",
		"stack_max": 9,
		"tags": ["key", "progression"],
		"floor_loot_weights": {
			"loot_common": 1.0,
			"loot_floor_1_2": 1.8,
			"scavenge_floor_1": 2.4,
			"scavenge_floor_2": 2.0,
			"combat_floor_1": 1.2,
			"elite_floor_1": 1.0,
			"elite_floor_2": 1.0,
		},
	}


func _register_backpack_equipment() -> void:
	var backpacks: Array[Dictionary] = [
		{
			"id": "equipment_backpack_2",
			"name": "轻型腰包",
			"description": "装备后增加2个背包格。可从搜索容器或普通怪物身上获得。",
			"type": "equipment",
			"subtype": "backpack",
			"rarity": "common",
			"stack_max": 1,
			"extra_slots": 2,
			"tags": ["equipment", "backpack", "capacity"],
			"floor_loot_weights": {
				"loot_common": 0.22,
				"loot_floor_1_2": 0.50,
				"scavenge_floor_1": 1.20,
				"scavenge_floor_2": 0.90,
				"combat_floor_1": 0.28,
				"combat_floor_2": 0.20,
			},
			"price": 55,
			"merchant_tier": 1,
		},
		{
			"id": "equipment_backpack_4",
			"name": "战术背包",
			"description": "装备后增加4个背包格。主要来自中层搜索与精英怪物。",
			"type": "equipment",
			"subtype": "backpack",
			"rarity": "uncommon",
			"stack_max": 1,
			"extra_slots": 4,
			"tags": ["equipment", "backpack", "capacity"],
			"floor_loot_weights": {
				"loot_floor_1_2": 0.16,
				"loot_floor_3_4": 0.65,
				"scavenge_floor_2": 0.35,
				"scavenge_floor_3": 1.00,
				"scavenge_floor_4": 0.80,
				"elite_floor_1": 0.85,
				"elite_floor_2": 0.55,
				"combat_floor_3": 0.22,
			},
			"price": 120,
			"merchant_tier": 2,
		},
		{
			"id": "equipment_backpack_8",
			"name": "远征背包",
			"description": "装备后增加8个背包格。主要来自深层搜索、精英与Boss。",
			"type": "equipment",
			"subtype": "backpack",
			"rarity": "rare",
			"stack_max": 1,
			"extra_slots": 8,
			"tags": ["equipment", "backpack", "capacity"],
			"floor_loot_weights": {
				"loot_floor_5": 0.55,
				"loot_abyss": 0.85,
				"scavenge_floor_4": 0.25,
				"scavenge_floor_5": 0.90,
				"elite_floor_2": 0.75,
				"boss_floor_1": 1.25,
				"boss_floor_2": 1.80,
			},
			"price": 260,
			"merchant_tier": 3,
		},
	]
	for backpack in backpacks:
		_items[str(backpack["id"])] = backpack

## 注册武器模块类（蓝图类，玩家获得后可在基地解锁）
func _register_weapon_modules() -> void:
	# Tier 0 — 基础（总是可用）
	_register_weapon_drops()
	_register_gunbody_tier0()
	# Tier 1 — 解锁后追加
	_register_gunbody_tier1()
	_register_bullet_tier0()
	_register_bullet_tier1()
	_register_attachment_tier0()
	_register_attachment_tier1()

func _register_weapon_drops() -> void:
	var weapons: Array = [
		{
			"id": "weapon_pistol",
			"assembly_id": "bp_pistol",
			"name": "豌豆手枪",
			"description": "可靠的基础半自动武器。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "common",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "pistol"],
			"floor_loot_weights": {
				"loot_floor_1_2": 0.8,
				"scavenge_floor_1": 0.8,
				"scavenge_floor_2": 1.4,
				"combat_floor_1": 0.5,
				"combat_floor_2": 0.8,
			},
			"price": 70,
		},
		{
			"id": "weapon_shotgun",
			"assembly_id": "bp_shotgun",
			"name": "散射喷壶",
			"description": "近距离多弹丸散射武器。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "uncommon",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "shotgun"],
			"floor_loot_weights": {
				"spawn_starter": 3.0,
				"loot_floor_1_2": 1.0,
				"scavenge_floor_1": 1.4,
				"scavenge_floor_2": 2.0,
				"combat_floor_1": 0.8,
				"combat_floor_2": 1.2,
			},
			"price": 110,
		},
		{
			"id": "weapon_rifle",
			"assembly_id": "bp_rifle",
			"name": "步枪",
			"description": "稳定连发的中距离武器。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "rare",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "rifle"],
			"price": 150,
			"loot_table_tier": 1,
			"floor_loot_weights": {
				"loot_floor_1_2": 0.3,
				"loot_floor_3_4": 1.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 2.5,
				"boss_floor_1": 2.0,
				"boss_floor_2": 3.0,
				"scavenge_floor_3": 1.0,
				"scavenge_floor_4": 1.5,
				"scavenge_floor_5": 2.0,
				"combat_floor_1": 0.5,
				"combat_floor_2": 1.0,
				"combat_floor_3": 1.5,
				"elite_floor_1": 1.5,
				"elite_floor_2": 2.0,
			},
		},
		{
			"id": "weapon_machinegun",
			"assembly_id": "bp_machinegun",
			"name": "蜂窝机枪",
			"description": "高射速压制武器，适合清群怪。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "uncommon",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "auto"],
			"price": 180,
			"loot_table_tier": 1,
			"floor_loot_weights": {
				"loot_floor_1_2": 1.0,
				"loot_floor_3_4": 1.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 2.5,
				"scavenge_floor_1": 0.5,
				"scavenge_floor_2": 1.0,
				"scavenge_floor_3": 1.2,
				"scavenge_floor_4": 1.5,
				"scavenge_floor_5": 2.5,
				"combat_floor_1": 0.8,
				"combat_floor_2": 1.2,
				"combat_floor_3": 1.5,
				"elite_floor_1": 1.5,
				"elite_floor_2": 2.5,
			},
		},
		{
			"id": "weapon_sniper",
			"assembly_id": "bp_sniper",
			"name": "弹弓狙击",
			"description": "低射速高伤害，穿透力强，适合精准打击。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "rare",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "sniper"],
			"price": 220,
			"loot_table_tier": 2,
			"floor_loot_weights": {
				"loot_floor_3_4": 0.5,
				"loot_floor_5": 1.5,
				"loot_abyss": 2.5,
				"boss_floor_1": 2.0,
				"boss_floor_2": 4.0,
				"scavenge_floor_3": 0.5,
				"scavenge_floor_4": 1.0,
				"scavenge_floor_5": 2.0,
				"combat_floor_2": 0.3,
				"combat_floor_3": 0.8,
				"elite_floor_1": 1.5,
				"elite_floor_2": 2.0,
			},
		},
		{
			"id": "weapon_launcher",
			"assembly_id": "bp_launcher",
			"name": "反胃榴弹筒",
			"description": "发射爆炸弹，抛物线弹道，大范围AOE。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "rare",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "launcher"],
			"price": 250,
			"loot_table_tier": 2,
			"floor_loot_weights": {
				"loot_floor_3_4": 1.0,
				"loot_floor_5": 1.5,
				"loot_abyss": 2.5,
				"boss_floor_1": 2.5,
				"boss_floor_2": 4.0,
				"scavenge_floor_3": 0.5,
				"scavenge_floor_4": 1.0,
				"scavenge_floor_5": 2.0,
				"combat_floor_3": 0.8,
				"combat_floor_4": 0.5,
				"combat_floor_5": 1.0,
				"elite_floor_2": 3.0,
			},
		},
		{
			"id": "weapon_charge",
			"assembly_id": "bp_charge",
			"name": "蓄力萝卜炮",
			"description": "蓄力时间越长伤害越高，超蓄力后弹体变大并附带穿透。左键装备为当前主武器。",
			"type": "weapon",
			"subtype": "gun_body",
			"rarity": "epic",
			"stack_max": 1,
			"tags": ["weapon", "gun_body", "charge"],
			"price": 350,
			"loot_table_tier": 3,
			"floor_loot_weights": {
				"loot_floor_5": 0.8,
				"loot_abyss": 2.0,
				"boss_floor_2": 4.0,
				"scavenge_floor_4": 0.4,
				"scavenge_floor_5": 1.0,
				"combat_floor_4": 0.5,
				"combat_floor_5": 1.0,
				"elite_floor_2": 3.0,
			},
		},
	]
	for weapon in weapons:
		_items[weapon["id"]] = weapon

func _register_gunbody_tier0() -> void:
	# 基础枪身蓝图（Tier 0，初始可用）
	var gun_bodies: Array = [
		{
			"id": "bp_pistol",
			"name": "豌豆手枪蓝图碎片",
			"description": "使用后解锁豌豆手枪蓝图，并获得 20 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "common",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body"],
			"price": 50,
			"loot_table_tier": 0,
			"merchant_tier": 0,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 0,
			"extraction_points_reward": 20,
			"floor_loot_weights": {
				"loot_floor_1_2": 3.0,
				"loot_floor_3_4": 2.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 1.5,
				"loot_common": 1.0,
				"spawn_starter": 4.0,
				"scavenge_floor_1": 2.5,
				"scavenge_floor_2": 1.8,
				"combat_floor_1": 1.5,
				"combat_floor_2": 1.0,
			},
		},
		{
			"id": "bp_shotgun",
			"name": "散射喷壶蓝图碎片",
			"description": "使用后解锁散射喷壶蓝图，并获得 25 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "common",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body", "shotgun"],
			"price": 60,
			"loot_table_tier": 0,
			"merchant_tier": 0,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 0,
			"extraction_points_reward": 25,
			"floor_loot_weights": {
				"loot_floor_1_2": 2.5,
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 1.5,
				"loot_abyss": 1.0,
				"loot_common": 1.0,
				"spawn_starter": 3.5,
				"scavenge_floor_1": 2.0,
				"scavenge_floor_2": 1.5,
				"combat_floor_1": 1.0,
				"combat_floor_2": 0.5,
			},
		},
	]
	for bp in gun_bodies:
		_items[bp["id"]] = bp

func _register_gunbody_tier1() -> void:
	# 进阶枪身蓝图（Tier 1+，蓝图Tier >= 1 时可用）
	var gun_bodies: Array = [
		{
			"id": "bp_rifle",
			"name": "步枪蓝图碎片",
			"description": "使用后解锁步枪蓝图，并获得 35 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "uncommon",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body", "rifle"],
			"price": 80,
			"loot_table_tier": 1,
			"merchant_tier": 1,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 1,
			"extraction_points_reward": 35,
			"floor_loot_weights": {
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 2.5,
				"loot_abyss": 3.0,
				"boss_floor_1": 3.0,
				"loot_common": 1.0,
				"spawn_starter": 2.0,
				"scavenge_floor_3": 1.5,
				"scavenge_floor_4": 2.0,
				"combat_floor_1": 1.5,
				"combat_floor_2": 1.0,
				"combat_floor_3": 0.8,
			},
		},
		{
			"id": "bp_machinegun",
			"name": "蜂窝机枪蓝图碎片",
			"description": "使用后解锁蜂窝机枪蓝图，并获得 40 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "uncommon",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body", "auto"],
			"price": 90,
			"loot_table_tier": 1,
			"merchant_tier": 1,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 1,
			"extraction_points_reward": 40,
			"floor_loot_weights": {
				"loot_floor_3_4": 1.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 2.5,
				"scavenge_floor_3": 1.5,
				"scavenge_floor_4": 2.0,
				"scavenge_floor_5": 2.5,
				"combat_floor_1": 0.8,
				"combat_floor_2": 0.5,
			},
		},
		{
			"id": "bp_sniper",
			"name": "弹弓狙击蓝图碎片",
			"description": "使用后解锁弹弓狙击蓝图，并获得 50 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "rare",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body", "sniper"],
			"price": 120,
			"loot_table_tier": 2,
			"merchant_tier": 2,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 2,
			"extraction_points_reward": 50,
			"floor_loot_weights": {
				"loot_floor_5": 2.0,
				"loot_abyss": 3.0,
				"boss_floor_1": 4.0,
				"boss_floor_2": 5.0,
				"scavenge_floor_5": 1.5,
				"combat_floor_3": 1.5,
				"combat_floor_4": 2.0,
				"combat_floor_5": 2.5,
				"loot_common": 0.5,
				"spawn_starter": 1.0,
			},
		},
		{
			"id": "bp_launcher",
			"name": "反胃榴弹筒蓝图碎片",
			"description": "使用后解锁反胃榴弹筒蓝图，并获得 55 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "rare",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body", "launcher"],
			"price": 130,
			"loot_table_tier": 2,
			"merchant_tier": 2,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 2,
			"extraction_points_reward": 55,
			"floor_loot_weights": {
				"loot_abyss": 2.5,
				"boss_floor_1": 3.0,
				"boss_floor_2": 4.0,
				"scavenge_floor_5": 1.0,
				"combat_floor_3": 0.5,
				"combat_floor_4": 0.3,
			},
		},
		{
			"id": "bp_charge",
			"name": "蓄力萝卜炮蓝图碎片",
			"description": "使用后解锁蓄力萝卜炮蓝图，并获得 80 资源点",
			"type": "blueprint",
			"subtype": "gun_body",
			"rarity": "epic",
			"stack_max": 99,
			"tags": ["blueprint", "gun_body", "charge"],
			"price": 200,
			"loot_table_tier": 3,
			"merchant_tier": 3,
			"use_action": "unlock_blueprint",
			"blueprint_category": "gunbody",
			"blueprint_loot_tier": 3,
			"extraction_points_reward": 80,
			"floor_loot_weights": {
				"loot_abyss": 2.0,
				"boss_floor_2": 4.0,
				"scavenge_floor_5": 0.5,
				"combat_floor_4": 0.5,
				"combat_floor_5": 1.0,
			},
		},
	]
	for bp in gun_bodies:
		_items[bp["id"]] = bp

## 注册消耗品
func _register_consumables() -> void:
	var consumables: Array = [
		{
			"id": "item_health_potion",
			"name": "治疗药水",
			"description": "恢复 30 点生命值",
			"type": "consumable",
			"rarity": "common",
			"stack_max": 5,
			"tags": ["consumable", "healing"],
			"use_action": "heal",
			"heal_amount": 30,
			"floor_loot_weights": {
				"loot_common": 2.0,
				"loot_floor_1_2": 2.0,
				"loot_floor_3_4": 1.5,
				"spawn_starter": 2.0,
				"combat_floor_1": 1.5,
				"combat_floor_2": 2.0,
				"combat_floor_3": 1.0,
			},
			"price": 40,
		},
		{
			"id": "item_ammo_pack",
			"name": "弹药包",
			"description": "额外弹药补给",
			"type": "consumable",
			"rarity": "common",
			"stack_max": 5,
			"tags": ["consumable", "ammo"],
			"use_action": "refill_ammo",
			"floor_loot_weights": {
				"loot_common": 1.5,
				"loot_floor_1_2": 2.5,
				"spawn_starter": 2.0,
				"combat_floor_1": 2.0,
				"combat_floor_2": 2.5,
				"combat_floor_3": 2.0,
				"combat_floor_4": 2.5,
				"combat_floor_5": 2.0,
			},
			"price": 30,
		},
	]
	for c in consumables:
		_items[c["id"]] = c

func _register_bullet_tier0() -> void:
	var bullets: Array = [
		{
			"id": "mod_bullet_standard",
			"name": "标准子弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "common",
			"stack_max": 10,
			"tags": ["module", "bullet"],
			"price": 30,
			"loot_table_tier": 0,
					"merchant_tier": 0,
			"floor_loot_weights": {
				"loot_floor_1_2": 3.0,
				"loot_floor_3_4": 2.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 1.5,
				"spawn_starter": 3.0,
				"scavenge_floor_1": 3.0,
				"scavenge_floor_2": 2.5,
				"combat_floor_1": 3.0,
				"combat_floor_2": 2.5,
			},
		},
		{
			"id": "mod_bullet_sticky",
			"name": "黏黏弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "uncommon",
			"stack_max": 10,
			"tags": ["module", "bullet", "sticky"],
			"price": 50,
			"loot_table_tier": 0,
					"merchant_tier": 1,
			"floor_loot_weights": {
				"loot_floor_1_2": 2.0,
				"loot_floor_3_4": 2.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 1.5,
				"spawn_starter": 2.0,
				"scavenge_floor_1": 2.0,
				"scavenge_floor_2": 2.5,
				"combat_floor_1": 2.0,
				"combat_floor_2": 2.5,
			},
		},
		{
			"id": "mod_bullet_bounce",
			"name": "回旋镖弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "uncommon",
			"stack_max": 10,
			"tags": ["module", "bullet", "bounce"],
			"price": 60,
			"loot_table_tier": 0,
					"merchant_tier": 1,
			"floor_loot_weights": {
				"loot_floor_1_2": 1.5,
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 2.5,
				"loot_abyss": 2.0,
				"spawn_starter": 1.5,
				"scavenge_floor_1": 1.5,
				"scavenge_floor_2": 2.0,
				"combat_floor_1": 1.5,
				"combat_floor_2": 2.0,
			},
		},
	]
	for b in bullets:
		_items[b["id"]] = b

func _register_bullet_tier1() -> void:
	var bullets: Array = [
		{
			"id": "mod_bullet_piercing",
			"name": "穿甲弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "rare",
			"stack_max": 10,
			"tags": ["module", "bullet", "piercing"],
			"price": 80,
			"loot_table_tier": 1,
					"merchant_tier": 2,
			"floor_loot_weights": {
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 2.5,
				"loot_abyss": 3.0,
				"scavenge_floor_3": 2.0,
				"scavenge_floor_4": 2.5,
				"scavenge_floor_5": 3.0,
				"combat_floor_3": 1.5,
			},
		},
		{
			"id": "mod_bullet_explosive",
			"name": "爆炸弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "rare",
			"stack_max": 10,
			"tags": ["module", "bullet", "explosive"],
			"price": 100,
			"loot_table_tier": 1,
					"merchant_tier": 2,
			"floor_loot_weights": {
				"loot_floor_3_4": 1.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 2.5,
				"scavenge_floor_3": 1.5,
				"scavenge_floor_4": 2.0,
				"scavenge_floor_5": 2.5,
				"combat_floor_3": 1.0,
			},
		},
		{
			"id": "mod_bullet_homing",
			"name": "蜂卵弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "epic",
			"stack_max": 10,
			"tags": ["module", "bullet", "homing", "summon"],
			"price": 150,
			"loot_table_tier": 2,
					"merchant_tier": 3,
			"floor_loot_weights": {
				"loot_floor_5": 2.0,
				"loot_abyss": 3.0,
				"boss_floor_1": 4.0,
				"scavenge_floor_4": 2.0,
				"scavenge_floor_5": 3.0,
				"combat_floor_4": 1.5,
				"combat_floor_5": 2.5,
			},
		},
		{
			"id": "mod_bullet_blackhole",
			"name": "黑洞弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "epic",
			"stack_max": 10,
			"tags": ["module", "bullet", "blackhole", "pull"],
			"price": 180,
			"loot_table_tier": 2,
					"merchant_tier": 3,
			"floor_loot_weights": {
				"loot_abyss": 2.5,
				"boss_floor_1": 3.0,
				"boss_floor_2": 4.0,
				"scavenge_floor_4": 2.5,
				"scavenge_floor_5": 4.0,
				"combat_floor_4": 2.0,
				"combat_floor_5": 3.0,
			},
		},
		{
			"id": "mod_bullet_balloon",
			"name": "气球弹模块",
			"type": "module",
			"subtype": "bullet",
			"rarity": "rare",
			"stack_max": 10,
			"tags": ["module", "bullet", "balloon", "slow"],
			"price": 90,
			"loot_table_tier": 1,
					"merchant_tier": 2,
			"floor_loot_weights": {
				"loot_floor_3_4": 1.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 2.0,
				"scavenge_floor_3": 1.5,
				"scavenge_floor_4": 2.0,
				"scavenge_floor_5": 2.0,
				"combat_floor_3": 1.0,
				"combat_floor_4": 1.5,
			},
		},
	]
	for b in bullets:
		_items[b["id"]] = b

func _register_attachment_tier0() -> void:
	var attachments: Array = [
		{
			"id": "attach_triple_muzzle",
			"name": "三叉枪口",
			"type": "attachment",
			"subtype": "muzzle",
			"rarity": "uncommon",
			"stack_max": 5,
			"tags": ["attachment", "muzzle", "multi_shot"],
			"price": 70,
			"loot_table_tier": 0,
					"merchant_tier": 1,
			"floor_loot_weights": {
				"loot_floor_1_2": 2.5,
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 1.5,
				"loot_abyss": 1.0,
				"spawn_starter": 2.5,
				"scavenge_floor_1": 2.5,
				"scavenge_floor_2": 2.0,
				"scavenge_floor_3": 1.5,
				"scavenge_floor_4": 1.0,
				"combat_floor_1": 2.0,
				"combat_floor_2": 1.5,
			},
		},
		{
			"id": "attach_rubber_stock",
			"name": "橡皮枪托",
			"type": "attachment",
			"subtype": "stock",
			"rarity": "common",
			"stack_max": 5,
			"tags": ["attachment", "stock", "bounce"],
			"price": 45,
			"loot_table_tier": 0,
					"merchant_tier": 0,
			"floor_loot_weights": {
				"loot_floor_1_2": 3.0,
				"loot_floor_3_4": 2.5,
				"loot_floor_5": 2.0,
				"loot_abyss": 1.5,
				"spawn_starter": 3.0,
				"scavenge_floor_1": 3.0,
				"scavenge_floor_2": 2.5,
				"scavenge_floor_3": 2.0,
				"scavenge_floor_4": 1.5,
				"combat_floor_1": 2.5,
				"combat_floor_2": 2.0,
			},
		},
	]
	for a in attachments:
		_items[a["id"]] = a

func _register_attachment_tier1() -> void:
	var attachments: Array = [
		{
			"id": "attach_scope",
			"name": "放大镜瞄具",
			"type": "attachment",
			"subtype": "scope",
			"rarity": "rare",
			"stack_max": 5,
			"tags": ["attachment", "scope", "crit"],
			"price": 100,
			"loot_table_tier": 1,
					"merchant_tier": 2,
			"floor_loot_weights": {
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 2.5,
				"loot_abyss": 3.0,
				"scavenge_floor_3": 2.0,
				"scavenge_floor_4": 2.5,
				"scavenge_floor_5": 3.0,
				"combat_floor_2": 1.5,
				"combat_floor_3": 2.5,
			},
		},
		{
			"id": "attach_big_mag",
			"name": "肉质弹匣",
			"type": "attachment",
			"subtype": "magazine",
			"rarity": "uncommon",
			"stack_max": 5,
			"tags": ["attachment", "magazine", "heal"],
			"price": 80,
			"loot_table_tier": 1,
					"merchant_tier": 1,
			"floor_loot_weights": {
				"loot_floor_3_4": 2.0,
				"loot_floor_5": 2.5,
				"loot_abyss": 2.0,
				"scavenge_floor_3": 2.0,
				"scavenge_floor_4": 2.5,
				"scavenge_floor_5": 2.0,
				"combat_floor_1": 2.5,
				"combat_floor_2": 3.0,
			},
		},
		{
			"id": "attach_fan",
			"name": "小风扇",
			"type": "attachment",
			"subtype": "external",
			"rarity": "epic",
			"stack_max": 3,
			"tags": ["attachment", "external", "pull"],
			"price": 150,
			"loot_table_tier": 2,
					"merchant_tier": 3,
			"floor_loot_weights": {
				"loot_floor_5": 2.0,
				"loot_abyss": 2.5,
				"boss_floor_1": 3.0,
				"scavenge_floor_4": 2.0,
				"scavenge_floor_5": 2.5,
				"combat_floor_3": 1.5,
				"combat_floor_4": 2.0,
				"combat_floor_5": 2.5,
			},
		},
		{
			"id": "attach_copy_sticker",
			"name": "复制贴纸",
			"type": "attachment",
			"subtype": "mutator",
			"rarity": "epic",
			"stack_max": 3,
			"tags": ["attachment", "mutator", "copy"],
			"price": 200,
			"loot_table_tier": 2,
					"merchant_tier": 3,
			"floor_loot_weights": {
				"loot_abyss": 2.0,
				"boss_floor_1": 3.0,
				"boss_floor_2": 4.0,
				"scavenge_floor_4": 2.0,
				"scavenge_floor_5": 3.0,
				"combat_floor_3": 1.0,
				"combat_floor_4": 1.5,
				"combat_floor_5": 2.0,
			},
		},
	]
	for a in attachments:
		_items[a["id"]] = a

## 检查物品是否存在
func has_item(item_id: String) -> bool:
	return _items.has(item_id)

## 获取所有物品列表
func get_all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _items.values():
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result

## 按类型获取物品
func get_items_by_type(item_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _items.values():
		if item.get("type") == item_type:
			result.append(item)
	return result

## 按标签获取物品
func get_items_by_tag(tag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _items.values():
		if tag in item.get("tags", []):
			result.append(item)
	return result

## 获取掉落池（根据掉落表名称返回一组物品）
func get_loot_table(table_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _items.values():
		var weights: Dictionary = item.get("floor_loot_weights", {})
		if weights.has(table_name):
			# 复制物品定义并附加权重
			var entry: Dictionary = item.duplicate()
			entry["loot_weight"] = weights[table_name]
			result.append(entry)
	return result

func get_item(item_id: String) -> Dictionary:
	if not _items.has(item_id):
		return {}
	return (_items[item_id] as Dictionary).duplicate(true)

## 获取商人商品（根据层级）
func get_merchant_goods(tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _items.values():
		if item.get("merchant_tier", 0) <= tier and item.get("price", 0) > 0:
			result.append(item.duplicate())
	return result

## 调试：打印注册的所有物品
func debug_list_all() -> String:
	var lines: Array[String] = ["ItemRegistry [%d items]" % _items.size()]
	for item in _items.values():
		lines.append("  [%s] %s (%s)" % [item["id"], item["name"], item.get("rarity", "?")])
	return "\n".join(lines)
