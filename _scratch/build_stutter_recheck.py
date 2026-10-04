from pathlib import Path
import shutil, os
p=Path(__file__).resolve().parents[1]
src=(p/'_scratch/probe_rooftop_stutter_20261004.gd').read_text(encoding='utf-8')
src=src.replace('rooftop_stutter_20261004_r4.json','stutter_recheck_20261004.json')
src=src.replace('var direct_save_ms: Array[float] = []','var direct_save_ms: Array[float] = []\nvar save_breakdown: Array[Dictionary] = []')
src=src.replace('var sequence := ["baseline_a", "periodic_save_suppressed_a", "baseline_b", "periodic_save_suppressed_b", "baseline_c"]','var sequence := ["baseline_a", "periodic_save_suppressed_a", "no_cloud", "both_suppressed", "baseline_b", "periodic_save_suppressed_b"]\n\tRenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)')
src=src.replace('clouds.visible = phase != "clouds_hidden"','clouds.visible = phase not in ["no_cloud", "both_suppressed"]')
src=src.replace('if phase.begins_with("periodic_save_suppressed"):','if phase.begins_with("periodic_save_suppressed") or phase == "both_suppressed":')
src=src.replace('"cpu_process_ms":','"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), "render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()), "cpu_process_ms":')
src=src.replace('var result := {"renderer":','for i in range(8):\n\t\tsave_breakdown.append(_measure_save_parts())\n\tvar result := {"save_breakdown": save_breakdown, "cloud_snapshot": clouds.call("get_presentation_snapshot"), "cloud_cache": clouds.call("get_procedural_city_cache_snapshot"), "main_towers_only": clouds.get("main_towers_only"), "renderer":')
src+='''
func _measure_save_parts() -> Dictionary:
\tvar row: Dictionary = {}
\tvar t := Time.get_ticks_usec()
\tvar disk := BaseManager._read_disk_revision()
\trow["read_revision_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tGameTimeManager.flush_to_profile("recheck_full_save")
\trow["full_flush_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tvar payload := BaseManager.data._to_dict()
\trow["snapshot_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tvar envelope := ProfileSaveService.build_envelope(payload, BaseManager.data.save_revision, "recheck_parts")
\trow["build_envelope_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tvar checksum := ProfileSaveService.checksum_payload(payload)
\trow["one_checksum_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tvar encoded := JSON.stringify(envelope, "\\t")
\trow["stringify_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\trow["bytes"] = encoded.to_utf8_buffer().size()
\tt = Time.get_ticks_usec()
\tvar success := AtomicJsonStore.save_dictionary("user://diagnostic_parts.json", envelope)
\trow["atomic_write_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tvar stored: Variant = AtomicJsonStore.load_dictionary("user://diagnostic_parts.json")
\trow["read_parse_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\tt = Time.get_ticks_usec()
\tvar unpacked := ProfileSaveService.unpack(stored)
\trow["unpack_validate_ms"] = (Time.get_ticks_usec() - t) / 1000.0
\trow["valid"] = success and bool(unpacked.get("success", false))
\trow["disk_revision"] = disk
\trow["checksum"] = checksum
\treturn row
'''
(p/'_scratch/probe_stutter_recheck_20261004.gd').write_text(src,encoding='utf-8')
(p/'_scratch/probe_stutter_recheck_20261004.tscn').write_text('[gd_scene format=3]\n[ext_resource type="Script" path="res://_scratch/probe_stutter_recheck_20261004.gd" id="1"]\n[node name="Recheck" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8')
dest=Path('C:/tmp/ss2_stutter_recheck_20261004/Godot/app_userdata/弹壳风暴2')
dest.mkdir(parents=True,exist_ok=True)
source=Path(os.environ['APPDATA'])/'Godot/app_userdata/弹壳风暴2'
for name in ['base_save.json','graphics_settings.cfg','postfx_tuning.json']:
    f=source/name
    if f.exists():
        shutil.copy2(f,dest/name)
        print(name,f.stat().st_size)
print('probe generated; copied profile/config to isolated APPDATA')
