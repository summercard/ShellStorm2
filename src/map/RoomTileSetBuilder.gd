class_name RoomTileSetBuilder
extends RefCounted
## 运行时构建 Room TileSet — 生成纯色占位 Tile，不依赖外部图片资源
## 使用方式：在 Room 场景的 _ready() 中调用 build_tile_set(tilemap_layer)

## TileSet 配置（从 GridConstants 读取格子尺寸，房间格数由外部传入）
## CELL_SIZE 和 TILESET_SIZE 保持本地，因为 TileSet 是 4×4 图集，不是房间格
const CELL_SIZE := GridConstants.CELL_SIZE  # 64px，从 GridConstants 引用
const TILESET_SIZE := Vector2i(4, 4)  # 4×4 图集网格（共16个tile slot）

## 各房间类型的视觉配置
const ROOM_THEMES := {
	RoomData.RoomType.COMBAT: {
		"floor": Color(0.25, 0.25, 0.27),
		"floor_alt": Color(0.22, 0.22, 0.24),
		"wall": Color(0.18, 0.18, 0.20),
		"wall_top": Color(0.22, 0.22, 0.24),
		"accent": Color(0.35, 0.10, 0.08),
		"accent_glow": Color(0.0, 0.0, 0.0),
	},
	RoomData.RoomType.ELITE: {
		"floor": Color(0.20, 0.22, 0.28),
		"floor_alt": Color(0.18, 0.20, 0.25),
		"wall": Color(0.15, 0.16, 0.20),
		"wall_top": Color(0.20, 0.22, 0.26),
		"accent": Color(0.40, 0.15, 0.05),
		"accent_glow": Color(0.50, 0.10, 0.05),
	},
	RoomData.RoomType.SCAVENGE: {
		"floor": Color(0.30, 0.28, 0.25),
		"floor_alt": Color(0.28, 0.26, 0.22),
		"wall": Color(0.25, 0.22, 0.20),
		"wall_top": Color(0.32, 0.28, 0.24),
		"accent": Color(0.35, 0.30, 0.20),
		"accent_glow": Color(0.0, 0.0, 0.0),
	},
	RoomData.RoomType.MERCHANT: {
		"floor": Color(0.32, 0.28, 0.18),
		"floor_alt": Color(0.30, 0.26, 0.15),
		"wall": Color(0.28, 0.24, 0.15),
		"wall_top": Color(0.38, 0.32, 0.18),
		"accent": Color(0.90, 0.75, 0.25),
		"accent_glow": Color(1.0, 0.85, 0.30),
	},
	RoomData.RoomType.UPGRADE: {
		"floor": Color(0.22, 0.25, 0.30),
		"floor_alt": Color(0.20, 0.23, 0.28),
		"wall": Color(0.18, 0.20, 0.25),
		"wall_top": Color(0.25, 0.30, 0.40),
		"accent": Color(0.20, 0.40, 0.60),
		"accent_glow": Color(0.25, 0.50, 0.70),
	},
	RoomData.RoomType.EVENT: {
		"floor": Color(0.18, 0.14, 0.25),
		"floor_alt": Color(0.16, 0.12, 0.22),
		"wall": Color(0.14, 0.10, 0.20),
		"wall_top": Color(0.22, 0.15, 0.30),
		"accent": Color(0.55, 0.20, 0.70),
		"accent_glow": Color(0.65, 0.25, 0.80),
	},
	RoomData.RoomType.BOSS: {
		"floor": Color(0.10, 0.08, 0.10),
		"floor_alt": Color(0.08, 0.06, 0.08),
		"wall": Color(0.12, 0.05, 0.05),
		"wall_top": Color(0.18, 0.08, 0.08),
		"accent": Color(0.60, 0.05, 0.05),
		"accent_glow": Color(0.80, 0.10, 0.05),
	},
	RoomData.RoomType.TRAP: {
		"floor": Color(0.22, 0.12, 0.10),
		"floor_alt": Color(0.20, 0.10, 0.08),
		"wall": Color(0.18, 0.08, 0.07),
		"wall_top": Color(0.25, 0.10, 0.08),
		"accent": Color(0.50, 0.08, 0.05),
		"accent_glow": Color(0.0, 0.0, 0.0),
	},
	RoomData.RoomType.STORAGE: {
		"floor": Color(0.28, 0.20, 0.14),
		"floor_alt": Color(0.25, 0.18, 0.12),
		"wall": Color(0.22, 0.15, 0.10),
		"wall_top": Color(0.30, 0.22, 0.15),
		"accent": Color(0.35, 0.25, 0.15),
		"accent_glow": Color(0.0, 0.0, 0.0),
	},
	}

