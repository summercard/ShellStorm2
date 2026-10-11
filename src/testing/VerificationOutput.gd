class_name VerificationOutput
extends RefCounted
## 所有视觉验证只写入可丢弃输出目录，禁止覆盖正式美术资产。

const ROOT := "../ShellStorm2-work/verification/visual"


static func root_path() -> String:
	var configured := OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	if not configured.is_empty():
		return configured
	return ProjectSettings.globalize_path("res://").path_join(ROOT).simplify_path()


static func prepare() -> void:
	var absolute_path := root_path()
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("[VerificationOutput] Cannot create output directory: %s" % absolute_path)


static func path(file_name: String) -> String:
	prepare()
	return root_path().path_join(file_name)
