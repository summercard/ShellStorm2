extends Node
## 屏幕外怪物指示箭头 · 逻辑验收（注册 `core`）。
##
## 覆盖两段：
## A. 纯投影 `OffscreenEnemyIndicator3D.project_markers()`：屏内不画、四个方向各自贴边、
##    **身后目标落到下缘**（本功能最容易写错的一条）、同向合并。
## B. `Dungeon3D._get_offscreen_enemy_positions()` 的四条排除规则：活怪 / 已唤醒 / 同层 / 射程，
##    用真实敌人对象现场改状态验证，不用假数据。

const INDICATOR_SCRIPT = preload("res://src/ui/OffscreenEnemyIndicator3D.gd")
const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const EDGE_MARGIN := 30.0
const EDGE_EPSILON := 0.5


func _ready() -> void:
	var failures: Array[String] = []
	_verify_reference_viewport(failures)
	_verify_projection(failures)
	await _verify_runtime_provider(failures)
	_finish(failures)


func _verify_reference_viewport(failures: Array[String]) -> void:
	var observed := get_viewport().get_visible_rect().size
	_expect(
		observed.is_equal_approx(VIEWPORT_SIZE),
		"视口尺寸不是基准 1280×720（实测 %s）；下面的贴边坐标断言不再成立" % observed,
		failures
	)


# --- A. 纯投影 -------------------------------------------------------------


func _verify_projection(failures: Array[String]) -> void:
	var camera := Camera3D.new()
	camera.fov = 43.0
	camera.near = 0.1
	camera.far = 1000.0
	# 刻意不设 current：本用例只借它的投影矩阵，不能抢掉战局自己的相机。
	add_child(camera)
	camera.global_position = Vector3.ZERO
	camera.global_rotation = Vector3.ZERO

	var center := VIEWPORT_SIZE * 0.5
	var safe_half := Vector2(
		VIEWPORT_SIZE.x * 0.5 - EDGE_MARGIN,
		VIEWPORT_SIZE.y * 0.5 - EDGE_MARGIN
	)

	# 1) 屏内目标：一支箭头都不该有。
	var on_screen := _project(camera, [Vector3(0.0, 0.0, -10.0)])
	_expect(
		int(on_screen.get("on_screen_count", 0)) == 1
		and (on_screen.get("markers", []) as Array).is_empty(),
		"屏幕内的目标仍然产生了箭头",
		failures
	)

	# 2) 正前偏右 / 正前偏左 / 正前偏上：各自贴到对应边缘，方向落在对应象限。
	var right: Variant = _first_marker(_project(camera, [Vector3(60.0, 0.0, -10.0)]))
	_expect(right != null, "右侧画面外的目标没有产生箭头", failures)
	if right != null:
		_expect(
			absf(float(right["screen_point"].x) - (center.x + safe_half.x)) <= EDGE_EPSILON
			and absf(float(right["screen_point"].y) - center.y) <= EDGE_EPSILON,
			"右侧目标没有贴在右边缘：%s" % right["screen_point"],
			failures
		)
		_expect(absf(float(right["angle_rad"])) <= 0.05, "右侧目标的箭头方向不是朝右", failures)

	var left: Variant = _first_marker(_project(camera, [Vector3(-60.0, 0.0, -10.0)]))
	_expect(left != null, "左侧画面外的目标没有产生箭头", failures)
	if left != null:
		_expect(
			absf(float(left["screen_point"].x) - (center.x - safe_half.x)) <= EDGE_EPSILON,
			"左侧目标没有贴在左边缘：%s" % left["screen_point"],
			failures
		)
		_expect(absf(absf(float(left["angle_rad"])) - PI) <= 0.05, "左侧目标的箭头方向不是朝左", failures)

	var above: Variant = _first_marker(_project(camera, [Vector3(0.0, 30.0, -10.0)]))
	_expect(above != null, "上方画面外的目标没有产生箭头", failures)
	if above != null:
		_expect(
			absf(float(above["screen_point"].y) - (center.y - safe_half.y)) <= EDGE_EPSILON,
			"上方目标没有贴在上边缘：%s" % above["screen_point"],
			failures
		)

	# 3) 身后目标：必须落到**下**缘。用 unproject 的镜像值会指到上缘（玩家会往前跑），
	#    所以这条断言就是"不要改回镜像写法"的守门。
	var behind: Variant = _first_marker(_project(camera, [Vector3(0.0, -10.0, 40.0)]))
	_expect(behind != null, "身后的目标没有产生箭头", failures)
	if behind != null:
		_expect(
			absf(float(behind["screen_point"].y) - (center.y + safe_half.y)) <= EDGE_EPSILON,
			"身后的目标没有落在屏幕下缘：%s（相机身后目标的方向口径被改回镜像了？）"
			% behind["screen_point"],
			failures
		)
		_expect(
			float(behind["angle_rad"]) > 0.0,
			"身后目标的箭头方向不是朝下：%s" % behind["angle_rad"],
			failures
		)

	# 4) 同向合并：右边缘两支挤在一起只留一支，左边缘那支不受影响。
	var clustered := _project(
		camera,
		[Vector3(60.0, 0.0, -10.0), Vector3(70.0, 0.0, -10.0), Vector3(-60.0, 0.0, -10.0)]
	)
	var markers: Array = clustered.get("markers", [])
	_expect(markers.size() == 2, "同向的两支箭头没有合并：markers=%d" % markers.size(), failures)
	_expect(
		int(clustered.get("on_screen_count", 0)) == 0,
		"屏外目标被算成了屏内",
		failures
	)

	# 5) 合并半径之外的相邻目标各留一支。
	var spread := _project(camera, [Vector3(60.0, 0.0, -10.0), Vector3(60.0, 0.0, -60.0)])
	_expect(
		(spread.get("markers", []) as Array).size() == 2,
		"离散方向上的两支箭头被误合并",
		failures
	)

	camera.queue_free()


