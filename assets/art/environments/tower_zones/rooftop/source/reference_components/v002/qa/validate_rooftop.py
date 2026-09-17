import bpy,json,hashlib,math,sys
from pathlib import Path
from mathutils import Vector
O=Path(__file__).resolve().parents[1];R=Path('/Users/summercards/ShellStorm2')
catalog=json.loads((O/'component_packages_v002/catalog.json').read_text());errors=[];measured=[]
def check(ok,message):
    if not ok:errors.append(message)
groups=set();owned=set();sources=0
for p in catalog:
    c=bpy.data.collections.get(p['blender_collection']);root=bpy.data.objects.get(p['root_object'])
    check(c is not None and root is not None,p['slug']+' missing collection/root')
    if c is None or root is None:continue
    meshes=[o for o in c.objects if o.type=='MESH'];check(len(meshes)>0,p['slug']+' empty')
    check(set(o.name for o in meshes)==set(p['objects']),p['slug']+' membership')
    groups.add(p['category']);points=[]
    for o in meshes:
        check(len(o.users_collection)==1,o.name+' multi collection')
        check(o.name not in owned,o.name+' duplicate ownership');owned.add(o.name)
        check(o.parent==root,o.name+' parent')
        check(not o.hide_render,o.name+' shadow/render disabled')
        points.extend(o.matrix_local @ Vector(v) for v in o.bound_box)
    lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)];size=[hi[i]-lo[i] for i in range(3)]
    check(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,p['slug']+' origin')
    check(all(abs(a-b)<1e-5 for a,b in zip(size,p['bounds_size'])),p['slug']+' catalog bounds')
    if not p.get('vegetation_variant') and (p['slug'].startswith('facade') or p['slug'] in ('room_wall','room_window','room_doorwall')):
        check(all(abs(a-b)<1e-5 for a,b in zip(size,[5,.3,11.9])),p['slug']+' standard wall')
        check(p['collision_bounds']==[5,.3,12],p['slug']+' collision contract')
    if p['slug'].startswith(('floor','roof')):check(abs(size[2]-.3)<1e-5,p['slug']+' floor thickness')
    mf=O/'component_packages_v002'/p['category'][:2]/p['slug']/'asset_manifest.json'
    check(mf.is_file() and json.loads(mf.read_text())==p,p['slug']+' disk manifest')
    sc=bpy.data.collections.get(p['source_collection']);check(sc and len(sc.objects)>0,p['slug']+' editable source')
    if sc:sources+=len(sc.objects)
    if p.get('vegetation_variant') and p['slug'].startswith(('facade','room')):
        vs=[v.co for o in sc.objects if '叶片' not in o.name and '藤蔓茎' not in o.name for v in o.data.vertices]
        dims=[max(v[i] for v in vs)-min(v[i] for v in vs) for i in range(3)]
        check(all(abs(a-b)<1e-5 for a,b in zip(dims,[5,.3,11.9])),p['slug']+' structural envelope')
        check(p['collision_bounds']==[5,.3,12],p['slug']+' vegetation collision exclusion')
    if p['slug']=='door_lamp':
        for tag,depth in [('厚石材门柱',1.10),('厚门楣',1.16),('进深门槛',1.55)]:
            ob=next(o for o in sc.objects if tag in o.name)
            actual=max(v.co.y for v in ob.data.vertices)-min(v.co.y for v in ob.data.vertices)
            check(abs(actual-depth)<1e-5,'door '+tag+' depth')
    measured.append({'slug':p['slug'],'minimum':lo,'maximum':hi,'size':size})
check(len(catalog)==44,'expected 44 packages')
check(len(list((O/'component_packages_v002').glob('*/*/asset_manifest.json')))==44,'disk count')
check(len(bpy.data.materials)==4,'four materials')
check(not bpy.data.collections['02_游戏输出_独立资产包_v002'].hide_viewport,'outputs hidden')
check(not bpy.data.collections['02_游戏输出_独立资产包_v002'].hide_render,'outputs render hidden')
check(bpy.data.collections['01_制作组件_按设施拆分'].hide_viewport,'source visibility')
before=json.loads((O/'qa/scope_before.json').read_text());after={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in before}
check(before==after,'locked files changed')
check(not list(O.rglob('*色盘*.png')),'private palette')
palette=[i for i in bpy.data.images if i.source=='FILE'];check(len(palette)==1 and palette[0].packed_file is None,'single external palette')
assembly=json.loads((O/'reference_assembly.json').read_text())
tiles=[p for p in assembly['placements'] if p['slug']=='floor_full'];check(len(tiles)==100,'demo tiles')
check(len({tuple(p['position']) for p in tiles})==100,'overlap tiles')
check(all(abs(p['position'][2]+.3)<1e-8 for p in tiles),'floor finish datum')
walls=[p for p in assembly['placements'] if p['slug'].startswith('facade')]
check(len(walls)==40 and all(p['position'][2]==-12 for p in walls),'facade datum')
report={'passed':not errors,'errors':errors,'package_count':len(catalog),'category_count':len(groups),'source_meshes':sources,'output_meshes':len(owned),'disk_manifest_count':44,'empty_packages':0 if not errors else 'see errors','scope':'new library; prior sources excluded from scene; whole-file hashes stronger than individual geometry signatures','locked_match':before==after,'locked_before':before,'locked_after':after,'measured_bounds':measured,'assembly_floor_tiles':len(tiles),'assembly_facade_modules':len(walls),'runtime_imported':False,'GLB_PackedScene_collision_LOD':'not_requested_not_created','unexpected_script_errors':0,'expected_failures':[]}
(O/'qa/task_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['measured_bounds','locked_before','locked_after']},ensure_ascii=False,indent=2))
if errors:raise RuntimeError('; '.join(errors))
