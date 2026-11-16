extends Node

const ENEMY_SCENE := "res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
const PREFAB := "res://assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn"
const MODEL := "res://assets/art/enemies/normal_enemy_3d/ranged_caster/components/enm_ranged_sporeshooter01_visual_top3d.glb"
const CLIPS := {"armed_idle": 3.2, "walking_armed": 1.6, "running_armed": 0.8, "shoot": 0.8}
const STATES := {
	"dormant": "armed_idle", "idle": "armed_idle", "patrol": "walking_armed", "alert": "armed_idle",
	"chase": "running_armed", "search": "running_armed", "return": "running_armed",
	"telegraph": "shoot", "attack": "shoot", "recovery": "shoot",
	"stagger": "armed_idle", "dead": "armed_idle",
}
const EPS := 0.00001

func _ready() -> void:
	var scene := load(ENEMY_SCENE) as PackedScene
	assert(scene != null, "通用敌人场景缺失")
	var enemy := scene.instantiate()
	get_tree().root.add_child.call_deferred(enemy)
	await get_tree().process_frame
	enemy.configure_from_enemy_data({"enemy_type": "ranged_caster", "is_elite": false})
	await get_tree().process_frame
	# 后续同步检查不再让 AI 或自动时钟干预，仍经真实 Avatar 转发接口。
	enemy.set_physics_process(false)
	enemy.set_process(false)
	var avatar := enemy.get_node("Avatar")
	avatar.set_process(false)
	var snap: Dictionary = avatar.get_component_snapshot()
	assert(snap.get("formal_normal_asset", false), "正式远程表现未挂载")
	assert(snap.get("component_count", 0) == 2, "正式组件契约改变")
	var presenter := avatar.find_child("FormalNormal_ranged_caster", true, false) as Node3D
	assert(presenter != null, "警察僵尸表现根缺失")
	assert(presenter.scene_file_path == PREFAB, "稳定包装引用改变")
	presenter.set_process(false)
	var player := presenter.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := presenter.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(player != null and skeleton != null, "动画播放器或骨架缺失")
	_verify_asset(presenter, player, skeleton)
	assert(enemy.uses_no_corpse_death(), "远程僵尸必须沿用无尸体死亡路径")
	assert(absf(avatar.get_formal_death_duration() - 2.4) < EPS, "死亡接口时长改变")

	# 清掉初始化残留的平滑满速，再经 Avatar 初始化夹具。
	_freeze_base_speed(avatar, presenter, 30.0)
	avatar.sync_presentation("patrol", 0.0, 9.0, 0.38, 0.34, 30.0)
	assert(presenter.get_presentation_snapshot().get("clip", "") == "walking_armed", "巡逻必须使用持枪走路")
	avatar.sync_presentation("attack", 0.18, 0.0, 0.38, 0.34, 30.0)
	assert(presenter.get_presentation_snapshot().get("clip", "") == "shoot", "攻击必须使用射击段")
	for state in STATES:
		avatar.sync_presentation(state, 0.1, 0.0, 0.38, 0.34, 30.0)
		var state_snap: Dictionary = presenter.get_presentation_snapshot()
		assert(state_snap["clip"] == STATES[state], "十二态映射错误：%s" % state)
		assert(player.has_animation(state_snap["clip"]), "状态不能指向缺失动画：%s" % state)
		assert(player.current_animation == state_snap["clip"], "播放器与快照段名不一致")
		assert(is_finite(float(state_snap["sample_time"])), "采样时间非有限值")
		if state in ["stagger", "dead"]:
			_verify_pinned_fallback(presenter, player, skeleton, "hurt" if state == "stagger" else "dead")
			presenter._process(0.05)
			avatar.sync_presentation(state, 0.15, 0.0, 0.38, 0.34, 30.0)
			_verify_pinned_fallback(presenter, player, skeleton, "hurt" if state == "stagger" else "dead")

	_verify_fire_timing(avatar, presenter, player, skeleton)
	_verify_locomotion(avatar, presenter, player)
	_verify_hits(avatar, presenter, player, skeleton)
	print("SECURITY_ZOMBIE_PRESENTATION_OK bones=65 clips=4 texture=256 version=v004 embedded_gun=true states=12 fire=0.48 ranged_logic_preserved=true")
	get_tree().quit()

