class_name RoomData
## 房间数据 — 描述单个房间的类型、属性和标签

enum RoomType {
	INVALID = -1,
	PLAYER_SPAWN = 0,   # 玩家出生房（第一个房间）
	COMBAT = 1,          # 普通战斗房
	ELITE = 2,           # 精英战斗房
	SCAVENGE = 3,        # 搜刮房（道具、箱子）
	MERCHANT = 4,        # 商人房
	UPGRADE = 5,         # 改造房
	EVENT = 6,           # 事件房（随机事件、赌局）
	EXTRACTION = 7,     # 撤离房（可选择结束本局）
	BOSS = 8,            # Boss房
}

## 房间层级（影响难度和奖励）
enum FloorLevel {
	SHALLOW = 0,    # 浅层：怪物弱，资源一般
	MEDIUM = 1,     # 中层：精英怪、陷阱、特殊事件
	DEEP = 2,       # 深层：Boss频繁，稀有掉落
	ABYSS = 3,      # 污染/异化层：变种规则
}

var room_type: RoomType = RoomType.COMBAT
var floor_level: FloorLevel = FloorLevel.SHALLOW
var room_id: String = ""
var floor: int = 1  # 所在层
var position: Vector2 = Vector2.ZERO  # 在节点图中的坐标
var tags: Array[String] = []  # 房间标签，用于内容注入
var size: Vector2 = Vector2(800, 600)  # 默认房间尺寸

func _init(type: RoomType = RoomType.COMBAT, p_floor: int = 1):
	room_type = type
	floor = p_floor
	room_id = _generate_id()

func _generate_id() -> String:
	var timestamp := Time.get_datetime_string_from_system()
	var hash_str := str(Time.get_ticks_msec()) + str(room_type)
	return "room_%s_%d" % [hash_str, floor]

## 房间类型名称
static func get_type_name(t: RoomType) -> String:
	match t:
		RoomType.PLAYER_SPAWN: return "玩家出生"
		RoomType.COMBAT: return "普通战斗"
		RoomType.ELITE: return "精英战斗"
		RoomType.SCAVENGE: return "搜刮"
		RoomType.MERCHANT: return "商人"
		RoomType.UPGRADE: return "改造"
		RoomType.EVENT: return "事件"
		RoomType.EXTRACTION: return "撤离"
		RoomType.BOSS: return "Boss"
		_: return "未知"

## 层级名称
static func get_level_name(l: FloorLevel) -> String:
	match l:
		FloorLevel.SHALLOW: return "浅层"
		FloorLevel.MEDIUM: return "中层"
		FloorLevel.DEEP: return "深层"
		FloorLevel.ABYSS: return "污染层"
		_: return "未知"

## 是否为战斗相关房间
func is_combat() -> bool:
	return room_type in [RoomType.COMBAT, RoomType.ELITE, RoomType.BOSS]

## 是否可以搜刮
func is_scavenge() -> bool:
	return room_type in [RoomType.SCAVENGE, RoomType.MERCHANT]

## 是否可撤离
func is_extraction() -> bool:
	return room_type in [RoomType.EXTRACTION, RoomType.BOSS]

## 添加标签
func add_tag(tag: String) -> void:
	if not tag in tags:
		tags.append(tag)

## 是否有特定标签
func has_tag(tag: String) -> bool:
	return tag in tags

## 房间危险等级（用于UI显示）
func danger_level() -> int:
	match room_type:
		RoomType.BOSS: return 5
		RoomType.ELITE: return 4
		RoomType.COMBAT: return 1 + floor
		RoomType.EVENT: return 3
		_: return 0

## 奖励等级
func reward_level() -> int:
	match room_type:
		RoomType.BOSS: return 5
		RoomType.ELITE: return 4
		RoomType.SCAVENGE: return 3
		RoomType.MERCHANT: return 3
		RoomType.UPGRADE: return 2
		RoomType.COMBAT: return 1 + floor
		RoomType.EVENT: return 2
		_: return 0

func _to_string() -> String:
	return "[RoomData %s %s fl=%d]" % [get_type_name(room_type), room_id, floor_level]