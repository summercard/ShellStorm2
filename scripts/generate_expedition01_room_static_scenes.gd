extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const TOWER_DOOR_LEAF_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn"
)
## 暗门整樘预制体。房间 TSCN 里放的是**这个资源**的实例 ——
## 编辑器里看到的门与运行时 `SecretBranch3D` 建的是同一份，不存在两套外观。
const SECRET_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/common_components/secret_door/secret_door_root_top3d.tscn"
)
const RUN_SEED := 77001199
const OUTPUT_ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01"
const ROOM_IDS: Array[String] = [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]
## 已经「静态布局自持房间灯 + 墙面开关」的房间。
##
## 这些房间的房间灯（`WastelandLight3D`）与墙面开关（`RoomLightSwitch3D`）不再是运行时
## 自建对象，而是静态 TSCN 的直接子节点 —— 美术能在编辑器里手动调整它们的位置与数值。
## 已**全部 13 房**（远征01 无遗漏）：`start`、`room_01`…`room_10`、`boss`、`extraction`。
## 2026-09-29 从 room_01/room_02 两房推广到全量 —— 由
## `scripts/patch_expedition01_room_authored_devices.py` 按运行时实测真值逐房外科式插入完成。
##
## 每迁一户往这里加一行，重跑生成器即落地；不在名单里的房间逐字走原路径（运行时自建）。
##
## 🔴 单一真源：验收探针 `probe_expedition_room_authored_light_devices.gd` 直接读这个
## 常量（`TARGET_ROOMS` 由它派生），不要在两处各维护一份名单。
const AUTHORED_DEVICE_ROOMS: Array[String] = [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]

var failures: Array[String] = []
## 本局运行时塔楼根。`_emit_authored_secret_doors()` 要从它下面读
## `SecretBranches` 算定的位点（含外推后的真实位置）。
var tower_runtime: Node3D = null

func _ready() -> void:
	var previous_static_layout_mode: bool = ROOM_SCRIPT.use_expedition_static_layout_scenes
	ROOM_SCRIPT.use_expedition_static_layout_scenes = false
	var room_ids := _selected_room_ids()
	if room_ids.is_empty():
		_fail("没有选中任何房间（SS_STATIC_ROOMS 可能写错了房间名）")
		ROOM_SCRIPT.use_expedition_static_layout_scenes = previous_static_layout_mode
		for failure in failures:
			print("FAIL %s" % failure)
		get_tree().quit(1)
		return
	var tower := EXPEDITION_SCENE.instantiate()
	if tower == null:
		_fail("远征01场景无法实例化")
	else:
		tower_runtime = tower as Node3D
		tower.test_mode = true
		tower.run_seed_override = RUN_SEED
		add_child(tower)
		for _index in range(8):
			await get_tree().process_frame
			await get_tree().physics_frame
		var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
		if block == null:
			_fail("远征01运行时没有 Blocks/Expedition")
		else:
			for room_id in room_ids:
				var room := block.get_node_or_null(room_id) as Node3D
				if room == null:
					_fail("运行时缺少房间 %s" % room_id)
				else:
					await _generate_live_room(room_id, room)
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	ROOM_SCRIPT.use_expedition_static_layout_scenes = previous_static_layout_mode
	if failures.is_empty():
		print("EXPEDITION01_STATIC_SCENES_WRITTEN rooms=%d" % room_ids.size())
		get_tree().quit(0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)


## 本次要重生成的房间。默认全量 13 房；`SS_STATIC_ROOMS=room_01,room_02` 可只挑几间。
##
## 存在的理由：改了单个房型/组件后往往只想回灌受影响的那几间。全量重写会把其余房间
## 静态场景一起覆盖掉 —— 别人正在那些文件上做的编辑器手调会被无声抹掉。
## 用法：
##   SS_STATIC_ROOMS=room_01,room_02 "<godot>" --headless --path "<project>" \
##     --scene res://scripts/generate_expedition01_room_static_scenes.tscn
func _selected_room_ids() -> Array[String]:
	var raw := OS.get_environment("SS_STATIC_ROOMS").strip_edges()
	if raw.is_empty():
		return ROOM_IDS
	var wanted: Array[String] = []
	for token in raw.split(",", false):
		var room_id := token.strip_edges()
		if room_id.is_empty():
			continue
		if not ROOM_IDS.has(room_id):
			_fail("SS_STATIC_ROOMS 里含未知房间 %s，已忽略" % room_id)
			continue
		if not wanted.has(room_id):
			wanted.append(room_id)
	return wanted

