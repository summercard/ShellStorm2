extends Node3D

## 门禁：33 只 EGT 复刻怪的**子弹真的能飞出来、且看得见**。
##
## 这是业主报「很多小怪没有通过检验，子弹特效都飞不出来」之后补的检验。
## 之前所有探针都只验「有没有排队射击事件」，**没有一条验过子弹在场景里是否可见**，
## 所以"排队 8 发但玩家一个都看不到"能一路绿灯通过。
##
## 断言三类：
##   ① 会开火的怪（volley / chance / orbit）开火后场上必须出现 Projectile3D；
##   ② 每发子弹必须有视觉实例且 `visible`（visual 挂 null 或隐藏都是失败）；
##   ③ 子弹必须带射程与合理弹速 —— 没有射程的子弹只有 1 秒寿命，
##      16 m/s 时飞 16m 就自毁，读起来就是"子弹飞到一半消失"。
##
## 不验手感，只验"存在且可见"。

const ENEMY_SCRIPT_PATH := "res://src/enemy3d/Enemy3D.gd"

## 会发射子弹的骨架。其余（contact / explode / rush / support / grab / flee / disguise）
## 不开火 —— 它们**不该**有子弹，不能拿"没子弹"当失败。
const SHOOTING_STYLES := ["volley", "chance", "orbit"]

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	var kinds: Array = Enemy3D.PROFILES.keys().filter(
		func(k): return str(k).begins_with("egt_")
	)
	kinds.sort()
	print("=== EGT 子弹可见性门禁（%d 只）===" % kinds.size())
	for kind in kinds:
		await _probe_kind(str(kind))
	print("")
	if _failures.is_empty():
		print("EGT_BULLET_VISUAL_PROBE_OK %d 只会开火的怪：子弹均存在、有视觉、带射程" % kinds.size())
	else:
		print("EGT_BULLET_VISUAL_PROBE_FAIL count=%d" % _failures.size())
		for item in _failures:
			print("  - ", item)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _probe_kind(kind: String) -> void:
	var enemy := (load(ENEMY_SCRIPT_PATH) as GDScript).new() as Enemy3D
	enemy.enemy_kind = kind
	add_child(enemy)
	enemy.global_position = Vector3.ZERO
	await get_tree().physics_frame
	enemy.apply_profile(kind)
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -6)
	enemy._target = target

	var style := enemy._egt_attack_style()
	# chance（骰子布洛布）会**随机借用同族招式**，其中 `contact` 那次本来就不出弹。
	# 打一次就判"没子弹"是拿随机性当缺陷 —— 多打几轮，只要有一轮出弹就算它合格。
	var rounds := 6 if style == "chance" else 1
	for _round in range(rounds):
		enemy._perform_attack(Vector3(0, 0, -1), 6.0)
	# 连发型（interval>0）与绕圈链（orbit）不是当帧出手：
	# 不推进足够的帧，统计到的永远是 0 —— 那是探针的错，不是怪的错。
	if style == "orbit":
		for _i in range(40):
			await get_tree().physics_frame
	else:
		await get_tree().physics_frame
		await get_tree().physics_frame

	# **只统计这只怪打出的子弹**。早期版本用"总数差"，上一只的子弹还没回收时
	# 会让计数变成 -1，还会把别家的弹速算进自己的最小值 —— 那两个假失败都是探针自身缺陷。
	var mine: Array[Projectile3D] = []
	for node in _collect_projectiles(self):
		var proj := node as Projectile3D
		if proj != null and proj.shooter == enemy:
			mine.append(proj)
	var spawned := mine.size()

	var ok_visual := 0
	var bad_visual := 0
	var min_speed := 999.0
	var min_range := 999.0
	for proj in mine:
		var visual: Variant = proj.get("_visual")
		if visual == null or not (visual as Node3D).visible:
			bad_visual += 1
		else:
			ok_visual += 1
		min_speed = minf(min_speed, float(proj.get("speed")))
		min_range = minf(min_range, float(proj.get("range_m")))

	print(
		"  %-22s style=%-8s 新弹=%-2d visual(ok/bad)=%d/%d speed=%s range=%s"
		% [
			kind, style, spawned, ok_visual, bad_visual,
			("—" if min_speed > 900.0 else "%.1f" % min_speed),
			("—" if min_range > 900.0 else "%.1f" % min_range),
		]
	)

	# ① 会开火的骨架必须真的出弹
	if style in SHOOTING_STYLES and spawned <= 0:
		# 拟态怪伪装态本就该拦下 —— 那是正确行为，不是缺口。
		if not (kind == "egt_mimic" and enemy._disguised):
			_failures.append("%s（style=%s）开火后场上 0 发子弹" % [kind, style])
	# ② 视觉
	if bad_visual > 0:
		_failures.append("%s 有 %d 发子弹的视觉为空或隐藏" % [kind, bad_visual])
	# ③ 射程与弹速
	# ③ 射程与弹速。
	# 弹速这里**只校验配置层**（`profile.projectile_speed`），不校验单发实际值 ——
	# 因为「吐蛋 4.2 m/s」「链球 6.4 m/s」是**刻意慢**的：蛋要慢慢飞过去才读得出"蛋"，
	# 链要绕圈才形成"链"。拿单发值判"飘"会把这些设计意图当成 bug。
	# 真正会露馅的是「配置层压根没设弹速」⇒ 落到全局默认 7 m/s 且没有射程。
	if spawned > 0:
		if min_range <= 0.0:
			_failures.append("%s 的子弹没有射程（只有 1 秒寿命，会半路消失）" % kind)
		var profile_speed := float(enemy._active_profile.get("projectile_speed", 0.0))
		# 例外：`volley.speed` 显式声明了更慢的弹速 ⇒ 那是**刻意的形态**，不是遗漏。
		# 例：Gigi 的吐蛋 4.2 m/s —— 蛋要慢慢飞过去才读得出"蛋"；链球 6.4 同理。
		# 门禁要抓的是"压根没设弹速、落到全局默认"，不是"故意设得慢"。
		var declares_slow := (
			enemy._active_profile.get("volley", {}) is Dictionary
			and (enemy._active_profile.get("volley", {}) as Dictionary).has("speed")
		)
		if profile_speed < 6.0 and not declares_slow:
			_failures.append(
				"%s 配置层 projectile_speed=%.1f < 6（低于此会读成静止飘浮，而不是射击）" % [kind, profile_speed]
			)

	enemy.queue_free()
	target.queue_free()
	await get_tree().process_frame


func _count_projectiles(root: Node) -> int:
	return _collect_projectiles(root).size()


func _collect_projectiles(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if child is Projectile3D:
			out.append(child)
		out.append_array(_collect_projectiles(child))
	return out
