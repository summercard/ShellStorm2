extends Node
## 第二只正式精英「夺械者“收租人”」：正式资产目录、18 剪辑动画母版、状态机接线
## 与碰撞归属。
##
## 为什么单独一篇而不是塞进 `verify_first_elite_deployment_flow`：
## 那篇管的是**首只**的投放窗口与名册解耦；本资产引入了两个首只没有的东西 ——
## **真骨骼动画**（41 骨 / 18 剪辑，首只是纯静态 0 骨）和**精英表现层的状态驱动**
## （首只不需要、本只要）。这两件事各有独立的失败模式，混在一起会互相掩盖。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const ELITE_SLUG := "enm_elite_arms_taker"
## 路径直接写全字面量，**不要**用 `%` 拼接 —— GDScript 的 `const` 必须是常量表达式，
## `"...%s..." % [a, b]` 会在解析期报 "isn't a constant expression"，
## 而报错发生在 parse 阶段 ⇒ 场景加载失败、`quit()` 永不执行 ⇒ 表现为"验收卡死"。
const ELITE_SCENE := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
const ELITE_GLB := "res://assets/art/enemies/elite_3d/enm_elite_arms_taker/components/enm_elite_arms_taker/enm_elite_arms_taker_visual_top3d.glb"
const ASSET_ID := "ENM-ELITE-ARMS-TAKER-3D"
const TEMP_SAVE := "user://verification_second_elite.json"
## 18 条动作的权威名单与时长（秒）。逐字取自美术源的《状态机动画清单》。
##
## ⚠ 这里是**硬编码的绝对值钉子**：只断言"实现 ↔ 自己的表自洽"是不够的
## —— 把某条时长改坏、实现跟着改，两边仍自洽而测试照样绿。
const CLIP_DURATIONS := {
	"idle": 5.300, "walk": 1.433, "run": 0.867,
	"turn_left": 1.333, "turn_right": 1.333,
	"attack_light": 2.667, "attack_heavy": 1.100, "attack_jump": 3.700,
	"block": 1.333, "dodge": 1.633, "hit": 2.000,
	"stagger": 4.933, "stunned": 2.133, "death": 4.600,
	"spawn_standup": 3.100, "roar": 5.400, "kneel": 4.267, "slam": 7.567,
}
## `Enemy3D.VALID_STATES` 的 12 态，逐字取自代码。每个状态都必须能落到一条真剪辑。
const VALID_STATES := [
	"dormant", "idle", "patrol", "alert", "chase", "search", "return",
	"telegraph", "attack", "recovery", "stagger", "dead",
]
## 骨架骨数。源模型 41 骨；骨架一致性已在合并阶段断言过，这里再钉一次运行时可读值。
const BONE_COUNT := 41


