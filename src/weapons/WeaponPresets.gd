extends Node
class_name WeaponPresets

# WeaponPresets.gd — 武器预设工厂
# 提供游戏内置的枪身/子弹/配件预设节点，快速构建装配树
# 配合 AssemblyNode + WeaponAssemblyTree 使用

## 枪身预设
static func gun_body_pistol() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Pistol")
	node.tags = ["pistol", "sidearm"]
	node.set_base_stats({
		"damage": 12,
		"fire_rate": 3.0,
		"spread": 0.05,
		"bullet_count": 1,
		"speed": 1.0,
	})
	return node

static func gun_body_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Rifle")
	node.tags = ["rifle", "assault"]
	node.set_base_stats({
		"damage": 15,
		"fire_rate": 5.0,
		"spread": 0.08,
		"bullet_count": 1,
		"speed": 1.0,
	})
	return node

static func gun_body_shotgun() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Shotgun")
	node.tags = ["shotgun", "close_range"]
	node.set_base_stats({
		"damage": 8,
		"fire_rate": 1.5,
		"spread": 0.3,
		"bullet_count": 5,
		"speed": 1.0,
	})
	return node

## 子弹预设
static func bullet_standard() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Standard")
	node.tags = ["standard", "kinetic"]
	node.set_base_stats({
		"damage": 5,
		"fire_rate": 0.0,
		"spread": 0.0,
		"bullet_count": 1,
		"speed": 1.0,
	})
	return node

static func bullet_explosive() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Explosive")
	node.tags = ["explosive", "area_damage"]
	node.set_base_stats({
		"damage": 20,
		"fire_rate": 0.0,
		"spread": 0.0,
		"bullet_count": 1,
		"speed": 0.8,
	})
	return node

static func bullet_piercing() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Piercing")
	node.tags = ["piercing", "armor_penetration"]
	node.set_base_stats({
		"damage": 8,
		"fire_rate": 0.0,
		"spread": 0.0,
		"bullet_count": 1,
		"speed": 1.5,
	})
	return node

## 配件预设
static func attachment_muzzle_brake() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Attachment_MuzzleBrake")
	node.tags = ["muzzle", "stabilizer"]
	node.set_base_stats({
		"damage": 2,
		"fire_rate": 0.5,
		"spread": -0.03,
		"bullet_count": 0,
		"speed": 1.0,
	})
	return node

static func attachment_magazine_extended() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Attachment_MagazineExtended")
	node.tags = ["magazine", "capacity"]
	node.set_base_stats({
		"damage": 0,
		"fire_rate": 0.0,
		"spread": 0.0,
		"bullet_count": 0,
		"speed": 1.0,
		"magazine_size_bonus": 15,
	})
	return node

static func attachment_laser() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Attachment_Laser")
	node.tags = ["attachment", "accuracy"]
	node.set_base_stats({
		"damage": 0,
		"fire_rate": 0.0,
		"spread": -0.05,
		"bullet_count": 0,
		"speed": 1.0,
	})
	return node

## 快捷装配：用步枪 + 标准子弹创建一个基础武器装配树
static func create_basic_rifle_tree() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var rifle := gun_body_rifle()
	var bullet := bullet_standard()
	tree.set_root(rifle)
	rifle.mount(AssemblyNode.SlotType.BULLET, bullet)
	return tree

## 快捷装配：手枪 + 穿甲弹
static func create_pistol_piercing_tree() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var pistol := gun_body_pistol()
	var bullet := bullet_piercing()
	tree.set_root(pistol)
	pistol.mount(AssemblyNode.SlotType.BULLET, bullet)
	return tree

## 快捷装配：霰弹枪 + 爆炸弹
static func create_shotgun_explosive_tree() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var shotgun := gun_body_shotgun()
	var bullet := bullet_explosive()
	tree.set_root(shotgun)
	shotgun.mount(AssemblyNode.SlotType.BULLET, bullet)
	return tree