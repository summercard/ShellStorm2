import bpy,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v017'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v017.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];rig=bpy.data.objects['Boss002_Rig'];rig['heavy_spin_turns']=float(rig['heavy_spin_turns'])
for fc in rig.animation_data.action.fcurves:
 if 'heavy_spin_turns' in fc.data_path:fc.update_autoflags(rig)
source=(R/'scripts/blender/boss002_impact_preview_v014.py').read_text(encoding='utf-8')
source=source[:source.index('# White ink')].replace("'Keyboard outer shell'","'Portrait display'").replace('center_at(33)','center_at(65)').replace("fx['impact_frame']=33","fx['impact_frame']=65").replace('key(ob,55,loc,0)','key(ob,97,loc,0)').replace('(55,True)','(97,True)')
exec(source)
fx['style']='heavy slam: broad ink shockwave + cyan/magenta sparks; screen-only spin trails'
envelope(sprite('Heavy ground shock ring',1,True),65,69,80,origin,7.8)
envelope(sprite('Heavy outer echo ring',1,True),68,73,82,origin+Vector((0,0,.012)),9.0)
for i,(x,y,size) in enumerate([(-1.8,.1,2.7),(1.8,.2,3.2),(-.8,1,2.1),(.9,-.8,2.0)]):
 envelope(sprite('Heavy ink impact %d'%i,0),65+i%2,67+i%2,72+i,origin+Vector((x,y,.75)),size)
for i in range(8):
 a=math.tau*i/8;d=Vector((math.cos(a),math.sin(a),0));ob=sprite('Heavy cyber radial %02d'%i,2 if i%2==0 else 3)
 envelope(ob,65+i%3,68+i%3,76+i%3,origin+d*2.6+Vector((0,0,.5+(i%3)*.15)),1.5+(i%2)*.4)
# Purpose-built annular ribbons in the screen XZ plane: continuous rotation, no impact atlas.
def rotor_material(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;ns=m.node_tree.nodes;ns.clear();ls=m.node_tree.links
 attr=ns.new('ShaderNodeAttribute');attr.attribute_name='rotor_alpha';em=ns.new('ShaderNodeEmission');em.inputs[0].default_value=(*color,1);em.inputs[1].default_value=1.5
 tr=ns.new('ShaderNodeBsdfTransparent');mix=ns.new('ShaderNodeMixShader');out=ns.new('ShaderNodeOutputMaterial');ls.new(attr.outputs['Fac'],mix.inputs[0]);ls.new(tr.outputs[0],mix.inputs[1]);ls.new(em.outputs[0],mix.inputs[2]);ls.new(mix.outputs[0],out.inputs[0]);return m
rotor_mats=[rotor_material('PREVIEW_RotorCyan',(0,.65,1)),rotor_material('PREVIEW_RotorMagenta',(1,.015,.35)),rotor_material('PREVIEW_RotorWhite',(.65,.9,1))]
for j in range(6):
 verts=[];faces=[];alphas=[];radius=1.78+(j%3)*.16;span=math.radians(145 if j<3 else 105);width=.095 if j<3 else .025
 for i in range(65):
  t=i/64;a=t*span;w=width*math.sin(math.pi*t)**.65
  for side in [-1,1]:
   r=radius+side*w;verts.append((math.sin(a)*r,0,math.cos(a)*r));alphas.append((math.sin(math.pi*t)**.5)*(.8 if j<3 else .95))
  if i<64:faces.append((2*i,2*i+1,2*i+3,2*i+2))
 mesh=bpy.data.meshes.new('Rotor tapered ribbon');mesh.from_pydata(verts,[],faces);at=mesh.attributes.new('rotor_alpha','FLOAT','POINT')
 for d,a in zip(at.data,alphas):d.value=a
 ob=bpy.data.objects.new('Dedicated rotor ribbon %02d'%j,mesh);fx.objects.link(ob);mesh.materials.append(rotor_mats[j%3]);ob['preview_only']=True;ob['export']=False;ob['vfx_role']='rotation_only';ob.visible_shadow=False;ob.rotation_mode='XYZ'
 for f in range(1,98):
  studio.frame_set(f);axle=rig.pose.bones['rear_axle'].matrix.translation.copy();ob.location=axle+Vector((0,-.27-j*.009,0))
  strength=min(1,max(0,(f-18)/5),max(0,(51-f)/3));ob.scale=(strength,)*3;ob.rotation_euler=(0,float(rig['heavy_spin_turns'])*math.tau+j*math.tau/3,0)
  for prop in ['location','rotation_euler','scale']:ob.keyframe_insert(prop,frame=f)
  ob.hide_render=strength<=0;ob.keyframe_insert('hide_render',frame=f)
 for fc in ob.animation_data.action.fcurves:
  for k in fc.keyframe_points:k.interpolation='CONSTANT' if fc.data_path=='hide_render' else 'LINEAR'
studio.camera.location=(5,12,6);studio.camera.rotation_euler=(Vector((0,1,1.5))-studio.camera.location).to_track_quat('-Z','Y').to_euler();studio.camera.data.ortho_scale=11.5
studio.frame_set(1);studio['preview_instructions']='heavy_spin_slam 1-97: screen spins 3 turns, backlean49-55 hold55-59, impact65, low65-81, recover97. VFX only in studio.'
bpy.context.window.scene=studio;bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v017.blend'))
studio.cycles.samples=8;studio.render.resolution_x=960;studio.render.resolution_y=800
for f in [29,49,55,59,63,65,69,73,81,89,97]:
 studio.frame_set(f);studio.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
