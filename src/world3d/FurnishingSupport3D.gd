extends RefCounted
## Detect actual tabletop support in the authored layout, independently of node names.

static func bind_layout(root: Node3D) -> void:
	var props: Array[ReactiveProp3D] = []
	for node in root.find_children("*", "", true, false):
		if node is ReactiveProp3D:
			props.append(node)
	for prop in props:
		prop.supported_items.clear()
		prop.supporting_furniture = null
		prop.attached_lights.clear()
	for item in props:
		if item.prop_kind in ["furniture", "bookcase"]:
			continue
		var best: ReactiveProp3D
		var best_gap := INF
		for support in props:
			if support.prop_kind not in ["furniture", "bookcase"] or support == item:
				continue
			var point := support.to_local(item.global_position)
			var box := support._box
			var gap := absf((support.to_global(Vector3(point.x, box.end.y, point.z))).y - item.global_position.y)
			if point.x < box.position.x - 0.12 or point.x > box.end.x + 0.12 or point.z < box.position.z - 0.12 or point.z > box.end.z + 0.12:
				continue
			if gap < 0.22 and gap < best_gap:
				best = support
				best_gap = gap
		if best != null:
			best.supported_items.append(item)
			item.supporting_furniture = best
		# Some layouts keep a table lamp's real light as a sibling, not a child.
		if item.get_meta("component_family", "") not in ["lamp", "candelabra"]:
			continue
		for node in root.find_children("*", "Light3D", true, false):
			var light := node as Light3D
			var offset := light.global_position - item.global_position
			if Vector2(offset.x, offset.z).length() < 0.16 and offset.y >= -0.05 and offset.y < item._box.size.y * item.global_basis.y.length() + 0.4:
				item.attached_lights.append(light)
				if item is ReactiveLamp3D:
					light.light_color = ReactiveLamp3D.WARM_LIGHT
				light.set_meta("reactive_light_owner", item)
