extends SceneTree
## One-time migration input. Subsequent authoring is performed in the animation Blend.

class PreviewContext extends Node:
	var state := "idle"
	var velocity := Vector3.ZERO
	var progress := 0.0
	func get_presentation_state() -> String: return state
	func get_reload_snapshot() -> Dictionary: return {}
	func get_action_snapshot() -> Dictionary: return {}
	func get_dash_duration() -> float: return 0.204
	func get_hurt_recovery_duration() -> float: return 0.30
	func get_landing_duration() -> float: return 0.22
	func get_fall_speed_ratio() -> float: return 0.6
	func get_death_animation_progress() -> float: return progress
	func is_low_health() -> bool: return false

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var definitions := {"idle": 4.76190476, "moving": TAU / 11.2, "dashing": 0.2652, "hurt": 0.3, "locked": 1.25, "falling": 1.0, "landing": 0.22, "dead": 1.0}
	var result := {"fps": 60, "clips": {}, "rest": {}}
	for state in definitions:
		var avatar: Node3D = load("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v008.tscn").instantiate()
		root.add_child(avatar)
		avatar.set_process(false)
		var context := PreviewContext.new()
		root.add_child(context)
		context.state = state
		context.velocity = Vector3(0, 0, -7) if state == "moving" else Vector3.ZERO
		avatar.set("_player", context)
		var nodes := {"root": avatar.visual_root, "body": avatar.body, "head": avatar.head, "hand_l": avatar.bunny_hand_l, "hand_r": avatar.bunny_hand_r, "feet": avatar.feet, "foot_l": avatar.foot_l, "foot_r": avatar.foot_r, "ear_l": avatar.ear_socket_l, "ear_r": avatar.ear_socket_r}
		var clip := {"duration": definitions[state], "loop": state in ["idle", "moving", "locked"], "frames": []}
		var count := int(ceil(float(definitions[state]) * 60))
		for index in range(count + 1):
			context.progress = float(index) / count
			if index > 0:
				avatar.set("_elapsed", float(index) * float(definitions[state]) / count)
				avatar.call("_read_player_state")
				avatar.call("_update_state_motion", float(definitions[state]) / count)
			var frame := {}
			for bone in nodes:
				var node: Node3D = nodes[bone]
				frame[bone] = {"p": [node.position.x, node.position.y, node.position.z], "q": [node.quaternion.x, node.quaternion.y, node.quaternion.z, node.quaternion.w], "s": [node.scale.x, node.scale.y, node.scale.z]}
			clip.frames.append(frame)
			if index == 0: result.rest = frame
		result.clips[state] = clip
		avatar.free()
		context.free()
	var path := "res://outputs/character_pipeline/legacy_motion_capture.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	print("CHARACTER_MOTION_CAPTURE_OK ", path)
	quit()
