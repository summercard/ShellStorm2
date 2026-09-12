extends Node


func _ready() -> void:
	var expected_name := OS.get_environment("SHELLSTORM_VERIFICATION_USER_DIR_NAME")
	var actual_dir := OS.get_user_data_dir()
	var failures: Array[String] = []
	if expected_name.is_empty():
		failures.append("统一验收runner没有声明隔离用户目录")
	elif not actual_dir.ends_with("/" + expected_name):
		failures.append("Autoload使用的user://不是runner隔离目录：%s" % actual_dir)
	if actual_dir.ends_with("/弹壳风暴2"):
		failures.append("验收仍指向正式玩家数据目录")
	if failures.is_empty():
		print("VERIFICATION_RUNNER_CONTRACT_OK: preflight and autoload use isolated user data")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
