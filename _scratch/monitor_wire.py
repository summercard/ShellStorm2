from pathlib import Path
import json
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
def patch(path,a,b):
 p=R/path;t=p.read_text(encoding='utf-8');assert a in t,(path,a[:70]);p.write_text(t.replace(a,b,1),encoding='utf-8')
patch('src/enemy3d/BossContentCatalog.gd','static func get_by_content_id(content_id: String) -> Dictionary:\n','''const MONITOR_PROFILE := {"boss_content_id":"boss_monitor002", "display_name":"MONITOR.EXE 显示器", "presentation_asset_id":"ENM-BOSS-MONITOR002-3D", "presentation_scene":"res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn", "arena_asset_id":"", "arena_scene":"", "accent":Color(0.10,0.48,0.66), "phase_skill_bags":{1:["monitor_keyboard","monitor_cable","monitor_keyboard","monitor_spin_slam"],2:["monitor_cable","monitor_ground_current","monitor_keyboard","monitor_spin_slam"],3:["monitor_spin_slam","monitor_ground_current","monitor_cable","monitor_spin_slam","monitor_ground_current"]}}

static func get_by_content_id(content_id: String) -> Dictionary:
	if content_id == "boss_monitor002":return MONITOR_PROFILE.duplicate(true)
''')
patch('src/enemy3d/BossContentCatalog.gd','var result: Array[Dictionary] = []\n','var result: Array[Dictionary] = [MONITOR_PROFILE.duplicate(true)]\n')
patch('src/map/MonsterInjector.gd','result["boss_phase_skill_bags"] = (boss_profile["phase_skill_bags"] as Dictionary).duplicate(true)','''result["boss_phase_skill_bags"] = (boss_profile["phase_skill_bags"] as Dictionary).duplicate(true)
	if str(boss_profile["boss_content_id"]) == "boss_monitor002":
		# Fixed monitor encounter baseline, independent of obsolete tower depth multipliers.
		result.merge({"hp":200,"max_hp":200,"damage":20,"speed":41.28,"boss_scale":1.0},true)''')
patch('src/enemy3d/Enemy3D.gd','var _boss_skill_index := 0','var _boss_skill_index := 0\nvar monitor_combat: MonitorBossCombat')
patch('src/enemy3d/Enemy3D.gd','func configure_from_enemy_data(data: Dictionary) -> void:\n','func configure_from_enemy_data(data: Dictionary) -> void:\n\tif monitor_combat != null:monitor_combat.cancel()\n\tmonitor_combat = null\n')
patch('src/enemy3d/Enemy3D.gd','avatar.configure_boss_content(str(data.get("boss_content_id", "")))','''avatar.configure_boss_content(str(data.get("boss_content_id", "")))
		if str(data.get("boss_content_id", "")) == MonitorBossCombat.ID:
			monitor_combat = MonitorBossCombat.new(self)
			attack_range = 6.0''')
patch('src/enemy3d/Enemy3D.gd','avatar.sync_presentation(ai_state, _state_time, Vector2(get_real_velocity().x, get_real_velocity().z).length(), _telegraph_duration(), _recovery_duration())','''if monitor_combat != null:
			avatar.sync_boss_presentation(monitor_combat.presentation_context())
		else:
			avatar.sync_presentation(ai_state, _state_time, Vector2(get_real_velocity().x, get_real_velocity().z).length(), _telegraph_duration(), _recovery_duration())''')
patch('src/enemy3d/Enemy3D.gd','_apply_ai_decision(_ai_decision)\n','_apply_ai_decision(_ai_decision)\n\tif monitor_combat != null and monitor_combat.tick(delta):return\n')
patch('src/enemy3d/Enemy3D.gd','if to_target.length_squared() > 0.01 and not clap_locked:\n','''if monitor_combat != null:
		monitor_combat.face_target(to_target,delta)
	elif to_target.length_squared() > 0.01 and not clap_locked:
''')
patch('src/enemy3d/Enemy3D.gd','if enemy_kind in ["ranged_caster", "summoner", "boss"]:\n\t\tvar radial','if enemy_kind in ["ranged_caster", "summoner", "boss"] and monitor_combat == null:\n\t\tvar radial')
patch('src/enemy3d/Enemy3D.gd','elif interrupt_movement and (enemy_kind != "fat_zombie03"','''elif monitor_combat != null:
			monitor_combat.on_damage(applied,critical,hit_knockback,interrupt_movement)
		elif interrupt_movement and (enemy_kind != "fat_zombie03"''')
