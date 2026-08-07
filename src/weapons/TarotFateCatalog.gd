extends RefCounted
class_name TarotFateCatalog

## 运行时塔罗身份与逆位参数目录。
## stable_card_id 是唯一真值：旧中文功能名只负责旧存档迁移，玩家端统一显示塔罗名。

static var DEFINITIONS := {
	# 大阿尔卡那
	"fate_mark_enemy": _entry("愚者", "MAJOR", "MAJOR", "0", "十杀必得命运，失30魂", "每击杀10个敌人必得一张命运卡，同时失去30魂。", {"chance": 1.0, "currency_cost": 30}),
	"fate_gun_on_gun": _entry("魔术师", "MAJOR", "MAJOR", "I", "主副枪交替，单发更强", "主副枪改为交替开火；单发威力提高，但主枪射速降低。", {"alternate_fire": true, "damage_scale": 1.25, "fire_rate_scale": 0.75}),
	"fate_moon_vitality": _entry("女祭司", "MAJOR", "MAJOR", "II", "生命上限-10，恢复50", "最大生命降低10，并立即恢复50生命。", {"amount": -10, "heal": 50}),
	"fate_sun_extra_loot": _entry("皇后", "MAJOR", "MAJOR", "III", "下箱追加4抽，保留最佳", "下一个容器追加4次候选抽取并保留最高品质结果，最高为稀有且地面仍只掉落1件。", {"count": 4, "max_rarity": "RARE"}),
	"fate_sun_reinforce": _entry("皇帝", "MAJOR", "MAJOR", "IV", "下房增加精英，奖50魂", "下一个敌对房间增加1名精英；清理后额外获得50魂。", {"count": 1, "elite_count": 1, "clear_currency": 50}),
	"fate_sun_key": _entry("教皇", "MAJOR", "MAJOR", "V", "获得2把本层临时钥匙", "获得2把临时钥匙，离开当前楼层时失效。", {"count": 2, "temporary_floor_only": true}),
	"fate_moon_power": _entry("恋人", "MAJOR", "MAJOR", "VI", "枪伤-8%，暴击+15%", "枪械伤害降低8%，暴击率提高15%。", {"multiplier": 0.92, "crit_chance_bonus": 0.15}),
	"fate_bullet_carry_gun": _entry("战车", "MAJOR", "MAJOR", "VII", "携枪弹命中时高伤开火", "携枪子弹不再持续射击，只在命中时进行一次高伤射击。", {"fire_on_hit": true, "damage_scale": 1.15, "fire_rate_scale": 0.0}),
	"fate_armor_pierce": _entry("力量", "MAJOR", "MAJOR", "VIII", "伤害+15%，对盾翻倍", "伤害提高15%；不再穿盾，但对护盾造成双倍伤害。", {"damage_scale": 1.15, "pierce_shield": false, "shield_damage_scale": 2.0}),
	"fate_moon_stride": _entry("隐者", "MAJOR", "MAJOR", "IX", "移速-8%，冲刺无敌延长", "移动速度降低8%，冲刺无敌时间增加0.12秒。", {"multiplier": 0.92, "dash_invulnerability_bonus": 0.12}),
	"fate_every_seventh": _entry("命运之轮", "MAJOR", "MAJOR", "X", "换弹首发×2.5，弹匣-20%", "每次换弹后的第一发伤害×2.5，但弹匣容量降低20%。", {"nth": 1, "damage_multiplier": 2.5, "after_reload": true, "magazine_multiplier": 0.8}),
	"fate_sun_trial": _entry("正义", "MAJOR", "MAJOR", "XI", "下房敌伤-20%，魂减半", "下一个敌对房间敌人伤害降低20%，魂掉落减半。", {"damage_multiplier": 0.8, "currency_multiplier": 0.5}),
	"fate_moon_guard": _entry("倒吊人", "MAJOR", "MAJOR", "XII", "受伤+8%，反射15%", "受到伤害提高8%，同时反射15%的实际伤害。", {"multiplier": 1.08, "reflect_ratio": 0.15}),
	"fate_gluttony": _entry("死神", "MAJOR", "MAJOR", "XIII", "未命中成长，命中时释放", "未命中会累积子弹成长；下一次命中时消耗全部层数。", {"grow_on_miss": true, "consume_growth_on_hit": true}),
	"fate_sun_scorch": _entry("节制", "MAJOR", "MAJOR", "XIV", "下房敌血+20%，敌伤-20%", "下一个敌对房间敌人生命提高20%，伤害降低20%。", {"multiplier": 1.2, "damage_multiplier": 0.8}),
	"fate_out_of_control": _entry("恶魔", "MAJOR", "MAJOR", "XV", "乱射收束，射速更高", "乱射收束为90度锥形；射速提高，但后坐力增大。", {"aim_randomness": 0.25, "fire_rate_scale": 1.3, "recoil_scale": 1.5}),
	"fate_explode_reload": _entry("高塔", "MAJOR", "MAJOR", "XVI", "换弹产生聚怪爆炸", "换弹产生低伤害吸引爆炸，换弹额外耗时缩短为0.2秒。", {"explosion_damage_scale": 0.3, "attract_enemies": true, "reload_time_add": 0.2}),
	"fate_living_bullet": _entry("星星", "MAJOR", "MAJOR", "XVII", "追踪最远目标，伤害+25%", "子弹改为追踪最远可见敌人，并提高25%伤害。", {"target_mode": "farthest", "damage_scale": 1.25}),
	"fate_moon_first_hit": _entry("月亮", "MAJOR", "MAJOR", "XVIII", "后续3次受伤降低20%", "每房首次受伤不减免；随后3次受到的伤害降低20%。", {"multiplier": 1.0, "following_hit_multiplier": 0.8, "following_hit_count": 3}),
	"fate_sun_currency": _entry("太阳", "MAJOR", "MAJOR", "XIX", "魂-15%，每3掉落升品", "魂获取降低15%，每第3件掉落物品质提高1级。", {"multiplier": 0.85, "quality_every": 3, "quality_tiers": 1}),
	"fate_moon_last_stand": _entry("审判", "MAJOR", "MAJOR", "XX", "致命时耗50魂并回血", "受到致命伤时消耗50魂并恢复25%生命；每张牌仅触发一次。", {"charges": 1, "currency_cost": 50, "heal_ratio": 0.25}),
	"fate_sun_extraction": _entry("世界", "MAJOR", "MAJOR", "XXI", "撤离+30%，敌速减半", "撤离同步时间增加30%，同步区域内敌人移动速度降低50%。", {"multiplier": 1.3, "enemy_speed_multiplier": 0.5}),

	# 权杖：14张星星命运
	"fate_scale_node": _entry("权杖·王牌", "MINOR", "WANDS", "ACE", "体积缩小，速度提高", "体积×0.75、伤害降低20%、速度提高25%。", {"scale": 0.75, "damage_scale": 0.8, "speed_scale": 1.25}),
	"fate_overclock": _entry("权杖·二", "MINOR", "WANDS", "2", "射速-25%，单发+55%", "射速降低25%，单发伤害提高55%。", {"fire_rate_scale": 0.75, "damage_scale": 1.55, "overheat_penalty": 1.0}),
	"fate_attachment_parasite": _entry("权杖·三", "MINOR", "WANDS", "3", "配件改为换弹时触发", "配件效果改在换弹完成时触发，冷却3秒。", {"trigger_on_hit": false, "trigger_on_reload": true, "cooldown": 3.0}),
	"fate_turret_on_land": _entry("权杖·四", "MINOR", "WANDS", "4", "生成4秒移动炮台", "落地生成持续4秒、跟随玩家移动的炮台。", {"turret_duration": 4.0, "mobile_turret": true}),
	"fate_home_on_land": _entry("权杖·五", "MINOR", "WANDS", "5", "去程减伤，回程强化", "去程伤害降低30%，回程伤害提高120%。", {"outbound_damage_multiplier": 0.7, "return_damage_multiplier": 2.2}),
	"fate_bullet_return": _entry("权杖·六", "MINOR", "WANDS", "6", "折返回枪并回填1发", "命中后返回枪械并回填1发弹药，回程不造成伤害。", {"bounce_count": 1, "damage_scale_on_bounce": 0.0, "refund_ammo": 1}),
	"fate_chain_lightning": _entry("权杖·七", "MINOR", "WANDS", "7", "连锁5次，范围缩小", "最多连锁5次，连锁范围缩小，每次造成50%伤害。", {"chain_count": 5, "chain_range": 105.0, "chain_damage_scale": 0.5}),
	"fate_bounce_bullet": _entry("权杖·八", "MINOR", "WANDS", "8", "只弹1次，反弹后增伤", "只弹跳1次，反弹后伤害提高35%。", {"bounce_count": 1, "damage_scale": 1.35}),
	"fate_barrage_copy": _entry("权杖·九", "MINOR", "WANDS", "9", "前后各发一波", "同时向前、后各发一波，后方弹幕造成80%伤害。", {"copy_fire_delay": 0.0, "backward_wave": true, "second_wave_damage_scale": 0.8}),
	"fate_fuse_fire": _entry("权杖·十", "MINOR", "WANDS", "10", "低火伤延长，可刷新", "每秒4%火焰伤害，持续6秒，并可刷新持续时间。", {"dot_damage_per_sec": 0.04, "dot_duration": 6.0, "refresh_duration": true}),
	"fate_fuse_frost": _entry("权杖·侍从", "MINOR", "WANDS", "PAGE", "不冻结，减速35%", "不再冻结，改为减速35%，持续3秒。", {"freeze_duration": 0.0, "slow_ratio": 0.35, "slow_duration": 3.0}),
	"fate_fuse_poison": _entry("权杖·骑士", "MINOR", "WANDS", "KNIGHT", "毒不叠层，延迟爆发", "毒素不叠层，3秒后一次爆发35%武器伤害。", {"max_stacks": 1, "burst_delay": 3.0, "burst_damage_scale": 0.35}),
	"fate_crit_kill": _entry("权杖·王后", "MINOR", "WANDS", "QUEEN", "暴击击杀后3发增伤", "暴击击杀后接下来3发伤害提高30%，不保证暴击。", {"stacks": 3, "guaranteed_crit": false, "damage_multiplier": 1.3}),
	"fate_huge_scale": _entry("权杖·国王", "MINOR", "WANDS", "KING", "体积缩小，速度大增", "体积×0.65、伤害降低20%、速度提高60%。", {"scale": 0.65, "damage_scale": 0.8, "speed_scale": 1.6}),

	# 圣杯：当前已实装5张月亮命运
	"fate_moon_dash": _entry("圣杯·王牌", "MINOR", "CUPS", "ACE", "冲刺变慢，距离和无敌增加", "冲刺冷却增加20%，冲刺距离与无敌时间提高40%。", {"multiplier": 1.2, "distance_multiplier": 1.4, "invulnerability_multiplier": 1.4}),
	"fate_moon_room_heal": _entry("圣杯·二", "MINOR", "CUPS", "2", "进房失3血，清房回12", "进入新房失去3生命；清理房间后恢复12生命。", {"amount": -3, "clear_heal": 12}),
	"fate_moon_elite_heal": _entry("圣杯·三", "MINOR", "CUPS", "3", "精英开战得20护盾", "精英或首领进入战斗时获得20护盾，击杀不再回血。", {"amount": 0, "elite_engage_shield": 20}),
	"fate_moon_ammo": _entry("圣杯·四", "MINOR", "CUPS", "4", "进房首次换弹+25%", "进入新房后的首次换弹速度提高25%。", {"ratio": 0.0, "first_reload_speed": 1.25}),
	"fate_bless_dead": _entry("圣杯·五", "MINOR", "CUPS", "5", "高血存活后伤害+8%", "高于70%生命存活30秒后，伤害提高8%。", {"hp_threshold": 0.7, "threshold_mode": "above", "survive_duration": 30.0, "damage_bonus": 0.08}),

	# 星币：当前已实装7张太阳命运
	"fate_reinforce": _entry("星币·王牌", "MINOR", "PENTACLES", "ACE", "五杀增援精英，额外奖魂", "5连杀后增援1名精英，击杀后额外获得50魂。", {"spawn_count": 1, "spawn_elite": true, "clear_currency": 50}),
	"fate_lucky_chest": _entry("星币·二", "MINOR", "PENTACLES", "2", "下箱降品，但多2件", "下一个容器品质降低1级，但额外增加2件物品。", {"quality_boost": -1, "extra_count": 2}),
	"fate_extra_loot": _entry("星币·三", "MINOR", "PENTACLES", "3", "下箱追加抽取，单件升品", "下一个容器追加一次候选抽取，保留结果品质提高1级，地面仍只掉落1件。", {"extra_count": 1, "quality_boost": 1}),
	"fate_curse_map": _entry("星币·四", "MINOR", "PENTACLES", "4", "敌伤-10%，魂-30%", "当前房敌人伤害降低10%，但魂掉落降低30%。", {"enemy_damage_multiplier": 0.9, "currency_multiplier": 0.7}),
	"fate_sun_quality": _entry("星币·五", "MINOR", "PENTACLES", "5", "下箱品质+2，数量-1", "下一个容器品质提高2级，但物品数量减少1件。", {"tiers": 2, "count_delta": -1}),
	"fate_sun_reveal": _entry("星币·六", "MINOR", "PENTACLES", "6", "揭示4层，只见拓扑", "揭示周围4层拓扑，但隐藏房间类型。", {"radius": 4, "hide_room_types": true}),
	"fate_sun_bounty": _entry("星币·七", "MINOR", "PENTACLES", "7", "下房奖120，之后两房无魂", "下一个敌对房奖励120魂，之后2个敌对房不掉落魂。", {"rooms": 1, "amount": 120, "zero_currency_rooms_after": 2}),
}


static func _entry(
	name: String,
	arcana: String,
	suit: String,
	number: String,
	reversed_short: String,
	reversed_description: String,
	reversed_effect_patch: Dictionary
) -> Dictionary:
	return {
		"name": name,
		"arcana": arcana,
		"suit": suit,
		"number": number,
		"reversed_short": reversed_short,
		"reversed_description": reversed_description,
		"reversed_effect_patch": reversed_effect_patch,
	}


static func get_definition(stable_card_id: String) -> Dictionary:
	return (DEFINITIONS.get(stable_card_id, {}) as Dictionary).duplicate(true)


static func get_tarot_name(stable_card_id: String, fallback := "") -> String:
	return str((DEFINITIONS.get(stable_card_id, {}) as Dictionary).get("name", fallback))


static func has_definition(stable_card_id: String) -> bool:
	return DEFINITIONS.has(stable_card_id)
