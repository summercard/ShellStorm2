"""Centre each far tower package without changing its world-space geometry."""
import bpy,json,sys,hashlib,shutil
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];F=R/'assets/art/environments/open_world/source/tower_04/v010';cat=json.loads((F/'far_catalog.json').read_text(encoding='utf8'));p=R/cat['source_blend'];assert hashlib.sha256(p.read_bytes()).hexdigest()==cat['source_sha256']
backup=R.parent/'_scratch/tower04_v010/far_before_pivots.blend';assert not backup.exists();shutil.copy2(p,backup)
bpy.ops.wm.open_mainfile(filepath=str(p));sc=bpy.context.scene;rows=[]
for o in sc.objects:
 if o.type!='MESH' or not o.get('source_package'):continue
 before=[o.matrix_world@Vector(v) for v in o.bound_box]
 points=[v.co for v in o.data.vertices];lo=Vector([min(v[j] for v in points) for j in range(3)]);hi=Vector([max(v[j] for v in points) for j in range(3)]);offset=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 if o.data.users>1:o.data=o.data.copy()
 for v in o.data.vertices:v.co-=offset
 o.location+=o.matrix_world.to_3x3()@offset
 key=o['source_package'].split('/')[-1]+'_'+hashlib.sha1(o.name.encode()).hexdigest()[:8]
 o['package_id']='tower04_far/'+key;o['local_origin']='XY_center_Z_bottom'
 row=dict(package_id=o['package_id'],asset_id=cat['asset_id'],source_blend=cat['source_blend'],version='v010',lod='far',object=o.name,collection=[c.name for c in o.users_collection],source_package=o['source_package'],origin=list(o.location),dimensions=list(hi-lo),front_direction='-Y',bounds_min=[min(v[j] for v in before) for j in range(3)],bounds_max=[max(v[j] for v in before) for j in range(3)],triangles=sum(len(f.vertices)-2 for f in o.data.polygons),exported=False,collision_status='not_authored',block_id='open_world',asset_ledger='scenes::资产主表::'+cat['asset_id'])
 folder=F/'far_component_packages'/key;folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8');rows.append(row)
bpy.context.view_layer.update();bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p));cat['source_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();cat['packages']=rows;cat['tower_package_count']=len(rows);cat['local_pivots_centered']=True;(F/'far_catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf8');print('FAR_PACKAGES',len(rows),flush=True)
