extends Node
## 准星 / 敌方子弹「面向相机公告板」专项验收（2026-11-09）。
##
## 主人两条口述：
##   ①「准星重新设计，设计成准星的图标，一直面对摄像机的公告板」。
##   ②「敌方子弹也一样」。
##
## 覆盖：
##   A. 准星场景契约：`AimCursor` 只有一个 `Icon` 面片（旧 Torus/点已移除），
##      材质是本项目的 SDF shader，而不是 `BaseMaterial3D` 的 billboard（只绕 Y 轴会压扁）。
##   B. 准星朝向：基向量 = 相机基（余弦 1.0），摇杆与鼠标两条路径一致。
##   C. 准星尺寸：恒定屏幕占比 —— 两个差距很大的瞄准距离下，屏幕像素数必须一样。
##   D. 敌方子弹：billboard 开启、图标可见、3D 弹体隐藏、朝向余弦 1.0、
##      核心直径严格等于判定球直径。**两条路由都要测**（通用弹体 / 八弹种）。
##   E. 玩家子弹：保持 3D 弹体，不出现图标。
##   F. 防假绿哨兵。
##
## 判据：`CROSSHAIR_BILLBOARD_OK` 行 + ERROR 计数（不看裸退出码）。
## 只做几何与节点契约，不读 viewport 纹理 ⇒ 可安全 headless 运行。

const PLAYER := preload("res://scenes/Player3D.tscn")
const CROSSHAIR_SHADER_PATH := "res://assets/art/ui/crosshair/crosshair_icon.gdshader"
const ENEMY_ICON_SHADER_PATH := "res://assets/art/vfx/combat_3d/enemy_bullet_icon.gdshader"

## 准星屏幕占比的期望值（硬编码，不引用被测常量 —— 否则常量改坏时断言永远绿）。
## 6.2% 是**面片**占屏高的比例；图标墨迹只铺到 0.355 UV，可见直径约为它的 71%。
const EXPECTED_SCREEN_RATIO := 0.062
const SCREEN_RATIO_TOLERANCE := 0.012
## 朝向余弦门槛：1.0 = 面片平行于近平面。
const ALIGN_TOLERANCE := 0.002
## 判定球基准半径。
const HIT_RADIUS_M := 0.12

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	get_viewport().size = Vector2i(1920, 1080)
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)

	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(90, 0.2, 90)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0, -0.1, 0)
	ground.add_child(ground_shape)
	stage.add_child(ground)

	var player := PLAYER.instantiate() as Player3D
	stage.add_child(player)
	player.set_process(false)
	for i in range(40):
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.equip_weapon("bp_pistol", "mod_bullet_standard")
	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	await get_tree().process_frame

	_check_crosshair_scene(player)
	_check_crosshair_facing(player, camera)
	_check_crosshair_screen_ratio(player, camera)
	await _check_enemy_bullet_billboard(player, stage)
	await _check_bullet_routes(player, stage)

	_report()


## A. 场景契约：旧 Torus + 圆点必须被移除，不能「加一个图标但不删旧的」。
func _check_crosshair_scene(player: Player3D) -> void:
	var cursor := player.get_node_or_null("AimCursor") as Node3D
	_expect(cursor != null, "Player3D 缺少 AimCursor 节点")
	if cursor == null:
		return
	_samples += 1
	var names: Array[String] = []
	for child in cursor.get_children():
		names.append(String(child.name))
	_expect(
		names == ["Icon"],
		"准星应只有 Icon 一个子节点（旧 Ring/Dot 未删？），实测 %s" % str(names)
	)
	var icon := cursor.get_node_or_null("Icon") as MeshInstance3D
	_expect(icon != null, "准星缺少 Icon 面片")
	if icon == null:
		return
	_samples += 1
	_expect(icon.mesh is QuadMesh, "准星图标必须是 QuadMesh 面片，实测 %s" % (
		icon.mesh.get_class() if icon.mesh != null else "null"
	))
	var material := icon.material_override as ShaderMaterial
	_expect(material != null, "准星图标必须用 ShaderMaterial（SDF 抗锯齿），实测 %s" % (
		icon.material_override.get_class() if icon.material_override != null else "null"
	))
	if material == null:
		return
	_samples += 1
	_expect(
		material.shader != null and material.shader.resource_path == CROSSHAIR_SHADER_PATH,
		"准星图标应引用 %s，实测 %s" % [
			CROSSHAIR_SHADER_PATH,
			material.shader.resource_path if material.shader != null else "null",
		]
	)
	# 反面：材质不能是 StandardMaterial3D 的 billboard —— 那条路径只绕 Y 轴。
	_expect(
		not (icon.material_override is StandardMaterial3D),
		"准星不得回退到 StandardMaterial3D.billboard（只绕 Y 轴，俯视会压扁成椭圆）"
	)


