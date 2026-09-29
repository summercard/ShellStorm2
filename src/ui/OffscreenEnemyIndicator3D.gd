class_name OffscreenEnemyIndicator3D
extends Control
## 屏幕外怪物指示箭头（UI-HUD）：画面外的怪在屏幕边缘留一支小红三角，尖端指向它的方向。
##
## 职责边界（与 `docs/v0.1/design/对话与战斗信息呈现设计.md` 的「屏幕外怪物指示箭头」一致）：
## * 只**投影**领域喂进来的世界坐标；不自己找怪、不判断谁算目标、不写任何玩法状态。
##   "谁算目标"由 `Dungeon3D._get_offscreen_enemy_positions()` 决定。
## * 屏幕内的目标不画箭头 —— 箭头是"找不到"的补偿，不是第二套雷达。
## * 不画背板：主人已多轮去掉 HUD 背板，箭头必须直接压在实景上，只靠描边与外发光保证可读。
##
## 方向口径（俯视角相机的关键取舍，不要改回去）：
## 相机是挂在玩家身上、向下俯约 52° 的透视相机。目标**落到相机身后**时
## `unproject_position` 会把点镜像到画面另一侧，直接拿它当方向会让"身后的怪"指到屏幕顶部
## —— 玩家会朝反方向跑。所以身后目标改用**相机局部轴**求方向：
## `local = camera.basis⁻¹ · (世界点 - 相机位置)`，屏幕方向 = `Vector2(local.x, -local.y)`。
## 俯视相机下地面目标的 `local.y` 恒为负 ⇒ 身后目标稳定落屏幕**下**缘，语义与肉眼一致。

## 30Hz 足够跟随转身；小地图是 15Hz，箭头比它灵敏是因为相机一转整屏方向就变。
const REDRAW_INTERVAL := 1.0 / 30.0
## 箭头尖端到屏幕边缘的内缩（canvas px，1280×720 基准）。
## 取值只要够放下整支箭头：让它整体待在屏幕最外那条窄带里，不跟已有 HUD 面板抢位置。
const EDGE_MARGIN_PX := 30.0
## 箭头几何：尖端在前、底边在后。18×22 的三角在 720p 下可辨认但不占视野。
const ARROW_LENGTH_PX := 18.0
const ARROW_HALF_WIDTH_PX := 11.0
## 屏幕平面上的合并半径：两支箭头靠得比这更近时只留离玩家最近的那支。
## 56 = 3 倍箭头长度，合并后仍看得出方向离散，不会糊成一坨。
const CLUSTER_RADIUS_PX := 56.0
## 箭头红色不走独有色值：与小地图的敌人红点同属"危险红"这一支。
const ARROW_COLOR := UIPalette.DANGER_RED
## 描边与外发光都用同一支箭头放大/描一圈 —— 浅色天花板与深色废土上都能读出来。
const ARROW_OUTLINE_COLOR := Color(0.03, 0.0, 0.0, 0.90)
const ARROW_GLOW_COLOR := Color(0.96, 0.08, 0.14, 0.20)
const ARROW_OUTLINE_WIDTH_PX := 1.6
const GLOW_LENGTH_SCALE := 1.75
const GLOW_WIDTH_SCALE := 1.90
## 呼吸：亮度在 0.70~1.00 之间按 1.9 次/秒摆动，静止画面里也能抓住眼睛。
const PULSE_MIN_ALPHA := 0.70
const PULSE_SPEED := 1.9

var _targets_world: Array[Vector3] = []
var _camera: Camera3D = null
var _markers: Array[Dictionary] = []
var _on_screen_count := 0
var _pulse_phase := 0.0
var _redraw_accumulator := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta * PULSE_SPEED, 1.0)
	_redraw_accumulator += delta
	if _redraw_accumulator < REDRAW_INTERVAL:
		return
	_redraw_accumulator = 0.0
	_refresh_markers()
	queue_redraw()


## 领域喂数口：一组世界坐标 + 当前活动相机。传空数组即"没有需要指示的目标"。
func set_targets(world_positions: Array[Vector3], camera: Camera3D) -> void:
	_targets_world.assign(world_positions)
	_camera = camera
	_refresh_markers()
	queue_redraw()


func clear_targets() -> void:
	_targets_world.clear()
	_markers.clear()
	_on_screen_count = 0
	queue_redraw()


func get_snapshot() -> Dictionary:
	var marker_details: Array[Dictionary] = []
	for marker in _markers:
		marker_details.append({
			"screen_point": marker.get("screen_point", Vector2.ZERO),
			"angle_rad": float(marker.get("angle_rad", 0.0)),
		})
	return {
		"target_count": _targets_world.size(),
		"marker_count": _markers.size(),
		"on_screen_count": _on_screen_count,
		"edge_margin_px": EDGE_MARGIN_PX,
		"cluster_radius_px": CLUSTER_RADIUS_PX,
		"arrow_color": ARROW_COLOR,
		"markers": marker_details,
	}


