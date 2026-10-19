extends Node
## 一次性探针：真实 Player3D 事务下验证「弹药模块手动更换已锁」。
##
## 纯逻辑用例只能证明字段传下去了；这个探针证明 `install_bullet_module_to_weapon_slot`
## 这条真实路径会拒绝。2026-10-19 起**所有枪**都拒绝手动换弹：
##   - 掉落枪：先说明「已绑定」，再指向枪械工坊；
##   - 非掉落枪：说明需在枪械工坊更换。
## 「随机在枪身上」仍保留：掉落枪照旧自带随机弹种。
## 用法：godot --headless --path . res://tools/probe_bullet_lock.tscn

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const SERVICE := preload("res://src/rewards/RewardService.gd")
const BULLET := preload("res://src/weapons/WeaponBulletDrop.gd")

var _failures: Array[String] = []


func _ready() -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame

	# ① 掉落枪：装备后换弹必须被拒
	var report := SERVICE.resolve({
		"spec_id": "bullet_lock:ranged",
		"entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 1}],
	}, {"seed": 20261018, "floor": 1})
	var dropped := (report.get("grants", [])[0] as Dictionary).get("item", {}) as Dictionary
	var equipped := player.equip_weapon_item_to_slot(dropped, 0)
	_expect(bool(equipped.get("success", false)), "掉落枪必须能装备：%s" % str(equipped.get("reason", "")))
	var bound_module := player.get_equipped_bullet_item_for_slot(0)
	var bound_id := str(bound_module.get("id", ""))
	print("  掉落枪自带弹药 = %s（%s）" % [bound_id, bound_module.get("name", "?")])
	_expect(BULLET.is_valid(bound_id), "装备后必须能读到自带弹药模块，实际 '%s'" % bound_id)
	# 局内快捷装配读的是**运行树**上的字段，不是实例；装备后必须已同步过去。
	var runtime_tree := player.get_weapon_tree()
	_expect(runtime_tree != null, "装备后必须存在运行树")
	if runtime_tree != null:
		_expect(
			bool(runtime_tree.get("bullet_module_locked")),
			"装备后运行树必须带弹药绑定锁（否则局内快捷装配能绕过）"
		)

	var swap_target := "mod_bullet_blackhole" if bound_id != "mod_bullet_blackhole" else "mod_bullet_standard"
	var swap_item := ItemRegistry.get_instance().get_item(swap_target)
	var rejected := player.install_bullet_module_to_weapon_slot(swap_item, 0)
	_expect(not bool(rejected.get("success", true)), "掉落枪的弹药模块必须换不动")
	_expect(
		"绑定" in str(rejected.get("reason", "")),
		"拒绝原因应先说明弹药已绑定，实际 '%s'" % str(rejected.get("reason", ""))
	)
	_expect(
		"枪械工坊" in str(rejected.get("reason", "")),
		"拒绝原因应指向枪械工坊，实际 '%s'" % str(rejected.get("reason", ""))
	)
	var after := player.get_equipped_bullet_item_for_slot(0)
	_expect(str(after.get("id", "")) == bound_id, "被拒后弹药模块不得变化（期望 %s，实际 %s）" % [bound_id, str(after.get("id", ""))])

	# ② 非掉落枪（出厂 / 蓝图合成）同样不可手动换弹 —— 总闸关闭，不是只锁掉落枪
	var free_gun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	var free_equipped := player.equip_weapon_item_to_slot(
		WeaponInstance.ensure_weapon_item(free_gun), 0
	)
	_expect(bool(free_equipped.get("success", false)), "非掉落枪必须能装备")
	var free_before := str(player.get_equipped_bullet_item_for_slot(0).get("id", ""))
	var free_swap := player.install_bullet_module_to_weapon_slot(
		ItemRegistry.get_instance().get_item("mod_bullet_piercing"), 0
	)
	_expect(not bool(free_swap.get("success", true)), "非掉落枪也不得手动换弹（2026-10-19 总闸关闭）")
	_expect(
		"枪械工坊" in str(free_swap.get("reason", "")),
		"非掉落枪的拒绝原因应指向枪械工坊，实际 '%s'" % str(free_swap.get("reason", ""))
	)
	_expect(
		str(player.get_equipped_bullet_item_for_slot(0).get("id", "")) == free_before,
		"被拒后非掉落枪的弹种不得变化"
	)

	print("PROBE_BULLET_LOCK_DONE %s" % ("OK" if _failures.is_empty() else "FAILED"))
	for failure in _failures:
		push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
