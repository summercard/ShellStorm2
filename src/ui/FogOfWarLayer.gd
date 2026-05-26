extends CanvasLayer
class_name FogOfWarLayer

# FogOfWarLayer — 基于 ShaderMaterial 的传统 2D 视野/迷雾系统
# 覆盖全屏，每帧根据玩家位置和房间遮挡几何渲染可见区域
# 架构：GDScript 维护可见性数据（Image），Shader 负责渲染

## 迷雾每像素代表的世界单位大小（越小精度越高，性能也更低）
const CELL_PIXELS: int = 32  # 每 32 像素一个采样点

## 迷雾更新频率（每帧更新太贵，改用每 3 帧更新一次）
var _update_interval: int = 3
var _frame_counter: int = 0

## 迷雾 Image（每像素 = CELL_PIXELS 世界单位）
var _fog_image: Image
var _fog_texture: ImageTexture

## FogColorRect
var _fog_rect: ColorRect

## 视野半径（像素为单位，迷雾只在这个范围内有效）
var _view_radius_pixels: int = 320 / CELL_PIXELS  # = 10 cells

## 上次更新的玩家位置（位置变化不大时不更新）
var _last_player_pos: Vector2 = Vector2(-9999, -9999)
var _position_threshold: float = 16.0  # 移动超过16像素才更新

## 房间参考（用于读取墙体位置）
var _room_node: Node2D = null
var _vision_system: Node = null  # VisionSystem reference
var _player: Node2D = null

## 当前房间的墙体 Rect2 列表（世界坐标）
var _wall_rects: Array[Rect2] = []


func _ready() -> void:
	_setup_fog_layer()
	_update_fog_image_full()
	_update_fog_texture()


func _setup_fog_layer() -> void:
	# 创建全屏 ColorRect，使用 ShaderMaterial
	_fog_rect = ColorRect.new()
	_fog_rect.name = "FogOfWar"
	_fog_rect.anchors_preset = Control.PRESET_FULL_RECT
	_fog_rect.size = get_viewport().get_visible_rect().size
	_fog_rect.z_index = 200  # 确保在最上层
	
	var shader := Shader.new()
	shader.code = _get_fog_shader_code()
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	
	# 创建迷雾纹理（1024×768 对应 CELL_PIXELS=32 的网格）
	var tex := ImageTexture.create_from_image(_create_fog_image(Vector2i(1024, 768)))
	mat.set_shader_parameter("fog_texture", tex)
	mat.set_shader_parameter("fog_color", Color(0.02, 0.01, 0.04, 0.95))  # 深紫色黑雾
	mat.set_shader_parameter("ambient_color", Color(0.05, 0.04, 0.08, 0.0))  # 环境光
	
	_fog_rect.material = mat
	add_child(_fog_rect)


func _create_fog_image(size: Vector2i) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0, 1))  # 全黑（迷雾）
	return img


func _get_fog_shader_code() -> String:
	return "
shader_type canvas_item;

uniform sampler2D fog_texture: filter_nearest_mipmap;
uniform vec4 fog_color: source_color;
uniform vec4 ambient_color: source_color;

void fragment() {
	vec4 fog_sample = texture(fog_texture, UV);
	float fog_alpha = fog_sample.r;  // R通道 = 迷雾透明度 (0=完全黑, 255=完全透明)
	
	// 迷雾区域显示浓雾，非迷雾区域根据 ambient_color 轻微显示地形
	COLOR = mix(fog_color, ambient_color, 1.0 - fog_alpha);
}
"


## 初始化迷雾（房间切换时调用）
func setup(room_node: Node2D, vision_system: Node, player: Node2D) -> void:
	_room_node = room_node
	_vision_system = vision_system
	_player = player
	_last_player_pos = Vector2(-9999, -9999)
	
	# 读取房间大小并重建迷雾 Image
	var fog_size := Vector2i(1024, 768)
	var fog_img := _create_fog_image(fog_size)
	_fog_image = fog_img
	
	if _fog_rect != null and _fog_rect.material is ShaderMaterial:
		var mat: ShaderMaterial = _fog_rect.material as ShaderMaterial
		var tex := ImageTexture.create_from_image(_fog_image)
		mat.set_shader_parameter("fog_texture", tex)


func _process(delta: float) -> void:
	_frame_counter += 1
	if _frame_counter % _update_interval != 0:
		return
	if _player == null or not is_instance_valid(_player):
		return
	
	var player_pos: Vector2 = _player.global_position
	
	# 位置变化不大时跳过更新
	if player_pos.distance_to(_last_player_pos) < _position_threshold:
		return
	
	_last_player_pos = player_pos
	_update_fog_image()
	_update_fog_texture()