patch('src/enemy3d/Enemy3D.gd','ai_state = state_id\n\t_last_state_reason','''ai_state = state_id
	if monitor_combat != null:
		if state_id == "telegraph":monitor_combat.begin()
		elif state_id in ["dead","dormant"]:monitor_combat.cancel()
	_last_state_reason''')
patch('src/enemy3d/Enemy3D.gd','if avatar != null and avatar.has_formal_normal():\n','if avatar != null and (avatar.has_formal_normal() or monitor_combat != null):\n')
patch('src/enemy3d/Enemy3D.gd','"boss_skill_index": _boss_skill_index,\n\t}', '"boss_skill_index": _boss_skill_index,\n\t\t"monitor_poise_damage": monitor_combat.poise_damage if monitor_combat != null else 0.0,\n\t\t"monitor_electric_cooldown": monitor_combat.electric_cooldown if monitor_combat != null else 0.0,\n\t}')
patch('src/enemy3d/Enemy3D.gd','var saved_ai_state := str(state.get("ai_state", "idle"))','''if monitor_combat != null:
		monitor_combat.cancel()
		monitor_combat.poise_damage = maxf(0.0,float(state.get("monitor_poise_damage",0.0)))
		monitor_combat.electric_cooldown = maxf(0.0,float(state.get("monitor_electric_cooldown",0.0)))
	var saved_ai_state := str(state.get("ai_state", "idle"))''')
patch('src/enemy3d/EnemyAvatar3D.gd','if _formal_boss_root != null and is_instance_valid(_formal_boss_root):\n\t\t_formal_boss_root.queue_free()','if _formal_boss_root != null and is_instance_valid(_formal_boss_root):\n\t\t_root.remove_child(_formal_boss_root)\n\t\t_formal_boss_root.queue_free()')
patch('src/enemy3d/EnemyAvatar3D.gd','func flash_hit() -> void:\n','func flash_hit() -> void:\n\tif has_animated_boss():_formal_boss_root.flash_hit()\n')
patch('src/enemy3d/EnemyAvatar3D.gd','func get_formal_death_duration() -> float:\n','func get_formal_death_duration() -> float:\n\tif has_animated_boss():return 2.0\n')
patch('src/enemy3d/EnemyAvatar3D.gd','"procedural_pose": not has_formal_normal(),','"procedural_pose": not has_formal_normal() and not has_animated_boss(),\n\t\t"boss_presentation": _formal_boss_root.get_presentation_snapshot() if has_animated_boss() else {},')
patch('src/enemy3d/EnemyAvatar3D.gd','if has_formal_normal():\n\t\t_root.position = Vector3.ZERO','if has_formal_normal() or has_animated_boss():\n\t\t_root.position = Vector3.ZERO')
patch('src/enemy3d/EnemyAvatar3D.gd','_tell_ring.visible = ai_state == "telegraph"\n\t\treturn','_tell_ring.visible = ai_state == "telegraph" and not has_animated_boss()\n\t\treturn')
patch('src/enemy3d/EnemyAvatar3D.gd','func sync_presentation(state:', '''func has_animated_boss() -> bool:
	return is_instance_valid(_formal_boss_root) and _formal_boss_root.has_method("sync_context")

func sync_boss_presentation(context: Dictionary) -> void:
	if has_animated_boss():_formal_boss_root.sync_context(context)

func sync_presentation(state:''')
C=B/'components/enm_boss_monitor002';lib=json.loads((B/'source/expression_library_v004.json').read_text());(C/'expression_regions.json').write_text(json.dumps(lib['per_expression_slot_boxes_pixels']))
P=B/'runtime/enm_boss_monitor002';P.mkdir(parents=True,exist_ok=True)
(P/'enm_boss_monitor002_root_top3d.tscn').write_text('''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/enemy3d/MonitorBossPresentation.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/enm_boss_monitor002_visual_top3d.glb" id="2"]

[node name="MonitorBossPresentation" type="Node3D"]
script = ExtResource("1")
metadata/asset_id = "ENM-BOSS-MONITOR002-3D"
metadata/asset_version = "v031"

[node name="Model" parent="." instance=ExtResource("2")]
''',encoding='utf-8')
print('Wired monitor catalog, Enemy3D strategy, pure visual prefab')