## B. 朝向：摇杆路径与鼠标路径都必须把基向量设成相机基。
func _check_crosshair_facing(player: Player3D, camera: Camera3D) -> void:
	var cursor := player.get_node("AimCursor") as Node3D
	player._mobile_input_available = true
	player._mobile_face_active = true
	player._mobile_face_direction = Vector2(0.0, -1.0)
	player.call("_update_aim_from_mouse")
	await get_tree().process_frame
	_samples += 1
	var stick_align := cursor.global_transform.basis.z.normalized().dot(
		camera.global_transform.basis.z.normalized()
	)
	_expect(
		stick_align > 1.0 - ALIGN_TOLERANCE,
		"摇杆路径准星未正对相机（法线与光轴余弦 %.4f，期望 1.0）" % stick_align
	)

	# 鼠标路径：直接摆一个点再校朝向，绕开 headless 下没有真实指针的限制。
	_samples += 1
	player._mobile_face_active = false
	player.call("_place_aim_cursor", player.global_position + Vector3(1.5, 0.75, -4.0))
	await get_tree().process_frame
	var mouse_align := cursor.global_transform.basis.z.normalized().dot(
		camera.global_transform.basis.z.normalized()
	)
	_expect(
		mouse_align > 1.0 - ALIGN_TOLERANCE,
		"鼠标路径准星未正对相机（余弦 %.4f，期望 1.0）" % mouse_align
	)

	# 反面：如果朝向被写成「绕 Y 轴转」，俯视下俯仰分量会丢，余弦会掉到 0.7 量级。
	_expect(
		absf(cursor.global_transform.basis.z.normalized().y - camera.global_transform.basis.z.normalized().y) < 0.001,
		"准星基向量丢了俯仰分量（Y-billboard 的典型症状）"
	)


## C. 恒定屏幕占比：近距离与远距离的屏幕像素数必须相同（±容差）。
func _check_crosshair_screen_ratio(player: Player3D, camera: Camera3D) -> void:
	var near_pos := player.global_position + Vector3(0.0, 0.75, -2.0)
	var far_pos := player.global_position + Vector3(0.0, 0.75, -16.0)
	var near_px := _cursor_screen_px(player, camera, near_pos)
	var far_px := _cursor_screen_px(player, camera, far_pos)
	_samples += 2
	_expect(
		near_px > 1.0 and far_px > 1.0,
		"准星屏幕像素测不到（near=%.2f far=%.2f）" % [near_px, far_px]
	)
	_expect(
		absf(near_px - far_px) / maxf(near_px, far_px) < 0.05,
		"准星未做恒定屏幕尺寸补偿：近 %.1fpx / 远 %.1fpx" % [near_px, far_px]
	)
	var viewport_height := float(get_viewport().get_visible_rect().size.y)
	var expected_px := viewport_height * EXPECTED_SCREEN_RATIO
	var ratio := near_px / viewport_height
	_expect(
		absf(ratio - EXPECTED_SCREEN_RATIO) < SCREEN_RATIO_TOLERANCE,
		"准星屏幕占比应为 %.3f（%.1fpx），实测 %.3f（%.1fpx）" % [
			EXPECTED_SCREEN_RATIO, expected_px, ratio, near_px
		]
	)


## 把准星摆到 `pos`，返回它在屏幕上占的像素边长。
func _cursor_screen_px(player: Player3D, camera: Camera3D, pos: Vector3) -> float:
	player.call("_place_aim_cursor", pos)
	var cursor := player.get_node("AimCursor") as Node3D
	var half := cursor.scale.x * 0.5
	var right := cursor.global_transform.basis.x.normalized() * half
	var p0 := camera.unproject_position(cursor.global_position - right)
	var p1 := camera.unproject_position(cursor.global_position + right)
	return p0.distance_to(p1)


## D. 敌方子弹 billboard（通用弹体路由 —— 绝大多数敌人走这条）。
func _check_enemy_bullet_billboard(player: Player3D, stage: Node3D) -> void:
	var projectile := Projectile3D.new()
	stage.add_child(projectile)
	projectile.activate({
		"direction": Vector3(0, 0, -1), "speed": 12.0, "damage": 5, "hostile": true,
		"target_group": "player_3d", "projectile_collision_mask": 1,
		"visual_scale": 2.0, "shooter": player,
	}, Vector3(2.0, 0.75, -3.0))
	# 朝向在 `_process` 里逐帧校 —— 必须等一帧，否则读到的是「还没摆正」的默认基。
	await get_tree().process_frame
	_check_billboard_snapshot(
		projectile.get_orientation_snapshot(), "敌方子弹（通用弹体）", 2.0
	)
	projectile.queue_free()