## 更新迷雾图像（在玩家位置或房间状态变化时调用）
func _update_fog_image() -> void:
	if _fog_image == null or _player == null:
		return
	
	var player_pos: Vector2 = _player.global_position
	var fog_size: Vector2i = _fog_image.get_size()
	
	# 对每个像素判断是否可见
	for py in range(fog_size.y):
		for px in range(fog_size.x):
			# 世界坐标
			var wx: float = (float(px) / float(fog_size.x) - 0.5) * 1024.0
			var wy: float = (float(py) / float(fog_size.y) - 0.5) * 768.0
			var world_pt := Vector2(wx, wy)
			
			# 距离判断：超过视野半径则完全黑
			var dist_to_player: float = world_pt.distance_to(player_pos)
			var view_r: float = 320.0  # 视野半径
			if dist_to_player > view_r:
				_fog_image.set_pixel(px, py, Color(0, 0, 0, 1))  # 完全黑
				continue
			
			# 射线检测：player_pos 到 world_pt 是否有遮挡
			var visible: bool = _ray_visible(player_pos, world_pt)
			if visible:
				_fog_image.set_pixel(px, py, Color(1, 1, 1, 1))  # 完全透明（可见）
			else:
				_fog_image.set_pixel(px, py, Color(0, 0, 0, 1))  # 完全黑


## 完整更新（进入房间时调用一次）
func _update_fog_image_full() -> void:
	if _fog_image == null:
		var fog_size := Vector2i(1024, 768)
		_fog_image = _create_fog_image(fog_size)
	_update_fog_image()


## 简单的射线检测（两点之间是否有 Rect2 阻挡）
func _ray_visible(from: Vector2, to: Vector2) -> bool:
	# 读取 wall_rects（从 VisionSystem 或直接存储）
	if _wall_rects.is_empty():
		# 读取 RoomTileMapInitializer 的墙体数据
		_load_wall_rects()
	
	for r in _wall_rects:
		if _ray_intersects_rect(from, to, r):
			return false
	return true


func _load_wall_rects() -> void:
	_wall_rects.clear()
	if _room_node == null:
		return
	
	# 尝试从 VisionOccluders 获取
	var occluders_node: Node2D = _room_node.find_child("VisionOccluders", true, false) as Node2D
	if occluders_node != null:
		for child in occluders_node.get_children():
			if child is LightOccluder2D:
				var occl: LightOccluder2D = child as LightOccluder2D
				var polygon: OccluderPolygon2D = occl.occluder as OccluderPolygon2D
				if polygon != null and polygon.polygon.size() >= 3:
					# 从多边形计算 AABB
					var min_x: float = INF
					var min_y: float = INF
					var max_x: float = -INF
					var max_y: float = -INF
					for pt in polygon.polygon:
						min_x = minf(min_x, pt.x)
						min_y = minf(min_y, pt.y)
						max_x = maxf(max_x, pt.x)
						max_y = maxf(max_y, pt.y)
					var world_rect: Rect2 = Rect2(
						occl.position.x + min_x,
						occl.position.y + min_y,
						max_x - min_x, max_y - min_y
					)
					_wall_rects.append(world_rect)


## 射线与 AABB 求交
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
	
	return tmax >= maxf(tmin, 0.0)


## 更新迷雾纹理（上传到 GPU）
func _update_fog_texture() -> void:
	if _fog_image == null:
		return
	if _fog_rect == null or not (_fog_rect.material is ShaderMaterial):
		return
	
	var mat: ShaderMaterial = _fog_rect.material as ShaderMaterial
	var tex: ImageTexture = ImageTexture.create_from_image(_fog_image)
	mat.set_shader_parameter("fog_texture", tex)


## 外部调用：设置墙体检疫（由 RoomGameMode 提供）
func set_wall_rects(rects: Array[Rect2]) -> void:
	_wall_rects = rects
	_update_fog_image()
	_update_fog_texture()


## 切换房间时重建迷雾
func rebuild_for_room(room_node: Node2D, player: Node2D) -> void:
	_room_node = room_node
	_player = player
	_wall_rects.clear()
	_load_wall_rects()
	_last_player_pos = Vector2(-9999, -9999)
	_frame_counter = 0
	
	# 重建迷雾大小（基于房间尺寸）
	var fog_w: int = 1024 / CELL_PIXELS  # = 32
	var fog_h: int = 768 / CELL_PIXELS   # = 24
	var fog_size := Vector2i(fog_w, fog_h)
	_fog_image = _create_fog_image(fog_size)
	_fog_rect.size = Vector2(1024, 768)  # 固定房间尺寸
	
	_update_fog_image()
	_update_fog_texture()
