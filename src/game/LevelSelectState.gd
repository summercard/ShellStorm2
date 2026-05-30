class_name LevelSelectData
extends Node

## 关卡选择状态 — 跨场景传递用户选择的初始楼层
## LevelSelectData Autoload 实例使用本脚本

var selection_made: bool = false
var selected_floor: int = 1
var selected_seed: int = -1

func reset() -> void:
	selection_made = false
	selected_floor = 1
	selected_seed = -1