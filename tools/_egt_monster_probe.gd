extends Node
## 远征03 复刻怪专项探针（2026-10-29）。
##
## 只验**数据与解析**，不跑真实战斗：
##   ① 12 只怪都能被 `MonsterInjector` 生成，且 hp 与设计表一致
##   ② `Enemy3D.PROFILES` 每只都有行、`volley` 等行为键能读到
##   ③ `EnemyAvatar3D.resolve_asset_kind()` 把每只都映射到**已有的**资产基类
##      （这条是「套入现有资产」的硬保证 —— 漏登记会让表现静默退化成默认怪）
##   ④ 远征03 `monster_rules` 能被读出来、`enemy_pool` 覆盖 12 只
##
## 用法：godot --headless --path . --scene res://tools/_egt_monster_probe.tscn
## ⚠ 必须用 `--scene` 而不是 `--script`：本探针要编译 `MonsterInjector` / `Enemy3D`，
## 它们依赖 `EliteRosterService` / `MonsterAIManager` 两个 autoload，而 `--script` 模式
## **不加载 autoload**，会直接编译失败（报 `Identifier not found`）。

const EXPECTED := {
	# —— 33 种统一由 tools/retune_egt_monsters.py 生成，别手改单条 ——
	"egt_bullet_kin": {"hp": 150, "damage": 17},
	"egt_bandana_kin": {"hp": 150, "damage": 17},
	"egt_veteran_kin": {"hp": 150, "damage": 17},
	"egt_cardinal": {"hp": 225, "damage": 17},
	"egt_hollowpoint": {"hp": 250, "damage": 17},
	"egt_red_shotgun": {"hp": 300, "damage": 17},
	"egt_blue_shotgun": {"hp": 400, "damage": 17},
	"egt_veteran_shotgun": {"hp": 338, "damage": 17},
	"egt_pinhead": {"hp": 130, "damage": 17},
	"egt_nitra": {"hp": 100, "damage": 17},
	"egt_king_bullat": {"hp": 260, "damage": 17},
	"egt_blobulon": {"hp": 200, "damage": 17},
	"egt_blobuloid": {"hp": 100, "damage": 17},
	"egt_blobulin": {"hp": 10, "damage": 17},
	"egt_chancebulon": {"hp": 500, "damage": 17},
	"egt_bookllet": {"hp": 250, "damage": 17},
	"egt_blue_bookllet": {"hp": 250, "damage": 17},
	"egt_green_bookllet": {"hp": 250, "damage": 17},
	"egt_gunjurer": {"hp": 188, "damage": 17},
	"egt_gunsinger": {"hp": 150, "damage": 0},
	"egt_gigi": {"hp": 120, "damage": 17},
	"egt_bullat": {"hp": 10, "damage": 17},
	"egt_shotgat": {"hp": 20, "damage": 17},
	"egt_grenat": {"hp": 30, "damage": 17},
	"egt_spirat": {"hp": 50, "damage": 17},
	"egt_keybullet_kin": {"hp": 150, "damage": 17},
	"egt_chance_kin": {"hp": 150, "damage": 17},
	"egt_confirmed": {"hp": 450, "damage": 17},
	"egt_mimic": {"hp": 1000, "damage": 17},
	"egt_gun_fairy": {"hp": 150, "damage": 17},
	"egt_gripmaster": {"hp": 300, "damage": 0},
	"egt_gun_nut": {"hp": 1000, "damage": 17},
	"egt_chain_gunner": {"hp": 900, "damage": 17},
}

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	var injector := MonsterInjector.new()

	# ① 生成 + 数值
	for kind in EXPECTED.keys():
		var data := injector.generate_box_enemy(str(kind), 1, 1)
		_check(not data.is_empty(), "%s 无法生成（MonsterInjector 未登记？）" % kind)
		if data.is_empty():
			continue
		_check(
			int(data.get("max_hp", -1)) == int(EXPECTED[kind]["hp"]),
			"%s max_hp=%d，设计表要求 %d" % [kind, int(data.get("max_hp", -1)), int(EXPECTED[kind]["hp"])]
		)
		_check(
			int(data.get("damage", -1)) == int(EXPECTED[kind]["damage"]),
			"%s damage=%d，设计表要求 %d" % [kind, int(data.get("damage", -1)), int(EXPECTED[kind]["damage"])]
		)
		_check(
			str(data.get("enemy_type", "")) == str(kind),
			"%s 被改写成了 %s（强化怪升级没关？）" % [kind, str(data.get("enemy_type", ""))]
		)

	# ② PROFILES + 行为键
	for kind in EXPECTED.keys():
		_check(Enemy3D.PROFILES.has(kind), "%s 在 Enemy3D.PROFILES 里没有行" % kind)
	var ranged := ["egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin", "egt_red_shotgun", "egt_blue_shotgun"]
	for kind in ranged:
		var profile := Enemy3D.profile_for(str(kind))
		_check(profile.has("volley"), "%s 缺 volley 规格（会退化成默认单发）" % kind)
	var split_kinds := ["egt_blobulon", "egt_blobuloid"]
	for kind in split_kinds:
		_check(Enemy3D.profile_for(str(kind)).has("death_split"), "%s 缺 death_split" % kind)
	for kind in ["egt_red_shotgun", "egt_blue_shotgun"]:
		_check(Enemy3D.profile_for(str(kind)).has("death_burst"), "%s 缺 death_burst" % kind)
	_check(Enemy3D.profile_for("egt_bullat").has("suicide_rush"), "egt_bullat 缺 suicide_rush")
	_check(Enemy3D.profile_for("egt_gunsinger").has("support_buff"), "egt_gunsinger 缺 support_buff")
	# 第二批：每种「非弹道」行为都必须有对应参数键（声明了却没有参数 = 该行为静默失效）
	var behavior_keys := {
		"egt_king_bullat": "death_split",
		"egt_chancebulon": "chance_moves",
		"egt_hollowpoint": "blink",
		"egt_gunjurer": "blink",
		"egt_keybullet_kin": "flee",
		"egt_chance_kin": "flee",
		"egt_mimic": "disguise",
		"egt_gripmaster": "grab",
		"egt_chain_gunner": "orbit",
		"egt_gun_fairy": "wander",
		"egt_gigi": "egg",
	}
	for kind in behavior_keys:
		var key := str(behavior_keys[kind])
		_check(Enemy3D.profile_for(kind).has(key), "%s 缺 %s" % [kind, key])
	# 子弹榴弹王的死亡分裂是**多种子代**（Bullat + Shotgat），不是单一 child
	var king_split: Dictionary = Enemy3D.profile_for("egt_king_bullat").get("death_split", {})
	_check(
		(king_split.get("children", []) as Array).size() == 2,
		"子弹榴弹王应同时产两种子代（children 长度 2）"
	)
	# 蓝霰弹必须是「两段」而不是"一次五发"
	_check(
		Enemy3D.profile_for("egt_blue_shotgun")["volley"].has("followup"),
		"蓝霰弹枪缺 followup（原作的第二段 4 发）"
	)
	# 三阶分裂链必须首尾相接，否则打死一只就断了
	_check(
		str(Enemy3D.profile_for("egt_blobulon")["death_split"]["child"]) == "egt_blobuloid",
		"布洛布分裂子代不是幼体"
	)
	_check(
		str(Enemy3D.profile_for("egt_blobuloid")["death_split"]["child"]) == "egt_blobulin",
		"布洛布幼体分裂子代不是微体"
	)
	_check(
		not Enemy3D.profile_for("egt_blobulin").has("death_split"),
		"布洛布微体不该再有 death_split（会造成无限裂解）"
	)

	# ③ 资产别名 —— 漏登记 = 表现静默退化成默认怪
	var legal_assets := ["fat_zombie03", "melee_chaser", "ranged_caster", "summoner", "exploder", "ambusher"]
	for kind in EXPECTED.keys():
		var asset := EnemyAvatar3D.resolve_asset_kind(str(kind))
		_check(asset != str(kind), "%s 没有资产别名（会被当成未知种类）" % kind)
		_check(asset in legal_assets, "%s 的别名 %s 不是合法资产基类" % [kind, asset])
		var footprint := EnemyAvatar3D.get_footprint_profile(str(kind))
		_check(
			float(footprint.get("radius", 0.0)) > 0.0,
			"%s 没有碰撞足迹（会套到默认值）" % kind
		)

	# ④ 远征03 关卡规则
	var rules := _load_level_rules()
	_check(not rules.is_empty(), "远征03 level_plan.json 没有 monster_rules")
	# `enemy_pool` 已于 2026-10-29 删除：本关编成全部走 `spawn_roster`，
	# 公式刷怪不再是合法路径。留着它反而会让人以为"还有一条公式兜底"。
	_check(
		not rules.has("enemy_pool"),
		"enemy_pool 应已删除（本关只走 spawn_roster），实际仍在"
	)
	var per_kind: Dictionary = (rules.get("stats", {}) as Dictionary).get("per_kind", {})
	_check(
		per_kind.size() == EXPECTED.size(),
		"stats.per_kind 应含 %d 只，实际 %d" % [EXPECTED.size(), per_kind.size()]
	)
	for kind in EXPECTED.keys():
		_check(per_kind.has(kind), "stats.per_kind 缺 %s" % kind)
	_check(
		float((rules.get("strong_variant", {}) as Dictionary).get("chance", 1.0)) == 0.0,
		"远征03 应关闭强化怪（chance 必须为 0）"
	)

	_report()


func _load_level_rules() -> Dictionary:
	var path := "res://data/level_plans/expedition_03/level_plan.json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("monster_rules", {}) as Dictionary


func _report() -> void:
	if failures.is_empty():
		print("EGT_MONSTER_PROBE_OK 33 只复刻怪：生成/数值/行为键/资产别名/关卡规则 全部通过")
		get_tree().quit(0)
		return
	print("EGT_MONSTER_PROBE_FAIL count=%d" % failures.size())
	for message in failures:
		print("  - %s" % message)
	get_tree().quit(1)