func _generate_live_room(room_id: String, room: Node3D) -> void:
	var dungeon_room := room as DungeonRoom3D
	if dungeon_room == null:
		_fail("%s 不是 DungeonRoom3D" % room_id)
		return
	dungeon_room.ensure_shell_built()
	if room_id in AUTHORED_DEVICE_ROOMS:
		# 名单里的房间要把房间灯与墙面开关固化进静态场景，取值来自运行时实际算定的那份。
		# 🔴 必须赶在下面「搬走艺术根子节点」之前建 detail：组件节点被挪进 root_owner 后，
		# 依赖房间内容的构建路径就没得读了。
		dungeon_room.ensure_detail_built()
	await get_tree().process_frame
	var static_root := dungeon_room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if static_root == null:
		static_root = dungeon_room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if static_root == null:
		static_root = dungeon_room.get_node_or_null("ExpeditionRoomStaticLayout") as Node3D
	if static_root == null:
		_fail("%s 运行时没有静态艺术根" % room_id)
		return
	var root_owner := Node3D.new()
	root_owner.name = "ExpeditionRoomStaticLayout"
	root_owner.transform = static_root.transform
	# 艺术根上的实例总数、AssetID 等元数据仍是现有运行时与验收契约的一部分。
	# TSCN 化只改变静态节点的来源，不能在搬运子节点时丢掉这些契约。
	for meta_name in static_root.get_meta_list():
		root_owner.set_meta(meta_name, static_root.get_meta(meta_name))
	for key in [
		"authored_layout_shell", "authored_layout_asset_id", "authored_layout_version",
		"authored_layout_room_id", "authored_layout_corner_count", "authored_layout_solid_wall_count",
		"authored_layout_door_wall_count", "authored_layout_floor_tile_count",
		"authored_layout_exclusive_count", "authored_layout_multi_level_count",
		"authored_layout_room_type_component_count", "authored_layout_promoted_walls",
	]:
		if dungeon_room.has_meta(key):
			root_owner.set_meta(key, dungeon_room.get_meta(key))
	# 安全房（入口房）v007 的房间级事实：版本、整房旋转步数、四角 L 开关与计数、
	# 房间包数量。这些值在动态装配时算定；静态布局必须一并保留，否则运行时房间
	# 读不到它们（快照 safe_room_* 归零、入口房验收误判为「未接入 v007 美术」）。
	for meta_name in dungeon_room.get_meta_list():
		var meta_key := str(meta_name)
		if meta_key.begins_with("safe_room_"):
			root_owner.set_meta(meta_key, dungeon_room.get_meta(meta_key))
	for direction in ["north", "south", "east", "west"]:
		var runtime_key := "tower_wall_door_offset_%s" % direction
		if dungeon_room.has_meta(runtime_key):
			root_owner.set_meta(
				"snapshot_tower_wall_door_offset_%s" % direction,
				dungeon_room.get_meta(runtime_key)
			)
	root_owner.set_meta("schema", "shellstorm2.expedition.room_static_layout.v001")
	root_owner.set_meta("room_id", room_id)
	root_owner.set_meta("room_type", dungeon_room.room_type)
	root_owner.set_meta("source_mode", "live_expedition_runtime_static_extract")
	root_owner.set_meta("static_layout_only", true)
	# 运行时拥有的节点清单（声明性契约：这些不进静态 TSCN，由 DungeonRoom3D 按本局算定）。
	# 出口提示牌 `ENV-BATTLE-EXIT-NEON-SIGN` 由 `_build_safe_room_exit_sign()` 按本局
	# **世界门向**生成 —— 门向每局变，所以它**不能**固化进静态布局；只有安全房会有一块。
	# 2026-10-12：漏声明过，导致后人读 TSCN 以为「漏摆了 EXIT 牌」。
	var dynamic_owned: Array[String] = ["RoomDoor3D", "RoomTrigger", "RuntimeDetail", "NavigationRegion3D"]
	if dungeon_room.room_type == "STAIR_LOBBY":
		dynamic_owned.append("SafeRoomExitSign")
	root_owner.set_meta("dynamic_runtime_owned", dynamic_owned)
	var move: Array[Node] = []
	for child in static_root.get_children():
		move.append(child)
	for child in move:
		static_root.remove_child(child)
		root_owner.add_child(child)
	# 连接端口是房间坐标系的一部分，而不是动态玩法节点；将其与静态房型一起固化，
	# 使编辑器、运行时探针和后续拼装都读取同一组可视锚点。
	var connection_ports_root := dungeon_room.get_node_or_null("ConnectionPorts") as Node3D
	if connection_ports_root != null:
		dungeon_room.remove_child(connection_ports_root)
		root_owner.add_child(connection_ports_root)
		root_owner.set_meta("connection_port_count", connection_ports_root.get_child_count())
	if room_id == "start":
		_add_safe_room_door_previews(dungeon_room, root_owner)
	# 房间灯与墙面开关：名单里的房间把它们固化成静态场景节点（设备真源）。
	# 必须在下面统一接管 owner 之前挂上 —— 这个循环会把它们的 owner 一并设好。
	if room_id in AUTHORED_DEVICE_ROOMS:
		_emit_authored_room_devices(dungeon_room, root_owner)
	# 暗门同样固化成静态节点：业主在编辑器里直接看到门、直接拖。
	_emit_authored_secret_doors(dungeon_room, root_owner)
	# 房间场景只拥有顶层 prefab 实例根；组件内部 owner 保持原 PackedScene 边界。
	# 递归改 owner 会把 ImportedModel/Mesh/Collision 全部展开进房间 TSCN，
	# 既破坏 prefab 可编辑边界，也会在退出时造成大规模 3D RID 泄漏。
	for child in root_owner.get_children():
		child.owner = root_owner
		if child.name == "ConnectionPorts":
			for marker in child.get_children():
				marker.owner = root_owner
	var packed := PackedScene.new()
	var pack_error := packed.pack(root_owner)
	if pack_error != OK:
		_fail("%s PackedScene.pack 失败: %s" % [room_id, str(pack_error)])
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
		var path := "%s/f00_%s_static_layout.tscn" % [OUTPUT_ROOT, room_id]
		var save_error := ResourceSaver.save(packed, path)
		if save_error != OK:
			_fail("%s 保存失败: %s" % [room_id, str(save_error)])
		else:
			print("STATIC_SCENE_WRITTEN room=%s path=%s children=%d" % [room_id, path, root_owner.get_child_count()])
	root_owner.free()


