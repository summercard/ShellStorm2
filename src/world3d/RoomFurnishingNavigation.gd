extends RefCounted
## Rebuild the authored furnishing navigation only after a collider changes state.
## Uniform 0.5 m cells match the initial room grid and navigation-server precision.
const STEP := 0.5
const CLEARANCE := 0.6


static func rebuild(dim: Vector2, blockers: Array, ports: Array) -> Array:
	var columns := int(round(dim.x / STEP)) - 2
	var rows := int(round(dim.y / STEP)) - 2
	if columns <= 0 or rows <= 0:
		return []
	@warning_ignore("integer_division")
	if columns > 2147483647 / rows:
		return []
	var cell_count := columns * rows
	# 0：可走未访问，1：阻挡，2：已入队；无港口时也复用为 inspected。
	var cells := PackedByteArray()
	if cells.resize(cell_count) != OK:
		return []
	var origin := -dim * .5 + Vector2.ONE * STEP
	for value in blockers:
		var bounds := value as AABB
		if bounds.position.y >= 1.5 or bounds.end.y <= .05:
			continue
		var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(CLEARANCE)
		var first := Vector2i(floori((rect.position.x - origin.x) / STEP), floori((rect.position.y - origin.y) / STEP))
		var last := Vector2i(ceili((rect.end.x - origin.x) / STEP) - 1, ceili((rect.end.y - origin.y) / STEP) - 1)
		for x in range(maxi(0, first.x), mini(columns - 1, last.x) + 1):
			for z in range(maxi(0, first.y), mini(rows - 1, last.y) + 1):
				cells[x * rows + z] = 1
	var queue := PackedInt32Array()
	if queue.resize(cell_count) != OK:
		return []
	var count := 0
	for port in ports:
		var lane := float(port.get("lane_m", 0.0))
		var point := Vector2(lane, -dim.y * .5 + 1.25)
		match str(port.get("side", "")):
			"south": point = Vector2(lane, dim.y * .5 - 1.25)
			"west": point = Vector2(-dim.x * .5 + 1.25, lane)
			"east": point = Vector2(dim.x * .5 - 1.25, lane)
		var cell := Vector2i(floori((point.x - origin.x) / STEP), floori((point.y - origin.y) / STEP))
		if cell.x >= 0 and cell.x < columns and cell.y >= 0 and cell.y < rows:
			var index := cell.x * rows + cell.y
			# 重复起点的邻居会在首次出队时全部检查，省略其重复出队不改变发现顺序。
			if cells[index] == 0:
				cells[index] = 2
				queue[count] = index
				count += 1
	var reached := PackedInt32Array()
	if count > 0:
		count = _flood_packed(cells, queue, count, rows)
		reached = queue
	else:
		for index in cell_count:
			if cells[index] != 0:
				continue
			cells[index] = 2
			queue[0] = index
			var component_count := _flood_packed(cells, queue, 1, rows)
			if component_count > reached.size():
				reached = queue.slice(0, component_count)
		count = reached.size()
	var polygons := []
	for cursor in count:
		var index := reached[cursor]
		@warning_ignore("integer_division")
		var cell := Vector2i(index / rows, index % rows)
		var at: Vector2 = origin + Vector2(cell) * STEP
		polygons.append([[at.x, .08, at.y], [at.x + STEP, .08, at.y],
			[at.x + STEP, .08, at.y + STEP], [at.x, .08, at.y + STEP]])
	return polygons


static func _flood_packed(cells: PackedByteArray, queue: PackedInt32Array, count: int, rows: int) -> int:
	var cursor := 0
	while cursor < count:
		var index := queue[cursor]
		cursor += 1
		# x 优先索引；邻居访问顺序与旧 BFS 的 LEFT、RIGHT、UP、DOWN 一致。
		var neighbor := index - rows
		if neighbor >= 0 and cells[neighbor] == 0:
			cells[neighbor] = 2
			queue[count] = neighbor
			count += 1
		neighbor = index + rows
		if neighbor < cells.size() and cells[neighbor] == 0:
			cells[neighbor] = 2
			queue[count] = neighbor
			count += 1
		var z := index % rows
		neighbor = index - 1
		if z > 0 and cells[neighbor] == 0:
			cells[neighbor] = 2
			queue[count] = neighbor
			count += 1
		neighbor = index + 1
		if z + 1 < rows and cells[neighbor] == 0:
			cells[neighbor] = 2
			queue[count] = neighbor
			count += 1
	return count


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
