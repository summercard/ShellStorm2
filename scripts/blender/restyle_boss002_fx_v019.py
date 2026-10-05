import bpy,math,json,hashlib
from pathlib import Path
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v019';P.mkdir(exist_ok=True)
def snapshot():
 return hashlib.sha256(repr([(a.name,[(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]) for a in bpy.data.actions if a.name in ['idle','move','melee_keyboard','heavy_spin_slam']]).encode()).hexdigest()
def material(name,col):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();e=n.new('ShaderNodeEmission');e.inputs[0].default_value=col;e.inputs[1].default_value=.8;o=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(e.outputs[0],o.inputs[0]);return m
for kind in ['model','animation']:
 bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v018.blend'));before=snapshot()
 for s in bpy.data.scenes:s['asset_version']='v019'
 if kind=='animation':
  fx=bpy.data.collections['BOSS002_IMPACT_PREVIEW'];red=material('FX_Flat_Red',(.9,0,0,1));blue=material('FX_Flat_Blue',(0,.012,.95,1));ink=material('FX_Clean_Outline',(.003,.005,.012,1))
  for j,ob in enumerate(sorted(fx.objects,key=lambda o:o.name)):
   verts=[];faces=[];ids=[]
   def poly(points,idx,z=0):
    start=len(verts);verts.extend([(x,y,z) for x,y in points]);faces.append(tuple(range(start,len(verts))));ids.append(idx)
   def band(r0,r1,idx,z=0):
    start=len(verts)
    for k in range(128):
     a=k*math.tau/128
     for r in [r0,r1]:verts.append((r*math.cos(a),r*math.sin(a),z))
    for k in range(128):faces.append((start+2*k,start+2*k+1,start+(2*k+3)%256,start+(2*k+2)%256));ids.append(idx)
   if ob.get('vfx_role')=='rotation_only':
    # Replace translucent ribbons with opaque flat fill and two precise edge bands.
    old=list(ob.data.vertices)
    for k in range(len(old)//2):
     a=old[2*k].co.copy();b=old[2*k+1].co.copy();mid=(a+b)*.5;d=(b-a).normalized();w=(b-a).length*.5
     for off in [-w-.012,-w,w,w+.012]:verts.append(tuple(mid+d*off))
    for k in range(len(old)//2-1):
     for q in range(3):faces.append((4*k+q,4*k+q+1,4*(k+1)+q+1,4*(k+1)+q));ids.append(0 if q==1 else 1)
   elif 'ring' in ob.name:
    band(.40,.49,1);band(.413,.477,0,.002)
   else:
    if 'impact' in ob.name:
     # Designed eight-point silhouette, no scratches, hatching, or tiny ink flecks.
     pts=[]
     for k in range(16):
      a=k*math.tau/16+.16*(j%3);r=(.49 if k%4==0 else .39) if k%2==0 else .19
      pts.append((math.cos(a)*r,math.sin(a)*r))
    else:
     pts=[(-.43,-.04),(-.08,-.09),(.12,-.27),(.09,-.06),(.46,.06),(.09,.10),(-.10,.29),(-.07,.06)]
    poly([(x*1.09,y*1.09) for x,y in pts],1);poly(pts,0,.003)
   mesh=bpy.data.meshes.new(ob.name+'_clean_flat');mesh.from_pydata(verts,[],faces);mesh.materials.append(red if j%2 else blue);mesh.materials.append(ink)
   for p,idx in zip(mesh.polygons,ids):p.material_index=idx
   ob.data=mesh;ob['vfx_style']='solid color blocks with clean outline; no texture';ob.visible_shadow=False
  fx['style']='clean flat red/blue color shapes with dark outlines; no sketch marks';fx['palette']='saturated red and blue'
 assert snapshot()==before
 bpy.ops.wm.save_as_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v019.blend'))
(P/'style_audit.json').write_text(json.dumps({'character_actions_unchanged':True,'style':'opaque solid red/blue blocks with clean dark outline','texture_nodes_used_by_fx':0,'timing':'inherited v018'},indent=2))
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;s.cycles.samples=8;s.render.resolution_x=960;s.render.resolution_y=800
for f in [29,69]:s.frame_set(f);s.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
