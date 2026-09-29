extends Node
## 世界准星 + 系统指针可见性的契约验收。
##
## 钉住三件事：
##   ① 玩法中世界里**有且只有一个**瞄准指示器 —— `Player3D.AimCursor`
##      （环 + 中心点 + 四向十字，6 件，默认可见）；
##   ② 它的世界位置 = **瞄准射线 ∩ 角色高度平面**，且每帧正对相机 ⇒
##      投影回屏幕与鼠标位置严格重合（这条是「准星和光标位置对不上」的回归判据）；
##   ③ 系统箭头在玩法期间隐藏、菜单 / 暂停 / 非玩法时显示（`UiCursorMode`）。
##
## 为什么独立成场景：原 `verify_tower_descent_flow` 里的准星断言在当前工程状态下
## **不可达** —— 该场景在 `floor_generation_mode == "arrival_gate_atomic_floor_bundle"`
## 时直接 `quit(0)` 早退（见其第 29~36 行），断言在早退之后。
##
## 跑法：godot --headless --path . --scene res://tests/verification/verify_cursor_crosshair_flow.tscn
## 必须走「跑场景」：--script / --check-only 模式下 autoload 名不进 GDScript 全局标识符表。

const HEIGHT := Player3D.AIM_CURSOR_HEIGHT_M


