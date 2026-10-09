import bpy,json,math,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_father_office/v002'
story='--story' in sys.argv
if story:O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/v001'
version='v001' if story else 'v002';prefix='env_block00_' if story else 'env_father_office_';asset='ENV-BATTLE-BLOCK00-STORY-ROOMS-SOURCE' if story else 'ENV-BATTLE-FATHER-OFFICE-SOURCE'
main=bpy.context.scene;catalog=json.loads((O/'component_catalog.json').read_text(encoding='utf8'));report=[]
for d in catalog:
 s=bpy.data.scenes.new('组件_'+d['name_zh']);s.unit_settings.system='METRIC';s.world=main.world
 original=bpy.data.collections[d['name_zh']]
 source=bpy.data.collections.new('01_制作组件_'+d['slug']);source.children.link(original);s.collection.children.link(source)
 output=bpy.data.collections.new('02_游戏输出_'+d['slug']);s.collection.children.link(output)
 master=bpy.data.collections[d['collection']];output.children.link(master)
 bpy.context.window.scene=s
 bpy.context.view_layer.update()
 s.view_layers[0].layer_collection.children[source.name].exclude=True
 bounds=d['bounds_size_m'];scale=max(bounds)*1.7
 cd=bpy.data.cameras.new('组件预览相机');camera=bpy.data.objects.new('组件预览相机',cd);s.collection.objects.link(camera)
 camera.location=(scale,-scale,scale*.8);target=Vector((0,0,bounds[2]*.45));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();cd.type='ORTHO';cd.ortho_scale=scale;s.camera=camera
 ld=bpy.data.lights.new('组件柔光','AREA');ld.energy=700;ld.size=6;light=bpy.data.objects.new('组件柔光',ld);s.collection.objects.link(light);light.location=(2,-3,7)
 s['asset_id']=d['component_id'];s['asset_version']=version;s['source_only']=True;s['block_id']='master_office';s['floor_number']=98
 dest=O/'component_packages'/d['category']/d['slug'];file=dest/(prefix+d['slug']+'_source_'+version+'.blend')
 bpy.data.libraries.write(str(file),{s},path_remap='RELATIVE',fake_user=True)
 manifest=json.loads((dest/'asset_manifest.json').read_text(encoding='utf8'));manifest['component_blend']=str(file.relative_to(R)).replace('\\','/');manifest['instance_count']=d['instance_count'];manifest['parent_asset_id']=asset;manifest['status']='Blender源已完成'
 (dest/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
 report.append({'slug':d['slug'],'path':str(file.relative_to(R)),'bytes':file.stat().st_size})
 bpy.context.window.scene=main
 bpy.data.scenes.remove(s)
(O/'package_delivery.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('PACKAGE_FILES_OK',len(report))
