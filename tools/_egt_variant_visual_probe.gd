extends Node
## 远征03 复刻怪的「族内变种区分」验证探针（2026-10-29）
##
## 要证的事只有一件：**同一族里的变种，玩家不看名字能不能分开。**
## 因此逐只打印「实际世界体型 / 玩家真正看到的颜色 / 血条宽度」，并做四层检查：
##
##   ① 族内体型不重复 —— 同族两只一样大 = 区分失效
##   ② 族内颜色不重复 —— 同族两只一样色 = 区分失效（分裂族豁免，见下）
##   ③ 族内「体型 ↔ 血量」同序 —— 不许出现血更多反而更小
##   ④ 用正式模型的怪**必须**有染色配方 —— 见下面这条最要命的坑
##
## ⚠ **最容易静默翻车的一条（④）**：
##   远程族 5 只全部借用 `ranged_caster`，而 `ranged_caster` 有正式 GLB，
##   加载时会把程序化外壳 `hide()`。于是 `COLORS` 对它们 **一行都不生效** ——
##   改 `COLORS` 看不出任何变化，5 只仍然是同一个外观。真正生效的是
##   `FORMAL_MODEL_TINT`（见该表注释）。
##   所以本探针的「颜色」一律取**玩家真正看到的那个**：
##   有正式模型 ⇒ 取 `FORMAL_MODEL_TINT`；无正式模型 ⇒ 取 `COLORS`。
##   取不到就直接判失败，而不是回退到 `COLORS` 假装通过。
##
## ⚠ **跨族不做体型单调检查**，这是刻意排除的，理由必须记下来：
##   体型在族内表达「强度排序」，跨族表达「形态体积」，是两种不同语义。
##   - `egt_bullat` 是一只**活体子弹**，14 接触伤害却只有 0.55 体型 —— 它就该像一颗弹丸；
##   - `egt_blobulin` 是分裂终段碎片，体型由分裂层级决定，与血量无关；
##   - `egt_gunsinger` 是辅助，**刻意最大**，让玩家一眼锁定「先杀它」；
##   - `egt_bullet_kin` 是远程族入门怪，**刻意最小** —— 族内梯度的要求。
##   把这些压成一条单调曲线会毁掉形态语言。
##   跨族只查一件事：**同形状 + 同颜色不得跨族**（长得一样却属不同族才是真事故）。
##
## 用法：godot --headless --path . --scene res://tools/_egt_variant_visual_probe.tscn
## ⚠ 必须 `--scene` 而非 `--script`：要实例化 Enemy3D，它依赖 autoload。

## ## 体型单调的**显式豁免**
##
## 「血更厚 → 看起来更大」是条好规则，但它是**规则**，不是法律。业主点名的个别
## 调整会打破它，这里登记豁免而不是偷偷放宽判据 —— 放宽容差会让所有真倒挂一起溜过去。
##
## 每条豁免必须写清三件事：谁批的、为什么、拿什么替代了"体型梯度"这条区分维度。
const SIZE_EXEMPT := {
	# 业主 2026-10-30：「这个怪物的大小缩小一点，到现在的 70%」（1.44m → 1.01m）。
	# 它因此成为子弹族里最小的，而血量 250 是族内最高 —— 体型梯度在它身上失效。
	# 替代区分维度：它是族内**唯一会瞬移**的（`blink`），且弹型是 4 连发（count=4），
	# 玩家靠"它消失了"和"子弹是四连"就能认出它，不靠体型。
	"egt_hollowpoint": "业主点名缩到 70%；该族改用弹道形状 + 瞬移行为区分",
}

const FAMILIES := {
	"子弹族": {
		"dimension": "体型阶梯 + 染色(=弹色)",
		"members": [
			"egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin",
			"egt_cardinal", "egt_hollowpoint",
		],
		"same_color_ok": false,
	},
	"霰弹枪族": {
		"dimension": "体型阶梯 + 染色(=弹色)",
		"members": ["egt_red_shotgun", "egt_veteran_shotgun", "egt_blue_shotgun"],
		"same_color_ok": false,
	},
	"分裂族（三阶链）": {
		"dimension": "纯体型阶梯（同色：分裂体应与母体同貌）",
		"members": ["egt_blobulon", "egt_blobuloid", "egt_blobulin"],
		"same_color_ok": true,
	},
	"骰子布洛布": {
		# 它不是三阶链的一环：招式随机、还能自杀，所以**刻意与母体不同色**，
		# 好让玩家在混战里一眼认出"这一只不可预测"。
		"dimension": "独苗：与分裂三阶刻意异色",
		"members": ["egt_chancebulon"],
		"same_color_ok": false,
	},
	"爆炸族": {
		"dimension": "体型 + 色温（区分引爆方式）",
		"members": [
			"egt_pinhead", "egt_nitra", "egt_bullat", "egt_grenat", "egt_king_bullat",
		],
		"same_color_ok": false,
	},
	"冲撞族": {
		"dimension": "体型 + 颜色（区分撞到时吐什么）",
		"members": ["egt_shotgat", "egt_spirat"],
		"same_color_ok": false,
	},
	"书怪族": {
		"dimension": "同血 25，只靠颜色区分弹形（体型仅微调）",
		"members": ["egt_bookllet", "egt_blue_bookllet", "egt_green_bookllet"],
		"same_color_ok": false,
	},
	"法术族": {
		"dimension": "体型 + 颜色（施法者 vs 蛋射手）",
		"members": ["egt_gunjurer", "egt_gigi"],
		"same_color_ok": false,
	},
	"辅助族": {
		"dimension": "放大 + 高亮（独苗，必须一眼识别）",
		"members": ["egt_gunsinger"],
		"same_color_ok": false,
	},
	"触发 / 逃逸族": {
		"dimension": "体型 + 颜色（六种完全不同的存在方式）",
		"members": [
			"egt_gun_fairy", "egt_keybullet_kin", "egt_chance_kin",
			"egt_gripmaster", "egt_confirmed", "egt_mimic",
		],
		"same_color_ok": false,
	},
	"重型族": {
		"dimension": "体型 + 颜色（血量顶点的两只小 Boss）",
		"members": ["egt_chain_gunner", "egt_gun_nut"],
		"same_color_ok": false,
	},
}

