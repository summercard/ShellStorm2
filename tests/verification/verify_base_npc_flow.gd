extends Node
## 验收入口：99F 基地 NPC（`BASE-NPC`）。
##
## 覆盖范围（每条失败单独报错，不合并）：
##   A01–A05 真实 99F 基地接入与内容目录；A06–A14b 模型/全绿/面饰/落地/体型同口径/头顶分层/无自发光；
##   A15–A18 巡逻与朝向；A19 净空；A20–A25b 交互半径/提示/白点退役/搭话定住与转向/对话推进收起/恢复巡逻；
##   A26 塔楼只读投影。
##
## ⚠️ 场景口径：**必须加载 `TowerDescent3D.tscn`**，不是 `BaseWorld3D.tscn`。
##   前者是正式 99F 基地（`facility` 房间），后者是旧的"基地与荒野"兼容场景
##   —— 2026-11-02 第一版就装错了地方，截图背景是破败公路而不是基地内部。
##
## 不覆盖：真实渲染观感（需真实渲染器，见 `capture_base99_npc.gd`）。

const NPC_ID := "npc_base99_green"
const NPC_NODE_NAME := "BaseNpc99F"
## 玩家场景（不含版本号）。NPC 与玩家共用同一份模型，验收也按同一入口取几何，
## 不另外引用 `*_vNNN.tscn` —— 运行资产命名门禁对测试脚本同样适用。
const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const GREEN_MIN := 0.55
const GREEN_OVER_RED := 0.30
const GREEN_OVER_BLUE := 0.20
## 99F 基地地面高度（`TowerDescent3D.FLOOR_HEIGHT` 的负值）。
const BASE99_FLOOR_Y := -12.0
## 与任何设施的最小净距：NPC 交互半径 2.4m，小于这个值会与设施抢交互候选。
const FACILITY_CLEARANCE_M := 2.4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	await _run(failures)
	_finish(failures)


