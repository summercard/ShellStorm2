from pathlib import Path
R=Path.cwd()
def edit(path, pairs):
 p=R/path;s=p.read_text(encoding='utf-8')
 for old,new in pairs:
  assert old in s,(path,old);s=s.replace(old,new,1)
 p.write_text(s,encoding='utf-8')
edit('src/enemy3d/MonitorBossCombat.gd',[
 ('const ID := "boss_monitor002"','const ID := "boss_monitor002"\nconst ACTIVATION_DURATION := 6.4'),
 ('var _phase_at_cast := 1','''var _phase_at_cast := 1
var activation_completed := false
var activation_elapsed := 0.0

func tick_activation(delta: float) -> bool:
	if activation_completed or owner_enemy.ai_state == "dead":return false
	if not owner_enemy._runtime_ai_active or owner_enemy.ai_state == "dormant":return true
	owner_enemy.transition_to("alert", "monitor_activation")
	owner_enemy.velocity.x = 0.0;owner_enemy.velocity.z = 0.0
	owner_enemy._commit_motion(delta)
	activation_elapsed = minf(ACTIVATION_DURATION, activation_elapsed + delta)
	if activation_elapsed >= ACTIVATION_DURATION:
		activation_completed = true
		owner_enemy._attack_timer = 0.65
		owner_enemy.transition_to("idle", "monitor_activation_finished")
	return true
'''),
 ('func begin() -> void:\n','func begin() -> void:\n\tif not activation_completed:return\n'),
 ('\tif owner_enemy.ai_state == "stagger" and seated:','\tif not activation_completed:return\n\tif owner_enemy.ai_state == "stagger" and seated:'),
 ('\tif state == "dead":clip = "dead"','\tif state == "dead":clip = "dead"\n\telif not activation_completed:clip = "activate";time = activation_elapsed')])
edit('src/enemy3d/Enemy3D.gd',[
 ('\t\t"monitor_electric_cooldown": monitor_combat.electric_cooldown if monitor_combat != null else 0.0,','''		"monitor_electric_cooldown": monitor_combat.electric_cooldown if monitor_combat != null else 0.0,
		"monitor_activation_completed": monitor_combat.activation_completed if monitor_combat != null else true,
		"monitor_activation_elapsed": monitor_combat.activation_elapsed if monitor_combat != null else 0.0,'''),
 ('\t\tmonitor_combat.electric_cooldown = maxf(0.0,float(state.get("monitor_electric_cooldown",0.0)))','''		monitor_combat.electric_cooldown = maxf(0.0,float(state.get("monitor_electric_cooldown",0.0)))
		monitor_combat.activation_completed = bool(state.get("monitor_activation_completed",true))
		monitor_combat.activation_elapsed = clampf(float(state.get("monitor_activation_elapsed",0.0)),0.0,MonitorBossCombat.ACTIVATION_DURATION)'''),
 ('\tif MonsterAIManager != null:\n\t\tMonsterAIManager.update_enemy_spatial(self)','\tif monitor_combat != null and monitor_combat.tick_activation(delta):return\n\tif MonsterAIManager != null:\n\t\tMonsterAIManager.update_enemy_spatial(self)'),
 ('\tif ai_state == state_id:\n','\tif monitor_combat != null and not monitor_combat.activation_completed and state_id not in ["dead","dormant","idle","alert"]:\n\t\treturn false\n\tif ai_state == state_id:\n')])
edit('src/enemy3d/monitor_code.gdshader',[
 ('uniform float scroll_phase;','uniform float scroll_phase;\nuniform float boot_reveal = 1.0;'),
 ('\tALBEDO = color;','\tcolor *= step(1.0 - boot_reveal, UV.y) * step(0.001, boot_reveal);\n\tALBEDO = color;')])
edit('src/enemy3d/MonitorBossPresentation.gd',[
 ('const FX_SCRIPT :=','const ACTIVATION_FX := preload("res://src/enemy3d/MonitorBossActivationVfx.gd")\nconst FX_SCRIPT :='),
 ('var _blend_time := 1.0','var _blend_time := 1.0\nvar _emerging_meshes: Array[MeshInstance3D] = []\nvar activation_fx: Node3D'),
 ('\t\tmesh.extra_cull_margin = 12.0','''		mesh.extra_cull_margin = 12.0
		var label := str(mesh.name)
		if label.begins_with("Continuous spring") or label.begins_with("Sculpted glove") or label.begins_with("White cuff") or label.begins_with("Behind monitor cable") or label.begins_with("Plug contact") or label in ["Long data cable whip","Cable strain relief","Connector alloy collar","Connector front inset","Data connector body","Luminous data plug"]:
			_emerging_meshes.append(mesh)'''),
 ('\tfx = FX_SCRIPT.new();fx.name = "CyberEffects";add_child(fx)','\tfx = FX_SCRIPT.new();fx.name = "CyberEffects";add_child(fx)\n\tactivation_fx = ACTIVATION_FX.new();activation_fx.name = "ActivationTethers";add_child(activation_fx)'),
 ('\tif _code:_code.set_shader_parameter("scroll_phase",code_phase)','\tif _code and action_id != "activate":_code.set_shader_parameter("scroll_phase",code_phase)'),
 ('and action_id != "dead":expression = 4','and action_id not in ["dead","activate"]:expression = 4'),
 ('\tfor slot in _faces:\n','\tfor slot in _faces:\n\t\tvar face_start := 5.7 if slot == "large_eye" else 5.83 if slot == "round_eye" else 6.0\n\t\t_faces[slot].mesh.visible = action_id != "activate" or sample_time >= face_start\n'),
 ('\tfx.sync_effects(context,self)','''		if action_id == "activate":
			var pop := clampf((sample_time-face_start)/0.20,0.0,1.0)
			var size := lerpf(0.20,1.0,pop) + sin(pop*PI)*0.35
			_faces[slot].material.set_shader_parameter("face_scale",Vector2(size,size))
	for mesh in _emerging_meshes:mesh.visible = action_id != "activate" or sample_time >= (3.73 if str(mesh.name).ends_with("L") else 3.9)
	if _code:
		_code.set_shader_parameter("boot_reveal",clampf(floorf((sample_time-0.60)*30.0)/27.0,0.0,1.0) if action_id == "activate" else 1.0)
		if action_id == "activate":_code.set_shader_parameter("scroll_phase",maxf(0.0,sample_time-0.6)*0.32)
	activation_fx.sync_activation(action_id,sample_time,self)
	fx.sync_effects(context,self)'''),
 ('"version":"v031"','"version":"v034"')])
print('ACTIVATION_RUNTIME_PATCHED')