## tile_id → 配置索引（对应 TileSetAtlasSource 的坐标）
enum TileId {
	FLOOR = 0,     # (0,0) 地板主格
	FLOOR_ALT = 1, # (1,0) 地板变化格
	WALL = 2,      # (2,0) 墙体格
	WALL_TOP = 3,  # (3,0) 墙顶格
	ACCENT = 4,    # (0,1) 装饰格（血迹等）
	ACCENT_GLOW = 5,  # (1,1) 光效装饰
	PROP_DOOR = 6, # (2,1) 门框标记
	PROP_MARKER = 7,  # (3,1) 特殊标记
}


## 为 TileMapLayer 构建并应用 TileSet
func build_tile_set(tilemap: TileMapLayer, room_type: RoomData.RoomType) -> void:
	var theme: Dictionary = ROOM_THEMES.get(room_type, ROOM_THEMES[RoomData.RoomType.COMBAT])
	
	# 创建 TileSet
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)
	
	# 创建 AtlasSource（4×4 网格 = 16 slots）
	var atlas_source := TileSetAtlasSource.new()
	
	# 生成16个占位tile
	var colors := [
		theme["floor"],        # (0,0) FLOOR
		theme["floor_alt"],    # (1,0) FLOOR_ALT
		theme["wall"],         # (2,0) WALL
		theme["wall_top"],     # (3,0) WALL_TOP
		theme["accent"],       # (0,1) ACCENT
		theme["accent_glow"],  # (1,1) ACCENT_GLOW
		Color(0.5, 0.5, 0.4),  # (2,1) PROP_DOOR
		Color(0.4, 0.4, 0.5),  # (3,1) PROP_MARKER
		Color(0.25, 0.25, 0.27),  # (0,2) extra
		Color(0.22, 0.22, 0.24),  # (1,2) extra
		Color(0.18, 0.18, 0.20),  # (2,2) extra
		Color(0.22, 0.22, 0.24),  # (3,2) extra
		theme["accent"] * 0.8,  # (0,3) darker accent
		theme["accent_glow"] * 0.7,  # (1,3) darker glow
		Color(0.3, 0.3, 0.35),  # (2,3) wall shadow
		Color(0.15, 0.15, 0.18),  # (3,3) deep shadow
	]
	
	# 用 Godot 的 Image API 生成占位纹理
	atlas_source.texture = _create_atlas_texture(colors)
	atlas_source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
	
	# 为每个坐标创建 tile item
	for y in range(TILESET_SIZE.y):
		for x in range(TILESET_SIZE.x):
			var coords := Vector2i(x, y)
			atlas_source.create_tile(coords)
	
	tile_set.add_source(atlas_source, 0)
	
	# 应用到 TileMapLayer
	tilemap.tile_set = tile_set


## 用 Image API 生成 4×4 tileset 图集纹理（纯色占位）
func _create_atlas_texture(colors: Array) -> Texture2D:
	var atlas_w := TILESET_SIZE.x * CELL_SIZE  # 256
	var atlas_h := TILESET_SIZE.y * CELL_SIZE  # 256
	
	var image := Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	for i in range(colors.size()):
		var x: int = (i % TILESET_SIZE.x) * CELL_SIZE
		var y: int = int(i / TILESET_SIZE.x) * CELL_SIZE
		# 填充这个 tile 区域
		var color: Color = colors[i]
		for py in range(CELL_SIZE):
			for px in range(CELL_SIZE):
				image.set_pixel(x + px, y + py, color)
	
	return ImageTexture.create_from_image(image)


