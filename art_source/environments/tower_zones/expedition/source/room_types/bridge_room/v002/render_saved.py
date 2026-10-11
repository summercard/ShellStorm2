from pathlib import Path
import bpy,json,sys
p=Path(bpy.data.filepath).parent
manifest=json.loads((p/'room_type_manifest.json').read_text(encoding='utf-8'))
mode=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'complete'
names={'complete':('参考镜头_完整外墙','complete_structure.png',False),'full':('参考镜头_剖视全景','reference_cutaway.png',True),'lower':('参考镜头_下层结构','lower_layers_detail.png',True),'upper':('参考镜头_上层机房','upper_machine_room_detail.png',True),'top':('参考镜头_顶视','top_plan.png',True)}
cam,out,cut=names[mode]
for rec in manifest['packages']: bpy.data.collections[rec['collection']].hide_render=cut and rec['reference_cutaway_hidden']
s=bpy.context.scene
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use=d.type!='CPU'
    s.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception: s.cycles.device='CPU'
s.camera=bpy.data.objects[cam];s.render.filepath=str(p/'renders'/out);s.render.resolution_percentage=100;s.cycles.samples=64
bpy.ops.render.render(write_still=True)
print('RENDER_COMPLETE',out)
