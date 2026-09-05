"""Regrade the V017 northwest stair; preserve the landing and loft interfaces."""
import bpy
import bmesh
import hashlib
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend'
REPORT = ROOT / 'outputs/verification/base99_stair_repair'


def signature(objects):
    data = []
    for o in sorted(objects, key=lambda o: o.name):
        data.append((o.name, o.type, o.parent.name if o.parent else '', list(map(list, o.matrix_world)),
                     [(tuple(v.co)) for v in o.data.vertices] if o.type == 'MESH' else None,
                     [(tuple(p.vertices), p.material_index) for p in o.data.polygons] if o.type == 'MESH' else None,
                     [m.name if m else '' for m in o.data.materials] if o.type == 'MESH' else None))
    return hashlib.sha256(repr(data).encode()).hexdigest()


def bounds(o):
    p = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return Vector([min(v[i] for v in p) for i in range(3)]), Vector([max(v[i] for v in p) for i in range(3)])


def remap(point):
    p = point.copy()
    # Lengthen both runs, keep the corner and loft exit fixed.
    if p.y < 12.8:
        p.y = 12.8 + (p.y - 12.8) * 5.8 / 4.56
    if p.x > -12.8:
        if p.x <= -8.24:
            p.x = -12.8 + (p.x + 12.8) * 5.8 / 4.56
        else:
            p.x = -7.0 + (p.x + 8.24) * 2.2 / 3.44
    return p


def mesh_object(name, vertices, faces, coll, template=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    if template:
        obj.data.materials.append(template.data.materials[0])
        uv = mesh.uv_layers.new(name='PaletteUV')
        src = template.data.uv_layers.active
        center = sum((v.uv for v in src.data), Vector((0, 0))) / len(src.data)
        cell = Vector(((int(center.x * 10) + .5) / 10, (int(center.y * 10) + .5) / 10))
        for p in mesh.polygons:
            for i, li in enumerate(p.loop_indices):
                angle = 2 * math.pi * i / len(p.loop_indices)
                uv.data[li].uv = cell + Vector((math.cos(angle), math.sin(angle))) * .022
        uv.active_render = True
    return obj


FACES = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]


def slab(name, start, end, width, thickness, coll):
    a,b = Vector(start),Vector(end)
    side = Vector((-(b-a).y, (b-a).x, 0)).normalized()*width/2
    top = [a-side,b-side,b+side,a+side]
    points = [p-Vector((0,0,thickness)) for p in top]+top
    obj = mesh_object(name, points, FACES, coll)
    obj.hide_render = True
    obj.hide_set(True)
    obj['collision_shape'] = 'convex_source_vertices'
    return obj


def merge_walk_surfaces():
    for ramp_name,landing_name in [('COLLISION_西北L梯_下段连续斜坡','COLLISION_西北L梯_转角平台'),('COLLISION_西北L梯_上段连续斜坡','COLLISION_西北L梯_顶层平台')]:
        ramp=bpy.data.objects.get(ramp_name);landing=bpy.data.objects.get(landing_name)
        if not ramp or not landing:continue
        bm=bmesh.new()
        for o in [ramp,landing]:
            for v in o.data.vertices:bm.verts.new(o.matrix_world@v.co)
        bmesh.ops.convex_hull(bm,input=list(bm.verts))
        bm.to_mesh(ramp.data);bm.free()
        bpy.data.objects.remove(landing,do_unlink=True)
        ramp['collision_interface']='continuous slope and landing hull, no internal edge'


