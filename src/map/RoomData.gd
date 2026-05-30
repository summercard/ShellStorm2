class_name RoomData
extends RefCounted
## 房间数据 — 描述单个房间的类型、属性和标签

enum RoomType {
	INVALID = -1,
	PLAYER_SPAWN = 0,  # 玩家出生房（第一个房间）
	COMBAT = 1,  # 普通战斗房
	ELITE = 2,  # 精英战斗房
	SCAVENGE = 3,  # 搜刮房（道具、箱子）
	MERCHANT = 4,  # 商人房
	UPGRADE = 5,  # 改造房
	EVENT = 6,  # 事件房（随机事件、赌局）
	EXTRACTION = 7,  # 撤离房（可选择结束本局）
	BOSS = 8,  # Boss房
	STORAGE = 9,  # 藏储室（隐藏容器，需要钥匙或特殊条件）
	TRAP = 10,  # 陷阱房（环境危险，怪物埋伏）
	BASEMENT = 11,  # 地下室（垂直关卡下层，比浅层更难，奖励更丰富）
	STAIRS_DOWN = 12,  # 通往地下室的楼梯入口
	STAIRS_UP = 13,   # 通往二楼的楼梯出口
	ELEVATOR = 14,    # 电梯（可上可下）
}

## 垂直楼层（用于实现真实上下楼结构）
## 注意：这不是 floor（关卡层），而是同一 floor 内的垂直位置
## floor=1, vertical_level=0 → 一楼
## floor=1, vertical_level=-1 → 地下室
## floor=1, vertical_level=1 → 二楼
enum VerticalLevel {
	BASEMENT = -1,  # 地下室（地下层）
	MAIN = 0,       # 主层（默认）
	UPPER = 1,      # 上层（二楼）
}

## 房间层级（影响难度和奖励）
enum FloorLevel {
	SHALLOW = 0,  # 浅层：怪物弱，资源一般
	MEDIUM = 1,  # 中层：精英怪、陷阱、特殊事件
	DEEP = 2,  # 深层：Boss频繁，稀有掉落
	ABYSS = 3,  # 污染/异化层：变种规则
}

## 房间尺寸分类（PH11 规范）
enum RoomSize {
	SMALL = 0,    # 单向出口，1v1战斗，快速通过（640×512）
	MEDIUM = 1,   # 标准战斗房（960×768）
	LARGE = 2,   # 多波次精英战，有更多走位空间（1280×1024）
	ARENA = 3,   # Boss战、事件爆发、极限压力（1600×1200）
}

## 房间尺寸像素对照表（按 RoomSize 枚举）
const ROOM_SIZE_TABLE: Dictionary = {
	RoomSize.SMALL:   Vector2(640, 512),
	RoomSize.MEDIUM:  Vector2(960, 768),
	RoomSize.LARGE:   Vector2(1280, 1024),
	RoomSize.ARENA:   Vector2(1600, 1200),
}

var room_type: RoomType = RoomType.COMBAT
var floor_level: FloorLevel = FloorLevel.SHALLOW
var room_id: String = ""
var room_number: int = -1
var floor: int = 1  # 所在层（关卡层，如第1关、第2关）
var vertical_level: VerticalLevel = VerticalLevel.MAIN  # 垂直楼层（地下室、主层、二楼）
var position: Vector2 = Vector2.ZERO  # 在节点图中的坐标
var tags: Array[String] = []  # 房间标签，用于内容注入
## 房间尺寸（默认 MEDIUM）
var room_size: RoomSize = RoomSize.MEDIUM
## 房间像素尺寸
var size: Vector2 = Vector2(960, 768)
func get_default_room_size() -> RoomSize:
	match room_type:
		RoomType.BOSS:
			return RoomSize.ARENA       # Boss房最大
		RoomType.ELITE:
			return RoomSize.LARGE       # 精英战需要更多走位
		RoomType.PLAYER_SPAWN:
			return RoomSize.MEDIUM      # 出生房标准
		RoomType.SCAVENGE:
			return RoomSize.MEDIUM      # 搜刮房标准
		RoomType.MERCHANT:
			return RoomSize.MEDIUM      # 商人房标准
		RoomType.UPGRADE:
			return RoomSize.MEDIUM      # 改造房标准
		RoomType.EVENT:
			return RoomSize.MEDIUM      # 事件房标准
		RoomType.EXTRACTION:
			return RoomSize.MEDIUM      # 撤离房标准
		RoomType.BASEMENT:
			return RoomSize.LARGE       # 地下室更大（有隐藏奖励探索空间）
		RoomType.STAIRS_DOWN, RoomType.STAIRS_UP, RoomType.ELEVATOR:
			return RoomSize.SMALL       # 通道房间最小（单向出口）
		RoomType.STORAGE:
			return RoomSize.SMALL       # 隐藏储藏室小
		RoomType.TRAP:
			return RoomSize.SMALL       # 陷阱房小（紧凑增加压力）
		_:
			# COMBAT：根据进度层级微调
			match floor_level:
				FloorLevel.SHALLOW:
					return RoomSize.MEDIUM
				FloorLevel.MEDIUM:
					return RoomSize.MEDIUM
				FloorLevel.DEEP:
					return RoomSize.LARGE
				FloorLevel.ABYSS:
					return RoomSize.LARGE
	return RoomSize.MEDIUM


## 获取房间像素尺寸（查表）
func get_pixel_size() -> Vector2:
	return ROOM_SIZE_TABLE.get(room_size, Vector2(960, 768))


