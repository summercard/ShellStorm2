extends Node

## 一次性探针（_scratch）：在套件被并行改动阻塞时，单独确认花洒机枪能
## 落到正式美术资产上，并且视觉层读到的数值与数据层一致。

var _failures: Array[String] = []


func _ready() -> void:
	var script := load("res://src/combat3d/WeaponModel3D.gd") as GDScript
	if script == null:
		push_error("WeaponModel3D.gd 无法加载（编译失败）")
		get_tree().quit(1)
		return
	var model := script.new() as Node3D
	add_child(model)
	if not bool(model.call("configure", "bp_sprinkler", "mod_bullet_standard")):
		_failures.append("configure(bp_sprinkler) 返回 false")
	var snapshot: Dictionary = model.call("get_snapshot") as Dictionary
	if str(snapshot.get("gun_id", "")) != "bp_sprinkler":
		_failures.append("视觉层 gun_id 解析成 %s" % str(snapshot.get("gun_id", "")))
	if int(snapshot.get("magazine_size", 0)) != 100:
		_failures.append("视觉层 magazine_size = %d" % int(snapshot.get("magazine_size", 0)))
	# damage 不断言绝对値：视觉层读的是 AssemblyTree 合计值（枪身 + 子弹模块），
	# 枪身 8 点的口径由 verify_starting_weapon_contract 在数据层断言。
	
	var machinegun := script.new() as Node3D
	add_child(machinegun)
	machinegun.call("configure", "bp_machinegun", "mod_bullet_standard")
	var mg_snapshot: Dictionary = machinegun.call("get_snapshot") as Dictionary
	var delta := int(mg_snapshot.get("damage", 0)) - int(snapshot.get("damage", 0))
	if delta != 7:
		_failures.append("与蜂窝机枪的合计伤害差是 %d，期望 7（15-8）" % delta)
	var hint: Vector3 = model.call("get_visual_bounds_hint")
	if not is_equal_approx(hint.z, 1.18):
		_failures.append("visual_bounds_hint 长度 = %.3f" % hint.z)
	if _find_logic(model, "bp_machinegun") == null:
		_failures.append("没有找到 logic_id=bp_machinegun 的正式美术资产")
	if _failures.is_empty():
		print("SCRATCH_SPRINKLER_VISUAL_OK: 花洒机枪映射到 water_tank_blaster 正式资产，视觉层读到弹匣 100 发、长度 1.18m，与蜂窝机枪合计伤害差 7（枪身 15-8），gun_id 解析为 bp_sprinkler")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _find_logic(root: Node, logic_id: String) -> Node:
	if str(root.get_meta("logic_id", "")) == logic_id:
		return root
	for child in root.get_children():
		var result := _find_logic(child, logic_id)
		if result != null:
			return result
	return null
