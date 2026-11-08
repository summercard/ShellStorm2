extends SceneTree

var _inst: Node = null
var _n := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://assets/art/characters/player/external/maid01/chr_maid01_root_v001.tscn")
	if ps == null:
		print("PROBE_ERR scene_load_failed")
		quit(9)
		return
	_inst = ps.instantiate()
	root.add_child(_inst)

func _find_lib(n: Node) -> Node:
	if n.has_method("clip_wants_loop"):
		return n
	for c in n.get_children():
		var r: Node = _find_lib(c)
		if r != null:
			return r
	return null

func _process(_d: float) -> bool:
	_n += 1
	if _n < 15:
		return false
	var lib: Node = _find_lib(_inst)
	var ap: AnimationPlayer = null
	if _inst != null:
		ap = _inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("PROBE lib_found=", lib != null, " ap_found=", ap != null)
	if lib != null:
		print("PROBE loop_source=", lib.loop_source, " applied=", lib.loop_flags_applied, " total=", lib.loop_flags_total)
	if ap != null:
		print("PROBE current=", ap.current_animation, " playing=", ap.is_playing())
		for nm in ["idle", "walking", "armed_idle", "armed_walking", "longgun_idle", "longgun_walking_forward"]:
			if ap.has_animation(nm):
				var a: Animation = ap.get_animation(nm)
				var wants := false
				if lib != null:
					wants = lib.clip_wants_loop(nm)
				print("CLIP ", nm, " loop_mode=", a.loop_mode, " length=", a.length, " wants=", wants)
			else:
				print("CLIP ", nm, " MISSING")
	print("PROBE_DONE")
	quit(0)
	return true
