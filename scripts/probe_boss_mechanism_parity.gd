extends Node
## 两关 boss 房「机制一致性」对拍探针。
##
## 远征01 的 boss 房与测试关 99 的 boss 房是不是同一套机制，**不能靠读代码推断** ——
## 两关的 boss 房布局路径由 `room_instances/<关卡id>/f00_boss_static_layout.tscn` 派生，
## 各自可能是不同房图、不同档位。本探针把两关各起一次，把机制项逐条打出来对拍。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_mech'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_mechanism_parity.tscn

const LEVELS := [
	{"id": "expedition_01", "scene": "res://scenes/ExpeditionLevel01_3D.tscn"},
	{"id": "99", "scene": "res://scenes/ExpeditionLevel99_3D.tscn"},
]
const RUN_SEED := 77001199
const MECH_KEYS: Array[String] = [
	"static_layout_scene_path", "static_layout_scene_loaded", "authored_layout_asset_id",
	"authored_layout_version", "layout_instance_total", "walk_surface_owner",
	"walk_surface_scene", "walk_surface_y_m", "component_owned_support", "fog_profile",
	"authored_room_light_switch", "authored_layout_door_wall_count",
	"authored_layout_room_type_component_count", "boss_content_id", "port_door_visuals",
	"authored_room_devices", "dynamic_runtime_owned", "safe_room_orientation_steps",
]

var _root: Window


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	for value in LEVELS:
		var level := value as Dictionary
		await _dump_level(str(level.get("id", "")), str(level.get("scene", "")))
	print("BOSS_MECH_PARITY_DONE")
	get_tree().quit(0)


func _dump_level(level_id: String, scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		print("MECH %s <场景加载失败 %s>" % [level_id, scene_path])
		return
	var tower := packed.instantiate() as Dungeon3D
	if tower == null:
		print("MECH %s <根节点不是 Dungeon3D>" % level_id)
		return
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	_root.add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame

	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	print("=== LEVEL %s ===" % level_id)
	if room == null:
		print("  MECH %s boss=<缺>" % level_id)
		tower.queue_free()
		await get_tree().process_frame
		return
	var dims := room.get_dimensions()
	print("  MECH %s  位置=%s 尺寸=(%.1f,%.1f) 类型=%s" % [
		level_id, _v(room.global_position), dims.x, dims.y, room.room_type,
	])
	var static_layout := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if static_layout == null:
		static_layout = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	print("  MECH %s  art_root=%s" % [level_id, "有" if static_layout != null else "无"])
	for key in MECH_KEYS:
		var got: Variant = room.get_meta(key, null)
		if got == null and static_layout != null:
			got = _find_meta(static_layout, key)
		print("  MECH %s  %-42s = %s" % [level_id, key, _short(got)])

	# 灯 / 开关：手写递归，避开 find_children 对脚本类名过滤的歧义。
	# 🔴 扫**整个房间**（不只是艺术根）：99 那间的灯不一定挂在静态根下，
	#    只扫艺术根会得出「0 盏灯」的错误结论。
	var lights: Array[WastelandLight3D] = []
	var switches: Array[Node] = []
	_collect_lights(room, lights, switches)
	var on_count := 0
	var off_names: Array[String] = []
	for light in lights:
		if light.light_enabled:
			on_count += 1
		else:
			off_names.append("%s(%s)" % [str(light.name), str(light.fixture_style)])
	var in_art := 0
	if static_layout != null:
		var art_lights: Array[WastelandLight3D] = []
		var art_switches: Array[Node] = []
		_collect_lights(static_layout, art_lights, art_switches)
		in_art = art_lights.size()
	print("  MECH %s  %-42s = 全房灯 %d（艺术根内 %d）/ 亮 %d ；全房开关 %d ；运行时 _light_switch=%s" % [
		level_id, "lights", lights.size(), in_art, on_count, switches.size(),
		str(room.get("_light_switch") != null),
	])
	for light in lights:
		print("       灯 %-26s enabled=%-5s energy=%-6.2f range=%-5.1f style=%s" % [
			str(light.name), str(light.light_enabled), light.energy,
			light.light_range, str(light.fixture_style),
		])
	if not off_names.is_empty():
		print("       未亮的灯：%s" % str(off_names))
	# 原生 Light3D（非 WastelandLight3D）：单独点一下，避免「全房灯 0」被误读成漆黑。
	var native_lights: Array[Node] = []
	_collect_native_lights(room, native_lights)
	print("  MECH %s  %-42s = %d" % [level_id, "原生Light3D数", native_lights.size()])

	# 门控
	var gate := room.find_child("ArenaGate", true, false) as BossRoom02ArenaGate3D
	if gate == null:
		print("  MECH %s  %-42s = 无" % [level_id, "arena_gate"])
	else:
		print("  MECH %s  %-42s = 有 gate_count=%d snapshot=%s" % [
			level_id, "arena_gate", gate.gate_count(), str(gate.arena_gate_snapshot()),
		])
	print("  MECH %s  %-42s = %d" % [level_id, "Gate_槽位数", _count_prefixed(room, "Gate_")])
	var slots: Array[String] = []
	_collect_names(room, "Gate_", slots)
	print("       槽位名：%s" % str(slots))

	# 走面碰撞节点 / 一体化碰撞
	var walk := room.find_child("BossRoom02WalkSurface", true, false)
	print("  MECH %s  %-42s = %s" % [level_id, "walk_surface_node", "有" if walk != null else "无"])

	# 门 / 端口
	var door_targets: Dictionary = room.get("door_targets")
	var sides: Array[String] = []
	for side_key in door_targets.keys():
		sides.append("%s→%s" % [str(side_key), str(door_targets[side_key])])
	print("  MECH %s  %-42s = %s" % [level_id, "doors", str(sides)])
	print("  MECH %s  %-42s = %d" % [level_id, "connection_ports", room.connection_ports.size()])
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		print("      port %-3s side=%-5s lane=%7.2f height=%5.2f target=%s" % [
			str(port.get("port_id", "")), str(port.get("side", "")),
			float(port.get("lane_m", 0.0)), float(port.get("height_m", 0.0)),
			str(port.get("target_room_id", "")),
		])

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _collect_lights(
	node: Node, lights: Array[WastelandLight3D], switches: Array[Node]
) -> void:
	for child in node.get_children():
		if child is WastelandLight3D:
			lights.append(child as WastelandLight3D)
		elif child is RoomLightSwitch3D:
			switches.append(child)
		_collect_lights(child, lights, switches)


func _collect_names(node: Node, prefix: String, out: Array[String]) -> void:
	for child in node.get_children():
		if str(child.name).begins_with(prefix):
			out.append(str(child.name))
		_collect_names(child, prefix, out)


## 原生 Light3D（OmniLight3D / SpotLight3D / DirectionalLight3D）：
## 用来分辨「没有 WastelandLight3D」到底是「漆黑」还是「换成原生灯了」。
func _collect_native_lights(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is Light3D and not (child is WastelandLight3D):
			out.append(child)
		_collect_native_lights(child, out)


func _count_prefixed(root_node: Node, prefix: String) -> int:
	var names: Array[String] = []
	_collect_names(root_node, prefix, names)
	return names.size()


func _find_meta(node: Node, key: String) -> Variant:
	if node.has_meta(key):
		return node.get_meta(key)
	for child in node.get_children():
		var found: Variant = _find_meta(child, key)
		if found != null:
			return found
	return null


func _short(value: Variant) -> String:
	if value == null:
		return "<无>"
	var text := str(value)
	return text if text.length() <= 160 else text.substr(0, 160) + "…"


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
