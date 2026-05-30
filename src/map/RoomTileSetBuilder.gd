class_name RoomTileSetBuilder
extends RefCounted
## 运行时构建 Room TileSet — 生成纯色占位 Tile，不依赖外部图片资源
## 使用方式：在 Room 场景的 _ready() 中调用 build_tile_set(tilemap_layer)

## TileSet 配置（从 GridConstants 读取格子尺寸，房间格数由外部传入）
## CELL_SIZE 和 TILESET_SIZE 保持本地，因为 TileSet 是 4×4 图集，不是房间格
const CELL_SIZE := GridConstants.CELL_SIZE  # 64px，从 GridConstants 引用
const TILESET_SIZE := Vector2i(4, 4)  # 4×4 图集网格（共16个tile slot）

## 楼层主题配置 — 第1关冷灰钢铁 / 第2关锈铁血锈 / 第3关深紫异化 / 第4关混沌黑红
## 格式: FLOOR_THEMES[floor][room_type] = { floor, floor_alt, wall, wall_top, accent, accent_glow }
const FLOOR_THEMES := {
	1: {
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
		RoomData.RoomType.STAIRS_DOWN: {
			"floor": Color(0.26, 0.20, 0.16),
			"floor_alt": Color(0.24, 0.18, 0.14),
			"wall": Color(0.20, 0.15, 0.11),
			"wall_top": Color(0.28, 0.22, 0.17),
			"accent": Color(0.50, 0.30, 0.10),
			"accent_glow": Color(0.55, 0.35, 0.12),
		},
		RoomData.RoomType.STAIRS_UP: {
			"floor": Color(0.26, 0.20, 0.16),
			"floor_alt": Color(0.24, 0.18, 0.14),
			"wall": Color(0.20, 0.15, 0.11),
			"wall_top": Color(0.28, 0.22, 0.17),
			"accent": Color(0.50, 0.30, 0.10),
			"accent_glow": Color(0.55, 0.35, 0.12),
		},
		RoomData.RoomType.ELEVATOR: {
			"floor": Color(0.26, 0.20, 0.16),
			"floor_alt": Color(0.24, 0.18, 0.14),
			"wall": Color(0.20, 0.15, 0.11),
			"wall_top": Color(0.28, 0.22, 0.17),
			"accent": Color(0.60, 0.40, 0.15),
			"accent_glow": Color(0.70, 0.50, 0.20),
		},
		RoomData.RoomType.BASEMENT: {
			"floor": Color(0.18, 0.14, 0.12),
			"floor_alt": Color(0.16, 0.12, 0.10),
			"wall": Color(0.14, 0.10, 0.08),
			"wall_top": Color(0.22, 0.16, 0.12),
			"accent": Color(0.45, 0.20, 0.05),
			"accent_glow": Color(0.40, 0.15, 0.04),
		},
		RoomData.RoomType.EXTRACTION: {
			"floor": Color(0.15, 0.22, 0.28),
			"floor_alt": Color(0.13, 0.20, 0.26),
			"wall": Color(0.12, 0.18, 0.24),
			"wall_top": Color(0.18, 0.28, 0.38),
			"accent": Color(0.15, 0.60, 0.50),
			"accent_glow": Color(0.20, 0.75, 0.60),
		},
		RoomData.RoomType.PLAYER_SPAWN: {
			"floor": Color(0.20, 0.28, 0.22),
			"floor_alt": Color(0.18, 0.25, 0.20),
			"wall": Color(0.15, 0.22, 0.18),
			"wall_top": Color(0.22, 0.30, 0.24),
			"accent": Color(0.20, 0.50, 0.35),
			"accent_glow": Color(0.25, 0.65, 0.45),
		},
	},
	2: {
		## 第二关：锈铁血锈主题 — 暖棕红调，危险压迫感更强
		RoomData.RoomType.COMBAT: {
			"floor": Color(0.28, 0.22, 0.18),
			"floor_alt": Color(0.25, 0.19, 0.15),
			"wall": Color(0.20, 0.15, 0.12),
			"wall_top": Color(0.28, 0.20, 0.16),
			"accent": Color(0.50, 0.12, 0.06),
			"accent_glow": Color(0.45, 0.08, 0.04),
		},
		RoomData.RoomType.ELITE: {
			"floor": Color(0.22, 0.18, 0.20),
			"floor_alt": Color(0.20, 0.15, 0.18),
			"wall": Color(0.17, 0.12, 0.14),
			"wall_top": Color(0.24, 0.18, 0.20),
			"accent": Color(0.55, 0.10, 0.05),
			"accent_glow": Color(0.60, 0.08, 0.04),
		},
		RoomData.RoomType.SCAVENGE: {
			"floor": Color(0.32, 0.26, 0.20),
			"floor_alt": Color(0.29, 0.23, 0.17),
			"wall": Color(0.26, 0.20, 0.15),
			"wall_top": Color(0.35, 0.27, 0.20),
			"accent": Color(0.45, 0.30, 0.15),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.MERCHANT: {
			"floor": Color(0.34, 0.28, 0.18),
			"floor_alt": Color(0.31, 0.25, 0.15),
			"wall": Color(0.29, 0.23, 0.15),
			"wall_top": Color(0.40, 0.32, 0.18),
			"accent": Color(0.88, 0.72, 0.22),
			"accent_glow": Color(1.0, 0.82, 0.28),
		},
		RoomData.RoomType.UPGRADE: {
			"floor": Color(0.24, 0.26, 0.32),
			"floor_alt": Color(0.21, 0.23, 0.29),
			"wall": Color(0.18, 0.20, 0.26),
			"wall_top": Color(0.26, 0.30, 0.42),
			"accent": Color(0.22, 0.42, 0.62),
			"accent_glow": Color(0.28, 0.52, 0.72),
		},
		RoomData.RoomType.EVENT: {
			"floor": Color(0.20, 0.14, 0.28),
			"floor_alt": Color(0.18, 0.12, 0.25),
			"wall": Color(0.16, 0.10, 0.22),
			"wall_top": Color(0.26, 0.16, 0.35),
			"accent": Color(0.58, 0.22, 0.72),
			"accent_glow": Color(0.68, 0.28, 0.82),
		},
		RoomData.RoomType.BOSS: {
			"floor": Color(0.12, 0.08, 0.11),
			"floor_alt": Color(0.10, 0.06, 0.09),
			"wall": Color(0.14, 0.06, 0.07),
			"wall_top": Color(0.22, 0.08, 0.10),
			"accent": Color(0.65, 0.06, 0.06),
			"accent_glow": Color(0.85, 0.12, 0.06),
		},
		RoomData.RoomType.TRAP: {
			"floor": Color(0.26, 0.14, 0.11),
			"floor_alt": Color(0.23, 0.12, 0.09),
			"wall": Color(0.20, 0.09, 0.07),
			"wall_top": Color(0.30, 0.12, 0.09),
			"accent": Color(0.55, 0.09, 0.05),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.STORAGE: {
			"floor": Color(0.30, 0.22, 0.15),
			"floor_alt": Color(0.27, 0.19, 0.13),
			"wall": Color(0.24, 0.17, 0.11),
			"wall_top": Color(0.33, 0.24, 0.16),
			"accent": Color(0.38, 0.26, 0.16),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.STAIRS_DOWN: {
			"floor": Color(0.28, 0.22, 0.18),
			"floor_alt": Color(0.26, 0.20, 0.16),
			"wall": Color(0.22, 0.16, 0.12),
			"wall_top": Color(0.30, 0.22, 0.18),
			"accent": Color(0.55, 0.32, 0.12),
			"accent_glow": Color(0.60, 0.38, 0.15),
		},
		RoomData.RoomType.STAIRS_UP: {
			"floor": Color(0.28, 0.22, 0.18),
			"floor_alt": Color(0.26, 0.20, 0.16),
			"wall": Color(0.22, 0.16, 0.12),
			"wall_top": Color(0.30, 0.22, 0.18),
			"accent": Color(0.55, 0.32, 0.12),
			"accent_glow": Color(0.60, 0.38, 0.15),
		},
		RoomData.RoomType.ELEVATOR: {
			"floor": Color(0.28, 0.22, 0.18),
			"floor_alt": Color(0.26, 0.20, 0.16),
			"wall": Color(0.22, 0.16, 0.12),
			"wall_top": Color(0.30, 0.22, 0.18),
			"accent": Color(0.65, 0.42, 0.18),
			"accent_glow": Color(0.75, 0.52, 0.22),
		},
		RoomData.RoomType.BASEMENT: {
			"floor": Color(0.20, 0.15, 0.13),
			"floor_alt": Color(0.18, 0.13, 0.11),
			"wall": Color(0.16, 0.11, 0.09),
			"wall_top": Color(0.24, 0.17, 0.13),
			"accent": Color(0.48, 0.22, 0.06),
			"accent_glow": Color(0.42, 0.16, 0.05),
		},
		RoomData.RoomType.EXTRACTION: {
			"floor": Color(0.16, 0.24, 0.30),
			"floor_alt": Color(0.14, 0.22, 0.28),
			"wall": Color(0.13, 0.20, 0.26),
			"wall_top": Color(0.20, 0.30, 0.40),
			"accent": Color(0.16, 0.62, 0.52),
			"accent_glow": Color(0.22, 0.78, 0.65),
		},
		RoomData.RoomType.PLAYER_SPAWN: {
			"floor": Color(0.22, 0.28, 0.23),
			"floor_alt": Color(0.20, 0.25, 0.21),
			"wall": Color(0.17, 0.22, 0.19),
			"wall_top": Color(0.24, 0.30, 0.25),
			"accent": Color(0.22, 0.52, 0.38),
			"accent_glow": Color(0.28, 0.65, 0.48),
		},
	},
	3: {
		## 第三关：深紫异化主题
		RoomData.RoomType.COMBAT: {
			"floor": Color(0.20, 0.16, 0.22),
			"floor_alt": Color(0.17, 0.13, 0.19),
			"wall": Color(0.14, 0.10, 0.17),
			"wall_top": Color(0.22, 0.17, 0.26),
			"accent": Color(0.42, 0.08, 0.32),
			"accent_glow": Color(0.52, 0.12, 0.42),
		},
		RoomData.RoomType.ELITE: {
			"floor": Color(0.16, 0.12, 0.20),
			"floor_alt": Color(0.13, 0.10, 0.17),
			"wall": Color(0.11, 0.08, 0.15),
			"wall_top": Color(0.19, 0.14, 0.24),
			"accent": Color(0.48, 0.08, 0.38),
			"accent_glow": Color(0.58, 0.10, 0.48),
		},
		RoomData.RoomType.SCAVENGE: {
			"floor": Color(0.25, 0.22, 0.28),
			"floor_alt": Color(0.22, 0.19, 0.25),
			"wall": Color(0.20, 0.17, 0.22),
			"wall_top": Color(0.28, 0.24, 0.32),
			"accent": Color(0.35, 0.25, 0.45),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.MERCHANT: {
			"floor": Color(0.26, 0.22, 0.15),
			"floor_alt": Color(0.23, 0.19, 0.12),
			"wall": Color(0.21, 0.17, 0.11),
			"wall_top": Color(0.32, 0.26, 0.18),
			"accent": Color(0.82, 0.65, 0.18),
			"accent_glow": Color(0.92, 0.75, 0.25),
		},
		RoomData.RoomType.UPGRADE: {
			"floor": Color(0.18, 0.20, 0.28),
			"floor_alt": Color(0.15, 0.17, 0.25),
			"wall": Color(0.12, 0.15, 0.22),
			"wall_top": Color(0.22, 0.26, 0.38),
			"accent": Color(0.18, 0.38, 0.58),
			"accent_glow": Color(0.22, 0.48, 0.68),
		},
		RoomData.RoomType.EVENT: {
			"floor": Color(0.14, 0.10, 0.22),
			"floor_alt": Color(0.12, 0.08, 0.19),
			"wall": Color(0.10, 0.06, 0.17),
			"wall_top": Color(0.20, 0.12, 0.30),
			"accent": Color(0.52, 0.15, 0.65),
			"accent_glow": Color(0.62, 0.20, 0.75),
		},
		RoomData.RoomType.BOSS: {
			"floor": Color(0.08, 0.05, 0.12),
			"floor_alt": Color(0.06, 0.03, 0.09),
			"wall": Color(0.10, 0.03, 0.08),
			"wall_top": Color(0.16, 0.05, 0.14),
			"accent": Color(0.58, 0.04, 0.58),
			"accent_glow": Color(0.78, 0.08, 0.78),
		},
		RoomData.RoomType.TRAP: {
			"floor": Color(0.20, 0.10, 0.18),
			"floor_alt": Color(0.17, 0.08, 0.15),
			"wall": Color(0.15, 0.06, 0.13),
			"wall_top": Color(0.25, 0.10, 0.22),
			"accent": Color(0.48, 0.06, 0.48),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.STORAGE: {
			"floor": Color(0.22, 0.16, 0.25),
			"floor_alt": Color(0.19, 0.13, 0.22),
			"wall": Color(0.17, 0.11, 0.19),
			"wall_top": Color(0.28, 0.20, 0.30),
			"accent": Color(0.32, 0.22, 0.40),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.STAIRS_DOWN: {
			"floor": Color(0.20, 0.15, 0.22),
			"floor_alt": Color(0.18, 0.13, 0.20),
			"wall": Color(0.16, 0.11, 0.17),
			"wall_top": Color(0.25, 0.18, 0.26),
			"accent": Color(0.52, 0.28, 0.12),
			"accent_glow": Color(0.58, 0.32, 0.15),
		},
		RoomData.RoomType.STAIRS_UP: {
			"floor": Color(0.20, 0.15, 0.22),
			"floor_alt": Color(0.18, 0.13, 0.20),
			"wall": Color(0.16, 0.11, 0.17),
			"wall_top": Color(0.25, 0.18, 0.26),
			"accent": Color(0.52, 0.28, 0.12),
			"accent_glow": Color(0.58, 0.32, 0.15),
		},
		RoomData.RoomType.ELEVATOR: {
			"floor": Color(0.20, 0.15, 0.22),
			"floor_alt": Color(0.18, 0.13, 0.20),
			"wall": Color(0.16, 0.11, 0.17),
			"wall_top": Color(0.25, 0.18, 0.26),
			"accent": Color(0.62, 0.38, 0.18),
			"accent_glow": Color(0.72, 0.48, 0.22),
		},
		RoomData.RoomType.BASEMENT: {
			"floor": Color(0.15, 0.10, 0.18),
			"floor_alt": Color(0.13, 0.08, 0.15),
			"wall": Color(0.11, 0.06, 0.13),
			"wall_top": Color(0.20, 0.12, 0.22),
			"accent": Color(0.42, 0.18, 0.05),
			"accent_glow": Color(0.38, 0.12, 0.04),
		},
		RoomData.RoomType.EXTRACTION: {
			"floor": Color(0.12, 0.20, 0.28),
			"floor_alt": Color(0.10, 0.18, 0.25),
			"wall": Color(0.09, 0.16, 0.23),
			"wall_top": Color(0.16, 0.28, 0.38),
			"accent": Color(0.12, 0.58, 0.48),
			"accent_glow": Color(0.18, 0.72, 0.60),
		},
		RoomData.RoomType.PLAYER_SPAWN: {
			"floor": Color(0.18, 0.24, 0.20),
			"floor_alt": Color(0.15, 0.21, 0.18),
			"wall": Color(0.13, 0.18, 0.15),
			"wall_top": Color(0.22, 0.28, 0.24),
			"accent": Color(0.20, 0.48, 0.35),
			"accent_glow": Color(0.25, 0.58, 0.42),
		},
	},
	4: {
		## 第四关：混沌黑红主题
		RoomData.RoomType.COMBAT: {
			"floor": Color(0.14, 0.10, 0.12),
			"floor_alt": Color(0.12, 0.08, 0.10),
			"wall": Color(0.10, 0.06, 0.08),
			"wall_top": Color(0.18, 0.12, 0.14),
			"accent": Color(0.55, 0.06, 0.04),
			"accent_glow": Color(0.65, 0.08, 0.05),
		},
		RoomData.RoomType.ELITE: {
			"floor": Color(0.11, 0.08, 0.11),
			"floor_alt": Color(0.09, 0.06, 0.09),
			"wall": Color(0.08, 0.05, 0.08),
			"wall_top": Color(0.15, 0.10, 0.12),
			"accent": Color(0.60, 0.05, 0.05),
			"accent_glow": Color(0.72, 0.06, 0.06),
		},
		RoomData.RoomType.SCAVENGE: {
			"floor": Color(0.18, 0.14, 0.12),
			"floor_alt": Color(0.15, 0.12, 0.10),
			"wall": Color(0.13, 0.09, 0.08),
			"wall_top": Color(0.22, 0.17, 0.14),
			"accent": Color(0.42, 0.22, 0.12),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.MERCHANT: {
			"floor": Color(0.20, 0.16, 0.10),
			"floor_alt": Color(0.17, 0.13, 0.08),
			"wall": Color(0.15, 0.11, 0.07),
			"wall_top": Color(0.28, 0.22, 0.14),
			"accent": Color(0.80, 0.58, 0.15),
			"accent_glow": Color(0.92, 0.68, 0.22),
		},
		RoomData.RoomType.UPGRADE: {
			"floor": Color(0.12, 0.15, 0.22),
			"floor_alt": Color(0.10, 0.13, 0.19),
			"wall": Color(0.08, 0.11, 0.17),
			"wall_top": Color(0.18, 0.22, 0.32),
			"accent": Color(0.15, 0.32, 0.52),
			"accent_glow": Color(0.20, 0.42, 0.62),
		},
		RoomData.RoomType.EVENT: {
			"floor": Color(0.10, 0.07, 0.18),
			"floor_alt": Color(0.08, 0.05, 0.15),
			"wall": Color(0.07, 0.04, 0.13),
			"wall_top": Color(0.17, 0.10, 0.26),
			"accent": Color(0.48, 0.10, 0.58),
			"accent_glow": Color(0.58, 0.14, 0.68),
		},
		RoomData.RoomType.BOSS: {
			"floor": Color(0.06, 0.03, 0.06),
			"floor_alt": Color(0.04, 0.02, 0.04),
			"wall": Color(0.08, 0.02, 0.04),
			"wall_top": Color(0.14, 0.04, 0.08),
			"accent": Color(0.70, 0.03, 0.05),
			"accent_glow": Color(0.90, 0.05, 0.05),
		},
		RoomData.RoomType.TRAP: {
			"floor": Color(0.15, 0.07, 0.08),
			"floor_alt": Color(0.12, 0.05, 0.06),
			"wall": Color(0.10, 0.04, 0.05),
			"wall_top": Color(0.20, 0.08, 0.10),
			"accent": Color(0.52, 0.05, 0.04),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.STORAGE: {
			"floor": Color(0.16, 0.12, 0.10),
			"floor_alt": Color(0.13, 0.10, 0.08),
			"wall": Color(0.11, 0.08, 0.06),
			"wall_top": Color(0.22, 0.16, 0.13),
			"accent": Color(0.35, 0.20, 0.12),
			"accent_glow": Color(0.0, 0.0, 0.0),
		},
		RoomData.RoomType.STAIRS_DOWN: {
			"floor": Color(0.15, 0.12, 0.11),
			"floor_alt": Color(0.13, 0.10, 0.09),
			"wall": Color(0.11, 0.08, 0.07),
			"wall_top": Color(0.20, 0.15, 0.13),
			"accent": Color(0.55, 0.25, 0.10),
			"accent_glow": Color(0.62, 0.30, 0.12),
		},
		RoomData.RoomType.STAIRS_UP: {
			"floor": Color(0.15, 0.12, 0.11),
			"floor_alt": Color(0.13, 0.10, 0.09),
			"wall": Color(0.11, 0.08, 0.07),
			"wall_top": Color(0.20, 0.15, 0.13),
			"accent": Color(0.55, 0.25, 0.10),
			"accent_glow": Color(0.62, 0.30, 0.12),
		},
		RoomData.RoomType.ELEVATOR: {
			"floor": Color(0.15, 0.12, 0.11),
			"floor_alt": Color(0.13, 0.10, 0.09),
			"wall": Color(0.11, 0.08, 0.07),
			"wall_top": Color(0.20, 0.15, 0.13),
			"accent": Color(0.65, 0.35, 0.15),
			"accent_glow": Color(0.75, 0.45, 0.20),
		},
		RoomData.RoomType.BASEMENT: {
			"floor": Color(0.12, 0.08, 0.10),
			"floor_alt": Color(0.10, 0.06, 0.08),
			"wall": Color(0.08, 0.05, 0.07),
			"wall_top": Color(0.18, 0.11, 0.13),
			"accent": Color(0.45, 0.18, 0.04),
			"accent_glow": Color(0.40, 0.12, 0.03),
		},
		RoomData.RoomType.EXTRACTION: {
			"floor": Color(0.10, 0.18, 0.25),
			"floor_alt": Color(0.08, 0.15, 0.22),
			"wall": Color(0.07, 0.14, 0.20),
			"wall_top": Color(0.15, 0.25, 0.35),
			"accent": Color(0.10, 0.55, 0.45),
			"accent_glow": Color(0.15, 0.68, 0.55),
		},
		RoomData.RoomType.PLAYER_SPAWN: {
			"floor": Color(0.15, 0.20, 0.17),
			"floor_alt": Color(0.13, 0.18, 0.15),
			"wall": Color(0.10, 0.15, 0.12),
			"wall_top": Color(0.20, 0.26, 0.22),
			"accent": Color(0.18, 0.45, 0.30),
			"accent_glow": Color(0.22, 0.55, 0.38),
		},
	},
}

## tile_id → 配置索引（对应 TileSetAtlasSource 的坐标）
enum TileId {
	FLOOR = 0,
	FLOOR_ALT = 1,
	WALL = 2,
	WALL_TOP = 3,
	ACCENT = 4,
	ACCENT_GLOW = 5,
	PROP_DOOR = 6,
	PROP_MARKER = 7,
	PROP_CRATE = 8,
	PROP_BARREL = 9,
}


## 获取指定楼层的主题配色（fallback到楼层1）
func _get_theme_for_floor(floor: int, room_type: RoomData.RoomType) -> Dictionary:
	var floor_themes: Dictionary = FLOOR_THEMES.get(floor, FLOOR_THEMES[1])
	return floor_themes.get(room_type, FLOOR_THEMES[1].get(RoomData.RoomType.COMBAT))


## 为 TileMapLayer 构建并应用 TileSet（支持楼层感知配色）
func build_tile_set(tilemap: TileMapLayer, room_type: RoomData.RoomType, floor: int = 1) -> void:
	var theme: Dictionary = _get_theme_for_floor(floor, room_type)
	
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)

	# TileMap 瓦片仅做视觉展示，碰撞由 RoomLayout 统一提供
	# 不再添加 physics_layer，避免与 RoomLayout 碰撞重叠导致问题

	var atlas_source := TileSetAtlasSource.new()
	
	var colors := [
		theme["floor"],
		theme["floor_alt"],
		theme["wall"],
		theme["wall_top"],
		theme["accent"],
		theme["accent_glow"],
		Color(0.5, 0.5, 0.4),
		Color(0.4, 0.4, 0.5),
		Color(0.42, 0.32, 0.20),
		Color(0.38, 0.20, 0.12),
		theme["wall"] * 0.85,
		theme["floor_alt"] * 0.9,
		theme["accent"] * 0.8,
		theme["accent_glow"] * 0.7 if theme["accent_glow"] != Color(0, 0, 0) else theme["accent"] * 0.6,
		Color(0.3, 0.3, 0.35),
		Color(0.15, 0.15, 0.18),
	]
	
	atlas_source.texture = _create_atlas_texture(colors)
	atlas_source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
	
	for y in range(TILESET_SIZE.y):
		for x in range(TILESET_SIZE.x):
			var coords := Vector2i(x, y)
			atlas_source.create_tile(coords)

	tile_set.add_source(atlas_source, 0)
	tilemap.tile_set = tile_set


## 用 Image API 生成 4×4 tileset 图集纹理（纯色占位）
func _create_atlas_texture(colors: Array) -> Texture2D:
	var atlas_w := TILESET_SIZE.x * CELL_SIZE
	var atlas_h := TILESET_SIZE.y * CELL_SIZE
	
	var image := Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	for i in range(colors.size()):
		var x: int = (i % TILESET_SIZE.x) * CELL_SIZE
		var y: int = int(i / TILESET_SIZE.x) * CELL_SIZE
		var color: Color = colors[i]
		for py in range(CELL_SIZE):
			for px in range(CELL_SIZE):
				image.set_pixel(x + px, y + py, color)
	
	return ImageTexture.create_from_image(image)


## 填充房间 TileMap（内部用，支持楼层感知）
func populate_room_tilemap(
	tilemap: TileMapLayer, room_size: Vector2, room_type: RoomData.RoomType, floor: int = 1,
	door_info: Array[Dictionary] = []
) -> void:
	var theme: Dictionary = _get_theme_for_floor(floor, room_type)
	
	var cell_count_x: int = int(room_size.x) / CELL_SIZE
	var cell_count_y: int = int(room_size.y) / CELL_SIZE
	
	var offset: Vector2i = Vector2i(-cell_count_x / 2, -cell_count_y / 2)
	
	for cy in range(cell_count_y):
		for cx in range(cell_count_x):
			var use_alt: bool = (cx + cy) % 3 == 0
			var tile_id: Vector2i = Vector2i(0, 0) if use_alt else Vector2i(1, 0)
			var coords := Vector2i(cx + offset.x, cy + offset.y)
			tilemap.set_cell(coords, 0, tile_id)

	if room_type == RoomData.RoomType.COMBAT or room_type == RoomData.RoomType.ELITE:
		_add_splatter_decoration(tilemap, cell_count_x, cell_count_y, offset, floor)
	elif room_type == RoomData.RoomType.MERCHANT:
		_add_merchant_glow(tilemap, cell_count_x, cell_count_y, offset, theme)
	elif room_type == RoomData.RoomType.UPGRADE:
		_add_upgrade_cables(tilemap, cell_count_x, cell_count_y, offset, theme)

	# 墙体边界：房间最外一圈铺设 WALL 瓦片（自带碰撞），门洞位置留空
	# 上边
	for cx in range(cell_count_x):
		if _has_open_door_in_direction(door_info, Vector2i(0, -1)):
			continue
		tilemap.set_cell(Vector2i(cx + offset.x, offset.y), 0, Vector2i(TileId.WALL, 0))
	# 下边
	for cx in range(cell_count_x):
		if _has_open_door_in_direction(door_info, Vector2i(0, 1)):
			continue
		tilemap.set_cell(Vector2i(cx + offset.x, cell_count_y - 1 + offset.y), 0, Vector2i(TileId.WALL, 0))
	# 左边
	for cy in range(cell_count_y):
		if _has_open_door_in_direction(door_info, Vector2i(-1, 0)):
			continue
		tilemap.set_cell(Vector2i(offset.x, cy + offset.y), 0, Vector2i(TileId.WALL, 0))
	# 右边
	for cy in range(cell_count_y):
		if _has_open_door_in_direction(door_info, Vector2i(1, 0)):
			continue
		tilemap.set_cell(Vector2i(cell_count_x - 1 + offset.x, cy + offset.y), 0, Vector2i(TileId.WALL, 0))


## 辅助：判断指定方向是否有开门（用于门洞位置留空）
func _has_open_door_in_direction(door_info: Array[Dictionary], dir: Vector2i) -> bool:
	if dir == Vector2i(0, -1):  # 上
		var UP := Vector2(0, -1)
		for info in door_info:
			if not info.get("is_open", false):
				continue
			var d: Vector2 = info.get("direction", Vector2.ZERO)
			if d == UP:
				return true
	elif dir == Vector2i(0, 1):  # 下
		var DOWN := Vector2(0, 1)
		for info in door_info:
			if not info.get("is_open", false):
				continue
			var d: Vector2 = info.get("direction", Vector2.ZERO)
			if d == DOWN:
				return true
	elif dir == Vector2i(-1, 0):  # 左
		var LEFT := Vector2(-1, 0)
		for info in door_info:
			if not info.get("is_open", false):
				continue
			var d: Vector2 = info.get("direction", Vector2.ZERO)
			if d == LEFT:
				return true
	elif dir == Vector2i(1, 0):  # 右
		var RIGHT := Vector2(1, 0)
		for info in door_info:
			if not info.get("is_open", false):
				continue
			var d: Vector2 = info.get("direction", Vector2.ZERO)
			if d == RIGHT:
				return true
	return false

## 添加血迹装饰（战斗房/精英房，floor>=2时血迹更密集）
func _add_splatter_decoration(
	tilemap: TileMapLayer, cell_count_x: int, cell_count_y: int, offset: Vector2i, floor: int
) -> void:
	var splatter_positions: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(3, 4), Vector2i(5, 3),
		Vector2i(7, 5), Vector2i(4, 6), Vector2i(8, 3),
		Vector2i(6, 7), Vector2i(3, 7),
	]
	## floor>=2 时血迹位置增加50%，floor>=3增加100%
	if floor >= 3:
		splatter_positions.append_array([
			Vector2i(4, 3), Vector2i(7, 6), Vector2i(2, 5), Vector2i(5, 7),
			Vector2i(8, 5), Vector2i(1, 6),
		])
	elif floor >= 2:
		splatter_positions.append_array([
			Vector2i(4, 3), Vector2i(7, 6), Vector2i(2, 5),
		])
	
	for pos in splatter_positions:
		if pos.x < cell_count_x - 1 and pos.y < cell_count_y - 1:
			var coords := Vector2i(pos.x + offset.x, pos.y + offset.y)
			tilemap.set_cell(coords, 0, Vector2i(4, 0))


## 添加商人房暖色光斑
func _add_merchant_glow(
	tilemap: TileMapLayer, cell_count_x: int, cell_count_y: int, offset: Vector2i, theme: Dictionary
) -> void:
	var glow_positions := [
		Vector2i(cell_count_x / 2 - 1, cell_count_y / 2 - 1),
		Vector2i(cell_count_x / 2 + 1, cell_count_y / 2),
	]
	for pos in glow_positions:
		if pos.x > 0 and pos.y > 0 and pos.x < cell_count_x - 1 and pos.y < cell_count_y - 1:
			var coords := Vector2i(pos.x + offset.x, pos.y + offset.y)
			tilemap.set_cell(coords, 0, Vector2i(5, 0))


## 添加改造房电缆装饰
func _add_upgrade_cables(
	tilemap: TileMapLayer, cell_count_x: int, cell_count_y: int, offset: Vector2i, theme: Dictionary
) -> void:
	var cable_positions := [
		Vector2i(2, cell_count_y / 2 - 1),
		Vector2i(3, cell_count_y / 2),
		Vector2i(cell_count_x - 3, cell_count_y / 2 - 1),
		Vector2i(cell_count_x - 4, cell_count_y / 2),
		Vector2i(cell_count_x / 2, 2),
		Vector2i(cell_count_x / 2 - 1, 3),
	]
	for pos in cable_positions:
		if pos.x > 0 and pos.y > 0 and pos.x < cell_count_x - 1 and pos.y < cell_count_y - 1:
			var coords := Vector2i(pos.x + offset.x, pos.y + offset.y)
			tilemap.set_cell(coords, 0, Vector2i(4, 0))


## 获取房间主题色（用于其他装饰节点，支持楼层感知）
func get_room_theme_colors(room_type: RoomData.RoomType, floor: int = 1) -> Dictionary:
	return _get_theme_for_floor(floor, room_type)
