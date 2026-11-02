extends Node
## 枪械开火反馈专项验收（2026-11-02）。
##
## 业主原话：「增加枪开枪的时候的向后弹一下 然后扩大压缩的动画，让枪更加有反馈」。
## 本用例只验表现层两个通道（后坐位移 / 沿轴压缩·横向扩张），**不验**伤害、射速、
## 弹道与命中 —— 那几项由 `verify_starting_weapon_contract` / `verify_3d_fate_weapon_flow`
## 各自钉住。反向对照写在每一节里：改回旧行为必须让本用例报红。
##
## 判据：`WEAPON_FIRE_FEEDBACK_OK` 行 + 失败计数（不看裸退出码）。

const WEAPON_MODEL_SCENE: PackedScene = preload("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn")

## 外部真源 = `WeaponModel3D.GUN_FIRE_FEEDBACK`。这里**硬编码**一份期望值，
## 表被顺手改坏时本用例要能发现，而不是把当前值当标准回读。
##
## 2026-11-02 第二版（业主：「目前没有看到变化……我希望的是一个由弹性压扁然后弹回去的动画」）：
## 第一版 punch 只有 0.09、按 18 px/m 的俯视尺度算压短不到 1 个像素 ⇒ 肉眼不可见。
## 本版一律放大 3~4 倍，并给每把枪独立的 `punch_hz` / `roll`。
const EXPECTED_FEEDBACK := {
	"bp_pistol": {"kick_m": 0.130, "hz": 7.0, "punch": 0.62, "punch_hz": 3.4, "roll": 0.40},
	"bp_shotgun": {"kick_m": 0.205, "hz": 5.0, "punch": 0.78, "punch_hz": 2.8, "roll": 0.52},
	"bp_rifle": {"kick_m": 0.145, "hz": 6.2, "punch": 0.55, "punch_hz": 3.6, "roll": 0.34},
	"bp_starter_rifle": {"kick_m": 0.135, "hz": 6.4, "punch": 0.52, "punch_hz": 3.7, "roll": 0.32},
	"bp_machinegun": {"kick_m": 0.110, "hz": 7.6, "punch": 0.36, "punch_hz": 4.6, "roll": 0.20},
	"bp_sprinkler": {"kick_m": 0.100, "hz": 7.6, "punch": 0.34, "punch_hz": 4.8, "roll": 0.18},
	"bp_sniper": {"kick_m": 0.200, "hz": 4.6, "punch": 0.72, "punch_hz": 2.7, "roll": 0.28},
	"bp_launcher": {"kick_m": 0.210, "hz": 4.8, "punch": 0.82, "punch_hz": 2.8, "roll": 0.46},
	"bp_charge": {"kick_m": 0.185, "hz": 5.0, "punch": 0.70, "punch_hz": 3.0, "roll": 0.38},
}

## 轴向压缩与横向扩张的比例：`(1 − sz) = 0.62 × (sx − 1)`。改成别的值必须同时改这里。
const AXIAL_COMPRESSION_RATIO := 0.62

## 欠阻尼弹簧的过冲率：
##   位移 ζ = 0.42 ⇒ exp(−πζ/√(1−ζ²)) ≈ 23.6%
##   压扁 ζ = 0.50 ⇒ ≈ 16.3%（压扁之后反向「拉长」）
## 旧实现（单指数衰减）的过冲是 **0**，会被这条抓死。
const EXPECTED_OVERSHOOT := 0.236
const EXPECTED_PUNCH_OVERSHOOT := 0.163
const OVERSHOOT_TOLERANCE := 0.06

## 连射语义是「刷新到至少峰值」，不是累加：上界恒等于 `peak`。
## 不用累加+封顶是因为算出来方向是反的 —— 机枪 12 发/秒衰减到 20.9%，
## 稳态只有 `0.695 × peak`，连射比单发还弱。
const PUNCH_REFRESH_TO_PEAK := true

