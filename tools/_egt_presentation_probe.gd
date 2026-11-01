extends Node
## 远征03 怪物「表现层三件事」专项验收（2026-10-31 业主报单）。
##
## 三件事各自独立，失败互不掩盖：
##   ① **移除附加几何**：33只均不生成程序化变种标识件（2026-11-02用户修订）；
##   ② **受击不漂移**：受击姿态只在「站定」时播；太阳伤害这类环境结算**完全不播**；
##   ③ **不绕圈**：远程怪在远处**直线逼近**、到位**站住**、太近才后撤，而不是满速绕玩家转。
##
## 用法：`godot --headless --path . --scene res://tools/_egt_presentation_probe.tscn`
## ⚠ 必须 `--scene`（要 autoload 与 `Enemy3D` 的依赖）。
##
## ## 判据为什么是这三条
## ①来自业主要求去掉球/方块附加件；②来自「一边移动一边受到反馈动画，就变成漂移」。
## ③ 来自「有几只怪会环绕角色走，不会直着对着角色过来」。三条都能被**数值**证伪：
##   · ② 断言的是 `clip != "hurt"` 而不是"看起来没飘"——旧实现 0.8 s 内 chase 也被覆盖；
##   · ③ 断言的是速度与径向的**点积**与**平面速度**：绕圈时点积 ≈ 0 且速度是满速，
##     旧的 `tangent * 0.78 + radial * radial_weight` 就是这个形状，改动前后数值会翻面。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const INJECTOR := preload("res://src/map/MonsterInjector.gd")

## 站定判据：平面速度低于它算"已经到位"。
## 取值依据：最慢的怪（gunsinger 1.0 m/s）也在 0.35 系数下 ≥0.35 m/s，
## 而"站住"分支输出 `Vector3.ZERO`（再经 `_steer_planar(delta*5.5)` 平滑收掉），实测应 < 0.15。
const STAND_SPEED_MPS := 0.30
## 逼近判据：速度方向与"指向玩家"的点积。1.0 = 正对着走，0 = 纯切向（绕圈）。
const APPROACH_DOT_MIN := 0.85
## 后撤判据：太快贴脸时必须往外走。
const RETREAT_DOT_MAX := -0.55

var _failures: Array[String] = []
var _rows: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _ready() -> void:
	print("=== EGT_PRESENTATION_PROBE 表现层三件事 ===")
	_check_distinction_attached()
	_check_hurt_pose()
	_check_sunlight_no_feedback()
	_check_locomotion_clip()
	_check_death_carries_zombie_rules()
	await _check_approach()
	_finish()


# ── ① 逐只确认附加标识件已移除 ───────────────────────────────────────────
func _check_distinction_attached() -> void:
	var injector := INJECTOR.new()
	var kinds: Array[String] = []
	for kind in injector.BASE_ENEMY_TYPES.keys():
		if str(kind).begins_with("egt_"):
			kinds.append(str(kind))
	kinds.sort()
	for kind in kinds:
		var data: Dictionary = injector.generate_box_enemy(kind, 1, 1)
		if data.is_empty():
			_failures.append("%s 无法生成" % kind)
			continue
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		if enemy == null:
			_failures.append("%s 预制体实例化失败" % kind)
			continue
		add_child(enemy)
		enemy.configure_from_enemy_data(data)
		var info: Dictionary = enemy.avatar.get_component_snapshot()
		var distinction: Dictionary = info.get("distinction", {})
		_check(not bool(distinction.get("attached", false)), "%s仍挂着程序化变种件" % kind)
		_check(int(distinction.get("piece_count", -1)) == 0, "%s仍有程序化球/方块标识件" % kind)
		_check(enemy.avatar.find_children("Distinction*", "Node3D", true, false).is_empty(), "%s节点树仍有标识容器" % kind)
		_rows.append("%-24s 无附加标识件" % kind)
		enemy.queue_free()
	print("[附加几何] 33只均应无标识件")
	for row in _rows:
		print(row)
	_rows.clear()


