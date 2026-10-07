import bpy,json,hashlib,math
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v004'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for key,tag in [('source_blend','source'),('optimized_blend','optimized')]:
 p=m[key];assert sha(p)==m['hashes_sha256'][tag]
 bpy.ops.wm.open_mainfile(filepath=p);bpy.context.preferences.filepaths.save_version=0
 mat=bpy.data.materials['01_精工金属_紫色骨架'];node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 node.inputs['Roughness'].default_value=.32;node.inputs['Coat Weight'].default_value=.1
 count=0
 for o in bpy.data.objects:
  if o.type!='MESH' or 'PaletteUV' not in o.data.uv_layers:continue
  uv=o.data.uv_layers['PaletteUV']
  for f in o.data.polygons:
   if all(int(uv.data[l].uv.x*10)==9 and int(uv.data[l].uv.y*10)==3 for l in f.loop_indices):
    for l in f.loop_indices:uv.data[l].uv.y+=.3
    count+=1
 if tag=='optimized':bpy.context.scene['optimized_source_sha256']=m['hashes_sha256']['source']
 bpy.ops.wm.save_as_mainfile(filepath=p);m['hashes_sha256'][tag]=sha(p)
 print('LOCAL_FRAME_UV_CHANGED',tag,count)
light=bpy.data.objects['StatusLight_UI灯光_柔和自发光'];light.name='StatusLight'
bpy.ops.object.select_all(action='DESELECT')
for name in ['ItemRoot','Visual','Antenna','StatusLight']:bpy.data.objects[name].select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['ItemRoot']
bpy.ops.export_scene.gltf(filepath=m['component_glb'],export_format='GLB',use_selection=True,export_apply=True,export_image_format='NONE',export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
m['hashes_sha256']['glb']=sha(m['component_glb'])
m['materials']['01_精工金属_紫色骨架'].update(roughness=.32,coat=.1)
m['palette']['metal_frame_cell']=[9,6]
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('LOCAL_METAL_GLARE_REDUCED_OK')