## 可见性下限（业主两轮反馈的核心）：`tools/probe_weapon_fire_feedback.tscn` 在实战相机
## （43° / −52° / 1920×1080）实测枪口→枪根屏幕长度 = **15.8 px**。
## 屏幕缩短量 = `punch × 0.62 × 15.8` px。低于 3 px 人眼在动态画面里基本抓不到，
## 所以 `punch ≥ 3 / (0.62 × 15.8) ≈ 0.31`。设 0.31 为硬下限，低于即报红。
const MIN_VISIBLE_PUNCH := 0.31

## 时长下限：压扁相位在 60 fps 下必须至少占 3 帧（50 ms）才看得清。
## 由 `punch_hz` 决定：半周期 = 1/(2·punch_hz)，要求 ≥ 0.05 s ⇒ punch_hz ≤ 10。
const MIN_SQUASH_FRAMES := 3

## 防假绿哨兵：至少 9 把枪 × 多节断言。
const EXPECTED_MIN_SAMPLES := 60

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	await get_tree().process_frame
	_check_table_matches_runtime()
	await _check_single_shot_envelope()
	_check_punch_shape()
	await _check_no_ballistic_side_effect()
	await _check_machinegun_stacking()
	_check_ordering()
	_report()


func _expect(condition: bool, message: String) -> void:
	_samples += 1
	if not condition:
		_failures.append(message)


## ① 逐枪：运行期 `_recoil` / `_punch_peak` 必须与表一致（表是唯一真源，测试是外部期望）。
func _check_table_matches_runtime() -> void:
	for gun_id in EXPECTED_FEEDBACK:
		var weapon := _make_weapon(String(gun_id))
		if weapon == null:
			continue
		var expected: Dictionary = EXPECTED_FEEDBACK[gun_id]
		weapon.set_process(false)
		weapon.call("_apply_fire_feedback")
		_samples += 1
		_expect(
			is_equal_approx(float(weapon.get("_recoil")), float(expected["kick_m"])),
			"%s：后坐位移期望 %.3f m，实测 %.4f m" % [gun_id, float(expected["kick_m"]), float(weapon.get("_recoil"))]
		)
		_expect(
			is_equal_approx(float(weapon.get("_recoil_hz")), float(expected["hz"])),
			"%s：弹簧频率期望 %.1f Hz，实测 %.2f Hz" % [gun_id, float(expected["hz"]), float(weapon.get("_recoil_hz"))]
		)
		_expect(
			is_equal_approx(float(weapon.get("_punch_peak")), float(expected["punch"])),
			"%s：压扁峰值期望 %.3f，实测 %.4f" % [gun_id, float(expected["punch"]), float(weapon.get("_punch_peak"))]
		)
		_expect(
			is_equal_approx(float(weapon.get("_punch")), float(expected["punch"])),
			"%s：首发应给到完整峰值 %.4f（上一发已收住），实测 %.4f" % [
				gun_id, float(expected["punch"]), float(weapon.get("_punch"))
			]
		)
		_expect(
			is_equal_approx(float(weapon.get("_punch_hz")), float(expected["punch_hz"])),
			"%s：压扁弹簧频率期望 %.1f Hz，实测 %.2f Hz" % [
				gun_id, float(expected["punch_hz"]), float(weapon.get("_punch_hz"))
			]
		)
		_expect(
			is_equal_approx(float(weapon.get("_punch_roll")), float(expected["roll"])),
			"%s：压扁侧倾期望 %.2f rad，实测 %.3f rad" % [
				gun_id, float(expected["roll"]), float(weapon.get("_punch_roll"))
			]
		)
		# 可见性下限：这是业主第二版反馈的直接门禁 —— 压幅小于 0.20 在俯视尺度下又看不见了。
		_expect(
			float(expected["punch"]) >= MIN_VISIBLE_PUNCH,
			"%s：压扁振幅 %.3f 低于可见下限 %.2f（俯视约 18 px/m，会缩不到 2 px）" % [
				gun_id, float(expected["punch"]), MIN_VISIBLE_PUNCH
			]
		)
		weapon.free()


