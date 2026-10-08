from pathlib import Path
R=Path.cwd();p=R/'tests/verification/verify_monitor_boss_flow.gd';s=p.read_text(encoding='utf-8');a=s.index('\t# Grounded move:');b=s.index('\tfor state in Enemy3D.VALID_STATES:',a)
s=s[:a]+'''\t# User r27: old walk rhythm, reduced 10-degree edge lift; all half frames stay supported.
\tvar base_i := (presenter.motion.bones as Array).find("pedestal_motion")
\tvar base_rest := presenter.skeleton.get_bone_global_rest(presenter._bone_map[base_i])
\tvar pedestal := presenter.find_child("Crescent pedestal",true,false) as MeshInstance3D
\tvar grounded := true
\tvar peak_tilt := 0.0
\tvar x_min := INF
\tvar x_max := -INF
\tfor sample in range(97):
\t\tpresenter.sync_context({"action_id":"move","time":sample/60.0},false)
\t\tvar deformation: Transform3D = presenter._blended[base_i]*base_rest.affine_inverse()
\t\tvar bounds := skinned_bounds(pedestal,presenter.skeleton)
\t\tgrounded = grounded and bounds.position.y > -0.0001 and bounds.position.y < 0.009
\t\tpeak_tilt = maxf(peak_tilt,rad_to_deg(acos(clampf(deformation.basis.y.normalized().dot(Vector3.UP),-1,1))))
\t\tx_min = minf(x_min,deformation.origin.x);x_max = maxf(x_max,deformation.origin.x)
\texpect(grounded and absf(peak_tilt-10.0)<0.1,"Move has reduced 10 degree lift and supported bottom at 60Hz")
\texpect(x_max-x_min>0.45,"Move retains original lateral shuffle without root travel")
''' +s[b:];p.write_text(s,encoding='utf-8')
p=R/'tests/verification/verify_monitor_boss_visual.gd';s=p.read_text(encoding='utf-8').replace('v032','v033');p.write_text(s,encoding='utf-8')
p=R/'assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn';s=p.read_text(encoding='utf-8').replace('v032','v033');p.write_text(s,encoding='utf-8')
