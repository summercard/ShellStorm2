class_name VerificationOutput
extends RefCounted
## 所有视觉验证只写入可丢弃输出目录，禁止覆盖正式美术资产。

const ROOT := "res://outputs/verification"


static func prepare() -> void:
	var absolute_path := ProjectSettings.globalize_path(ROOT)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("[VerificationOutput] Cannot create output directory: %s" % absolute_path)


static func path(file_name: String) -> String:
	prepare()
	return ROOT.path_join(file_name)
