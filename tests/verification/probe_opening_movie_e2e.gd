extends Node
## 一次性探针：真实窗口下跑**完整新档入口链** —— StartupLoadingScreen → 开场影片
## → 98F 主人办公室，逐阶段截图。用来证明"分流真的接上了"，而不只是"各部件各自能跑"。
##
## 手法：把截图器挂到 `SceneTree.root` 下（而不是当前场景），这样
## `change_scene_to_packed()` 换掉当前场景时截图器能活下来。用完即弃。

const STARTUP_SCENE := "res://scenes/StartupLoadingScreen.tscn"


func _ready() -> void:
	print("E2E_START")
	# `_ready()` 期间父节点正在建立子节点，直接 add_child 会被拒（实测报
	# "Parent node is busy setting up children"），必须走 deferred。
	var surface := Node.new()
	surface.name = "E2ECapture"
	surface.set_script(load("res://tests/verification/_e2e_capture.gd"))
	get_parent().add_child.call_deferred(surface)
	call_deferred("_boot")


func _boot() -> void:
	var scene := load(STARTUP_SCENE) as PackedScene
	var error := get_tree().change_scene_to_packed(scene)
	print("E2E_BOOT ", error_string(error))
