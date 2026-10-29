extends Node
## 远征03 复刻怪的**注册一致性**验证探针（2026-10-29 第二批）
##
## 要证的事只有一件：**33 种非 Boss 敌人，在九个注册点上一个都不能漏。**
##
## 为什么必须专门写这个：这套体系里「漏登记」不会报错，只会**静默降级** ——
##   · 漏 `PROXY_ASSET_KIND` ⇒ `configure()` 判未知 ⇒ 表现退化成一只小僵尸
##   · 漏 `COLORS`/`FORMAL_MODEL_TINT` ⇒ 同族几只长得一模一样，区分归零
##   · 漏 `BODY_SCALE_BY_KIND` ⇒ 拿到借用资产的体型（同族全部 1.0 / 0.78）
##   · 漏 `BASE_ENEMY_TYPES` ⇒ 刷怪盒整条失效、房间空着，且日志一个字都不说
##   · 漏 `stats.per_kind` ⇒ 数值回落到「楼层缩放 × 主题倍率」，与本关的绝对值口径冲突
##   · 漏 `ALLOWED_BOX_TYPES` ⇒ 盒子校验直接拒，编成表写了也调不到
## 所以本探针**逐只逐点**比对，缺一条就 FAIL 并指名道姓。
##
## 检查清单：
##   ① 九个注册点全覆盖（PROFILES / BODY_SCALE / HEALTH_BAR / PROXY_ASSET /
##      颜色通道 / BASE_ENEMY_TYPES / ENEMY_PRESENTATION / ALLOWED_BOX_TYPES / level_plan stats）
##   ② 颜色通道选对（正式 GLB 只吃 TINT，程序化外壳只吃 COLORS —— 见 `怪物设计.md §T3.4`）
##   ③ 血量与 EGT 原始值满足幂律换算（不是手填一个差不多的数）
##   ④ 攻击规格自洽（attack_style 与它依赖的键必须同时存在）
##   ⑤ 攻击冒烟：每只怪真打一次，不许抛错、不许零弹（远程族）
##
## 用法：godot --headless --path . --scene res://tools/_egt_monster_registry_probe.tscn
## ⚠ 必须 `--scene` 而非 `--script`：要实例化 Enemy3D，它依赖 autoload。

## 33 种非 Boss 敌人：`kind` → {family, egt_hp}。`egt_hp` 是《挺进地牢》第一层原值，
## **只用来复算换算公式**，不参与运行时。
const ROSTER := {
	# —— 2.1 子弹族 ——
	"egt_bullet_kin": {"family": "子弹族", "egt_hp": 15.0},
	"egt_bandana_kin": {"family": "子弹族", "egt_hp": 15.0},
	"egt_veteran_kin": {"family": "子弹族", "egt_hp": 15.0},
	"egt_cardinal": {"family": "子弹族", "egt_hp": 22.5},
	"egt_hollowpoint": {"family": "子弹族", "egt_hp": 25.0},
	# —— 2.2 霰弹枪族 ——
	"egt_red_shotgun": {"family": "霰弹枪族", "egt_hp": 30.0},
	"egt_blue_shotgun": {"family": "霰弹枪族", "egt_hp": 40.0},
	"egt_veteran_shotgun": {"family": "霰弹枪族", "egt_hp": 33.8},
	# —— 2.3 爆炸族 ——
	"egt_pinhead": {"family": "爆炸族", "egt_hp": 13.0},
	"egt_nitra": {"family": "爆炸族", "egt_hp": 10.0},
	"egt_king_bullat": {"family": "爆炸族", "egt_hp": 26.0},
	"egt_grenat": {"family": "爆炸族", "egt_hp": 3.0},
	# —— 2.4 分裂族 ——
	"egt_blobulon": {"family": "分裂族", "egt_hp": 20.0},
	"egt_blobuloid": {"family": "分裂族", "egt_hp": 10.0},
	"egt_blobulin": {"family": "分裂族", "egt_hp": 1.0},
	"egt_chancebulon": {"family": "分裂族", "egt_hp": 50.0},
	# —— 2.5 书怪族 ——
	"egt_bookllet": {"family": "书怪族", "egt_hp": 25.0},
	"egt_blue_bookllet": {"family": "书怪族", "egt_hp": 25.0},
	"egt_green_bookllet": {"family": "书怪族", "egt_hp": 25.0},
	# —— 2.6 法术 / 辅助族 ——
	"egt_gunjurer": {"family": "法术族", "egt_hp": 18.8},
	"egt_gigi": {"family": "法术族", "egt_hp": 12.0},
	"egt_gunsinger": {"family": "辅助族", "egt_hp": 15.0},
	# —— 2.7 一次性冲撞族 ——
	"egt_bullat": {"family": "冲撞族", "egt_hp": 1.0},
	"egt_shotgat": {"family": "冲撞族", "egt_hp": 2.0},
	"egt_spirat": {"family": "冲撞族", "egt_hp": 5.0},
	# —— 2.8 触发 / 逃逸型 ——
	"egt_keybullet_kin": {"family": "触发族", "egt_hp": 15.0},
	"egt_chance_kin": {"family": "触发族", "egt_hp": 15.0},
	"egt_confirmed": {"family": "触发族", "egt_hp": 45.0},
	"egt_mimic": {"family": "触发族", "egt_hp": 100.0},
	"egt_gun_fairy": {"family": "触发族", "egt_hp": 15.0},
	"egt_gripmaster": {"family": "触发族", "egt_hp": 30.0},
	# —— 2.9 重型 ——
	"egt_gun_nut": {"family": "重型族", "egt_hp": 100.0},
	"egt_chain_gunner": {"family": "重型族", "egt_hp": 90.0},
}