# --- B. 战局取数口 ---------------------------------------------------------


func _verify_runtime_provider(failures: Array[String]) -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 12:
		await get_tree().process_frame

	var indicator := dungeon.get_node_or_null("HUD/OffscreenEnemyIndicator3D") as OffscreenEnemyIndicator3D
	_expect(indicator != null, "HUD 下没有装屏幕外指示箭头层", failures)
	if indicator != null:
		_expect(
			indicator.z_index == 110,
			"箭头层层级不是 110（会与小地图/暗角的遮挡关系错位）：%d" % indicator.z_index,
			failures
		)

	var enemies := await _enter_first_room_with_live_enemies(dungeon)
	_expect(enemies.size() >= 1, "没有找到任何「已进入房间的活怪」，取数口无法验证", failures)
	if enemies.is_empty():
		dungeon.queue_free()
		await get_tree().process_frame
		return

	var positions: Array = dungeon.call("_get_offscreen_enemy_positions")
	_expect(
		positions.size() == enemies.size(),
		"射程/同层内的已唤醒活怪没有全部进指示：取数 %d / 实际 %d"
		% [positions.size(), enemies.size()],
		failures
	)
	# 箭头指向的高度是躯干中线，不是脚底。
	var expected_offset := Vector3.UP * dungeon.OFFSCREEN_INDICATOR_TARGET_HEIGHT_M
	var matched := 0
	for position_value in positions:
		var position: Vector3 = position_value
		for enemy in enemies:
			if position.distance_to(enemy.global_position + expected_offset) <= 0.05:
				matched += 1
				break
	_expect(
		matched == positions.size(),
		"取数口给出的世界点不是「敌人躯干中线」：匹配 %d / %d" % [matched, positions.size()],
		failures
	)
	_expect(
		absf(dungeon.OFFSCREEN_INDICATOR_RANGE_M - 50.0) <= 0.001,
		"取数半径被改掉了（设计口径是最大战斗房半对角线向上取整 = 50 m）",
		failures
	)

	# 排除规则 1：休眠怪不给箭头（门后没进的房间 / 未触发的怪）。
	var dormant_probe: Enemy3D = enemies[0]
	dormant_probe.set_runtime_active(false)
	_expect(
		(dungeon.call("_get_offscreen_enemy_positions") as Array).size() == enemies.size() - 1,
		"休眠的怪仍然拿到了箭头（等于隔墙报出未进入房间的怪）",
		failures
	)
	dormant_probe.set_runtime_active(true)
	_expect(
		(dungeon.call("_get_offscreen_enemy_positions") as Array).size() == enemies.size(),
		"怪被唤醒后没有重新拿到箭头",
		failures
	)

	# 排除规则 2：已死（血量归零）的怪不给箭头。归零与恢复都走真实字段，
	# 只在这一帧判定取数，不触发死亡回调。
	var dead_probe: Enemy3D = enemies[enemies.size() - 1]
	var dead_hp: int = dead_probe.current_hp
	dead_probe.current_hp = 0
	_expect(
		(dungeon.call("_get_offscreen_enemy_positions") as Array).size() == enemies.size() - 1,
		"血量归零的怪仍然拿到了箭头",
		failures
	)
	dead_probe.current_hp = dead_hp

	# 排除规则 3：潜伏中的伏击怪不给箭头（它醒着，但正趴在地下）。
	var concealed_probe: Enemy3D = enemies[0]
	var original_kind: String = concealed_probe.enemy_kind
	concealed_probe.enemy_kind = "ambusher"
	_expect(
		concealed_probe.is_concealed_in_world(),
		"伏击怪在未触发时没有被判定为「藏在世界里」",
		failures
	)
	_expect(
		(dungeon.call("_get_offscreen_enemy_positions") as Array).size() == enemies.size() - 1,
		"潜伏中的伏击怪仍然拿到了箭头（伏击点被直接报出来了）",
		failures
	)
	concealed_probe.enemy_kind = original_kind
	_expect(
		not concealed_probe.is_concealed_in_world(),
		"非伏击怪被误判为「藏在世界里」",
		failures
	)

	# 取数口 → 控件：喂真实取数结果，箭头全部贴在屏幕最外那条窄带上，且屏内目标不产生箭头。
	if indicator != null:
		indicator.set_targets(dungeon.call("_get_offscreen_enemy_positions"), get_viewport().get_camera_3d())
		var snapshot := indicator.get_snapshot()
		_expect(
			int(snapshot.get("target_count", 0)) == enemies.size(),
			"控件没有收到完整的目标列表：%d" % int(snapshot.get("target_count", 0)),
			failures
		)
		var red: Color = snapshot.get("arrow_color", Color.BLACK)
		_expect(
			red.r > 0.9 and red.g < 0.2 and red.b < 0.2 and red.a >= 1.0,
			"箭头颜色不是不透明危险红：%s" % red,
			failures
		)
		var viewport_size := get_viewport().get_visible_rect().size
		var band_center := viewport_size * 0.5
		var band_margin := float(snapshot.get("edge_margin_px", EDGE_MARGIN))
		var band_half := Vector2(
			viewport_size.x * 0.5 - band_margin,
			viewport_size.y * 0.5 - band_margin
		)
		var off_band := 0
		for marker_value in snapshot.get("markers", []):
			var marker: Dictionary = marker_value
			var point: Vector2 = marker.get("screen_point", Vector2.ZERO)
			var on_band := (
				absf(absf(point.x - band_center.x) - band_half.x) <= EDGE_EPSILON
				or absf(absf(point.y - band_center.y) - band_half.y) <= EDGE_EPSILON
			)
			if not on_band:
				off_band += 1
		_expect(
			off_band == 0,
			"有 %d 支箭头没有贴在屏幕边缘窄带上" % off_band,
			failures
		)
		# 每帧喂数：暂停战局的喂数后清空目标，控件必须自己收敛到零箭头。
		indicator.set_targets([], get_viewport().get_camera_3d())
		_expect(
			int(indicator.get_snapshot().get("marker_count", -1)) == 0,
			"目标清空后箭头没有清掉",
			failures
		)

	dungeon.queue_free()
	await get_tree().process_frame


