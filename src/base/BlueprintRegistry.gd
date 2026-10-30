extends Node
## 蓝图注册表 — 将蓝图物品ID映射到武器装配工厂
## Autoload 别名：BlueprintRegistry（通过 project.godot 注册）
## 
## 工作流程：
##   1. 玩家在局内获得蓝图碎片（ItemRegistry 中注册为 blueprint 类型物品）
##   2. WorkshopMenu 解锁 BlueprintTier
##   3. LootModule 根据 BlueprintTier 过滤掉落（已实现）
##   4. 玩家开始游戏时，BlueprintRegistry 根据 BlueprintTier 提供可用武器树
##   5. Player3D / Dungeon3D 使用 BlueprintRegistry 获取初始武器

func _ready() -> void:
	_build_registry()

func _ensure_registry() -> void:
	if _registry["gunbody"].is_empty() or _registry["bullet"].is_empty():
		_build_registry()

## ========== 注册表结构 ==========
## 格式：category_id -> blueprint_id -> {
##   item_id: String,         # ItemRegistry 中的物品ID
##   tier: int,               # 需要的蓝图Tier（>= 此Tier才可用）
##   node_type: String,       # "gun_body" | "bullet" | "attachment"
##   factory: Callable,      # () -> AssemblyNode
##   tags: Array[String],
##   display_name: String,
## }

var _registry: Dictionary = {
	"gunbody": {},
	"bullet": {},
	"attachment": {}
}

## 出厂配发主武器。`Player3D.start_with_weapon` 经 `get_starting_weapon_tree()`
## 走到这里，所以换掉这一个 ID 就等于换掉「新档出生 / 死亡返城」白送的枪。
##
## ⚠️ 新档首局的地面初始枪**不在这里** —— 它由剧本 `nar_tower_opening_01_wake` 的
## `scene.spawn_item` 刷出（`TowerDescent3D._clear_new_game_opening_loadout()` 会先收回
## 本函数白送的枪）。改出厂枪必须**同时**改那支剧本里的 `item_id`，否则新档拿到的仍是旧枪。
const DEFAULT_STARTING_GUN_ID := "bp_starter_rifle"

## PUBG式统一槽位框架：界面位置固定，枪型只声明开放的槽位子集。
const ROOT_ATTACHMENT_SUPPORT := {
	"GunBody_Pistol": ["scope", "muzzle", "magazine", "mutator"],
	"GunBody_Shotgun": ["muzzle", "magazine", "stock", "tactical", "mutator"],
	"GunBody_Rifle": ["scope", "muzzle", "magazine", "stock", "tactical", "mutator"],
	"GunBody_Machinegun": ["scope", "muzzle", "magazine", "stock", "tactical"],
	"GunBody_Sprinkler": ["scope", "muzzle", "magazine", "stock", "tactical"],
	"GunBody_StarterRifle": ["scope", "muzzle", "magazine", "stock", "tactical", "mutator"],
	"GunBody_Sniper": ["scope", "muzzle", "magazine", "stock", "mutator"],
	"GunBody_Launcher": ["scope", "stock", "tactical", "mutator"],
	"GunBody_Charge": ["scope", "stock", "tactical", "mutator"],
}

const ASSEMBLY_NODE_ITEM_IDS := {
	"GunBody_Pistol": "weapon_pistol",
	"GunBody_Shotgun": "weapon_shotgun",
	"GunBody_Rifle": "weapon_rifle",
	"GunBody_Machinegun": "weapon_machinegun",
	"GunBody_Sprinkler": "weapon_sprinkler",
	"GunBody_StarterRifle": "weapon_starter_rifle",
	"GunBody_Sniper": "weapon_sniper",
	"GunBody_Launcher": "weapon_launcher",
	"GunBody_Charge": "weapon_charge",
	"Melee_BaseballBat": "weapon_baseball_bat",
	"Melee_Greatblade": "weapon_greatblade",
	"Melee_Waraxe": "weapon_waraxe",
	"Bullet_Standard": "mod_bullet_standard",
	"Bullet_Sticky": "mod_bullet_sticky",
	"Bullet_Bounce": "mod_bullet_bounce",
	"Bullet_Piercing": "mod_bullet_piercing",
	"Bullet_Explosive": "mod_bullet_explosive",
	"Bullet_Homing": "mod_bullet_homing",
	"Bullet_Blackhole": "mod_bullet_blackhole",
	"Bullet_Balloon": "mod_bullet_balloon",
	"Att_TripleMuzzle": "attach_triple_muzzle",
	"Att_RubberStock": "attach_rubber_stock",
	"Att_Scope": "attach_scope",
	"Att_BigMag": "attach_big_mag",
	"Att_Fan": "attach_fan",
	"Att_CopySticker": "attach_copy_sticker",
}

