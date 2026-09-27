extends Node

func _ready() -> void:
	print("INVOKE_OK argv=" + str(OS.get_cmdline_args()))
	get_tree().quit(0)
	return