## 把本房间的暗门固化成静态节点（业主 2026-10-19：要在房间 TSCN 里看得见、能拖）。
##
## 位置真源**分两层**，先后顺序不能反：
##   ① 已有 TSCN 里那扇门的 `transform` —— 业主在编辑器里手调过的位置，必须原样留住；
##   ② 没有才用运行时算出的位点（已按实测墙面外推到墙外 0.40m）。
## 这样「重跑生成器」只补齐缺的门，不会把人的手调抹回自动值 ——
## 文件头那句「全量重写会抹掉别人手调」的告警对暗门不再成立。
##
## metadata 是给编辑器和排查用的：`secret_site_id` 让运行时知道这扇门对应哪个位点，
## 改名字反而会让它退回自动位点（名字就是契约，`SecretDoor_<site_id>`）。
func _emit_authored_secret_doors(dungeon_room: DungeonRoom3D, root_owner: Node3D) -> void:
	if SECRET_DOOR_PREFAB == null:
		_fail("暗门预制体缺失，%s 无法固化门前节点" % dungeon_room.room_id)
		return
	var sites := _runtime_secret_sites()
	if sites.is_empty():
		return
	var room_id := dungeon_room.room_id
	var existing := _read_existing_secret_doors(room_id)
	# 位点是**世界坐标**，房间 TSCN 存的是**房间局部**。少这一层换算，
	# 关卡一挪房间，编辑器里的门与游戏里的门就会差出整个房间的距离。
	var room_inverse := dungeon_room.global_transform.affine_inverse()
	var emitted := 0
	for value in sites:
		var site := value as Dictionary
		if str(site.get("room_id", "")) != room_id:
			continue
		var site_id := str(site.get("site_id", ""))
		if site_id.is_empty():
			continue
		var door := SECRET_DOOR_PREFAB.instantiate() as Node3D
		if door == null:
			_fail("%s 暗门 `%s` 预制体实例化失败" % [room_id, site_id])
			continue
		door.name = "SecretDoor_%s" % site_id
		var room_local: Transform3D = (
			existing.get(site_id, Transform3D.IDENTITY) as Transform3D
		)
		var kept_manual := existing.has(site_id)
		if not kept_manual:
			room_local = room_inverse * _site_transform(site)
		door.transform = root_owner.transform.affine_inverse() * room_local
		door.set_meta("secret_site_id", site_id)
		door.set_meta("secret_pair_id", int(site.get("pair_id", -1)))
		door.set_meta("secret_role", str(site.get("role", "")))
		# 声明这扇门是**位置真源**：运行时按它的 transform 装门，不是纯装饰。
		door.set_meta("secret_door_position_source", "authored")
		door.set_meta("secret_door_position_kept_manual", kept_manual)
		root_owner.add_child(door)
		emitted += 1
	if emitted > 0:
		print("AUTHORED_SECRET_DOORS room=%s doors=%d kept_manual=%d" % [
			room_id, emitted, existing.size(),
		])