## 创建后自动设置尺寸（供 MapGenerator 调用）
func auto_size() -> void:
	room_size = get_default_room_size()
	size = get_pixel_size()
var content_config: Dictionary = {
	"enemies": [],
	"loot": [],
	"events": [],
	"interactables": [],
	"special_conditions": [],
}


func _init(type: RoomType = RoomType.COMBAT, p_floor: int = 1):
	room_type = type
	floor = p_floor
	room_id = _generate_id()


func _generate_id() -> String:
	var timestamp := Time.get_datetime_string_from_system()
	var hash_str := str(Time.get_ticks_msec()) + str(room_type)
	return "room_%s_%d" % [hash_str, floor]


func assign_number(number: int) -> void:
	room_number = number
	room_id = "F%02d-R%03d" % [floor, number]


## 房间类型名称
static func get_type_name(t: RoomType) -> String:
	match t:
		RoomType.PLAYER_SPAWN:
			return "玩家出生"
		RoomType.COMBAT:
			return "普通战斗"
		RoomType.ELITE:
			return "精英战斗"
		RoomType.SCAVENGE:
			return "搜刮"
		RoomType.MERCHANT:
			return "商人"
		RoomType.UPGRADE:
			return "改造"
		RoomType.EVENT:
			return "事件"
		RoomType.EXTRACTION:
			return "撤离"
		RoomType.BOSS:
			return "Boss"
		RoomType.STORAGE:
			return "藏储室"
		RoomType.TRAP:
			return "陷阱"
		RoomType.BASEMENT:
			return "地下室"
		RoomType.STAIRS_DOWN:
			return "楼梯口(下)"
		RoomType.STAIRS_UP:
			return "楼梯口(上)"
		RoomType.ELEVATOR:
			return "电梯"
		_:
			return "未知"


## 层级名称
static func get_level_name(l: FloorLevel) -> String:
	match l:
		FloorLevel.SHALLOW:
			return "浅层"
		FloorLevel.MEDIUM:
			return "中层"
		FloorLevel.DEEP:
			return "深层"
		FloorLevel.ABYSS:
			return "污染层"
		_:
			return "未知"


## 垂直楼层名称
static func get_vertical_level_name(v: VerticalLevel) -> String:
	match v:
		VerticalLevel.BASEMENT:
			return "地下室"
		VerticalLevel.MAIN:
			return "主层"
		VerticalLevel.UPPER:
			return "二楼"
		_:
			return "未知"


## 是否为战斗相关房间
func is_combat() -> bool:
	return room_type in [RoomType.COMBAT, RoomType.ELITE, RoomType.BOSS]


## 是否可以搜刮
func is_scavenge() -> bool:
	return room_type in [RoomType.SCAVENGE, RoomType.MERCHANT]


## 是否可撤离
func is_extraction() -> bool:
	return room_type == RoomType.EXTRACTION


## 是否为垂直通道房间（楼梯/电梯，可前往其他垂直楼层）
func is_vertical_access() -> bool:
	return room_type in [RoomType.STAIRS_UP, RoomType.STAIRS_DOWN, RoomType.ELEVATOR]


## 获取完整显示名称（包含垂直楼层）
func get_display_name() -> String:
	var base_name := get_type_name(room_type)
	if vertical_level != VerticalLevel.MAIN:
		var vname := get_vertical_level_name(vertical_level)
		return "%s[%s]" % [base_name, vname]
	return base_name


## 是否为垂直关卡关联房间（与当前房间相连的不同垂直楼层房间）
func is_basement() -> bool:
	return room_type == RoomType.BASEMENT or vertical_level == VerticalLevel.BASEMENT


## 添加标签
func add_tag(tag: String) -> void:
	if not tag in tags:
		tags.append(tag)


## 是否有特定标签
func has_tag(tag: String) -> bool:
	return tag in tags


## 设置由 ContentInjector 生成的房间内容配置
func set_content_config(config: Dictionary) -> void:
	content_config = {
		"enemies": _duplicate_dictionary_array(config.get("enemies", [])),
		"loot": _duplicate_dictionary_array(config.get("loot", [])),
		"events": _duplicate_dictionary_array(config.get("events", [])),
		"interactables": _duplicate_dictionary_array(config.get("interactables", [])),
		"special_conditions": config.get("special_conditions", []).duplicate(),
	}


func get_content_config() -> Dictionary:
	return {
		"enemies": _duplicate_dictionary_array(content_config.get("enemies", [])),
		"loot": _duplicate_dictionary_array(content_config.get("loot", [])),
		"events": _duplicate_dictionary_array(content_config.get("events", [])),
		"interactables": _duplicate_dictionary_array(content_config.get("interactables", [])),
		"special_conditions": content_config.get("special_conditions", []).duplicate(),
	}


func _duplicate_dictionary_array(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in values:
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


## 房间危险等级（用于UI显示）
func danger_level() -> int:
	match room_type:
		RoomType.BOSS:
			return 5
		RoomType.ELITE:
			return 4
		RoomType.COMBAT:
			return 1 + floor
		RoomType.EVENT:
			return 3
		_:
			return 0


## 奖励等级
func reward_level() -> int:
	match room_type:
		RoomType.BOSS:
			return 5
		RoomType.ELITE:
			return 4
		RoomType.SCAVENGE:
			return 3
		RoomType.MERCHANT:
			return 3
		RoomType.UPGRADE:
			return 2
		RoomType.COMBAT:
			return 1 + floor
		RoomType.EVENT:
			return 2
		_:
			return 0


func _to_string() -> String:
	return "[RoomData %s %s fl=%d]" % [get_type_name(room_type), room_id, floor_level]