func _ready() -> void:
	var failures: Array[String] = []
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	BaseManager.save_path = TEMP_SAVE
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()

	_check_catalog(failures)
	_check_asset_layout(failures)
	_check_animation_master(failures)
	_check_deployment_window(failures)
	_check_runtime_wiring(failures)

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
	if failures.is_empty():
		print("SECOND_ELITE_ARMS_TAKER_OK: catalog/layout, 18-clip animation master, state machine wiring and collision ownership pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 定义存在、是 DEPLOYED、表现字段指向正式资产。
func _check_catalog(failures: Array[String]) -> void:
	var definition := EliteContentCatalog.get_by_id("elite_arms_taker")
	if definition.is_empty():
		failures.append("elite_arms_taker is missing from EliteContentCatalog")
		return
	if str(definition.get("deployment_status", "")) != EliteContentCatalog.DEPLOYED:
		failures.append("elite_arms_taker is not DEPLOYED")
	if str(definition.get("presentation_asset_id", "")) != ASSET_ID:
		failures.append("elite_arms_taker presentation AssetID drifted: %s" % str(definition.get("presentation_asset_id", "")))
	if str(definition.get("presentation_scene", "")) != ELITE_SCENE:
		failures.append("elite_arms_taker presentation scene drifted: %s" % str(definition.get("presentation_scene", "")))
	if str(definition.get("name", "")) != "夺械者“收租人”":
		failures.append("elite_arms_taker display name drifted")
	# 血条：精英档必须 >= 2.0 m 宽（与首只同口径，靠宽度表达"这只不一样"）。
	var bar := definition.get("health_bar_profile", {}) as Dictionary
	if (bar.get("size", Vector2.ZERO) as Vector2).x < 2.0:
		failures.append("elite_arms_taker health bar is narrower than the elite tier")
	if str(bar.get("display_name", "")) != "夺械者“收租人”":
		failures.append("elite_arms_taker health bar has no display name")


## 正式目录：GLB 在 `components/<slug>/`、场景在 `runtime/<slug>/`，且路径不含版本号。
func _check_asset_layout(failures: Array[String]) -> void:
	if not ResourceLoader.exists(ELITE_GLB):
		failures.append("Elite GLB is not at the stable component path: %s" % ELITE_GLB)
	if not ResourceLoader.exists(ELITE_SCENE):
		failures.append("Elite scene is not at the stable runtime path: %s" % ELITE_SCENE)
	for path in [ELITE_GLB, ELITE_SCENE]:
		var base := String(path).get_file()
		if base.contains("_v0") or base.contains("_v1") or base.contains("_v2"):
			failures.append("Runtime asset path illegally carries a version suffix: %s" % path)
	# 场景里不得有玩法碰撞（表现资产）。
	var scene := load(ELITE_SCENE) as PackedScene
	if scene == null:
		failures.append("Elite PackedScene cannot be loaded")
		return
	var root := scene.instantiate() as Node3D
	if root == null:
		failures.append("Elite PackedScene root is not a Node3D")
		return
	if _contains_collision_object(root):
		failures.append("Presentation-only elite scene illegally owns gameplay collision")
	if str(root.get_meta("asset_id", "")) != ASSET_ID:
		failures.append("Elite scene root metadata/asset_id drifted")
	if str(root.get_meta("content_id", "")) != "elite_arms_taker":
		failures.append("Elite scene root metadata/content_id drifted")
	root.queue_free()


## 动画母版：18 条 clip、名字与时长对源清单、骨架 41 骨。
func _check_animation_master(failures: Array[String]) -> void:
	if not ResourceLoader.exists(ELITE_GLB):
		return
	var packed := load(ELITE_GLB) as PackedScene
	if packed == null:
		failures.append("Elite GLB cannot be instantiated as a PackedScene")
		return
	var root := packed.instantiate()
	var player := _find_first(root, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(root, "Skeleton3D") as Skeleton3D
	if player == null:
		failures.append("Elite GLB has no AnimationPlayer (18 clips were not merged)")
		root.queue_free()
		return
	if skeleton == null:
		failures.append("Elite GLB has no Skeleton3D")
		root.queue_free()
		return
	if skeleton.get_bone_count() != BONE_COUNT:
		failures.append("Elite skeleton bone count drifted: %d != %d" % [skeleton.get_bone_count(), BONE_COUNT])
	var listed := player.get_animation_list()
	var missing: Array[String] = []
	for clip_name in CLIP_DURATIONS.keys():
		if not listed.has(clip_name):
			missing.append(str(clip_name))
	if not missing.is_empty():
		failures.append("Elite animation master is missing clips: %s" % str(missing))
	# 多余 clip 同样是缺陷：源里 slam.glb 自带一条 Blender 默认名 clip
	# （`ArmatureAction`），合并时若没清掉就会一起进来。
	var extra: Array[String] = []
	for clip_name in listed:
		if not CLIP_DURATIONS.has(str(clip_name)):
			extra.append(str(clip_name))
	if not extra.is_empty():
		failures.append("Elite animation master carries stray clips: %s" % str(extra))
	# 时长逐条对源清单，容差 1 帧（1/24 s）。
	for clip_name in CLIP_DURATIONS.keys():
		if not listed.has(clip_name):
			continue
		var animation := player.get_animation(str(clip_name))
		var want := float(CLIP_DURATIONS[clip_name])
		if absf(animation.length - want) > 1.0 / 24.0 + 1e-3:
			failures.append("Clip %s duration drifted: %.3f vs %.3f" % [str(clip_name), animation.length, want])
	root.queue_free()


## 投放窗口：94/93/92 层、每局按种子三选一、不侵入 95F Boss 层与首只的 98-96 窗口。
func _check_deployment_window(failures: Array[String]) -> void:
	for floor_number in [94, 93, 92]:
		var eligible := EliteContentCatalog.get_deployable_for_floor(floor_number)
		var ids: Array[String] = []
		for definition in eligible:
			ids.append(str(definition.get("elite_id", "")))
		if ids != ["elite_arms_taker"]:
			failures.append("Floor %d eligible set drifted: %s" % [floor_number, str(ids)])
	# 与首只的窗口不得重叠：98-96 上只能有首只。
	for floor_number in [98, 97, 96]:
		for definition in EliteContentCatalog.get_deployable_for_floor(floor_number):
			if str(definition.get("elite_id", "")) == "elite_arms_taker":
				failures.append("elite_arms_taker leaked into the first elite's 98-96 window")
	if not EliteContentCatalog.get_deployable_for_floor(95).is_empty():
		failures.append("elite_arms_taker leaked into the 95F boss floor")
	# 每局三选一：30 个种子必须覆盖到全部三层。
	var selected: Dictionary = {}
	for seed_value in range(30):
		selected[EliteContentCatalog.get_selected_floor_for_seed("elite_arms_taker", seed_value)] = true
	if selected.size() != 3:
		failures.append("Run seeds do not distribute elite_arms_taker across all three eligible floors")


## 运行时接线：真实例化一次，断言表现层确实带状态机、12 态全部有剪辑可播、
## 且表现资产没有改掉玩法碰撞。
func _check_runtime_wiring(failures: Array[String]) -> void:
	var injector := MonsterInjector.new()
	var seed_value := _seed_for_floor(93, 931000)
	injector.set_seed(seed_value)
	var generated := injector.generate_enemies({
		"type":"elite", "floor":2, "floor_level":RoomData.FloorLevel.MEDIUM,
		"floor_number":93, "encounter_id":"second_elite:93:random_room", "seed":seed_value,
	})
	if generated.size() != 1:
		failures.append("93F did not generate the second deployed elite")
		return
	var config := generated[0]
	if str(config.get("elite_id", "")) != "elite_arms_taker":
		failures.append("93F generated the wrong elite identity: %s" % str(config.get("elite_id", "")))
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy)
	enemy.configure_from_enemy_data(config)
	var snapshot := enemy.get_state_snapshot()
	var components := snapshot.get("component_snapshot", {}) as Dictionary
	if not bool(components.get("formal_elite_asset", false)):
		failures.append("EnemyAvatar3D did not load the elite PackedScene")
	if str(components.get("elite_presentation_asset_id", "")) != ASSET_ID:
		failures.append("Elite presentation AssetID was not preserved at runtime")
	# 表现层必须是**真骨骼动画**：有 18 条 clip 且暴露 sync_state。
	var presentation := components.get("elite_presentation", {}) as Dictionary
	if presentation.is_empty():
		failures.append("Elite presentation snapshot is empty (state machine not wired)")
	else:
		if int(presentation.get("clip_count", 0)) != CLIP_DURATIONS.size():
			failures.append("Elite presentation exposes %d clips, expected %d" % [
				int(presentation.get("clip_count", 0)), CLIP_DURATIONS.size(),
			])
		if int(presentation.get("bone_count", 0)) != BONE_COUNT:
			failures.append("Elite presentation bone count drifted: %d" % int(presentation.get("bone_count", 0)))
		if bool(presentation.get("procedural_pose", true)):
			failures.append("Elite presentation is reported as procedural pose, expected skeletal")
	# 12 态逐态驱动：每一态都必须能落到一条**真实存在**的剪辑上，
	# 且落地剪辑不能是空名（空名会让 AnimationPlayer 静默不播 = 僵在 bind pose）。
	var player := _find_first(enemy, "AnimationPlayer") as AnimationPlayer
	if player == null:
		failures.append("Runtime elite has no AnimationPlayer to drive")
	else:
		for state in VALID_STATES:
			var elite_root := _find_formal_elite(enemy)
			if elite_root == null:
				failures.append("Runtime elite presentation root is missing")
				break
			elite_root.call("sync_state", state, 0.0, 0.0, 0.5, 0.5, 1.5)
			var clip := str(
				(elite_root.call("get_presentation_snapshot") as Dictionary).get("clip", "")
			)
			if clip.is_empty() or not CLIP_DURATIONS.has(clip):
				failures.append("State %s resolves to an unknown clip: '%s'" % [str(state), clip])
	# 玩法碰撞必须仍是基类 `melee_chaser` 的脚印 —— 表现资产不得改碰撞。
	var collision := snapshot.get("collision_profile", {}) as Dictionary
	var base_footprint := EnemyAvatar3D.get_footprint_profile("melee_chaser")
	if not is_equal_approx(float(collision.get("radius", 0.0)), float(base_footprint.get("radius", -1.0))):
		failures.append("Presentation asset changed the gameplay collision radius")
	# In-place conversion must edit an instance library, never the cached imported clip.
	var raw_scene := load(ELITE_GLB) as PackedScene
	var raw_root := raw_scene.instantiate()
	var raw_player := _find_first(raw_root, "AnimationPlayer") as AnimationPlayer
	var runtime_player := _find_first(enemy.avatar._formal_elite_root, "AnimationPlayer") as AnimationPlayer
	for clip_name in ["walk", "run"]:
		var source_animation := raw_player.get_animation(clip_name)
		var runtime_animation := runtime_player.get_animation(clip_name)
		if source_animation == runtime_animation:
			failures.append("In-place animation is shared with imported source: " + clip_name)
		for track in source_animation.get_track_count():
			var track_path := source_animation.track_get_path(track)
			if source_animation.track_get_type(track) != Animation.TYPE_POSITION_3D \
					or track_path.get_subname_count() == 0 or str(track_path.get_subname(0)) != "Hip":
				continue
			var end := source_animation.track_get_key_count(track)-1
			var source_first: Vector3 = source_animation.track_get_key_value(track,0)
			var source_last: Vector3 = source_animation.track_get_key_value(track,end)
			var runtime_first: Vector3 = runtime_animation.track_get_key_value(track,0)
			var runtime_last: Vector3 = runtime_animation.track_get_key_value(track,end)
			if source_first.distance_to(source_last) < 0.9 or runtime_first.distance_to(runtime_last) > 0.00001:
				failures.append("Root-motion source/runtime isolation failed: " + clip_name)
	raw_root.free()
	EliteRosterService.settle(
		str(snapshot.get("elite_id", "")),
		str(snapshot.get("elite_encounter_instance_id", "")),
		"despawned"
	)
	enemy.queue_free()


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


func _contains_collision_object(root: Node) -> bool:
	if root is CollisionObject3D or root is CollisionShape3D:
		return true
	for child in root.get_children():
		if _contains_collision_object(child):
			return true
	return false


func _seed_for_floor(floor_number: int, start: int) -> int:
	for seed_value in range(start, start + 400):
		if EliteContentCatalog.get_selected_floor_for_seed("elite_arms_taker", seed_value) == floor_number:
			return seed_value
	return start