# ── ② 受击姿态：跑动不播、站定才播、环境伤害不播 ───────────────────────────
func _check_hurt_pose() -> void:
	# 用小僵尸模型的怪代表（业主原话「先调试用小僵尸模型做的怪物」）。
	for kind in ["egt_blobulon", "egt_bullet_kin", "egt_gun_nut"]:
		var enemy := _spawn(kind)
		if enemy == null:
			continue
		var avatar := enemy.avatar

		# 站定挨打 ⇒ 允许踉跄
		avatar.flash_hit(true)
		avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
		var standing := _hurt_visible(enemy)
		_check(standing, "%s 站定挨打应播受击姿态" % kind)

		# 追击中挨打 ⇒ 只闪白，不许播受击姿态（这就是"漂移"的根因）
		avatar.flash_hit(true)
		avatar.sync_presentation("chase", 0.0, 4.0, 0.38, 0.34)
		var running := _hurt_visible(enemy)
		_check(not running, "%s 追击中挨打仍在播受击姿态（会漂移）" % kind)
		print("[受击] %-20s 站定=%s 追击=%s" % [kind, _clip(enemy), _clip(enemy)])

		# 环境伤害（太阳）⇒ 连闪白之外什么都不该有
		avatar.flash_hit(false)
		avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
		var sun := _hurt_visible(enemy)
		_check(not sun, "%s 太阳伤害仍在播受击姿态" % kind)
		enemy.queue_free()


## 太阳伤害的判据在**调用点**（`_tick_illumination_effects` 直接扣血、不走 take_damage），
## 运行时没法在无光照世界里造出"阳光直射"状态，所以这里做源码级守卫：
## 该函数体内一旦出现 `flash_hit` / `transition_to("stagger")` 就是回归。
func _check_sunlight_no_feedback() -> void:
	var file := FileAccess.open("res://src/enemy3d/Enemy3D.gd", FileAccess.READ)
	if file == null:
		_failures.append("读不到 Enemy3D.gd，无法做太阳伤害守卫")
		return
	var text := file.get_as_text()
	var start := text.find("func _tick_illumination_effects")
	if start < 0:
		_failures.append("找不到 _tick_illumination_effects")
		return
	var end := text.find("\nfunc ", start + 10)
	var body := text.substr(start, (end if end > start else text.length()) - start)
	_check(not body.contains("flash_hit"), "太阳伤害里仍有 flash_hit（受击反馈）")
	_check(not body.contains("stagger"), "太阳伤害里仍在切 stagger")
	print("[太阳] 守卫通过：%s" % ("无受击反馈" if not body.contains("flash_hit") else "仍有 flash_hit"))


## 移动段必须跟着**实际速度**走，不能只看状态名。
##
## 业主："小僵尸和警察僵尸移动的时候都没使用跑步动画"。根因是复刻怪的突进（11 m/s）、
## 逃跑（×1.45）、游荡、瞬移重定位都是外推位移，`ai_state` 常停在 patrol 甚至 idle，
## 只按状态名给段就会"高速移动却播走路 / 站立"。
##
## 断言用**同一状态、两种速度**对比：这是唯一能把"按速度改判"和"按状态名给段"分开的形状。
## 只测一种速度的话，旧实现也能蒙对（chase → running 本来就是对的）。
func _check_locomotion_clip() -> void:
	for kind in ["egt_blobulon", "egt_bullet_kin", "egt_gun_nut"]:
		var fast := _clip_after(kind, "patrol", 1.0)
		var slow := _clip_after(kind, "patrol", 0.25)
		var idle_fast := _clip_after(kind, "idle", 1.0)
		_check(_is_run_clip(fast), "%s 巡逻状态满速移动仍在播走路段（%s）" % [kind, fast])
		_check(_is_walk_clip(slow), "%s 巡逻状态慢速却在播跑步段（%s）" % [kind, slow])
		_check(not _is_idle_clip(idle_fast), "%s 站立状态高速位移仍在播站立段（%s），这就是漂移" % [kind, idle_fast])
		print("[移动段] %-20s 满速=%s 慢速=%s 站立高速=%s" % [kind, fast, slow, idle_fast])


## 走**真实时序**取移动段：先以目标速度进入状态（此时补间事件开始），
## 再把 `state_time` 推到 2 s 让起步/转身这类一次性事件自然播完，最后读段名。
##
## 不这样做的话，量到的是"起步段"（`move_start`）而不是"持续移动段"，
## 那是把事件的第 0 帧当成常态 —— 会得出"胖子永远不会跑步"的假结论。
func _clip_after(kind: String, state: String, speed_ratio: float) -> String:
	var enemy := _spawn(kind)
	if enemy == null:
		return ""
	var base: float = enemy.get_effective_move_speed()
	var avatar := enemy.avatar
	avatar.sync_presentation(state, 0.0, base * speed_ratio, 0.38, 0.34, base)
	avatar.sync_presentation(state, 2.0, base * speed_ratio, 0.38, 0.34, base)
	var clip := _clip(enemy)
	enemy.queue_free()
	return clip