def sync_source_manifest():
    coll=next(c for c in bpy.data.collections if c.get('资产包键')=='northwest_l_stair')
    path=ROOT/'source/art/blender/base_facility_layout/component_packages_v017/architecture/northwest_l_stair/asset_manifest.json'
    data=json.loads(path.read_text())
    objects=list(coll.all_objects)
    ps=[o.matrix_world@Vector(v) for o in objects if o.type=='MESH' and not o.name.startswith('COLLISION_') for v in o.bound_box]
    lo=[min(p[i] for p in ps) for i in range(3)];hi=[max(p[i] for p in ps) for i in range(3)]
    data.update(object_count=len(objects),mesh_count=sum(o.type=='MESH' for o in objects),
                object_names=sorted(o.name for o in objects),collider_names=sorted(o.name for o in objects if o.name.startswith('COLLISION_')),
                world_center_m=[round((a+b)/2,4) for a,b in zip(lo,hi)],bounding_size_m=[round(b-a,4) for a,b in zip(lo,hi)],
                expected_export='northwest_l_stair_visual_top3d_v002.glb',export_status='optimized_and_imported_v021',
                collision_status='two continuous convex ramp/landing hulls and six separate rail hulls',
                slope_degrees=27.699473,treads_per_flight=16,runtime_version='v021',revision='gentle_28deg_r2')
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def main():
    assert Path(bpy.data.filepath).resolve() == SOURCE.resolve()
    coll = next(c for c in bpy.data.collections if c.get('资产包键') == 'northwest_l_stair')
    if coll.get('walkable_revision') == 'gentle_28deg_r2':
        sync_source_manifest()
        print('Already repaired'); return
    REPORT.mkdir(parents=True, exist_ok=True)
    backup = REPORT / 'base_facility_runtime_layout_hq_v017_before_stair_repair.blend'
    if not backup.exists(): shutil.copy2(SOURCE, backup)
    objects = list(coll.all_objects)
    locked = [o for o in bpy.data.objects if o not in objects]
    before = signature(locked)
    # Use existing authored tread, trim and lamp meshes/UV as templates.
    templates = {}
    for token in ['踏步_', '导光_', '银色防滑边_', '橙色踏步灯_']:
        templates[token] = next(o for o in objects if token in o.name and ('第一跑' in o.name))
    template_copies = {k:(o.data.copy(), bounds(o), o.matrix_world.copy(), list(o.data.materials)) for k,o in templates.items()}
    remove = [o for o in objects if o.name.startswith('COLLISION_') or any(t in o.name for t in templates)]
    for o in objects:
        if o in remove or o.type != 'MESH': continue
        world = o.matrix_world.copy()
        o.data = o.data.copy()
        # Bake only horizontal layout changes; preserve all vertical dimensions.
        for v in o.data.vertices: v.co = remap(world @ v.co)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for o in remove: bpy.data.objects.remove(o, do_unlink=True)
    rise = 3.045 / 16
    run = 5.8 / 16
    for flight in range(2):
        for i in range(16):
            for token,(mesh,(lo,hi),world,mats) in template_copies.items():
                obj = bpy.data.objects.new('L梯V017缓坡_%d_%s%02d' % (flight+1,token,i+1), mesh.copy())
                coll.objects.link(obj)
                center = (lo+hi)/2
                # Treads become 19cm risers; small attached trims keep their section.
                for v in obj.data.vertices:
                    p = world @ v.co
                    if token == '踏步_':
                        p.y = 7.0 + i*run + (p.y-lo.y)/(hi.y-lo.y)*run
                        p.z = i*rise + (p.z-lo.z)/(hi.z-lo.z)*rise
                    else:
                        p.y = 7.0 + i*run + (p.y-8.24)
                        p.z = (i+1)*rise + (p.z-.3045)
                    if flight:
                        p = Vector((-12.8+(p.y-7.0),13.8-(p.x+13.8),p.z+3.045))
                    v.co=p
    # True continuous walking surfaces, no upright entry lips or platform gaps.
    slab('COLLISION_西北L梯_下段连续斜坡',(-13.8,6.94,-.032),(-13.8,12.8,3.045),1.64,.12,coll)
    slab('COLLISION_西北L梯_上段连续斜坡',(-12.8,13.8,3.045),(-7.0,13.8,6.09),1.64,.12,coll)
    slab('COLLISION_西北L梯_转角平台',(-13.8,12.8,3.045),(-13.8,14.8,3.045),2.0,.24,coll)
    slab('COLLISION_西北L梯_顶层平台',(-7.0,13.8,6.09),(-4.75,13.8,6.09),1.88,.16,coll)
    for x in [-14.63,-12.93]:
        slab('COLLISION_西北L梯_下段护栏_%s'%x,(x,7,1.05),(x,12.8,4.095),.08,1.0,coll)
    for y in [12.93,14.63]:
        slab('COLLISION_西北L梯_上段护栏_%s'%y,(-12.8,y,4.095),(-7.0,y,7.14),.08,1.0,coll)
        slab('COLLISION_西北L梯_平台护栏_%s'%y,(-7.0,y,7.14),(-4.85,y,7.14),.08,1.0,coll)
    merge_walk_surfaces()
    coll['walkable_revision']='gentle_28deg_r2'
    coll['slope_degrees']=math.degrees(math.atan(3.045/5.8))
    coll['treads_per_flight']=16
    bpy.context.view_layer.update()
    after=signature(locked)
    assert before==after,'Out-of-scope geometry changed'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    sync_source_manifest()
    (REPORT/'source_repair.json').write_text(json.dumps(dict(source=str(SOURCE),backup=str(backup),locked_before=before,locked_after=after,locked_match=before==after,slope_degrees=coll['slope_degrees'],run_m=5.8,rise_per_step_m=rise,treads_per_flight=16),indent=2))
    print('V017_STAIR_REPAIRED',coll['slope_degrees'])

if __name__=='__main__': main()
