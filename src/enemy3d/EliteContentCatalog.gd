class_name EliteContentCatalog
extends RefCounted
## 精英内容定义库。只描述稳定身份、投放条件和表现契约；跨局档案与预约由
## EliteRosterService 持有，Enemy3D 继续持有战斗事实。

const DEPLOYED := "deployed"
const DESIGN_ONLY := "design_only"

const DEFINITIONS: Array[Dictionary] = [
	{
		"elite_id":"elite_rift_boar_armed", "name":"背枪的裂口爬虫",
		"base_enemy_id":"melee_chaser", "behavior_id":"armed_rush",
		"modifier_id":"Elite.WeaponParasite", "growth":"副枪射击频率",
		"translation":"gun_body_to_followup_shot",
		"deployment_status":DEPLOYED, "eligible_floor_numbers":[98, 97, 96],
		"floor_selection_mode":"one_per_run_seed",
		"spawn_room_types":["ELITE"], "spawn_weight":1,
		"growth_profile":{
			"escape_enabled":true, "escape_health_ratio":0.20,
			"escape_duration":4.2, "escape_speed_multiplier":1.55,
			"hp_per_level":0.08, "damage_per_level":0.045,
			"sidearm_base_attack_interval":3,
			"sidearm_interval_step_levels":4,
			"sidearm_min_attack_interval":1,
			"bounty_currency_by_tier":[45, 75, 115, 165, 230],
		},
		"presentation_asset_id":"ENM-ELITE-RIFT-BOAR-ARMED-3D",
		"presentation_scene":"res://assets/art/enemies/elite_3d/rift_boar_armed/runtime/enm_elite_rift_boar_armed_root_top3d_v001.tscn",
		"health_bar_profile":{
			"display_name":"背枪的裂口爬虫", "size":Vector2(2.05, 0.23),
			"visual_height":2.0,
			"frame_color":Color(0.92, 0.47, 0.055, 1.0),
			"empty_color":Color(0.055, 0.018, 0.075, 0.98),
			"full_color":Color(0.055, 0.84, 0.94, 1.0),
			"low_color":Color(1.0, 0.20, 0.075, 1.0),
		},
	},
	{"elite_id":"elite_spore_devourer","name":"吞弹者·孢子射手","base_enemy_id":"ranged_caster","behavior_id":"bullet_devourer","modifier_id":"Elite.BulletEater","growth":"吸收容量与反击弹数","translation":"bullet_to_counter_volley","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_iron_carapace","name":"铁壁·壳甲统领","base_enemy_id":"shielded","behavior_id":"rotating_carapace","modifier_id":"Elite.Huge","growth":"护甲面与转向间隔","translation":"stock_magazine_to_guard_counter","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_ninth_hive_queen","name":"蜂后“第九巢”","base_enemy_id":"summoner","behavior_id":"hive_network","modifier_id":"Elite.Parasite","growth":"巢数与节点协同","translation":"attachment_to_hive_modifier","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_emberfruit","name":"焦雷果·余烬","base_enemy_id":"exploder","behavior_id":"renewing_mines","modifier_id":"Elite.SpawnOnDeath","growth":"连锁种子与燃烧区","translation":"explosive_round_to_mine_field","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_blackneedle","name":"缝行者“黑针”","base_enemy_id":"ambusher","behavior_id":"false_burrow_routes","modifier_id":"Elite.Huge","growth":"假路线与二次突袭","translation":"piercing_optic_to_line_lunge","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_mirror_shell","name":"反射者·镜壳","base_enemy_id":"shielded","behavior_id":"mirror_sector","modifier_id":"Elite.Ricochet","growth":"反射扇区与弱点窗口","translation":"ricochet_optic_to_reflect_sector","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_arms_taker","name":"夺械者“收租人”","base_enemy_id":"ranged_caster","behavior_id":"weapon_phase_swap","modifier_id":"Elite.WeaponParasite","growth":"完整枪身阶段转译","translation":"gun_body_to_phase_skill","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_seven_signs","name":"命运残响“七签”","base_enemy_id":"ranged_caster","behavior_id":"seven_attack_rule","modifier_id":"Elite.Ricochet","growth":"一至两条公开规则","translation":"fate_to_budgeted_rule","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_echo_brood","name":"寄生母体“回声”","base_enemy_id":"summoner","behavior_id":"attachment_echo","modifier_id":"Elite.Parasite","growth":"双回声召唤修饰","translation":"attachment_to_summon_echo","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_returning_king","name":"逃亡王“折返者”","base_enemy_id":"ambusher","behavior_id":"escape_route","modifier_id":"Elite.SpawnOnDeath","growth":"折返段与伏击次数","translation":"return_round_to_retreat_lunge","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
	{"elite_id":"elite_nameless_crown","name":"准首领“无名王冠”","base_enemy_id":"boss","behavior_id":"three_crowns","modifier_id":"Elite.Huge","growth":"名册推进与三冠阶段","translation":"assembly_to_three_phase_bag","deployment_status":DESIGN_ONLY,"eligible_floor_numbers":[]},
]


static func get_all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in DEFINITIONS:
		result.append(definition.duplicate(true))
	return result


static func get_by_id(elite_id: String) -> Dictionary:
	for definition in DEFINITIONS:
		if str(definition.get("elite_id", "")) == elite_id:
			return definition.duplicate(true)
	return {}


static func get_deployable_for_floor(floor_number: int, seed_value := -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in DEFINITIONS:
		if str(definition.get("deployment_status", DESIGN_ONLY)) != DEPLOYED:
			continue
		var floors := definition.get("eligible_floor_numbers", []) as Array
		if floor_number not in floors:
			continue
		if (
			seed_value >= 0
			and str(definition.get("floor_selection_mode", "")) == "one_per_run_seed"
			and get_selected_floor_for_seed(str(definition.get("elite_id", "")), seed_value) != floor_number
		):
			continue
		if floor_number in floors:
			result.append(definition.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("elite_id", "")) < str(b.get("elite_id", ""))
	)
	return result


static func get_selected_floor_for_seed(elite_id: String, seed_value: int) -> int:
	var definition := get_by_id(elite_id)
	var floors := definition.get("eligible_floor_numbers", []) as Array
	if floors.is_empty():
		return 0
	var mixed_seed := seed_value ^ hash(elite_id)
	return int(floors[posmod(mixed_seed, floors.size())])


static func is_deployed_on_floor(elite_id: String, floor_number: int) -> bool:
	var definition := get_by_id(elite_id)
	return (
		str(definition.get("deployment_status", DESIGN_ONLY)) == DEPLOYED
		and floor_number in (definition.get("eligible_floor_numbers", []) as Array)
	)