func _is_run_clip(clip: String) -> bool:
	return clip.contains("running")


func _is_walk_clip(clip: String) -> bool:
	return clip.contains("walking")


func _is_idle_clip(clip: String) -> bool:
	return clip.contains("idle")


## 死亡表现：借了僵尸模型的复刻怪必须继承僵尸的死亡口径（无倒地动画、无尸体）。
##
## 业主："被干掉后也不需要到底动画，直接使用小僵尸的死亡特效"。
## 这条规则本来就存在（`ZOMBIE_KINDS`），但它按 `enemy_kind` 判，而 egt 怪的 kind 是
## `egt_*` ⇒ 全部漏掉：每只 egt 怪死亡仍播 2.4~2.6 s 倒地段、还留一具尸体。
## 断言逐只跑 33 只，而不是抽查 —— 漏一只就是那种"某只怪倒下时要等两秒"的偶发现象。
func _check_death_carries_zombie_rules() -> void:
	var injector := INJECTOR.new()
	var counts := {"no_corpse": 0, "goo": 0, "total": 0}
	for kind in injector.BASE_ENEMY_TYPES.keys():
		if not str(kind).begins_with("egt_"):
			continue
		var enemy := _spawn(str(kind))
		if enemy == null:
			continue
		counts["total"] = int(counts["total"]) + 1
		var asset := EnemyAvatar3D.resolve_asset_kind(str(kind))
		var expects_zombie := asset in ["melee_chaser", "ranged_caster", "fat_zombie03"]
		_check(
			enemy.uses_no_corpse_death() == expects_zombie,
			"%s（借 %s）的 no_corpse 判定错：期望 %s" % [kind, asset, expects_zombie]
		)
		if expects_zombie:
			counts["no_corpse"] = int(counts["no_corpse"]) + 1
		# 特效分两支：小僵尸 / 警察走绿方块，胖子走重型自爆。
		if asset in ["melee_chaser", "ranged_caster"]:
			_check(enemy.uses_goo_death_burst(), "%s（借 %s）死亡没走绿色方块爆开" % [kind, asset])
			counts["goo"] = int(counts["goo"]) + 1
		enemy.queue_free()
	print("[死亡] 共 %d 只，无尸体 %d 只，绿方块爆开 %d 只" % [
		int(counts["total"]), int(counts["no_corpse"]), int(counts["goo"])
	])
	_check(int(counts["total"]) == 33, "死亡口径只跑了 %d 只，应为 33" % int(counts["total"]))


# ── ③ 逼近 / 站定 / 后撤 ───────────────────────────────────────────────────
##
## 直接调 `_tick_chase`（**不是**另写一份复刻逻辑，那种测试会"绿得没有意义"）：
## 每只怪重复推进若干帧到速度稳态，再读 `velocity`。
## 旧实现在站位附近输出纯切向满速 ⇒ 点积 ≈ 0、平面速度 ≈ 满速，本函数当场红。
func _check_approach() -> void:
	var kinds := ["egt_bullet_kin", "egt_blue_shotgun", "egt_chain_gunner", "egt_bookllet"]
	for kind in kinds:
		var enemy := _spawn(kind)
		if enemy == null:
			continue
		var player := Node3D.new()
		player.set("current_hp", 100.0)
		add_child(player)
		player.global_position = Vector3.ZERO
		var range_m: float = float(enemy.attack_range)
		var ideal := range_m * 0.70
		enemy.set("_target", player)
		# 冷却锁住：否则 `_tick_chase` 一进来就会请求攻击令牌并转 telegraph。
		enemy.set("_attack_timer", 999.0)
		enemy.transition_to("chase")

		var far_dot := await _drive(enemy, player, range_m * 0.98)
		var ideal_speed := await _drive_speed(enemy, player, ideal)
		var near_dot := await _drive(enemy, player, range_m * 0.35)
		_rows.append("%-22s 远dot=%+.2f 站位速度=%.2fm/s 近dot=%+.2f" % [kind, far_dot, ideal_speed, near_dot])
		_check(far_dot >= APPROACH_DOT_MIN, "%s 远处没有直线逼近（dot=%.2f）—— 在绕圈" % [kind, far_dot])
		_check(ideal_speed <= STAND_SPEED_MPS, "%s 已在站位却仍在动（%.2fm/s，判据 ≤%.2f）—— 在绕圈" % [kind, ideal_speed, STAND_SPEED_MPS])
		_check(near_dot <= RETREAT_DOT_MAX, "%s 贴脸时没有后撤（dot=%.2f）" % [kind, near_dot])
		player.queue_free()
		enemy.queue_free()
	print("[走位]")
	for row in _rows:
		print(row)
	_rows.clear()


