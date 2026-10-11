import bpy, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
V006 = ROOT / 'art_source/environments/tower_zones/battle/source/common_components/v006/env_battle_common_components_source_v006.blend'
OUT = ROOT / 'art_source/environments/tower_zones/battle/source/common_components/v007'
OUT.mkdir(parents=True, exist_ok=True)

def remove_if_exists(name):
    c = bpy.data.collections.get(name)
    if c and c.library is None:
        bpy.data.collections.remove(c)

def cube(name, dims, loc, mat):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object
    o.name = name
    o.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    uv = o.data.uv_layers.get('UVMap')
    if uv: uv.name = 'PaletteUV'
    return o

def main():
    bpy.ops.wm.open_mainfile(filepath=str(V006))
    remove_if_exists('trim_fixed_2p5m_制作源')
    remove_if_exists('trim_fixed_2p5m_通用包')
    src = bpy.data.collections.new('trim_fixed_2p5m_制作源')
    out = bpy.data.collections.new('trim_fixed_2p5m_通用包')
    bpy.context.scene.collection.children.link(src)
    bpy.context.scene.collection.children.link(out)
    metal = bpy.data.materials['01_精工金属_紫色骨架']
    matte = bpy.data.materials['02_细腻哑光_青绿大面']
    gloss = bpy.data.materials['03_清漆反光_紫粉点缀']
    glow = bpy.data.materials['04_柔和自发光_UI灯光']
    # 2.5m closure trim: side rails define exact envelope; center panel carries the visual mass.
    parts = [
        cube('trim_fixed_2p5m_主体面板', (2.30, 0.18, 11.60), (0, 0, 5.80), matte),
        cube('trim_fixed_2p5m_左金属压边', (0.10, 0.28, 11.90), (-1.20, 0, 5.95), metal),
        cube('trim_fixed_2p5m_右金属压边', (0.10, 0.28, 11.90), (1.20, 0, 5.95), metal),
        cube('trim_fixed_2p5m_顶部灯带', (2.30, 0.08, 0.06), (0, -0.12, 11.82), glow),
        cube('trim_fixed_2p5m_底部灯带', (2.30, 0.08, 0.06), (0, -0.12, 0.08), glow),
        cube('trim_fixed_2p5m_中部识别条', (1.20, 0.05, 0.12), (0, -0.13, 6.10), gloss),
    ]
    for o in parts:
        src.objects.link(o)
        # remove default collection link
        for c in list(o.users_collection):
            if c != src: c.objects.unlink(o)
    # Output keeps body and emissive/detail surfaces separate.
    body = bpy.data.objects.new('trim_fixed_2p5m_主体_金属哑光反光', None)
    out.objects.link(body)
    body['asset_id'] = 'ENV-BATTLE-COMP-TRIM-FIXED-2P5M'
    body['bounds_size_m'] = [2.5, 0.3, 11.9]
    body['local_origin'] = [0.0, 0.0, 0.0]
    body['front_axis'] = '-Z'
    body['allowed_rotations_y_deg'] = [0,90,180,270]
    body['collision_owner'] = 'godot_wrapper'
    body['palette_uv_layer'] = 'PaletteUV'
    body['component_id'] = 'trim_fixed_2p5m'
    body['room_owned_geometry'] = False
    # Keep output collection as a semantic package and source geometry editable; instances use the package.
    for o in parts[:3] + [parts[5]]:
        out.objects.link(o)
        src.objects.unlink(o)
    for o in parts[3:5]:
        out.objects.link(o)
        src.objects.unlink(o)
    src.hide_viewport = True
    src.hide_render = True
    out.hide_viewport = False
    out.hide_render = False
    scene = bpy.context.scene
    scene['component_id'] = 'trim_fixed_2p5m'
    scene['asset_id'] = 'ENV-BATTLE-COMP-TRIM-FIXED-2P5M'
    scene['component_version'] = 'v001'
    scene['bounds_size_m'] = [2.5, 0.3, 11.9]
    scene['coordinate_contract'] = 'bottom Z=0; centered X/Y; front=-Z; rotations=0/90/180/270'
    scene['source_parent'] = 'art_source/environments/tower_zones/battle/source/common_components/v006/env_battle_common_components_source_v006.blend'
    blend = OUT / 'env_battle_common_components_source_v007.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    manifest = {
      'schema':'shellstorm2.battle.shared_component_manifest', 'schema_version':1,
      'component_id':'trim_fixed_2p5m', 'asset_id':'ENV-BATTLE-COMP-TRIM-FIXED-2P5M',
      'display_name':'2.5m固定收边组件', 'source_blend':str(blend.relative_to(ROOT)).replace('\\','/'),
      'component_collection':'trim_fixed_2p5m_通用包', 'authoring_collection':'trim_fixed_2p5m_制作源',
      'bounds_size_m':[2.5,0.3,11.9], 'local_origin_m':[0,0,0], 'front_axis':'-Z',
      'allowed_rotations_y_deg':[0,90,180,270], 'collision_owner':'godot_wrapper',
      'palette_uv_layer':'PaletteUV', 'room_owned_geometry':False,
      'materials':['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'],
      'design_note':'2.5m窄幅封边；双侧金属压边、上下柔和灯带、中部识别条；不替代5m墙体。'
    }
    (OUT/'component_packages'/'trim_fixed_2p5m').mkdir(parents=True, exist_ok=True)
    (OUT/'component_packages'/'trim_fixed_2p5m'/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    catalog = {'schema':'shellstorm2.battle.common_component_catalog','schema_version':1,'source_blend':manifest['source_blend'],'components':[manifest]}
    (OUT/'component_catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
    print('TRIM_COMPONENT_BUILT', blend, 'bounds=[2.5,0.3,11.9]')
main()