## 逐房进入，直到找到一间有「已唤醒活怪」的房间。避开硬编码房间 id ——
## 房间 id 由版图生成器决定，写死会在改版图时静默变成空跑。
func _enter_first_room_with_live_enemies(dungeon: Dungeon3D) -> Array:
	var room_by_id: Dictionary = dungeon.get("_room_by_id")
	for room_id_value in room_by_id.keys():
		var room_id := str(room_id_value)
		var room := room_by_id[room_id] as DungeonRoom3D
		if room == null or not GameDesignConfig.ROOM_TYPES_WITH_HOSTILES.has(room.room_type):
			continue
		if room.enemy_spawn_points.is_empty():
			continue
		dungeon.force_enter_room_for_test(room_id)
		for _frame in 30:
			await get_tree().process_frame
			var live := _collect_live_enemies(dungeon, room_id)
			if not live.is_empty():
				return live
	return []


func _collect_live_enemies(dungeon: Dungeon3D, room_id: String) -> Array:
	var result: Array = []
	var by_room: Dictionary = dungeon.get("_enemy_nodes_by_room")
	for value in by_room.get(room_id, []):
		if value == null or not is_instance_valid(value):
			continue
		var enemy := value as Enemy3D
		if enemy == null or enemy.is_queued_for_deletion() or enemy.current_hp <= 0:
			continue
		if not enemy.is_runtime_ai_active() or enemy.is_concealed_in_world():
			continue
		result.append(enemy)
	return result


func _project(camera: Camera3D, positions: Array) -> Dictionary:
	var typed: Array[Vector3] = []
	for value in positions:
		typed.append(value)
	return INDICATOR_SCRIPT.project_markers(camera, typed, VIEWPORT_SIZE)


func _first_marker(result: Dictionary) -> Variant:
	var markers: Array = result.get("markers", [])
	if markers.is_empty():
		return null
	return markers[0]


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("OFFSCREEN_ENEMY_INDICATOR_OK: off-screen enemies get edge arrows, on-screen and dormant ones stay clean")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
