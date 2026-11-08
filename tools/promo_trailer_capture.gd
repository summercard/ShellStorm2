extends Node3D
## Actual gameplay recorder. The director only sends ordinary input events.
## No staged actors, camera overrides, teleports, forced doors or direct damage.
## Launch in an isolated APPDATA/LOCALAPPDATA directory containing gameplay_trailer.

var tower: TowerDescent3D
var actor: Player3D
var frame := 0
var mode := "boot"
var move_goal := Vector3.ZERO
var walking := false
var fighting := false
var held: Dictionary = {}
var events: Array[Dictionary] = []
var output_dir := ""
var last_room := ""
var last_progress := Vector3.ZERO
var stuck_ticks := 0
var battle_ticks := 0
var aim_point := Vector3.ZERO
var max_frames := 18000
var run_level := "expedition_03"
var healing := false
var observed_enemies: Dictionary = {}
var last_heal_frame := -1000
var pursuit_path := PackedVector3Array()
var pursuit_room := ""
var last_pursuit_frame := -1000
var live_kills := 0
var quick_heal_ready := false
var clicking := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	output_dir = OS.get_environment("TRAILER_OUTPUT")
	if output_dir.is_empty() or not OS.get_user_data_dir().contains("gameplay_trailer"):
		push_error("Recording requires isolated gameplay_trailer user data and TRAILER_OUTPUT")
		get_tree().quit(2)
		return
	var level_env := OS.get_environment("TRAILER_LEVEL")
	if not level_env.is_empty():
		run_level = level_env
	var frames_env := OS.get_environment("TRAILER_FRAMES")
	if not frames_env.is_empty():
		max_frames = int(frames_env)
	call_deferred("_begin")

func _begin() -> void:
	# Keep the input driver alive across the game's own scene transitions.
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.current_scene = null
	var data := BaseData.new()
	data.tutorial_completed = true
	data.base99_rooftop_ladder_deployed = true
	data.workshop_unlocked = true
	data.divination_unlocked = true
	data.vault_unlocked = true
	data.archive_unlocked = true
	data.extraction_points = 1200
	var registry := ItemRegistry.get_instance()
	for item_id in ["weapon_rifle", "weapon_shotgun", "item_ammo_pack", "item_health_potion", "item_battery_l"]:
		var item := BaseShopService.ensure_item_instance(registry.get_item(item_id))
		item["count"] = 600 if item_id == "item_ammo_pack" else (18 if item_id == "item_health_potion" else 1)
		data.pending_loadout_items.append(item)
	data.save_revision = BaseManager.data.save_revision if BaseManager.data != null else 0
	BaseManager.data = data
	BaseManager.save_base("isolated_gameplay_recording_profile")
	GameEntryFlow.request_gameplay_entry("recording_resume", GameEntryFlow.SPAWN_BASE_99F)
	_mark("startup")
	tree.change_scene_to_file("res://scenes/StartupLoadingScreen.tscn")
	await _wait_for_tower(false)
	if not is_instance_valid(actor):
		_finish("base_load_failed")
		return
	_mark("base_ready")
	await _frames(80)
	# All facility windows are opened through the player's E interaction.
	await _visit_facility("base_vending", 150)
	await _visit_facility("weapon_forge", 150)
	await _tap(&"ui_inventory")
	_mark("inventory")
	await _frames(90)
	await _equip_inventory_weapon("weapon_rifle")
	await _assign_quick_healing()
	await _frames(60)
	await _tap(&"ui_inventory")
	await _visit_facility("mission_operations", 180, false)
	var menu := tower.get("_active_facility_menu") as CanvasLayer
	if menu == null or not menu is RogueMapSelectMenu:
		_finish("mission_interaction_failed")
		return
	var selection_menu := menu as RogueMapSelectMenu
	while is_instance_valid(selection_menu) and str(selection_menu.get("_state")) != "active":
		await _frames(1)
	var index := selection_menu.LEVEL_IDS.find(run_level)
	if index < 0:
		_finish("level_unavailable")
		return
	for i in index:
		await _tap(&"ui_right")
		await _frames(15)
	_mark("expedition_selected_" + run_level)
	await _frames(90)
	await _tap(&"ui_accept")
	await _wait_for_tower(true)
	if not is_instance_valid(actor):
		_finish("expedition_load_failed")
		return
	_mark("expedition_ready")
	# Base and expedition own separate inventory instances. Rebind via the real UI.
	var quick := tower.get("_quick_inventory") as InventoryModule
	quick_heal_ready = quick != null and str((quick.get_slot(0).get("item", {}) as Dictionary).get("id", "")) == "item_health_potion"
	if not quick_heal_ready:
		await _tap(&"ui_inventory")
		await _frames(20)
		await _assign_quick_healing()
		await _tap(&"ui_inventory")
		await _frames(20)
	await _tap(&"toggle_flashlight")
	_mark("flashlight_on")
	await _frames(60)
	await _tap(&"toggle_floor_map")
	_mark("floor_map")
	await _frames(90)
	await _tap(&"toggle_floor_map")
	await _frames(20)
	fighting = true
	var route := _room_route("start", "boss")
	_mark("route_" + ",".join(route))
	for room_id in route:
		if room_id == str(tower.get("_current_room_id")):
			continue
		await _clear_current_room(1200)
		await _loot_current_room()
		if not is_instance_valid(actor) or actor.current_hp <= 0:
			break
		var current := str(tower.get("_current_room_id"))
		var room := tower._room_by_id.get(current) as DungeonRoom3D
		var next_room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null or next_room == null:
			continue
		var door := room.get_door_node_towards(room_id)
		if door == null:
			door = next_room.get_door_node_towards(current)
		var door_position: Vector3
		if door != null:
			door_position = door.global_position
		else:
			door_position = (room.global_position + next_room.global_position) * 0.5
		var toward := next_room.global_position - room.global_position
		toward.y = 0.0
		toward = toward.normalized()
		if door != null:
			var normal := Vector3(door.global_basis.z.x, 0, door.global_basis.z.z).normalized()
			if normal.dot(toward) < 0:
				normal = -normal
			toward = normal
		await _walk_to(door_position - toward * 2.2, 1200)
		if door != null and door.is_manual_interaction_enabled():
			await _tap(&"interact")
		await _frames(40)
		await _walk_direct(door_position + toward * 2.4, 360)
		if room_id == "boss" and await _descend_boss_stair(next_room):
			_mark("boss_arena_reached")
		else:
			await _walk_to(next_room.global_position, 1000)
		_mark("entered_" + str(tower.get("_current_room_id")))
		await _frames(60)
		if frame > max_frames - 300:
			break
	await _clear_current_room(2400)
	await _frames(120)
	if not is_instance_valid(actor) or actor.current_hp <= 0:
		_finish("player_defeated")
	elif str(tower.get("_current_room_id")) == "boss":
		_finish("boss_gameplay_captured")
	else:
		_finish("route_incomplete")

