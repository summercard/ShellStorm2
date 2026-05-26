extends Node
class_name VisionSystem
## VisionSystem — 传统视野系统
## 负责：房间障碍几何构建 + 基于射线检测的可见性判断
## 
## 工作流程：
## 1. build_room_occlusion() — 由 RoomGameMode 在进入房间时调用，收集房间内所有墙体遮挡几何
## 2. is_point_visible(from, to) — 判断两点之间是否有遮挡
## 3. get_visible_enemies() — 返回当前可见敌人的列表（给 AI/UI 使用）

const DEFAULT_VIEW_RADIUS: float = 360.0
const DEFAULT_VIEW_ANGLE: float = PI * 100.0 / 180.0
const NEAR_VIEW_RADIUS: float = 72.0

## 视野范围（像素）
var view_radius: float = DEFAULT_VIEW_RADIUS

## 视野角度（弧度）与朝向
var view_angle: float = DEFAULT_VIEW_ANGLE
var view_direction: Vector2 = Vector2.RIGHT

## 所有墙体格的世界坐标列表（用于射线检测）
var _wall_world_rects: Array[Rect2] = []

## 房间边界 Rect2
var _room_bounds: Rect2 = Rect2(-400, -300, 800, 600)

var _debug_occluders: Array[Rect2] = []


## 由 RoomGameMode 在进入房间时调用，构建房间级别的遮挡几何
func build_room_occlusion(room_bounds: Rect2, wall_rects: Array[Rect2]) -> void:
	_room_bounds = room_bounds
	_wall_world_rects.clear()
	_debug_occluders.clear()
	
	for r in wall_rects:
		if r.size.x > 0 and r.size.y > 0:
			_wall_world_rects.append(r)
			_debug_occluders.append(r)
	
## 判断两点之间是否被遮挡（核心射线检测）
func is_point_visible(from: Vector2, to: Vector2) -> bool:
	# 先做快速排除：to 不在房间内一定不可见
	if not _room_bounds.has_point(to):
		return false
	
	var distance: float = from.distance_to(to)
	if distance > view_radius:
		return false

	if distance > NEAR_VIEW_RADIUS and view_angle >= 0.0:
		var target_direction: Vector2 = (to - from).normalized()
		var angle_to_target: float = absf(view_direction.angle_to(target_direction))
		if angle_to_target > view_angle * 0.5:
			return false

	if _point_in_any_rect(from, _wall_world_rects) or _point_in_any_rect(to, _wall_world_rects):
		return false

	if distance < 1.0:
		return true

	for rect in _wall_world_rects:
		if _ray_intersects_rect(from, to, rect):
			return false
	return true


func _ray_intersects_rect(ray_start: Vector2, ray_end: Vector2, rect: Rect2) -> bool:
	var dir: Vector2 = ray_end - ray_start
	if dir.length() < 0.001:
		return false
	
	var inv_dx: float = 1.0 / dir.x if absf(dir.x) > 0.0001 else 1e9
	var inv_dy: float = 1.0 / dir.y if absf(dir.y) > 0.0001 else 1e9
	
	var t1: float = (rect.position.x - ray_start.x) * inv_dx
	var t2: float = (rect.position.x + rect.size.x - ray_start.x) * inv_dx
	var t3: float = (rect.position.y - ray_start.y) * inv_dy
	var t4: float = (rect.position.y + rect.size.y - ray_start.y) * inv_dy
	
	var tmin_x: float = minf(t1, t2)
	var tmax_x: float = maxf(t1, t2)
	var tmin_y: float = minf(t3, t4)
	var tmax_y: float = maxf(t3, t4)
	
	var tmin: float = maxf(tmin_x, tmin_y)
	var tmax: float = minf(tmax_x, tmax_y)
	
	return tmax >= maxf(tmin, 0.0) and tmin <= 1.0


func _point_in_any_rect(p: Vector2, rects: Array[Rect2]) -> bool:
	for r in rects:
		if r.has_point(p):
			return true
	return false


## 获取玩家周围的可见区域（给迷雾系统使用）
## 返回一系列可见的圆盘区域
func get_visible_sectors(origin: Vector2, radius: float, angle_start: float, angle_count: int) -> Array[Dictionary]:
	var sectors: Array[Dictionary] = []
	var angle_step: float = TAU / float(angle_count)
	for i in range(angle_count):
		var a: float = angle_start + i * angle_step
		var is_clear: bool = true
		# 每隔一定角度发一条射线
		for dist in range(32, int(radius), 16):
			var dir: Vector2 = Vector2(cos(a), sin(a))
			var target: Vector2 = origin + dir * float(dist)
			if not is_point_visible(origin, target):
				is_clear = false
				sectors.append({"angle": a, "max_dist": float(dist), "clear": false})
				break
		if is_clear:
			sectors.append({"angle": a, "max_dist": radius, "clear": true})
	return sectors


## 更新视野范围
func set_view_radius(r: float) -> void:
	view_radius = maxf(50.0, r)


func set_view_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		view_direction = direction.normalized()


func set_view_angle(angle_radians: float) -> void:
	view_angle = clampf(angle_radians, 0.05, TAU)


## 重置（切换房间时）
func reset() -> void:
	_wall_world_rects.clear()
	_debug_occluders.clear()
