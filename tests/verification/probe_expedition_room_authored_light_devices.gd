extends Node
## 探针：远征01「房间灯与墙面开关是否已改由静态布局 TSCN 持有」的实测与回归。
##
## 背景：房间的中央顶灯（`WastelandLight3D`）与墙面开关（`RoomLightSwitch3D`）原先
## 一律由 `DungeonRoom3D._build_content()` 在运行时实例化，静态 TSCN 里查不到 ——
## 美术无法在编辑器里手动调整位置与数值。本次改动把这两类设备改为**静态布局真源**：
## 静态 TSCN 根（`AuthoredLayoutArtRoot`）下直接持有 `WastelandLight3D` 与
## `RoomLightSwitch3D` 节点；运行时优先「认领」它们，不再自建。
##
## 逐房打印（`DUMP` 行可直接对照 TSCN 文本）：
##   · 房型事实：size_class / dimensions / theme / authored_room_light_on / tower_module_shell
##   · 静态根：名字与 transform（灯与开关写进 TSCN 时用的是**相对该根的局部坐标**）
##   · 每盏灯与开关：`var_to_str(transform)` + 全部导出参数 + 是否来自静态布局
##
## 断言（`TARGET_ROOMS` 里声明的房间）：
##   ① 静态布局根下必须存在 `WastelandLight3D` 与 `RoomLightSwitch3D`（真源已落地）；
##   ② 这些静态节点必须就是运行时登记进 `_room_lights` / `_light_switch` 的那批
##      （识别为「运行时复用了静态节点」，而非又建了一份）；
##   ③ 开关能真的控制灯：`perform_interaction` 后灯状态翻转且 omni 实际能量跟随。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_authored_devices'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://tests/verification/probe_expedition_room_authored_light_devices.tscn

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
## 静态场景生成器。它的 `AUTHORED_DEVICE_ROOMS` 是「哪些房自持灯与开关」的唯一真源，
## 探针直接读它 —— 两处各维护一份名单迟早会有一边忘了改，然后就是「探针绿、场景缺件」。
const STATIC_SCENE_GENERATOR := preload("res://scripts/generate_expedition01_room_static_scenes.gd")
const RUN_SEED := 77001199
const STATIC_ROOT_NAMES: Array[String] = ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]
const MIN_LIGHT_ENERGY := 0.01
const INTERACTION_RANGE_M := 2.2
const TILE_STAND_HALF_M := 2.47
const PLAYER_BODY_RADIUS_M := 0.45
## 站位点与开关的最小平面距离（≈ 玩家身位直径）。开关贴墙，站得太近会被物理挤出墙体、
## 甚至掉出本房归属，交互区（半径 INTERACTION_RANGE_M 的球，心在开关上方 0.9m）便探不到。
const MIN_STAND_DISTANCE_M := PLAYER_BODY_RADIUS_M * 2.0

var _violations: Array[String] = []
var _checks := 0


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		_fail("远征01运行时没有 Blocks/Expedition")
		_finish(0)
		return
	for room_id in _target_rooms():
		var room := block.get_node_or_null(room_id) as DungeonRoom3D
		if room == null:
			_fail("运行时缺少房间 %s" % room_id)
			continue
		await _probe_room(tower, room)
	_finish(_target_rooms().size())


## 待验房间 = 生成器声明的自持设备名单（分批推进：每迁一户改生成器常量即可）。
func _target_rooms() -> Array[String]:
	return STATIC_SCENE_GENERATOR.AUTHORED_DEVICE_ROOMS


