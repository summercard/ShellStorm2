extends Node
## 远征关卡02 关卡与房间场景加载验证（纯只读）。
##
## 跑法（**以场景方式跑**，autoload 才可用）：
##   godot --headless --path "<项目根>" res://scripts/verify_expedition02_scene.tscn
##
## 验证：
##   ① `GameDesignConfig` 里 expedition_02 已登记且 `scene_3d` 资源真实存在
##   ② 关卡场景可加载、可实例化，且 `expedition_run_id` 指向本关
##   ③ 26 个房间静态布局场景**逐个**可加载、可实例化、根节点 metadata 完整
##   ④ 每个房间的实例总数与 metadata 声明一致（防生成器与文件脱节）

const LEVEL_ID := "expedition_02"
const ROOM_ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_02"
const EXPECTED_ROOM_COUNT := 26
## 不封顶的房间（按**运行时房间 ID**）：入口安全屋（业主要求不封）+ 挑高前厅（通高空间）。
## 入口房的运行时 ID 是 `start`（远征硬契约），不是设计 key `entry`。
const NO_CEILING := ["start", "room_01"]

var failures: Array[String] = []


## 房间清单**从目录扫**，不手写。
## 手写清单踩过坑：入口房改名 `f00_entry` → `f00_start` 之后，清单仍指向旧名，
## 探针只是"少了一间"，看起来像数字不对，而实机上就是那一间没有美术。
func _room_runtime_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(ROOM_ROOT)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if (
			not dir.current_is_dir()
			and entry_name.begins_with("f00_")
			and entry_name.ends_with("_static_layout.tscn")
		):
			ids.append(entry_name.trim_prefix("f00_").trim_suffix("_static_layout.tscn"))
		entry_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


func _ready() -> void:
	# ---- ① 关卡登记 ----
	# 项目把「从 Variant 推断类型」当错误（warning treated as error）⇒ 必须显式标注。
	var entry: Dictionary = GameDesignConfig.expedition_level(LEVEL_ID)
	if entry.is_empty():
		_fail("GameDesignConfig 未登记 %s" % LEVEL_ID)
	else:
		var scene_path := str(entry.get("scene_3d", ""))
		print("登记: %s / %s / %s" % [
			entry.get("display_name", ""), entry.get("setting_name", ""), scene_path])
		if not ResourceLoader.exists(scene_path):
			_fail("scene_3d 不存在: %s" % scene_path)
	print("远征关卡清单: %s" % str(GameDesignConfig.expedition_level_ids()))
	print("默认关卡: %s" % GameDesignConfig.default_expedition_level_id())

	# ---- ② 关卡场景 ----
	# ⚠️ **既不能实例化、也不 load 它**：该场景 `preload` 了整套地牢美术与主题资源，
	# 在 headless 下加载会长时间不返回（第一次挂死 5 分钟就是这么来的），
	# 而实例化还会启动远征引导流程（加载屏 + 逐帧等待），永远跑不完。
	# 所以这里只校验「资源存在」+「文本里声明的 run_id / expedition_mode 正确」。
	var scene_path := str(entry.get("scene_3d", ""))
	if not ResourceLoader.exists(scene_path):
		_fail("关卡场景不存在: %s" % scene_path)
	else:
		var text := FileAccess.get_file_as_string(scene_path)
		if text.is_empty():
			_fail("关卡场景读取为空: %s" % scene_path)
		else:
			if 'expedition_run_id = "%s"' % LEVEL_ID not in text:
				_fail("关卡场景未声明 expedition_run_id = \"%s\"" % LEVEL_ID)
			if "expedition_mode = true" not in text:
				_fail("关卡场景未声明 expedition_mode = true")
			print("关卡场景 OK: %s（存在 + 声明正确；未加载/未实例化）" % scene_path)

	# ---- ③④ 房间场景（清单扫目录得到）----
	var room_ids := _room_runtime_ids()
	if room_ids.size() != EXPECTED_ROOM_COUNT:
		_fail("房间场景数 %d，期望 %d（清单 %s）"
			% [room_ids.size(), EXPECTED_ROOM_COUNT, str(room_ids)])
	if not "start" in room_ids:
		_fail("扫不到 f00_start_static_layout.tscn —— 入口房必须用运行时 ID `start`（出生点按它取房）")
	var total_instances := 0
	var ceiling_rooms: Array[String] = []
	for key in room_ids:
		var path := "%s/f00_%s_static_layout.tscn" % [ROOM_ROOT, key]
		if not ResourceLoader.exists(path):
			_fail("房间场景不存在: %s" % path)
			continue
		var room_packed := load(path) as PackedScene
		if room_packed == null:
			_fail("房间场景加载失败: %s" % key)
			continue
		var room := room_packed.instantiate()
		if room == null:
			_fail("房间场景实例化失败: %s" % key)
			continue
		var declared := int(room.get_meta("layout_instance_total", -1))
		var child_count := room.get_child_count()
		if declared != child_count:
			_fail("%s: metadata 声明 %d 个实例，实际子节点 %d" % [key, declared, child_count])
		var ceiling: Variant = null
		if room.has_meta("ceiling_bottom_y_m"):
			ceiling = room.get_meta("ceiling_bottom_y_m")
		if ceiling != null:
			ceiling_rooms.append(key)
			if absf(float(ceiling) - 4.0) > 0.001:
				_fail("%s: 封顶底面 y=%s，应为 4.0" % [key, str(ceiling)])
		total_instances += child_count
		room.free()

	# 封顶覆盖：除入口安全屋与挑高前厅外，其余 24 间都必须有封顶
	for key in room_ids:
		var should_have := not key in NO_CEILING
		var has := key in ceiling_rooms
		if should_have != has:
			_fail("%s: 封顶有无不符（期望 %s，实得 %s）" % [key, str(should_have), str(has)])
	print("房间场景: %d 间 / 实例合计 %d / 有封顶 %d 间" % [
		room_ids.size(), total_instances, ceiling_rooms.size()])

	_finish()


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION02_SCENE_VERIFY_OK")
		get_tree().quit(0)
		return
	print("EXPEDITION02_SCENE_VERIFY_FAILED count=%d" % failures.size())
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)