func _build_registry() -> void:
	# ========== 枪身 ==========
	_register_gunbody({
		"item_id": "bp_pistol",
		"tier": 0,
		"factory": func(): return _create_gunbody_pistol(),
		"tags": ["pistol", "semi_auto", "sidearm"],
		"display_name": "豌豆手枪",
	})
	_register_gunbody({
		"item_id": "bp_sprinkler",
		"tier": 0,
		"factory": func(): return _create_gunbody_sprinkler(),
		"tags": ["auto", "high_rate", "spray"],
		"display_name": "花洒机枪",
	})
	_register_gunbody({
		"item_id": "bp_starter_rifle",
		"tier": 0,
		"factory": func(): return _create_gunbody_starter_rifle(),
		"tags": ["rifle", "automatic", "assault"],
		"display_name": "初始步枪",
	})
	_register_gunbody({
		"item_id": "bp_shotgun",
		"tier": 0,
		"factory": func(): return _create_gunbody_shotgun(),
		"tags": ["shotgun", "close_range", "burst"],
		"display_name": "散射喷壶",
	})
	_register_gunbody({
		"item_id": "bp_rifle",
		"tier": 1,
		"factory": func(): return _create_gunbody_rifle(),
		"tags": ["rifle", "automatic", "assault"],
		"display_name": "步枪",
	})
	_register_gunbody({
		"item_id": "bp_machinegun",
		"tier": 1,
		"factory": func(): return _create_gunbody_machinegun(),
		"tags": ["auto", "high_rate", "spray"],
		"display_name": "蜂窝机枪",
	})
	_register_gunbody({
		"item_id": "bp_sniper",
		"tier": 2,
		"factory": func(): return _create_gunbody_sniper(),
		"tags": ["sniper", "precision", "high_damage"],
		"display_name": "弹弓狙击",
	})
	_register_gunbody({
		"item_id": "bp_launcher",
		"tier": 2,
		"factory": func(): return _create_gunbody_launcher(),
		"tags": ["launcher", "explosive", "slow"],
		"display_name": "反胃榴弹筒",
	})
	_register_gunbody({
		"item_id": "bp_charge",
		"tier": 3,
		"factory": func(): return _create_gunbody_charge(),
		"tags": ["charge", "蓄力", "high_damage"],
		"display_name": "蓄力萝卜炮",
	})
	_register_gunbody({
		"item_id": "bp_baseball_bat",
		"tier": 0,
		"factory": func(): return _create_melee_baseball_bat(),
		"tags": ["weapon", "melee", "light_melee", "baseball_bat"],
		"display_name": "废土棒球棍",
	})
	_register_gunbody({
		"item_id": "bp_greatblade",
		"tier": 0,
		"factory": func(): return _create_melee_greatblade(),
		"tags": ["weapon", "melee", "heavy_melee", "greatblade"],
		"display_name": "巨型工业断刃",
	})
	_register_gunbody({
		"item_id": "bp_waraxe",
		"tier": 1,
		"factory": func(): return _create_melee_waraxe(),
		"tags": ["weapon", "melee", "heavy_melee", "waraxe"],
		"display_name": "攻城裂甲斧",
	})

	# ========== 子弹 ==========
	_register_bullet({
		"item_id": "mod_bullet_standard",
		"tier": 0,
		"factory": func(): return _create_bullet_standard(),
		"tags": ["bullet", "kinetic", "standard"],
		"display_name": "标准子弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_sticky",
		"tier": 0,
		"factory": func(): return _create_bullet_sticky(),
		"tags": ["bullet", "sticky", "dot"],
		"display_name": "黏黏弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_bounce",
		"tier": 0,
		"factory": func(): return _create_bullet_bounce(),
		"tags": ["bullet", "bounce", "ricochet"],
		"display_name": "回旋镖弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_piercing",
		"tier": 1,
		"factory": func(): return _create_bullet_piercing(),
		"tags": ["bullet", "piercing", "armor"],
		"display_name": "穿甲弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_explosive",
		"tier": 1,
		"factory": func(): return _create_bullet_explosive(),
		"tags": ["bullet", "explosive", "area"],
		"display_name": "爆炸弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_homing",
		"tier": 2,
		"factory": func(): return _create_bullet_homing(),
		"tags": ["bullet", "homing", "summon"],
		"display_name": "蜂卵弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_blackhole",
		"tier": 2,
		"factory": func(): return _create_bullet_blackhole(),
		"tags": ["bullet", "blackhole", "pull"],
		"display_name": "黑洞弹模块",
	})
	_register_bullet({
		"item_id": "mod_bullet_balloon",
		"tier": 1,
		"factory": func(): return _create_bullet_balloon(),
		"tags": ["bullet", "balloon", "slow", "big"],
		"display_name": "气球弹模块",
	})

	# ========== 配件 ==========
	_register_attachment({
		"item_id": "attach_triple_muzzle",
		"tier": 0,
		"factory": func(): return _create_attachment_triple_muzzle(),
		"tags": ["muzzle", "multi_shot"],
		"display_name": "三叉枪口",
	})
	_register_attachment({
		"item_id": "attach_rubber_stock",
		"tier": 0,
		"factory": func(): return _create_attachment_rubber_stock(),
		"tags": ["stock", "bounce"],
		"display_name": "橡皮枪托",
	})
	_register_attachment({
		"item_id": "attach_scope",
		"tier": 1,
		"factory": func(): return _create_attachment_scope(),
		"tags": ["scope", "crit", "accuracy"],
		"display_name": "放大镜瞄具",
	})
	_register_attachment({
		"item_id": "attach_big_mag",
		"tier": 1,
		"factory": func(): return _create_attachment_big_mag(),
		"tags": ["magazine", "heal", "capacity"],
		"display_name": "肉质弹匣",
	})
	_register_attachment({
		"item_id": "attach_fan",
		"tier": 2,
		"factory": func(): return _create_attachment_fan(),
		"tags": ["external", "pull", "wind"],
		"display_name": "小风扇",
	})
	_register_attachment({
		"item_id": "attach_copy_sticker",
		"tier": 2,
		"factory": func(): return _create_attachment_copy_sticker(),
		"tags": ["mutator", "copy", "duplicate"],
		"display_name": "复制贴纸",
	})

