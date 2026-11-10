extends Node
## 真实远征01：家具构建后测量主层安全容量、玩家距离与跨批占位。
## 结果是几何证据，不代替 Host/Director 的派发与回滚专项。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const PROBE_MAX_COUNT := 64
const ROOM_KEYS: Array[String] = [
	"room_03", "room_04", "room_06", "room_09", "room_10",
]

var tower: TowerDescent3D
var failures: Array[String] = []


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	# 资源预热/远征装配可能跨帧；只等待明确条件，最多60秒，不循环重开工程。
	var deadline := Time.get_ticks_msec() + 60000
	while not tower._room_by_id.has("room_10") and Time.get_ticks_msec() < deadline:
		if tower._expedition_bootstrap_failed:
			push_error("远征规划/初始化失败，容量探针停止；不把缺房当作安全容量结论")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	await get_tree().physics_frame
	print("ENCOUNTER_PROBE_ROOM_IDS=%s" % str(tower._room_by_id.keys()))
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for key in ROOM_KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			failures.append("缺少房间：%s" % key)
			continue
		_probe_room(room)
	for failure in failures:
		push_error(failure)
	print("ENCOUNTER_SPAWN_CAPACITY_PROBE_DONE failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _probe_room(room: DungeonRoom3D) -> void:
	# 所有参数为世界坐标，房心仅作玩家测试位，不作刷怪兜底。
	var player_world := room.to_global(Vector3.ZERO)
	for minimum in [0.0, 6.0, 8.0]:
		var occupied: Array[Vector3] = []
		var capacity := 0
		for index in PROBE_MAX_COUNT:
			# 每次独立查询都携带前批存活+本批已选，不再依赖 index=0 重置。
			var selection := room.choose_safe_spawn_position(player_world, minimum, occupied)
			if not bool(selection.get("ok", false)):
				break
			var point: Vector3 = selection["position"]
			if not room.is_safe_spawn_position_valid(point, player_world, minimum, occupied):
				failures.append("%s min=%.1f index=%d 选点与校验不一致" % [room.room_id, minimum, index])
				break
			occupied.append(point)
			capacity += 1
		if capacity == 0:
			failures.append("%s min=%.1f 无安全点" % [room.room_id, minimum])
		print("%s|dim=%s|min=%.1f|capacity=%d|world_transform=%s" % [
			room.room_id, str(room.get_dimensions()), minimum, capacity, str(room.global_transform),
		])
	# 授权盒候选不能偷偷回退全房；空域必须失败。
	var empty_domain := room.choose_safe_spawn_position(player_world, 6.0, [], [])
	if bool(empty_domain.get("ok", false)):
		failures.append("%s 空授权盒域错误扩展到全房" % room.room_id)
