extends Node
## 临时探针：窗口模式跑主场景，等主入口页 present 后截图存证。

const MAIN_SCENE := "res://scenes/TowerDescent3D.tscn"
const WAIT_S := 5.0
const TIMEOUT_S := 25.0

var _elapsed := 0.0
var _captured := false
var _main: Node = null


func _ready() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	if _captured:
		return
	_elapsed += delta
	if _elapsed < WAIT_S:
		return
	var entry := _main.get_node_or_null("MainEntryScreen3D")
	if entry != null and entry.has_method("get_entry_snapshot"):
		print("PROBE_ENTRY_SNAPSHOT=", JSON.stringify(entry.get_entry_snapshot()))
	else:
		print("PROBE_ENTRY_SNAPSHOT= entry_screen_null")
	_captured = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_scratch/probe_main_entry_screen.png")
	print("PROBE_MAIN_ENTRY_OK size=", img.get_size())
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
