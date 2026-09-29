extends Node
## 探针（**只读、不断言**）：把远征01 全部 13 房的「中央顶灯 / 墙面开关」运行时真值原样 dump 出来。
##
## 用途：`scripts/patch_expedition01_room_authored_devices.py` 的 `ROOMS` 表需要手抄真值，
## 而 `probe_expedition_room_authored_light_devices` 只跑 `AUTHORED_DEVICE_ROOMS` 名单里的房间
## —— 尚未迁移的房间在它那里根本不会出现。本探针固定遍历生成器的 `ROOM_IDS`（13 房），
## 把**尚未迁移**的房间也一并 dump，供批量迁移使用。
##
## 与正式探针的关键口径差异（**别混用**）：
##   · 正式探针断言「静态根下必须有设备」；本探针只打印，`_room_lights` 为空的房也照样列出；
##   · 本探针额外打印 **`art_local_tf`** —— 设备相对**艺术根**的 transform。
##     写进 TSCN 的就是这个值：运行时 TSCN 根会被改名成 `AuthoredLayoutArtRoot`
##     （`DungeonRoom3D.gd` 载入静态布局后 `static_layout.name = "AuthoredLayoutArtRoot"`），
##     设备在文件里是 `parent="."` 的直挂子节点 ⇒ 需要的是艺术根局部坐标，而不是
##     `RuntimeDetail` 局部坐标（未迁移的灯就挂在 `RuntimeDetail` 下，直接抄 `light.transform` 会错）。
##
## 运行：
##   export APPDATA='D:\ssverif\appdata_devices_dump'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://tests/verification/probe_expedition_room_device_dump.tscn

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const STATIC_SCENE_GENERATOR := preload("res://scripts/generate_expedition01_room_static_scenes.gd")
const RUN_SEED := 77001199
const STATIC_ROOT_NAMES: Array[String] = ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		print("DUMPX_FAIL 运行时没有 Blocks/Expedition")
		get_tree().quit(1)
		return
	var authored := STATIC_SCENE_GENERATOR.AUTHORED_DEVICE_ROOMS
	var room_ids: Array[String] = STATIC_SCENE_GENERATOR.ROOM_IDS
	var with_devices := 0
	for room_id in room_ids:
		var room := block.get_node_or_null(room_id) as DungeonRoom3D
		if room == null:
			print("DUMPX_MISSING room=%s" % room_id)
			continue
		if await _dump_room(room, authored.has(room_id)):
			with_devices += 1
	print("")
	print("DUMPX_DONE rooms=%d with_light_and_switch=%d" % [room_ids.size(), with_devices])
	get_tree().quit(0)


## 返回 true 表示本房运行时确实产出了「至少一盏灯 + 一个开关」。
func _dump_room(room: DungeonRoom3D, already_authored: bool) -> bool:
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle()
	var art_root := _static_root(room)
	var dimensions: Vector2 = room.call("get_dimensions")
	print("DUMPX room=%s room_type=%s size_class=%s dims=(%.3f,%.3f) already_authored=%s" % [
		room.room_id, str(room.get("room_type")), str(room.get("size_class")),
		dimensions.x, dimensions.y, str(already_authored),
	])
	if art_root == null:
		print("DUMPX room=%s art_root=<none>" % room.room_id)
		return false
	print("DUMPX room=%s art_root=%s art_tf=%s" % [
		room.room_id, art_root.name, var_to_str(art_root.transform),
	])
	var inverse := art_root.global_transform.affine_inverse()
	var lights: Array = room.get("_room_lights") as Array
	var switch := room.get("_light_switch") as RoomLightSwitch3D
	var central := room.get("_central_light") as WastelandLight3D
	for index in range(lights.size()):
		var light := lights[index] as WastelandLight3D
		if light == null:
			continue
		var parent := light.get_parent()
		var art_local := inverse * light.global_transform
		print("DUMPX room=%s light i=%d name=%s parent=%s central=%s" % [
			room.room_id, index, light.name,
			parent.name if parent != null else "<none>",
			str(central == light),
		])
		print("DUMPX room=%s light_tf i=%d tf=%s" % [
			room.room_id, index, var_to_str(art_local),
		])
		print("DUMPX room=%s light_params i=%d color=%s energy=%s range=%s failing=%s seed=%d shadow=%s style=%s enabled=%s cull_mask=%s" % [
			room.room_id, index,
			var_to_str(light.light_color), var_to_str(light.energy), var_to_str(light.light_range),
			str(light.failing), light.flicker_seed, str(light.cast_shadow),
			str(light.fixture_style), str(light.light_enabled), str(light.light_cull_mask),
		])
	if switch == null:
		print("DUMPX room=%s switch=<none> light_count=%d" % [room.room_id, lights.size()])
		return false
	var switch_tf := inverse * switch.global_transform
	print("DUMPX room=%s switch name=%s parent=%s light_on=%s" % [
		room.room_id, switch.name,
		str((switch.get_parent() as Node).name) if switch.get_parent() != null else "<none>",
		str(switch.is_light_on()),
	])
	print("DUMPX room=%s switch_tf tf=%s" % [room.room_id, var_to_str(switch_tf)])
	return not lights.is_empty()


func _static_root(room: DungeonRoom3D) -> Node3D:
	for candidate in STATIC_ROOT_NAMES:
		var found := room.get_node_or_null(candidate) as Node3D
		if found != null:
			return found
	return null


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
