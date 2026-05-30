extends Node
class_name WeaponPresets

# WeaponPresets.gd — 武器预设工厂
# 提供游戏内置枪械预设，配合 AssemblyNode + WeaponAssemblyTree 使用
# 统计键：damage / fire_rate / bullet_count / spread / reload_time / magazine_size / bullet_speed / bullet_damage

## ========== 枪身预设 ==========

## 1. 豌豆手枪 — 半自动，高精度，超快换弹（容错率高）
## 克制：近距离遭遇，速战速决 | 弱点：单发DPS最低(70)
## 调整：换弹极快(1.2s)让手枪在高压下快速重整，但DPS垫底
static func gun_pistol() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Pistol")
	node.tags = ["pistol", "semi_auto", "sidearm"]
	node.set_base_stats({
		"damage": 20,
		"fire_rate": 3.5,
		"bullet_count": 1,
		"spread": 0.03,
		"reload_time": 1.2,   # v2: 极快换弹，差异化核心
		"magazine_size": 12,
	})
	return node

## 2. 步枪 — 全自动，中伤害，稳
static func gun_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Rifle")
	node.tags = ["rifle", "automatic", "assault"]
	node.set_base_stats({
		"damage": 22,
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
		"damage": 15,
		"fire_rate": 1.2,
		"bullet_count": 5,
		"spread": 0.35,
		"reload_time": 3.0,
		"magazine_size": 6,
	})
	return node

## 4. 冲锋枪 — 超高射速(14)，近距离倾泻弹雨
## 克制：贴脸遭遇、快速消灭成群小怪 | 弱点：换弹慢(2.5s)，spread大只适合近战
## 与步枪差异：FR 14 vs 6，但damage 10 vs 22；步枪是精准单发，冲锋枪是贴脸倾泻
## 调整后DPS：10×14=140/2.5s换弹→实际持续DPS 56；爆发力极强但持续差
static func gun_smg() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_SMG")
	node.tags = ["smg", "automatic", "close_range"]
	node.set_base_stats({
		"damage": 10,
		"fire_rate": 14.0,
		"bullet_count": 1,
		"spread": 0.18,
		"reload_time": 2.5,  # v2: 换弹慢，制造风险
		"magazine_size": 35,
	})
	return node

## 5. 狙击枪 — 单发高伤害，高精度，远程点名
## 克制：中高甲敌人（单发65伤害，爆头秒杀脆皮）| 弱点：近距离（reload 3.5s，弹容量仅5发）
## 设计：DPS 实际不如步枪/冲子，但单发暴击价值高，适合精英怪和 Boss 战
## v2: 爆炸弹作为下位替代（bullet_explosive 28伤害），狙击枪走极端路线：单发极强但极慢
static func gun_sniper() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Sniper")
	node.tags = ["sniper", "precision", "semi_auto"]
	node.set_base_stats({
		"damage": 75,       # v2: 65→75，差异化更极端
		"fire_rate": 1.5,   # v2: 1.8→1.5，极慢
		"bullet_count": 1,
		"spread": 0.005,   # v2: 更精准
		"reload_time": 3.8, # v2: 更慢
		"magazine_size": 4,
	})
	return node

## 5.5 轻机枪 — 超高弹容量(80)，持续压制
## 克制：多波次小怪、逃跑路线上的杂兵 | 弱点：单发极低，换弹极慢(5s)，精度差
## 调整后DPS：8×12=96/5s换弹→实际持续DPS 19.2；80发弹匣压制力强但单发最弱
## 设计：作为"弹药消耗型"武器，配合"捡弹药"机制有独特价值
static func gun_lmg() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_LMG")
	node.tags = ["lmg", "automatic", "suppressive"]
	node.set_base_stats({
		"damage": 8,         # v2: 10→8，极端化
		"fire_rate": 12.0,   # v2: 14→12，略降
		"bullet_count": 1,
		"spread": 0.25,      # v2: 0.20→0.25，极不精准
		"reload_time": 5.0,  # v2: 4.2→5.0，极慢
		"magazine_size": 80, # v2: 60→80，超高弹容量
	})
	return node

## 6. 榴弹发射器 — 范围爆炸，低射速
## 克制：扎堆怪物、护盾怪物 | 弱点：单目标DPS极低，换弹慢（4s）
## 设计：范围伤害是核心价值，爆炸半径80px，单目标DPS约50/4=12.5
## 调整后爆炸伤害50，飞行速度0.6x需要预判
static func gun_launcher() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Launcher")
	node.tags = ["launcher", "explosive", "slow"]
	node.set_base_stats({
		"damage": 50,
		"fire_rate": 0.75,
		"bullet_count": 1,
		"spread": 0.12,
		"reload_time": 4.0,
		"magazine_size": 3,
		"explosion_radius": 80.0,
	})
	return node

## 6.5 爆发突击步枪 — 3连发爆发，中距离精准压制
## 与冲锋枪区分：冲锋枪是持续倾泻，burst是短促爆发
## 与霰弹枪区分：霰弹扇形，burst是精准单线
## 设计：扣一次扳机3发，中距离压制优于冲锋枪，单次爆发超过步枪
static func gun_burst_rifle() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_BurstRifle")
	node.tags = ["rifle", "burst", "assault"]
	node.set_base_stats({
		"damage": 18,
		"fire_rate": 3.0,
		"bullet_count": 3,
		"spread": 0.10,
		"reload_time": 2.4,
		"magazine_size": 24,
	})
	return node

## ========== 子弹预设 ==========

## 标准子弹 — 基础 kinetic
static func bullet_standard() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Standard")
	node.tags = ["bullet", "kinetic", "standard"]
	node.set_base_stats({
		"bullet_damage": 8,
		"bullet_speed": 1.0,
	})
	return node

