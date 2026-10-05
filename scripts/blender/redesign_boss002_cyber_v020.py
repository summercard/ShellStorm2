"""Boss002: designed cyber pulse FX, flat fills, no outlines or sketch textures."""
import bpy,math,json,hashlib,random
from pathlib import Path
from mathutils import Vector
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v020';P.mkdir(exist_ok=True)
def snapshot():
 return hashlib.sha256(repr([(a.name,[(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]) for a in bpy.data.actions if a.name in ['idle','move','melee_keyboard','heavy_spin_slam']]).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v019.blend'))
for sc in bpy.data.scenes:sc['asset_version']='v020'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v020.blend'))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v019.blend'));before=snapshot()
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];fx=bpy.data.collections['BOSS002_IMPACT_PREVIEW']
s.frame_set(69);origin=next(o.location.copy() for o in fx.objects if 'ground shock ring' in o.name);origin.z=.045
for ob in list(fx.objects):bpy.data.objects.remove(ob,do_unlink=True)
palette=[(.035,.22,.34,1),(.12,.50,.66,1),(.48,.09,.25,1),(.55,.78,.82,1),(.08,.18,.29,1)]
mats=[]
for i,col in enumerate(palette):
 m=bpy.data.materials.new('CYBER_FlatFill_%d'%i);m.use_nodes=True;n=m.node_tree.nodes;n.clear();l=m.node_tree.links
 e=n.new('ShaderNodeEmission');e.inputs[0].default_value=col;e.inputs[1].default_value=1.7 if i==3 else 1.15
 info=n.new('ShaderNodeObjectInfo');tr=n.new('ShaderNodeBsdfTransparent');mix=n.new('ShaderNodeMixShader');out=n.new('ShaderNodeOutputMaterial')
 l.new(info.outputs['Alpha'],mix.inputs[0]);l.new(tr.outputs[0],mix.inputs[1]);l.new(e.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],out.inputs[0]);mats.append(m)
def meshob(name,verts,faces,mat):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(mats[mat]);o=bpy.data.objects.new(name,me);fx.objects.link(o);o.visible_shadow=False;o['preview_only']=True;o['export']=False;return o
def arc(name,r,width,start,span,mat,vertical=False,taper=False):
 verts=[];faces=[]
 for k in range(49):
  t=k/48;a=start+t*span;w=width*(.12+.88*math.sin(math.pi*t)**.7 if taper else 1)
  for side in [-1,1]:
   rad=r+side*w/2;x=math.cos(a)*rad;y=math.sin(a)*rad;verts.append((x,0,y) if vertical else (x,y,0))
  if k<48:faces.append((2*k,2*k+1,2*k+3,2*k+2))
 return meshob(name,verts,faces,mat)
def key(o,f,loc,scale,alpha,rot=(0,0,0)):
 o.location=loc;o.scale=(scale,)*3;o.rotation_euler=rot;o.color=(1,1,1,max(0,min(1,alpha)));o.hide_render=alpha<=.001
 for prop in ['location','scale','rotation_euler','color','hide_render']:o.keyframe_insert(prop,frame=f)
def finish(o):
 for fc in o.animation_data.action.fcurves:
  for k in fc.keyframe_points:k.interpolation='CONSTANT' if fc.data_path=='hide_render' else 'LINEAR'
# Screen-space swept blades and spaced telemetry blocks; restrained pink accents.
for j in range(9):
 lane=j//3;r=1.8+lane*.18;o=arc('Cyber rotor band %02d'%j,r,[.15,.046,.07][lane],j%3*math.tau/3,math.radians([105,70,18][lane]),2 if j in [2,8] else (1 if lane==1 else 0),True,True);o['vfx_role']='rotation_only'
 for f in range(1,98):
  s.frame_set(f);a=min(1,max(0,(f-18)/4),max(0,(52-f)/4));key(o,f,rig.pose.bones['rear_axle'].matrix.translation+Vector((0,-.29-lane*.02,0)),1,a,(0,float(rig['heavy_spin_turns'])*math.tau,0))
 finish(o)