## ========== 注册辅助 ==========

func _register_gunbody(entry: Dictionary) -> void:
	_registry["gunbody"][entry["item_id"]] = entry

func _register_bullet(entry: Dictionary) -> void:
	_registry["bullet"][entry["item_id"]] = entry

func _register_attachment(entry: Dictionary) -> void:
	_registry["attachment"][entry["item_id"]] = entry

## ========== 公开接口 ==========

## 获取给定蓝图Tier下可用的枪身蓝图列表
func get_available_gunbodies(blueprint_tier: int) -> Array[Dictionary]:
	_ensure_registry()
	var result: Array[Dictionary] = []
	for item_id in _registry["gunbody"]:
		var entry: Dictionary = _registry["gunbody"][item_id]
		if entry["tier"] <= blueprint_tier:
			result.append({
				"item_id": item_id,
				"display_name": entry["display_name"],
				"tier": entry["tier"],
				"tags": entry["tags"],
			})
	return result

## 获取给定蓝图Tier下可用的子弹蓝图列表
func get_available_bullets(blueprint_tier: int) -> Array[Dictionary]:
	_ensure_registry()
	var result: Array[Dictionary] = []
	for item_id in _registry["bullet"]:
		var entry: Dictionary = _registry["bullet"][item_id]
		if entry["tier"] <= blueprint_tier:
			result.append({
				"item_id": item_id,
				"display_name": entry["display_name"],
				"tier": entry["tier"],
				"tags": entry["tags"],
			})
	return result