## 填充房间 TileMap（内部用）
## room_size: Vector2，房间像素尺寸（如 800×600）
## fills the interior with FLOOR tiles, borders with WALL tiles
func populate_room_tilemap(tilemap: TileMapLayer, room_size: Vector2, room_type: RoomData.RoomType) -> void:
	var theme: Dictionary = ROOM_THEMES.get(room_type, ROOM_THEMES[RoomData.RoomType.COMBAT])
	
	var cell_count_x: int = int(room_size.x) / CELL_SIZE
	var cell_count_y: int = int(room_size.y) / CELL_SIZE
	
	# 计算偏移（让 TileMap 以房间中心为原点）
	var offset: Vector2i = Vector2i(-room_size.x / 2, -room_size.y / 2)
	
	# 填充地板（内部格）
	for cy in range(1, cell_count_y - 1):
		for cx in range(1, cell_count_x - 1):
			var use_alt: bool = (cx + cy) % 3 == 0
			var tile_id: Vector2i = Vector2i(0, 0) if use_alt else Vector2i(1, 0)
			# 交错地板变化格
			var coords := Vector2i(cx + offset.x, cy + offset.y)
			tilemap.set_cell(coords, 0, tile_id)
	
	# 边缘：墙（第一圈和最后一圈）
	for cy in range(cell_count_y):
		for cx in range(cell_count_x):
			var is_edge: bool = (cx == 0 or cy == 0 or cx == cell_count_x - 1 or cy == cell_count_y - 1)
			if is_edge:
				var coords := Vector2i(cx + offset.x, cy + offset.y)
				# 顶层用 WALL_TOP（更亮），其他用 WALL
				var is_top_edge: bool = (cy == 0 or cy == cell_count_y - 1)
				var tile_id: Vector2i = Vector2i(3, 0) if is_top_edge else Vector2i(2, 0)
				tilemap.set_cell(coords, 0, tile_id)
	
	# 在战斗房添加血迹装饰
	if room_type == RoomData.RoomType.COMBAT or room_type == RoomData.RoomType.ELITE:
		_add_splatter_decoration(tilemap, cell_count_x, cell_count_y, offset)
	# 在商人房添加暖色光斑
	elif room_type == RoomData.RoomType.MERCHANT:
		_add_merchant_glow(tilemap, cell_count_x, cell_count_y, offset, theme)
	# 在改造房添加电缆装饰
	elif room_type == RoomData.RoomType.UPGRADE:
		_add_upgrade_cables(tilemap, cell_count_x, cell_count_y, offset, theme)


## 添加血迹装饰（战斗房/精英房）
func _add_splatter_decoration(tilemap: TileMapLayer, cell_count_x: int, cell_count_y: int, offset: Vector2i) -> void:
	# 在内部区域随机撒血迹格
	var splatter_positions := [
		Vector2i(2, 2), Vector2i(3, 4), Vector2i(5, 3),
		Vector2i(7, 5), Vector2i(4, 6), Vector2i(8, 3),
		Vector2i(6, 7), Vector2i(3, 7),
	]
	for pos in splatter_positions:
		if pos.x < cell_count_x - 1 and pos.y < cell_count_y - 1:
			var coords := Vector2i(pos.x + offset.x, pos.y + offset.y)
			tilemap.set_cell(coords, 0, Vector2i(4, 0))  # ACCENT tile


## 添加商人房暖色光斑（ACCENT_GLOW tile）
func _add_merchant_glow(tilemap: TileMapLayer, cell_count_x: int, cell_count_y: int, offset: Vector2i, theme: Dictionary) -> void:
	# 商人房中心区域有暖色光斑（模拟商人的灯光聚焦）
	var glow_positions := [
		Vector2i(cell_count_x / 2 - 1, cell_count_y / 2 - 1),  # 中心
		Vector2i(cell_count_x / 2 + 1, cell_count_y / 2),      # 略偏右
	]
	for pos in glow_positions:
		if pos.x > 0 and pos.y > 0 and pos.x < cell_count_x - 1 and pos.y < cell_count_y - 1:
			var coords := Vector2i(pos.x + offset.x, pos.y + offset.y)
			tilemap.set_cell(coords, 0, Vector2i(5, 0))  # ACCENT_GLOW tile


## 添加改造房电缆装饰（ACCENT tile）
func _add_upgrade_cables(tilemap: TileMapLayer, cell_count_x: int, cell_count_y: int, offset: Vector2i, theme: Dictionary) -> void:
	# 改造房地面有电缆穿过（工业风装饰）
	var cable_positions := [
		Vector2i(2, cell_count_y / 2 - 1),   # 左侧穿出
		Vector2i(3, cell_count_y / 2),       # 左侧穿出
		Vector2i(cell_count_x - 3, cell_count_y / 2 - 1),  # 右侧穿出
		Vector2i(cell_count_x - 4, cell_count_y / 2),      # 右侧穿出
		Vector2i(cell_count_x / 2, 2),        # 上方穿出
		Vector2i(cell_count_x / 2 - 1, 3),    # 上方穿出
	]
	for pos in cable_positions:
		if pos.x > 0 and pos.y > 0 and pos.x < cell_count_x - 1 and pos.y < cell_count_y - 1:
			var coords := Vector2i(pos.x + offset.x, pos.y + offset.y)
			tilemap.set_cell(coords, 0, Vector2i(4, 0))  # ACCENT tile


## 获取房间主题色（用于其他装饰节点）
func get_room_theme_colors(room_type: RoomData.RoomType) -> Dictionary:
	return ROOM_THEMES.get(room_type, ROOM_THEMES[RoomData.RoomType.COMBAT])
