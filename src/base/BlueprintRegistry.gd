extends Node
## 蓝图注册表 — 将蓝图物品ID映射到武器装配工厂
## Autoload 别名：BlueprintRegistry（通过 project.godot 注册）
## 
## 工作流程：
##   1. 玩家在局内获得蓝图碎片（ItemRegistry 中注册为 blueprint 类型物品）
##   2. WorkshopMenu 解锁 BlueprintTier
##   3. LootModule 根据 BlueprintTier 过滤掉落（已实现）
##   4. 玩家开始游戏时，BlueprintRegistry 根据 BlueprintTier 提供可用武器树
##   5. Player.gd / RoomGameMode 使用 BlueprintRegistry 获取初始武器

func _ready() -> void:
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
	# 尝试枪身
	var gun_entry: Dictionary = _registry["gunbody"].get(item_id, {})
	if not gun_entry.is_empty():
		return gun_entry["factory"].call() as AssemblyNode

	# 尝试子弹
	var bullet_entry: Dictionary = _registry["bullet"].get(item_id, {})
	if not bullet_entry.is_empty():
		return bullet_entry["factory"].call() as AssemblyNode

	# 尝试配件
	var attach_entry: Dictionary = _registry["attachment"].get(item_id, {})
	if not attach_entry.is_empty():
		return attach_entry["factory"].call() as AssemblyNode

	push_warning("[BlueprintRegistry] Unknown item_id: %s" % item_id)
	return null

## 构建一个完整武器树（枪身+子弹），根据蓝图Tier自动选择
func build_default_weapon_tree(blueprint_tier: int) -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()

	# 枪身：按优先级选一个可用的
	var available_guns: Array[Dictionary] = get_available_gunbodies(blueprint_tier)
	var gun_id: String = "bp_pistol"  # 默认
	if not available_guns.is_empty():
		gun_id = available_guns[0]["item_id"]

	var gun_node: AssemblyNode = create_assembly_node(gun_id)
	if gun_node == null:
		gun_node = _create_gunbody_pistol()

	tree.set_root(gun_node)

	# 子弹：尝试挂一个同Tier可用的
	var available_bullets: Array[Dictionary] = get_available_bullets(blueprint_tier)
	var bullet_id: String = "mod_bullet_standard"
	for b in available_bullets:
		if b["item_id"] != bullet_id:
			bullet_id = b["item_id"]
			break

	var bullet_node: AssemblyNode = create_assembly_node(bullet_id)
	if bullet_node != null:
		gun_node.mount(AssemblyNode.SlotType.BULLET, bullet_node)

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

func _create_gunbody_pistol() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Pistol")
	node.tags = ["pistol", "semi_auto", "sidearm"]
	node.set_base_stats({
		"damage": 18, "fire_rate": 3.5, "bullet_count": 1,
		"spread": 0.03, "reload_time": 1.5, "magazine_size": 12,
	})
	return node

func _create_gunbody_shotgun() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Shotgun")
	node.tags = ["shotgun", "close_range", "burst"]
	node.set_base_stats({
		"damage": 12, "fire_rate": 1.2, "bullet_count": 5,
		"spread": 0.35, "reload_time": 3.0, "magazine_size": 6,
	})
	return node

func _create_gunbody_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Rifle")
	node.tags = ["rifle", "automatic", "assault"]
	node.set_base_stats({
		"damage": 22, "fire_rate": 6.0, "bullet_count": 1,
		"spread": 0.07, "reload_time": 2.2, "magazine_size": 30,
	})
	return node

func _create_gunbody_machinegun() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Machinegun")
	node.tags = ["auto", "high_rate", "spray"]
	node.set_base_stats({
		"damage": 15, "fire_rate": 12.0, "bullet_count": 1,
		"spread": 0.15, "reload_time": 2.8, "magazine_size": 60,
	})
	return node

func _create_gunbody_sniper() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Sniper")
	node.tags = ["sniper", "precision", "high_damage"]
	node.set_base_stats({
		"damage": 55, "fire_rate": 1.0, "bullet_count": 1,
		"spread": 0.01, "reload_time": 3.5, "magazine_size": 5,
	})
	return node

func _create_gunbody_launcher() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Launcher")
	node.tags = ["launcher", "explosive", "slow"]
	node.set_base_stats({
		"damage": 38, "fire_rate": 0.8, "bullet_count": 1,
		"spread": 0.1, "reload_time": 4.0, "magazine_size": 3,
	})
	return node

func _create_gunbody_charge() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Charge")
	node.tags = ["charge", "蓄力", "high_damage"]
	node.set_base_stats({
		"damage": 30, "fire_rate": 1.5, "bullet_count": 1,
		"spread": 0.05, "reload_time": 3.0, "magazine_size": 4,
		"charge_time": 1.2,
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
	node.tags = ["muzzle", "multi_shot"]
	node.set_base_stats({ "bullet_count": 2, "spread": 0.08 })
	return node

func _create_attachment_rubber_stock() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_RubberStock")
	node.tags = ["stock", "bounce"]
	node.set_base_stats({ "spread": -0.04 })
	return node

func _create_attachment_scope() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_Scope")
	node.tags = ["scope", "crit", "accuracy"]
	node.set_base_stats({ "spread": -0.05, "damage": 5 })
	return node

func _create_attachment_big_mag() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_BigMag")
	node.tags = ["magazine", "heal", "capacity"]
	node.set_base_stats({ "magazine_size": 15 })
	return node

func _create_attachment_fan() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_Fan")
	node.tags = ["external", "pull", "wind"]
	node.set_base_stats({ "pull_strength": 0.5 })
	return node

func _create_attachment_copy_sticker() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_CopySticker")
	node.tags = ["mutator", "copy", "duplicate"]
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