## 获取给定蓝图Tier下可用的配件蓝图列表
func get_available_attachments(blueprint_tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id in _registry["attachment"]:
		var entry: Dictionary = _registry["attachment"][item_id]
		if entry["tier"] <= blueprint_tier:
			result.append({
				"item_id": item_id,
				"display_name": entry["display_name"],
				"tier": entry["tier"],
				"tags": entry["tags"],
			})
	return result

## 通过物品ID创建装配节点（用于初始武器装配）
func create_assembly_node(item_id: String) -> AssemblyNode:
	_ensure_registry()
	# 尝试枪身
	var gun_entry: Dictionary = _registry["gunbody"].get(item_id, {})
	if not gun_entry.is_empty():
		var gun := gun_entry["factory"].call() as AssemblyNode
		apply_runtime_contract(gun)
		return gun

	# 尝试子弹
	var bullet_entry: Dictionary = _registry["bullet"].get(item_id, {})
	if not bullet_entry.is_empty():
		return bullet_entry["factory"].call() as AssemblyNode

	# 尝试配件
	var attach_entry: Dictionary = _registry["attachment"].get(item_id, {})
	if not attach_entry.is_empty():
		var attachment := attach_entry["factory"].call() as AssemblyNode
		apply_runtime_contract(attachment)
		return attachment

	push_warning("[BlueprintRegistry] Unknown item_id: %s" % item_id)
	return null


## 旧存档水合入口：补齐后来加入的兼容标签，不改任何玩家数值或已装配节点。
func apply_runtime_contract(node: AssemblyNode) -> void:
	if node == null:
		return
	if node.node_type == AssemblyNode.NodeType.GUN_BODY:
		for slot_key in ROOT_ATTACHMENT_SUPPORT.get(node.node_name, []):
			var support_tag := "supports_%s" % str(slot_key)
			if support_tag not in node.tags:
				node.tags.append(support_tag)
	elif node.node_type == AssemblyNode.NodeType.ATTACHMENT:
		var slot_type := node.get_attachment_slot_type()
		if slot_type >= 0:
			var slot_tag := "attachment_slot_%s" % AssemblyNode.get_attachment_slot_key(slot_type)
			if slot_tag not in node.tags:
				node.tags.append(slot_tag)
	for child in node.get_all_descendants():
		if child.parent_node == node:
			apply_runtime_contract(child)


func get_item_id_for_assembly_node(node: AssemblyNode) -> String:
	return str(ASSEMBLY_NODE_ITEM_IDS.get(node.node_name, "")) if node != null else ""


func get_item_for_assembly_node(node: AssemblyNode) -> Dictionary:
	var item_id := get_item_id_for_assembly_node(node)
	return ItemRegistry.get_instance().get_item(item_id) if not item_id.is_empty() else {}


## 子弹模块的展示用基础属性（背包悬浮卡、装配对比用）。
##
## 直接 `create_assembly_node()` 会造一个 Node；悬浮卡每次鼠标进入都会调，不缓存就是
## 持续分配 ⇒ 这里按 content_id 记忆化。返回的是副本，调用方随便改。
var _bullet_base_stats_cache: Dictionary = {}

func get_bullet_base_stats(item_id: String) -> Dictionary:
	if _bullet_base_stats_cache.has(item_id):
		return (_bullet_base_stats_cache[item_id] as Dictionary).duplicate(true)
	_ensure_registry()
	var entry: Dictionary = _registry["bullet"].get(item_id, {})
	if entry.is_empty():
		return {}
	var node := entry["factory"].call() as AssemblyNode
	if node == null:
		return {}
	var stats := node.get_base_stats()
	node.free()
	_bullet_base_stats_cache[item_id] = stats.duplicate(true)
	return stats


func get_attachment_slot_type_for_item(item: Dictionary) -> int:
	var node := create_assembly_node(str(item.get("assembly_id", item.get("id", ""))))
	if node == null:
		return -1
	var result := node.get_attachment_slot_type()
	node.free()
	return result

## 构建一个完整武器树（枪身+子弹），根据蓝图Tier自动选择
func build_default_weapon_tree(blueprint_tier: int) -> WeaponAssemblyTree:
	# 枪身：优先给出厂枪；它被 Tier 锁住时才退回可用列表首位。
	var available_guns: Array[Dictionary] = get_available_gunbodies(blueprint_tier)
	var gun_id: String = DEFAULT_STARTING_GUN_ID
	var starter_present := false
	for gun in available_guns:
		if str(gun["item_id"]) == gun_id:
			starter_present = true
			break
	if not starter_present:
		gun_id = "bp_pistol"
		if not available_guns.is_empty():
			gun_id = available_guns[0]["item_id"]

	# 子弹：出厂树固定挂标准弹。特殊弹（黏黏/反弹/穿透…）是玩家在包裹里手动装配的玩法选择，
	# 不能由「自动挑一个」悄悄塞进出厂枪。
	#
	# ⚠️ 2026-10-17 修：旧实现是 `for b in available_bullets: if b["item_id"] != "mod_bullet_standard"`，
	#   本意大概是「挑一个可用的」，实际效果是**跳过标准弹、选中注册表里第一颗特殊弹**
	#   ——tier0 的可用列表是 [standard, sticky, bounce]，于是出厂初始步枪一直挂着
	#   `Bullet_Sticky`。命中触发 Projectile3D._apply_secondary_effect 的
	#   `apply_damage_over_time(max(2, damage/3), 2.4)`，56 点弹伤 ⇒ 18 点 DOT，
	#   每 0.5s 结算 `ceil(18×0.2)=4` 点 ⇒ 玩家看到「打中怪物后还在 4 点 4 点地掉血」。
	#   这不是持续伤害设计，是选弹循环把特殊弹当默认弹。
	var available_bullets: Array[Dictionary] = get_available_bullets(blueprint_tier)
	var bullet_id: String = "mod_bullet_standard"
	var standard_available := false
	for b in available_bullets:
		if str(b["item_id"]) == bullet_id:
			standard_available = true
			break
	if not standard_available and not available_bullets.is_empty():
		bullet_id = str(available_bullets[0]["item_id"])

	return build_weapon_tree(gun_id, bullet_id)


## 按正式注册表 ID 构建指定枪身+子弹的装配树，供测试、预览与内容工具复用。
func build_weapon_tree(
	gunbody_item_id: String, bullet_item_id: String = "mod_bullet_standard"
) -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun_node := create_assembly_node(gunbody_item_id)
	if gun_node == null or gun_node.node_type != AssemblyNode.NodeType.GUN_BODY:
		gun_node = _create_gunbody_pistol()
	tree.set_root(gun_node)
	if "melee" in gun_node.tags:
		return tree
	var bullet_node := create_assembly_node(bullet_item_id)
	if bullet_node != null and bullet_node.node_type == AssemblyNode.NodeType.BULLET:
		tree.mount(gun_node, AssemblyNode.SlotType.BULLET, bullet_node)
	return tree

## 获取默认初始武器（受蓝图Tier限制）
func get_starting_weapon_tree() -> WeaponAssemblyTree:
	var tier: int = 0
	if BaseManager != null:
		tier = BaseManager.get_blueprint_tier("gunbody")
	return build_default_weapon_tree(tier)

## 检查某物品ID是否已通过蓝图解锁（>= 对应Tier）
func is_unlocked(item_id: String) -> bool:
	for cat in ["gunbody", "bullet", "attachment"]:
		if _registry[cat].has(item_id):
			var entry: Dictionary = _registry[cat][item_id]
			var required_tier: int = entry["tier"]
			var current_tier: int = 0
			if BaseManager != null:
				current_tier = BaseManager.get_blueprint_tier(cat)
			return current_tier >= required_tier
	return false  # 未知物品默认不可用

## ========== 枪身工厂方法 ==========

## 豌豆手枪（2026-10-30 弹匣/弹速对齐《挺进地牢》）。
##
## 对标对象是**陆战队员的军用佩枪 `Marine Sidearm`**（Magazine 10 / Shot Speed 25 /
## Damage 5 / 0.25 s 每发 / 换弹 1.2 s）。本次只换业主指定的两项：
##   · `magazine_size` 12 → **10**
##   · 弹速 23 → **25 m/s**
## 本作的弹速口径是 `弹速 = 23 × 枪身倍率 × 弹种倍率 × 命运倍率`，23 m/s 即原作的
## Shot Speed 23，所以枪身只声明**倍率** `25 / 23 ≈ 1.0870`，不写 m/s。
## 枪身倍率与弹种倍率是**相乘**（`AssemblyNode._combine_stats`），否则挂上标准弹
## （倍率 1.0）会把枪身值覆盖掉——这条以前没人踩过，因为枪身从不声明弹速。
func _create_gunbody_pistol() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Pistol")
	node.tags = ["pistol", "semi_auto", "sidearm"]
	node.set_base_stats({
		"damage": 25, "fire_rate": 3.5, "bullet_count": 1, "range": 15,
		"spread": 0.03, "reload_time": 1.5, "magazine_size": 10,
		"bullet_speed": 25.0 / 23.0,
	})
	return node

func _create_melee_baseball_bat() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "Melee_BaseballBat")
	node.tags = ["weapon", "melee", "light_melee", "baseball_bat", "starter_melee"]
	node.set_base_stats({
		"weapon_kind": "melee", "damage": 20,
		"melee_reach": 2.05, "melee_arc_degrees": 105.0, "melee_knockback": 3.2,
		"melee_combo_count": 3,
		"melee_1_damage_scale": 0.88, "melee_1_windup_s": 0.13,
		"melee_1_active_s": 0.08, "melee_1_recovery_s": 0.15, "melee_1_knockback_scale": 0.80,
		"melee_2_damage_scale": 1.00, "melee_2_windup_s": 0.12,
		"melee_2_active_s": 0.08, "melee_2_recovery_s": 0.16, "melee_2_knockback_scale": 1.00,
		"melee_3_damage_scale": 1.28, "melee_3_windup_s": 0.22,
		"melee_3_active_s": 0.11, "melee_3_recovery_s": 0.28, "melee_3_knockback_scale": 1.35,
	})
	return node

