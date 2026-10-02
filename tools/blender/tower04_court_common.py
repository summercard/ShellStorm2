"""Palette-preserving component authoring helpers for the Tower 04 courtyard."""
import ast,bpy,json,math,random
from pathlib import Path
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
R=Path(__file__).resolve().parents[2]
CREAM=(9,9);LIGHT=(9,8);TILE=(9,7);TILE2=(9,6);STEEL=(9,3);DARK=(9,1);RUST=(6,2)
NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
MATS=[]
for file,names in [('build_skyline_08_source_v001.py',{'coll','uv_mesh','Part'})]:
 p=R/'tools/blender'/file
 nodes=[n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
 exec(compile(ast.Module(body=nodes,type_ignores=[]),str(p),'exec'),globals())
BasePart=Part
p=R/'tools/blender/build_tower04_mall_source.py'
n=next(n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,ast.ClassDef) and n.name=='Part')
prism=next(x for x in n.body if isinstance(x,ast.FunctionDef) and x.name=='prism')
exec(compile(ast.Module(body=[prism],type_ignores=[]),str(p),'exec'),globals())
Part.prism=prism

def setup_materials():
 global MATS
 MATS=[bpy.data.materials[n] for n in NAMES if n in bpy.data.materials]
 for m in MATS:
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE' and n.image:n.image.filepath=str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png')

def mesh_of(p):
 mn=[min(v[j] for v in p.v) for j in range(3)];mx=[max(v[j] for v in p.v) for j in range(3)]
 origin=Vector(((mn[0]+mx[0])/2,(mn[1]+mx[1])/2,mn[2]))
 m=bpy.data.meshes.new(p.name+'_网格');m.from_pydata([tuple(Vector(v)-origin) for v in p.v],[],p.f);m.update()
 uv_mesh(m,p.co,p.mi,MATS[:3]);return m,origin,[mx[j]-mn[j] for j in range(3)]

def camera(sc,name,pos,target,scale,collection):
 d=bpy.data.cameras.new(name);d.type='ORTHO';d.ortho_scale=scale;d.clip_end=1000
 o=bpy.data.objects.new(name,d);collection.objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o

def render(sc,cam,path,res=(1440,1000),samples=32):
 sc.camera=cam;sc.render.engine='CYCLES';sc.cycles.samples=samples;sc.cycles.use_denoising=True
 try:
  prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
  for d in prefs.devices:d.use=d.type!='CPU'
  sc.cycles.device='GPU'
 except Exception:sc.cycles.device='CPU'
 sc.render.resolution_x,sc.render.resolution_y=res;sc.render.resolution_percentage=100
 sc.render.image_settings.file_format='PNG';sc.render.filepath=str(path)
 bpy.ops.render.render(write_still=True,scene=sc.name)

def foliage(p,pos,radius,height,seed,low=False):
 rng=random.Random(seed);x,y,z=pos
 # Branch-supported layered broadleaf canopy; near leaves have folded silhouettes.
 n=14 if low else 90
 for i in range(n):
  a=rng.random()*math.tau;r=radius*math.sqrt(rng.random());zz=z+height*(.2+.8*rng.random())
  xx=x+r*math.cos(a);yy=y+r*math.sin(a);s=rng.uniform(.22,.55)*(1.2 if low else 1)
  c=rng.choice([(3,4),(4,4),(5,4),(6,4)])
  p.poly([(xx-s,yy,zz),(xx,yy-s*.65,zz+.09),(xx+s,yy,zz),(xx,yy+s*.65,zz-.03),(xx,yy,zz+.16)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],c,1)

def tree(p,variant=0,low=False):
 rng=random.Random(140+variant);h=[6.8,8.2,5.5][variant];radius=[2.7,2.8,2.2][variant]
 p.rod((0,0,0),(.18,-.12,h*.75),.22,(4,2),1,7 if low else 12)
 for i in range(5):
  a=i*math.tau/5+variant;end=(math.cos(a)*radius*.65,math.sin(a)*radius*.65,h*.72+rng.uniform(-.3,.8))
  p.rod((.08,-.04,h*.40),end,.10,(5,2),1,5 if low else 8)
  foliage(p,(end[0],end[1],end[2]-.5),radius*.54,1.65,1400+variant*20+i,low)
 foliage(p,(0,0,h*.73),radius*.62,1.8,180+variant,low)
 if not low:
  for i in range(5):
   a=i*math.tau/5;p.rod((0,0,.28),(.65*math.cos(a),.65*math.sin(a),.04),.10,(4,2),1,6)

def tri_count(objects):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects if o.type=='MESH')
