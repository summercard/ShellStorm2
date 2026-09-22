"""Render a low-cost Workbench preview for the component-library source."""
import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BLEND = ROOT / 'assets/art/environments/tower_zones/expedition/source/common_components/v001/expedition_boss_room_components_source_v001.blend'
OUT = ROOT / 'assets/art/environments/tower_zones/expedition/source/common_components/v001/renders/component_library_overview_workbench.png'

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.studio_light = 'paint.sl'
scene.display.shading.color_type = 'MATERIAL'
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = 'WORLD'
scene.display.shading.curvature_ridge_factor = 1.5
scene.display.shading.curvature_valley_factor = 1.0
scene.render.resolution_x = 1200
scene.render.resolution_y = 700
scene.render.resolution_percentage = 50
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(OUT)
OUT.parent.mkdir(parents=True, exist_ok=True)
scene.camera = bpy.data.objects.get('组件库代表组件相机')
assert scene.camera is not None
bpy.ops.render.render(write_still=True)
print('BOSS_COMPONENT_PREVIEW_OK', str(OUT), flush=True)
