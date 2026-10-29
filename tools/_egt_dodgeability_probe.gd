extends Node3D

## 可躲性验证：这一层的弹幕**有没有躲避解**，以及**靠什么躲**。
##
## 业主口径「敌人的子弹速度和伤害还有方式，要重点对齐」——
## 「速度」不能只说"改小了"，要能算出玩家怎么躲。
##
## 关键区分（第一版判据在这里出过错）：
##   **弹幕永远以"朝玩家"为中心展开**，所以玩家必然站在扇形正中。
##   窄弹（单发/紧密扇形）⇒ 横移半个弹道宽就能出界 ⇒ **走位可躲**。
##   宽扇形（90° / ±26°）⇒ 横移距离远超玩家速度 ⇒ **原作也是靠翻滚无敌帧躲的**。
##     EGT 的 Gun Nut 就是 90° 弧，玩家公认要翻滚穿，不是走位绕。
##   ⇒ 把这两类混在一起判"可躲"，会得出"90° 扇形设计有问题"的错误结论。
##
## 三类判据：
##   ① 窄弹（半宽 < 1.0m）：必须**走位可躲**（move > half）
##   ② 宽扇形（半宽 ≥ 1.0m）：不要求走位可躲，只要求**翻滚可躲**
##      （到达时间 > 可反应时间 + 翻滚前摇）
##   ③ 近身型（交战距离 < 3m）：不是弹幕对射，跳过
##
## 探针不判手感，只判「有没有解」。

## 玩家参数（与 Player3D 同源，改那边要同步这里）
const PLAYER_SPEED := 4.5       ## Player3D.SPEED
const REACTION_SEC := 0.25      ## 人类视觉反应下限
const ROLL_DURATION := 0.204    ## Player3D.DASH_DURATION

## 子弹自身半径 + 玩家半径：单发直射时几何宽度为 0，实际判定面约 0.52m
const PROJECTILE_HIT_HALF_WIDTH := 0.52
## 判定"这是宽扇形还是窄弹"的分界
const NARROW_HALF_WIDTH := 1.0
## 交战距离短于此视为近身型（不靠弹幕对射）
const MELEE_DISTANCE := 3.0

var _rows: Array[Dictionary] = []


func _ready() -> void:
	await get_tree().process_frame
	var kinds: Array = Enemy3D.PROFILES.keys().filter(
		func(k): return str(k).begins_with("egt_")
	)
	kinds.sort()
	print("=== 可躲性验证（玩家 %.1f m/s，反应 %.2fs，翻滚 %.3fs）===" % [PLAYER_SPEED, REACTION_SEC, ROLL_DURATION])
	print("%-24s %-6s %-6s %-6s %-7s %-8s %s" % ["kind", "弹速", "距离", "半宽", "可横移", "类型", "判定"])

	for kind in kinds:
		_analyze(str(kind))

	print("")
	var failures: Array[String] = []
	for row in _rows:
		if str(row["verdict"]) != "OK":
			failures.append("%s —— %s" % [row["kind"], row["verdict"]])
	if failures.is_empty():
		print("EGT_DODGEABILITY_PROBE_OK %d 只会开火的怪：窄弹走位可躲、宽扇形翻滚可躲" % _rows.size())
	else:
		print("EGT_DODGEABILITY_PROBE_FAIL count=%d" % failures.size())
		for item in failures:
			print("  - ", item)
	get_tree().quit(0 if failures.is_empty() else 1)


func _analyze(kind: String) -> void:
	var profile := Enemy3D.profile_for(kind)
	var style := str(profile.get("attack_style", ""))
	if not (style in ["volley", "chance"]):
		# orbit（链枪手）是贴身绕圈，不是对射；grab/support/contact 不发射弹幕
		return

	var speed := float(profile.get("projectile_speed", 0.0))
	var distance := float(profile.get("range", 8.0))
	var spec: Dictionary = profile.get("volley", {}) as Dictionary
	if spec.has("speed"):
		speed = float(spec["speed"])
	if distance < MELEE_DISTANCE:
		print("%-24s %-6.1f %-6.1f %-6s %-7s %-8s %s" % [kind, speed, distance, "—", "—", "近身型", "跳过"])
		return

	var spread_deg := float(spec.get("spread_deg", 0.0))
	var half := maxf(PROJECTILE_HIT_HALF_WIDTH, distance * tan(deg_to_rad(spread_deg)))
	var travel := distance / maxf(0.1, speed)
	var move := PLAYER_SPEED * maxf(0.0, travel - REACTION_SEC)

	var verdict := "OK"
	var kind_label := ""
	if half < NARROW_HALF_WIDTH:
		kind_label = "窄弹"
		if move <= half:
			verdict = "窄弹却走位躲不掉（可移 %.2f ≤ 半宽 %.2f）" % [move, half]
	else:
		kind_label = "宽扇形"
		# 宽扇形只要求"看到后还来得及起跳翻滚"
		if travel <= REACTION_SEC + ROLL_DURATION * 0.5:
			verdict = "宽扇形且来不及翻滚（到达 %.2fs ≤ 反应+半翻滚）" % travel

	_rows.append({"kind": kind, "verdict": verdict})
	print(
		"%-24s %-6.1f %-6.1f %-6.2f %-7.2f %-8s %s"
		% [kind, speed, distance, half, move, kind_label, ("可躲" if verdict == "OK" else verdict)]
	)
