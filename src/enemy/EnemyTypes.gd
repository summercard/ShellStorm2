extends Node
class_name EnemyTypeRegistry

# EnemyTypes.gd — 6种基础怪物类型工厂
# 每种类型是一个可实例化的场景+脚本组合
# 统一接口：spawn(position: Vector2) -> CharacterBody2D

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const SKILL_COMPONENT_SCRIPT := preload("res://src/enemy/components/EnemySkillComponent.gd")

## ========== 1. 近战追击型 — 小菌猪 ==========
## 特点：贴脸追击，速度快，血量低，伤害中
## 技能：冲刺猛击（突进眩晕）+ 狂暴化（低血量移速+40%）
static func spawn_chaser(pos: Vector2) -> CharacterBody2D:
	var enemy := _spawn_base(pos)
	enemy.max_hp = 20
	enemy.speed = 120.0
	enemy.damage = 12
	enemy.get_node("Shape").color = Color(0.6, 1.0, 0.4, 1.0)  # 绿色
	var skill_comp := EnemySkillComponent.inject_chaser_skill(enemy)
	enemy.add_child(skill_comp)
	skill_comp.set_component_owner(enemy)
	return enemy

## ========== 2. 远程弹幕型 — 孢子射手 ==========
## 特点：保持距离，周期性发射投射物，速度慢
## 技能：散射弹幕（3发偏移）+ 警戒射击（被近身时后退反击）
static func spawn_ranged(pos: Vector2) -> CharacterBody2D:
	var enemy := _spawn_base(pos)
	enemy.max_hp = 25
	enemy.speed = 50.0
	enemy.damage = 8
	enemy.get_node("Shape").color = Color(0.9, 0.5, 0.9, 1.0)  # 紫色
	# 添加远程行为组件
	enemy.set("ai_type", "ranged")
	enemy.set("shoot_interval", 2.0)
	var skill_comp := EnemySkillComponent.inject_ranged_skill(enemy)
	enemy.add_child(skill_comp)
	skill_comp.set_component_owner(enemy)
	return enemy

## ========== 3. 召唤型 — 蜂巢怪 ==========
## 特点：每隔一段时间生成小怪协助作战
## 技能：持续召唤小怪 + 母巢光环（召唤物强化）
static func spawn_summoner(pos: Vector2) -> CharacterBody2D:
	var enemy := _spawn_base(pos)
	enemy.max_hp = 40
	enemy.speed = 30.0
	enemy.damage = 5
	enemy.get_node("Shape").color = Color(0.8, 0.7, 0.2, 1.0)  # 黄色
	enemy.set("ai_type", "summoner")
	enemy.set("summon_interval", 5.0)
	var skill_comp := EnemySkillComponent.inject_summoner_skill(enemy)
	enemy.add_child(skill_comp)
	skill_comp.set_component_owner(enemy)
	return enemy

## ========== 4. 护盾型 — 壳甲卫兵 ==========
## 特点：高血量，低速度，有护盾格挡部分伤害
## 技能：盾击（冲锋眩晕）+ 钢铁意志（15%几率完全抵挡伤害）
static func spawn_tank(pos: Vector2) -> CharacterBody2D:
	var enemy := _spawn_base(pos)
	enemy.max_hp = 60
	enemy.speed = 40.0
	enemy.damage = 15
	enemy.get_node("Shape").color = Color(0.4, 0.5, 0.8, 1.0)  # 蓝色
	enemy.set("has_shield", true)
	enemy.set("shield_rate", 0.3)  # 30% 概率格挡
	var skill_comp := EnemySkillComponent.inject_tank_skill(enemy)
	enemy.add_child(skill_comp)
	skill_comp.set_component_owner(enemy)
	return enemy

## ========== 5. 自爆型 — 膨胀鼠 ==========
## 特点：低血量，接近玩家后自爆造成范围伤害
## 技能：地刺陷阱（延迟爆炸区域）+ 碎片飞溅（死亡散射8颗碎片）
static func spawn_bomber(pos: Vector2) -> CharacterBody2D:
	var enemy := _spawn_base(pos)
	enemy.max_hp = 12
	enemy.speed = 90.0
	enemy.damage = 0  # 爆炸伤害不体现在此
	enemy.get_node("Shape").color = Color(1.0, 0.3, 0.3, 1.0)  # 红色
	enemy.set("ai_type", "bomber")
	enemy.set("explosion_radius", 80.0)
	enemy.set("explosion_damage", 25)
	var skill_comp := EnemySkillComponent.inject_bomber_skill(enemy)
	enemy.add_child(skill_comp)
	skill_comp.set_component_owner(enemy)
	return enemy

## ========== 6. 潜伏型 — 地刺虫 ==========
## 特点：在玩家靠近前保持静止，低血量，攻击窗口短
## 技能：地刺陷阱 + 诱捕孢子（被攻击时释放减速区域）
static func spawn_trapper(pos: Vector2) -> CharacterBody2D:
	var enemy := _spawn_base(pos)
	enemy.max_hp = 15
	enemy.speed = 0.0  # 默认静止
	enemy.damage = 20
	enemy.get_node("Shape").color = Color(0.5, 0.3, 0.2, 1.0)  # 棕色
	enemy.set("ai_type", "trapper")
	enemy.set("trigger_radius", 100.0)
	var skill_comp := EnemySkillComponent.inject_trapper_skill(enemy)
	enemy.add_child(skill_comp)
	skill_comp.set_component_owner(enemy)
	return enemy

## ========== 内部工具 ==========

static func _spawn_base(pos: Vector2) -> CharacterBody2D:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
	enemy.position = pos
	enemy.current_hp = enemy.max_hp
	# 禁用默认追击（由各类型自己决定行为）
	enemy.set("use_default_chase", false)
	return enemy

## ========== 词缀系统接入 ==========

## 为敌人应用精英词缀
static func apply_modifier(enemy: CharacterBody2D, modifier_id: String, tier: int = 1) -> void:
	if enemy.has_method("add_modifier"):
		enemy.add_modifier(modifier_id, tier)
