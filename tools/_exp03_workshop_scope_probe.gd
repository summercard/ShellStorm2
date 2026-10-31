extends Node
## 工坊可编辑范围体检：逐个公馆组件回答「它会不会被运行时删掉重建」。
##
## 判据与 `DungeonRoom3D._rebuild_manor_shell()` 完全一致：
##   `ART_SOURCE.is_art_layer_structure(prefab)` 为真 ⇒ 会被删掉重铺
##   ⇒ **工坊里移动它不生效**（下次加载按本局门位重算）。
##
## 业主会问「哪些能拖、哪些不能」，这张表就是答案。只读。

const ART_SOURCE := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const MANOR_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

var _frozen: Array[String] = []
var _free: Array[String] = []
var _other: Array[String] = []


func _ready() -> void:
	var da := DirAccess.open(MANOR_DIR)
	if da == null:
		push_error("打不开组件目录 %s" % MANOR_DIR)
		get_tree().quit(1)
		return
	var dirs: Array[String] = []
	da.list_dir_begin()
	var entry := da.get_next()
	while not entry.is_empty():
		if da.current_is_dir() and not entry.begins_with("."):
			dirs.append(entry)
		entry = da.get_next()
	da.list_dir_end()
	dirs.sort()
	print("SCOPE 目录 %d 个，逐个判定：")
	print("SCOPE %-34s %-12s %-9s %s" % ["组件 slug", "structure", "运行时", "工坊里能拖动吗"])
	for dir_name in dirs:
		var prefab := _find_prefab(MANOR_DIR.path_join(dir_name))
		if prefab.is_empty():
			continue
		var slug := ART_SOURCE.prefab_slug(prefab)
		var tag := ART_SOURCE.structure_tag(prefab)
		var keep := ART_SOURCE.is_art_layer_structure(prefab)
		var verdict := ""
		var fate := ""
		if keep:
			fate = "冻结重铺"
			verdict = "✗ 移动/旋转不生效"
			_frozen.append(dir_name)
		elif tag.is_empty():
			fate = "保留"
			verdict = "✓ 自由"
			_free.append(dir_name)
		else:
			# 结构件族、但不在 `ART_LAYER_STRUCTURE_ALLOWLIST` 放行名单里 ⇒ 加载时被剥离。
			fate = "剥离"
			verdict = "✗ 会被删掉（不是公馆美术）"
			_other.append(dir_name)
		print("SCOPE %-34s %-12s %-9s %s"
			% [dir_name, ("-" if tag.is_empty() else tag), fate, verdict])
	print("SCOPE_SUMMARY 冻结=%d 自由=%d 异常=%d"
		% [_frozen.size(), _free.size(), _other.size()])
	_frozen.sort()
	_free.sort()
	print("SCOPE_FROZEN %s" % ", ".join(_frozen))
	print("SCOPE_FREE %s" % ", ".join(_free))
	if not _other.is_empty():
		print("SCOPE_OTHER %s" % ", ".join(_other))
	get_tree().quit(0)


func _find_prefab(dir: String) -> String:
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	da.list_dir_begin()
	var name := da.get_next()
	var found := ""
	while not name.is_empty():
		# 包装场景固定叫 `<slug>_root_top3d.tscn`，跳过内嵌的 `_visual_` GLB 包装。
		if name.ends_with("_root_top3d.tscn"):
			found = dir.path_join(name)
			break
		name = da.get_next()
	da.list_dir_end()
	return found
