import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
P=Path(__file__).parent;root=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/melee_chaser');D=json.loads((P/'uv_rig_source.json').read_text());UV=json.loads((P/'uv_stitched.json').read_text())
m=next(o for o in bpy.context.scene.objects if o.type=='MESH');a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');bpy.context.preferences.filepaths.save_version=0
# Body skeleton: explicit anatomical joints, preserve source joint positions where meaningful.
old={b['name']:b for b in D['bones']};spec={}
def bone(n,h,t,p=None):spec[n]={'head':list(h),'tail':list(t),'parent':p}
bone('Root',(0,0,0),(0,0,.12));bone('Hip',(-.012,.073,.43),(-.014,.071,.5),'Root');bone('Waist',(-.014,.071,.5),(-.018,.069,.64),'Hip');bone('Spine02',(-.018,.069,.64),(-.021,.067,.77),'Waist');bone('Neck',(-.021,.067,.77),(-.024,.065,.89),'Spine02');bone('Head',(-.024,.065,.89),(-.025,.065,1.56),'Neck')
finger_defs={ 'Thumb':[(.515,.09,.755),(.529,.136,.748),(.529,.175,.742)],'Index':[(.572,.071,.77),(.606,.08,.755),(.633,.088,.750)],'Middle':[(.575,.012,.774),(.61,.012,.764),(.638,.012,.756)],'Pinky':[(.559,-.044,.769),(.583,-.056,.758),(.604,-.065,.746)] }
for side,sign in [('L',-1),('R',1)]:
 def h(n):return old[side+'_'+n]['head']
 bone(side+'_Clavicle',h('Clavicle'),h('Upperarm'),'Spine02');bone(side+'_Upperarm',h('Upperarm'),h('Forearm'),side+'_Clavicle');bone(side+'_Forearm',h('Forearm'),h('Hand'),side+'_Upperarm');bone(side+'_Hand',h('Hand'),(sign*.574,.023,.768),side+'_Forearm')
 bone(side+'_Thigh',h('Thigh'),h('Calf'),'Hip');bone(side+'_Calf',h('Calf'),h('Foot'),side+'_Thigh');foot=h('Foot');bone(side+'_Foot',foot,(foot[0],.19,.07),side+'_Calf')
 for finger,pts in finger_defs.items():
  q=[(sign*x,y,z) for x,y,z in pts]
  for j in range(2):bone(side+'_'+finger+str(j+1),q[j],q[j+1],side+'_Hand' if j==0 else side+'_'+finger+'1')
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);bpy.context.view_layer.objects.active=a;bpy.ops.object.mode_set(mode='EDIT')
for b in list(a.data.edit_bones):a.data.edit_bones.remove(b)
for n,s in spec.items():
 b=a.data.edit_bones.new(n);b.head=s['head'];b.tail=s['tail'];b.use_deform=n!='Root'
 if s['parent']:b.parent=a.data.edit_bones[s['parent']]
 b.align_roll(Vector((0,1,0)))
bpy.ops.object.mode_set(mode='OBJECT')
for g in list(m.vertex_groups):m.vertex_groups.remove(g)
for n in spec:m.vertex_groups.new(name=n)
def project(v,n):
 s=spec[n];h=Vector(s['head']);t=Vector(s['tail']);return (v-h).dot(t-h)/(t-h).length_squared
