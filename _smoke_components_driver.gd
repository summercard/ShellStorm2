## 角色组件系统冒烟测试驱动 (2026-06-10)

extends Node

func _ready() -> void:
	await get_tree().process_frame
	_run_test()

func _run_test() -> void:
	print("[SMOKE-COMPONENTS] ====== 角色组件系统冒烟测试 ======")
	var passed: int = 0
	var total: int = 0
	var final_ok: bool = true
	
	# 1. 创建 CharacterComponents + 默认布局
	var comps: CharacterComponents = CharacterComponents.new()
	comps.name = "Components"
	var char_node: Node2D = get_tree().root.find_child("Char", true, false)
	char_node.add_child(comps)
	comps.create_default_layout(
		NodePath("/root/SmokeRoot/Char/BodyVis"),
		NodePath("/root/SmokeRoot/Char/HeadVis"),
		NodePath("/root/SmokeRoot/Char/HandVis")
	)
	total += 1
	var has_body: bool = comps.get("body") != null
	var has_head: bool = comps.get("head") != null
	var has_hand: bool = comps.get("hand") != null
	if has_body and has_head and has_hand:
		passed += 1
		print("[SMOKE-COMPONENTS] OK: body/head/hand 都创建")
	else:
		final_ok = false
		print("[SMOKE-COMPONENTS] FAIL: 组件创建缺失 body=%s head=%s hand=%s" % [has_body, has_head, has_hand])
	
	# 2. 验证 hand 有 WeaponAnchor
	total += 1
	var hand_obj: Node = comps.get("hand")
	var anchor: Marker2D = null
	if hand_obj != null and hand_obj.has_method("get_weapon_anchor"):
		anchor = hand_obj.get_weapon_anchor()
	if anchor != null:
		passed += 1
		print("[SMOKE-COMPONENTS] OK: hand 有 WeaponAnchor (%s)" % anchor.get_path())
	else:
		final_ok = false
		print("[SMOKE-COMPONENTS] FAIL: hand 缺少 WeaponAnchor")
	
	# 3. attach_weapon_to_hand 测试
	total += 1
	var weapon: Node2D = Node2D.new()
	weapon.name = "TestWeapon"
	var ok: bool = comps.attach_weapon_to_hand(weapon)
	if ok and weapon.get_parent() == anchor:
		passed += 1
		print("[SMOKE-COMPONENTS] OK: 武器挂到 WeaponAnchor 下")
	else:
		final_ok = false
		print("[SMOKE-COMPONENTS] FAIL: 武器未挂上")
	
	# 4. apply_feedback_all (FLASH_DAMAGE) - 验证 ColorRect 颜色变化
	total += 1
	comps.apply_feedback_all(1, 0.5, 1.0)  # 1 = FLASH_DAMAGE
	var body_node: ColorRect = char_node.get_node("BodyVis")
	# FLASH_DAMAGE 应该把 color 改成 (1,1,1,0.95)
	if body_node.color.r > 0.9 and body_node.color.g > 0.9 and body_node.color.b > 0.9:
		passed += 1
		print("[SMOKE-COMPONENTS] OK: 反馈后 body color 变化 (%s)" % body_node.color)
	else:
		final_ok = false
		print("[SMOKE-COMPONENTS] FAIL: body color 未变 (%s)" % body_node.color)
	
	# 5. 等反馈结束，验证颜色恢复
	total += 1
	await get_tree().create_timer(0.7).timeout
	comps.tick_feedbacks(1.0)  # 推大秒数强制结束
	# 颜色应该恢复成原始 (1, 0.4, 0.4, 1)
	if abs(body_node.color.r - 1.0) < 0.1 and abs(body_node.color.g - 0.4) < 0.1:
		passed += 1
		print("[SMOKE-COMPONENTS] OK: 反馈结束后颜色恢复 (%s)" % body_node.color)
	else:
		final_ok = false
		print("[SMOKE-COMPONENTS] FAIL: 颜色未恢复 (%s)" % body_node.color)
	
	# 6. set_aim_direction 测试（旋转 weapon anchor）
	total += 1
	if hand_obj != null and hand_obj.has_method("set_aim_direction"):
		hand_obj.set_aim_direction(Vector2.RIGHT)
		# anchor.rotation 应该 ≈ 0
		var anchor_rot: float = anchor.rotation
		if abs(anchor_rot) < 0.1:
			passed += 1
			print("[SMOKE-COMPONENTS] OK: hand 瞄准方向生效 (rotation=%.2f)" % anchor_rot)
		else:
			final_ok = false
			print("[SMOKE-COMPONENTS] FAIL: hand 旋转异常 (rotation=%.2f)" % anchor_rot)
	else:
		final_ok = false
		print("[SMOKE-COMPONENTS] FAIL: hand 没有 set_aim_direction 方法")
	
	# 总结
	print("[SMOKE-COMPONENTS] 总结: %d/%d 通过" % [passed, total])
	if final_ok:
		print("[SMOKE-COMPONENTS] FINAL: PASS")
		get_tree().quit(0)
	else:
		print("[SMOKE-COMPONENTS] FINAL: FAIL")
		get_tree().quit(1)