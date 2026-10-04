from pathlib import Path
import shutil,subprocess,os,re,json
root=Path(__file__).resolve().parents[1]
dest=root/'_scratch/deep_perf_project'
dest.mkdir(exist_ok=True)
for name in ['src']:
    shutil.copytree(root/name,dest/name,dirs_exist_ok=True)
for name in ['assets','data','scenes','addons']:
    if (root/name).exists() and not (dest/name).exists():
        subprocess.run(['powershell','-NoProfile','-Command',f"New-Item -ItemType Junction -Path '{dest/name}' -Target '{root/name}' | Out-Null"],check=True)
(dest/'.godot').mkdir(exist_ok=True)
for name in ['imported']:
    if not (dest/'.godot'/name).exists():
        subprocess.run(['powershell','-NoProfile','-Command',f"New-Item -ItemType Junction -Path '{dest/'.godot'/name}' -Target '{root/'.godot'/name}' | Out-Null"],check=True)
for name in ['global_script_class_cache.cfg','uid_cache.bin','scene_groups_cache.cfg']:
    shutil.copy2(root/'.godot'/name,dest/'.godot'/name)
shutil.copy2(root/'project.godot',dest/'project.godot')
diag=dest/'diagnostics'; diag.mkdir(exist_ok=True)
(diag/'Trace.gd').write_text('''extends RefCounted
static var active := false
static var phase := "boot"
static var spans: Dictionary = {}
static var events: Array = []
static func span(label: String, started: int) -> void:
\tif not active: return
\tvar us := Time.get_ticks_usec() - started
\tvar frame := Engine.get_process_frames()
\tif not spans.has(frame): spans[frame] = {}
\tvar f: Dictionary = spans[frame]
\tif not f.has(label): f[label] = [0, 0, 0]
\tf[label][0] += us
\tf[label][1] += 1
\tf[label][2] = maxi(f[label][2], us)
static func event(label: String, detail: Variant) -> void:
\tif active: events.append({"frame": Engine.get_process_frames(), "time_us": Time.get_ticks_usec(), "phase": phase, "label": label, "detail": detail})
''',encoding='utf-8')
specs={
'src/base/BaseManager.gd':[('save_base','reason','bool'),('flush_runtime_checkpoint','reason','bool'),('_capture_runtime_checkpoint','','Dictionary'),('_read_disk_revision','','int')],
'src/core/GameTimeManager.gd':[('flush_to_profile','reason','bool')],
'src/player3d/PlayerInteractionController3D.gd':[('_process','delta','void'),('_sync_interaction_dots','delta','void')],
'src/player3d/Player3D.gd':[('_physics_process','delta','void')],
'src/player3d/PlayerAvatar3D.gd':[('_process','delta','void')],
'src/world3d/TowerDescent3D.gd':[('_process','delta','void'),('_physics_process','delta','void'),('_update_floor_visibility_state','','void')],
'src/world3d/Dungeon3D.gd':[('_process','delta','void'),('build_runtime_save_snapshot','','Dictionary')],
'src/vfx/VfxCloudSea3D.gd':[('_process','delta','void')],
}
for path,functions in specs.items():
    p=dest/path; s=p.read_text(encoding='utf-8'); label=p.stem
    for name,args,ret in functions:
        pattern=r'^func '+re.escape(name)+r'\([^\n]*\)(?: -> [^:\n]+)?:'
        m=re.search(pattern,s,re.M)
        if not m: raise RuntimeError((path,name,'not found'))
        header=m.group(); renamed='__diag_'+label+'_'+name
        end=s.find('\nfunc ',m.end()); end=len(s) if end<0 else end
        body=s[m.end():end].replace('super(', 'super.'+name+'(')
        s=s[:m.start()]+header.replace('func '+name,'func '+renamed,1)+body+s[end:]
        wrapper='\n\n'+header+'\n\tvar __start := Time.get_ticks_usec()\n'
        wrapper+='\t'+('var __result = ' if ret!='void' else '')+renamed+'('+args+')\n'
        wrapper+='\tpreload("res://diagnostics/Trace.gd").span("'+label+'.'+name+'", __start)\n'
        if name in ['save_base','flush_runtime_checkpoint','flush_to_profile']:
            wrapper+='\tpreload("res://diagnostics/Trace.gd").event("'+label+'.'+name+'", {"reason": reason, "ms": (Time.get_ticks_usec()-__start)/1000.0, "ok": __result})\n'
        if ret!='void': wrapper+='\treturn __result\n'
        s+=wrapper
    p.write_text(s,encoding='utf-8')
app=Path('C:/tmp/ss2_deep_perf_20261004/Godot/app_userdata/弹壳风暴2'); app.mkdir(parents=True,exist_ok=True)
for name in ['base_save.json','graphics_settings.cfg','postfx_tuning.json']:
    source=Path(os.environ['APPDATA'])/'Godot/app_userdata/弹壳风暴2'/name
    if source.exists(): shutil.copy2(source,app/name)
print(dest)
