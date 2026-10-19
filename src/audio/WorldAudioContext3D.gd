class_name WorldAudioContext3D
extends RefCounted
## Read actual support/roof colliders and semantic component capabilities.
## Never infer a room from the last visited room ID or alter navigation/AI.

static func describe_support(body: Node, profiles: Dictionary) -> Dictionary:
	var result := {"surface": "concrete", "environment": "", "reverb": "dry", "room_type": ""}
	var surface_declared := false
	var node := body
	while is_instance_valid(node):
		if not surface_declared and node.has_meta("audio_surface"):
			result.surface = str(node.get_meta("audio_surface"))
			surface_declared = true
		if node.has_meta("audio_environment") and str(result.environment).is_empty():
			result.environment = str(node.get_meta("audio_environment"))
		if bool(node.get_meta("is_vertical_connector", false)) or str(node.get_meta("audio_acoustics", "")) == "stairwell":
			result.reverb = "stairwell"
			result.environment = "indoor"
		if str(node.get_meta("block_id", "")) == "stairs":
			result.reverb = "stairwell"
			result.environment = "indoor"
		if not surface_declared:
			var identity := (node.scene_file_path + " " + str(node.name) + " " + str(node.get_meta("asset_id", "")) + " " + str(node.get_meta("component_slug", ""))).to_lower()
			for rule in profiles.get("surface_rules", []):
				for token in rule.get("tokens", []):
					if str(token) in identity:
						result.surface = str(rule.surface)
						surface_declared = true
		if node.is_in_group("dungeon_room_3d"):
			var room_type := str(node.get("room_type"))
			result.room_type = room_type
			if room_type == "STAIR_LOBBY":
				result.reverb = "stairwell"
				result.environment = "indoor"
			elif str(result.environment).is_empty() and (str(node.get("size_class")) == "rooftop" or room_type == "ROOFTOP"):
				result.environment = "rooftop"
			elif str(result.environment).is_empty():
				result.environment = "indoor"
			if not surface_declared:
				result.surface = str((profiles.get("room_surfaces", {}) as Dictionary).get(room_type, "concrete"))
		if node.is_in_group("tower_floor_stage_3d") and str(result.environment).is_empty():
			if str(node.get("floor_kind")) == "rooftop":
				result.environment = "rooftop"
			else:
				result.environment = "indoor"
		node = node.get_parent()
	return result


static func resolve(actor: CharacterBody3D, profiles: Dictionary) -> Dictionary:
	var pos := actor.global_position
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.35, pos - Vector3.UP * 3.0, 1, [actor.get_rid()])
	var state := actor.get_world_3d().direct_space_state
	var hit := state.intersect_ray(query)
	if hit.is_empty():
		return {"surface": "concrete", "environment": "void", "reverb": "dry", "support_position": pos}
	var context := describe_support(hit.collider as Node, profiles)
	context.support_position = hit.position
	if str(context.reverb) == "stairwell":
		return context
	# A roof over the listener wins over an outdoor-floor declaration. This also
	# handles stair enclosures placed on a rooftop and indoor/outdoor base decks.
	var roof := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.8, pos + Vector3.UP * 16.0, 1, [actor.get_rid()])
	var roof_hit := state.intersect_ray(roof)
	if not roof_hit.is_empty():
		var ceiling := describe_support(roof_hit.collider as Node, profiles)
		context.environment = "indoor"
		if str(ceiling.reverb) == "stairwell":
			context.reverb = "stairwell"
	elif str(context.environment).is_empty():
		# Missing ceiling collision is common in cutaway rooms; silence outdoor
		# ambience unless the support explicitly declares an outdoor capability.
		context.environment = "indoor"
	return context
