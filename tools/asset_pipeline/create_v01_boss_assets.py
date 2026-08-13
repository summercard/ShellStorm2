import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path('/Users/summercards/ShellStorm2')
BOSS_DIR = ROOT / 'assets/art/enemies/bosses_v01'
ARENA_DIR = ROOT / 'assets/art/environments/boss_arenas_v01'
SOURCE_DIR = ROOT / 'source/art/blender/bosses_v01'


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != 'Collection':
            bpy.data.collections.remove(collection)


def material(name, color, metallic=0.0, roughness=0.65, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = next(node for node in mat.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = strength
    return mat


def finish(obj, name, mat=None, bevel=0.08):
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    if bevel > 0:
        modifier = obj.modifiers.new('EdgeBevel', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
    bpy.ops.object.shade_smooth_by_angle()
    return obj


def cube(name, loc, scale, mat, rot=(0, 0, 0), bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)


def cyl(name, loc, radius, depth, mat, vertices=16, rot=(0, 0, 0), bevel=0.06):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    return finish(bpy.context.object, name, mat, bevel)


def sphere(name, loc, scale, mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, 0.04)


def torus(name, loc, major, minor, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=24, minor_segments=8, location=loc, rotation=rot)
    return finish(bpy.context.object, name, mat, 0.03)


def parent_root(name, asset_id):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    root['asset_id'] = asset_id
    root['forward_axis'] = '-Z'
    root['up_axis'] = '+Y'
    for obj in list(bpy.context.scene.objects):
        if obj != root and obj.parent is None:
            obj.parent = root
    return root


def export_asset(filename, asset_id, builder, out_dir):
    reset()
    builder()
    parent_root(filename.replace('.glb', ''), asset_id)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0
    source_path = SOURCE_DIR / filename.replace('.glb', '.blend')
    output_path = out_dir / filename
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    bpy.ops.export_scene.gltf(
        filepath=str(output_path), export_format='GLB', export_apply=True,
        export_yup=True, export_materials='EXPORT', export_cameras=False,
        export_lights=False, export_extras=True,
    )


steel = lambda: material('M_Steel', (0.09, 0.13, 0.17), 0.72, 0.38)
dark = lambda: material('M_DarkShell', (0.025, 0.04, 0.06), 0.45, 0.68)


def archivist():
    shell, trim = steel(), material('M_ArchiveIvory', (0.42, 0.52, 0.56), 0.25, 0.45)
    glow = material('M_ArchiveGlow', (0.02, 0.22, 0.27), 0.15, 0.25, (0.05, 0.9, 1.0), 7.0)
    cube('Shell_CoreObelisk', (0, 1.85, 0), (0.72, 1.35, 0.56), shell, rot=(0, 0, math.radians(45)), bevel=0.15)
    sphere('Core_LuminousArchive', (0, 1.9, -0.62), (0.48, 0.72, 0.22), glow)
    torus('StateVFX_OrbitRingA', (0, 1.95, 0), 1.52, 0.08, glow, rot=(math.radians(72), 0, 0))
    torus('StateVFX_OrbitRingB', (0, 1.95, 0), 1.12, 0.06, glow, rot=(math.radians(90), math.radians(35), 0))
    for side in (-1, 1):
        for i in range(3):
            cube(f'Appendage_PageWing_{side}_{i}', (side*(1.0+i*0.42), 2.15-i*0.12, 0.12+i*0.08), (0.36, 0.62-i*0.08, 0.08), trim, rot=(0, side*math.radians(15+i*9), side*math.radians(12)), bevel=0.05)
        cyl(f'Appendage_Stylus_{side}', (side*1.45, 1.05, 0), 0.10, 1.75, glow, vertices=12, rot=(0, math.radians(90), side*math.radians(18)))


def furnace():
    shell = material('M_FurnaceArmor', (0.16, 0.12, 0.10), 0.82, 0.40)
    brass = material('M_Brass', (0.38, 0.20, 0.07), 0.75, 0.34)
    glow = material('M_MoltenCore', (0.42, 0.04, 0.01), 0.05, 0.28, (1.0, 0.13, 0.015), 9.0)
    cyl('Shell_FurnaceTorso', (0, 1.45, 0), 1.08, 2.35, shell, vertices=16)
    torus('Shell_ArmorBand', (0, 1.45, 0), 1.10, 0.17, brass, rot=(math.radians(90), 0, 0))
    sphere('Core_MoltenHeart', (0, 1.48, -1.02), (0.58, 0.66, 0.20), glow)
    cyl('Appendage_Chimney', (0, 3.05, 0.25), 0.42, 1.25, shell, vertices=12)
    for side in (-1, 1):
        cube(f'Appendage_Shoulder_{side}', (side*1.22, 2.15, 0), (0.46, 0.43, 0.64), brass, rot=(0, 0, side*math.radians(10)), bevel=0.12)
        cyl(f'Appendage_HammerArm_{side}', (side*1.62, 1.25, 0), 0.22, 1.85, shell, vertices=12, rot=(0, math.radians(90), 0))
        cube(f'Appendage_HammerHead_{side}', (side*2.45, 1.20, 0), (0.54, 0.40, 0.68), brass, bevel=0.10)


def choir():
    shell = material('M_ChoirCeramic', (0.24, 0.22, 0.31), 0.28, 0.47)
    black = dark()
    glow = material('M_ChoirGlow', (0.10, 0.015, 0.22), 0.08, 0.25, (0.56, 0.10, 1.0), 8.0)
    sphere('Core_HollowMask', (0, 2.05, 0), (0.88, 1.25, 0.36), shell)
    sphere('Core_MaskVoid', (0, 2.03, -0.35), (0.54, 0.82, 0.12), black)
    torus('StateVFX_Halo', (0, 2.10, 0.18), 1.35, 0.10, glow, rot=(math.radians(90), 0, 0))
    for i in range(5):
        angle = math.tau * i / 5.0
        x, z = math.cos(angle)*1.85, math.sin(angle)*1.85
        sphere(f'Appendage_VoiceMask_{i}', (x, 1.25 + (i%2)*0.35, z), (0.35, 0.52, 0.18), shell)
        cyl(f'StateVFX_VoiceBeam_{i}', (x*0.60, 1.55, z*0.60), 0.035, 1.5, glow, vertices=8, rot=(math.radians(90), 0, -angle))


def archive_arena():
    stone, metal = material('M_ArchiveFloor', (0.10, 0.16, 0.18), 0.35, 0.75), steel()
    glow = material('M_ArchiveLine', (0.01, 0.18, 0.22), 0.1, 0.32, (0.03, 0.75, 1.0), 5.0)
    torus('Arena_CentralDataRing', (0, 0.12, 0), 7.0, 0.22, glow)
    for i in range(8):
        a = math.tau*i/8
        cube(f'Arena_ArchivePillar_{i}', (math.cos(a)*12, 1.5, math.sin(a)*12), (0.65, 1.5, 0.65), metal, rot=(0, -a, 0), bevel=0.12)
        cube(f'Arena_CoverPlinth_{i}', (math.cos(a+0.22)*7.8, 0.65, math.sin(a+0.22)*7.8), (1.8, 0.65, 0.55), stone, rot=(0, -a, 0), bevel=0.14)


def furnace_arena():
    iron = material('M_FoundryIron', (0.12, 0.09, 0.075), 0.82, 0.48)
    hazard = material('M_FoundryHeat', (0.48, 0.045, 0.008), 0.05, 0.30, (1.0, 0.10, 0.01), 7.0)
    cyl('Arena_CentralCrucible', (0, 0.55, 0), 3.8, 1.1, iron, vertices=20)
    torus('Arena_CrucibleHeat', (0, 1.12, 0), 3.25, 0.22, hazard)
    for i in range(6):
        a = math.tau*i/6
        cyl(f'Arena_VentStack_{i}', (math.cos(a)*11.5, 2.0, math.sin(a)*11.5), 0.65, 4.0, iron, vertices=12)
        cube(f'Arena_HeatBarrier_{i}', (math.cos(a+0.28)*7.8, 0.75, math.sin(a+0.28)*7.8), (2.2, 0.75, 0.42), iron, rot=(0, -a, 0), bevel=0.10)


def choir_arena():
    ceramic = material('M_ChoirStone', (0.15, 0.14, 0.21), 0.22, 0.72)
    glow = material('M_ChoirResonance', (0.10, 0.01, 0.23), 0.05, 0.28, (0.55, 0.08, 1.0), 6.0)
    torus('Arena_ResonanceCircle', (0, 0.10, 0), 8.5, 0.18, glow)
    for i in range(10):
        a = math.tau*i/10
        height = 2.4 + (i % 3)*0.65
        cyl(f'Arena_ChoirMonolith_{i}', (math.cos(a)*12.5, height/2, math.sin(a)*12.5), 0.52, height, ceramic, vertices=8)
        torus(f'Arena_VoiceRing_{i}', (math.cos(a)*12.5, height+0.25, math.sin(a)*12.5), 0.72, 0.06, glow)
    for i in range(5):
        a = math.tau*i/5 + 0.3
        cube(f'Arena_EchoCover_{i}', (math.cos(a)*6.5, 0.70, math.sin(a)*6.5), (1.6, 0.70, 0.48), ceramic, rot=(0, -a, 0), bevel=0.14)


for directory in (BOSS_DIR, ARENA_DIR, SOURCE_DIR):
    directory.mkdir(parents=True, exist_ok=True)

export_asset('enm_boss_archivist_95_top3d_v001.glb', 'ENM-BOSS-ARCHIVIST-95', archivist, BOSS_DIR)
export_asset('enm_boss_furnace_warden_90_top3d_v001.glb', 'ENM-BOSS-FURNACE-WARDEN-90', furnace, BOSS_DIR)
export_asset('enm_boss_hollow_choir_85_top3d_v001.glb', 'ENM-BOSS-HOLLOW-CHOIR-85', choir, BOSS_DIR)
export_asset('env_boss_arena_archive_95_top3d_v001.glb', 'ENV-BOSS-ARENA-ARCHIVE-95', archive_arena, ARENA_DIR)
export_asset('env_boss_arena_furnace_90_top3d_v001.glb', 'ENV-BOSS-ARENA-FURNACE-90', furnace_arena, ARENA_DIR)
export_asset('env_boss_arena_choir_85_top3d_v001.glb', 'ENV-BOSS-ARENA-CHOIR-85', choir_arena, ARENA_DIR)
