class_name BossContentCatalog
extends RefCounted
## 每五层Boss的稳定内容、阶段技能袋、表现资产与独立竞技场资产映射。

const CONTENT: Dictionary = {
	95: {"boss_content_id":"boss_abyss_archivist_95","display_name":"深渊档案官","presentation_asset_id":"ENM-BOSS-ARCHIVIST-95","presentation_scene":"res://assets/art/enemies/bosses_v01/enm_boss_archivist_95_top3d_v001.glb","arena_asset_id":"ENV-BOSS-ARENA-ARCHIVE-95","arena_scene":"res://assets/art/environments/boss_arenas_v01/env_boss_arena_archive_95_top3d_v001.glb","accent":Color(0.10,0.86,1.0),"phase_skill_bags":{1:["archive_fan","summon_scribes","archive_fan"],2:["index_beam","archive_fan","summon_scribes","index_beam"],3:["archive_storm","summon_scribes","index_beam","archive_storm"]}},
	90: {"boss_content_id":"boss_furnace_warden_90","display_name":"熔炉狱监","presentation_asset_id":"ENM-BOSS-FURNACE-WARDEN-90","presentation_scene":"res://assets/art/enemies/bosses_v01/enm_boss_furnace_warden_90_top3d_v001.glb","arena_asset_id":"ENV-BOSS-ARENA-FURNACE-90","arena_scene":"res://assets/art/environments/boss_arenas_v01/env_boss_arena_furnace_90_top3d_v001.glb","accent":Color(1.0,0.20,0.035),"phase_skill_bags":{1:["molten_volley","hammer_drive","molten_volley"],2:["summon_cinders","hammer_drive","furnace_burst","molten_volley"],3:["furnace_burst","summon_cinders","hammer_drive","furnace_burst"]}},
	85: {"boss_content_id":"boss_hollow_choir_85","display_name":"空洞合唱团","presentation_asset_id":"ENM-BOSS-HOLLOW-CHOIR-85","presentation_scene":"res://assets/art/enemies/bosses_v01/enm_boss_hollow_choir_85_top3d_v001.glb","arena_asset_id":"ENV-BOSS-ARENA-CHOIR-85","arena_scene":"res://assets/art/environments/boss_arenas_v01/env_boss_arena_choir_85_top3d_v001.glb","accent":Color(0.62,0.16,1.0),"phase_skill_bags":{1:["choir_wave","summon_echoes","choir_wave"],2:["silence_chord","choir_wave","summon_echoes","echo_burst"],3:["echo_burst","silence_chord","summon_echoes","echo_burst"]}},
}

static func get_for_floor(floor_number: int) -> Dictionary:
	return (CONTENT.get(floor_number, {}) as Dictionary).duplicate(true)

static func get_by_content_id(content_id: String) -> Dictionary:
	for profile in CONTENT.values():
		if str((profile as Dictionary).get("boss_content_id", "")) == content_id:
			return (profile as Dictionary).duplicate(true)
	return {}


## 内容 ID → 该内容所属的稳定层号（名册里没有则返回 0）。
## 名册的键就是层号，故层号是内容的固有属性；设计源用 ID 指派时也要能拿到它，
## 否则结算（Enemy3D 的 floor_number 记账）会记在设计源房间所在的层号上。
static func floor_number_for_content_id(content_id: String) -> int:
	for floor_number in CONTENT.keys():
		var profile := CONTENT[floor_number] as Dictionary
		if str(profile.get("boss_content_id", "")) == content_id:
			return int(floor_number)
	return 0


## 本房实际出场的 Boss 档案 —— **唯一解析口径**。
##
## 优先级：设计源指定的 `boss_content_id` > 按层号指派（塔楼 95/90/85）。
## 返回空字典 = 本房**不出 Boss**，两种情形：
##   · 设计源没写 ID，且本层没有按层指派的内容（单层关卡 floor_number=0）——
##     口径：「没写 boss 就是没有 boss」；
##   · 设计源写了 ID，但名册里没有这一条（拼写错误）—— 静态校验已能拦住
##     `boss_content_id_unknown`；运行时**绝不静默替换成另一个 Boss**，
##     否则作者会看到一个自己没指定的首领。
##
## 返回的档案一律带 `floor_number`，供随后的结算按真实层号记账。
## 两个消费方（`MonsterInjector._generate_boss` / `TowerDescent3D._append_plan_room_record`）
## 都必须走本函数，禁止各自复刻「先按 ID、再按层」的回退顺序。
static func resolve_profile(authored_content_id: String, floor_number: int) -> Dictionary:
	if not authored_content_id.is_empty():
		var authored := get_by_content_id(authored_content_id)
		if authored.is_empty():
			return {}
		authored["floor_number"] = floor_number_for_content_id(authored_content_id)
		return authored
	var by_floor := get_for_floor(floor_number)
	if not by_floor.is_empty():
		by_floor["floor_number"] = floor_number
	return by_floor

static func all_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for floor_number in [95, 90, 85]:
		var profile := get_for_floor(floor_number)
		profile["floor_number"] = floor_number
		result.append(profile)
	return result