## 运行时算定的全部支线位点（含 `_push_site_out_of_wall()` 外推后的位置）。
func _runtime_secret_sites() -> Array:
	if tower_runtime == null:
		return []
	var branch := tower_runtime.get_node_or_null("SecretBranches")
	if branch == null:
		return []
	# 房间这刻已装配完，正好补做一次外推，拿到的是**实测墙面之外**的位置。
	branch.call("settle_sites")
	var snapshot := branch.call("debug_snapshot") as Dictionary
	if snapshot == null:
		return []
	return snapshot.get("sites", []) as Array


## 位点 → 房间局部 transform。`SecretDoor3D` 的朝向契约：
## `rotation.y = atan2(normal.x, normal.z)`（门的 +Z 对准朝外法线）。
func _site_transform(site: Dictionary) -> Transform3D:
	var position := site.get("position", Vector3.ZERO) as Vector3
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	var basis := Basis.IDENTITY
	if normal.length() > 0.0001:
		basis = Basis(Vector3.UP, atan2(normal.x, normal.z))
	return Transform3D(basis, position)


## 读已有房间 TSCN 里 `SecretDoor_*` 的**房间局部** transform。
##
## 只认根层直接子节点：门的 `DoorLeaf` / `Boards` 子节点也是 Node3D，
## 递归下去会把手动位置算到门叶上。
func _read_existing_secret_doors(room_id: String) -> Dictionary:
	var result: Dictionary = {}
	var path := "%s/f00_%s_static_layout.tscn" % [OUTPUT_ROOT, room_id]
	if not ResourceLoader.exists(path):
		return result
	var packed := load(path) as PackedScene
	if packed == null:
		return result
	var state := packed.get_state()
	if state == null:
		return result
	var root_xform := _state_transform(state, 0)
	for index in range(state.get_node_count()):
		var node_name := str(state.get_node_name(index))
		if not node_name.begins_with("SecretDoor_"):
			continue
		# 只认根层：`get_node_path()` 返回节点自己的完整路径（`./SecretDoor_S1`），
		# 根层即「斜杠恰好 1 个」；门叶/木板会是 `./SecretDoor_S1/DoorLeaf`。
		var node_path := str(state.get_node_path(index))
		if node_path.count("/") != 1:
			continue
		var site_id := node_name.trim_prefix("SecretDoor_")
		if site_id.is_empty():
			continue
		result[site_id] = root_xform * _state_transform(state, index)
	return result


## 取 SceneState 里某个节点的 transform；没有该属性就返回单位阵
## （预制体默认位置就是这个值 —— 导出时与默认相同会被省略）。
func _state_transform(state: SceneState, index: int) -> Transform3D:
	for property_index in range(state.get_node_property_count(index)):
		if str(state.get_node_property_name(index, property_index)) == "transform":
			return state.get_node_property_value(index, property_index) as Transform3D
	return Transform3D.IDENTITY