## 允许的攻击骨架。新增一种必须同时改 `_perform_egt_attack()` 与这里 ——
## 本表是「表里写了但运行时不认」的第一个哨兵。
const ALLOWED_STYLES := [
	"volley", "contact", "explode", "rush", "support", "grab", "orbit", "chance", "flee",
]
## 允许的弹道图案。必须与 `_pattern_directions()` 的 match 分支一一对应。
const ALLOWED_PATTERNS := [
	"line", "fan", "v", "ring", "cross", "clover", "compass", "arrows", "letter", "spiral",
	"serpentine", "dice",
]
## 每种骨架**必须**同时存在的键（缺了就等于"声明了行为却没有参数"）。
const STYLE_REQUIRED_KEY := {
	"volley": "volley",
	"rush": "suicide_rush",
	"support": "support_buff",
	"grab": "grab",
	"orbit": "orbit",
	"chance": "chance_moves",
	"flee": "flee",
}

## **刻意不染色**的族。分裂族三只共用小僵尸 GLB 且都不染色 ——
## 这是设计（分裂体应该看起来和母体一模一样，靠体型区分阶段），不是漏登记。
## 除这一族以外，用正式 GLB 却不登记 `FORMAL_MODEL_TINT` 一律判失败。
const SAME_COLOR_FAMILIES := ["分裂族"]

var _failures: Array[String] = []
var _level_rules := {}


## 假目标：只需要 `take_damage` / `notify_attacked_by` 两个方法 + 一个位置。
## 用 `CharacterBody3D` 是为了让 `_predict_target_position()` 能读到 `velocity`。
class Target3D extends CharacterBody3D:
	var current_hp := 9999.0
	func take_damage(_amount: int, _critical := false, _dir := Vector3.ZERO, _knock := 0.0, _interrupt := true) -> void:
		pass
	func notify_attacked_by(_node: Node) -> void:
		pass


func _ready() -> void:
	print("=== EGT_MONSTER_REGISTRY_PROBE 远征03 复刻怪注册一致性 ===")
	print("名单规模：%d 种（非 Boss）" % ROSTER.size())
	_load_level_plan()
	_check_registrations()
	_check_numeric_formula()
	_check_attack_specs()
	_smoke_attacks()
	_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _load_level_plan() -> void:
	var path := "res://data/level_plans/expedition_03/level_plan.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("读不到 level_plan.json：%s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_failures.append("level_plan.json 解析失败")
		return
	_level_rules = ((parsed as Dictionary).get("monster_rules", {}) as Dictionary)


