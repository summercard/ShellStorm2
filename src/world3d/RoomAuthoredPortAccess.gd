extends RefCounted
## Only explicitly authored edge variants can give way to a real door.
## Existing furnishings and all interior partitions remain where the author put them.

static func configure(root: Node3D, ports: Array, dimensions: Vector2) -> void:
	var approaches := preload("res://src/world3d/ManorFurnishing.gd")._door_boxes(ports, dimensions.x * .5, dimensions.y * .5)
	var contract := preload("res://src/world3d/RoomArtLayoutContract.gd")
	var removed := []
	for node in root.find_children("*", "Node3D", true, false):
		if not is_instance_valid(node):
			continue
		if not bool(node.get_meta("port_clearance_candidate", false)):
			continue
		var size: Vector3 = node.get_meta("bounds_size_m", Vector3.ZERO)
		var tf: Transform3D = contract.local_transform(root, node)
		# A candidate on a side partition opens the complete lateral approach,
		# including the run from the outer wall to the central passage.
		var side := str(node.get_meta("port_access_side", ""))
		var lane := float(node.get_meta("port_access_lane_m", 0.0))
		var opens := false
		var rules: Array = node.get_meta("port_access_rules", [])
		if not rules.is_empty():
			for rule in rules:
				for port in ports:
					if str(port.get("side", "")) == str(rule.get("side", "")) and absf(float(port.get("lane_m", 0.0)) - float(rule.get("lane_m", 0.0))) < float(rule.get("half_span_m", 1.9)):
						opens = true
		elif not side.is_empty():
			for port in ports:
				if str(port.get("side", "")) == side and absf(float(port.get("lane_m", 0.0)) - lane) < float(node.get_meta("port_access_half_span_m", 1.9)):
					opens = true
		else:
			var points: PackedVector2Array = contract.footprint(tf, size)
			for box in approaches:
				if contract.overlaps_box(points, box):
					opens = true
		if opens:
			removed.append(str(root.get_path_to(node)))
			node.free()
	root.set_meta("authored_port_clearance_removed", removed)