func _verify_asset(presenter: Node3D, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var snap: Dictionary = presenter.get_presentation_snapshot()
	assert(skeleton.get_bone_count() == 65 and snap["bone_count"] == 65, "必须使用新65骨模型")
	var right_hand := str(snap["shotgun_bone"])
	var head := str(snap["head_bone"])
	assert(right_hand.ends_with("RightHand") and skeleton.find_bone(right_hand) >= 0, "实际右手骨不存在")
	assert(head.ends_with("Head") and skeleton.find_bone(head) >= 0, "实际头骨不存在")
	for index in range(skeleton.get_bone_count()):
		assert(str(skeleton.get_bone_name(index)).begins_with("mixamorig"), "并非新 mixamorig 骨架")
	var eye_spec: Dictionary = presenter.get_eye_socket_spec()
	assert(eye_spec.get("bone_name", "") == head, "眼位标定必须匹配实际头骨名")
	assert(eye_spec.get("bone_offsets", []).size() == 2, "眼位标定必须包含两个骨空间偏移")
	assert(eye_spec.get("calibration", "") == "police_zombie25_texture_pupil_raycast_v004", "眼位标定标识错误")
	assert(snap["source"] == "police_zombie25_animation_v002", "新制作源标记错误")
	assert(snap["asset_version"] == "v004", "256贴图运行版本错误")
	assert(snap["model_scene"] == MODEL, "稳定模型路径改变")
	assert(not snap["collision_owned"] and not snap["procedural_pose"], "表现层不能接管玩法或程序姿态")
	assert(snap["missing_clips"] == ["hurt", "dead"], "必须如实报告缺失受击/死亡片段")
	var animations := Array(player.get_animation_list())
	animations.erase("RESET")
	assert(animations.size() == 4, "不得生成额外动作或保留旧剪辑")
	for clip in CLIPS:
		assert(clip in animations, "正式片段缺失：%s" % clip)
		var animation := player.get_animation(clip)
		assert(absf(animation.length - float(CLIPS[clip])) < EPS, "片段时长错误：%s" % clip)
		var loop_mode := Animation.LOOP_NONE if clip == "shoot" else Animation.LOOP_LINEAR
		assert(animation.loop_mode == loop_mode, "片段循环错误：%s" % clip)
		assert(absf(float(snap["clip_specs"][clip]["length"]) - animation.length) < EPS, "快照时长不真实")
		assert(snap["clip_specs"][clip]["loop_mode"] == animation.loop_mode, "快照循环不真实")
	assert(presenter.find_child("SecurityShotgunAttachment", true, false) == null, "旧枪绑点仍存在")
	assert(presenter.find_child("ShotgunVisual", true, false) == null, "旧外挂枪仍存在")
	assert(not presenter.has_method("_attach_shotgun"), "旧外挂逻辑未删除")
	for attachment in presenter.find_children("*", "BoneAttachment3D", true, false):
		assert(str(attachment.bone_name) != "L_Hand", "旧左手外挂仍存在")

	var meshes := _skinned_meshes(presenter)
	assert(meshes.size() == 1, "源必须仅有一个蒙皮融合网格，不得有第二个蒙皮枪体")
	# 仅豁免真实眼光容器下的四个已知网格，非蒙皮外挂枪仍必须失败。
	var eye_glow := skeleton.get_node_or_null("StrongEyeSocket3D/StrongEyeGlow3D")
	for node in presenter.find_children("*", "MeshInstance3D", true, false):
		var extra := node as MeshInstance3D
		if extra.skin != null:
			continue
		assert(eye_glow != null and extra.get_parent() == eye_glow, "发现眼光之外的非蒙皮外挂，可能有重复枪：%s" % presenter.get_path_to(extra))
		assert(eye_glow.get_script() == load("res://src/enemy3d/StrongVariantEyeGlow3D.gd"), "眼光豁免容器类型错误")
		if str(extra.name) in ["EyeGlowL", "EyeGlowR"]:
			assert(extra.mesh is SphereMesh, "眼球豁免网格类型错误")
		else:
			assert(str(extra.name) in ["HaloEyeGlowL", "HaloEyeGlowR"] and extra.mesh is QuadMesh, "发现非眼光网格，可能有重复枪")
	var mesh := meshes[0] as MeshInstance3D
	assert(mesh.mesh != null and mesh.skin != null, "融合枪蒙皮网格不存在")
	assert(mesh.get_node_or_null(mesh.skeleton) == skeleton, "融合网格骨架引用错误")
	assert(snap["shotgun_visual"] and snap["shotgun_embedded"], "融合枪未报告")
	assert(snap["shotgun_mesh_paths"] == [str(presenter.get_path_to(mesh))], "快照没有指向实际融合网格")
	var hand_bind := -1
	for bind in range(mesh.skin.get_bind_count()):
		var bind_name := str(mesh.skin.get_bind_name(bind))
		if bind_name == right_hand or (bind_name.is_empty() and mesh.skin.get_bind_bone(bind) == skeleton.find_bone(right_hand)):
			hand_bind = bind
	assert(hand_bind >= 0, "融合网格没有实际右手绑定")
	var rigid_hand_vertices := 0
	var texture_count := 0
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in range(bones.size()):
			if bones[index] == hand_bind and weights[index] > 0.99:
				rigid_hand_vertices += 1
		# 同时检查源 surface 与正在渲染的 override，防止快照常量掩盖旧贴图。
		for material in [mesh.mesh.surface_get_material(surface), mesh.get_active_material(surface)]:
			assert(material is StandardMaterial3D, "源或实际材质类型错误")
			var texture: Texture2D = material.albedo_texture
			assert(texture != null and texture.get_width() == 256 and texture.get_height() == 256, "实际材质必须绑定256源贴图")
			var image := texture.get_image()
			assert(image != null and image.get_size() == Vector2i(256, 256), "实际贴图像素不是256")
			texture_count += 1
	# 新源实测75个导出顶点、39个唯一位置，允许导入合并接缝但不能只剩手掌。
	assert(rigid_hand_vertices >= 39, "融合枪缺少刚性跟随 RightHand 的实际几何")
	assert(texture_count > 0 and not snap["albedo_textures"].is_empty(), "贴图检查未覆盖任何材质")
	for texture_spec in snap["albedo_textures"]:
		assert(texture_spec["size"] == Vector2(256, 256), "快照贴图尺寸不真实")

func _verify_pinned_fallback(presenter: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, missing: String) -> void:
	var snap: Dictionary = presenter.get_presentation_snapshot()
	assert(snap["requested_clip"] == missing and snap["missing_clip"] == missing, "缺片原因未如实报告")
	assert(snap["missing_clip_fallback"] == "armed_idle@0" and snap["clip"] == "armed_idle", "缺片必须明确回退")
	assert(not snap["looping"] and float(snap["blend_left"]) == 0.0, "缺片不得继续相位或残留混合")
	assert(float(snap["sample_time"]) == 0.0 and float(snap["phase"]) == 0.0, "缺片未钉0")
	assert(absf(player.current_animation_position) < EPS, "实际播放器未钉0")
	assert(not snap["hurt_pose"], "不能伪造受击姿态")
	var actual := _poses(skeleton)
	player.stop()
	player.play("armed_idle")
	player.seek(0.0, true)
	_assert_poses_equal(actual, _poses(skeleton), "缺片实际骨姿不是 armed_idle@0")

func _verify_fire_timing(avatar: Node, presenter: Node3D, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var previous := -1.0
	for step in range(21):
		avatar.sync_presentation("telegraph", 0.38 * step / 20.0, 0.0, 0.38, 0.34, 30.0)
		var snap: Dictionary = presenter.get_presentation_snapshot()
		var expected := 0.8 * 0.48 * step / 20.0
		assert(snap["clip"] == "shoot" and not snap["looping"], "前摇必须使用非循环射击")
		assert(absf(float(snap["sample_time"]) - expected) < EPS, "前摇48%映射错误")
		assert(absf(player.current_animation_position - expected) < EPS, "实际射击采样错误")
		assert(float(snap["sample_time"]) >= previous, "前摇采样不连续")
		previous = float(snap["sample_time"])
	var boundary_pose := _poses(skeleton)
	avatar.sync_presentation("attack", 0.18, 0.0, 0.38, 0.34, 30.0)
	assert(absf(player.current_animation_position - 0.384) < EPS, "攻击不是0.384秒/48%")
	_assert_poses_equal(boundary_pose, _poses(skeleton), "前摇到攻击骨姿不连续")
	avatar.sync_presentation("recovery", 0.0, 0.0, 0.38, 0.34, 30.0)
	_assert_poses_equal(boundary_pose, _poses(skeleton), "攻击到恢复骨姿不连续")
	for step in range(21):
		avatar.sync_presentation("recovery", 0.34 * step / 20.0, 0.0, 0.38, 0.34, 30.0)
		var expected := 0.8 * lerpf(0.48, 1.0, step / 20.0)
		assert(absf(player.current_animation_position - expected) < EPS, "恢复采样错误")
		assert(player.current_animation_position + EPS >= previous, "恢复采样不连续")
		previous = player.current_animation_position

func _verify_locomotion(avatar: Node, presenter: Node3D, player: AnimationPlayer) -> void:
	_freeze_base_speed(avatar, presenter, 30.0)
	for pair in [[0.61, "walking_armed"], [0.62, "running_armed"], [0.55, "running_armed"], [0.50, "running_armed"], [0.499, "walking_armed"]]:
		avatar.sync_presentation("patrol", 0.0, float(pair[0]) * 30.0, 0.38, 0.34, 30.0)
		var boundary_snap: Dictionary = presenter.get_presentation_snapshot()
		assert(absf(float(boundary_snap["base_speed"]) - 30.0) < EPS, "迟滞夹具满速发生漂移")
		assert(absf(float(boundary_snap["speed_ratio"]) - float(pair[0])) < EPS, "Avatar未透传实际速度/满速")
		assert(boundary_snap["clip"] == pair[1], "0.62/0.50迟滞边界改变：%s" % [pair])
	assert(absf(float(presenter.get_presentation_snapshot()["blend_left"]) - 0.16) < EPS, "混合时长必须为0.16秒")
	presenter._process(0.08)
	assert(absf(float(presenter.get_presentation_snapshot()["blend_left"]) - 0.08) < EPS, "混合没有推进")
	presenter._process(0.08)
	avatar.sync_presentation("patrol", 0.16, 14.97, 0.38, 0.34, 30.0)
	assert(absf(float(presenter.get_presentation_snapshot()["blend_left"])) < EPS, "混合没有结束")
	assert(player.current_animation == "walking_armed", "实际移动段错误")
	presenter._process(0.1)
	avatar.sync_presentation("patrol", 0.26, 14.97, 0.38, 0.34, 30.0)
	var snap: Dictionary = presenter.get_presentation_snapshot()
	assert(float(snap["sample_time"]) > 0.0 and snap["looping"], "循环移动相位没有推进")
	var base_before := float(snap["base_speed"])
	presenter._process(0.1)
	avatar.sync_presentation("patrol", 0.36, 6.0, 0.38, 0.34, 12.0)
	var expected := lerpf(base_before, 12.0, 1.0 - exp(-0.1 / 0.30))
	assert(absf(float(presenter.get_presentation_snapshot()["base_speed"]) - expected) < EPS, "满速平滑时间常数不是0.30秒")

func _verify_hits(avatar: Node, presenter: Node3D, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var meshes := _skinned_meshes(presenter)
	assert(meshes.size() == 1, "受击材质检查必须选择唯一蒙皮本体")
	var mesh := meshes[0] as MeshInstance3D
	var material := mesh.get_active_material(0) as StandardMaterial3D
	presenter._process(0.5)
	var baseline := material.emission_energy_multiplier
	avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	avatar.flash_hit(true)
	avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	_verify_pinned_fallback(presenter, player, skeleton, "hurt")
	presenter._process(0.01)
	assert(material.emission_enabled and material.emission_energy_multiplier > baseline, "普通受击未闪白实际材质")
	presenter._process(0.3)
	assert(absf(material.emission_energy_multiplier - baseline) < EPS, "普通受击闪白未恢复")
	avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	assert(presenter.get_presentation_snapshot()["missing_clip"] == "", "受击结束未退出回退")

	# 先制造一次尚未结束的普通受击，再切太阳伤害，验证 false 会取消插姿态。
	avatar.flash_hit(true)
	avatar.flash_hit(false)
	avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	var snap: Dictionary = presenter.get_presentation_snapshot()
	assert(not snap["hurt_pose_allowed"] and not snap["hurt_pose"] and snap["missing_clip"] == "", "flash_hit(false)仍插入受击或缺片姿态")
	assert(snap["clip"] == "armed_idle" and snap["looping"], "false受击不应钉住正常待机")
	presenter._process(0.01)
	assert(material.emission_energy_multiplier > baseline, "false受击未闪白实际材质")
	presenter._process(0.12)
	assert(absf(material.emission_energy_multiplier - baseline) < EPS, "false闪白未恢复")
	avatar.sync_presentation("chase", 0.0, 2.0, 0.38, 0.34)
	avatar.flash_hit(true)
	avatar.sync_presentation("chase", 0.0, 2.0, 0.38, 0.34)
	snap = presenter.get_presentation_snapshot()
	assert(snap["clip"] == "running_armed" and snap["missing_clip"] == "", "移动受击错误插入姿态")
	avatar.sync_presentation("dead", 1.0, 0.0, 0.38, 0.34)
	presenter._process(0.5)
	avatar.flash_hit(true)
	assert(float(presenter.get_presentation_snapshot()["flash_time"]) == 0.0, "死亡后不应重新触发闪白")
	_verify_pinned_fallback(presenter, player, skeleton, "dead")

func _skinned_meshes(presenter: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in presenter.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin != null:
			result.append(mesh)
	return result

func _freeze_base_speed(avatar: Node, presenter: Node3D, base_speed: float) -> void:
	# 只重置测试实例缓存，不改生产参数，也不绕过 Avatar 参数透传。
	presenter.set("_base_speed", 0.0)
	presenter.set("_base_speed_clock", presenter.get("_clock"))
	avatar.sync_presentation("attack", 0.0, 0.0, 0.38, 0.34, base_speed)
	assert(absf(float(presenter.get_presentation_snapshot()["base_speed"]) - base_speed) < EPS, "Avatar未正确透传满速或夹具初始化失败")

func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for index in range(skeleton.get_bone_count()):
		result.append(skeleton.get_bone_pose(index))
	return result

func _assert_poses_equal(a: Array[Transform3D], b: Array[Transform3D], message: String) -> void:
	assert(a.size() == b.size(), message)
	for index in range(a.size()):
		assert(a[index].is_equal_approx(b[index]), "%s：bone=%d" % [message, index])
