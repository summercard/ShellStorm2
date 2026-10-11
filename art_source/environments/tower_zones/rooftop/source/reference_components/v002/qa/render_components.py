import bpy,json,math,shutil
from pathlib import Path
from mathutils import Vector
O=Path(__file__).resolve().parents[1]
catalog=json.loads((O/'component_packages_v002/catalog.json').read_text())
s=bpy.data.scenes.new('组件独立摄影');s.world=bpy.data.worlds['中性日光世界']
s.collection.children.link(bpy.data.collections['90_展示与验收_灯光相机'])
s.render.engine='CYCLES';s.cycles.samples=16;s.cycles.use_denoising=True
s.render.resolution_x=500;s.render.resolution_y=440;s.render.resolution_percentage=100;s.render.film_transparent=True
s.render.image_settings.file_format='PNG';s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=.65
camd=bpy.data.cameras.new('组件相机');cam=bpy.data.objects.new('组件相机',camd);s.collection.objects.link(cam);camd.type='ORTHO';s.camera=cam
inst=bpy.data.objects.new('临时独立实例',None);inst.instance_type='COLLECTION';s.collection.objects.link(inst)
(O/'renders/components').mkdir(exist_ok=True)
for p in catalog:
    previous=O.parent/'v001/renders/components'/f'{p["slug"]}.png'
    if p['slug']!='door_lamp' and not p.get('vegetation_variant') and previous.exists():
        shutil.copy2(previous,O/'renders/components'/previous.name)
        continue
    inst.instance_collection=bpy.data.collections[p['blender_collection']]
    size=p['bounds_size'];height=size[2];extent=max(size)
    target=Vector((0,0,height/2));cam.location=target+Vector((.9,-1.8,1.25))*extent
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camd.ortho_scale=extent*1.65
    s.render.filepath=str(O/'renders/components'/f'{p["slug"]}.png');bpy.ops.render.render(write_still=True,scene=s.name)
# Same camera/light settings for a material-independent geometry review.
s=bpy.data.scenes['天台_参考拼装展示'];s.camera=bpy.data.objects['01_参考镜头全景']
m=bpy.data.materials.new('临时素模_不保存');m.diffuse_color=(.45,.45,.45,1);m.use_nodes=True;m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.45,.45,.45,1)
s.view_layers[0].material_override=m;s.render.filepath=str(O/'renders/00_固定镜头结构素模.png');bpy.ops.render.render(write_still=True,scene=s.name)