func _create_gunbody_shotgun() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Shotgun")
	node.tags = ["shotgun", "close_range", "burst"]
	node.set_base_stats({
		"damage": 45, "fire_rate": 1.2, "bullet_count": 5, "range": 7,
		"spread": 0.35, "reload_time": 3.0, "magazine_size": 6,
	})
	return node

func _create_gunbody_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Rifle")
	node.tags = ["rifle", "automatic", "assault"]
	node.set_base_stats({
		"damage": 60, "fire_rate": 6.0, "bullet_count": 1, "range": 20,
		"spread": 0.07, "reload_time": 2.2, "magazine_size": 30,
	})
	return node

func _create_gunbody_machinegun() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Machinegun")
	node.tags = ["auto", "high_rate", "spray"]
	node.set_base_stats({
		"damage": 15, "fire_rate": 12.0, "bullet_count": 1, "range": 18,
		"spread": 0.15, "reload_time": 2.8, "magazine_size": 60,
	})
	return node

## 出厂机枪：沿用蜂窝机枪的射速与散布，单发伤害减半、弹匣加厚到 100 发。
## 它是白送枪，所以不开放「特性」槽，命运槽容量由 ItemRegistry 限成 4。
func _create_gunbody_sprinkler() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Sprinkler")
	node.tags = ["auto", "high_rate", "spray"]
	node.set_base_stats({
		"damage": 12, "fire_rate": 12.0, "bullet_count": 1, "range": 18,
		"spread": 0.15, "reload_time": 2.8, "magazine_size": 100,
	})
	return node