mapping={'Spine01':'Waist','Waist':'Hip','NeckTwist01':'Neck','NeckTwist02':'Head'}
for i,v in enumerate(m.data.vertices):
 w={}
 for gi,wt in D['weights'][i]:
  n=D['groups'][gi];n=mapping.get(n,n)
  for seg in ['Upperarm','Forearm','Thigh','Calf']:
   if seg+'Twist' in n:n=n[:2]+seg
  if n.endswith('ToeBase'):n=n[:2]+'Foot'
  w[n]=w.get(n,0)+wt
 # Hand region is explicitly rebuilt, including source thumb vertices missed by L_Hand.
 x,y,z=v.co;ax=abs(x);side='R' if x>0 else 'L';point=Vector((ax,y,z))
 if ax>.495 and .70<z<.835 and -.09<y<.19:
  distances=[]
  for f,pts in finger_defs.items():
   h=Vector(pts[0]);t=Vector(pts[2]);p=max(0,min(1,(point-h).dot(t-h)/(t-h).length_squared));dist=(point-(h+(t-h)*p)).length;distances.append((dist,f,p))
  dist,f,p=min(distances);base=Vector(finger_defs[f][0]);end=Vector(finger_defs[f][2]);progress=(point-base).dot(end-base)/(end-base).length_squared
  strength=max(0,min(1,(progress+.12)/.40)) if dist<.045 else 0
  hand_blend=max(0,min(1,(ax-.50)/.055))
  if f=='Thumb' and y>.105:hand_blend=1
  body={side+'_Forearm':1-hand_blend,side+'_Hand':hand_blend}
  if strength>0:
   distal=max(0,min(1,(progress-.30)/.45));body={k:val*(1-strength) for k,val in body.items()};body[side+'_'+f+'1']=strength*(1-distal);body[side+'_'+f+'2']=strength*distal
  w=body
 w={k:val for k,val in w.items() if val>1e-5 and k in spec};total=sum(w.values());assert total>0
 for n,wt in w.items():m.vertex_groups[n].add([i],wt/total,'REPLACE')
# Model collections, descriptive metadata, unchanged identity IDs.
for c in list(bpy.data.collections):
 if c.name not in ['Collection']:continue
 c.name='01_部件'
rigc=bpy.data.collections.new('00_共享骨架');bpy.context.scene.collection.children.link(rigc)
for c in list(a.users_collection):c.objects.unlink(a)
rigc.objects.link(a);a.show_in_front=True;a.data.display_type='OCTAHEDRAL';a['skeleton_id']='SKEL-MELEE-FUNGBOAR01-002';a['display_name']='小僵尸';a['finger_design']='4 digits per hand, 2 deform segments each; original geometry preserved'
m['display_name']='小僵尸';m['source_height_m']=1.3/.7;m['runtime_display_multiplier']=.7;m['runtime_height_m']=1.3;m['uv_policy']='asymmetric_unique_2k'
u=m.data.uv_layers.active;u.name='UVMap'
for p in m.data.polygons:
 for j,li in enumerate(p.loop_indices):u.data[li].uv=UV['uv'][p.index][j]
# Explicit seams from current continuity (not angle auto cuts).
edges={}
for p in m.data.polygons:
 for j,li in enumerate(p.loop_indices):
  lj=p.loop_indices[(j+1)%len(p.loop_indices)];va=m.data.loops[li].vertex_index;vb=m.data.loops[lj].vertex_index;edges.setdefault(tuple(sorted((va,vb))),[]).append({va:tuple(u.data[li].uv),vb:tuple(u.data[lj].uv)})
for e in m.data.edges:
 rows=edges[tuple(sorted(e.vertices))];e.use_seam=len(rows)!=2 or any(abs(rows[0][v][k]-rows[1][v][k])>1e-6 for v in e.vertices for k in range(2))
# Packing performed outside Blender after native pack access violation; preserves islands.
packed=json.loads((P/'uv_packed.json').read_text())
for p in m.data.polygons:
 for j,li in enumerate(p.loop_indices):u.data[li].uv=packed[p.index][j]
# Preserve original image packed as reference, final pixels supplied in separate audited step.
for im in bpy.data.images:
 if im.size[0]>0:im.pack()
for mat in m.data.materials:
 for n in list(mat.node_tree.nodes):
  if n.type=='NORMAL_MAP' and not any(o.is_linked for o in n.outputs):mat.node_tree.nodes.remove(n)
D2={'uv':[[list(u.data[li].uv) for li in p.loop_indices] for p in m.data.polygons],'bones':spec,'vertices':[list(v.co) for v in m.data.vertices]};(P/'v002_layout.json').write_text(json.dumps(D2))
bpy.ops.wm.save_as_mainfile(filepath=str(P/'v002_candidate.blend'));print('CANDIDATE_OK bones=',len(spec))
