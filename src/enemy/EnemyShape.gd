class_name EnemyShape
## EnemyShape — 程序生成 6 种怪物形状的 Polygon2D 顶点数组
## 用途：让玩家凭形状也能一眼分辨怪物类型（不只是颜色）
## 所有形状以 (0,0) 为中心，半径约 18px

extends RefCounted


enum ShapeType {
	CHASER = 0,    # 三角
	RANGED = 1,    # 菱形
	SUMMONER = 2,  # 五角星
	TANK = 3,      # 六边形
	BOMBER = 4,    # 圆形（实际用 ColorRect 风格绘制，但用 polygon 模拟圆）
	TRAPPER = 5,   # 倒三角
}

## 体型、碰撞与运动频率的单一数据源。渲染器和 EnemyBase 共用这些数值，
## 避免“看起来很大，实际碰撞圈很小”的战斗误导。
const PROFILES: Dictionary = {
	ShapeType.CHASER: {
		"role": "rush_melee",
		"silhouette": "low_wedge_tusks",
		"visual_scale": 0.82,
		"collision_radius": 15.0,
		"contact_radius": 27.0,
		"visual_extent": 27.0,
		"gait_frequency": 9.0,
	},
	ShapeType.RANGED: {
		"role": "flank_ranged",
		"silhouette": "tall_spore_tripod",
		"visual_scale": 1.0,
		"collision_radius": 18.0,
		"contact_radius": 31.0,
		"visual_extent": 34.0,
		"gait_frequency": 3.2,
	},
	ShapeType.SUMMONER: {
		"role": "spawn_support",
		"silhouette": "wide_hive_satellites",
		"visual_scale": 1.32,
		"collision_radius": 25.0,
		"contact_radius": 41.0,
		"visual_extent": 42.0,
		"gait_frequency": 1.65,
	},
	ShapeType.TANK: {
		"role": "frontline_guard",
		"silhouette": "broad_shell_shield",
		"visual_scale": 1.55,
		"collision_radius": 29.0,
		"contact_radius": 47.0,
		"visual_extent": 48.0,
		"gait_frequency": 2.25,
	},
	ShapeType.BOMBER: {
		"role": "proximity_burst",
		"silhouette": "swollen_core_cracks",
		"visual_scale": 1.14,
		"collision_radius": 21.0,
		"contact_radius": 33.0,
		"visual_extent": 36.0,
		"gait_frequency": 5.4,
	},
	ShapeType.TRAPPER: {
		"role": "buried_ambush",
		"silhouette": "ground_mound_spikes",
		"visual_scale": 0.92,
		"collision_radius": 17.0,
		"contact_radius": 29.0,
		"visual_extent": 29.0,
		"gait_frequency": 7.2,
	},
}


## 生成器名称和运行时 ai_type 到视觉职责的唯一映射。
static func shape_for_kind(enemy_type: String, ai_type: String = "") -> int:
	match enemy_type.to_lower():
		"melee_chaser", "chaser", "basic", "melee":
			return ShapeType.CHASER
		"ranged_caster", "ranged", "caster", "shooter":
			return ShapeType.RANGED
		"summoner":
			return ShapeType.SUMMONER
		"shielded", "tank", "brute", "elite_brute", "guard":
			return ShapeType.TANK
		"exploder", "bomber", "suicide":
			return ShapeType.BOMBER
		"ambusher", "trapper":
			return ShapeType.TRAPPER
	match ai_type.to_lower():
		"ranged": return ShapeType.RANGED
		"summoner": return ShapeType.SUMMONER
		"bomber": return ShapeType.BOMBER
		"trapper": return ShapeType.TRAPPER
	return ShapeType.CHASER


static func get_profile(shape_type: int) -> Dictionary:
	return (PROFILES.get(shape_type, PROFILES[ShapeType.CHASER]) as Dictionary).duplicate(true)


## 根据形状类型和大小返回顶点数组（中心 (0,0)）
static func make_polygon(shape_type: int, size: float = 18.0) -> PackedVector2Array:
	match shape_type:
		ShapeType.CHASER:
			return _triangle(size, false)
		ShapeType.RANGED:
			return _diamond(size)
		ShapeType.SUMMONER:
			return _five_pointed_star(size)
		ShapeType.TANK:
			return _hexagon(size)
		ShapeType.BOMBER:
			return _circle_approx(size, 14)
		ShapeType.TRAPPER:
			return _triangle(size, true)  # 倒三角
		_:
			return _triangle(size, false)


## 三角 (is_inverted=false 顶点朝上; true 顶点朝下)
static func _triangle(size: float, is_inverted: bool) -> PackedVector2Array:
	if is_inverted:
		return PackedVector2Array([
			Vector2(-size, -size * 0.6),
			Vector2(size, -size * 0.6),
			Vector2(0, size),
		])
	else:
		return PackedVector2Array([
			Vector2(0, -size),
			Vector2(size, size * 0.6),
			Vector2(-size, size * 0.6),
		])


## 菱形
static func _diamond(size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -size),
		Vector2(size * 0.7, 0),
		Vector2(0, size),
		Vector2(-size * 0.7, 0),
	])


## 五角星（5 顶点 + 5 内点，10 个顶点）
static func _five_pointed_star(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var outer_r := size
	var inner_r := size * 0.45
	for i in 10:
		var angle: float = -PI / 2.0 + i * PI / 5.0
		var r: float = outer_r if i % 2 == 0 else inner_r
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts


## 六边形
static func _hexagon(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle: float = i * PI / 3.0
		pts.append(Vector2(cos(angle), sin(angle)) * size)
	return pts


## 圆形近似（多边形）
static func _circle_approx(size: float, segments: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle: float = TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * size)
	return pts


## 形状类型的字符串映射（供 EnemyTypes 字段名引用）
static func shape_name(shape_type: int) -> String:
	match shape_type:
		ShapeType.CHASER: return "chaser"
		ShapeType.RANGED: return "ranged"
		ShapeType.SUMMONER: return "summoner"
		ShapeType.TANK: return "tank"
		ShapeType.BOMBER: return "bomber"
		ShapeType.TRAPPER: return "trapper"
		_: return "unknown"
