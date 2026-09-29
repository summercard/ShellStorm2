extends Node
## 诊断：自持开关与门位净空盒的相对位置（判定「开关是否真的落在门洞里」）。
##
## 门洞净空盒（与 verify_expedition_room_type_component_replay::_check_door_aperture 同一口径）：
##   沿墙轴 |along| ≤ 1.05、法向 |normal| ≤ 0.4、竖直 y ∈ [0.15, 2.35]。
## `lane` 与 `switch.position` **同为艺术根局部** ⇒ 可直接相减，无需再换算。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199
const APERTURE_HALF_ALONG := 1.05
const APERTURE_HALF_NORMAL := 0.4
const TARGETS: Array[String] = [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]
const STATIC_ROOT_NAMES: Array[String] = ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	for room_id in TARGETS:
		var room := block.get_node_or_null(room_id) as DungeonRoom3D
		if room == null:
			print("DIAG_FATAL 缺少房间 %s" % room_id)
			continue
		room.ensure_shell_built()
		room.ensure_detail_built()
		await _settle()
		var art: Node3D = null
		for name in STATIC_ROOT_NAMES:
			art = room.get_node_or_null(name) as Node3D
			if art != null:
				break
		var sw := room.get("_light_switch") as RoomLightSwitch3D
		if art == null or sw == null:
			print("DIAG room=%s art=%s switch=%s" % [room_id, str(art != null), str(sw != null)])
			continue
		for direction_value in room.doors:
			var direction := str(direction_value)
			var door := room.get_door_node(direction) as Node3D
			if door == null:
				continue
			var lane: Vector3 = art.global_transform.affine_inverse() * door.global_position
			var delta: Vector3 = sw.position - lane
			var along := absf(delta.x) if direction in ["north", "south"] else absf(delta.z)
			var normal := absf(delta.z) if direction in ["north", "south"] else absf(delta.x)
			var in_box := along <= APERTURE_HALF_ALONG and normal <= APERTURE_HALF_NORMAL
			print("DIAG room=%s door=%-5s lane=%s switch=%s | along=%.3f (<=1.05) normal=%.3f (<=0.4) => 开关本体%s门洞" % [
				room_id, direction, var_to_str(lane), var_to_str(sw.position),
				along, normal, "落在" if in_box else "不在",
			])
			# 交互球：中心 = 开关位置 + 局部 up × 0.9，半径 2.2 ⇒ 到门洞中心的平面距离
			var flat := Vector2(delta.x, delta.z).length()
			print("DIAG room=%s door=%-5s 开关平面距门洞中心=%.3f，交互球半径 2.2 => 球%s够到门洞带" % [
				room_id, direction, flat, "" if flat > 2.2 + 0.4 else "**",
			])
	get_tree().quit(0)


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
