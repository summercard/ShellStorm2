import bpy, json
from pathlib import Path
ROOT=Path('/Users/summercards/ShellStorm2')
manifest=json.loads((ROOT/'source/art/blender/base_facility_layout/export/v022/export_manifest.json').read_text())
for slug,p in manifest['packages'].items():
 c=bpy.data.collections[p['collection']]
 obs=set(c.objects)
 for ch in c.children: obs.update(ch.all_objects)
 obs=[o for o in obs if not o.name.startswith('COLLISION_') and o.type!='LIGHT']
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=next((o for o in obs if o.type=='EMPTY'),obs[0])
 bpy.ops.export_scene.gltf(filepath=str(ROOT/p['glb']),export_format='GLB',use_selection=True,export_yup=True,
  export_apply=False,export_animations=True,export_materials='EXPORT',export_image_format='NONE',export_lights=False,
  export_cameras=False,export_extras=True)
print(f'V022_REEXPORTED_WITHOUT_LIGHTS={len(manifest["packages"])}')
