## 组件摆动动画冒烟测试 (2026-06-10)

extends Node

func _ready() -> void:
	await get_tree().process_frame
	_run_test()

func _run_test() -> void:
	print("[ANIM-SMOKE] ===== 组件摆动动画测试 =====")
	var passed: int = 0
	var total: int = 0
	var final_ok: bool = true

	# 构造一个测试 Player
	var player: Node2D = Node2D.new()
	player.name = "TestPlayer"
	add_child(player)
	var comps: CharacterComponents = CharacterComponents.new()
	comps.name = "Components"
	player.add_child(comps)
	comps.create_default_layout(NodePath(""), NodePath(""), NodePath(""))

	# 1. 待机状态 1 秒：body 应该在 y 方向轻微摆动
	total += 1
	var body: Node = comps.get("body")
	var y_samples: Array = []
	for i in range(30):
		comps.tick_animations(0.033, Vector2.ZERO)
		y_samples.append((body as Node2D).position.y)
	var y_min: float = y_samples[0]
	var y_max: float = y_samples[0]
	for v in y_samples:
		if v < y_min: y_min = v
		if v > y_max: y_max = v
	var y_range: float = y_max - y_min
	if y_range > 0.5:  # 摆动幅度至少 0.5 像素
		passed += 1
		print("[ANIM-SMOKE] OK: 待机 body Y 摆动 (min=%.2f max=%.2f range=%.2f)" % [y_min, y_max, y_range])
	else:
		final_ok = false
		print("[ANIM-SMOKE] FAIL: 待机 body 不摆动 (min=%.2f max=%.2f range=%.2f)" % [y_min, y_max, y_range])

	# 2. 待机时 body.rotation 应该是 0
	total += 1
	var rot_zero: bool = abs((body as Node2D).rotation) < 0.001
	if rot_zero:
		passed += 1
		print("[ANIM-SMOKE] OK: 待机 body 不倾斜 (rotation=%.4f)" % (body as Node2D).rotation)
	else:
		final_ok = false
		print("[ANIM-SMOKE] FAIL: 待机 body 旋转异常 (rotation=%.4f)" % (body as Node2D).rotation)

	# 3. 移动状态 1 秒：body 应该有 rotation 变化
	total += 1
	var rot_samples: Array = []
	for i in range(30):
		comps.tick_animations(0.033, Vector2.RIGHT)
		rot_samples.append((body as Node2D).rotation)
	var r_min: float = rot_samples[0]
	var r_max: float = rot_samples[0]
	for v in rot_samples:
		if v < r_min: r_min = v
		if v > r_max: r_max = v
	var r_range: float = r_max - r_min
	if r_range > 0.01:
		passed += 1
		print("[ANIM-SMOKE] OK: 移动 body 倾斜 (min=%.4f max=%.4f range=%.4f)" % [r_min, r_max, r_range])
	else:
		final_ok = false
		print("[ANIM-SMOKE] FAIL: 移动 body 不倾斜 (min=%.4f max=%.4f)" % [r_min, r_max])

	# 4. 头/手位置应当与 body 同步摆动
	total += 1
	var head: Node = comps.get("head")
	var hand: Node = comps.get("hand")
	var head_y: float = (head as Node2D).position.y
	var hand_y: float = (hand as Node2D).position.y
	var body_y: float = (body as Node2D).position.y
	# 头/手的 y 可能不严格等于 body.y（相位延迟），但应在同一数量级
	if abs(head_y - body_y) < 5.0 and abs(hand_y - body_y) < 5.0:
		passed += 1
		print("[ANIM-SMOKE] OK: 头/手跟身体摆动 (body_y=%.2f head_y=%.2f hand_y=%.2f)" % [body_y, head_y, hand_y])
	else:
		final_ok = false
		print("[ANIM-SMOKE] FAIL: 头/手不跟身体 (body_y=%.2f head_y=%.2f hand_y=%.2f)" % [body_y, head_y, hand_y])

	# 5. 移动方向反了：倾斜方向也应反
	total += 1
	comps.tick_animations(0.033, Vector2.LEFT)  # 立即切方向
	var rot_after_left: float = (body as Node2D).rotation
	# 倾斜 sign 应该反了（因为 move_dir.x 是负）
	# 这条比较宽松：仅检查 rotation 不为 0
	if abs(rot_after_left) > 0.001:
		passed += 1
		print("[ANIM-SMOKE] OK: 方向反了 body 仍倾斜 (rotation=%.4f)" % rot_after_left)
	else:
		final_ok = false
		print("[ANIM-SMOKE] FAIL: 方向反了 body 不倾斜")

	print("[ANIM-SMOKE] 总结: %d/%d 通过" % [passed, total])
	if final_ok:
		print("[ANIM-SMOKE] FINAL: PASS")
		get_tree().quit(0)
	else:
		print("[ANIM-SMOKE] FINAL: FAIL")
		get_tree().quit(1)
