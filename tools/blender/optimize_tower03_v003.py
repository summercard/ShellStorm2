"""塔3 v003 独立候选：仅 Blender 优化、严格 UV 检查与追溯，不改运行资产。"""
from __future__ import annotations
import bpy
import bmesh
import hashlib
import json
import math
from pathlib import Path
from collections import Counter
from mathutils import Vector

ROOT = Path('I:/工作项目/shellstrom2/ShellStorm2')
BASE = ROOT / 'assets/art/environments/open_world'
SOURCE = BASE / 'source/tower_03/export/v001/env_tower_03-v001-runtime.blend'
ORIGINAL = BASE / 'source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
OUT_DIR = BASE / 'source/tower_03/export/v003'
OUT_BLEND = OUT_DIR / 'env_tower_03-v003-runtime_optimized.blend'
QA_DIR = OUT_DIR / 'qa'
PALETTE = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
EXPECTED_HASHES = {SOURCE: 'a5eb1a4429fdb9ccbbf1de3a6ae11a4f2b1edcac3deb02878f455ecf99b3f744', ORIGINAL: '91b2f8f7d7ccfd483e76799e4b0a7573492b1741021eb3f7b34e5bfc24ec631e'}
UV_MARGIN = 0.01
UV_MIN_AREA = 1e-10
BOUND_EPS = 1e-6
END_BAND = 0.001


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def local_bounds(objects):
    points = [obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
    return [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]]


def add_anchor(bounds, anchor):
    return [[bounds[s][i] + anchor[i] for i in range(3)] for s in range(2)]


def geometry_signature(obj):
    mesh = obj.data
    payload = ([tuple(v.co) for v in mesh.vertices], [tuple(p.vertices) for p in mesh.polygons], [p.material_index for p in mesh.polygons], [tuple(row) for row in obj.matrix_world])
    return hashlib.sha256(repr(payload).encode()).hexdigest()


def uv_area(coords):
    return abs(sum(a[0]*coords[(i+1) % len(coords)][1] - coords[(i+1) % len(coords)][0]*a[1] for i,a in enumerate(coords))) * .5


def uv_cell(uv):
    return (min(9,max(0,int(math.floor(uv[0]*10)))), min(9,max(0,int(math.floor(uv[1]*10)))))


def uv_status(coords):
    if not coords or not all(math.isfinite(v) for uv in coords for v in uv):
        return 'invalid'
    cells = {uv_cell(uv) for uv in coords}
    if len(cells) != 1:
        return 'crosses_cells'
    x,y = next(iter(cells))
    if not all(x*.1+UV_MARGIN <= uv[0] <= (x+1)*.1-UV_MARGIN and y*.1+UV_MARGIN <= uv[1] <= (y+1)*.1-UV_MARGIN for uv in coords):
        return 'unsafe_margin'
    if uv_area(coords) <= UV_MIN_AREA:
        return 'zero_uv_area'
    return 'ok'


def audit_uv(objects):
    summary = Counter()
    details = []
    for obj in objects:
        mesh = obj.data
        layer = mesh.uv_layers.get('PaletteUV')
        errors = Counter()
        for p in mesh.polygons:
            summary['faces'] += 1
            status = uv_status([tuple(layer.data[i].uv) for i in p.loop_indices]) if layer else 'missing_layer'
            summary[status] += 1
            if status != 'ok': errors[status] += 1
        active = bool(layer and mesh.uv_layers.active == layer and layer.active_render)
        extra = [l.name for l in mesh.uv_layers if l.name != 'PaletteUV']
        if not active: summary['inactive_layer_objects'] += 1
        if extra: summary['extra_layer_objects'] += 1
        if errors or not active or extra: details.append({'object':obj.name, 'errors':dict(errors), 'active_palette':active, 'extra_uv_layers':extra})
    summary['failed_faces'] = summary['faces'] - summary['ok']
    return {'counts':dict(summary), 'failures':details, 'passed': summary['failed_faces']==0 and not summary['inactive_layer_objects'] and not summary['extra_layer_objects']}


