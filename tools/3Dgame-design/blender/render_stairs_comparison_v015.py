"""Identical overhead and perspective views, before and after reconstruction."""
import bpy, math
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
out=ROOT/'source/art/whitebox/tower_zones/v015/renders'
out.mkdir(parents=True,exist_ok=True)
for version,path in [('before','v013/blender/whitebox_tower_stairs_v013.blend'),('after','v015/blender/whitebox_tower_stairs_v015.blend')]:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/art/whitebox/tower_zones'/path))
    scene=bpy.context.scene
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO'; scene.display.shading.studiolight_rotate_z=.4
    scene.display.shading.color_type='SINGLE'; scene.display.shading.single_color=(.42,.62,.66)
    scene.display.shading.show_shadows=True; scene.display.shading.show_cavity=True; scene.display.shading.cavity_type='BOTH'
    scene.display.shading.background_type='WORLD'; scene.world.color=(.08,.08,.08)
    scene.render.resolution_x=1280; scene.render.resolution_y=800; scene.render.resolution_percentage=100
    camera=bpy.data.objects.new('验收相机',bpy.data.cameras.new('验收相机')); scene.collection.objects.link(camera); scene.camera=camera
    camera.data.type='ORTHO'
    for view,position,target,scale in [('overview',(75,95,85),(0,0,-9),115),('top',(0,0,120),(0,0,-9),108),('close',(68,49,23),(40,11,-14),42)]:
        camera.location=position; camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler(); camera.data.ortho_scale=scale
        scene.render.filepath=str(out/f'{version}_{view}.png'); bpy.ops.render.render(write_still=True)
