class_name LevelSelectData
extends Node

## 关卡选择状态 — 跨场景传递用户选择的初始楼层
## LevelSelectData Autoload 实例使用本脚本

var selection_made: bool = false
var selected_floor: int = 1
var selected_seed: int = -1
var return_entrance_id: String = ""

func reset() -> void:
	selection_made = false
	selected_floor = 1
	selected_seed = -1
	return_entrance_id = ""


func prepare_dungeon_entry(floor: int, entrance_id: String, seed: int = -1) -> void:
	selection_made = true
	selected_floor = floor
	selected_seed = seed
	return_entrance_id = entrance_id
