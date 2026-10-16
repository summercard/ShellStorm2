extends Node
## 强化怪（-强化怪）**红色发光眼**专项验收。
##
## 外部真源：
##   - 眼位配方 src/enemy3d/MonsterVariants.gd → `EYE_SOCKETS`
##   - 表现实现 src/enemy3d/StrongVariantEyeGlow3D.gd
##   - 挂载 src/enemy3d/EnemyAvatar3D.gd（`Head` 骨的 `BoneAttachment3D`）
##   - 业主口径 docs/v0.1/design/怪物设计.md「红色发光眼」
##
## 覆盖：
##   ① 三个变种各长**一对**红眼；普通怪**一只都不长**（回归钉：曾因回退分支放行而全怪长眼）；
##   ② 挂在 `Head` 骨的 `BoneAttachment3D` 上 —— 不是固定坐标节点，否则转头穿帮；
##   ③ 材质**真发红光**（emission 开、色相偏红、强度 > 0），不是普通红材质；
##   ④ 左右对称（|L.x+R.x|≈0、等高）—— 不对称说明眼位换算写歪；
##   ⑤ 眼位与配方一致（按怪**自身局部坐标**量，避免被位移污染）；
##   ⑥ 头部动画播放下绑点**跟着头走**（否则「绑点」二字无意义）；
##   ⑦ 纯表现：零碰撞体、不影响玩法状态；
##   ⑧ `dismiss()` 幂等且真能撤掉。
## 判据：`EYE_GLOW_OK` 行 + `EYE_GLOW_FAIL` 计数（不看裸退出码）。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)

## 模型视觉总高（契约值，与账本 / 动作设计一致）。
const MODEL_HEIGHT := {
	"melee_chaser": 1.857143,
	"ranged_caster": 1.857143,
	"fat_zombie03": 3.142857,
}
## 眼位比例容差。三只怪是低模（1545~2993 顶点、无眼骨），
## 实测「配方值 → 生效值」有约 0.02 的系统差（同一个换算路径），故给 0.03。
const RATIO_TOLERANCE := 0.03
## 左右对称容差（米）。
const MIRROR_TOLERANCE_M := 0.01

## **文档侧硬编码一份眼位配方**，与 `MonsterVariants.EYE_SOCKETS` 逐值比对。
##
## 为什么必须有这一份（实测教训）：只断言「配方 ↔ 生效值自洽」是不够的 ——
## 把配方里的 y_ratio 从 0.535 改成 0.30，实现跟着用 0.30，两边仍然自洽，
## **测试照样绿**，而眼睛已经掉到肚子上。所以配方的**绝对值**必须另有钉子。
## 这与 `verify_monster_startup_roar` 把文档数字硬编码一遍是同一套纪律。
const DOC_EYE_SOCKETS := {
	"melee_chaser": {"y_ratio": 0.535, "half_x": 0.160, "radius": 0.030},
	"ranged_caster": {"y_ratio": 0.630, "half_x": 0.155, "radius": 0.030},
	"fat_zombie03": {"y_ratio": 0.880, "half_x": 0.195, "radius": 0.042},
}
## 头部带判定与横向上限也必须钉住：改动它们会整体平移所有眼位。
const DOC_HEAD_BAND_FROM_TOP := 0.45
const DOC_HEAD_HALF_X_LIMIT := 0.45

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	_check_doc_contract()
	await _check_strong_variants_have_glow()
	await _check_normal_monsters_have_none()
	await _check_socket_is_bone_attachment()
	await _check_material_really_glows()
	await _check_eye_positions_match_socket()
	await _check_follows_head_animation()
	await _check_no_gameplay_impact()
	await _check_dismiss()
	_expect(_samples >= 20, "样本数 %d 低于下限（疑似用例被跳过）" % _samples)
	_report()


## 建一只怪并等它完成两阶段挂载（挂点 → 下一帧算偏移）。
func _spawn(kind: String) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy)
	# 关物理：本场景无地板，不关会自由下落，把「绝对世界坐标」类断言全污染。
	enemy.set_physics_process(false)
	enemy.apply_profile(kind)
	await get_tree().process_frame
	await get_tree().process_frame
	return enemy


