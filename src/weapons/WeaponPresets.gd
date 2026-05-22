extends Node
class_name WeaponPresets

# WeaponPresets.gd — 武器预设工厂
# 提供游戏内置枪械预设，配合 AssemblyNode + WeaponAssemblyTree 使用
# 统计键：damage / fire_rate / bullet_count / spread / reload_time / magazine_size / bullet_speed / bullet_damage

## ========== 枪身预设 ==========

## 1. 豌豆手枪 — 半自动，低伤害，高精度
static func gun_pistol() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Pistol")
	node.tags = ["pistol", "semi_auto", "sidearm"]
	node.set_base_stats({
		"damage": 12,
		"fire_rate": 3.5,
		"bullet_count": 1,
		"spread": 0.03,
		"reload_time": 1.5,
		"magazine_size": 12,
	})
	return node

## 2. 步枪 — 全自动，中伤害，稳
static func gun_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Rifle")
	node.tags = ["rifle", "automatic", "assault"]
	node.set_base_stats({
		"damage": 15,
		"fire_rate": 6.0,
		"bullet_count": 1,
		"spread": 0.07,
		"reload_time": 2.2,
		"magazine_size": 30,
	})
	return node

## 3. 霰弹枪 — 低射速，多弹丸，高扩散
static func gun_shotgun() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Shotgun")
	node.tags = ["shotgun", "close_range", "burst"]
	node.set_base_stats({
		"damage": 8,
		"fire_rate": 1.2,
		"bullet_count": 5,
		"spread": 0.35,
		"reload_time": 3.0,
		"magazine_size": 6,
	})
	return node

## 4. 冲锋枪 — 高射速，低单发伤害
static func gun_smg() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_SMG")
	node.tags = ["smg", "automatic", "close_range"]
	node.set_base_stats({
		"damage": 8,
		"fire_rate": 10.0,
		"bullet_count": 1,
		"spread": 0.12,
		"reload_time": 1.8,
		"magazine_size": 25,
	})
	return node

## 5. 狙击枪 — 慢射速，超高单发伤害
static func gun_sniper() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Sniper")
	node.tags = ["sniper", "precision", "semi_auto"]
	node.set_base_stats({
		"damage": 45,
		"fire_rate": 1.0,
		"bullet_count": 1,
		"spread": 0.01,
		"reload_time": 3.5,
		"magazine_size": 5,
	})
	return node

## 6. 榴弹发射器 — 极慢，爆炸弹丸
static func gun_launcher() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Launcher")
	node.tags = ["launcher", "explosive", "slow"]
	node.set_base_stats({
		"damage": 30,
		"fire_rate": 0.8,
		"bullet_count": 1,
		"spread": 0.1,
		"reload_time": 4.0,
		"magazine_size": 3,
	})
	return node

## ========== 子弹预设 ==========

## 标准子弹 — 基础 kinetic
static func bullet_standard() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Standard")
	node.tags = ["bullet", "kinetic", "standard"]
	node.set_base_stats({
		"bullet_damage": 5,
		"bullet_speed": 1.0,
	})
	return node

## 穿甲弹 — 更高伤害倍率
static func bullet_piercing() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Piercing")
	node.tags = ["bullet", "piercing", "armor_penetration"]
	node.set_base_stats({
		"bullet_damage": 9,
		"bullet_speed": 1.4,
	})
	return node

## 爆炸弹 — 牺牲穿透换取范围
static func bullet_explosive() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Explosive")
	node.tags = ["bullet", "explosive", "area_damage"]
	node.set_base_stats({
		"bullet_damage": 20,
		"bullet_speed": 0.75,
	})
	return node

## 高速弹 — 速度翻倍
static func bullet_hyper() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Hyper")
	node.tags = ["bullet", "hyper", "long_range"]
	node.set_base_stats({
		"bullet_damage": 4,
		"bullet_speed": 2.0,
	})
	return node

## ========== 配件预设 ==========

## 枪口制动器 — 减少扩散
static func att_muzzle_brake() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_MuzzleBrake")
	node.tags = ["muzzle", "stabilizer"]
	node.set_base_stats({
		"spread": -0.04,
	})
	return node

## 扩容弹匣 — 增加弹容量
static func att_extended_mag() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_ExtendedMag")
	node.tags = ["magazine", "capacity"]
	node.set_base_stats({
		"magazine_size": 15,
	})
	return node

## 激光瞄具 — 减少扩散（与枪口叠加）
static func att_laser() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_Laser")
	node.tags = ["scope", "accuracy"]
	node.set_base_stats({
		"spread": -0.05,
	})
	return node

## 刺刀 — 增加单发伤害
static func att_bayonet() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.ATTACHMENT, "Att_Bayonet")
	node.tags = ["muzzle", "damage_up"]
	node.set_base_stats({
		"damage": 5,
	})
	return node

## ========== 快捷装配树 ==========

## 步枪 + 标准子弹
static func build_rifle() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_rifle()
	var bul := bullet_standard()
	tree.set_root(gun)
	gun.mount(AssemblyNode.SlotType.BULLET, bul)
	return tree

## 手枪 + 穿甲子弹
static func build_pistol_piercing() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_pistol()
	var bul := bullet_piercing()
	tree.set_root(gun)
	gun.mount(AssemblyNode.SlotType.BULLET, bul)
	return tree

## 霰弹枪 + 爆炸弹
static func build_shotgun_explosive() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_shotgun()
	var bul := bullet_explosive()
	tree.set_root(gun)
	gun.mount(AssemblyNode.SlotType.BULLET, bul)
	return tree

## 冲锋枪 + 高速弹
static func build_smg_hyper() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_smg()
	var bul := bullet_hyper()
	tree.set_root(gun)
	gun.mount(AssemblyNode.SlotType.BULLET, bul)
	return tree

## 狙击枪 + 穿甲弹（带枪口制动器）
static func build_sniper() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_sniper()
	var bul := bullet_piercing()
	var att := att_muzzle_brake()
	tree.set_root(gun)
	gun.mount(AssemblyNode.SlotType.BULLET, bul)
	gun.mount(AssemblyNode.SlotType.MUZZLE, att)
	return tree

## 榴弹发射器 + 爆炸弹
static func build_launcher() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_launcher()
	var bul := bullet_explosive()
	tree.set_root(gun)
	gun.mount(AssemblyNode.SlotType.BULLET, bul)
	return tree

## ========== 预设注册表（用于武器切换）==========
## 键为数字索引（1-6），方便按键切换
static func get_preset_by_index(idx: int) -> WeaponAssemblyTree:
	match idx:
		1: return build_rifle()
		2: return build_pistol_piercing()
		3: return build_shotgun_explosive()
		4: return build_smg_hyper()
		5: return build_sniper()
		6: return build_launcher()
	return build_rifle()

## 获取预设名称描述
static func get_preset_name(idx: int) -> String:
	match idx:
		1: return "步枪 + 穿甲弹"
		2: return "手枪 + 穿甲弹"
		3: return "霰弹枪 + 爆炸弹"
		4: return "冲锋枪 + 高速弹"
		5: return "狙击枪 + 穿甲弹"
		6: return "榴弹发射器"
	return "步枪"