extends Node
## 「夺械者”收租人“」状态机的**真实运行**探针。
##
## 与 `verify_second_elite_arms_taker` 的分工：那篇是**逻辑断言**（目录、剪辑表、
## 定义字段、碰撞归属），跑在一次 `_ready` 里、不推进时间。本篇是**真的把怪放进
## 场景树、让 `_process` 跑起来**，逐态确认 `AnimationPlayer` 真的在换段、
## 采样点在动、骨骼姿势真的在变 —— 也就是排除"表全对、实际一动不动"这类假绿。
##
## 为什么必须另开一篇：`AnimationPlayer.set_callback_mode_process(MANUAL)` 下，
## 不推进引擎时间就不会动；而"表里 clip 名对得上"完全可以在静止状态下成立。
## 本轮实测踩到的 `playback_speed` 写错就是这个形态 —— 逻辑断言查不出来。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const TEMP_SAVE := "user://probe_second_elite_motion.json"
## 逐态采样：每态推进这么多帧，看骨骼姿势是否真的发生了变化。
const FRAMES_PER_STATE := 60
const VALID_STATES := [
	"dormant", "idle", "patrol", "alert", "chase", "search", "return",
	"telegraph", "attack", "recovery", "stagger", "dead",
]


func _ready() -> void:
	var failures: Array[String] = []
	await get_tree().process_frame
	await _run(failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
	if failures.is_empty():
		print("SECOND_ELITE_MOTION_OK: all 12 authoritative context routes and authored bone samples pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()

	var injector := MonsterInjector.new()
	var seed_value := _seed_for_floor(92, 921000)
	injector.set_seed(seed_value)
	var generated := injector.generate_enemies({
		"type":"elite", "floor":2, "floor_level":RoomData.FloorLevel.MEDIUM,
		"floor_number":92, "encounter_id":"probe_second_elite:92:motion", "seed":seed_value,
	})
	if generated.size() != 1:
		failures.append("92F did not generate the second elite for the motion probe")
		return
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy)
	enemy.configure_from_enemy_data(generated[0])
	# 等两帧：GLB 实例化后骨架/AnimationPlayer 需要一帧才解析完成
	# （与 `verify_strong_variant_eye_glow` 同一坑：同帧读到的骨骼姿势是未解析的零值）。
	await get_tree().process_frame
	await get_tree().process_frame

	var elite_root := _find_formal_elite(enemy)
	if elite_root == null:
		failures.append("Elite presentation root missing in the motion probe")
		enemy.queue_free()
		return
	var player := _find_first(elite_root, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(elite_root, "Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		failures.append("Elite presentation has no AnimationPlayer/Skeleton3D to probe")
		enemy.queue_free()
		return
	enemy.set_physics_process(false)

	for state in VALID_STATES:
		# Check the formal Enemy3D -> action context -> avatar route before inspecting clips.
		enemy.transition_to(state)
		enemy._process(0.0)
		var routed: Dictionary = elite_root.call("get_presentation_snapshot")
		if str(routed.get("state", "")) != state:
			failures.append("Formal action context did not reach presentation state: " + str(state))
		# 逐态驱动：每态先喂一次 sync_state，再推若干帧，看骨骼是否在动。
		var poses: Array[float] = []
		var initial_rotations: Array[Quaternion] = []
		for bone in skeleton.get_bone_count():
			initial_rotations.append(skeleton.get_bone_pose_rotation(bone))
		for frame in range(FRAMES_PER_STATE):
			elite_root.call("sync_state", state, float(frame)/60.0, 3.0, 0.5, 0.5, 4.0)
			elite_root.call("_process", 1.0 / 60.0)
			# Measure every authored bone; summed Euler magnitudes can cancel each other.
			var fingerprint := 0.0
			for bone_index in skeleton.get_bone_count():
				fingerprint = maxf(fingerprint,initial_rotations[bone_index].angle_to(skeleton.get_bone_pose_rotation(bone_index)))
			poses.append(fingerprint)
		var clip := str(
			(elite_root.call("get_presentation_snapshot") as Dictionary).get("clip", "")
		)
		if clip.is_empty():
			failures.append("State %s produced no clip at runtime" % str(state))
			continue
		if not player.has_animation(clip):
			failures.append("State %s drove a clip that does not exist: '%s'" % [str(state), clip])
			continue
		# 静止类状态（dormant）允许姿势不变；其余状态必须真的在动。
		var spread: float = poses.max() - poses.min()
		if state != "dormant" and spread < 0.0005:
			failures.append(
				"State %s did not move any bone (spread=%.6f, clip=%s)" % [str(state), spread, clip]
			)

	EliteRosterService.settle(
		str(enemy.get_state_snapshot().get("elite_id", "")),
		str(enemy.get_state_snapshot().get("elite_encounter_instance_id", "")),
		"despawned"
	)
	enemy.queue_free()
	BaseManager.save_path = original_path
	BaseManager.data = original_data


func _find_formal_elite(root: Node) -> Node:
	if root.name.begins_with("FormalElite_"):
		return root
	for child in root.get_children():
		var found := _find_formal_elite(child)
		if found != null:
			return found
	return null


func _find_first(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _seed_for_floor(floor_number: int, start: int) -> int:
	for seed_value in range(start, start + 400):
		if EliteContentCatalog.get_selected_floor_for_seed("elite_arms_taker", seed_value) == floor_number:
			return seed_value
	return start