## 纯投影：世界坐标 → 屏幕边缘箭头。不碰节点、不碰玩法，可脱离场景单测。
## 返回 `{"markers": [{screen_point, angle_rad, world_position}], "on_screen_count": int}`。
static func project_markers(
	camera: Camera3D,
	world_positions: Array[Vector3],
	viewport_size: Vector2,
	edge_margin := EDGE_MARGIN_PX,
	cluster_radius := CLUSTER_RADIUS_PX
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var on_screen_count := 0
	if camera == null or not is_instance_valid(camera):
		return {"markers": candidates, "on_screen_count": 0}
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return {"markers": candidates, "on_screen_count": 0}
	var center := viewport_size * 0.5
	var safe_half := Vector2(
		maxf(1.0, viewport_size.x * 0.5 - edge_margin),
		maxf(1.0, viewport_size.y * 0.5 - edge_margin)
	)
	var camera_origin := camera.global_position
	var inverse_basis := camera.global_transform.basis.inverse()
	for world_position in world_positions:
		var behind := camera.is_position_behind(world_position)
		var direction := Vector2.ZERO
		if behind:
			var local := inverse_basis * (world_position - camera_origin)
			# 相机局部 +x → 屏幕右，局部 +y → 屏幕上；而屏幕 y 向下 ⇒ y 分量取反。
			direction = Vector2(local.x, -local.y)
		else:
			var projected := camera.unproject_position(world_position)
			if (
				absf(projected.x - center.x) <= safe_half.x
				and absf(projected.y - center.y) <= safe_half.y
			):
				on_screen_count += 1
				continue
			direction = projected - center
		if direction.length_squared() < 0.0001:
			# 目标正压在画面中轴上：屏内（还差得远）或方向退化，两种情况都不需要箭头。
			on_screen_count += 1
			continue
		var edge_scale := minf(
			safe_half.x / maxf(absf(direction.x), 0.0001),
			safe_half.y / maxf(absf(direction.y), 0.0001)
		)
		candidates.append({
			"world_position": world_position,
			"screen_point": center + direction * edge_scale,
			"angle_rad": direction.angle(),
			"distance_squared": world_position.distance_squared_to(camera_origin),
		})
	# 合并：近处优先，靠得近的只留一支，避免边缘糊成一片红。
	candidates.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return float(first["distance_squared"]) < float(second["distance_squared"])
	)
	var markers: Array[Dictionary] = []
	for candidate in candidates:
		var point: Vector2 = candidate["screen_point"]
		var merged := false
		for kept in markers:
			var kept_point: Vector2 = kept["screen_point"]
			if point.distance_to(kept_point) < cluster_radius:
				merged = true
				break
		if merged:
			continue
		markers.append({
			"world_position": candidate["world_position"],
			"screen_point": point,
			"angle_rad": float(candidate["angle_rad"]),
		})
	return {"markers": markers, "on_screen_count": on_screen_count}


func _refresh_markers() -> void:
	var camera := _resolve_camera()
	var result := project_markers(camera, _targets_world, get_viewport_rect().size)
	_markers.assign(result.get("markers", []))
	_on_screen_count = int(result.get("on_screen_count", 0))


## 优先用领域传进来的相机（测试可喂确定值）；没有就用视口的活动相机 ——
## 开场与剧情会临时接管相机，运行时问视口才不会指错方向。
func _resolve_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree():
		return _camera
	return get_viewport().get_camera_3d()


func _draw() -> void:
	if _markers.is_empty():
		return
	var alpha := _pulse_alpha()
	for marker in _markers:
		var point: Vector2 = marker.get("screen_point", Vector2.ZERO)
		_draw_arrow(point, float(marker.get("angle_rad", 0.0)), alpha)


func _draw_arrow(tip: Vector2, angle_rad: float, alpha: float) -> void:
	var forward := Vector2.RIGHT.rotated(angle_rad)
	var side := Vector2.DOWN.rotated(angle_rad)
	var base := tip - forward * ARROW_LENGTH_PX
	var arrow := PackedVector2Array([
		tip,
		base + side * ARROW_HALF_WIDTH_PX,
		base - side * ARROW_HALF_WIDTH_PX,
	])
	# 外发光是同一支三角放大一圈，不是背板 —— 箭头底下必须是实景。
	var glow_base := tip - forward * (ARROW_LENGTH_PX * GLOW_LENGTH_SCALE)
	var glow := PackedVector2Array([
		tip,
		glow_base + side * (ARROW_HALF_WIDTH_PX * GLOW_WIDTH_SCALE),
		glow_base - side * (ARROW_HALF_WIDTH_PX * GLOW_WIDTH_SCALE),
	])
	draw_colored_polygon(glow, Color(ARROW_GLOW_COLOR, ARROW_GLOW_COLOR.a * alpha))
	draw_colored_polygon(arrow, Color(ARROW_COLOR, alpha))
	draw_polyline(
		PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]),
		Color(ARROW_OUTLINE_COLOR, ARROW_OUTLINE_COLOR.a * alpha),
		ARROW_OUTLINE_WIDTH_PX,
		true
	)


func _pulse_alpha() -> float:
	return lerpf(PULSE_MIN_ALPHA, 1.0, 0.5 + 0.5 * sin(_pulse_phase * TAU))
