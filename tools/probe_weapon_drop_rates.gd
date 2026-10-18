extends Node
## 一次性探针：实测「枪械到底从谁身上掉」。
## 不读设计文档、不读权重表，直接跑 RuntimeRewardCoordinator 的真实解析链，
## 统计每类怪的「出枪率 / 出枪件数 / 物理件数」。
## 用法：godot --headless --path . --script res://tools/probe_weapon_drop_rates.gd

const COORDINATOR := preload("res://src/rewards/RuntimeRewardCoordinator.gd")

const RANGED_GUNS := [
	"weapon_pistol", "weapon_shotgun", "weapon_rifle", "weapon_machinegun",
	"weapon_sprinkler", "weapon_starter_rifle", "weapon_sniper",
	"weapon_launcher", "weapon_charge",
]

const SAMPLES := 6000


func _ready() -> void:
	_run("普通怪·浅层", {"enemy_type": "melee_chaser", "floor": 1, "loot_table": "loot_floor_1_2"}, SAMPLES)
	_run("普通怪·中层", {"enemy_type": "melee_chaser", "floor": 3, "loot_table": "loot_floor_3_4"}, SAMPLES)
	_run("普通怪·深层", {"enemy_type": "fat_zombie03", "floor": 5, "loot_table": "loot_floor_5"}, SAMPLES)
	_run("普通怪·深渊", {"enemy_type": "ambusher", "floor": 5, "loot_table": "loot_abyss"}, SAMPLES)
	_run("强化怪·浅层", {"enemy_type": "melee_chaser_strong", "floor": 1, "loot_table": "loot_floor_1_2"}, SAMPLES)
	_run("强化怪·深层", {"enemy_type": "ranged_caster_strong", "floor": 5, "loot_table": "loot_floor_5"}, SAMPLES)
	_run("精英·浅层", {"enemy_type": "melee_chaser", "is_elite": true, "floor": 1, "loot_table": "elite_floor_1"}, SAMPLES)
	_run("Boss·1档", {"enemy_type": "boss", "is_boss": true, "floor": 1, "loot_table": "boss_floor_1"}, SAMPLES)
	_run("Boss·2档", {"enemy_type": "boss", "is_boss": true, "floor": 2, "loot_table": "boss_floor_2"}, SAMPLES)
	get_tree().quit(0)


func _run(label: String, enemy_data: Dictionary, samples: int) -> void:
	var coordinator := COORDINATOR.new()
	coordinator.configure(20261018)
	var with_gun := 0
	var total_guns := 0
	var min_guns := 99
	var max_guns := 0
	var total_physical := 0
	var min_physical := 99
	var max_physical := 0
	var rejected_total := 0
	var grade_counts := {"blue": 0, "purple": 0, "gold": 0}
	for index in range(samples):
		var report := coordinator.resolve_kill({}, enemy_data, "%s:%d" % [label, index])
		rejected_total += (report.get("rejected", []) as Array).size()
		var guns := 0
		var physical := 0
		for value in report.get("grants", []):
			var grant := value as Dictionary
			if str(grant.get("kind", "")) == "currency":
				continue
			physical += 1
			if RANGED_GUNS.has(str(grant.get("item_id", ""))):
				guns += 1
				var gun := grant.get("item", {}) as Dictionary
				var grade := str(gun.get("drop_grade", ""))
				if grade_counts.has(grade):
					grade_counts[grade] += 1
				else:
					grade_counts["MISSING"] = int(grade_counts.get("MISSING", 0)) + 1
		if guns > 0:
			with_gun += 1
		total_guns += guns
		total_physical += physical
		min_guns = mini(min_guns, guns)
		max_guns = maxi(max_guns, guns)
		min_physical = mini(min_physical, physical)
		max_physical = maxi(max_physical, physical)
	var gun_total := 0
	for key in grade_counts.keys():
		gun_total += int(grade_counts[key])
	var grade_parts: Array[String] = []
	for key in grade_counts.keys():
		grade_parts.append("%s=%.1f%%" % [
			key, 100.0 * float(grade_counts[key]) / float(maxi(1, gun_total)),
		])
	var grade_text := "  ".join(grade_parts)
	print("%-14s 出枪率=%6.2f%%  平均枪数=%.2f [%d..%d]  物理件数=%.2f [%d..%d]  rejected=%d  品质：%s" % [
		label,
		100.0 * float(with_gun) / float(samples),
		float(total_guns) / float(samples), min_guns, max_guns,
		float(total_physical) / float(samples), min_physical, max_physical,
		rejected_total, grade_text,
	])