## 初始步枪：以步枪为原型的出厂白送枪。单发伤害与射速都远高于量产步枪
## （业主 2026-10-14 指定 50 / 50 / 换弹 1.8s），因此它的平衡杠杆只剩
## 「命运槽容量 4」（见 ItemRegistry.weapon_starter_rifle）—— 白送不代表能长成终局武器。
## 弹匣/散布沿用步枪本体，配件槽位与步枪一致（含特性槽）。
func _create_gunbody_starter_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_StarterRifle")
	node.tags = ["rifle", "automatic", "assault", "starter_rifle"]
	node.set_base_stats({
		"damage": 50, "fire_rate": 5.0, "bullet_count": 1, "range": 20,
		"spread": 0.07, "reload_time": 1.8, "magazine_size": 30,
	})
	return node

func _create_gunbody_sniper() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Sniper")
	node.tags = ["sniper", "precision", "high_damage"]
	node.set_base_stats({
		"damage": 380, "fire_rate": 1.0, "bullet_count": 1, "range": 60,
		"spread": 0.01, "reload_time": 3.5, "magazine_size": 5,
	})
	return node

func _create_gunbody_launcher() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Launcher")
	node.tags = ["launcher", "explosive", "slow"]
	node.set_base_stats({
		"damage": 250, "fire_rate": 1.0, "bullet_count": 1, "range": 18,
		"spread": 0.1, "reload_time": 4.0, "magazine_size": 3,
		# 命中范围爆炸的中心倍率：弹体伤害(250+标准弹8=258) × 0.697675 = 180。
		# 沿用"范围伤害=弹体伤害×倍率×距离衰减"的既有模型，距离衰减 1.0→0.25。
		"explosion_damage_scale": 0.697675,
	})
	return node

