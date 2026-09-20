import bpy,json,math
from pathlib import Path
from mathutils import Vector
P=Path(__file__).parent;m=next(o for o in bpy.context.scene.objects if o.type=='MESH');a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');source=json.loads((P/'uv_rig_source.json').read_text());s=bpy.context.scene
assert len(m.data.vertices)==len(source['vertices'])
assert max((v.co-Vector(source['vertices'][i])).length for i,v in enumerate(m.data.vertices))<1e-7
z=[(m.matrix_world@v.co).z for v in m.data.vertices];assert abs(max(z)-min(z)-1.3/.7)<1e-5
weights=[sum(g.weight for g in v.groups) for v in m.data.vertices];assert min(weights)>.99999 and max(weights)<1.00001
assert m.data.uv_layers.active.name=='UVMap';assert len(bpy.data.actions)==0
images=[n.image for mat in m.data.materials for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'];assert all(i.packed_file and tuple(i.size)==(2048,2048) for i in images)
def evalverts():
 bpy.context.view_layer.update();e=m.evaluated_get(bpy.context.evaluated_depsgraph_get());me=e.to_mesh();pts=[v.co.copy() for v in me.vertices];e.to_mesh_clear();return pts
base=evalverts();tests=[]
for b in a.pose.bones:
 if not any(k in b.name for k in ['Thumb','Index','Middle','Pinky']):continue
 group=m.vertex_groups[b.name];ids=[v.index for v in m.data.vertices if any(g.group==group.index and g.weight>.05 for g in v.groups)];assert len(ids)>0,b.name
 b.rotation_mode='XYZ';b.rotation_euler.x=.45;new=evalverts();disp=max((new[i]-base[i]).length for i in ids);assert disp>.0005,(b.name,disp)
 opposite=[i for i,v in enumerate(m.data.vertices) if v.co.x*(1 if b.name.startswith('L') else -1)>.1];leak=max((new[i]-base[i]).length for i in opposite);assert leak<1e-6
 tests.append({'bone':b.name,'weighted_vertices':len(ids),'test_angle_degrees':math.degrees(.45),'max_displacement_m':disp,'opposite_side_max_displacement':leak});b.rotation_euler=(0,0,0)
# Body joint stress poses are diagnostics, not animation production.
for side in ['L','R']:
 for segment in ['Upperarm','Forearm','Thigh','Calf']:
  b=a.pose.bones[side+'_'+segment];b.rotation_mode='XYZ';b.rotation_euler.x=.35;pts=evalverts();assert all(math.isfinite(c) for v in pts for c in v);b.rotation_euler=(0,0,0)
report={'height_source_m':max(z)-min(z),'height_display_m':(max(z)-min(z))*.7,'min_z':min(z),'bones':len(a.data.bones),'finger_deform_bones':len(tests),'finger_tests':tests,'vertices':len(m.data.vertices),'faces':len(m.data.polygons),'weights_normalized':True,'geometry_unchanged':True,'images_packed':True,'actions':len(bpy.data.actions),'status':'source_verified_not_godot_integrated'};(P/'rig_validation.json').write_text(json.dumps(report,indent=2));print('RIG_SOURCE_OK',json.dumps(report))
# Render final reopened file and source under same camera/light, no saving preview objects.
s.render.engine='CYCLES';s.cycles.samples=24;s.cycles.use_denoising=True;s.render.resolution_x=720;s.render.resolution_y=840;s.render.resolution_percentage=100;s.view_settings.view_transform='Standard';s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[0].default_value=(.72,.75,.8,1);s.world.node_tree.nodes['Background'].inputs[1].default_value=.7
for loc,power in [((2,4,4),180),((-3,2,2),110),((0,-3,3),130)]:
 data=bpy.data.lights.new('QA','AREA');data.energy=power;data.size=4;o=bpy.data.objects.new('QA',data);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
c=bpy.data.cameras.new('QA');c.type='ORTHO';c.ortho_scale=2.18;cam=bpy.data.objects.new('QA',c);s.collection.objects.link(cam);s.camera=cam
for name,loc,target,scale in [('front',(0,5,.92),(0,0,.92),2.18),('back',(0,-5,.92),(0,0,.92),2.18),('side',(5,0,.92),(0,0,.92),2.18),('hand_rest',(.56,.03,3),(.56,.03,.765),.33),('hand_flex',(.56,.03,3),(.56,.03,.765),.33),('body_pose',(2.7,5,2),(0,0,.9),2.18)]:
 if name=='hand_flex':
  for b in a.pose.bones:
   if b.name.startswith('R_') and any(k in b.name for k in ['Thumb','Index','Middle','Pinky']):b.rotation_euler.x=.6
 if name=='body_pose':
  for b in a.pose.bones:b.rotation_euler=(0,0,0)
  a.pose.bones['R_Forearm'].rotation_euler.x=.65;a.pose.bones['L_Upperarm'].rotation_euler.x=.35;a.pose.bones['R_Calf'].rotation_euler.x=.5
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();c.ortho_scale=scale;s.render.filepath=str(P/('v002_'+name+'.png'));bpy.ops.render.render(write_still=True)
# checker preview protects against texture transfer hiding distortion
for b in a.pose.bones:b.rotation_euler=(0,0,0)
mat=m.data.materials[0];tree=mat.node_tree;checker=tree.nodes.new('ShaderNodeTexChecker');checker.inputs['Scale'].default_value=40;uvnode=tree.nodes.new('ShaderNodeTexCoord');tree.links.new(uvnode.outputs['UV'],checker.inputs['Vector']);tree.links.new(checker.outputs['Color'],next(n for n in tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color']);cam.location=(0,5,.92);cam.rotation_euler=(Vector((0,0,.92))-cam.location).to_track_quat('-Z','Y').to_euler();c.ortho_scale=2.18;s.render.filepath=str(P/'v002_checker.png');bpy.ops.render.render(write_still=True)
print('REOPEN_AND_RENDER_OK')
