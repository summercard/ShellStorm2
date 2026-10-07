"""使用固定相机/材质/灯光渲染塔3 v001 runtime 与 v003 优化候选对照。"""
from __future__ import annotations
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2')
BASE=ROOT/'assets/art/environments/open_world'
MANIFEST=BASE/'source/tower_03/export/v001/export_manifest.json'
OUTPUT=ROOT/'outputs/tower03_v003'


def parse():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    assert len(args)==2,(args,'需要 blend 与 output 子目录')
    return Path(args[0]), Path(args[1])


def all_mesh_objects(): return [o for o in bpy.data.objects if o.type=='MESH']


def points(objects): return [o.matrix_world@Vector(c) for o in objects for c in o.bound_box]


def bounds(objects):
    p=points(objects)
    return Vector((min(x.x for x in p),min(x.y for x in p),min(x.z for x in p))),Vector((max(x.x for x in p),max(x.y for x in p),max(x.z for x in p)))


def look_at(obj,target): obj.rotation_euler=(target-obj.location).to_track_quat('-Z','Y').to_euler()


def add_camera(name, location, target, lens=52):
    data=bpy.data.cameras.new(name); obj=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(obj); obj.location=location; data.lens=lens; look_at(obj,target); return obj


def add_lights(center,size):
    root=bpy.data.collections.new('v003_对照渲染灯光'); bpy.context.scene.collection.children.link(root)
    for name,offset,energy,color,area in [('主光',(-1.0,-1.3,1.7),1500,(0.68,0.82,1.0),max(size.x,size.y)),('辅光',(1.2,-0.5,0.8),900,(0.76,0.48,1.0),max(size.x,size.y)*.7),('轮廓光',(0.2,1.4,1.4),1200,(1.0,.5,.25),max(size.x,size.y)*.8)]:
        data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.color=color; data.shape='DISK'; data.size=area
        light=bpy.data.objects.new(name,data); root.objects.link(light); light.location=center+Vector((offset[0]*max(size.x,size.y),offset[1]*max(size.x,size.y),offset[2]*size.z)); look_at(light,center)


def render_view(name, camera, output):
    scene=bpy.context.scene; scene.camera=camera; scene.render.filepath=str(output); scene.render.image_settings.file_format='PNG'; scene.render.resolution_x=768; scene.render.resolution_y=768; scene.render.resolution_percentage=100; scene.render.engine='BLENDER_EEVEE_NEXT'; scene.render.film_transparent=False; scene.world.color=(.008,.012,.025); scene.view_settings.look='AgX - Medium High Contrast'; bpy.ops.render.render(write_still=True)


def main():
    blend,outdir=parse(); outdir=OUTPUT/outdir; outdir.mkdir(parents=True,exist_ok=True)
    assert Path(bpy.data.filepath).resolve()==blend.resolve(),(bpy.data.filepath,blend)
    objects=all_mesh_objects(); assert len(objects)>=217
    minimum,maximum=bounds(objects); size=maximum-minimum; center=(minimum+maximum)*.5; add_lights(center,size)
    manifest=json.loads(MANIFEST.read_text(encoding='utf-8')); byslug={r['slug']:bpy.data.objects[r['objects'][0]] for r in manifest['records'] if r['objects'][0] in bpy.data.objects}
    views={
      '全景_front':(center+Vector((0,-max(size.x,size.y)*1.85,size.z*.42)),center+Vector((0,0,size.z*.42)),54),
      '全景_back':(center+Vector((0,max(size.x,size.y)*1.85,size.z*.42)),center+Vector((0,0,size.z*.42)),54),
      '全景_side':(center+Vector((max(size.x,size.y)*1.85,0,size.z*.42)),center+Vector((0,0,size.z*.42)),54),
      '全景_rooftop':(center+Vector((size.x*.82,-size.y*.98,size.z*1.65)),center+Vector((0,0,size.z*.78)),58),
    }
    hvac=[byslug[s] for s in ('ac_lower_left','ac_upper_left','ac_lower_right','duct_upper_front','duct_lower_left','duct_lower_front','duct_lower_right') if s in byslug]
    roof=[o for o in objects if any((o.matrix_world@Vector(c)).z>maximum.z-size.z*.22 for c in o.bound_box)]
    hmin,hmax=bounds(hvac); hcenter=(hmin+hmax)*.5; hsize=hmax-hmin
    views['近景_HVAC']=(hcenter+Vector((max(hsize.x,hsize.y)*1.8,-max(hsize.x,hsize.y)*1.8,hsize.z*.7)),hcenter,max(48,60))
    rmin,rmax=bounds(roof); rcenter=(rmin+rmax)*.5; rsize=rmax-rmin
    views['近景_天台']=(rcenter+Vector((rsize.x*1.3,-rsize.y*1.55,rsize.z*1.4)),rcenter,max(48,58))
    for name,(location,target,lens) in views.items():
        cam=add_camera('固定_'+name,location,target,lens); render_view(name,cam,outdir/(name+'.png'))
    print('RENDERED',blend,outdir)

if __name__=='__main__': main()
