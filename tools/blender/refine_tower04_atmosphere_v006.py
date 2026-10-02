"""Derive v006 from v005; change only its separate presentation scene."""
import ast
import bpy
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path
from mathutils import Vector

R = Path(__file__).resolve().parents[2]
OLD = R / 'assets/art/environments/open_world/source/tower_04/v005'
OUT = OLD.parent / 'v006'
OLD_BLEND = next(OLD.glob('*.blend'))
BLEND = OUT / '塔4_末世平台模块化_150x50m_v006.blend'
assert Path(bpy.data.filepath).resolve() == OLD_BLEND.resolve()
assert not BLEND.exists(), 'Never overwrite an existing source version'
OUT.mkdir(exist_ok=True)
for directory in ('qa', 'previews', 'mood'):
    (OUT / directory).mkdir(exist_ok=True)

src = R / 'tools/blender/refine_tower04_routes_v003.py'
nodes = [n for n in ast.parse(src.read_text(encoding='utf-8')).body
         if isinstance(n, ast.FunctionDef) and n.name in {'sha', 'floats', 'signature', 'material_signature'}]
exec(compile(ast.Module(body=nodes, type_ignores=[]), str(src), 'exec'), globals())
old_hash = hashlib.sha256(OLD_BLEND.read_bytes()).hexdigest()
locked = json.loads((OLD / 'qa/locked_before.json').read_text(encoding='utf-8'))
MATS = list(bpy.data.materials)
before = {name: signature(bpy.data.objects[name]) for name in locked['objects']}
all_meshes = {o.name: signature(o) for o in bpy.data.objects if o.type == 'MESH'}
materials = material_signature()
neutral = bpy.data.scenes['Scene']
mood = bpy.data.scenes['塔4_黄昏末世氛围']
assert mood.world != neutral.world

# A low golden sun and a real sky gradient affect only the presentation scene.
sun = bpy.data.objects['末世夕阳']
azimuth = math.radians(28)
elevation = math.radians(12)
incoming = Vector((-math.cos(elevation)*math.cos(azimuth),
                   -math.cos(elevation)*math.sin(azimuth), -math.sin(elevation)))
sun.rotation_euler = incoming.to_track_quat('-Z', 'Y').to_euler()
sun.data.energy = 3.2
sun.data.color = (1.0, 0.66, 0.36)
sun.data.angle = math.radians(2.0)
fill = bpy.data.objects['天空冷色柔光']
fill.data.energy = 8500
fill.data.color = (0.68, 0.79, 1.0)
fill.data.size = 100
mood.world.use_nodes = True
tree = mood.world.node_tree
bg = tree.nodes.get('Background')
sky = tree.nodes.new('ShaderNodeTexSky')
sky.name = '末世展示_黄昏天空'
sky.sky_type = 'NISHITA'
sky.sun_disc = True
sky.sun_size = math.radians(1.0)
sky.sun_intensity = 0.3
sky.sun_elevation = elevation
sky.sun_rotation = azimuth
sky.altitude = 0.25
sky.air_density = 1.15
sky.dust_density = 2.0
sky.ozone_density = 1.0
tree.links.new(sky.outputs['Color'], bg.inputs['Color'])
bg.inputs['Strength'].default_value = 0.22
mood.view_settings.exposure = 0.1

# Distance-based aerial perspective, with no volumetric material or game geometry.
mood.view_layers[0].use_pass_mist = True
mood.world.mist_settings.start = 25.0
mood.world.mist_settings.depth = 150.0
mood.world.mist_settings.falloff = 'QUADRATIC'
mood.use_nodes = True
nt = mood.node_tree
nt.nodes.clear()
rl = nt.nodes.new('CompositorNodeRLayers')
rl.scene = mood
amount = nt.nodes.new('CompositorNodeMath')
amount.operation = 'MULTIPLY'
amount.inputs[1].default_value = 0.22
nt.links.new(rl.outputs['Mist'], amount.inputs[0])
mix = nt.nodes.new('CompositorNodeMixRGB')
mix.blend_type = 'MIX'
mix.inputs[2].default_value = (0.64, 0.42, 0.24, 1.0)
nt.links.new(amount.outputs[0], mix.inputs[0])
nt.links.new(rl.outputs['Image'], mix.inputs[1])
out = nt.nodes.new('CompositorNodeComposite')
nt.links.new(mix.outputs[0], out.inputs[0])