func _create_gunbody_charge() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Charge")
	node.tags = ["charge", "蓄力", "high_damage"]
	node.set_base_stats({
		"damage": 880, "fire_rate": 1.5, "bullet_count": 1, "range": 18,
		"spread": 0.05, "reload_time": 3.0, "magazine_size": 4,
		"charge_time": 1.2,
		# 命中范围爆炸的中心倍率：弹体伤害(880+标准弹8=888) × 0.630631 = 560。
		"explosion_damage_scale": 0.630631,
	})
	return node

func _create_melee_greatblade() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "Melee_Greatblade")
	node.tags = ["weapon", "melee", "heavy_melee", "greatblade", "wide_arc"]
	node.set_base_stats({
		"weapon_kind": "melee", "damage": 34,
		"melee_reach": 2.65, "melee_arc_degrees": 115.0, "melee_knockback": 5.4,
		"melee_combo_count": 3,
		"melee_1_damage_scale": 0.82, "melee_1_windup_s": 0.20,
		"melee_1_active_s": 0.10, "melee_1_recovery_s": 0.20, "melee_1_knockback_scale": 0.80,
		"melee_2_damage_scale": 1.00, "melee_2_windup_s": 0.18,
		"melee_2_active_s": 0.11, "melee_2_recovery_s": 0.23, "melee_2_knockback_scale": 1.00,
		"melee_3_damage_scale": 1.48, "melee_3_windup_s": 0.32,
		"melee_3_active_s": 0.14, "melee_3_recovery_s": 0.40, "melee_3_knockback_scale": 1.55,
	})
	return node

func _create_melee_waraxe() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "Melee_Waraxe")
	node.tags = ["weapon", "melee", "heavy_melee", "waraxe", "high_knockback"]
	node.set_base_stats({
		"weapon_kind": "melee", "damage": 46,
		"melee_reach": 2.85, "melee_arc_degrees": 100.0, "melee_knockback": 7.2,
		"melee_combo_count": 3,
		"melee_1_damage_scale": 0.78, "melee_1_windup_s": 0.48,
		"melee_1_active_s": 0.14, "melee_1_recovery_s": 0.40, "melee_1_knockback_scale": 0.90,
		"melee_2_damage_scale": 1.02, "melee_2_windup_s": 0.52,
		"melee_2_active_s": 0.16, "melee_2_recovery_s": 0.46, "melee_2_knockback_scale": 1.10,
		"melee_3_damage_scale": 1.62, "melee_3_windup_s": 0.65,
		"melee_3_active_s": 0.20, "melee_3_recovery_s": 0.65, "melee_3_knockback_scale": 1.70,
	})
	return node