func _process(_delta: float) -> void:
	frame += 1
	if frame >= max_frames:
		_finish("frame_limit")
	if is_instance_valid(tower) and is_instance_valid(actor):
		var room_id := str(tower.get("_current_room_id"))
		if room_id != last_room:
			last_room = room_id
			_mark("room_" + room_id)
		if fighting and actor.current_hp > 0 and actor.current_hp <= 80 and not actor.input_locked and frame - last_heal_frame > 35:
			if quick_heal_ready:
				last_heal_frame = frame
				_use_quick_healing()
			elif not healing and frame - last_heal_frame > 180:
				_use_healing_item()
		if frame % 150 == 0:
			print("GAMEPLAY_STATE frame=%d mode=%s room=%s pos=%s hp=%d ammo=%s" % [frame, mode, room_id, str(actor.global_position), actor.current_hp, str(actor.weapon.current_ammo if actor.weapon != null else -1)])

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(actor) or not actor.can_process() or get_tree().paused:
		return
	if actor.input_locked or healing or clicking:
		_release_movement()
		_set_action(&"shoot", false)
		return
	var direction := Vector3.ZERO
	if walking:
		direction = move_goal - actor.global_position
		direction.y = 0.0
		if direction.length() < 0.33:
			walking = false
			direction = Vector3.ZERO
	var target := _enemy_target() if fighting else null
	if target != null:
		battle_ticks += 1
		var offset := target.global_position - actor.global_position
		offset.y = 0.0
		aim_point = target.global_position
		aim_point.y = actor.global_position.y
		if not walking:
			var tangent := Vector3(-offset.z, 0.0, offset.x).normalized()
			var sign_value := 1.0 if (battle_ticks / 170) % 2 == 0 else -1.0
			direction = tangent * sign_value
			if offset.length() < 4.0:
				direction -= offset.normalized() * 1.5
			elif offset.length() > 9.0:
				direction += offset.normalized()
			if not _free_at(actor.global_position + direction.normalized() * 1.2):
				direction = -direction
			if not _free_at(actor.global_position + direction.normalized() * 1.0):
				direction = Vector3.ZERO
		if frame % 150 == 0:
			print("GAMEPLAY_AIM target=%s hp=%d dir=%s desired=%s mouse=%s" % [target.enemy_kind, target.current_hp, str(actor.aim_direction), str(offset.normalized()), str(get_viewport().get_mouse_position())])
		_set_action(&"shoot", true)
		if actor.weapon != null and actor.weapon.current_ammo == 0:
			_set_action(&"reload", battle_ticks % 8 < 2)
		else:
			_set_action(&"reload", false)
		_set_action(&"dash", battle_ticks % 260 < 2 and direction.length() > 0.1)
	else:
		_set_action(&"shoot", false)
		_set_action(&"dash", false)
		_set_action(&"reload", actor.weapon != null and actor.weapon.current_ammo < 8 and frame % 30 < 3)
		if fighting and not walking:
			var hidden := _enemy_target(false)
			if hidden != null:
				var current_room := str(tower.get("_current_room_id"))
				if frame - last_pursuit_frame > 90 or pursuit_room != current_room:
					pursuit_path = _grid_path(hidden.global_position)
					pursuit_room = current_room
					last_pursuit_frame = frame
				while not pursuit_path.is_empty() and actor.global_position.distance_to(pursuit_path[0]) < 0.5:
					pursuit_path.remove_at(0)
				if not pursuit_path.is_empty():
					direction = pursuit_path[0] - actor.global_position
				else:
					direction = hidden.global_position - actor.global_position
				direction.y = 0.0
				if not _free_at(actor.global_position + direction.normalized()):
					direction = Vector3(-direction.z, 0, direction.x) * (1.0 if (frame / 150) % 2 == 0 else -1.0)
		if direction.length() > 0.1:
			aim_point = actor.global_position + direction.normalized() * 4.0
	if direction.length() > 0.1:
		direction = direction.normalized()
	_set_axis(&"move_right", maxf(direction.x, 0.0))
	_set_axis(&"move_left", maxf(-direction.x, 0.0))
	_set_axis(&"move_down", maxf(direction.z, 0.0))
	_set_axis(&"move_up", maxf(-direction.z, 0.0))
	if actor.camera != null and aim_point != Vector3.ZERO:
		var screen := actor.camera.unproject_position(aim_point)
		var viewport_size := get_viewport().get_visible_rect().size
		screen = screen.clamp(Vector2(2, 2), viewport_size - Vector2(2, 2))
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		motion.global_position = screen
		Input.warp_mouse(screen)
		Input.parse_input_event(motion)