func _run(failures: Array[String]) -> void:
	# —— A01 载入正式 99F 基地 ——
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if packed == null:
		failures.append("A01 TowerDescent3D scene does not load")
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var rooms := tower.get("_room_by_id") as Dictionary
	var facility_room := rooms.get("facility") as DungeonRoom3D
	if facility_room == null:
		failures.append("A01 99F base room 『facility』 was not built")
		_finish_now(tower, failures)
		return

	# —— A02 接入个数与归属：必须在 99F 基地里，不能装在旧兼容场景 ——
	var npc_count := tower.get_npc_count()
	if npc_count != 1:
		failures.append("A02 99F base should host exactly 1 NPC, actual %d" % npc_count)
	var npc := tower.find_npc(NPC_ID)
	if npc == null:
		failures.append("A02 TowerDescent3D does not expose NPC 『%s』" % NPC_ID)
		_finish_now(tower, failures)
		return
	if not facility_room.is_ancestor_of(npc):
		failures.append("A02 NPC is not inside the 99F base room")
	var parent := npc.get_parent()
	if parent == null or parent.name != "Art":
		failures.append("A02 NPC is not attached to the base art layout (parent=%s)" % (str(parent.name) if parent != null else "<none>"))
	var legacy := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	if legacy != null:
		var legacy_root := legacy.instantiate()
		if legacy_root.get_node_or_null(NPC_NODE_NAME) != null:
			failures.append("A02 the legacy BaseWorld3D hub still carries an NPC (it must live only in the real 99F base)")
		legacy_root.free()

	# —— A03/A04 内容目录 ——
	if npc.npc_id != NPC_ID:
		failures.append("A03 NPC id mismatch: %s" % npc.npc_id)
	if not NpcCatalog.has_npc(NPC_ID):
		failures.append("A03 NpcCatalog is missing 『%s』" % NPC_ID)
	if npc.get_display_name() != NpcCatalog.get_display_name(NPC_ID):
		failures.append("A04 NPC display name does not follow the catalog: %s" % npc.get_display_name())
	if npc.get_role().is_empty():
		failures.append("A04 NPC role is empty")

	# —— A05 台词 ——
	var lines := NpcCatalog.get_lines(NPC_ID)
	if lines.size() < 3:
		failures.append("A05 NPC has too few dialogue lines: %d" % lines.size())
	for index in lines.size():
		if str(lines[index]).strip_edges().is_empty():
			failures.append("A05 NPC line %d is empty" % index)
	var unique := {}
	for line in lines:
		unique[line] = true
	if unique.size() != lines.size():
		failures.append("A05 NPC dialogue lines contain duplicates")

	# —— A06 模型：必须是玩家 bunny01 几何 ——
	var visual := npc.get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		failures.append("A06 NPC has no VisualRoot (model missing)")
		_finish_now(tower, failures)
		return
	for rig_path in ["BunnyRig/BodyJoint", "BunnyRig/HeadJoint", "BunnyRig/FeetRoot/FootJointL", "BunnyRig/FeetRoot/FootJointR"]:
		if visual.get_node_or_null(rig_path) == null:
			failures.append("A06 NPC model is not the player bunny rig, missing %s" % rig_path)

	# —— A07 可见网格 ——
	var visible_meshes: Array[MeshInstance3D] = []
	var aabb := AABB()
	var has_aabb := false
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.is_visible_in_tree():
			continue
		visible_meshes.append(mesh_instance)
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if has_aabb:
			aabb = aabb.merge(box)
		else:
			aabb = box
			has_aabb = true
	if visible_meshes.size() < 8:
		failures.append("A07 NPC visible mesh count too low: %d" % visible_meshes.size())

	# —— A08/A09/A10 全绿皮肤：色源必须是衣柜 ——
	var skin := NpcCatalog.get_skin_albedo(NPC_ID)
	var skin_variant := NpcCatalog.get_skin_variant(NPC_ID)
	if skin_variant.is_empty():
		failures.append("A09 NPC skin variant is empty")
	elif not PlayerAvatar3D.has_customization_variant("body", skin_variant):
		failures.append("A09 NPC skin variant 『%s』 is not a wardrobe option" % skin_variant)
	var wardrobe_color := AvatarCustomizationCatalog.get_variant_color(skin_variant)
	if not skin.is_equal_approx(wardrobe_color):
		failures.append("A09 NPC skin color %s does not come from wardrobe variant %s (%s)" % [str(skin), skin_variant, str(wardrobe_color)])
	if not skin.is_equal_approx(PlayerAvatar3D.BODY_COLORS.get(skin_variant, Color.BLACK)):
		failures.append("A09 wardrobe catalog and avatar body color disagree for 『%s』" % skin_variant)
	if skin.g < GREEN_MIN:
		failures.append("A09 wardrobe green channel too low: %.2f" % skin.g)
	if skin.g <= skin.r + GREEN_OVER_RED:
		failures.append("A09 wardrobe variant is not green enough over red: g=%.2f r=%.2f" % [skin.g, skin.r])
	if skin.g <= skin.b + GREEN_OVER_BLUE:
		failures.append("A09 wardrobe variant is not green enough over blue: g=%.2f b=%.2f" % [skin.g, skin.b])

	var shared_material: Material = null
	var body_mesh_count := 0
	var mask_mesh_count := 0
	for mesh_instance in visible_meshes:
		var material := mesh_instance.material_override
		if _is_under_face_mask(mesh_instance):
			mask_mesh_count += 1
			if material != null and material is BaseMaterial3D and (material as BaseMaterial3D).albedo_color.is_equal_approx(skin):
				failures.append("A08 NPC face mask mesh 『%s』 was painted green (the blue eyes would be lost)" % mesh_instance.name)
			continue
		body_mesh_count += 1
		if material == null:
			failures.append("A08 NPC mesh 『%s』 is not skinned (material_override missing)" % mesh_instance.name)
			continue
		if shared_material == null:
			shared_material = material
		elif material != shared_material:
			failures.append("A08 NPC meshes use more than one skin material")
		if material is BaseMaterial3D:
			var albedo := (material as BaseMaterial3D).albedo_color
			if not albedo.is_equal_approx(skin):
				failures.append("A09 NPC mesh 『%s』 albedo %s != wardrobe green %s" % [mesh_instance.name, str(albedo), str(skin)])
	if body_mesh_count < 8:
		failures.append("A08 NPC body mesh count too low: %d" % body_mesh_count)
	if mask_mesh_count < 1:
		failures.append("A08 NPC has no face mask meshes (the head geometry has no eyes of its own)")
	if shared_material != null and shared_material.resource_name != "NPC_GreenSkin":
		failures.append("A10 NPC skin material name is not NPC_GreenSkin: %s" % shared_material.resource_name)

	# —— A11 玩家共享材质未被染色 ——
	var avatar_shell := PLAYER_SCENE.instantiate()
	var player_avatar := avatar_shell.get_node_or_null("Avatar3D")
	var player_visual: Node3D = null
	if player_avatar != null:
		player_visual = player_avatar.get_node_or_null("VisualRoot") as Node3D
	if player_visual != null:
		for node in player_visual.find_children("*", "MeshInstance3D", true, false):
			var player_mesh := node as MeshInstance3D
			if player_mesh == null:
				continue
			if player_mesh.material_override != null:
				failures.append("A11 NPC skinning leaked onto the player avatar (material_override on 『%s』)" % player_mesh.name)
				break
	else:
		failures.append("A11 player scene exposes no Avatar3D/VisualRoot to compare against")
	avatar_shell.free()

	# —— A12/A13 落在 99F 地面上 ——
	var npc_height := 0.0
	if not has_aabb:
		failures.append("A12 NPC has no measurable bounds")
	else:
		var foot_offset := aabb.position.y - npc.global_position.y
		if absf(foot_offset) > 0.06:
			failures.append("A12 NPC bottom is %.3f m off its origin" % foot_offset)
		if absf(aabb.position.y - BASE99_FLOOR_Y) > 0.08:
			failures.append("A12 NPC is not standing on the 99F floor: bottom %.3f vs %.1f" % [aabb.position.y, BASE99_FLOOR_Y])
		npc_height = aabb.end.y - aabb.position.y
		# 资产原尺寸 1.519m（缩放前）→ 乘玩家同一口径的 0.8 后 1.215m。
		if npc_height < 1.05 or npc_height > 1.40:
			failures.append("A13 NPC visible height out of range: %.3f m（应为 1.519 × 0.8 ≈ 1.22）" % npc_height)

	# —— A13b 体型与玩家同口径：业主 2026-11-02「头要和角色一样大，现在大了很多」——
	# 第一版忘了乘 `Player3D.DEFAULT_BASE_SIZE_MULTIPLIER`，NPC 比玩家大 25%。
	var base_player_avatar: Node3D = null
	if tower.player != null:
		base_player_avatar = tower.player.get_node_or_null("Avatar3D") as Node3D
	if base_player_avatar == null:
		failures.append("A13b the 99F player exposes no Avatar3D to compare against")
	else:
		if not visual.scale.is_equal_approx(base_player_avatar.scale):
			failures.append(
				"A13b NPC visual scale %s != player avatar scale %s —— 体型没有跟玩家同口径"
					% [str(visual.scale), str(base_player_avatar.scale)]
			)
		var base_player_visual := base_player_avatar.get_node_or_null("VisualRoot") as Node3D
		if base_player_visual == null:
			failures.append("A13b player Avatar3D has no VisualRoot")
		elif npc_height > 0.01:
			var player_height := _visible_aabb(base_player_visual).size.y
			if player_height > 0.01:
				var ratio := npc_height / player_height
				if absf(ratio - 1.0) > 0.10:
					failures.append(
						"A13b NPC height %.3f vs player %.3f（比值 %.2f，应在 1.0 附近）"
							% [npc_height, player_height, ratio]
					)

	# —— A14 头顶只允许"交互提示 / 台词气泡"两层，且都在头顶之上 ——
	if not has_aabb:
		failures.append("A14 cannot verify label heights without bounds")
	else:
		var model_top := aabb.end.y - npc.global_position.y
		var prompt_half := NpcCharacter3D.PROMPT_FONT_SIZE * NpcCharacter3D.PROMPT_PIXEL_SIZE * 0.5
		# 两行气泡：世界高 = (2 × 48 + 上下内边距 48) × pixel_size，半高见常量注释。
		var bubble_half := 144.0 * NpcCharacter3D.BUBBLE_PIXEL_SIZE * 0.5
		var prompt_bottom := NpcCharacter3D.PROMPT_HEIGHT - prompt_half
		var bubble_bottom := NpcCharacter3D.BARK_HEIGHT - bubble_half
		if prompt_bottom - model_top < 0.05:
			failures.append("A14 prompt label sits too close to the head: gap %.3f" % (prompt_bottom - model_top))
		if bubble_bottom - model_top < 0.05:
			failures.append("A14 speech bubble overlaps the head: gap %.3f" % (bubble_bottom - model_top))
		# A14b 俯视角压缩：业主「对话框会遮住整个角色，往上放一些」。
		# 基地相机俯角约 53°，世界 Y 抬 1m 屏幕上只走 cos53° ≈ 0.60m —— 旧的 0.23m 世界间隙
		# 折算到屏幕上只有 3~4 像素，看着就是贴在头上。这条按屏幕等效量守门。
		const CAMERA_PITCH_COS := 0.60
		var screen_gap := (bubble_bottom - model_top) * CAMERA_PITCH_COS
		var character_screen_height := (model_top * CAMERA_PITCH_COS)
		if screen_gap < character_screen_height * 0.45:
			failures.append(
				"A14b bubble sits only %.2f m above the head on screen（角色屏幕高 %.2f m，至少要 45%%）"
					% [screen_gap, character_screen_height]
			)
		# 名字牌/身份牌已按业主口径退役：头顶除交互提示外不许再有常驻文字。
		for child in npc.get_children():
			if child is Label3D and (child as Label3D).name != "PromptLabel":
				failures.append("A14 a permanent label 『%s』 is still mounted over the NPC head" % child.name)
		if bool(npc.get_snapshot().get("has_name_label", true)):
			failures.append("A14 NPC still mounts a NameLabel")

	# —— A14b 皮肤不做自发光：业主 2026-11-02「为什么是自发光？荧光感太强了」——
	if shared_material is BaseMaterial3D:
		var skin_material := shared_material as BaseMaterial3D
		if skin_material.emission_enabled:
			failures.append(
				"A14b NPC skin still emits（energy=%.2f）—— 画面上会有荧光感"
					% skin_material.emission_energy_multiplier
			)
	if absf(NpcCatalog.get_skin_emission(NPC_ID)) > 0.001:
		failures.append("A14b NpcCatalog still declares a non-zero skin emission")

	# —— A19 净空：不与设施抢交互 ——
	for node in facility_room.find_children("*", "Node3D", true, false):
		var script: Variant = node.get_script()
		if script == null or not str((script as Script).resource_path).ends_with("BaseFacility3D.gd"):
			continue
		var facility := node as Node3D
		var distance := facility.global_position.distance_to(npc.global_position)
		if distance < FACILITY_CLEARANCE_M:
			failures.append("A19 NPC stands %.2f m from facility 『%s』 (needs >= %.1f)" % [distance, facility.name, FACILITY_CLEARANCE_M])

	# —— A15–A18 巡逻 ——
	var snapshot := npc.get_snapshot()
	if not bool(snapshot.get("patrol_enabled", false)):
		failures.append("A15 NPC patrol is disabled in the base")
	if int(snapshot.get("patrol_point_count", 0)) < 2:
		failures.append("A15 NPC needs at least 2 patrol points (anchors missing?)")
	var start_position: Vector3 = npc.global_position
	await get_tree().create_timer(1.2).timeout
	var walked: float = start_position.distance_to(npc.global_position)
	if walked < 0.8:
		failures.append("A16 NPC did not walk along its patrol path: moved %.2f m in 1.2 s" % walked)
	var forward := npc.global_position - start_position
	if forward.length() > 0.2:
		var expected_yaw := atan2(-forward.normalized().x, -forward.normalized().z)
		var yaw_error := absf(wrapf(npc.rotation.y - expected_yaw, -PI, PI))
		if yaw_error > 0.25:
			failures.append("A18 NPC does not face its walking direction: yaw error %.2f rad" % yaw_error)
	var saw_dwell := bool(npc.get_snapshot().get("dwelling", false))
	var start_target := int(npc.get_snapshot().get("patrol_target", 0))
	for _i in 40:
		await get_tree().create_timer(0.1).timeout
		var probe: Dictionary = npc.get_snapshot()
		if bool(probe.get("dwelling", false)) or int(probe.get("patrol_target", 0)) != start_target:
			saw_dwell = true
			break
	if not saw_dwell:
		failures.append("A17 NPC never paused at a patrol point within 4 s")

	# —— A20–A25 交互与对话 ——
	npc.patrol_enabled = false
	await get_tree().physics_frame
	var player := tower.player
	if not bool(npc.get_interaction_candidate(player).is_empty()):
		failures.append("A20 NPC offers a candidate while the player is far away")
	# A20b「接近才出来」：1.5m 半径之外（放到 2.0m）不许给候选 —— 旧版 2.4m 太远。
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 2.0)
	for _frame in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	if not bool(npc.get_interaction_candidate(player).is_empty()):
		failures.append("A20b NPC offers a candidate from 2.0 m (interaction radius must be ~1.5 m)")
	if bool(npc.get_snapshot().get("prompt_visible", true)):
		failures.append("A20b the [E] prompt is visible before the player is close enough")
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 1.4)
	for _frame in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	if not bool(npc.get_snapshot().get("in_range", false)):
		failures.append("A20 NPC does not detect the player inside its interaction range")
	# 被聚焦后黄色提示才出现（常驻文字已经全部撤除，这是头顶唯一的文字）。
	if not bool(npc.get_snapshot().get("prompt_visible", false)):
		failures.append("A20 the [E] prompt does not appear when the player is close and focused")
	# A20c 白点退役：控制器给 NPC **根本不该建** 圆点节点。
	# 业主两轮口径：「上面的白点去掉」→「这个白色的交谈和白点不要了」。
	# 判据是快照为空（节点不存在），不是一个 visible_amount —— 后者要等插值淡出，
	# 中间会闪一下白点和白色「(e) 交谈」，正是业主看到的现象。
	var dot := player.interaction_controller.get_interaction_dot_snapshot(npc)
	if not dot.is_empty():
		failures.append(
			"A20c the NPC still got an interaction dot from the controller (visible_amount=%.2f) —— 白点与白色按键牌必须完全不建"
				% float(dot.get("visible_amount", 0.0))
		)
	if bool(npc.call("is_interaction_dot_visible")):
		failures.append("A20c NPC still asks the controller for a resident interaction dot")
	if not PlayerInteractionController3D.DOT_EXCLUDED_PROVIDER_SCRIPTS.has(
		"res://src/npc/NpcCharacter3D.gd"
	):
		failures.append(
			"A20c NpcCharacter3D is missing from DOT_EXCLUDED_PROVIDER_SCRIPTS —— 白点会重新长出来"
		)
	var candidate := npc.get_interaction_candidate(player)
	if candidate.is_empty():
		failures.append("A21 NPC returns no candidate while the player is in range")
	else:
		if str(candidate.get("prompt", "")) != NpcCharacter3D.PROMPT_TEXT:
			failures.append("A21 NPC prompt is not 『%s』: %s" % [NpcCharacter3D.PROMPT_TEXT, str(candidate.get("prompt", ""))])
		if int(candidate.get("priority", -1)) != NpcCharacter3D.PROVIDER_PRIORITY:
			failures.append("A21 NPC provider priority mismatch")
		if not str(candidate.get("interaction_id", "")).begins_with("base_npc:"):
			failures.append("A21 NPC interaction id is not namespaced: %s" % str(candidate.get("interaction_id", "")))
	if not player.request_interaction_for_test():
		failures.append("A22 the unified interaction controller rejects the NPC")
	await get_tree().process_frame
	var first := npc.get_snapshot()
	if int(first.get("line_index", -1)) != 0:
		failures.append("A22 first interaction does not speak line 0: %d" % int(first.get("line_index", -1)))
	if str(npc.get_current_line()) != str(lines[0]):
		failures.append("A22 spoken line does not match the catalog")
	if not bool(first.get("speaking", false)):
		failures.append("A24 the head bubble did not open for the NPC line")
	# —— A22b 搭话立刻停下来并转向玩家（业主 2026-11-02 明确要求）——
	if not bool(first.get("talk_engaged", false)):
		failures.append("A22b the NPC did not enter the engaged state on interaction")
	if bool(first.get("moving", true)):
		failures.append("A22b the NPC keeps walking after the dialogue starts")
	if bool(first.get("prompt_visible", true)):
		failures.append("A22b the [E] prompt is still shown while the NPC is talking")
	var to_player := player.global_position - npc.global_position
	to_player.y = 0.0
	var expected_yaw := atan2(-to_player.x, -to_player.z)
	var yaw_gap := absf(wrapf(float(first.get("yaw", 0.0)) - expected_yaw, -PI, PI))
	if yaw_gap > 0.15:
		failures.append("A22b the NPC did not turn to the player immediately: yaw gap %.2f rad" % yaw_gap)

	var bubble_text := ""
	var bark := npc.get_node_or_null("CharacterBark3D") as CharacterBark3D
	if bark != null:
		bubble_text = DialogueUI.current_text()
	if bubble_text != str(lines[0]):
		failures.append("A24 bubble text 『%s』 != catalog line 『%s』" % [bubble_text, str(lines[0])])
	# —— A24b 气泡字号（业主三轮口径：太小学直看不清楚）——
	# 直接量世界尺寸，而不是只比常量：常量对了但 `bubble_scale` 被别处改小，画面上一样小。
	if bark != null:
		var bubble := bark.get_bubble()
		if bubble == null:
			failures.append("A24b the NPC has no speech bubble instance")
		else:
			var bubble_label := bubble.get_node_or_null("Text") as Label3D
			if bubble_label == null:
				failures.append("A24b the bubble has no Text node")
			elif not is_equal_approx(bubble_label.pixel_size, NpcCharacter3D.BUBBLE_PIXEL_SIZE):
				failures.append(
					"A24b bubble pixel_size %.4f != NpcCharacter3D.BUBBLE_PIXEL_SIZE %.4f"
						% [bubble_label.pixel_size, NpcCharacter3D.BUBBLE_PIXEL_SIZE]
				)
			# —— A24b 头顶形态与底栏字号（业主 2026-11-10 改造）——
			#
			# ⚠️ 判据已经反转：对话时头顶**不再**是 3m 宽的文字气泡，
			# 而是固定 0.5~1.3m 的「正在说话」示意框（业主：原来那个太挡角色）；
			# 文字统一进底栏，所以字号要改成量底栏。
			if not bark.is_indicator_active():
				failures.append("A24b 对话开始时头顶没有出现说话示意框")
			if not bubble.get_bubble_text().is_empty():
				failures.append(
					"A24b 对话文字仍写在头顶气泡里：『%s』（应统一到底栏）" % bubble.get_bubble_text()
				)
			var bubble_width := bubble.get_bubble_width_m()
			if bubble_width < 0.5 or bubble_width > 1.3:
				failures.append(
					"A24b 头顶示意框宽 %.2f m，超出 0.5~1.3 m 的小框区间" % bubble_width
				)
			var panel := DialogueUI.get("_panel") as Control
			if panel == null:
				failures.append("A24b 找不到底栏面板")
			elif not is_equal_approx(panel.anchor_left, 0.15) or not is_equal_approx(panel.anchor_right, 0.85):
				failures.append(
					"A24b 底栏宽度不是视口 70%%（实际 %.2f~%.2f）" % [panel.anchor_left, panel.anchor_right]
				)
			var text_label := DialogueUI.get("_text_label") as Label
			if text_label == null:
				failures.append("A24b 底栏缺少正文 Label")
			elif text_label.get_theme_font_size("font_size") < 19:
				failures.append(
					"A24b 底栏正文字号 %d < 19 —— 收窄宽度后不能顺手把字缩小"
						% text_label.get_theme_font_size("font_size")
				)
			# —— A24c 底板半透明（业主 2026-11-02「黑色背景半透明」）——
			if bubble.fill_color.a >= 0.9:
				failures.append(
					"A24c bubble fill is opaque（alpha=%.2f）—— 会像一块死板挡住角色"
						% bubble.fill_color.a
				)
			if bubble.fill_color.a <= 0.15:
				failures.append(
					"A24c bubble fill is nearly invisible（alpha=%.2f）—— 字会压不住背景"
						% bubble.fill_color.a
				)
			var fill_material := bubble.get_node_or_null("Panel") as MeshInstance3D
			if fill_material != null:
				var surface_material := fill_material.get_surface_override_material(1) as StandardMaterial3D
				if surface_material == null:
					failures.append("A24c bubble fill surface has no material")
				elif surface_material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
					failures.append(
						"A24c bubble fill material is not alpha-blended（transparency=%d）"
							% surface_material.transparency
					)
				elif bubble_label != null and surface_material.render_priority >= bubble_label.render_priority:
					# ⚠️ 半透明底板若排在文字之后渲染，会把文字压暗 55%。
					# 底板 priority 0 / 文字 priority 2 是"先底板、后文字"的硬保证。
					failures.append(
						"A24c fill render_priority %d >= text %d —— 半透明底板会盖在文字上把它压暗"
							% [surface_material.render_priority, bubble_label.render_priority]
					)
	for expected in range(1, lines.size()):
		var result := npc.advance_dialogue()
		if int(result.get("line_index", -1)) != expected:
			failures.append("A23 dialogue index mismatch: expected %d, actual %d" % [expected, int(result.get("line_index", -1))])
		if bool(result.get("finished_cycle", true)):
			failures.append("A23 finished_cycle fired before the dialogue looped at line %d" % expected)
	var looped := npc.advance_dialogue()
	if int(looped.get("line_index", -1)) != 0:
		failures.append("A23 dialogue does not loop back to line 0")
	if not bool(looped.get("finished_cycle", false)):
		failures.append("A23 finished_cycle did not fire when the dialogue looped back")
	# —— A22c 搭话期间即使把巡逻打开也必须钉住不动 ——
	var frozen_at: Vector3 = npc.global_position
	npc.patrol_enabled = true
	await get_tree().create_timer(0.5).timeout
	if bool(npc.get_snapshot().get("moving", false)):
		failures.append("A22c the NPC resumed walking while still engaged in dialogue")
	var drifted := frozen_at.distance_to(npc.global_position)
	if drifted > 0.02:
		failures.append("A22c the NPC drifted %.3f m while engaged in dialogue" % drifted)
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 8.0)
	for _frame in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	var left := npc.get_snapshot()
	if bool(left.get("in_range", false)):
		failures.append("A25 NPC still reports the player in range after leaving")
	if bool(left.get("dialogue_visible", false)) or bool(left.get("speaking", false)):
		failures.append("A25 NPC dialogue did not close after the player left")
	if int(left.get("line_index", 0)) != -1:
		failures.append("A25 NPC dialogue index was not reset after the player left")
	# —— A25b 玩家离开 → 解除定住、恢复巡逻 ——
	# 判据是"位置重新开始变化"，不是只看 `moving` 标志：NPC 可能正好停在巡逻点上
	# 做 1.6s 的到点停留，那段时间 `moving=false` 是完全正常的。
	var resumed_from: Vector3 = npc.global_position
	var resumed := false
	for _i in 30:
		await get_tree().create_timer(0.1).timeout
		if resumed_from.distance_to(npc.global_position) > 0.10:
			resumed = true
			break
	if bool(npc.get_snapshot().get("talk_engaged", false)):
		failures.append("A25b the NPC is still engaged after the player walked away")
	if not resumed:
		failures.append("A25b the NPC never resumed patrol within 3 s after the player left")

	# —— A26 塔楼只读投影 ——
	var snapshots := tower.get_npc_snapshots()
	if snapshots.size() != 1:
		failures.append("A26 get_npc_snapshots should expose exactly 1 NPC, actual %d" % snapshots.size())
	else:
		var projected: Dictionary = snapshots[0]
		for key in ["npc_id", "display_name", "role", "in_range", "line_count", "skin_albedo", "painted_mesh_count", "patrol_point_count"]:
			if not projected.has(key):
				failures.append("A26 NPC snapshot is missing key 『%s』" % key)

	_finish_now(tower, failures)


func _is_under_face_mask(node: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor.name == NpcCharacter3D.FACE_MASK_NODE:
			return true
		cursor = cursor.get_parent()
	return false


## 可见网格的世界包围盒（隐藏件不计）。A13b 用它比较"NPC 与玩家是否等高"。
func _visible_aabb(holder: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.is_visible_in_tree():
			continue
		var one := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			box = one
			first = false
		else:
			box = box.merge(one)
	return box


func _finish_now(owner_node: Node, failures: Array[String]) -> void:
	if owner_node != null and is_instance_valid(owner_node):
		owner_node.queue_free()
		await get_tree().process_frame
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_NPC_FLOW_OK: 99F base NPC matches the player's body scale, wears the wardrobe's suit_green without emission, keeps no floating name/dot, freezes and turns to the player when talked to, and patrols between anchors")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
