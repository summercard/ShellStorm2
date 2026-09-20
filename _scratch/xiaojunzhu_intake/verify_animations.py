import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Vector
P=Path(__file__).parent;meta=json.loads((P/'animation_meta.json').read_text());results=[];render='--render' in __import__('sys').argv;dest=P/'animation_frames';dest.mkdir(exist_ok=True)
for entry in meta['clips']:
 s=bpy.data.scenes[entry['scene']];bpy.context.window.scene=s;a=next(o for o in s.objects if o.type=='ARMATURE');m=next(o for o in s.objects if o.type=='MESH');sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,7) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest();assert sig==meta['skeleton_signature'];assert m.data.library is not None
 low=100;high=-100;first=None;last=None;rootmax=0;maxedge=0
 for step in range(entry['frames']*4+1):
  f=1+step/4;s.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update();ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();pts=[m.matrix_world@v.co for v in mesh.vertices];z=min(v.z for v in pts);low=min(low,z);high=max(high,z)
  if step==0:first=pts
  if step==entry['frames']*4:last=pts
  assert all(abs(k-1)<1e-5 for p in a.pose.bones for k in p.scale)
  rootmax=max(rootmax,a.pose.bones['Root'].location.length,abs(a.pose.bones['Root'].rotation_quaternion.angle));ev.to_mesh_clear()
 seam=max((u-v).length for u,v in zip(first,last));assert low>-.004,(entry['id'],'ground',low)
 if entry['loop']:assert seam<1e-5,(entry['id'],'seam',seam)
 assert rootmax<1e-6
 if entry['id']=='dead':
  vertical=a.pose.bones['Head'].matrix.to_quaternion()@a.data.bones['Head'].matrix_local.to_quaternion().inverted()@Vector((0,0,1))
  assert abs(vertical.z)<.25, ('death_not_lying',list(vertical))
 results.append({'clip':entry['id'],'samples':entry['frames']*4+1,'min_surface_z':low,'max_min_surface_z':high,'loop_vertex_error':seam if entry['loop'] else None,'root_motion':rootmax,'skeleton_match':True,'unit_scale':True})
 if not render:continue
 s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=420;s.render.resolution_y=420;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG';s.world=bpy.data.worlds.new('PreviewWorld');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[0].default_value=(.72,.76,.82,1);s.world.node_tree.nodes['Background'].inputs[1].default_value=.7;s.view_settings.view_transform='Standard'
 coll=bpy.data.collections.new('90_预览环境_不导出_'+entry['id']);s.collection.children.link(coll)
 for pos,power in [((3,4,5),400),((-3,1,3),220),((0,-3,4),280)]:
  d=bpy.data.lights.new('Preview','AREA');d.energy=power;d.size=4;o=bpy.data.objects.new('Preview',d);coll.objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
 d=bpy.data.cameras.new('Preview');d.type='ORTHO';d.ortho_scale=2.65;c=bpy.data.objects.new('Preview',d);coll.objects.link(c);c.location=(3.5,5,2.5);target=Vector((0,-.2,.8));c.rotation_euler=(target-c.location).to_track_quat('-Z','Y').to_euler();s.camera=c
 # Ground mesh for readable contact/shadows, preview only.
 mesh=bpy.data.meshes.new('PreviewGround');mesh.from_pydata([(-4,-4,0),(4,-4,0),(4,4,0),(-4,4,0)],[],[(0,1,2,3)]);g=bpy.data.objects.new('PreviewGround',mesh);coll.objects.link(g);mat=bpy.data.materials.new('Ground');mat.diffuse_color=(.55,.59,.64,1);g.data.materials.append(mat)
 for idx in range(25):
  frame=1+entry['frames']*idx/24;s.frame_set(int(frame),subframe=frame-int(frame));s.render.filepath=str(dest/(entry['id']+'_%02d.png'%idx));bpy.ops.render.render(write_still=True)
(P/'animation_validation.json').write_text(json.dumps(results,indent=2));print('SIX_CLIPS_SOURCE_OK',json.dumps(results))