def palette_data():
    image = bpy.data.images.load(str(PALETTE), check_existing=True)
    assert tuple(image.size) == (512,512)
    pixels = list(image.pixels)
    def sample(uv):
        # 原素材采用 REPEAT；颜色最近格比较在实际像素线性空间执行。
        u,v = float(uv[0]) % 1.0, float(uv[1]) % 1.0
        ix,iy = min(511,int(u*512)), min(511,int(v*512))
        start = 4*(iy*512+ix)
        return tuple(pixels[start:start+3])
    colors = {(x,y):sample(((x+.5)/10,(y+.5)/10)) for x in range(10) for y in range(10)}
    return image, sample, colors


def repair_uv(objects, sample, colors):
    changes = []
    for obj in objects:
        mesh = obj.data
        layer = mesh.uv_layers.get('PaletteUV')
        if layer is None:
            raise RuntimeError('原素材缺失 PaletteUV，不能猜色: '+obj.name)
        for p in mesh.polygons:
            old = [tuple(layer.data[i].uv) for i in p.loop_indices]
            reason = uv_status(old)
            if reason == 'ok': continue
            if reason == 'invalid': raise RuntimeError('无效 UV 无法取原色: '+obj.name)
            center = tuple(sum(uv[a] for uv in old)/len(old) for a in range(2))
            # 按面重心实际采样颜色选最近格；相同颜色优先原格，避免无意义改色。
            target_color = sample(center)
            original_cell = uv_cell(center)
            cell = min(colors, key=lambda c:(sum((colors[c][a]-target_color[a])**2 for a in range(3)), c!=original_cell, c))
            color_distance = math.sqrt(sum((colors[cell][a]-target_color[a])**2 for a in range(3)))
            x,y = cell
            radius = .022
            for j,i in enumerate(p.loop_indices):
                angle = 2*math.pi*j/len(old)
                layer.data[i].uv = ((x+.5)/10+radius*math.cos(angle), (y+.5)/10+radius*math.sin(angle))
            changes.append({'object':obj.name,'face':p.index,'reason':reason,'old_uv':old,'target_cell':cell,'sample_color':target_color,'color_distance_linear':color_distance})
        mesh.uv_layers.active = layer
        layer.active_render = True
        for other in list(mesh.uv_layers):
            if other != layer: mesh.uv_layers.remove(other)
        mesh.update()
    return changes


def audit_materials(objects):
    used = set(m for o in objects for m in o.data.materials if m)
    results = []
    for m in sorted(used, key=lambda m:m.name):
        nodes = list(m.node_tree.nodes) if m.use_nodes else []
        textures = [n for n in nodes if n.type=='TEX_IMAGE']
        uvnodes = [n for n in nodes if n.type=='UVMAP']
        ok = m.name in ('01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光') and bool(textures) and bool(uvnodes)
        for n in textures:
            ok = ok and bool(n.image) and Path(bpy.path.abspath(n.image.filepath)).resolve()==PALETTE.resolve() and not n.image.packed_file and n.interpolation=='Closest'
        ok = ok and all(n.uv_map=='PaletteUV' for n in uvnodes)
        results.append({'material':m.name,'passed':bool(ok),'images':[{'path':bpy.path.abspath(n.image.filepath),'packed':bool(n.image.packed_file),'interpolation':n.interpolation} for n in textures if n.image]})
    return {'passed':all(r['passed'] for r in results) and len(results)<=4, 'materials':results, 'unused_materials':[m.name for m in bpy.data.materials if m not in used]}


def clean_mesh(obj, locked):
    mesh = obj.data
    bm = bmesh.new(); bm.from_mesh(mesh)
    zero = [f for f in bm.faces if f.calc_area() <= 1e-14]
    isolated_edges = [e for e in bm.edges if not e.link_faces]
    isolated_vertices = [v for v in bm.verts if not v.link_faces]
    seen = set(); duplicate = []
    uv = bm.loops.layers.uv.get('PaletteUV')
    for face in bm.faces:
        key = (face.material_index, tuple(sorted((tuple(l.vert.co), tuple(l[uv].uv) if uv else ()) for l in face.loops)))
        if key in seen: duplicate.append(face)
        seen.add(key)
    result = {'zero_area_faces_found':len(zero), 'duplicate_faces_found':len(duplicate),'isolated_edges_found':len(isolated_edges),'isolated_vertices_found':len(isolated_vertices),'zero_area_faces_removed':0,'duplicate_faces_removed':0,'isolated_edges_removed':0,'isolated_vertices_removed':0,'merged_vertices':0,'hidden_faces_removed':0,'unproven_hidden_faces':'保留；没有可见性与阴影证据，不删背面或底面','merge_policy':'不跨 UV、材质或硬边焊接；无已证明安全的重合顶点对'}
    if locked:
        result['locked_cleaning_policy'] = '完整只读清理检查；为保留地板100%及主体入口原签名，不改变几何'
    else:
        remove = set(zero+duplicate)
        if remove: bmesh.ops.delete(bm, geom=list(remove), context='FACES_ONLY')
        loose_edges = [e for e in bm.edges if not e.link_faces]
        if loose_edges: bmesh.ops.delete(bm, geom=loose_edges, context='EDGES')
        loose_verts = [v for v in bm.verts if not v.link_faces]
        if loose_verts: bmesh.ops.delete(bm, geom=loose_verts, context='VERTS')
        result.update(zero_area_faces_removed=len(zero),duplicate_faces_removed=len(duplicate),isolated_edges_removed=len(loose_edges),isolated_vertices_removed=len(loose_verts))
        bm.to_mesh(mesh); mesh.update()
    bm.free()
    return result


