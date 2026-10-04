from pathlib import Path
root=Path.cwd()
def edit(path, pairs):
 p=root/path;s=p.read_text(encoding='utf-8')
 for old,new in pairs:
  assert old in s,(path,old)
  s=s.replace(old,new,1)
 p.write_text(s,encoding='utf-8')
edit('src/enemy3d/EnemyAvatar3D.gd',[
 ('const COLORS := {','const COLORS := {\n\t"fat_zombie03": Color(0.38, 0.43, 0.26),'),
 ('const FOOTPRINT_PROFILES := {','const FOOTPRINT_PROFILES := {\n\t"fat_zombie03": {"radius": 1.10, "height": 3.142857},'),
 ('const FORMAL_NORMAL_SCENES := {','const FORMAL_NORMAL_SCENES := {\n\t"fat_zombie03": "res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn",'),
 ('const FORMAL_NORMAL_HEIGHTS := {','const FORMAL_NORMAL_HEIGHTS := {"fat_zombie03": 3.142857, '),
])
edit('src/enemy3d/Enemy3D.gd',[
 ('const BODY_SCALE_BY_KIND := {','const BODY_SCALE_BY_KIND := {\n\t"fat_zombie03": 1.0,'),
 ('const HEALTH_BAR_SIZE_BY_KIND := {','const HEALTH_BAR_SIZE_BY_KIND := {\n\t"fat_zombie03": Vector2(1.8, 0.18),'),
 ('const PROFILES := {','const PROFILES := {\n\t"fat_zombie03": {"hp": 232, "speed": 0.857142857, "damage": 19, "range": 1.55, "cooldown": 1.3, "patrol_multiplier": 0.5, "telegraph": 1.2, "recovery": 1.3, "alert": 0.6, "stagger": 0.8},'),
 ('const SOURCE_HP_BASE := {','const SOURCE_HP_BASE := {\n\t"fat_zombie03": 100.0,'),
 ('const SOURCE_DAMAGE_BASE := {','const SOURCE_DAMAGE_BASE := {\n\t"fat_zombie03": 8.0,'),
 ('@export_enum("melee_chaser",','@export_enum("fat_zombie03", "melee_chaser",'),
 ('ai_state == "alert" and _state_time > 0.28','ai_state == "alert" and _state_time > float(PROFILES[enemy_kind].get("alert", 0.28))'),
 ('if _state_time > 0.16:\n\t\t\t\ttransition_to("chase")','if _state_time > float(PROFILES[enemy_kind].get("stagger", 0.16)):\n\t\t\t\ttransition_to("chase")'),
 ('if to_target.length_squared() > 0.01:\n\t\trotation.y = lerp_angle','var clap_locked := enemy_kind == "fat_zombie03" and (ai_state in ["attack", "recovery"] or (ai_state == "telegraph" and _state_time >= 1.0))\n\tif to_target.length_squared() > 0.01 and not clap_locked:\n\t\trotation.y = lerp_angle'),
 ('get_effective_move_speed() * 0.32,','get_effective_move_speed() * float(PROFILES[enemy_kind].get("patrol_multiplier", 0.32)),'),
 ('\tmatch enemy_kind:\n\t\t"ranged_caster":\n\t\t\t_fire_projectile_volley','\tmatch enemy_kind:\n\t\t"fat_zombie03":\n\t\t\t_last_attack_result = "miss"\n\t\t\tif distance <= attack_range and (-global_basis.z).dot(to_target.normalized()) >= 0.5 and is_instance_valid(_target) and _has_line_of_sight(_target) and _target.has_method("take_damage"):\n\t\t\t\tif _target.has_method("notify_attacked_by"):\n\t\t\t\t\t_target.call("notify_attacked_by", self)\n\t\t\t\t_target.call("take_damage", contact_damage, false, to_target.normalized())\n\t\t\t\t_last_attack_result = "hit"\n\t\t"ranged_caster":\n\t\t\t_fire_projectile_volley'),
 ('elif interrupt_movement:\n\t\t\ttransition_to("stagger")','elif interrupt_movement and (enemy_kind != "fat_zombie03" or critical or hit_knockback >= 0.8 or applied >= max_hp * 0.08):\n\t\t\ttransition_to("stagger")'),
 ('func _recovery_duration() -> float:\n\treturn','func _recovery_duration() -> float:\n\tif PROFILES[enemy_kind].has("recovery"):\n\t\treturn float(PROFILES[enemy_kind]["recovery"])\n\treturn'),
 ('func _telegraph_duration() -> float:\n','func _telegraph_duration() -> float:\n\tif PROFILES[enemy_kind].has("telegraph"):\n\t\treturn float(PROFILES[enemy_kind]["telegraph"])\n'),
 ('death_tween.tween_interval(2.4)','death_tween.tween_interval(float(avatar._formal_normal_root.get_presentation_snapshot().get("death_duration", 2.4)))'),
])
edit('src/map/MonsterInjector.gd',[
 ('const BASE_ENEMY_TYPES := {','const BASE_ENEMY_TYPES := {\n\t"fat_zombie03": {"name": "胖子僵尸", "hp_base": 100, "damage_base": 8, "speed": 20.5714286},'),
 ('const ENEMY_PRESENTATION := {','const ENEMY_PRESENTATION := {\n\t"fat_zombie03": {"emoji": "尸", "color": Color(0.38, 0.43, 0.26), "ai_type": "chase"},'),
])
edit('assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn',[
 ('load_steps=2','load_steps=3'),
 ('[node name="FatZombie03" type="Node3D"]','[ext_resource type="Script" path="res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/fat_zombie03_formal_visual.gd" id="2"]\n\n[node name="FatZombie03" type="Node3D"]\nscript = ExtResource("2")'),
 ('all_13_clips_verified_state_binding_pending','runtime_binding_pending_verification'),
 ('autoplay = "idle"','autoplay = ""'),
])
print('FAT_ZOMBIE03_BOUND')
