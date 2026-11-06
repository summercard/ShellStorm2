extends RefCounted
## Rebuild the authored furnishing navigation only after a collider changes state.
## Uniform 0.5 m cells match the initial room grid and navigation-server precision.
const STEP := 0.5
const CLEARANCE := 0.6


static func rebuild(dim: Vector2, blockers: Array, ports: Array) -> Array:
	var columns := int(round(dim.x / STEP)) - 2
	var rows := int(round(dim.y / STEP)) - 2
	var origin := -dim * .5 + Vector2.ONE * STEP
	var blocked := {}
	for value in blockers:
		var bounds := value as AABB
		if bounds.position.y >= 1.5 or bounds.end.y <= .05:
			continue
		var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(CLEARANCE)
		var first := Vector2i(floori((rect.position.x - origin.x) / STEP), floori((rect.position.y - origin.y) / STEP))
		var last := Vector2i(ceili((rect.end.x - origin.x) / STEP) - 1, ceili((rect.end.y - origin.y) / STEP) - 1)
		for x in range(maxi(0, first.x), mini(columns - 1, last.x) + 1):
			for z in range(maxi(0, first.y), mini(rows - 1, last.y) + 1):
				blocked[Vector2i(x, z)] = true
	var walkable := {}
	for x in columns:
		for z in rows:
			var cell := Vector2i(x, z)
			if not blocked.has(cell):
				walkable[cell] = true
	var starts: Array[Vector2i] = []
	for port in ports:
		var lane := float(port.get("lane_m", 0.0))
		var point := Vector2(lane, -dim.y * .5 + 1.25)
		match str(port.get("side", "")):
			"south": point = Vector2(lane, dim.y * .5 - 1.25)
			"west": point = Vector2(-dim.x * .5 + 1.25, lane)
			"east": point = Vector2(dim.x * .5 - 1.25, lane)
		var cell := Vector2i(floori((point.x - origin.x) / STEP), floori((point.y - origin.y) / STEP))
		if walkable.has(cell):
			starts.append(cell)
	var reached := _flood(walkable, starts)
	if reached.is_empty():
		var inspected := {}
		for cell in walkable:
			if inspected.has(cell):
				continue
			var component := _flood(walkable, [cell])
			inspected.merge(component)
			if component.size() > reached.size():
				reached = component
	var polygons := []
	for cell in reached:
		var at: Vector2 = origin + Vector2(cell) * STEP
		polygons.append([[at.x, .08, at.y], [at.x + STEP, .08, at.y],
			[at.x + STEP, .08, at.y + STEP], [at.x, .08, at.y + STEP]])
	return polygons


static func _flood(walkable: Dictionary, starts: Array) -> Dictionary:
	var reached := {}
	var queue: Array = starts.duplicate()
	for cell in starts:
		reached[cell] = true
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + delta
			if walkable.has(neighbor) and not reached.has(neighbor):
				reached[neighbor] = true
				queue.append(neighbor)
	return reached
