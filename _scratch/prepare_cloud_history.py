from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
diag=root/'_scratch/deep_perf_project/diagnostics'
src=(root/'_scratch/probe_bridge_recheck.gd').read_text(encoding='utf-8')
src=src.replace('const OUTPUT := "res://outputs/stutter_bridge_recheck_20261004.json"','var OUTPUT := OS.get_environment("DEEP_OUTPUT")')
src=src.replace('var sequence := ["periodic_save_suppressed_a", "both_suppressed", "periodic_save_suppressed_b", "both_suppressed_repeat"]','var sequence := ["periodic_save_suppressed_a", "periodic_save_suppressed_b"]')
src=src.replace('RuntimePerformanceManager.set_verification_frame_budget_override(60)','GameTimeManager.set_elapsed_game_seconds(4500.0, false)\n\tGameTimeManager.clock_running = false\n\tRuntimePerformanceManager.set_verification_frame_budget_override(60)')
src=src.replace('phase_name = phase','phase_name = phase\n\t\tclouds.set("_flow_time", 0.0)')
src=src.replace('clouds.call("get_procedural_city_cache_snapshot")','clouds.call("get_procedural_city_cache_snapshot") if clouds.has_method("get_procedural_city_cache_snapshot") else {}')
src=src.replace('"save_breakdown": save_breakdown,','"window_size": str(get_window().size), "viewport_texture_size": str(get_viewport().get_texture().get_size()), "save_breakdown": save_breakdown,')
src=src.replace('var file := FileAccess.open(OUTPUT, FileAccess.WRITE)','player.global_position = Vector3(20, y, -56.5)\n\tawait get_tree().create_timer(0.4).timeout\n\tawait RenderingServer.frame_post_draw\n\tget_viewport().get_texture().get_image().save_png(OUTPUT.trim_suffix(".json") + ".png")\n\tvar file := FileAccess.open(OUTPUT, FileAccess.WRITE)')
(diag/'CloudHistory.gd').write_text(src,encoding='utf-8')
(diag/'CloudHistory.tscn').write_text('[gd_scene format=3]\n[ext_resource type="Script" path="res://diagnostics/CloudHistory.gd" id="1"]\n[node name="History" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8')
old=subprocess.check_output(['git','show','058ca672^:src/vfx/VfxCloudSea3D.gd'],cwd=root).decode('utf-8')
old=old.replace('mesh_node.material_override = mesh_node.material_override.duplicate()','mesh_node.material_override = mesh_node.material_override.duplicate()\n\t\t\t(mesh_node.material_override as ShaderMaterial).shader = load("res://diagnostics/cloud_before_oct02.gdshader")')
(diag/'cloud_before_oct02.txt').write_text(old,encoding='utf-8')
shader=subprocess.check_output(['git','show','058ca672^:assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader'],cwd=root)
(diag/'cloud_before_oct02.gdshader').write_bytes(shader)
current=root/'_scratch/deep_perf_project/src/vfx/VfxCloudSea3D.gd'
(diag/'cloud_current.txt').write_bytes(current.read_bytes())
print('cloud subsystem history comparison prepared')