var _failures: Array[String] = []
var _measured := {}


func _ready() -> void:
	print("=== EGT_VARIANT_VISUAL_PROBE 远征03 族内变种区分 ===")
	for family_name in FAMILIES:
		_probe_family(family_name, FAMILIES[family_name])
	_audit_cross_family()
	_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _probe_family(family_name: String, spec: Dictionary) -> void:
	print("\n--- %s ｜主区分维度：%s ---" % [family_name, spec["dimension"]])
	var rows: Array = []
	for kind in spec["members"]:
		var m := _measure(kind)
		_measured[kind] = m
		rows.append(m)
		print(
			"  %-20s hp=%-3d 体型=%.2f 世界=%.3f 世界高=%.2fm 可见色=%s 来源=%s 血条=%.2fx%.2f"
			% [kind, m["hp"], m["body_scale"], m["world_scale"], m["world_height"],
				m["color_text"], m["color_source"], m["bar"].x, m["bar"].y]
		)

	_check_unique_scale(family_name, rows)
	if spec["same_color_ok"]:
		print("   （本族刻意同色：分裂体应看起来与母体一致）")
	else:
		_check_unique_color(family_name, rows)
	_check_monotonic_in_family(family_name, rows)


## 族内不能有两只**看起来一样大**。
##
## ⚠ 判据是**世界高**，不是根节点 `scale`（2026-10-30 改）。
## `scale` 是「资产基准高 × 0.70 × 倍率」里的**倍率**，跨资产不可比：
## `gripmaster` 借 summoner（基准 1.82m）scale=1.02 得 1.30m，
## `chance_kin` 借 melee_chaser（基准 1.30m）scale=1.19 却只有 1.08m。
## 用 scale 判会出现「屏幕上一只明显更大、判据说它们一样大」的荒谬结论。
func _check_unique_scale(family_name: String, rows: Array) -> void:
	var seen := {}
	for r in rows:
		var key := "%.2f" % r["world_height"]
		if seen.has(key):
			_failures.append(
				"%s：%s 与 %s 世界高完全相同（%.2fm），族内无法靠体型区分"
				% [family_name, r["kind"], seen[key], r["world_height"]]
			)
		seen[key] = r["kind"]


func _check_unique_color(family_name: String, rows: Array) -> void:
	var seen := {}
	for r in rows:
		var key := str(r["color"])
		if seen.has(key):
			_failures.append(
				"%s：%s 与 %s 可见颜色完全相同（%s），族内无法靠颜色区分"
				% [family_name, r["kind"], seen[key], r["color_text"]]
			)
		seen[key] = r["kind"]


## 族内按血量升序，**看到的大小**必须不下降。
##
## ⚠ 判据是**世界高**，不是根节点 `scale`（2026-10-30 改）。
## 规则的本意是「血更厚的那只不该看起来更小」—— 那是玩家看到的东西。
## 而 `scale` 只是倍率，同一族里一旦混了不同基准高的资产（`mimic` 借 3.14m 的胖僵尸、
## `confirmed` 借 1.62m 的射手），倍率小的高血怪反而更高，用 scale 判会**误报倒挂**。
## 反向验证过：把 `blobulin` 世界高抬到超过 `blobuloid` 而血量更低，本判据能抓住。
func _check_monotonic_in_family(family_name: String, rows: Array) -> void:
	var sorted_rows := rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return a["hp"] < b["hp"])
	var prev: Dictionary = {}
	for r in sorted_rows:
		if SIZE_EXEMPT.has(str(r["kind"])):
			prev = r
			continue
		if not prev.is_empty() and r["hp"] > prev["hp"] and r["world_height"] < prev["world_height"] - 0.01:
			_failures.append(
				"%s 族内倒挂：%s(hp=%d,世界高=%.2fm) 血量高于 %s(hp=%d,世界高=%.2fm) 却更小"
				% [family_name, r["kind"], r["hp"], r["world_height"],
					prev["kind"], prev["hp"], prev["world_height"]]
			)
		prev = r


