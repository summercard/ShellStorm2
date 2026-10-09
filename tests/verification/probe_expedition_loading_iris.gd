extends Node
## 单跑探针：远征读条（黑白兔子版）+ 全局光圈过场 autoload 的结构与语法闸门。
## 只读断言：不写存档、不切场景、不把读取界面入树运行。
## 运行：GODOT --headless --path . --scene res://tests/verification/probe_expedition_loading_iris.tscn

const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const IRIS_SCRIPT := "res://src/ui/IrisTransition.gd"
const CITY_MENU_SCRIPT := "res://scenes/RogueMapSelectMenu.gd"
const REQUIRED_NODES: Array[String] = [
	"Root",
	"Root/Center",
	"Root/Center/Breadcrumb",
	"Root/Center/Title",
	"Root/Center/Progress",
	"Root/Center/Step",
	"Root/Content",
	"Root/Content/LoadingBar",
	"Root/Content/WaveLoading",
]

var _failures: Array[String] = []


func _ready() -> void:
	_check_autoload()
	_check_scripts()
	_check_loading_screen()
	_finish()


func _check_autoload() -> void:
	var iris := get_node_or_null("/root/IrisTransition")
	if iris == null:
		_failures.append("IrisTransition autoload 未注册")
		return
	for method in ["iris_close", "iris_open", "cover_now", "clear_now", "open_after_scene"]:
		if not iris.has_method(method):
			_failures.append("IrisTransition 缺少方法：%s" % method)


func _check_scripts() -> void:
	for path in [IRIS_SCRIPT, CITY_MENU_SCRIPT, "res://scenes/ExpeditionLoadingScreen.gd"]:
		if load(path) == null:
			_failures.append("脚本加载失败：%s" % path)


func _check_loading_screen() -> void:
	if not ResourceLoader.exists(LOADING_SCENE, "PackedScene"):
		_failures.append("读取界面场景不存在：%s" % LOADING_SCENE)
		return
	var packed := load(LOADING_SCENE) as PackedScene
	var screen := packed.instantiate() as CanvasLayer
	if screen == null:
		_failures.append("ExpeditionLoadingScreen 实例化失败")
		return
	# 刻意不入树：与既有验收同一调用方式，验证 _build_ui 在脱离场景树时也安全。
	screen.call("_build_ui")
	for path in REQUIRED_NODES:
		if screen.get_node_or_null(path) == null:
			_failures.append("读取界面缺少节点：%s" % path)
	var title := screen.get_node_or_null("Root/Center/Title") as Label
	if title == null or title.text.is_empty():
		_failures.append("读取界面标题为空")
	var progress := screen.get_node_or_null("Root/Center/Progress") as ProgressBar
	if progress == null or progress.max_value <= 0.0:
		_failures.append("读取界面进度条 max_value 非正")
	screen.free()


func _finish() -> void:
	if _failures.is_empty():
		print("PROBE_OK expedition_loading_iris")
	else:
		for failure in _failures:
			printerr("PROBE_FAIL " + failure)
		print("PROBE_FAILED %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
