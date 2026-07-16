class_name VerificationQuitter
extends Node
## Lets async verification entrypoints unwind before SceneTree shutdown.

var _exit_code := 0
var _frames_remaining := 3


static func schedule(host: Node, exit_code: int, settle_frames: int = 3) -> void:
	if host == null or not is_instance_valid(host):
		return
	var existing := host.get_node_or_null("__VerificationQuitter") as VerificationQuitter
	if existing != null:
		existing._exit_code = maxi(existing._exit_code, exit_code)
		existing._frames_remaining = maxi(existing._frames_remaining, settle_frames)
		return
	var quitter := VerificationQuitter.new()
	quitter.name = "__VerificationQuitter"
	quitter._exit_code = exit_code
	quitter._frames_remaining = maxi(1, settle_frames)
	quitter.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(quitter)


func _process(_delta: float) -> void:
	_frames_remaining -= 1
	if _frames_remaining <= 0:
		set_process(false)
		get_tree().quit(_exit_code)
