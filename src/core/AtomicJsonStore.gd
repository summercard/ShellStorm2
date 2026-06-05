class_name AtomicJsonStore
extends RefCounted
## JSON 存储工具：临时写入、备份旧文件，再提升为主文件。

static func load_dictionary(path: String) -> Variant:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error == OK and parser.data is Dictionary:
			return parser.data
	return null

static func save_dictionary(path: String, data: Dictionary) -> bool:
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		push_error("[AtomicJsonStore] Cannot open temporary save: %s" % temp_path)
		return false
	temp_file.store_string(JSON.stringify(data, "\t"))
	temp_file.flush()
	temp_file.close()

	_remove_if_exists(backup_path)
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(_absolute(path), _absolute(backup_path))
		if backup_error != OK:
			push_error("[AtomicJsonStore] Cannot back up save: %s" % error_string(backup_error))
			_remove_if_exists(temp_path)
			return false

	var promote_error := DirAccess.rename_absolute(_absolute(temp_path), _absolute(path))
	if promote_error != OK:
		push_error("[AtomicJsonStore] Cannot promote temporary save: %s" % error_string(promote_error))
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(_absolute(backup_path), _absolute(path))
		_remove_if_exists(temp_path)
		return false

	# 保留上一版备份，便于后续发现主文件损坏时回退。
	return true

static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_absolute(path))

static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)