def subset_mesh(mesh, indices):
    result = mesh.copy()
    bm = bmesh.new(); bm.from_mesh(result); bm.faces.ensure_lookup_table()
    remove = [f for f in bm.faces if f.index not in indices]
    if remove: bmesh.ops.delete(bm,geom=remove,context='FACES_ONLY')
    edges = [e for e in bm.edges if not e.link_faces]
    if edges: bmesh.ops.delete(bm,geom=edges,context='EDGES')
    vertices = [v for v in bm.verts if not v.link_faces]
    if vertices: bmesh.ops.delete(bm,geom=vertices,context='VERTS')
    bm.to_mesh(result); bm.free(); result.update()
    return result


def decimate(obj, ratio, minimum, facade):
    original = obj.data.copy()
    before = tri_count(obj)
    lo,hi = local_bounds([obj])
    # 保护几何原值：主宽度/高度 1mm 极值端带，以及六向极值点的完整邻接面。
    axes = [0, 1, 2]
    extreme_ids = {min(obj.data.vertices,key=lambda v:v.co[a]).index for a in range(3)} | {max(obj.data.vertices,key=lambda v:v.co[a]).index for a in range(3)}
    boundary_vertices = {v.index for v in obj.data.vertices if any(abs(v.co[a]-bound) <= END_BAND for a in axes for bound in (lo[a], hi[a]))}
    protected = {p.index for p in obj.data.polygons if set(p.vertices) & (extreme_ids | boundary_vertices)}
    interior = set(range(len(original.polygons))) - protected
    if not interior:
        bpy.data.meshes.remove(original)
        return {'requested_ratio':ratio,'applied_interior_ratio':None,'protected_faces':len(protected),'retention':1.0,'reason':'全部面处于极值保护端带，无安全简化空间'}
    keep = subset_mesh(original, protected)
    reduce_mesh = subset_mesh(original, interior)
    keep.calc_loop_triangles(); reduce_mesh.calc_loop_triangles()
    protected_tri = len(keep.loop_triangles)
    interior_tri = len(reduce_mesh.loop_triangles)
    target = math.ceil(before*ratio)
    interior_ratio = min(1.0,max(0.0,(target-protected_tri)/interior_tri))
    # 受保护面三角数可能大于目标，仍保留端带，不为预算删除它们。
    work = bpy.data.objects.new('临时内部减面',reduce_mesh)
    bpy.context.scene.collection.objects.link(work)
    def evaluate(r):
        work.data = reduce_mesh
        mod = work.modifiers.new('v003候选评估','DECIMATE'); mod.ratio=r; mod.use_collapse_triangulate=True
        deps = bpy.context.evaluated_depsgraph_get()
        evaluated = work.evaluated_get(deps)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True,depsgraph=deps)
        work.modifiers.remove(mod)
        mesh.calc_loop_triangles()
        return mesh, len(mesh.loop_triangles)+protected_tri
    chosen_mesh, count = evaluate(interior_ratio)
    if minimum is not None and count < math.ceil(before*minimum):
        bpy.data.meshes.remove(chosen_mesh)
        low,high = interior_ratio,1.0
        for _ in range(12):
            mid=(low+high)/2; test,count=evaluate(mid); bpy.data.meshes.remove(test)
            if count >= math.ceil(before*minimum): high=mid
            else: low=mid
        interior_ratio=high
        chosen_mesh,count=evaluate(high)
    # 接口端带网格逐顶点不变，与内部简化结果合并但不重新焊接。
    work.data=chosen_mesh
    obj.data=keep
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); work.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.object.join()
    after_bounds=local_bounds([obj])
    delta=max(abs(after_bounds[s][a]-[lo,hi][s][a]) for s in range(2) for a in range(3))
    if delta > BOUND_EPS:
        old = obj.data
        obj.data = original.copy()
        if old.users == 0: bpy.data.meshes.remove(old)
        if reduce_mesh.users == 0: bpy.data.meshes.remove(reduce_mesh)
        return {'requested_ratio':ratio,'applied_interior_ratio':None,'protected_faces':len(protected),'triangles_after':before,'retention':1.0,'bounds_delta_m':0.0,'protected_band_m':END_BAND,'fallback':'restore_original_mesh_because_extreme_envelope_would_drift','protection':'原端带保真优先；该对象未安全减面'}
    if minimum is not None: assert tri_count(obj)>=math.ceil(before*minimum),obj.name
    after=tri_count(obj)
    bpy.data.meshes.remove(original)
    if reduce_mesh.users==0: bpy.data.meshes.remove(reduce_mesh)
    return {'requested_ratio':ratio,'applied_interior_ratio':interior_ratio,'protected_faces':len(protected),'protected_triangles':protected_tri,'interior_triangles_before':interior_tri,'triangles_after':after,'retention':after/before,'bounds_delta_m':delta,'protected_band_m':END_BAND,'protection':'原端带完整邻接面保留，不缩放、不新增替代盒，不放宽包络'}