func _probe_room(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle()
	var static_root := _static_root(room)
	var dimensions: Vector2 = room.call("get_dimensions")
	print("DUMP room=%s size_class=%s dimensions=%s theme=%s" % [
		room.room_id,
		str(room.get("size_class")),
		vec2_to_txt(dimensions),
		_res_path(room.get("theme")),
	])
	print("DUMP room=%s authored_room_light_on=%s tower_module_shell=%s" % [
		room.room_id,
		str(room.get("authored_room_light_on")),
		str(room.get("tower_module_shell")),
	])
	if static_root == null:
		_fail("%s 运行时找不到静态布局根（%s）" % [room.room_id, str(STATIC_ROOT_NAMES)])
		return
	print("DUMP room=%s static_root=%s transform=%s" % [
		room.room_id, static_root.name, var_to_str(static_root.transform),
	])
	_dump_static_children(room, static_root)
	_dump_door_clearance(room, static_root as Node3D)

	var static_lights := _collect_static_lights(static_root)
	var static_switches := _collect_static_switches(static_root)
	var runtime_lights: Array = room.get("_room_lights") as Array
	var runtime_switch := room.get("_light_switch") as RoomLightSwitch3D
	var central := room.get("_central_light") as WastelandLight3D

	print("DUMP room=%s static_lights=%d static_switches=%d runtime_lights=%d runtime_switch=%s" % [
		room.room_id, static_lights.size(), static_switches.size(),
		runtime_lights.size(), str(runtime_switch != null),
	])
	for value in runtime_lights:
		var light := value as WastelandLight3D
		if light == null:
			continue
		var parent := light.get_parent()
		print("DUMP room=%s light node=%s parent=%s from_static=%s" % [
			room.room_id, light.name,
			parent.name if parent != null else "<none>",
			str(static_lights.has(light)),
		])
		print("DUMP room=%s light %s transform=%s" % [
			room.room_id, light.name, var_to_str(light.transform),
		])
		print("DUMP room=%s light %s params color=%s energy=%s range=%s failing=%s seed=%d shadow=%s style=%s enabled=%s cull_mask=%s" % [
			room.room_id, light.name,
			var_to_str(light.light_color), var_to_str(light.energy), var_to_str(light.light_range),
			str(light.failing), light.flicker_seed, str(light.cast_shadow),
			str(light.fixture_style), str(light.light_enabled), str(light.light_cull_mask),
		])
	if central != null:
		print("DUMP room=%s central_light=%s from_static=%s" % [
			room.room_id, central.name, str(static_lights.has(central)),
		])
	if runtime_switch != null:
		var sparent := runtime_switch.get_parent()
		print("DUMP room=%s switch node=%s parent=%s from_static=%s transform=%s light_on=%s" % [
			room.room_id, runtime_switch.name,
			sparent.name if sparent != null else "<none>",
			str(static_switches.has(runtime_switch)),
			var_to_str(runtime_switch.transform),
			str(runtime_switch.is_light_on()),
		])

	# ── 断言 ────────────────────────────────────────────────────────────────
	_checks += 1
	if static_lights.is_empty():
		_fail("%s 静态布局里没有 WastelandLight3D（仍未改由 TSCN 持有）" % room.room_id)
	_checks += 1
	if static_switches.is_empty():
		_fail("%s 静态布局里没有 RoomLightSwitch3D（仍未改由 TSCN 持有）" % room.room_id)
	for value in runtime_lights:
		var light := value as WastelandLight3D
		if light == null:
			continue
		_checks += 1
		if not static_lights.has(light):
			_fail("%s 运行时登记了非静态灯 %s（parent=%s），说明仍在自建" % [
				room.room_id, light.name,
				str((light.get_parent() as Node).name) if light.get_parent() != null else "<none>",
			])
	if runtime_switch != null:
		_checks += 1
		if not static_switches.has(runtime_switch):
			_fail("%s 运行时开关不是静态节点（parent=%s）" % [
				room.room_id,
				str((runtime_switch.get_parent() as Node).name)
					if runtime_switch.get_parent() != null else "<none>",
			])
	if runtime_switch != null and not static_lights.is_empty():
		await _probe_switch_controls_lights(room, runtime_switch, tower)


func _probe_switch_controls_lights(
	room: DungeonRoom3D, switch: RoomLightSwitch3D, tower: TowerDescent3D
) -> void:
	var player := tower.player
	if player == null:
		_fail("%s 没有玩家，无法验开关控灯" % room.room_id)
		return
	var stand := _stand_position(room, switch)
	player.global_position = stand + Vector3(0.0, 0.05, 0.0)
	await _settle()
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var candidate: Dictionary = switch.get_interaction_candidate(player as Player3D)
	_checks += 1
	if candidate.is_empty():
		_fail("%s 站在开关前仍无交互候选（归属=%s）" % [
			room.room_id, str(tower.get("_current_room_id")),
		])
		return
	var before := switch.is_light_on()
	var performed := switch.perform_interaction(player as Player3D, candidate)
	await _settle()
	var after := switch.is_light_on()
	_checks += 1
	if not performed or after == before:
		_fail("%s 开关未能控制灯：perform=%s %s→%s" % [
			room.room_id, str(performed), str(before), str(after),
		])
		return
	_checks += 1
	if after and not _lights_lit(room):
		_fail("%s 灯状态为开，但 omni 实际能量为 0" % room.room_id)
	print("DUMP room=%s switch_controls_lights=%s→%s" % [
		room.room_id, str(before), str(after),
	])


func _lights_lit(room: DungeonRoom3D) -> bool:
	var lights: Array = room.get("_room_lights") as Array
	var checked := false
	for value in lights:
		var light := value as WastelandLight3D
		if light == null:
			continue
		checked = true
		var omni := light.get("_light") as OmniLight3D
		if omni == null or omni.light_energy <= MIN_LIGHT_ENERGY:
			return false
	return checked


## 站位点（**世界坐标**）：玩家要站到开关**朝房心一侧**才触发得了交互。
##
## 两个坑（2026-09-29 修，扩到 13 房后由 `start` / `boss` 暴露）：
##
##   ① **坐标系各自归位**。设备改挂静态艺术根后，`switch.position` 是**艺术根局部**；
##      而砖格 `_authored_tile_cells` 是**房间局部**（来自 `authored_layout_instances`
##      的 `floor_tile` 槽位）。两者必须各用各的父级换算。此前一律 `room.to_global(switch.position)`，
##      只是因为多数房的艺术根恰为 identity 才没出错 —— 入口安全房的艺术根带 yaw −90°，
##      同一段代码会把玩家位错出 **10.6m**（交互半径才 2.2m），必然无候选。
##
##   ② **别把玩家塞进开关里**。砖格 clamp 得出的点可能与开关**重合**（BOSS 房实测 dist=0）：
##      开关贴在墙上，重合点等于让玩家站在墙体/开关体内，物理把他挤出去，
##      归属甚至会掉到隔壁房（实测归属=room_10）。故最终点必须与开关保持
##      `MIN_STAND_DISTANCE_M` 的平面距离；无砖格可依时也走同一条退化路径。
##
## 返回世界坐标，调用方直接赋值给 `player.global_position`。
func _stand_position(room: DungeonRoom3D, light_switch: RoomLightSwitch3D) -> Vector3:
	# 开关换算回**房间局部**，与砖格同一坐标系后再做平面比较。
	var switch_local: Vector3 = room.global_transform.affine_inverse() * light_switch.global_position
	var cells: Array = room.get("_authored_tile_cells") as Array
	var best := INF
	var best_point := switch_local
	for value in cells:
		var cell := value as Vector3
		var point := Vector3(
			clampf(switch_local.x, cell.x - TILE_STAND_HALF_M, cell.x + TILE_STAND_HALF_M),
			0.0,
			clampf(switch_local.z, cell.z - TILE_STAND_HALF_M, cell.z + TILE_STAND_HALF_M),
		)
		var distance := Vector2(point.x - switch_local.x, point.z - switch_local.z).length()
		if distance < best:
			best = distance
			best_point = point
	# 退化保护：无砖格、或最近砖格点与开关贴得太近 ⇒ 退到「朝房心 MIN_STAND_DISTANCE_M」。
	# 房间原点即房间中心（砖格与开关坐标都以此为零点），故 -switch_local 即朝房心方向。
	if best == INF or best < MIN_STAND_DISTANCE_M:
		var inland := Vector3(-switch_local.x, 0.0, -switch_local.z)
		if inland.length() > 1e-4:
			best_point = switch_local + inland.normalized() * MIN_STAND_DISTANCE_M
	best_point.y = 0.0
	return room.to_global(best_point)


func _dump_static_children(room: DungeonRoom3D, static_root: Node) -> void:
	var lights := 0
	var switches := 0
	var others := 0
	for child in static_root.get_children():
		if child is WastelandLight3D:
			lights += 1
			print("DUMP room=%s static_child LIGHT %s transform=%s" % [
				room.room_id, child.name, var_to_str((child as Node3D).transform),
			])
		elif child is RoomLightSwitch3D:
			switches += 1
			print("DUMP room=%s static_child SWITCH %s transform=%s" % [
				room.room_id, child.name, var_to_str((child as Node3D).transform),
			])
		elif child is OmniLight3D:
			others += 1
			print("DUMP room=%s static_child STRAY_OMNI %s transform=%s energy=%s" % [
				room.room_id, child.name, var_to_str((child as Node3D).transform),
				var_to_str((child as OmniLight3D).light_energy),
			])
	print("DUMP room=%s static_children lights=%d switches=%d stray_omni=%d" % [
		room.room_id, lights, switches, others,
	])


## 门位净空盒的**逐节点归因**（只打印，不作断言）。
##
## 判据与 `verify_expedition_room_type_component_replay.gd::_check_door_aperture()` 逐字一致：
## 沿墙轴 ±1.05、竖直 y ∈ [0.15, 2.35]、法向 ±0.4。
## 用途：房间静态布局里新增「自持设备节点」后，必须能说出净空盒里的顶点**到底是谁的** ——
## 否则会出现「数字没变 ⇒ 以为无关」的误判（旧运行时的开关挂在 `RuntimeDetail` 下，
## 不经过本检查；改成静态节点后它才第一次进入检查视野）。
func _dump_door_clearance(room: DungeonRoom3D, art_root: Node3D) -> void:
	if art_root == null:
		return
	for direction_value in room.doors:
		var direction := str(direction_value)
		var door := room.get_door_node(direction) as Node3D
		if door == null:
			continue
		var lane := art_root.transform.affine_inverse() * door.position
		var total := 0
		for child in art_root.get_children():
			if not (child is Node3D):
				continue
			var hits := _count_door_box(child as Node3D, art_root, direction, lane)
			if hits <= 0:
				continue
			total += hits
			print("DUMP room=%s door=%s blocker=%s class=%s verts=%d device=%s" % [
				room.room_id, direction, child.name, child.get_class(), hits,
				str(child.get_meta("authored_room_device", "<none>")),
			])
		print("DUMP room=%s door=%s lane=(%.3f,%.3f,%.3f) blocked_total=%d" % [
			room.room_id, direction, lane.x, lane.y, lane.z, total,
		])


func _count_door_box(module: Node3D, art_root: Node3D, direction: String, lane: Vector3) -> int:
	var blocked := 0
	for node in _mesh_instances_of(module):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var to_art := _transform_relative_to_ancestor(mesh_instance, art_root)
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for vertex in vertices:
				var local := to_art * vertex
				if local.y < 0.15 or local.y > 2.35:
					continue
				if direction in ["north", "south"]:
					if absf(local.x - lane.x) <= 1.05 and absf(local.z - lane.z) <= 0.4:
						blocked += 1
				elif absf(local.z - lane.z) <= 1.05 and absf(local.x - lane.x) <= 0.4:
					blocked += 1
	return blocked


func _mesh_instances_of(module: Node3D) -> Array[Node]:
	var meshes: Array[Node] = []
	if module is MeshInstance3D:
		meshes.append(module)
	meshes.append_array(module.find_children("*", "MeshInstance3D", true, false))
	return meshes


func _transform_relative_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var relative := node.transform
	var cursor := node.get_parent()
	while cursor != ancestor:
		if cursor == null:
			return Transform3D()
		if not (cursor is Node3D):
			return Transform3D()
		relative = (cursor as Node3D).transform * relative
		cursor = cursor.get_parent()
	return relative


func _static_root(room: DungeonRoom3D) -> Node:
	for name in STATIC_ROOT_NAMES:
		var found := room.get_node_or_null(name)
		if found != null:
			return found
	return null


## 静态根下递归收集房间灯（静态 TSCN 的直接子节点即为真源；组件 prefab 内部无灯具）。
func _collect_static_lights(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is WastelandLight3D:
			found.append(child)
		found.append_array(_collect_static_lights(child))
	return found


func _collect_static_switches(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is RoomLightSwitch3D:
			found.append(child)
		found.append_array(_collect_static_switches(child))
	return found


func _res_path(value: Variant) -> String:
	var resource := value as Resource
	return resource.resource_path if resource != null else "<none>"


func vec2_to_txt(value: Vector2) -> String:
	return "(%.3f,%.3f)" % [value.x, value.y]


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout


func _fail(message: String) -> void:
	_violations.append(message)


func _finish(target_count: int) -> void:
	print("")
	if _violations.is_empty():
		print("EXPEDITION_ROOM_AUTHORED_LIGHT_DEVICES_OK rooms=%d checks=%d" % [
			target_count, _checks,
		])
		get_tree().quit(0)
		return
	for violation in _violations:
		print("FAIL %s" % violation)
	get_tree().quit(1)