func _enemy_target(require_los := true) -> Enemy3D:
	var selected: Enemy3D
	var best := INF
	var current := str(tower.get("_current_room_id"))
	for node in get_tree().get_nodes_in_group("enemy_3d"):
		var enemy := node as Enemy3D
		if enemy == null or not is_instance_valid(enemy) or enemy.current_hp <= 0 or not enemy.can_process():
			continue
		if enemy.room_id != current or enemy.is_concealed_in_world():
			continue
		var distance := actor.global_position.distance_squared_to(enemy.global_position)
		if distance >= best:
			continue
		if require_los:
			if distance > 24.0 * 24.0:
				continue
			var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.8, enemy.global_position + Vector3.UP * 0.7, 1, [actor.get_rid()])
			if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				continue
		selected = enemy
		best = distance
	return selected

func _loot_current_room() -> void:
	if not is_instance_valid(actor) or actor.current_hp <= 0:
		return
	var room := tower._room_by_id.get(str(tower.get("_current_room_id"))) as DungeonRoom3D
	if room == null:
		return
	for chest in room.get_treasure_chests():
		if bool(chest.get("_opened")):
			continue
		mode = "loot"
		var toward := actor.global_position - chest.global_position
		toward.y = 0.0
		if toward.length() < 0.1:
			toward = Vector3.FORWARD
		await _walk_to(chest.global_position + toward.normalized() * 1.25, 600)
		await _frames(15)
		var focus := actor.get_interaction_focus_snapshot()
		if str(focus.get("interaction_id", "")).begins_with("treasure_chest:"):
			_mark("chest_interact")
			await _tap(&"interact")
			await _frames(100)
			_mark("chest_opened_" + str(chest.get("_opened")))
			# Walk over the actual drops; pickup is owned by the normal runtime.
			await _walk_direct(chest.global_position + toward.normalized() * 0.6, 60)
			await _frames(35)
		break