## 把怪摆到 `distance` 处、推进到速度稳态，返回「速度方向 · 指向玩家」的点积。
func _drive(enemy: Enemy3D, player: Node3D, distance: float) -> float:
	_place(enemy, distance)
	for step in 40:
		await get_tree().physics_frame
		var to_target: Vector3 = player.global_position - enemy.global_position
		to_target.y = 0.0
		enemy._tick_chase(to_target, to_target.length(), get_physics_process_delta_time())
	var radial := (player.global_position - enemy.global_position)
	radial.y = 0.0
	if radial.length_squared() < 0.0001:
		return 0.0
	var planar := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
	if planar.length_squared() < 0.0001:
		# 站着不动时"方向"没有意义；用"有没有在动"另行判定（见 `_drive_speed`）。
		return 0.0
	return planar.normalized().dot(radial.normalized())


## 同上，但返回平面速度（用于判"是不是站住了"）。
func _drive_speed(enemy: Enemy3D, player: Node3D, distance: float) -> float:
	_place(enemy, distance)
	for step in 40:
		await get_tree().physics_frame
		var to_target: Vector3 = player.global_position - enemy.global_position
		to_target.y = 0.0
		enemy._tick_chase(to_target, to_target.length(), get_physics_process_delta_time())
	return Vector3(enemy.velocity.x, 0.0, enemy.velocity.z).length()


func _place(enemy: Enemy3D, distance: float) -> void:
	enemy.global_position = Vector3(0, 1.0, distance)
	enemy.velocity = Vector3.ZERO


func _spawn(kind: String) -> Enemy3D:
	var injector := INJECTOR.new()
	var data: Dictionary = injector.generate_box_enemy(kind, 1, 1)
	if data.is_empty():
		_failures.append("%s 无法生成" % kind)
		return null
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("%s 预制体实例化失败" % kind)
		return null
	add_child(enemy)
	enemy.configure_from_enemy_data(data)
	# 冻住物理与 AI：本探针只驱动 `_tick_chase`，不能让引擎自己的 `_physics_process`
	# 抢着改速度（否则量到的是两份逻辑的叠加）。
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy


func _clip(enemy: Enemy3D) -> String:
	var info: Dictionary = enemy.avatar.get_component_snapshot()
	var presentation: Dictionary = info.get("presentation", {})
	return str(presentation.get("clip", ""))


## 三只模型的受击表现形式**本来就不同**，所以判据不能统一看 clip 名：
##   · 小僵尸 / 保安僵尸：整段换 `hurt` 段 ⇒ 看 `clip`；
##   · 胖子：只混合上半身骨骼（`hit_light`），主段仍是 idle/running ⇒ 看 `hit_light_active`。
## 两种都表达"此刻有没有在演受击"。若统一看 clip，胖子会被永远判成"没播"，
## 那条断言就成了摆设。
func _hurt_visible(enemy: Enemy3D) -> bool:
	var info: Dictionary = enemy.avatar.get_component_snapshot()
	var presentation: Dictionary = info.get("presentation", {})
	if presentation.has("hit_light_active"):
		return bool(presentation.get("hit_light_active", false))
	return str(presentation.get("clip", "")) == "hurt"


func _finish() -> void:
	if _failures.is_empty():
		print("EGT_PRESENTATION_PROBE_OK")
	else:
		print("EGT_PRESENTATION_PROBE_FAILED（%d 项）" % _failures.size())
		for failure in _failures:
			print("  ✗ %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