for j in range(12):
 o=arc('Rotor data tile %02d'%j,2.2+(j%2)*.06,.055,j*math.tau/12,math.radians(3+(j%3)*2),2 if j%5==0 else 1,True)
 for f in range(1,98):
  s.frame_set(f);a=min(.7,max(0,(f-22)/5),max(0,(50-f)/3));a*=.5 if (f+j)%9<3 else 1;key(o,f,rig.pose.bones['rear_axle'].matrix.translation+Vector((0,-.33,0)),1,a,(0,float(rig['heavy_spin_turns'])*math.tau*.7,0))
 finish(o)
# Three staggered expanding shockfronts. Gaps and uneven sector sizes prevent a target-ring look.
for layer in range(3):
 for j in range(7):
  a=j*math.tau/7+.19*layer;span=math.radians(27+(j*7)%17);o=arc('Ground pulse %d sector %d'%(layer,j),1,[.06,.022,.035][layer],a,span,2 if (j+layer*2)%8==0 else [1,0,4][layer])
  for f in range(1,98):
   t=(f-65-layer*2)/[12,13,15][layer];active=0<=t<=1;rad=.65+(3.9+layer*.35)*(1-(1-max(0,min(t,1)))**2);alpha=(1-max(t,0))**1.15 if active else 0
   key(o,f,origin+Vector((0,0,.012*layer)),rad,alpha,(0,0,.07*layer*t))
  finish(o)
# Directional solid shards rise and travel out from the impact, with late data-block breakup.
rng=random.Random(20)
for j in range(22):
 a=j*math.tau/22+rng.uniform(-.07,.07);d=Vector((math.cos(a),math.sin(a),0));side=Vector((-d.y,d.x,0));length=rng.uniform(1.1,2.0);width=rng.uniform(.08,.16);height=rng.uniform(.28,.95)
 verts=[tuple(-side*width),tuple(side*width),tuple(d*length+Vector((0,0,height))+side*width*.35),tuple(d*(length+.22)+Vector((0,0,height)))]
 o=meshob('Radial energy shard %02d'%j,verts,[(0,1,2,3)],2 if j%6==0 else (3 if j%5==0 else 0));start=65+j%3;end=76+j%4
 for f in range(1,98):
  t=(f-start)/(end-start);u=max(0,min(1,t));alpha=min(1,(1-u)*1.8) if 0<=t<=1 else 0;loc=origin+d*(.95+u*(2+j%3*.5))+Vector((0,0,.07+math.sin(u*math.pi)*.2));key(o,f,loc,1-u*.65,alpha)
 finish(o)
for j in range(24):
 a=j*2.399;d=Vector((math.cos(a),math.sin(a),0));w=.08+(j%3)*.035;h=.028+(j%2)*.025
 o=meshob('Escaping data block %02d'%j,[(-w,-h,0),(w,-h,0),(w,h,0),(-w,h,0)],[(0,1,2,3)],2 if j%7==0 else 1)
 start=67+j%4
 for f in range(1,98):
  t=(f-start)/12;u=max(0,min(1,t));alpha=(1-u)*(.35 if (f+j)%5==0 else .85) if 0<=t<=1 else 0;loc=origin+d*(1.5+2.4*u)+Vector((0,0,.1+(j%5)*.16+math.sin(u*math.pi)*.35));key(o,f,loc,1-u*.4,alpha,(math.radians(55),0,a))
 finish(o)
for sc in bpy.data.scenes:sc['asset_version']='v020'
fx['style']='cyber pulse: unoutlined cool cyan/teal solid shapes, muted magenta data accents, segmented expanding rings';fx['palette']='cool desaturated blue/cyan, restrained magenta, ice highlights'
assert before==snapshot();s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v020.blend'))
(P/'style_audit.json').write_text(json.dumps({'character_actions_unchanged':True,'fx_objects':len(fx.objects),'style':fx['style'],'no_outlines':True,'no_texture_nodes':all(not any(n.type=='TEX_IMAGE' for n in m.node_tree.nodes) for m in mats),'first_last_hidden':all((s.frame_set(f) is None and all(o.hide_render for o in fx.objects)) for f in [1,97])},indent=2))
s.cycles.samples=12;s.render.resolution_x=960;s.render.resolution_y=800
for f in [29,67,70]:s.frame_set(f);s.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