## 把房间灯与墙面开关固化进静态布局 —— 「设备真源」从运行时自建改成场景持有。
##
## 位置与数值**一律取运行时实际算定的那一份**：先让房间照常把 detail 建一遍，再把
## `_room_lights` / `_light_switch` 这些节点原样搬进静态场景。这里不复刻任何摆位规则
## —— 两套规则一旦分叉，编辑器里手调的值与游戏里跑的值就会各说各话。
##
## 搬过去的是组件母版实例本身（`prp_wasteland_light_root_top3d` /
## `prp_room_light_switch_root_top3d` 的实例根），房型场景只拥有顶层实例根、
## 不展开组件内部节点，与其余组件实例同一条约定。
##
## 运行时侧由 `DungeonRoom3D._adopt_authored_room_devices()` 反向认领这两个节点，
## 不会再建第二份（见 `DungeonRoom3D._build_content()` 的 `authored_devices` 分支）。
func _emit_authored_room_devices(dungeon_room: DungeonRoom3D, root_owner: Node3D) -> void:
	# detail 已在 `_generate_live_room()` 里提前建好（必须早于搬运艺术根子节点）。
	dungeon_room.ensure_detail_built()
	var light_count := 0
	for value in (dungeon_room.get("_room_lights") as Array):
		var light := value as WastelandLight3D
		if light == null:
			continue
		light.set_meta("authored_room_device", "ceiling_light")
		_graft_static_device(light, root_owner)
		light_count += 1
	var light_switch := dungeon_room.get("_light_switch") as RoomLightSwitch3D
	if light_switch != null:
		light_switch.set_meta("authored_room_device", "wall_switch")
		_graft_static_device(light_switch, root_owner)
	if light_count == 0 or light_switch == null:
		# 名单里声明了「本房自持设备」，运行时却拿不出灯或开关 ⇒ 生成出来的静态场景
		# 会缺件、运行时又因为 `authored_devices` 分支跳过自建 ⇒ 房间永远没灯。
		# 这种静默半成品必须硬失败。
		_fail("%s 在 AUTHORED_DEVICE_ROOMS 里，但运行时没有灯/开关可固化（灯 %d 盏、开关 %s）" % [
			dungeon_room.room_id, light_count, str(light_switch != null),
		])
		return
	root_owner.set_meta("authored_room_devices", true)
	print("AUTHORED_ROOM_DEVICES room=%s lights=%d switch=%s" % [
		dungeon_room.room_id, light_count, light_switch.name,
	])


## 把运行时设备节点搬进静态场景。
##
## 两个坐标系要换算一层：设备在运行时挂在 `RuntimeDetail` 下（房内局部），静态场景的
## 子节点则是「静态艺术根局部」。`root_owner.transform` 已按原逻辑取成艺术根的 transform，
## 所以取逆乘一次即可 —— 艺术根是单位阵时（当前 13 房）逐字不变。
##
## owner **只设在设备根上**：运行时自建的灯罩 / 灯管 / 交互球 owner 保持空 ⇒ 不会被写进
## 房型 TSCN。编辑器里看到的仍是可手调的实例根，而不是一堆展开的死几何；
## 运行时 `WastelandLight3D._ready()` / `RoomLightSwitch3D._build_visual()` 照常自建。
func _graft_static_device(device: Node3D, root_owner: Node3D) -> void:
	var previous_parent := device.get_parent()
	if previous_parent != null:
		previous_parent.remove_child(device)
	device.transform = root_owner.transform.affine_inverse() * device.transform
	root_owner.add_child(device)


func _add_safe_room_door_previews(room: DungeonRoom3D, root_owner: Node3D) -> void:
	for direction in room.doors:
		var runtime_door := room.get_door_node(str(direction)) as Node3D
		if runtime_door == null:
			_fail("start 缺少运行时门 %s，无法生成静态预览" % str(direction))
			continue
		var preview := TOWER_DOOR_LEAF_PREFAB.instantiate() as Node3D
		if preview == null:
			_fail("start 门扇预览 prefab 实例化失败 (%s)" % str(direction))
			continue
		preview.name = "DoorLeafPreview_%s" % str(direction).capitalize()
		preview.transform = root_owner.transform.affine_inverse() * runtime_door.transform
		preview.set_meta("editor_preview_only", true)
		preview.set_meta("runtime_hidden", true)
		preview.set_meta("door_direction", str(direction))
		root_owner.add_child(preview)


func _fail(message: String) -> void:
	failures.append(message)
