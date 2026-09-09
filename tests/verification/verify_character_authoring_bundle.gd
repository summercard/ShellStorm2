extends Node

const PACKAGE := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v009/"
const OLD := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v008.tscn"

func _ready() -> void:
	var failures: Array[String] = []
	var old: Node3D = load(OLD).instantiate()
	var current: Node3D = load(PACKAGE + "runtime/chr_bunny01_root_v009.tscn").instantiate()
	add_child(old)
	add_child(current)
	old.set_process(false)
	current.set_process(false)
	var old_bounds := bounds(old)
	var new_bounds := bounds(current)
	if old_bounds.position.distance_to(new_bounds.position) > 0.002 or old_bounds.size.distance_to(new_bounds.size) > 0.002:
		failures.append("Rest silhouette changed: %s -> %s" % [old_bounds, new_bounds])
	for child in current.find_children("*", "CollisionObject3D", true, false):
		failures.append("Presentation contains physics: " + str(child.get_path()))
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE + "exports/anim_bunny01_library_v009.json"))
	for state in ["idle", "moving", "dashing", "hurt", "locked", "falling", "landing", "dead"]:
		if not library.clips.has(state): failures.append("Missing " + state)
		else:
			var clip: Dictionary = library.clips[state]
			if float(clip.duration) <= 0 or clip.frames.size() < 2: failures.append("Invalid clip " + state)
	current.set("_state", "moving")
	var driver := CharacterMotionLibrary3D.new()
	driver.bind(current)
	driver.apply(current, 0.15)
	if driver.active_clip != "moving" or absf(current.foot_l.position.y - current.foot_r.position.y) < 0.001:
		failures.append("Imported moving bones do not animate alternate feet")
	print("CHARACTER_REST_BOUNDS old=", old_bounds, " new=", new_bounds)
	old.queue_free()
	current.queue_free()
	if failures.is_empty():
		print("CHARACTER_AUTHORING_BUNDLE_OK: bounds, no physics, eight Blender clips, moving bone playback")
		get_tree().quit()
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)

func bounds(avatar: Node3D) -> AABB:
	var low := Vector3(INF,INF,INF)
	var high := Vector3(-INF,-INF,-INF)
	for node in avatar.get_node("VisualRoot/BunnyRig").find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree(): continue
		var box: AABB = node.global_transform * node.get_aabb()
		low=low.min(box.position)
		high=high.max(box.end)
	return AABB(low,high-low)