## 跨族检查「**视觉特征是否撞车**」，不是「体型是否随血量单调」。
func _audit_cross_family() -> void:
	print("\n--- 跨族视觉撞车检查（同形状 + 同颜色不得跨族）---")
	var family_of := {}
	for family_name in FAMILIES:
		for kind in FAMILIES[family_name]["members"]:
			family_of[kind] = family_name

	var groups := {}
	for kind in _measured:
		var m: Dictionary = _measured[kind]
		var key := "%s|%s" % [EnemyAvatar3D.resolve_asset_kind(kind), str(m["color"])]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(kind)

	for key in groups:
		var kinds: Array = groups[key]
		var families := {}
		for k in kinds:
			families[family_of[k]] = true
		var shape := String(key.split("|")[0])
		if families.size() > 1:
			_failures.append(
				"视觉撞车：%s 共用形状=%s 且颜色相同，却分属 %s"
				% [str(kinds), shape, str(families.keys())]
			)
			print("  ⚠ 撞车 %s（形状 %s，跨族 %s）" % [str(kinds), shape, str(families.keys())])
		elif kinds.size() > 1:
			print("  %s 同形同色 —— 同族刻意（%s），由族内体型区分" % [str(kinds), shape])
		else:
			print("  %-20s 形状=%-14s 独立" % [kinds[0], shape])

	print("\n--- 体型总览（按体型降序，仅供人工核对）---")
	var kinds_all: Array = _measured.keys()
	kinds_all.sort_custom(func(a, b): return _measured[a]["body_scale"] > _measured[b]["body_scale"])
	for kind in kinds_all:
		var m: Dictionary = _measured[kind]
		print("  %-20s 体型=%.2f  hp=%-3d  %s" % [kind, m["body_scale"], m["hp"], family_of[kind]])


func _measure(kind: String) -> Dictionary:
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

	var asset_kind := EnemyAvatar3D.resolve_asset_kind(kind)
	var uses_formal := EnemyAvatar3D.FORMAL_NORMAL_SCENES.has(asset_kind)
	var body_color: Color = avatar.get("_base_color")
	var tint: Color = EnemyAvatar3D.FORMAL_MODEL_TINT.get(kind, Color.WHITE)

	# 「玩家真正看到的颜色」：正式模型看染色，程序化外壳看 COLORS。
	var visible := tint if uses_formal else body_color
	var source := "正式模型染色" if uses_formal else "程序化外壳 COLORS"

	# ④ 用正式模型的怪必须有染色配方，否则族内区分静默失效。
	if uses_formal and not EnemyAvatar3D.FORMAL_MODEL_TINT.has(kind):
		# 分裂族刻意同色，不在此列；由调用方判断，这里只记录事实。
		source = "正式模型·未染色"

	var result := {
		"kind": kind,
		"hp": int(Enemy3D.PROFILES[kind]["hp"]),
		"body_scale": float(Enemy3D.BODY_SCALE_BY_KIND[kind]),
		"world_scale": enemy.scale.x,
		# 世界高 = 碰撞柱高 × 根节点 scale。碰撞柱高是按"实际模型最大轮廓"定的
		# （`EnemyAvatar3D.FOOTPRINT_PROFILES`），所以它是"看到有多大"的可靠代理。
		"world_height": float(
			EnemyAvatar3D.get_footprint_profile(kind).get("height", 1.2)
		) * enemy.scale.y,
		"color": visible,
		"color_text": "(%.2f,%.2f,%.2f)" % [visible.r, visible.g, visible.b],
		"color_source": source,
		"uses_formal": uses_formal,
		"has_tint": EnemyAvatar3D.FORMAL_MODEL_TINT.has(kind),
		"bar": Enemy3D.HEALTH_BAR_SIZE_BY_KIND.get(kind, Vector2.ZERO) as Vector2,
	}
	enemy.queue_free()
	return result


func _report() -> void:
	# ④ 独立成一项：族内需要靠颜色区分、又用了正式模型却没染色的，一律判失败。
	for family_name in FAMILIES:
		if FAMILIES[family_name]["same_color_ok"]:
			continue
		for kind in FAMILIES[family_name]["members"]:
			var m: Dictionary = _measured.get(kind, {})
			if m.is_empty():
				continue
			if bool(m["uses_formal"]) and not bool(m["has_tint"]):
				_failures.append(
					"%s：%s 用正式 GLB 但没登记 FORMAL_MODEL_TINT，"
					% [family_name, kind]
					+ "程序化外壳已被 hide()，COLORS 不生效 —— 族内区分静默失效"
				)

	print("\n=== 结果 ===")
	if _failures.is_empty():
		print("EGT_VARIANT_VISUAL_PROBE_OK")
		print("%d 个族（含 33 只）变种均具备可区分性；跨族无同形同色撞车" % FAMILIES.size())
		return
	for f in _failures:
		print("FAIL: " + f)
	print("EGT_VARIANT_VISUAL_PROBE_FAIL count=%d" % _failures.size())
