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

static func all_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for floor_number in [95, 90, 85]:
		var profile := get_for_floor(floor_number)
		profile["floor_number"] = floor_number
		result.append(profile)
	return result
