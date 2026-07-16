class_name VerificationClock
extends RefCounted
## Node-owned test delay; unlike SceneTreeTimer it is destroyed with the verifier.


static func wait(host: Node, seconds: float) -> void:
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(0.001, seconds)
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(timer)
	timer.start()
	await timer.timeout
	if is_instance_valid(timer):
		timer.queue_free()
	await host.get_tree().process_frame
