class_name EnemyHitVolume3D
extends StaticBody3D
## 「动画受击体积」的承载节点。
##
## 为什么必须另起一个物理体、而不是把形状直接挂在敌人身上：
## 受击盒是**贴着模型**走的，模型会伸进地面（坐地、倒地）和墙里（扑砸、甩击）。
## 如果这些形状属于 `Enemy3D` 自己，`move_and_slide` 就会把它们当承重面 ——
## 实测坐地时怪物被顶高 **0.42 m**、砸地时被推开 **0.26 m**（见《Boss002显示器技能设计》
## 的实测表）。所以受击盒只能做「子弹打得到、但谁也不挡」的被动碰撞体：
##   - `collision_layer = 4`（第 3 层，与敌人本体同层）⇒ 玩家子弹（掩码 1|4）打得到；
##   - `collision_mask = 0` ⇒ 它自己不检测任何东西，不参与任何移动。
##
## 命中后必须把伤害转交本体：子弹拿到的 `collider` 是这个代理，
## 而伤害/状态/掉落的所有权在 `Enemy3D`。转发清单只有下面这几个入口 ——
## `verify_monitor_boss_flow` 逐条断言它们都存在，新增伤害入口漏转发会直接把那条用例弄红。

## 伤害与状态的真正归属（`Enemy3D`）。
var owner_enemy: Node = null


func bind(enemy: Node) -> void:
	owner_enemy = enemy


func _owner_alive() -> bool:
	return owner_enemy != null and is_instance_valid(owner_enemy)


func take_projectile_damage(
	amount: int,
	critical := false,
	hit_direction := Vector3.ZERO,
	tags: Array[String] = [],
	behavior: Dictionary = {},
	attacker: Node3D = null,
	knockback := 0.0
) -> void:
	if _owner_alive():
		owner_enemy.call("take_projectile_damage", amount, critical, hit_direction, tags, behavior, attacker, knockback)


func take_damage(amount: int, critical := false, hit_direction := Vector3.ZERO, knockback := 0.0) -> void:
	if _owner_alive():
		owner_enemy.call("take_damage", amount, critical, hit_direction, knockback)


func notify_attacked_by(attacker: Node3D) -> void:
	if _owner_alive():
		owner_enemy.call("notify_attacked_by", attacker)


func can_absorb_projectile(tags: Array[String]) -> bool:
	return _owner_alive() and bool(owner_enemy.call("can_absorb_projectile", tags))


func on_projectile_absorbed(absorbed_damage: int) -> void:
	if _owner_alive():
		owner_enemy.call("on_projectile_absorbed", absorbed_damage)


func apply_slow(factor: float, duration: float) -> void:
	if _owner_alive():
		owner_enemy.call("apply_slow", factor, duration)


func apply_damage_over_time(total_damage: int, duration: float) -> void:
	if _owner_alive():
		owner_enemy.call("apply_damage_over_time", total_damage, duration)


func apply_pull(origin: Vector3, strength: float) -> void:
	if _owner_alive():
		owner_enemy.call("apply_pull", origin, strength)


func apply_fate_element(element: String, params: Dictionary, weapon_damage: int, source: WeaponAssemblyTree, attacker: Node3D) -> void:
	if _owner_alive():
		owner_enemy.call("apply_fate_element", element, params, weapon_damage, source, attacker)
