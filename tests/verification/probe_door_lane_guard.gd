## 临时探针：门槽 lane 归属判定（DungeonRoom3D.classify_door_lane）单元验证。
##
## 为什么需要它：这条断言按构造在**正常布局下永不触发** —— 坐在门槽 lane 上的实墙会被
## 提升成门墙（uses_door=true），所以「门槽上是实墙」只可能出现在真错位时。跑关卡永远
## 看不到它开火，只能是「跑过关卡」而不是「安全网还活着」。这里用合成台账把三态打全。
extends Node

const ROOM := preload("res://src/world3d/DungeonRoom3D.gd")
const TOL := ROOM.DOOR_LANE_GUARD_TOLERANCE_M

var _checks := 0
var _failures := 0


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL  ", label)


func _record(side: String, along: float, uses_door: bool) -> Dictionary:
	return {"side": side, "along": along, "uses_door": uses_door}


func _classify(records: Array, side: String, door_offset: float) -> String:
	return str(ROOM.classify_door_lane(records, side, door_offset))


func _ready() -> void:
	print("---- 门槽 lane 归属判定 单元探针 ----")
	print("容差 = %s m" % str(TOL))

	# ① 门槽 lane 上是门墙 ⇒ 本房承接。
	_check(
		_classify([_record("south", 2.5, true)], "south", 2.5) == "door_wall",
		"① 门槽上是门墙应判 door_wall"
	)

	# ② 门槽 lane 上是实墙 ⇒ 真「门开在实墙上」，必须开火。
	_check(
		_classify([_record("south", 2.5, false)], "south", 2.5) == "solid_wall",
		"② 门槽上是实墙应判 solid_wall（安全网）"
	)

	# ③ 远征 13 房的实际形态：该侧只有**别的 lane** 的实墙（±5m），门槽那道墙归邻房 ⇒ 委派。
	_check(
		_classify(
			[_record("south", -2.5, false), _record("south", 7.5, false)], "south", 2.5
		) == "",
		"③ 该侧只有邻 lane 实墙应判空串（委派），不得误报"
	)

	# ③b 同一侧「别的 lane 实墙 ＋ 门槽上是门墙」⇒ 仍是 door_wall（不得被邻 lane 实墙带偏）。
	_check(
		_classify(
			[_record("south", 2.5, true), _record("south", -2.5, false)], "south", 2.5
		) == "door_wall",
		"③b 门槽有门墙时邻 lane 实墙不得翻案"
	)

	# ④ 该侧一件墙都没有 ⇒ 委派。
	_check(_classify([], "south", 2.5) == "", "④ 无墙应判空串（委派）")

	# ⑤ 别的侧的墙不能参与本侧判定。
	_check(
		_classify([_record("north", 2.5, true)], "south", 2.5) == "",
		"⑤ 别的侧墙件不得算进本侧门槽"
	)

	# ⑥ 容差边界的「差一点」错位要抓得住（0.2m < 0.25m）。
	_check(
		_classify([_record("south", 2.5 - TOL * 0.8, false)], "south", 2.5) == "solid_wall",
		"⑥ 离门槽 0.8×容差的实墙应判 solid_wall（近失错位抓得住）"
	)

	# ⑦ 容差之外（1.5×容差）不得误判 —— 否则 5m lane 间距会被吃掉。
	_check(
		_classify([_record("south", 2.5 - TOL * 1.5, false)], "south", 2.5) == "",
		"⑦ 超出容差的墙不得算作占据门槽"
	)

	# ⑧ 容差必须远小于 lane 间距，否则邻 lane 墙会被误当门槽占据。
	_check(
		TOL < 2.5,
		"⑧ 容差 %s m 必须小于半个 lane 间距 2.5m" % str(TOL)
	)

	# ⑨ 台账里混入非 Dictionary 不得崩（采集端已保证是 Dictionary，这里是防御性断言）。
	_check(
		_classify([null, _record("south", 2.5, true)], "south", 2.5) == "door_wall",
		"⑨ 台账混入非法项时应跳过而非崩溃"
	)

	print("-- 断言数 = %d，失败数 = %d" % [_checks, _failures])
	if _failures == 0:
		print("DOOR_LANE_GUARD_OK checks=%d" % _checks)
	else:
		print("DOOR_LANE_GUARD_FAILED checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