## ========== 子弹工厂方法 ==========

func _create_bullet_standard() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Standard")
	node.tags = ["bullet", "kinetic", "standard"]
	node.set_base_stats({ "bullet_damage": 8, "bullet_speed": 1.0 })
	return node

func _create_bullet_sticky() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Sticky")
	node.tags = ["bullet", "sticky", "dot"]
	node.set_base_stats({ "bullet_damage": 6, "bullet_speed": 0.8 })
	return node

func _create_bullet_bounce() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Bounce")
	node.tags = ["bullet", "bounce", "ricochet"]
	node.set_base_stats({ "bullet_damage": 7, "bullet_speed": 1.1 })
	return node

func _create_bullet_piercing() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Piercing")
	node.tags = ["bullet", "piercing", "armor"]
	node.set_base_stats({ "bullet_damage": 14, "bullet_speed": 1.4 })
	return node

func _create_bullet_explosive() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Explosive")
	node.tags = ["bullet", "explosive", "area"]
	node.set_base_stats({ "bullet_damage": 28, "bullet_speed": 0.75 })
	return node

func _create_bullet_homing() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Homing")
	node.tags = ["bullet", "homing", "summon"]
	node.set_base_stats({ "bullet_damage": 10, "bullet_speed": 0.9 })
	return node

func _create_bullet_blackhole() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Blackhole")
	node.tags = ["bullet", "blackhole", "pull"]
	node.set_base_stats({ "bullet_damage": 12, "bullet_speed": 0.6 })
	return node

func _create_bullet_balloon() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Balloon")
	node.tags = ["bullet", "balloon", "slow", "big"]
	node.set_base_stats({ "bullet_damage": 18, "bullet_speed": 0.5 })
	return node

## ========== 配件工厂方法 ==========

func _create_attachment_triple_muzzle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_TripleMuzzle")
	node.tags = ["muzzle", "multi_shot", "attachment_slot_muzzle"]
	node.set_base_stats({ "bullet_count": 2, "spread": 0.08 })
	return node

func _create_attachment_rubber_stock() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_RubberStock")
	node.tags = ["stock", "bounce", "attachment_slot_stock"]
	node.set_base_stats({ "spread": -0.04 })
	return node

func _create_attachment_scope() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_Scope")
	node.tags = ["scope", "crit", "accuracy", "attachment_slot_scope"]
	node.set_base_stats({ "spread": -0.05, "damage": 15 })
	return node

func _create_attachment_big_mag() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_BigMag")
	node.tags = ["magazine", "heal", "capacity", "attachment_slot_magazine"]
	node.set_base_stats({ "magazine_size": 15 })
	return node

func _create_attachment_fan() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_Fan")
	node.tags = ["external", "pull", "wind", "attachment_slot_tactical"]
	node.set_base_stats({ "pull_strength": 0.5 })
	return node

func _create_attachment_copy_sticker() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_CopySticker")
	node.tags = ["mutator", "copy", "duplicate", "attachment_slot_mutator"]
	node.set_base_stats({ "copy_chance": 0.25 })
	return node

## 调试：打印注册表摘要
func debug_summary() -> String:
	var lines: Array[String] = ["BlueprintRegistry summary:"]
	for cat in ["gunbody", "bullet", "attachment"]:
		var entries: Array = _registry[cat].values()
		lines.append("  %s: %d entries" % [cat, entries.size()])
		for e in entries:
			lines.append("    [%s] Tier%d %s" % [e["item_id"], e["tier"], e["display_name"]])
	return "\n".join(lines)