## ② 手枪一整条位移曲线：先到峰值、再越过零点反向过冲、最后收敛到 0。
##    这一节是「弹一下」的核心证据 —— 旧单指数衰减永远不会有负位移。
func _check_single_shot_envelope() -> void:
	var weapon := _make_weapon("bp_pistol")
	if weapon == null:
		return
	weapon.set_process(false)
	var kick := float(EXPECTED_FEEDBACK["bp_pistol"]["kick_m"])
	weapon.call("_apply_fire_feedback")
	var peak := float(weapon.get("_recoil"))
	var min_offset := 0.0
	var settling_frames := 0
	var overshot_at := -1.0
	var elapsed := 0.0
	var step := 1.0 / 120.0
	for index in range(180):
		weapon.call("_process", step)
		elapsed += step
		var offset := float(weapon.get("_recoil"))
		min_offset = minf(min_offset, offset)
		if overshot_at < 0.0 and offset < -0.001:
			overshot_at = elapsed
		if absf(offset) < 0.001 and absf(float(weapon.get("_recoil_velocity"))) < 0.005:
			settling_frames += 1
		_samples += 1
	_expect(is_equal_approx(peak, kick), "手枪：开火帧位移应为 %.3f m，实测 %.4f m" % [kick, peak])
	_expect(min_offset < -0.001, "手枪：回弹过程没有反向过冲（最小位移 %.5f）——弹簧退化成单调衰减" % min_offset)
	var overshoot_ratio := absf(min_offset) / maxf(0.0001, kick)
	_expect(
		absf(overshoot_ratio - EXPECTED_OVERSHOOT) <= OVERSHOOT_TOLERANCE,
		"手枪：过冲率期望 %.3f±%.2f，实测 %.3f（ζ=0.42 的解析值 0.236）" % [
			EXPECTED_OVERSHOOT, OVERSHOOT_TOLERANCE, overshoot_ratio
		]
	)
	_expect(overshot_at > 0.0 and overshot_at < 0.20, "手枪：过零时刻期望 <0.20 s，实测 %.3f s" % overshot_at)
	_expect(absf(float(weapon.get("_recoil"))) < 0.001, "手枪：0.75 s 后位移未收敛，实测 %.5f" % float(weapon.get("_recoil")))
	_expect(settling_frames >= 20, "手枪：收敛后应稳定在 0，实测稳定帧 %d < 20" % settling_frames)
	weapon.free()
	await get_tree().process_frame


