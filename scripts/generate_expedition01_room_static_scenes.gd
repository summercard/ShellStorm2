extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const TOWER_DOOR_LEAF_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn"
)
const RUN_SEED := 77001199
const OUTPUT_ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01"
const ROOM_IDS := [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]

var failures: Array[String] = []

func _ready() -> void:
	var previous_static_layout_mode: bool = ROOM_SCRIPT.use_expedition_static_layout_scenes
	ROOM_SCRIPT.use_expedition_static_layout_scenes = false
	var tower := EXPEDITION_SCENE.instantiate()
	if tower == null:
		_fail("远征01场景无法实例化")
	else:
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
			for room_id in ROOM_IDS:
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
		print("EXPEDITION01_STATIC_SCENES_WRITTEN rooms=%d" % ROOM_IDS.size())
		get_tree().quit(0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)

func _generate_live_room(room_id: String, room: Node3D) -> void:
	var dungeon_room := room as DungeonRoom3D
	if dungeon_room == null:
		_fail("%s 不是 DungeonRoom3D" % room_id)
		return
	dungeon_room.ensure_shell_built()
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
	root_owner.set_meta("dynamic_runtime_owned", ["RoomDoor3D", "RoomTrigger", "RuntimeDetail", "NavigationRegion3D"])
	var move: Array[Node] = []
	for child in static_root.get_children():
		move.append(child)
	for child in move:
		static_root.remove_child(child)
		root_owner.add_child(child)
	if room_id == "start":
		_add_safe_room_door_previews(dungeon_room, root_owner)
	# 房间场景只拥有顶层 prefab 实例根；组件内部 owner 保持原 PackedScene 边界。
	# 递归改 owner 会把 ImportedModel/Mesh/Collision 全部展开进房间 TSCN，
	# 既破坏 prefab 可编辑边界，也会在退出时造成大规模 3D RID 泄漏。
	for child in root_owner.get_children():
		child.owner = root_owner
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