func _ready() -> void:
	var failures: Array[String] = []

	var scene := load("res://scenes/Player3D.tscn") as PackedScene
	if scene == null:
		_finish(["Player3D.tscn 加载失败"], failures)
		return
	var player := scene.instantiate() as Player3D
	add_child(player)
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	var cursor := player.get_node_or_null("AimCursor") as Node3D
	if cam == null or cursor == null:
		_finish(["AimCursor 或 Camera3D 缺失"], failures)
		return

	# --- 1. 几何：6 件且默认可见 -----------------------------------------------
	print("--- world crosshair geometry ---")
	print("child_count=%d visible=%s" % [cursor.get_child_count(), cursor.visible])
	_expect(
		cursor.get_child_count() == 6,
		"准星部件数不是 6（环 + 中心点 + 四向十字）",
		failures
	)
	for bar_name in ["CursorBarUp", "CursorBarDown", "CursorBarLeft", "CursorBarRight"]:
		var bar := cursor.get_node_or_null(bar_name) as MeshInstance3D
		_expect(bar != null and bar.mesh != null, "四向十字部件缺失：%s" % bar_name, failures)
	_expect(cursor.visible, "世界准星在场景里默认不可见 —— 玩法中玩家将没有瞄准指示器", failures)

	# --- 2. 位置与朝向：真跑一次瞄准更新 ---------------------------------------
	print("--- aim update ---")
	player.call("_update_aim_from_mouse")
	print(
		"cursor_y=%.4f expected_y=%.4f player_y=%.4f visible=%s"
		% [
			cursor.global_position.y,
			player.global_position.y + HEIGHT,
			player.global_position.y,
			cursor.visible,
		]
	)
	_expect(
		absf(cursor.global_position.y - (player.global_position.y + HEIGHT)) < 0.02,
		"3D 准星没有浮到角色高度（仍停在脚底平面上）",
		failures
	)
	var basis_dot := cursor.global_transform.basis.z.dot(cam.global_transform.basis.z)
	print("basis_z_dot=%.5f" % basis_dot)
	_expect(basis_dot > 0.999, "3D 准星没有正对相机（仍平躺，斜俯视下是压扁的椭圆）", failures)

	# --- 3. 屏幕对齐：合成多条射线，准星必须投影回它自己的采样点 ----------------
	# 射线上的点投影回屏幕必然等于该采样点；一旦实现改成「抬起瞄准点的 Y」，
	# 误差就是这个量级（对照见下）。这是「准星和光标位置对不上」的硬判据。
	print("--- screen alignment (synthetic rays) ---")
	var worst_err := 0.0
	for screen_point in [
		Vector2(640.0, 360.0),
		Vector2(160.0, 120.0),
		Vector2(1120.0, 640.0),
		Vector2(640.0, 40.0),
	]:
		var ray_origin := cam.project_ray_origin(screen_point)
		var ray_dir := cam.project_ray_normal(screen_point)
		var ground = Plane(Vector3.UP, player.global_position.y).intersects_ray(
			ray_origin, ray_dir
		)
		var aim_target: Vector3 = ground if ground is Vector3 else Vector3.ZERO
		var world: Vector3 = player.call(
			"_resolve_aim_cursor_position", ray_origin, ray_dir, aim_target
		)
		var back := cam.unproject_position(world)
		var err := back.distance_to(screen_point)
		worst_err = maxf(worst_err, err)
		print(
			"screen=%s world=(%.2f, %.3f, %.2f) unproject=%s err=%.4f"
			% [str(screen_point), world.x, world.y, world.z, str(back.round()), err]
		)
		_expect(
			err <= 1.0,
			"准星屏幕位置与鼠标射线偏差 %.2f px（应 ≤ 1 px）：%s" % [err, str(screen_point)],
			failures
		)
		_expect(
			absf(world.y - (player.global_position.y + HEIGHT)) < 0.001,
			"准星世界高度不是「角色原点 + %.2f」：%s" % [HEIGHT, str(world)],
			failures
		)
	print("worst_screen_err=%.4f px" % worst_err)

	# 对照证据：旧写法（取地面瞄准点的 XZ、Y 抬到角色高度）会偏多少 —— 防止改回去。
	var worst_old_err := 0.0
	for screen_point in [
		Vector2(640.0, 360.0),
		Vector2(160.0, 120.0),
		Vector2(1120.0, 640.0),
		Vector2(640.0, 40.0),
	]:
		var ray_origin := cam.project_ray_origin(screen_point)
		var ray_dir := cam.project_ray_normal(screen_point)
		var ground = Plane(Vector3.UP, player.global_position.y).intersects_ray(
			ray_origin, ray_dir
		)
		if not ground is Vector3:
			continue
		var g := ground as Vector3
		var old_world := Vector3(g.x, player.global_position.y + HEIGHT, g.z)
		worst_old_err = maxf(
			worst_old_err, cam.unproject_position(old_world).distance_to(screen_point)
		)
	print("worst_old_screen_err=%.2f px (旧写法，仅供对照)" % worst_old_err)

	# --- 4. 指针可见性门禁 ------------------------------------------------------
	print("--- cursor visibility gate ---")
	var stub := Node.new()
	add_child(stub)
	_expect_visible(failures, "idle", true)
	UiCursorMode.hold(stub)
	_expect_visible(failures, "gameplay", false)
	UiCursorMode.set_modal(stub, true)
	_expect_visible(failures, "modal", true)
	UiCursorMode.set_modal(stub, false)
	_expect_visible(failures, "modal closed", false)
	Global.acquire_pause("verify_cursor_crosshair_flow")
	_expect_visible(failures, "paused", true)
	Global.release_pause("verify_cursor_crosshair_flow")
	_expect_visible(failures, "unpaused", false)
	UiCursorMode.release(stub)
	_expect_visible(failures, "released", true)
	_expect(
		UiCursorMode.GAMEPLAY_MOUSE_MODE != UiCursorMode.NON_GAMEPLAY_MOUSE_MODE,
		"玩法 / 非玩法的指针模式相同 —— 隐藏语义丢失",
		failures
	)
	# 玩法期间必须是「隐藏 + 约束在窗口内」：只用 HIDDEN 会把指针推出窗口、瞄准丢输入。
	print("gameplay_mouse_mode=%d" % UiCursorMode.GAMEPLAY_MOUSE_MODE)
	_expect(
		UiCursorMode.GAMEPLAY_MOUSE_MODE == Input.MOUSE_MODE_CONFINED_HIDDEN,
		"玩法指针模式不是 CONFINED_HIDDEN（可能被推出窗口或没隐藏）",
		failures
	)
	stub.queue_free()

	_finish(["世界准星与指针可见性契约全部通过"], failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_visible(failures: Array[String], label: String, expected: bool) -> void:
	var actual: bool = UiCursorMode.wants_visible()
	print(
		"%s -> visible=%s (expect %s) %s"
		% [label, actual, expected, "OK" if actual == expected else "MISMATCH"]
	)
	if actual != expected:
		failures.append("指针可见性不符：%s = %s，应为 %s" % [label, actual, expected])


func _finish(summary: Array[String], failures: Array[String]) -> void:
	if failures.is_empty():
		print("CURSOR_CROSSHAIR_FLOW_OK: %s" % summary[0])
		get_tree().quit(0)
		return
	for message in failures:
		print("CURSOR_CROSSHAIR_FLOW_FAIL: %s" % message)
	get_tree().quit(1)
