@tool
extends RefCounted
## Select authored wall-bay variants from actual ports, before their nodes enter the tree.
## The scene owns all furniture transforms and navigation cells. This only selects openings.


static func configure(root: Node3D, ports: Array, dimensions: Vector2) -> void:
	var bays := root.get_node_or_null("ArtComponents/PerimeterBays")
	if bays == null:
		return
	var opened := {}
	var approaches: Array[Rect2] = []
	var links := root.get_meta("perimeter_entry_links_m") as Dictionary
	var depth := float(root.get_meta("perimeter_band_depth_m"))
	for value in ports:
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		var lane := float(port.get("lane_m", 0.0))
		var targets := links.get(side, []) as Array
		if targets.is_empty():
			continue
		var target := float(targets[0])
		for candidate in targets:
			if absf(float(candidate) - lane) < absf(target - lane):
				target = float(candidate)
		var low := minf(lane, target) - 2.5
		var high := maxf(lane, target) + 2.5
		match side:
			"north": approaches.append(Rect2(low, -dimensions.y * .5, high-low, depth))
			"south": approaches.append(Rect2(low, dimensions.y * .5-depth, high-low, depth))
			"west": approaches.append(Rect2(-dimensions.x * .5, low, depth, high-low))
			"east": approaches.append(Rect2(dimensions.x * .5-depth, low, depth, high-low))
	for bay in bays.get_children():
		var values := bay.get_meta("perimeter_bay_rect_m", []) as Array
		if values.size() != 4:
			continue
		var rect := Rect2(float(values[0]), float(values[1]), float(values[2]) - float(values[0]), float(values[3]) - float(values[1]))
		for approach in approaches:
			if rect.intersects(approach):
				opened[str(bay.name)] = true
				break
	for bay in bays.get_children():
		if opened.has(str(bay.name)):
			bay.free()
		else:
			for fixture in bay.get_children():
				if fixture.has_meta("perimeter_return_neighbor") and not opened.has(str(fixture.get_meta("perimeter_return_neighbor"))):
					fixture.free()
	var polygons := []
	var axes := root.get_meta("furnishing_navigation_axes") as Array
	for cell in root.get_meta("furnishing_navigation_cells", []):
		var available := true
		for blocker in cell[2]:
			if not opened.has(str(blocker)):
				available = false
				break
		if available:
			var xa := float(axes[0][int(cell[0])])
			var xb := float(axes[0][int(cell[0]) + 1])
			var za := float(axes[1][int(cell[1])])
			var zb := float(axes[1][int(cell[1]) + 1])
			polygons.append([[xa, .08, za], [xb, .08, za], [xb, .08, zb], [xa, .08, zb]])
	root.set_meta("furnishing_navigation_polygons", polygons)
	root.set_meta("perimeter_opened_bays", opened.keys())
	root.remove_meta("furnishing_navigation_cells")
	root.remove_meta("furnishing_navigation_axes")
