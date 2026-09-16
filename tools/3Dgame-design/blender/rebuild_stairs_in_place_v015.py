"""Recover the v013 placement and split surfaces into fixed, unscaled modules."""
import json
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / 'source/art/whitebox/tower_zones/stairs/v015'
SCENE_ID = 'whitebox_tower_stairs_v015'
source = ROOT / 'source/art/whitebox/tower_zones/stairs/v013/blender/whitebox_tower_stairs_v013.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
bpy.context.view_layer.update()
base = bpy.data.objects['Stair_Generic_Rotatable_ROOT']
inverse = base.matrix_world.inverted()
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name.startswith('Stair_Generic_Rotatable')]

def points(o): return [inverse @ o.matrix_world @ v.co for v in o.data.vertices]
def bounds(ps): return [[min(v[i] for v in ps) for i in range(3)], [max(v[i] for v in ps) for i in range(3)]]
def vector(v): return dict(zip('xyz', [round(float(x), 7) for x in v]))
def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

first = next(o for o in objects if o.name.endswith('UpperFlight_Tread_01'))
lo, hi = bounds(points(first))
pivot = Vector(((lo[0]+hi[0])/2, (lo[1]+hi[1])/2-.5, 0))
profile = {'version': 1, 'source': str(source.relative_to(ROOT)), 'origin': 'upper_endpoint', 'runLength':15, 'riseHeight':6, 'parts':[]}
for obj in objects:
    if 'UpperFlight' not in obj.name: continue
    ps = [v-pivot for v in points(obj)]
    role = 'tread' if 'Tread_' in obj.name else ('guard' if 'Guard_' in obj.name else 'slope')
    if role == 'tread' and not obj.name.endswith('Tread_01'): continue
    profile['parts'].append({'name':obj.name.split('UpperFlight_')[-1], 'role':role, 'vertices':[[float(x) for x in p] for p in ps], 'faces':[list(f.vertices) for f in obj.data.polygons]})
save(ROOT / 'tools/3Dgame-design/src/stair-flight-profile.json', profile)

components = []
checks = []
unit = dict(x=1,y=1,z=1)
def record(name, type_, group, position, settings, asset_id, rotation=0):
    item={'name':name,'type':type_,'group':group,'position':vector(position),'rotation':dict(x=0,y=0,z=rotation),'scale':unit.copy(),'assetId':asset_id}
    item['stairwellSettings' if type_=='楼梯间楼梯' else 'surfaceSettings']=settings
    components.append(item)
    return item
def intervals(lo, hi, step):
    if hi-lo < 1e-5: return []
    count=math.ceil((hi-lo-1e-5)/step)
    return [(lo+i*step, min(hi,lo+(i+1)*step)) for i in range(count)]

groups=[]
labels={'LowerDoorLanding':'下层地板','UpperDoorLanding':'上层楼板','TurnLanding':'中层楼板','CoreConnector':'门口连接板','EnclosureWall':'围墙'}
for code,prefix in [('A','Stair_Special_Rooftop'),('B','Stair_Generic_Rotatable')]:
    root=bpy.data.objects[prefix+'_ROOT']
    for category in ['楼板','墙壁','楼梯']:
        groups.append({'name':f'楼梯间{code}/{category}','position':vector(root.location),'rotation':vector([math.degrees(v) for v in root.rotation_euler]),'scale':unit.copy()})
    scoped_objects = [o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(prefix)]
    for obj in scoped_objects:
        if 'Flight' in obj.name: continue
        ps=[root.matrix_world.inverted() @ obj.matrix_world @ v.co for v in obj.data.vertices]; low,high=bounds(ps); span=[high[i]-low[i] for i in range(3)]
        wall='EnclosureWall' in obj.name or 'Guard' in obj.name
        axis=0 if span[0]>=span[1] else 1
        # Standard 5m modules. The final edge cell is a fixed cut piece.
        grid=[5,5,max(span[2],.001)]
        if wall: grid=[5,.3,12.9] if axis==0 else [.3,5,12.9]
        pieces=[]
        for ix,(x0,x1) in enumerate(intervals(low[0],high[0],grid[0])):
            for iy,(y0,y1) in enumerate(intervals(low[1],high[1],grid[1])):
                for iz,(z0,z1) in enumerate(intervals(low[2],high[2],grid[2])):
                    dx,dy,dz=x1-x0,y1-y0,z1-z0
                    part=(obj.name.replace(prefix+'_',''))
                    name=f'{code}_{part}_{ix+1:02d}_{iy+1:02d}_{iz+1:02d}'
                    if wall:
                        settings={'kind':'wall','width':dx if axis==0 else dy,'thickness':dy if axis==0 else dx,'height':dz,'fixedModule':True,'sourceObject':obj.name,'edgeCut':True,'nominalSize':[5,.3,12.9]}
                        asset='ENV-TOWER-WALL-SOLID-5M'
                    else:
                        settings={'kind':'floor','length':dx,'width':dy,'thickness':dz,'fixedModule':True,'sourceObject':obj.name,'edgeCut':abs(dx-5)>.0001 or abs(dy-5)>.0001,'nominalSize':[5,5,.3]}
                        asset='ENV-TOWER-FLOOR-TILE-5M'
                    item=record(name,'墙壁' if wall else '地板',f'楼梯间{code}/'+('墙壁' if wall else '楼板'),((x0+x1)/2,(y0+y1)/2,z0),settings,asset,90 if wall and axis==1 else 0)
                    pieces.append({'name':name,'bounds':[[x0,y0,z0],[x1,y1,z1]]})
        checks.append({'source':obj.name.replace('Stair_Generic_Rotatable',prefix),'root':vector(root.location),'rotationZ':math.degrees(root.rotation_euler.z),'localBounds':[low,high],'pieces':pieces})
    settings={'profile':'original-v013','runLength':15,'slopeDeg':math.degrees(math.atan2(6,15)),'width':6,'stepCount':20,'handrailHeight':1.2}
    record(f'{code}_上跑','楼梯间楼梯',f'楼梯间{code}/楼梯',pivot,settings.copy(),'ENV-TOWER-STAIR-FLIGHT-ADJUSTABLE')
    lower_settings=settings.copy()
    lower_settings['omitParts']=[p['name'] for p in profile['parts'] if p['role']=='guard' and not any(o.name.endswith('LowerFlight_'+p['name']) for o in scoped_objects)]
    record(f'{code}_下跑','楼梯间楼梯',f'楼梯间{code}/楼梯',pivot+Vector((-8,15,-6)),lower_settings,'ENV-TOWER-STAIR-FLIGHT-ADJUSTABLE',180)

payload={'version':3,'id':SCENE_ID,'name':'楼梯间·原位组件拼装 v015','coordinateSystem':'blender-z-up','axes':{'right':'X','forward':'-Y','up':'Z'},'units':{'distance':'m','rotation':'deg'},'groups':groups,'components':components,'editorSettings':{'snapping':False,'grounding':False,'collision':False},'project':{'blockId':'stairs','blockName':'楼梯区','blockNodePath':'Blocks/Stairs','floorRange':'100→99、99→98'},'camera':{'position':{'x':80,'y':90,'z':70},'target':{'x':0,'y':0,'z':-9},'fov':48},'savedAt':'2026-09-14T12:00:00Z','blenderFile':SCENE_ID+'.blend'}
save(DEST/'data'/f'{SCENE_ID}.json',payload)
save(DEST/'data'/'original_surface_comparison.json',checks)
save(DEST/'data'/'stair_flight_profile_v001.json',profile)
print(json.dumps({'components':len(components),'groups':len(groups),'pivot':list(pivot)},ensure_ascii=False))
