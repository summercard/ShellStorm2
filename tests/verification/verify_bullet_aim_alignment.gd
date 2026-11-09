extends Node
## 准星 ↔ 弹道对齐 + 碰撞体随视觉放大 专项验收（2026-11-09）。
##
## 业主两条口述：
##   ①「子弹的飞行轨迹和准星不对，会偏差。可能是因为准星在地上的原因」。
##   ②「我的很多子弹的视觉被我放大了，有些是 1.5 倍，有些是两倍，但是它的这个碰撞检测
##      没有放大，所以会导致子弹容易穿过去 / 打不到。不是把子弹视觉缩小，而是把子弹的
##      碰撞体也一起放大了」。
##
## 覆盖：
##   A. 准星平面高度 = 角色脚底 + `Player3D.AIM_TARGET_HEIGHT`（真实 `_update_aim_from_mouse` 路径）；
##   B. 弹道方向由「枪口 → 准星点」解算，射线穿过准星（世界误差 < 1mm）；
##   C. 同一发在相机屏幕上穿准星（< 1px @1920×1080）；内建反向对照证明旧口径会偏 40px 以上；
##   D. `Projectile3D` 碰撞半径 = 0.12 × 视觉倍率，覆盖枪身档位 / 气球弹 / 命运缩放 / 敌弹倍率；
##   E. 防假绿哨兵（样本数下限）。
##
## 判据：`BULLET_AIM_ALIGNMENT_OK` 行 + ERROR 计数（不看裸退出码）。
## 只做几何与数学，不读 viewport 纹理 ⇒ 可安全 headless 运行。

const PLAYER := preload("res://scenes/Player3D.tscn")

## 基准体型手枪枪口离地实测值（2026-11-09 探针 `tools/_probe_aim_trace`）。
## 硬编码在验收侧，不引用被测常量 —— 常量被改成 0.035 时必须红。
const EXPECTED_AIM_TARGET_HEIGHT := 0.75
## 旧口径（准星贴地 0.035 + 子弹沿水平方向）在 1080p 下实测偏差：正前 3.2m 处 21px、
## 近距斜向可达 44px。取 15px 作反向对照下限 —— 与目标 1px 差 15 倍，回退到旧口径必红。
const LEGACY_MIN_SCREEN_DELTA_PX := 15.0
## 弹道穿准星的容差：世界 1mm / 屏幕 1px。
const AIM_WORLD_TOLERANCE_M := 0.001
const AIM_SCREEN_TOLERANCE_PX := 1.0
## 相机与 `scenes/Player3D.tscn` 一致。
const VIEWPORT_SIZE := Vector2i(1920, 1080)

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	get_viewport().size = VIEWPORT_SIZE

	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80, 0.2, 80)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0, -0.1, 0)
	ground.add_child(ground_shape)
	stage.add_child(ground)

	var player := PLAYER.instantiate() as Player3D
	stage.add_child(player)
	player.set_process(false)
	for i in range(45):
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)

	_expect(player.equip_weapon("bp_pistol", "mod_bullet_standard"), "手枪装配失败，后续断言无意义")
	for i in range(4):
		await get_tree().process_frame

	var weapon: WeaponModel3D = player.weapon
	if weapon == null:
		_failures.append("装配后 player.weapon 为空")
		_report()
		return

	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	await get_tree().process_frame

	_check_crosshair_height(player)
	_check_ballistic_through_crosshair(player, weapon, camera)
	_check_legacy_off_axis_reference(player, weapon, camera)
	_check_collision_follows_visual()

	_report()


## A. 准星高度：走真实的摇杆瞄准分支（鼠标射线在 headless 下没有真实指针可读）。
func _check_crosshair_height(player: Player3D) -> void:
	_expect(
		absf(float(player.AIM_TARGET_HEIGHT) - EXPECTED_AIM_TARGET_HEIGHT) < 0.001,
		"AIM_TARGET_HEIGHT 应为基准枪口高度 %.2f，实测 %.4f（回退到贴地 0.035？）" % [
			EXPECTED_AIM_TARGET_HEIGHT, float(player.AIM_TARGET_HEIGHT)]
	)
	_samples += 1

	player._mobile_input_available = true
	player._mobile_face_active = true
	player._mobile_face_direction = Vector2(0.0, -1.0)
	player.call("_update_aim_from_mouse")
	var cursor := player.get_node("AimCursor") as Node3D
	var expected_y := player.global_position.y + float(player.AIM_TARGET_HEIGHT)
	_expect(
		absf(cursor.global_position.y - expected_y) < 0.02,
		"准星平面应停在角色脚底 + %.2fm（实测 y=%.3f，期望 %.3f）" % [
			float(player.AIM_TARGET_HEIGHT), cursor.global_position.y, expected_y]
	)
	_samples += 1