## ③ 形变口径：横向扩大、沿轴压缩，比例恒为 0.62；且必须走完「压扁 → 拉长 → 回正」。
##    这一节是业主第二版「一个由弹性压扁然后弹回去的动画」的核心证据：
##    旧实现是纯指数衰减，永远不会出现 `a < 0`（拉长）的那一段。
func _check_punch_shape() -> void:
	var weapon := _make_weapon("bp_shotgun")
	if weapon == null:
		return
	weapon.set_process(false)
	weapon.call("_apply_fire_feedback")
	weapon.call("_process", 1.0 / 240.0)
	var punch_root := weapon.get("_visual_root") as Node3D
	if punch_root == null:
		_failures.append("霰弹：武器没有视觉根节点，形变通道不可测")
		weapon.free()
		return
	var scale_vec := punch_root.scale
	_expect(
		is_equal_approx(scale_vec.x, scale_vec.y),
		"霰弹：横向两轴必须一致（实测 x=%.4f y=%.4f）" % [scale_vec.x, scale_vec.y]
	)
	_expect(scale_vec.x > 1.05, "霰弹：横向应明显扩张，实测 x=%.4f" % scale_vec.x)
	_expect(scale_vec.z < 0.95, "霰弹：沿枪轴应明显压缩，实测 z=%.4f" % scale_vec.z)
	_expect(
		absf((1.0 - scale_vec.z) - AXIAL_COMPRESSION_RATIO * (scale_vec.x - 1.0)) < 0.001,
		"霰弹：压缩/扩张比例期望 %.2f，实测 %.3f" % [
			AXIAL_COMPRESSION_RATIO,
			(1.0 - scale_vec.z) / maxf(0.0001, scale_vec.x - 1.0)
		]
	)

	# —— 时间维度：压扁后必须反弹越过零点，变成「拉长变细」再回正。——
	var punch_peak := float(EXPECTED_FEEDBACK["bp_shotgun"]["punch"])
	var stretch_at := -1.0
	var min_punch := 0.0
	var settled_at := -1.0
	var elapsed := 0.0
	var step := 1.0 / 120.0
	# 先归零再从干净状态抬升：上一步刚抬过一次，直接再抬会走连射叠加分支，
	# 起始量变成 `peak × 1.55`，过冲率的归一基准就错了。
	weapon.call("_reset_fire_feedback")
	weapon.call("_apply_fire_feedback")
	for index in range(180):
		weapon.call("_process", step)
		elapsed += step
		var current := float(weapon.get("_punch"))
		min_punch = minf(min_punch, current)
		if stretch_at < 0.0 and current < -0.01:
			stretch_at = elapsed
		if settled_at < 0.0 and absf(current) < 0.005 and absf(float(weapon.get("_punch_velocity"))) < 0.02:
			settled_at = elapsed
		_samples += 1
	_expect(min_punch < -0.01, "霰弹：压扁后没有反向拉长（最小压幅 %.4f）——弹回被写成了单调衰减" % min_punch)
	var stretch_ratio := absf(min_punch) / maxf(0.0001, punch_peak)
	_expect(
		absf(stretch_ratio - EXPECTED_PUNCH_OVERSHOOT) <= OVERSHOOT_TOLERANCE,
		"霰弹：拉长过冲率期望 %.3f±%.2f，实测 %.3f（ζ=0.50 的解析值 0.163）" % [
			EXPECTED_PUNCH_OVERSHOOT, OVERSHOOT_TOLERANCE, stretch_ratio
		]
	)
	# 相位：霰弹 punch_hz = 5.6 ⇒ 半周期 0.089 s，拉长出现在 0.09~0.12 s 之间。
	_expect(
		stretch_at > 0.03 and stretch_at < 0.20,
		"霰弹：拉长相位期望 0.03~0.20 s，实测 %.3f s" % stretch_at
	)
	# 时长：必须在下一发之前收住。霰弹 1.2 发/秒 ⇒ 间隔 0.833 s，留 15% 余量取 0.71 s。
	# 超过这个值说明压扁拖到了下一发，连射时会糊成常量。
	_expect(
		settled_at > 0.0 and settled_at < 0.71,
		"霰弹：弹回时长期望 <0.71 s（不跨发，间隔 0.833 s），实测 %.3f s" % settled_at
	)

	# 反向对照：把压扁清零后必须回到各向同性（= 纯 fate 基准），不能再有 x≠z。
	weapon.set("_punch", 0.0)
	weapon.set("_punch_velocity", 0.0)
	weapon.call("_process", 1.0 / 240.0)
	var settled := punch_root.scale
	_expect(
		is_equal_approx(settled.x, settled.z) and is_equal_approx(settled.x, settled.y),
		"霰弹：压扁归零后缩放必须各向同性，实测 %s" % str(settled)
	)
	weapon.free()