## 穿甲弹 — 更高伤害倍率
static func bullet_piercing() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Piercing")
	node.tags = ["bullet", "piercing", "armor_penetration"]
	node.set_base_stats({
		"bullet_damage": 14,
		"bullet_speed": 1.4,
	})
	return node

## 爆炸弹 — 牺牲穿透换取范围
static func bullet_explosive() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Explosive")
	node.tags = ["bullet", "explosive", "area_damage"]
	node.set_base_stats({
		"bullet_damage": 28,
		"bullet_speed": 0.75,
	})
	return node

## 高速弹 — 速度翻倍
static func bullet_hyper() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Hyper")
	node.tags = ["bullet", "hyper", "long_range"]
	node.set_base_stats({
		"bullet_damage": 7,
		"bullet_speed": 2.0,
	})
	return node

## 粘性弹 — 命中后减速敌人30%，持续2秒
## 设计：控制型子弹，适合风筝战术，对付快速近战追击怪
## 弱点：减速不叠加，多个命中也只刷新不加强
static func bullet_sticky() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Sticky")
	node.tags = ["bullet", "sticky", "slow"]
	node.set_base_stats({
		"bullet_damage": 6,
		"bullet_speed": 1.1,
		"slow_factor": 0.65,
		"slow_duration": 2.0,
	})
	return node

## 剧毒弹 — 命中后附着目标，持续3秒每秒8点伤害
## 设计：DOT型子弹，与黏黏弹（减速）区分；克制护盾类怪物（DOT无法被格挡）
## 弱点：DOT伤害需要时间累积，对付快速击杀无效
static func bullet_poison() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Poison")
	node.tags = ["bullet", "poison", "dot"]
	node.set_base_stats({
		"bullet_damage": 5,
		"bullet_speed": 0.9,
		"dot_dps": 8.0,
		"dot_duration": 3.0,
		"dot_type": "poison",
	})
	return node

## EMP弹 — 命中敌人后瘫痪其主动技能2秒，对召唤型/护盾型敌人有特效
## 设计：控制型子弹，适合对付技能型敌人（召唤小怪、护盾格挡、治疗光环）
## 克制：Summoner（瘫痪召唤）、Tank（瘫痪盾墙）、Trapper（瘫痪毒云）
## 弱点：对Chaser/Bomber无效（它们没有主动技能可瘫痪）
## 对比黏黏弹：黏黏弹是移动控制（减速），EMP弹是技能控制（瘫痪）
static func bullet_emp() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_EMP")
	node.tags = ["bullet", "emp", "disable", "control"]
	node.set_base_stats({
		"bullet_damage": 4,        # 低伤害，主要价值在控制
		"bullet_speed": 1.2,       # 中速，比黏黏弹快
		"disable_duration": 2.0,   # 瘫痪2秒
		"disable_type": "skill",   # 技能瘫痪
	})
	return node

## 跳雷弹 — 碰墙弹跳最多2次，命中敌人或超时后附着并爆炸
## 设计：区域压制型子弹，弥补霰弹枪远距无效的弱点
## 克制：蹲角落的敌人、护盾后方目标（爆炸可以绕过掩体）
## 弱点：弹跳有时间损耗，总伤害比爆炸弹低；且可能弹不到理想位置
## 对比爆炸弹：爆炸弹是直接AOE，跳雷弹是延迟AOE+可以"拐弯"
static func bullet_mine() -> AssemblyNode:
	var node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "Bullet_Mine")
	node.tags = ["bullet", "mine", "bounce", "area"]
	node.set_base_stats({
		"bullet_damage": 12,       # 爆炸伤害中等
		"bullet_speed": 1.3,       # 较快
		"bounce_max": 2,          # 最多弹跳2次
		"stick_duration": 1.5,     # 附着1.5秒后爆炸
		"explosion_radius": 55.0,  # 爆炸半径
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
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	return tree

## 手枪 + 穿甲子弹
static func build_pistol_piercing() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_pistol()
	var bul := bullet_piercing()
	tree.set_root(gun)
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	return tree

## 霰弹枪 + 爆炸弹
static func build_shotgun_explosive() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_shotgun()
	var bul := bullet_explosive()
	tree.set_root(gun)
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	return tree

## 冲锋枪 + 高速弹
static func build_smg_hyper() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_smg()
	var bul := bullet_hyper()
	tree.set_root(gun)
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	return tree

## 狙击枪 + 穿甲弹（带枪口制动器）
static func build_sniper() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_sniper()
	var bul := bullet_piercing()
	var att := att_muzzle_brake()
	tree.set_root(gun)
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	tree.mount(gun, AssemblyNode.SlotType.MUZZLE, att)
	return tree

## 榴弹发射器 + 爆炸弹
static func build_launcher() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_launcher()
	var bul := bullet_explosive()
	tree.set_root(gun)
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	return tree

## 爆发突击步枪 + 穿甲弹
static func build_burst_rifle() -> WeaponAssemblyTree:
	var tree := WeaponAssemblyTree.new()
	var gun := gun_burst_rifle()
	var bul := bullet_piercing()
	tree.set_root(gun)
	tree.mount(gun, AssemblyNode.SlotType.BULLET, bul)
	return tree

## ========== 预设注册表（用于武器切换）==========
## 键为数字索引（1-7），方便按键切换
static func get_preset_by_index(idx: int) -> WeaponAssemblyTree:
	match idx:
		1: return build_rifle()
		2: return build_pistol_piercing()
		3: return build_shotgun_explosive()
		4: return build_smg_hyper()
		5: return build_sniper()
		6: return build_launcher()
		7: return build_burst_rifle()
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
		7: return "爆发突击步枪 + 穿甲弹"
	return "步枪"
