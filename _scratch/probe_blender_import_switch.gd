## 只读探针：把 project.godot 里 Blender 导入相关的设置真值打出来。
## 用来证明「开关在运行时确实被读到 false」，而不是只在文件里写了字样。
extends SceneTree

const KEYS := [
	"filesystem/import/blender/enabled",
	"filesystem/import/blender/blender_path",
	"filesystem/import/blender/blender3_path",
	"filesystem/import/fbx2gltf/enabled",
]

func _init() -> void:
	print("PROBE_BEGIN")
	for key in KEYS:
		var has := ProjectSettings.has_setting(key)
		var value: Variant = ProjectSettings.get_setting(key) if has else "<absent>"
		print("  %-46s has=%s value=%s" % [key, str(has), str(value)])
	# 统计项目里可见的 .blend 资源数量：若导入器被关，扫描结果里不应出现任何 .blend
	var blend_seen := 0
	var blend_as_resource := 0
	var stack: Array[String] = ["res://assets"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				stack.append(full)
			elif entry.to_lower().ends_with(".blend"):
				blend_seen += 1
				if ResourceLoader.exists(full):
					blend_as_resource += 1
			entry = dir.get_next()
		dir.list_dir_end()
	print("  blend_files_on_disk_under_assets=%d" % blend_seen)
	print("  blend_files_recognized_as_resource=%d" % blend_as_resource)
	print("PROBE_END")
	quit()