assert materials == material_signature() and len(bpy.data.materials) == 4
assert before == {name: signature(bpy.data.objects[name]) for name in before}
assert all_meshes == {o.name: signature(o) for o in bpy.data.objects if o.type == 'MESH'}
assert hashlib.sha256(OLD_BLEND.read_bytes()).hexdigest() == old_hash
game = next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
game.name = '02_游戏输出_独立资产包_v006'
neutral['version'] = 'v006'
neutral['atmosphere_revision'] = 'presentation_scene_only'
mood['version'] = 'v006'

meta = json.loads((OLD / 'catalog.json').read_text(encoding='utf-8'))
old_source = meta['source_blend']
new_source = BLEND.relative_to(R).as_posix()
def revise(value):
    if isinstance(value, dict): return {k: revise(v) for k, v in value.items()}
    if isinstance(value, list): return [revise(v) for v in value]
    if isinstance(value, str): return value.replace(old_source, new_source).replace('v005', 'v006')
    return value
meta = revise(meta)
meta['version'] = 'v006'
meta['source_blend'] = new_source
meta['source_status'] = 'atmosphere_pending_visual_validation'
meta['reference_atmosphere_status'] = 'golden_hour_sky_and_aerial_perspective_pending_review'
meta['geometry_parent_source'] = old_source
meta['geometry_parent_sha256'] = old_hash
for package in meta['packages']:
    directory = OUT / 'component_packages' / package['category'] / package['slug']
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'asset_manifest.json').write_text(json.dumps(package, ensure_ascii=False, indent=2), encoding='utf-8')
(OUT / 'catalog.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(OUT / 'component_packages/tree.txt').write_text((OLD/'component_packages/tree.txt').read_text(encoding='utf-8').replace('v005','v006'),encoding='utf-8')
for name in ('component_plan.json', 'route_centerlines.json'):
    p = OLD / name
    if p.exists():
        if name == 'route_centerlines.json':
            shutil.copy2(p, OUT / name)
            continue
        data = json.loads(p.read_text(encoding='utf-8'))
        (OUT / name).write_text(json.dumps(revise(data), ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
for name in ('locked_before.json', 'build_plan_result.json'):
    shutil.copy2(OLD / 'qa' / name, OUT / 'qa' / name)
for p in (OLD / 'previews').glob('*.png'):
    shutil.copy2(p, OUT / 'previews' / p.name)
(OUT / 'references').mkdir(exist_ok=True)
for p in (OLD / 'references').glob('*.png'):
    shutil.copy2(p, OUT / 'references' / p.name)
bpy.context.window.scene = neutral
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
report = {'passed': True, 'geometry_meshes_unchanged': len(all_meshes),
          'locked_objects_unchanged': len(before), 'four_original_materials_unchanged': True,
          'v005_source_sha256': old_hash, 'v006_source_sha256': hashlib.sha256(BLEND.read_bytes()).hexdigest(),
          'neutral_previews_inherited_unchanged': 6,
          'changes': ['12 degree golden-hour sun', 'Nishita sky', 'subtle distance mist compositor'],
          'no_new_game_geometry': True, 'no_new_materials': True}
(OUT / 'qa/atmosphere_revision.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'OPTIX'
prefs.get_devices()
for device in prefs.devices: device.use = device.type != 'CPU'
bpy.context.window.scene = mood
mood.cycles.device = 'GPU'
mood.cycles.samples = 32 if '--preview' in sys.argv else 64
names = ['CAM_末世_棚下主街', 'CAM_末世_营地设施近景'] if '--preview' in sys.argv else sorted(o.name for o in bpy.data.objects if o.type=='CAMERA' and o.name.startswith('CAM_末世_'))
for name in names:
    mood.camera = bpy.data.objects[name]
    mood.render.resolution_x = 1000 if '--preview' in sys.argv else 1600
    mood.render.resolution_y = 625 if '--preview' in sys.argv else 1000
    mood.render.resolution_percentage = 100
    mood.render.filepath = str(OUT / 'mood' / (name[4:] + '.png'))
    bpy.ops.render.render(write_still=True, scene=mood.name)
    print('RENDERED', name, flush=True)
print('ATMOSPHERE_V006_SAVED', report, flush=True)