## ① + ② 九个注册点逐只比对。
func _check_registrations() -> void:
	print("\n--- ① 注册点覆盖 ---")
	var per_kind := (
		((_level_rules.get("stats", {}) as Dictionary).get("per_kind", {})) as Dictionary
	)
	var missing_report := {}
	for kind in ROSTER:
		var problems: Array[String] = []
		if not Enemy3D.PROFILES.has(kind):
			problems.append("PROFILES")
		if not Enemy3D.BODY_SCALE_BY_KIND.has(kind):
			problems.append("BODY_SCALE_BY_KIND")
		if not Enemy3D.HEALTH_BAR_SIZE_BY_KIND.has(kind):
			problems.append("HEALTH_BAR_SIZE_BY_KIND")
		if not EnemyAvatar3D.PROXY_ASSET_KIND.has(kind):
			problems.append("PROXY_ASSET_KIND")
		if not MonsterInjector.BASE_ENEMY_TYPES.has(kind):
			problems.append("BASE_ENEMY_TYPES")
		if not MonsterInjector.ENEMY_PRESENTATION.has(kind):
			problems.append("ENEMY_PRESENTATION")
		if not SpawnBoxCatalog.ALLOWED_BOX_TYPES.has(kind):
			problems.append("ALLOWED_BOX_TYPES")
		if not per_kind.has(kind):
			problems.append("level_plan.stats.per_kind")
		# ② 颜色通道：正式 GLB 只吃 TINT，程序化外壳只吃 COLORS。
		var asset_kind := EnemyAvatar3D.resolve_asset_kind(kind)
		var uses_formal := EnemyAvatar3D.FORMAL_NORMAL_SCENES.has(asset_kind)
		var same_color_family := SAME_COLOR_FAMILIES.has(str(ROSTER[kind]["family"]))
		if uses_formal:
			if not EnemyAvatar3D.FORMAL_MODEL_TINT.has(kind) and not same_color_family:
				problems.append("FORMAL_MODEL_TINT（它借的是正式 GLB，COLORS 对它无效）")
		else:
			if not EnemyAvatar3D.COLORS.has(kind):
				problems.append("COLORS（它走程序化外壳）")
		if not problems.is_empty():
			missing_report[kind] = problems
			_failures.append("%s 漏登记：%s" % [kind, ", ".join(problems)])
	if missing_report.is_empty():
		print("  33 种 × 9 个注册点：全部齐备")
	else:
		print("  ⚠ %d 种存在漏登记（见下面的 FAIL 行）" % missing_report.size())
	# 反向检查：PROFILES 里以 egt_ 开头但不在名单里的（写了却没纳入管理）
	for kind in Enemy3D.PROFILES:
		if str(kind).begins_with("egt_") and not ROSTER.has(kind):
			_failures.append("%s 在 PROFILES 里但不在本探针名单 —— 名单漏了一只" % kind)


## ③ 血量必须满足换算，而不是"手填一个差不多的数"。
##
## 2026-10-29 第二轮改口径：业主定为「按玩家子弹伤害等比」——
## 血量 = EGT 血量 × `HP_SCALE`，系数来自「保持击杀发数」：
##   EGT Bullet Kin 15 血 / 初始手枪约 6 伤 ≈ 3 发
##   本工程初始步枪 50 伤/发 ⇒ 150 血同样 3 发 ⇒ HP_SCALE = 10
## 旧口径是指数 0.72 的幂律压缩（把 6.67 倍压成 3.93 倍），已废弃。
const HP_SCALE := 10.0
const MIN_HP := 10


func _check_numeric_formula() -> void:
	print("\n--- ③ 血量与 EGT 原值的一致性（hp = max(10, round(egt_hp × %.0f))）---" % HP_SCALE)
	for kind in ROSTER:
		if not Enemy3D.PROFILES.has(kind):
			continue
		var egt_hp := float(ROSTER[kind]["egt_hp"])
		var expected := _expected_hp(egt_hp)
		var actual := int(Enemy3D.PROFILES[kind]["hp"])
		var mark := "ok" if actual == expected else "FAIL"
		if actual != expected:
			_failures.append(
				"%s 血量 %d ≠ 换算值 %d（EGT %.1f）—— 数值不是按 §T0.2 公式来的"
				% [kind, actual, expected, egt_hp]
			)
		print("  %-22s EGT=%-5.1f 期望=%-3d 实际=%-3d %s" % [kind, egt_hp, expected, actual, mark])


func _expected_hp(egt_hp: float) -> int:
	return maxi(MIN_HP, int(round(egt_hp * HP_SCALE)))