## ④ 弹道/冷却不受表现层影响：缩放不旋转 muzzle 的 −Z，射击间隔仍是 1/fire_rate。
func _check_no_ballistic_side_effect() -> void:
	var weapon := _make_weapon("bp_pistol")
	if weapon == null:
		return
	weapon.set_process(false)
	var aim := Vector3(0.0, 0.0, -1.0)
	var visual_root := weapon.get("_visual_root") as Node3D
	if visual_root == null:
		_failures.append("手枪：武器没有视觉根节点，形变通道不可测")
		weapon.free()
		return
	var before := visual_root.scale
	var damage_before := int(weapon.get("damage"))
	weapon.call("_apply_fire_feedback")
	var fired: bool = bool(weapon.call("_fire_now", aim, weapon, 1.0))
	_expect(fired, "手枪：正式开火入口拒绝了这次射击（前置条件不满足）")
	# 冷却必须在 `_process` 递减之前读：射击间隔只由 `fire_rate` 决定。
	_expect(
		is_equal_approx(float(weapon.get("_cooldown")), 1.0 / float(weapon.get("fire_rate"))),
		"手枪：后坐表现改写了冷却，期望 %.4f s，实测 %.4f s" % [
			1.0 / float(weapon.get("fire_rate")), float(weapon.get("_cooldown"))
		]
	)
	# 反向对照：表现层不得改写伤害/弹速这些玩法量（伤害的具体值由
	# `verify_starting_weapon_contract` 钉，这里只钉「本通道没碰它」）。
	_expect(
		int(weapon.get("damage")) == damage_before,
		"手枪：表现层改动了伤害，开火前 %d、开火后 %d" % [damage_before, int(weapon.get("damage"))]
	)
	weapon.call("_process", 1.0 / 240.0)
	# 缩放是各向异性的：muzzle 的 −Z **方向**必须一动不动（只改长度不改朝向）。
	var muzzle := weapon.find_child("MuzzleSocket", true, false) as Node3D
	_expect(muzzle != null, "手枪：找不到 MuzzleSocket，无法验证枪口朝向")
	if muzzle != null:
		var muzzle_forward := (-muzzle.global_basis.z).normalized()
		var angle := rad_to_deg(muzzle_forward.angle_to(aim))
		_expect(angle < 0.5, "手枪：形变改变了枪口朝向，与瞄准夹角 %.3f°" % angle)
	_expect(not before.is_equal_approx(visual_root.scale), "手枪：开火后缩放没有变化，形变通道未生效")
	weapon.free()
	await get_tree().process_frame


## ⑤ 机枪连射：刷新语义 —— 每发拉到至少峰值，上界恒为 `peak`，绝不累加鼓成气球。
##    这一节同时钉住「sustained ≥ peak」，即连射不会比单发更弱（旧累加语义的毛病）。
func _check_machinegun_stacking() -> void:
	var weapon := _make_weapon("bp_machinegun")
	if weapon == null:
		return
	weapon.set_process(false)
	var peak := float(EXPECTED_FEEDBACK["bp_machinegun"]["punch"])
	var first := 0.0
	var last := 0.0
	var interval := 1.0 / 12.0
	for index in range(6):
		weapon.call("_apply_fire_feedback")
		var current := float(weapon.get("_punch"))
		if index == 0:
			first = current
		last = current
		# 按机枪真实射速推进到下一发，不手动清零：这才是稳态。
		weapon.call("_process", interval)
	_samples += 1
	_expect(is_equal_approx(first, peak), "机枪：首发压扁应为峰值 %.3f，实测 %.4f" % [peak, first])
	_expect(is_equal_approx(last, peak), "机枪：连射中每发都应刷新到峰值 %.3f，实测 %.4f" % [peak, last])
	_expect(last <= peak + 0.0001, "机枪：连射压扁超过峰值上限 %.3f，实测 %.4f（会鼓成气球）" % [peak, last])
	# 反向对照：两发之间的谷值必须真的下降过 —— 否则不是「脉动」而是恒定量。
	var trough := 999.0
	for index in range(20):
		weapon.call("_process", interval / 20.0)
		trough = minf(trough, float(weapon.get("_punch")))
	_expect(trough < peak * 0.92, "机枪：连射谷值 %.4f 未明显下降（峰值 %.3f），不是脉动而是常量" % [trough, peak])
	weapon.free()