func _clear_current_room(limit := 540) -> void:
	mode = "combat"
	walking = false
	_mark("combat_begin")
	var quiet := 0
	for i in limit:
		if not is_instance_valid(actor) or actor.current_hp <= 0:
			return
		var alive := int((tower.get("_alive_by_room") as Dictionary).get(str(tower.get("_current_room_id")), 0))
		if alive <= 0 and _enemy_target() == null:
			quiet += 1
			if quiet > 70:
				break
		else:
			quiet = 0
		await _frames(1)
	_mark("combat_end")

func _visit_facility(id: String, dwell: int, close := true) -> void:
	var facility: BaseFacility3D
	for node in get_tree().get_nodes_in_group("base_facility"):
		if node is BaseFacility3D and node.facility_id == id and tower.is_ancestor_of(node):
			facility = node
			break
	if facility == null:
		_mark("facility_missing_" + id)
		return
	var shape := facility.get_node_or_null("InteractionShape") as CollisionShape3D
	var target := shape.global_position if shape != null else facility.global_position
	target.y = actor.global_position.y
	print("GAMEPLAY_FACILITY %s root=%s shape=%s" % [id, str(facility.global_position), str(target)])
	if id == "weapon_workshop":
		var room := tower._room_by_id.get("facility") as DungeonRoom3D
		var toward := room.global_position - facility.global_position
		toward.y = 0
		target = facility.global_position + toward.normalized() * 2.8
		target.y = actor.global_position.y
	await _walk_to(target, 1500)
	await _frames(20)
	_mark("interact_" + id)
	print("GAMEPLAY_FOCUS " + str(actor.get_interaction_focus_snapshot()))
	await _tap(&"interact")
	await _frames(5)
	if tower.get("_active_facility_menu") != null:
		_mark("menu_open_" + id)
	await _frames(dwell)
	if close:
		var menu := tower.get("_active_facility_menu") as CanvasLayer
		if is_instance_valid(menu):
			var button: Button
			for node in menu.find_children("*", "Button", true, false):
				if node.name.to_lower().contains("close") or (node as Button).text.contains("返回") or (node as Button).text.contains("关闭"):
					button = node
			if button != null:
				await _click(button)
			else:
				await _tap(&"ui_cancel")
		await _frames(25)

func _descend_boss_stair(room: DungeonRoom3D) -> bool:
	# Read the authored stair's own frame; only normal movement drives descent.
	var gate: BossRoom02ArenaGate3D
	for node in room.find_children("*", "Node3D", true, false):
		if node is BossRoom02ArenaGate3D:
			gate = node
			break
	if gate == null:
		return false
	mode = "boss_stair"
	var was_fighting := fighting
	fighting = false
	_set_action(&"shoot", false)
	_set_action(&"dash", false)
	_mark("boss_stair_begin")
	for local_z in [45.0, 40.0, 30.0, 20.0, 10.0, 0.0, -10.0, -15.0, -22.5]:
		var local_y := maxf(0.0, minf(12.0, 0.24 * local_z + 2.505))
		var goal := gate.to_global(Vector3(0.0, local_y, local_z))
		await _walk_direct(goal, 360)
		_mark("boss_stair_at_" + str(actor.global_position))
		if actor.current_hp <= 0:
			break
	fighting = was_fighting
	return gate.is_arena_sealed()

func _walk_to(target: Vector3, limit: int) -> void:
	mode = "walk"
	var route := _grid_path(target)
	_mark("walk_target_%s_points_%d" % [str(target), route.size()])
	if route.is_empty():
		route.append(target)
	var each := maxi(40, limit / maxi(1, route.size()))
	for point in route:
		await _walk_direct(point, each)
		if not is_instance_valid(actor) or actor.current_hp <= 0:
			return
	walking = false
	_release_movement()