## ④ 攻击规格自洽：声明了骨架就必须有对应参数键；弹道图案必须在白名单内。
func _check_attack_specs() -> void:
	print("\n--- ④ 攻击规格自洽 ---")
	var style_count := {}
	for kind in ROSTER:
		if not Enemy3D.PROFILES.has(kind):
			continue
		var profile: Dictionary = Enemy3D.PROFILES[kind]
		var style := str(profile.get("attack_style", ""))
		if style.is_empty():
			_failures.append("%s 没写 attack_style —— 分派会落到 contact，行为可能不是你要的" % kind)
			continue
		if not ALLOWED_STYLES.has(style):
			_failures.append("%s 的 attack_style=%s 不在白名单" % [kind, style])
			continue
		style_count[style] = int(style_count.get(style, 0)) + 1
		if STYLE_REQUIRED_KEY.has(style):
			var key := str(STYLE_REQUIRED_KEY[style])
			if not profile.has(key):
				_failures.append("%s 声明 attack_style=%s 但缺少 %s 参数" % [kind, style, key])
		for spec_key in ["volley", "volley_alt"]:
			var spec: Variant = profile.get(spec_key, null)
			if not (spec is Dictionary):
				continue
			var dict := spec as Dictionary
			var pattern := str(dict.get("pattern", "line"))
			if not ALLOWED_PATTERNS.has(pattern):
				_failures.append("%s.%s.pattern=%s 未实现" % [kind, spec_key, pattern])
			if int(dict.get("count", 1)) < 1 and pattern != "letter":
				_failures.append("%s.%s.count < 1" % [kind, spec_key])
			if float(dict.get("interval", 0.0)) < 0.0:
				_failures.append("%s.%s.interval < 0" % [kind, spec_key])
		if profile.has("volley_alt") and int(profile.get("alt_every", 0)) <= 0:
			_failures.append("%s 写了 volley_alt 但 alt_every<=0 —— 备用规格永远不会被用到" % kind)
	print("  骨架分布：%s" % str(style_count))


## ⑤ 每只怪真打一次。不许抛错、不许远程族一弹未出。
func _smoke_attacks() -> void:
	print("\n--- ⑤ 攻击冒烟（逐只真打一次）---")
	var target := Target3D.new()
	target.name = "ProbeTarget"
	target.add_to_group("player_3d")
	add_child(target)
	target.global_position = Vector3(0, 0, -8)
	for kind in ROSTER:
		if not Enemy3D.PROFILES.has(kind):
			continue
		var enemy := Enemy3D.new()
		var avatar := EnemyAvatar3D.new()
		avatar.name = "Avatar"
		enemy.add_child(avatar)
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		col.shape = CapsuleShape3D.new()
		enemy.add_child(col)
		add_child(enemy)
		enemy.apply_profile(kind)
		enemy.global_position = Vector3.ZERO
		enemy._target = target
		var style := enemy._egt_attack_style()
		# 拟态怪：伪装状态下**必须打不出东西**（这是它的定义），
		# 现形之后才允许开火。两条都查，否则"伪装永远不解除"这种 bug 会被漏掉。
		var disguised_blocked := false
		if enemy._disguised:
			enemy._perform_attack(Vector3(0, 0, -1), 6.0)
			disguised_blocked = (enemy._pending_volleys as Array).is_empty()
			if not disguised_blocked:
				_failures.append("%s 在伪装状态下居然开火了" % kind)
			enemy._reveal_disguise()
			if enemy._disguised:
				_failures.append("%s 调了现形之后仍然是伪装状态" % kind)
		enemy._perform_attack(Vector3(0, 0, -1), 6.0)
		# 排队型的（连发/字母/螺旋）当帧可能一弹未出，这里只统计**已排队的射击事件**。
		var fired := (enemy._pending_volleys as Array).size()
		if style == "volley" and fired <= 0:
			_failures.append("%s 走 volley 但一次攻击没排出任何射击事件" % kind)
		print(
			"  %-22s style=%-8s 排队=%-2d 体型=%.2f%s"
			% [
				kind, style, fired, float(Enemy3D.BODY_SCALE_BY_KIND.get(kind, -1.0)),
				"（伪装时已拦下）" if disguised_blocked else "",
			]
		)
		enemy.queue_free()
	target.queue_free()


func _report() -> void:
	print("\n=== 结果 ===")
	if _failures.is_empty():
		print("EGT_MONSTER_REGISTRY_PROBE_OK")
		print("33 种复刻怪在九个注册点全部齐备；血量与换算公式一致；攻击骨架自洽")
		return
	for failure in _failures:
		print("FAIL: " + failure)
	print("EGT_MONSTER_REGISTRY_PROBE_FAIL count=%d" % _failures.size())