## 两条路由都要过同一套判据：关卡点名 `visual_id` 时走八弹种 `VfxBulletBody3D`。
func _check_bullet_routes(player: Player3D, stage: Node3D) -> void:
	for visual_id in ["mod_bullet_piercing", "mod_bullet_electric"]:
		var projectile := Projectile3D.new()
		stage.add_child(projectile)
		projectile.activate({
			"direction": Vector3(0, 0, -1), "speed": 12.0, "damage": 5, "hostile": true,
			"target_group": "player_3d", "projectile_collision_mask": 1,
			"visual_id": visual_id, "shooter": player,
		}, Vector3(-2.0, 0.75, -3.0))
		await get_tree().process_frame
		await get_tree().process_frame
		_check_billboard_snapshot(
			projectile.get_orientation_snapshot(), "敌方子弹（%s）" % visual_id, 1.0
		)
		projectile.queue_free()

	# E. 玩家子弹必须保持 3D 弹体：billboard 只在 hostile 上开。
	await get_tree().process_frame
	var friendly := Projectile3D.new()
	stage.add_child(friendly)
	friendly.activate({
		"direction": Vector3(0, 0, -1), "speed": 15.0, "damage": 25, "hostile": false,
		"target_group": "enemy_3d", "projectile_collision_mask": 5, "shooter": player,
	}, Vector3(0.0, 0.75, -4.0))
	await get_tree().process_frame
	var snap := friendly.get_orientation_snapshot()
	_samples += 3
	_expect(not bool(snap.get("billboard", true)), "玩家子弹不得开启 billboard")
	_expect(not bool(snap.get("icon_visible", true)), "玩家子弹不得显示 billboard 图标")
	_expect(bool(snap.get("body_visible", false)), "玩家子弹的 3D 弹体必须可见")
	friendly.queue_free()


## 单发敌方子弹的 billboard 判据。
func _check_billboard_snapshot(snap: Dictionary, label: String, scale: float) -> void:
	_samples += 5
	_expect(bool(snap.get("billboard", false)), "%s：未开启 billboard" % label)
	_expect(bool(snap.get("icon_visible", false)), "%s：图标不可见" % label)
	_expect(
		not bool(snap.get("body_visible", true)),
		"%s：3D 弹体仍可见（会与图标叠着画）" % label
	)
	var align := float(snap.get("icon_camera_alignment", -1.0))
	_expect(
		align > 1.0 - ALIGN_TOLERANCE,
		"%s：图标未正对相机（法线与光轴余弦 %.4f）" % [label, align]
	)
	# 核心直径 = 判定球直径 = 2 × 0.12 × 视觉倍率。
	var expected_core := HIT_RADIUS_M * 2.0 * scale
	var core := float(snap.get("icon_core_diameter", -1.0))
	var radius := float(snap.get("collision_radius", -1.0))
	_samples += 2
	_expect(
		absf(core - expected_core) < 0.01,
		"%s：图标核心直径应为 %.3f（判定球 %.3f），实测 %.3f" % [
			label, expected_core, radius * 2.0, core
		]
	)
	_expect(
		absf(core - radius * 2.0) < 0.01,
		"%s：核心直径与判定球直径不一致（核心 %.3f / 判定 %.3f）—— 所见不等于所中" % [
			label, core, radius * 2.0
		]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	# 防假绿：A 5 条 + B 3 条 + C 3 条 + D 7 条 + 两条路由 14 条 + E 3 条 ≈ 35。
	if _samples < 28:
		_failures.append("防假绿哨兵：样本数只有 %d，期望 >= 28" % _samples)
	if not ResourceLoader.exists(CROSSHAIR_SHADER_PATH):
		_failures.append("准星 shader 不存在：%s" % CROSSHAIR_SHADER_PATH)
	if not ResourceLoader.exists(ENEMY_ICON_SHADER_PATH):
		_failures.append("敌方子弹 shader 不存在：%s" % ENEMY_ICON_SHADER_PATH)
	if _failures.is_empty():
		print("CROSSHAIR_BILLBOARD_OK: crosshair-icon / camera-facing / screen-ratio / enemy-bullet-icon / player-bullet-3d pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("CROSSHAIR_BILLBOARD_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)
