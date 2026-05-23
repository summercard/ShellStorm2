extends Node
## 精英怪词缀组件
## 附加在 EnemyBase 上，为怪物提供额外行为
## 与怪物本体解耦，通过 add_modifier() 添加

class EnemyModifier:
	var modifier_id: String
	var tier: int  # 1-3，影响强度

	func _init(mod_id: String, mod_tier: int = 1):
		modifier_id = mod_id
		tier = mod_tier

	func apply(enemy_node: Node) -> void:
		"""在怪物节点上应用词缀效果"""
		pass

	func remove(enemy_node: Node) -> void:
		"""从怪物节点移除词缀效果"""
		pass


class HugeModifier:
	extends EnemyModifier

	func _init():
		super("Elite.Huge", 1)

	func apply(enemy_node: Node) -> void:
		if enemy_node.has_method("apply_scale"):
			enemy_node.apply_scale(1.5 + tier * 0.25)
		var hp_value = enemy_node.get("max_hp")
		if hp_value != null:
			enemy_node.set("max_hp", int(hp_value * (1.3 + tier * 0.1)))
			enemy_node.set("current_hp", enemy_node.get("max_hp"))


class SpawnOnDeathModifier:
	extends EnemyModifier

	func _init():
		super("Elite.SpawnOnDeath", 1)

	func apply(enemy_node: Node) -> void:
		enemy_node.connect("enemy_died", _on_enemy_died)

	func _on_enemy_died() -> void:
		# 生成小怪
		pass  # 由调用方注入具体逻辑


class RicochetModifier:
	extends EnemyModifier

	func _init():
		super("Elite.Ricochet", 2)

	func apply(enemy_node: Node) -> void:
		if enemy_node.has_method("add_bullet_effect"):
			enemy_node.add_bullet_effect("ricochet", tier)


class ParasiteModifier:
	extends EnemyModifier

	func _init():
		super("Elite.Parasite", 2)

	func apply(enemy_node: Node) -> void:
		# 死亡后附着到附近怪物
		enemy_node.connect("enemy_died", _on_enemy_died)

	func _on_enemy_died() -> void:
		# 查找附近怪物并强化
		pass


class WeaponParasiteModifier:
	extends EnemyModifier

	var stolen_skill: Dictionary

	func _init(skill_data: Dictionary):
		super("Elite.WeaponParasite", 3)
		stolen_skill = skill_data

	func apply(enemy_node: Node) -> void:
		# 让精英怪获得玩家的射击技能
		if enemy_node.has_method("add_periodic_skill"):
			enemy_node.add_periodic_skill(stolen_skill, 3.0 / tier)


class Factory:
	static func create(modifier_id: String, tier: int = 1) -> EnemyModifier:
		match modifier_id:
			"Elite.Huge":
				return HugeModifier.new()
			"Elite.SpawnOnDeath":
				return SpawnOnDeathModifier.new()
			"Elite.Ricochet":
				return RicochetModifier.new()
			"Elite.Parasite":
				return ParasiteModifier.new()
			"Elite.WeaponParasite":
				return WeaponParasiteModifier.new({})
			"巨大化":
				return HugeModifier.new()
			"分裂":
				return SpawnOnDeathModifier.new()
			"反弹":
				return RicochetModifier.new()
			"寄生":
				return ParasiteModifier.new()
			"抢枪":
				return WeaponParasiteModifier.new({})
		return null
