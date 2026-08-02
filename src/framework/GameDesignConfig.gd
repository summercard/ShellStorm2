class_name GameDesignConfig
extends RefCounted
## 游戏设计文档 v0.1 对应的运行时公共契约。
## 这里只放跨系统稳定值；具体玩法参数仍归各自数据资源或系统所有。

const VERSION := "0.1.0"

const MAIN_SCENE := "res://scenes/TowerDescent3D.tscn"
const BASE_SCENE_3D := "res://scenes/BaseWorld3D.tscn"
const TRAINING_SCENE_3D := "res://scenes/TrainingRange3D.tscn"

const RENDER_LAYER_WORLD := 1
const RENDER_LAYER_PLAYER := 2
const LIGHT_MASK_WORLD_ONLY := RENDER_LAYER_WORLD
const LIGHT_MASK_WORLD_AND_PLAYER := RENDER_LAYER_WORLD | RENDER_LAYER_PLAYER

const ROOM_TYPES_WITH_HOSTILES: Array[String] = [
	"COMBAT",
	"ELITE",
	"BOSS",
	"TRAP",
	"BASEMENT",
	"STORAGE",
	"SCAVENGE",
]


static func scene_exists(scene_path: String) -> bool:
	return not scene_path.is_empty() and ResourceLoader.exists(scene_path, "PackedScene")