func _eyes_of(enemy: Enemy3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if enemy.avatar == null:
		return out
	for node in enemy.avatar.find_children("*", "MeshInstance3D", true, false):
		if str((node as MeshInstance3D).name).begins_with("EyeGlow"):
			out.append(node as Node3D)
	return out


## ⓪ 配方**绝对值**与文档侧硬编码逐值一致（防止「实现与配方一起改坏」仍判绿）。
func _check_doc_contract() -> void:
	for base_kind in DOC_EYE_SOCKETS:
		var doc: Dictionary = DOC_EYE_SOCKETS[base_kind]
		var actual := MonsterVariants.eye_socket_for_base(base_kind)
		_expect(not actual.is_empty(), "配方里缺少基类 %s" % base_kind)
		if actual.is_empty():
			continue
		for key in doc:
			_expect(
				is_equal_approx(float(actual.get(key, -1.0)), float(doc[key])),
				"配方 %s.%s 应为 %.4f（文档口径），实为 %.4f"
				% [base_kind, key, float(doc[key]), float(actual.get(key, -1.0))]
			)
			_samples += 1
	_expect(
		is_equal_approx(
			float(MonsterVariants.EYE_HEAD_BAND_FROM_TOP), DOC_HEAD_BAND_FROM_TOP
		),
		"头部带比例应为 %.2f，实为 %.2f" % [DOC_HEAD_BAND_FROM_TOP, MonsterVariants.EYE_HEAD_BAND_FROM_TOP]
	)
	_expect(
		is_equal_approx(
			float(MonsterVariants.EYE_HEAD_HALF_X_LIMIT), DOC_HEAD_HALF_X_LIMIT
		),
		"头部带横向上限应为 %.2f，实为 %.2f" % [DOC_HEAD_HALF_X_LIMIT, MonsterVariants.EYE_HEAD_HALF_X_LIMIT]
	)
	# 配方只允许登记这三只基类：多登记会让没被标定过的怪长出位置不准的红眼。
	_expect(
		MonsterVariants.EYE_SOCKETS.size() == DOC_EYE_SOCKETS.size(),
		"配方基类数应为 %d，实为 %d（新增基类必须先做标定并更新本表）"
		% [DOC_EYE_SOCKETS.size(), MonsterVariants.EYE_SOCKETS.size()]
	)
	_samples += 1


## ① 三个变种各一对红眼。
func _check_strong_variants_have_glow() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		var enemy := await _spawn(variant_id)
		var eyes := _eyes_of(enemy)
		_expect(eyes.size() == 2, "%s 应有一对发光眼，实得 %d 只" % [variant_id, eyes.size()])
		var snapshot: Dictionary = enemy.avatar.get_component_snapshot()
		var glow: Dictionary = snapshot.get("eye_glow", {})
		_expect(not glow.is_empty(), "%s 的快照里没有 eye_glow 段" % variant_id)
		_expect(int(glow.get("eye_count", 0)) == 2, "%s 快照 eye_count 应为 2" % variant_id)
		_samples += 1
		enemy.free()


## ② 普通怪一只都不长（回归钉）。
##
## 来由：`MonsterVariants.eye_socket_for()` 最初对基类也放行，
## 结果**所有普通怪都长了红眼**（实测输出「melee_chaser 眼数=2」）。
## 这条断言就是那次缺陷留下的钉子。
func _check_normal_monsters_have_none() -> void:
	for base_kind in MonsterVariants.all_base_kinds():
		var enemy := await _spawn(base_kind)
		var eyes := _eyes_of(enemy)
		_expect(eyes.size() == 0, "普通怪 %s 不该长发光眼，实得 %d 只" % [base_kind, eyes.size()])
		_samples += 1
		enemy.free()
	# 没配方的怪同样不长。
	for plain in ["exploder", "ambusher", "summoner"]:
		var enemy := await _spawn(plain)
		_expect(
			_eyes_of(enemy).size() == 0,
			"%s 没有眼位配方，不该长发光眼" % plain
		)
		_samples += 1
		enemy.free()


## ③ 挂点必须是 `BoneAttachment3D` 且绑在 `Head` 骨上。
func _check_socket_is_bone_attachment() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		var enemy := await _spawn(variant_id)
		var socket := enemy.avatar.find_child(
			EnemyAvatar3D.EYE_SOCKET_NODE_NAME, true, false
		)
		_expect(socket != null, "%s 找不到眼位绑点 %s" % [variant_id, EnemyAvatar3D.EYE_SOCKET_NODE_NAME])
		if socket != null:
			_expect(
				socket is BoneAttachment3D,
				"%s 的绑点不是 BoneAttachment3D（是 %s）⇒ 转头不跟骨，会穿帮"
				% [variant_id, socket.get_class()]
			)
			if socket is BoneAttachment3D:
				_expect(
					(socket as BoneAttachment3D).bone_name == EnemyAvatar3D.EYE_BONE_NAME,
					"%s 的绑点应挂在 %s 骨上，实为 %s"
					% [variant_id, EnemyAvatar3D.EYE_BONE_NAME, (socket as BoneAttachment3D).bone_name]
				)
		# 眼睛必须是绑点的后代 —— 也就是真的走了「骨骼绑点」这条链。
		var eyes := _eyes_of(enemy)
		for eye in eyes:
			_expect(
				eye.get_parent() is StrongVariantEyeGlow3D,
				"%s 的眼球父节点应是眼特效根，实为 %s" % [variant_id, eye.get_parent().get_class()]
			)
			var glow_root := eye.get_parent() as StrongVariantEyeGlow3D
			_expect(
				glow_root.get_parent() is BoneAttachment3D,
				"%s 的眼特效根没挂在 BoneAttachment3D 下 ⇒ 不跟骨" % variant_id
			)
		_samples += 1
		enemy.free()


## ④ 材质真发红光。
func _check_material_really_glows() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		var enemy := await _spawn(variant_id)
		for eye in _eyes_of(enemy):
			var material := (eye as MeshInstance3D).get_active_material(0) as StandardMaterial3D
			_expect(material != null, "%s 的眼球没有材质" % variant_id)
			if material == null:
				continue
			_expect(material.emission_enabled, "%s 的眼球 emission 未开启 ⇒ 不会发光" % variant_id)
			_expect(
				material.emission_energy_multiplier > 0.0,
				"%s 的眼球自发光能量应 > 0，实为 %.3f" % [variant_id, material.emission_energy_multiplier]
			)
			# 色相判定：红分量必须显著压过绿蓝，否则不是「红」色发光。
			var c := material.emission
			_expect(
				c.r > c.g * 2.0 and c.r > c.b * 2.0,
				"%s 的自发光色不够红：%s" % [variant_id, str(c)]
			)
			# 不受光：眼球要恒定亮，不能因怪走进阴影而变暗。
			_expect(
				material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
				"%s 的眼球应为 unshaded（否则进阴影会变暗）" % variant_id
			)
		_samples += 1
		enemy.free()


## ⑤ 眼位：左右对称 + 与配方比例一致。**按怪自身局部坐标量**。
func _check_eye_positions_match_socket() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		var base_kind := MonsterVariants.base_of(variant_id)
		var socket := MonsterVariants.eye_socket_for_base(base_kind)
		_expect(not socket.is_empty(), "%s 没有眼位配方" % variant_id)
		if socket.is_empty():
			continue
		var enemy := await _spawn(variant_id)
		var eyes := _eyes_of(enemy)
		if eyes.size() != 2:
			_fail("%s 的眼数不是 2，跳过眼位检查" % variant_id)
			enemy.free()
			continue
		var to_local := enemy.global_transform.affine_inverse()
		var l := to_local * eyes[0].global_position
		var r := to_local * eyes[1].global_position

		# 左右对称：换算出错时最先露馅的就是这里。
		_expect(
			absf(l.x + r.x) <= MIRROR_TOLERANCE_M,
			"%s 左右眼不对称：|L.x+R.x|=%.4f（应 <= %.3f）" % [variant_id, absf(l.x + r.x), MIRROR_TOLERANCE_M]
		)
		_expect(
			absf(l.y - r.y) <= MIRROR_TOLERANCE_M,
			"%s 左右眼不等高：|L.y-R.y|=%.4f" % [variant_id, absf(l.y - r.y)]
		)
		# 左右分居中线两侧。
		_expect(l.x < 0.0 and r.x > 0.0, "%s 的左右眼没有分居中线的两侧" % variant_id)
		# 眼距 ≈ 2 × 配方半宽。
		var want_half := float(socket.get("half_x", 0.0))
		var actual_half := (r.x - l.x) * 0.5
		_expect(
			absf(actual_half - want_half) <= 0.01,
			"%s 眼距半宽应为 %.4f，实为 %.4f" % [variant_id, want_half, actual_half]
		)
		# 高度比例 ≈ 配方值（容差 0.03，见 RATIO_TOLERANCE 注释）。
		var model_height := float(MODEL_HEIGHT[base_kind])
		var ratio := ((l.y + r.y) * 0.5) / model_height
		var want_ratio := float(socket.get("y_ratio", 0.0))
		_expect(
			absf(ratio - want_ratio) <= RATIO_TOLERANCE,
			"%s 眼高比例应为 %.4f，实为 %.4f（容差 %.2f）"
			% [variant_id, want_ratio, ratio, RATIO_TOLERANCE]
		)
		# 眼球必须在脸的前方（−Z 是正面），不能陷进后脑。
		_expect(
			(l.z + r.z) * 0.5 < 0.0,
			"%s 的眼球跑到后脑了：z=%.4f" % [variant_id, (l.z + r.z) * 0.5]
		)
		_samples += 1
		enemy.free()


## ⑥ 头部动画播放下，绑点跟着 `Head` 骨走。
##
## 判据：推进动画后，绑点的世界位置**必须与骨的位姿一起变**（不是钉在原地）。
## 这条是「骨骼绑点」这个方案的**存在理由** —— 若绑点不动，等价于固定坐标节点。
##
## ⚠ 每次 seek 之后**必须等一帧**再读数：`BoneAttachment3D` 在它自己的通知里更新变换，
## 同一帧内 seek 完立刻读，拿到的是上一帧的旧值 —— 实测会得出「骨动 0.27m、
## 绑点动 0.000m」的假故障，把正确的实现判成红的。
func _check_follows_head_animation() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		var enemy := await _spawn(variant_id)
		var skeleton: Skeleton3D = null
		for node in enemy.find_children("*", "Skeleton3D", true, false):
			skeleton = node as Skeleton3D
			break
		var socket := enemy.avatar.find_child(EnemyAvatar3D.EYE_SOCKET_NODE_NAME, true, false) as Node3D
		if skeleton == null or socket == null:
			_fail("%s 找不到骨架或绑点，跳过跟随测试" % variant_id)
			enemy.free()
			continue
		var head_index := skeleton.find_bone(EnemyAvatar3D.EYE_BONE_NAME)
		var player: AnimationPlayer = null
		for node in enemy.find_children("*", "AnimationPlayer", true, false):
			player = node as AnimationPlayer
			break
		if player == null or player.get_animation_list().is_empty():
			_fail("%s 没有动画，无法验证跟随" % variant_id)
			enemy.free()
			continue

		# 段的选择不能写死：`hurt` 只让头动 3mm，测不出跟随（实测踩过）。
		# 自动挑「头位移最大」的那一段，让断言作用在真正有信息量的数据上。
		var clip := ""
		var best_travel := -1.0
		for candidate in player.get_animation_list():
			var travel := _head_travel_of_clip(player, skeleton, head_index, str(candidate))
			if travel > best_travel:
				best_travel = travel
				clip = str(candidate)
		if clip.is_empty():
			_fail("%s 没有可用动画段" % variant_id)
			enemy.free()
			continue
		var length := player.get_animation(clip).length
		var socket_samples: Array[Vector3] = []
		var bone_samples: Array[Vector3] = []
		var local_samples: Array[Vector3] = []
		for step in range(4):
			player.play(clip)
			player.seek(length * 0.3 * float(step), true)
			player.advance(0.0)
			skeleton.force_update_all_bone_transforms()
			# 等一帧让 BoneAttachment3D 的通知跑完（见函数头注释）。
			await get_tree().process_frame
			await get_tree().process_frame
			socket_samples.append(socket.global_position)
			bone_samples.append((skeleton.global_transform * skeleton.get_bone_global_pose(head_index)).origin)
			# 同一次读数里记「眼睛相对怪局部」的位置：它应当**基本不变**
			# （眼睛焊在脸上），这比单纯「绑点在动」更强 —— 若绑点跟着头乱漂，
			# 局部坐标就会变，说明眼位算错了。
			var eyes := _eyes_of(enemy)
			if eyes.size() == 2:
				var to_local := enemy.global_transform.affine_inverse()
				local_samples.append(
					((to_local * eyes[0].global_position) + (to_local * eyes[1].global_position)) * 0.5
				)
		var bone_travel := 0.0
		for index in range(1, bone_samples.size()):
			bone_travel = maxf(bone_travel, bone_samples[index].distance_to(bone_samples[0]))
		var socket_travel := 0.0
		for index in range(1, socket_samples.size()):
			socket_travel = maxf(socket_travel, socket_samples[index].distance_to(socket_samples[0]))
		# 这三个模型的动画都是**整体位移为主、几乎不转头**，实测最大头位移仅 1.3~3.4 mm。
		# 所以断言不能建立在「位移够大」上，而要建立在**绑点与骨完全同步**上 ——
		# 实测两者逐位相等（0.0034 = 0.0034），这才是「跟骨」的直接证据。
		# 下限 0.0005 只用于确认「有信号」，不是效果门槛。
		_expect(
			bone_travel > 0.0005,
			"%s 的 %s 段完全没驱动 %s 骨（位移 %.6f m），跟随测试无信息量"
			% [variant_id, clip, EnemyAvatar3D.EYE_BONE_NAME, bone_travel]
		)
		var follow_tolerance := maxf(0.0005, bone_travel * 0.15)
		_expect(
			absf(socket_travel - bone_travel) <= follow_tolerance,
			"%s 的绑点没与 %s 骨同步：骨位移 %.6f m，绑点 %.6f m（差 %.6f > 容差 %.6f）"
			% [variant_id, EnemyAvatar3D.EYE_BONE_NAME, bone_travel, socket_travel,
				absf(socket_travel - bone_travel), follow_tolerance]
		)
		# 眼睛在**脸上**：局部坐标应当几乎不动（头动、眼随头动，相对位置不变）。
		if local_samples.size() == 4:
			var local_drift := 0.0
			for index in range(1, local_samples.size()):
				local_drift = maxf(local_drift, local_samples[index].distance_to(local_samples[0]))
			_expect(
				local_drift < 0.06,
				"%s 的眼睛在脸上漂了 %.4f m（应基本钉在脸上）" % [variant_id, local_drift]
			)
			print("[eye-glow] %s 跟随：骨位移=%.4f 绑点位移=%.4f 脸上漂移=%.4f（段 %s）" % [
				variant_id, bone_travel, socket_travel, local_drift, clip
			])
		_samples += 1
		enemy.free()


## 某动画段里 `Head` 骨的最大位移（用来挑「最能动头」的那一段做跟随测试）。
func _head_travel_of_clip(
	player: AnimationPlayer, skeleton: Skeleton3D, head_index: int, clip: String
) -> float:
	var length := player.get_animation(clip).length
	var samples: Array[Vector3] = []
	for step in range(4):
		player.play(clip)
		player.seek(length * 0.3 * float(step), true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		samples.append((skeleton.global_transform * skeleton.get_bone_global_pose(head_index)).origin)
	var travel := 0.0
	for index in range(1, samples.size()):
		travel = maxf(travel, samples[index].distance_to(samples[0]))
	return travel


## ⑦ 纯表现：零碰撞体，且不改玩法数值。
func _check_no_gameplay_impact() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		var enemy := await _spawn(variant_id)
		var glow_root := enemy.avatar.find_child("StrongEyeGlow3D", true, false)
		_expect(glow_root != null, "%s 找不到眼特效根" % variant_id)
		if glow_root != null:
			for node in glow_root.find_children("*", "CollisionObject3D", true, false):
				_fail("%s 的眼特效里出现了碰撞体 %s ⇒ 会挡住子弹/射线" % [variant_id, node.name])
			for node in glow_root.find_children("*", "CollisionShape3D", true, false):
				_fail("%s 的眼特效里出现了碰撞形状 %s" % [variant_id, node.name])
			for node in glow_root.find_children("*", "Light3D", true, false):
				var l := node as Light3D
				_expect(not l.shadow_enabled, "%s 的眼溢光不该开阴影（性能与观感都无必要）" % variant_id)
		_samples += 1
		enemy.free()


## ⑧ `dismiss()` 真能撤掉，且幂等。
func _check_dismiss() -> void:
	var enemy := await _spawn(MonsterVariants.all_variant_ids()[0])
	var glow_root := enemy.avatar.find_child("StrongEyeGlow3D", true, false) as StrongVariantEyeGlow3D
	if glow_root == null:
		_fail("找不到眼特效根，无法验证 dismiss")
		enemy.free()
		return
	_expect(glow_root.visible, "眼特效初始应可见")
	glow_root.dismiss()
	_expect(not glow_root.visible, "dismiss() 后眼特效应不可见")
	glow_root.dismiss()
	_expect(not glow_root.visible, "dismiss() 应幂等")
	for eye in _eyes_of(enemy):
		_expect(
			(eye as Node3D).is_visible_in_tree() == false,
			"dismiss() 后眼球仍可见"
		)
	_samples += 1
	enemy.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("EYE_GLOW_OK: variant glow / normal none / bone socket / material / mirror / ratio / follow / no-impact / dismiss pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("EYE_GLOW_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)