func _walk_direct(target: Vector3, limit: int) -> void:
	move_goal = target
	walking = true
	var start_position := actor.global_position
	for i in limit:
		if not is_instance_valid(actor) or not walking or actor.current_hp <= 0:
			break
		await _frames(1)
		if i > 0 and i % 90 == 0:
			if actor.global_position.distance_to(start_position) < 0.2:
				_mark("walk_blocked_" + str(actor.global_position))
				break
			start_position = actor.global_position
	walking = false
	_release_movement()

func _grid_path(target: Vector3) -> PackedVector3Array:
	var room := tower._room_by_id.get(str(tower.get("_current_room_id"))) as DungeonRoom3D
	if room == null:
		return PackedVector3Array()
	var dim := room.get_dimensions()
	var origin := room.global_position - Vector3(dim.x * 0.5, 0, dim.y * 0.5)
	if not tower.is_expedition():
		origin.x = minf(origin.x, minf(actor.global_position.x, target.x) - 6.0)
		origin.z = minf(origin.z, minf(actor.global_position.z, target.z) - 6.0)
		var far_x := maxf(room.global_position.x + dim.x * 0.5, maxf(actor.global_position.x, target.x) + 6.0)
		var far_z := maxf(room.global_position.z + dim.y * 0.5, maxf(actor.global_position.z, target.z) + 6.0)
		dim = Vector2(far_x - origin.x, far_z - origin.z)
	var step := 0.65
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, int(dim.x / step) + 1, int(dim.y / step) + 1)
	grid.cell_size = Vector2(step, step)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in grid.region.size.x:
		for z in grid.region.size.y:
			var pos := Vector3(origin.x + x * step, actor.global_position.y, origin.z + z * step)
			if not _free_at(pos):
				grid.set_point_solid(Vector2i(x, z), true)
	var from := Vector2i(roundi((actor.global_position.x - origin.x) / step), roundi((actor.global_position.z - origin.z) / step))
	var to := Vector2i(roundi((target.x - origin.x) / step), roundi((target.z - origin.z) / step))
	from = from.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
	to = to.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
	grid.set_point_solid(from, false)
	if grid.is_point_solid(to):
		var nearest := to
		var best := INF
		for x in range(maxi(0, to.x - 4), mini(grid.region.size.x, to.x + 5)):
			for z in range(maxi(0, to.y - 4), mini(grid.region.size.y, to.y + 5)):
				var point := Vector2i(x, z)
				var distance := point.distance_squared_to(to)
				if not grid.is_point_solid(point) and distance < best:
					nearest = point
					best = distance
		to = nearest
	var ids := grid.get_id_path(from, to, true)
	var result := PackedVector3Array()
	for index in range(1, ids.size()):
		var cell := ids[index]
		result.append(Vector3(origin.x + cell.x * step, actor.global_position.y, origin.z + cell.y * step))
	return result