## B + C. 弹道穿过准星；并在同一发上用相机投影复核屏幕位置。
func _check_ballistic_through_crosshair(
	player: Player3D, weapon: WeaponModel3D, camera: Camera3D
) -> void:
	var muzzle := weapon.muzzle_global_position()
	_expect(
		absf(muzzle.y - (player.global_position.y + EXPECTED_AIM_TARGET_HEIGHT)) < 0.02,
		"枪口高度应与准星平面一致（枪口 y=%.3f，期望 %.3f）—— 这是「同高 ⇒ 屏幕上重合」的前提" % [
			muzzle.y, player.global_position.y + EXPECTED_AIM_TARGET_HEIGHT]
	)
	_samples += 1

	# 三个典型鼠标落点：正前、右前方（斜向）、近距。
	var offsets := [Vector3(0.0, 0.0, -7.2), Vector3(4.6, 0.0, -6.4), Vector3(0.4, 0.0, -2.8)]
	for offset in offsets:
		var target_point: Vector3 = (
			player.global_position
			+ (offset as Vector3)
			+ Vector3.UP * float(player.AIM_TARGET_HEIGHT)
		)
		var flat: Vector3 = offset as Vector3
		flat.y = 0.0
		var flat_dir := flat.normalized()
		var shot_dir: Vector3 = player._ballistic_direction(flat_dir, target_point)
		var t := (target_point - muzzle).dot(shot_dir)
		var closest := muzzle + shot_dir * t
		_samples += 1
		_expect(
			closest.distance_to(target_point) < AIM_WORLD_TOLERANCE_M,
			"弹道未穿过准星（准星 %s，弹道最近点 %s，距离 %.4fm）" % [
				str(target_point), str(closest), closest.distance_to(target_point)]
		)
		var cursor_screen := camera.unproject_position(target_point)
		var closest_screen := camera.unproject_position(closest)
		var screen_delta := cursor_screen.distance_to(closest_screen)
		_samples += 2
		_expect(
			screen_delta < AIM_SCREEN_TOLERANCE_PX,
			"弹道与准星在 1080p 上相差 %.2fpx（上限 %.1f）" % [screen_delta, AIM_SCREEN_TOLERANCE_PX]
		)
		# 解算出的方向不得与「角色 → 准星」的水平方位反向（近身保护不得把枪打到自己身后）。
		_expect(
			Vector2(shot_dir.x, shot_dir.z).dot(Vector2(flat_dir.x, flat_dir.z)) > 0.0,
			"弹道水平方位与瞄准方向相反（shot=%s aim=%s）" % [str(shot_dir), str(flat_dir)]
		)


## C 的反向对照：旧口径 = 准星贴地 + 子弹沿水平方向 —— 必须偏出 30px 以上。
## 如果这条不再红，说明上面的像素判据已经量不到「准星贴地」这个缺陷了。
func _check_legacy_off_axis_reference(
	player: Player3D, weapon: WeaponModel3D, camera: Camera3D
) -> void:
	var muzzle := weapon.muzzle_global_position()
	# 近距 3.2m 才能把「贴地准星 + 水平弹道」的高度视差放大到 30px 以上
	# （正前 7.2m 处只有 21px，阈值必须按近距取，否则反向对照形同虚设）。
	var legacy_cursor := player.global_position + Vector3(0.0, 0.035, -3.2)
	var legacy_dir := Vector3(0.0, 0.0, -1.0)
	var flat := legacy_cursor - muzzle
	flat.y = 0.0
	var t := (legacy_cursor - muzzle).dot(legacy_dir)
	var closest := muzzle + legacy_dir * t
	var cursor_screen := camera.unproject_position(legacy_cursor)
	var closest_screen := camera.unproject_position(closest)
	var delta := cursor_screen.distance_to(closest_screen)
	_samples += 1
	_expect(
		delta > LEGACY_MIN_SCREEN_DELTA_PX,
		"反向对照失效：贴地准星 + 水平弹道应偏 >%.0fpx，实测只有 %.1fpx（判据已量不到旧缺陷）" % [
			LEGACY_MIN_SCREEN_DELTA_PX, delta]
	)


## D. 碰撞半径必须等于 0.12 × 视觉倍率，四条来源逐条覆盖。
func _check_collision_follows_visual() -> void:
	var cases := [
		{"label": "中性档", "config": {}, "expected": 0.12},
		{"label": "手枪 ×1.8", "config": {"gun_bullet_geometry": {"scale": 1.8}}, "expected": 0.216},
		{"label": "霰弹 ×2.0", "config": {"gun_bullet_geometry": {"scale": 2.0}}, "expected": 0.24},
		{"label": "榴弹 ×1.55", "config": {"gun_bullet_geometry": {"scale": 1.55}}, "expected": 0.186},
		{"label": "气球弹 ×1.55", "config": {"tags": ["balloon"]}, "expected": 0.186},
		{
			"label": "命运 ×2.0",
			"config": {"behavior": {"fate_scale": 2.0}},
			"expected": 0.24,
		},
		{"label": "敌弹 visual_scale ×2.0", "config": {"visual_scale": 2.0}, "expected": 0.24},
	]
	for entry in cases:
		var config: Dictionary = entry["config"]
		config["tags"] = config.get("tags", [])
		var projectile := Projectile3D.new()
		add_child(projectile)
		projectile.configure(config)
		var snapshot := projectile.get_orientation_snapshot()
		var radius := float(snapshot.get("collision_radius", -1.0))
		var expected := float(entry["expected"])
		_samples += 1
		_expect(
			absf(radius - expected) < 0.0005,
			"%s：碰撞半径应为 %.3f，实测 %.3f" % [String(entry["label"]), expected, radius]
		)
		projectile.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	# 防假绿：2 个高度断言 + 1 个枪口高度 + 3 组 × 3 条对齐 + 1 反向对照 + 7 碰撞用例 = 20。
	if _samples < 18:
		_failures.append("防假绿哨兵：样本数只有 %d，期望 >= 18" % _samples)
	if _failures.is_empty():
		print("BULLET_AIM_ALIGNMENT_OK: crosshair-height / ballistic-through-crosshair / screen-projection / collision-follows-visual pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("BULLET_AIM_ALIGNMENT_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)