def main():
    assert Path(bpy.data.filepath).resolve()==SOURCE.resolve()
    assert not OUT_BLEND.exists(), '不覆盖已有 v003 候选'
    manifest=json.loads((SOURCE.parent/'export_manifest.json').read_text(encoding='utf-8'))
    assert len(manifest['records'])==217
    for p,h in EXPECTED_HASHES.items(): assert sha256(p)==h,(str(p),sha256(p))
    palette_hash=sha256(PALETTE)
    objects=[bpy.data.objects[n] for r in manifest['records'] for n in r['objects']]
    assert len(objects)==len(set(objects))
    before_total=sum(tri_count(o) for o in objects); assert before_total==212967
    original_meshes = {}
    original_triangles = {}
    for o in objects:
        assert not o.library and not o.data.library
        o.data=o.data.copy()
        original_meshes[o.name] = o.data.copy()
        original_triangles[o.name] = tri_count(o)
        assert not o.modifiers, o.name
        assert tuple(o.location)==(0,0,0) and tuple(o.scale)==(1,1,1),o.name
    source_uv=audit_uv(objects)
    image,sample,colors=palette_data()
    source_materials=audit_materials(objects)
    # 在候选内规范唯一外链路径，保留全部原材质参数。
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type=='TEX_IMAGE': n.image=image; n.interpolation='Closest'
                if n.type=='UVMAP': n.uv_map='PaletteUV'
    image.filepath=str(PALETTE)
    assert not image.packed_file
    repairs_before=repair_uv(objects,sample,colors)
    results={}; partitions={}
    for r in manifest['records']:
        slug=r['slug']; os=[bpy.data.objects[n] for n in r['objects']]
        before=sum(tri_count(o) for o in os); bounds_before=local_bounds(os)
        signatures_before={o.name:geometry_signature(o) for o in os}
        locked=r['category']=='floor' or slug in {'main_structure','entrance'}
        facade=slug.startswith('facade_')
        group='facade' if facade else r['category']
        params=[]; cleaning=[]
        for o in os:
            cleaning.append(clean_mesh(o,locked))
            if not locked: params.append(decimate(o, .18 if facade else .82, None if facade else .82, facade))
        # Decimate 的实际三角计数可能因拓扑折叠低于线性预估；保守设施不接受低于82%，回退到该对象独立副本。
        if not facade and not locked and any(tri_count(o) < math.ceil(original_triangles[o.name] * .82) for o in os):
            for o in os:
                old = o.data
                o.data = original_meshes[o.name].copy()
                if old.users == 0: bpy.data.meshes.remove(old)
            params.append({'fallback': 'restore_independent_pre_optimization_mesh_to_meet_82_percent_retention'})
        repairs_after=repair_uv(os,sample,colors)
        after=sum(tri_count(o) for o in os); bounds_after=local_bounds(os)
        signatures_after={o.name:geometry_signature(o) for o in os}
        delta=max(abs(bounds_before[s][a]-bounds_after[s][a]) for s in range(2) for a in range(3))
        assert delta<=BOUND_EPS,(slug,delta)
        if locked: assert signatures_before==signatures_after and before==after,slug
        if not facade and not locked:
            assert after>=math.ceil(before*.82), (slug, before, after, after/before, params)
        results[slug]={'asset_id':r['asset_id'],'category':r['category'],'group':group,'objects':r['objects'],'triangles_before':before,'triangles_after':after,'retention':after/before,'reduction_ratio':1-after/before,'locked':locked,'geometry_signatures_before':signatures_before,'geometry_signatures_after':signatures_after,'locked_match':signatures_before==signatures_after if locked else None,'bounds_local_before':bounds_before,'bounds_local_after':bounds_after,'anchor_blender':r['anchor_blender'],'bounds_world_blender_before':add_anchor(bounds_before,r['anchor_blender']),'bounds_world_blender_after':add_anchor(bounds_after,r['anchor_blender']),'bounds_max_delta_m':delta,'cleaning':cleaning,'decimate':params,'uv_repairs_after':repairs_after,'runtime_integrated':False}
        part=partitions.setdefault(group,{'components':0,'triangles_before':0,'triangles_after':0})
        part['components']+=1; part['triangles_before']+=before; part['triangles_after']+=after
        print('COMPONENT',slug,before,after,flush=True)
    output_uv=audit_uv(objects); materials=audit_materials(objects)
    assert output_uv['passed'],output_uv
    assert materials['passed'],materials
    after_total=sum(r['triangles_after'] for r in results.values())
    # 即使预算失败也保存独立候选及完整阻塞证据，但不允许导出/提升。
    OUT_DIR.mkdir(parents=True,exist_ok=True); QA_DIR.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND))
    for p,h in EXPECTED_HASHES.items(): assert sha256(p)==h,str(p)
    assert sha256(PALETTE)==palette_hash
    report={'asset_id':manifest['asset_id'],'version':'v003','role':'optimized_candidate','passed_geometry_uv_budget':after_total<100000 and output_uv['passed'] and materials['passed'],'visual_acceptance':'pending','passed':False,'blockers':[] if after_total<100000 else ['保守端带保护后面数超预算'],'source':SOURCE.relative_to(ROOT).as_posix(),'source_sha256_before':EXPECTED_HASHES[SOURCE],'source_sha256_after':sha256(SOURCE),'original_source':ORIGINAL.relative_to(ROOT).as_posix(),'original_source_sha256_before':EXPECTED_HASHES[ORIGINAL],'original_source_sha256_after':sha256(ORIGINAL),'palette_sha256_before':palette_hash,'palette_sha256_after':sha256(PALETTE),'optimized_blend':OUT_BLEND.relative_to(ROOT).as_posix(),'optimized_blend_sha256':sha256(OUT_BLEND),'records':217,'triangles_before':before_total,'triangles_after':after_total,'partitions':partitions,'parameters':{'floor_retention':1.0,'main_structure_entrance_retention':1.0,'conservative_rooftop_retention_min':.82,'facade_target_ratio':.18,'facade_allowed_alternative':.15,'bound_numeric_epsilon_m':BOUND_EPS,'protected_extreme_band_m':END_BAND,'uv_margin':UV_MARGIN,'uv_min_area':UV_MIN_AREA},'source_uv_audit':source_uv,'source_material_audit':source_materials,'source_uv_repairs_in_candidate':repairs_before,'output_uv_audit':output_uv,'output_material_audit':materials,'component_results':results,'runtime_integrated':False,'stable_paths_touched':False,'blender_version':bpy.app.version_string}
    (QA_DIR/'optimization_v003.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('SUMMARY',json.dumps({'triangles_before':before_total,'triangles_after':after_total,'partitions':partitions,'source_uv':source_uv['counts'],'output_uv':output_uv['counts'],'optimized_hash':report['optimized_blend_sha256'],'budget_passed':after_total<100000},ensure_ascii=False),flush=True)

if __name__=='__main__': main()
