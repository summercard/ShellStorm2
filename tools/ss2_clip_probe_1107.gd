extends SceneTree
var _done := false
func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== CLIP PROBE START ===")
	var ps = load("res://assets/art/characters/player/external/maid01/maid_char.glb")
	if ps == null:
		print("PROBE_ERR glb_load_fail")
		return true
	var n = ps.instantiate()
	get_root().add_child(n)
	var ap = _find_anim(n)
	if ap == null:
		print("PROBE_ERR no_animation_player")
	else:
		var names = ap.get_animation_list()
		print("PROBE_COUNT " + str(names.size()))
		for i in range(names.size()):
			var a = ap.get_animation(names[i])
			print("ANIM|" + str(names[i]) + "|len=" + str(a.length) + "|loop=" + str(a.loop_mode))
	print("=== CLIP PROBE END ===")
	return true
func _find_anim(n):
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r = _find_anim(c)
		if r != null:
			return r
	return null
