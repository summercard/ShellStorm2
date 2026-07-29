class_name TowerGeometry3D
extends RefCounted
## 塔楼模块统一使用米制。门、楼道、平台和楼梯只能从这里读取净宽与位移，
## 避免局部函数各用一套数字造成接缝、重叠或不可通行。

const DOOR_CLEAR_WIDTH_M := 4.0
const PASSAGE_WIDTH_M := 4.0
const APPROACH_OUTSET_M := 3.0
const RUN_LENGTH_M := 10.0
const LANE_GAP_M := 1.2
const LANE_CENTER_SPACING_M := PASSAGE_WIDTH_M + LANE_GAP_M
const GUARD_HEIGHT_M := 0.9
const GUARD_END_CLEARANCE_M := PASSAGE_WIDTH_M * 0.6
const FLOOR_THICKNESS_M := 0.24
const FLOOR_HEIGHT_M := 6.0