func _free_at(pos: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.60)
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _room_route(start: String, goal: String) -> Array[String]:
	var neighbors := tower.get("_room_neighbors") as Dictionary
	var queue: Array[String] = [start]
	var previous := {start: ""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == goal:
			break
		for neighbor in neighbors.get(current, []) as Array:
			var id := str(neighbor)
			if not previous.has(id):
				previous[id] = current
				queue.append(id)
	var path: Array[String] = []
	if not previous.has(goal):
		return path
	var cursor := goal
	while not cursor.is_empty():
		path.push_front(cursor)
		cursor = str(previous[cursor])
	return path

func _wait_for_tower(expedition: bool) -> void:
	mode = "loading"
	for i in 6000:
		await _frames(1)
		var scene := get_tree().current_scene as TowerDescent3D
		if scene == null or scene.is_expedition() != expedition:
			continue
		if scene.player != null and scene._room_by_id.size() > 0 and scene.player.can_process() and not scene.player.input_locked:
			tower = scene
			actor = scene.player
			await _frames(20)
			return

func _set_axis(action: StringName, strength: float) -> void:
	var old := float(held.get(action, 0.0))
	if absf(old - strength) < 0.02:
		return
	held[action] = strength
	var event := InputEventAction.new()
	event.action = action
	event.pressed = strength > 0.01
	event.strength = strength
	Input.parse_input_event(event)

func _set_action(action: StringName, pressed: bool) -> void:
	_set_axis(action, 1.0 if pressed else 0.0)

func _release_movement() -> void:
	for action in [&"move_up", &"move_down", &"move_left", &"move_right"]:
		_set_action(action, false)

func _tap(action: StringName) -> void:
	_set_action(action, true)
	await _frames(2)
	_set_action(action, false)
	await _frames(2)

func _use_quick_healing() -> void:
	var hp_before := actor.current_hp
	await _tap(&"use_quick_item_1")
	_mark("quick_heal_hp_%d_to_%d" % [hp_before, actor.current_hp])
	var quick := tower.get("_quick_inventory") as InventoryModule
	quick_heal_ready = quick != null and str((quick.get_slot(0).get("item", {}) as Dictionary).get("id", "")) == "item_health_potion"

func _use_healing_item() -> void:
	healing = true
	last_heal_frame = frame
	var hp_before := actor.current_hp
	var ui := tower.get("_inventory_ui") as InventoryUI
	var inventory := tower.get("_inventory") as InventoryModule
	var found := -1
	for i in inventory.get_capacity():
		var slot := inventory.get_slot(i)
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == "item_health_potion":
			found = i
			break
	if found >= 0:
		await _tap(&"ui_inventory")
		await _frames(25)
		var board := ui.inventory_grid as GridInventoryBoard
		if board != null:
			await _click_at(board.get_global_transform_with_canvas() * (board.get_cell_position(found) + board.get_cell_size() * 0.5))
		await _frames(8)
		_mark("heal_item_hp_%d_to_%d" % [hp_before, actor.current_hp])
		if not quick_heal_ready:
			await _assign_quick_healing()
		await _tap(&"ui_inventory")
		await _frames(25)
	healing = false

func _assign_quick_healing() -> void:
	var ui := tower.get("_inventory_ui") as InventoryUI
	var inventory := tower.get("_inventory") as InventoryModule
	if ui == null or ui.quick_item_slots.is_empty():
		return
	var board := ui.inventory_grid as GridInventoryBoard
	if board == null:
		return
	for i in inventory.get_capacity():
		var slot := inventory.get_slot(i)
		if str((slot.get("item", {}) as Dictionary).get("id", "")) != "item_health_potion":
			continue
		var from := board.get_global_transform_with_canvas() * (board.get_cell_position(i) + board.get_cell_size() * 0.5)
		var to := ui.quick_item_slots[0].get_global_transform_with_canvas() * (ui.quick_item_slots[0].size * 0.5)
		clicking = true
		_mouse_motion(from)
		await _frames(2)
		_mouse_button(from, true)
		await _frames(3)
		for tick in 18:
			_mouse_motion(from.lerp(to, float(tick + 1) / 18.0), MOUSE_BUTTON_MASK_LEFT)
			await _frames(1)
		_mouse_button(to, false)
		await _frames(5)
		clicking = false
		var quick := tower.get("_quick_inventory") as InventoryModule
		quick_heal_ready = quick != null and not quick.get_slot(0).is_empty()
		_mark("quick_heal_assignment_" + str(quick_heal_ready))
		return

func _equip_inventory_weapon(item_id: String) -> void:
	var ui := tower.get("_inventory_ui") as InventoryUI
	if ui == null:
		return
	var board := ui.inventory_grid as GridInventoryBoard
	if board == null:
		return
	var inventory := tower.get("_inventory") as InventoryModule
	for i in inventory.get_capacity():
		var slot := inventory.get_slot(i)
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			await _click_at(board.get_global_transform_with_canvas() * (board.get_cell_position(i) + board.get_cell_size() * 0.5))
			_mark("equip_" + item_id)
			return

func _click(button: Button) -> void:
	await _click_at(button.get_global_rect().get_center())

func _mouse_motion(pos: Vector2, buttons := 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.relative = pos - get_viewport().get_mouse_position()
	motion.button_mask = buttons
	Input.warp_mouse(pos)
	Input.parse_input_event(motion)

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _click_at(pos: Vector2) -> void:
	clicking = true
	_mouse_motion(pos)
	await _frames(2)
	for pressed in [true, false]:
		_mouse_button(pos, pressed)
		await _frames(3)
	clicking = false

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _mark(label: String) -> void:
	events.append({"frame": frame, "time": float(frame) / 30.0, "event": label})
	print("GAMEPLAY_EVENT %d %s" % [frame, label])
	var file := FileAccess.open(output_dir.path_join("events.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(events, "\t"))

func _finish(reason: String) -> void:
	if mode == "finished":
		return
	mode = "finished"
	walking = false
	fighting = false
	for action in held.keys():
		_set_action(action, false)
	_mark("finish_" + reason)
	get_tree().quit()
