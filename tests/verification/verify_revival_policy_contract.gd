extends Node

const POLICY_SCRIPT := preload("res://src/game/RevivalPolicy.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var policy := POLICY_SCRIPT.new()
	var context := {
		"run_id": "revival_policy_probe",
		"death_position": Vector3(2.0, 3.0, 4.0),
		"committed_safe_anchors": ["room_entry"],
	}
	var before := context.duplicate(true)
	var decision := policy.query(context) as Dictionary
	if bool(decision.get("available", true)):
		failures.append("v0.1 空策略错误宣告存在可用复活源")
	if String(decision.get("reason", "")) != "no_revival_source":
		failures.append("空策略没有返回稳定失败原因")
	if not String(decision.get("source_id", "")).is_empty() or not String(decision.get("reservation_id", "")).is_empty():
		failures.append("空策略伪造了复活源或预约")
	var reservation := policy.reserve(context) as Dictionary
	if bool(reservation.get("success", true)):
		failures.append("无复活源时 reserve 错误成功")
	if context != before:
		failures.append("复活空策略修改了输入上下文")

	if failures.is_empty():
		print("REVIVAL_POLICY_CONTRACT_OK: empty v0.1 policy is explicit, side-effect-free and keeps death settlement unchanged")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
