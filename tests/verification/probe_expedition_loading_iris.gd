extends Node
## 单跑探针：远征读条（黑白兔子版）+ 全局光圈过场 autoload 的结构与语法闸门。
## 只读断言：不写存档、不切场景、不把读取界面入树运行。
## 运行：GODOT --headless --path . --scene res://tests/verification/probe_expedition_loading_iris.tscn

const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const IRIS_SCRIPT := "res://src/ui/IrisTransition.gd"
const CITY_MENU_SCRIPT := "res://scenes/RogueMapSelectMenu.gd"
## 用 preload 引用读取页脚本（而不是裸类名）：裸类名依赖 `.godot` 全局类缓存，
## 纯命令行下刚改过脚本时可能解析不到，而这组断言正是给"刚改过"准备的。
const LOADING_SCRIPT := preload("res://scenes/ExpeditionLoadingScreen.gd")
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
	_check_light_colors()
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


## 逐关灯色：01 灰蓝 / 02 淡黄 / 03 玫红，未登记关卡回到金色兜底。
## 断言的是**色相关系**（谁最高、谁最低、三关互不相同），不是抄一份 RGB 数值 ——
## 抄数字的门禁只会在"有人调了色"时无条件变红，反而逼人改测试；这里守的是设计意图：
## 三关必须一眼可区分、每关落在自己的色相家族里、99 与基地不许借用任何一关的颜色。
func _check_light_colors() -> void:
	var c01: Color = LOADING_SCRIPT.light_color_for_level("expedition_01")
	var c02: Color = LOADING_SCRIPT.light_color_for_level("expedition_02")
	var c03: Color = LOADING_SCRIPT.light_color_for_level("expedition_03")
	var fallback: Color = LOADING_SCRIPT.light_color_for_level("99")
	if c01.is_equal_approx(c02) or c02.is_equal_approx(c03) or c01.is_equal_approx(c03):
		_failures.append("逐关灯色存在重复：01=%s 02=%s 03=%s" % [c01, c02, c03])
	if not (c01.b > c01.r and c01.b >= c01.g):
		_failures.append("01 灯色不是冷灰蓝（蓝应为最高通道）：%s" % str(c01))
	if not (c02.r > c02.b and c02.g > c02.b and absf(c02.r - c02.g) < 0.1):
		_failures.append("02 灯色不是淡黄（R≈G 且都高于 B）：%s" % str(c02))
	if not (c03.r > c03.b and c03.b > c03.g):
		_failures.append("03 灯色不是玫红（R > B > G）：%s" % str(c03))
	if not fallback.is_equal_approx(LOADING_SCRIPT.light_color_for_level("")):
		_failures.append("未登记关卡的兜底灯色不一致：99=%s 空串=%s" % [
			str(fallback), str(LOADING_SCRIPT.light_color_for_level(""))])
	for known in [c01, c02, c03]:
		if fallback.is_equal_approx(known):
			_failures.append("兜底灯色与某一关相同，等于该关没有自己的颜色：%s" % str(fallback))


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