## ⑥ 分档关系：重枪的后坐位移必须大于轻枪、回弹必须更慢。
func _check_ordering() -> void:
	var pistol := float(EXPECTED_FEEDBACK["bp_pistol"]["kick_m"])
	var shotgun := float(EXPECTED_FEEDBACK["bp_shotgun"]["kick_m"])
	var sniper := float(EXPECTED_FEEDBACK["bp_sniper"]["kick_m"])
	var machinegun := float(EXPECTED_FEEDBACK["bp_machinegun"]["kick_m"])
	_expect(shotgun > pistol * 1.4, "霰弹位移应显著大于手枪（%.3f vs %.3f）" % [shotgun, pistol])
	_expect(sniper > pistol, "狙击位移应大于手枪（%.3f vs %.3f）" % [sniper, pistol])
	_expect(machinegun < pistol, "机枪单发位移应小于手枪（靠连射叠加出震颤）：%.3f vs %.3f" % [machinegun, pistol])
	_expect(
		float(EXPECTED_FEEDBACK["bp_sniper"]["hz"]) < float(EXPECTED_FEEDBACK["bp_pistol"]["hz"]),
		"狙击回弹频率应低于手枪（重枪慢回弹）"
	)
	_expect(
		float(EXPECTED_FEEDBACK["bp_shotgun"]["punch"]) > float(EXPECTED_FEEDBACK["bp_pistol"]["punch"]),
		"霰弹压扁应大于手枪"
	)
	# 压扁弹簧频率：轻枪快、重枪慢（和位移弹簧同向）。
	_expect(
		float(EXPECTED_FEEDBACK["bp_shotgun"]["punch_hz"]) < float(EXPECTED_FEEDBACK["bp_machinegun"]["punch_hz"]),
		"霰弹压扁节奏应慢于机枪"
	)
	_expect(
		float(EXPECTED_FEEDBACK["bp_pistol"]["roll"]) > float(EXPECTED_FEEDBACK["bp_sniper"]["roll"]),
		"狙击的压扁侧倾应小于手枪（贴腮要稳）"
	)


func _make_weapon(gun_id: String) -> WeaponModel3D:
	var weapon := WEAPON_MODEL_SCENE.instantiate() as WeaponModel3D
	if weapon == null:
		_failures.append("%s：武器模型场景根节点不是 WeaponModel3D" % gun_id)
		return null
	add_child(weapon)
	var tree := BlueprintRegistry.build_weapon_tree(gun_id, "mod_bullet_standard")
	if tree == null or not weapon.configure_from_tree(tree):
		_failures.append("%s：装配树构建或配置失败（GUN_FIRE_FEEDBACK 分档不可测）" % gun_id)
		weapon.free()
		return null
	weapon.global_position = Vector3(3.0, 1.0, 5.0)
	return weapon


## 开火会把投射物挂到 current_scene（=本测试根节点），退出前必须清掉，
## 否则套件按 ObjectDB 泄漏判 4。
func _purge_transients() -> void:
	for child in get_children():
		if child is WeaponModel3D:
			continue
		child.free()


func _report() -> void:
	_purge_transients()
	if _samples < EXPECTED_MIN_SAMPLES:
		_failures.append("哨兵失败：有效断言只有 %d 条，低于下限 %d —— 用例可能被短路" % [_samples, EXPECTED_MIN_SAMPLES])
	if _failures.is_empty():
		print("WEAPON_FIRE_FEEDBACK_OK: 9 gun profiles / recoil spring / squash-stretch envelope / visibility floor / ballistic isolation / stacking / ordering pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("WEAPON_FIRE_FEEDBACK_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)
