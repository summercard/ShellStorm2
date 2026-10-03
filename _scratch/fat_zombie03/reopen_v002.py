import bpy,json,struct
from pathlib import Path
p=Path(__file__).parent; root=p.parents[1]; pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03'
bpy.ops.wm.open_mainfile(filepath=str(pkg/'source/model/enm_normal_fat_zombie03_model_v002.blend'))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH')
assert len(a.data.bones)==66 and len(bpy.data.actions)==0
poseerr=max(abs(x-(1 if i==j else 0)) for b in a.pose.bones for i,row in enumerate(b.matrix_basis) for j,x in enumerate(row))
print('POSE_BASIS_ERROR',poseerr,[(b.name,list(b.rotation_quaternion),list(b.scale),list(b.location)) for b in a.pose.bones if max(abs(x-(1 if i==j else 0)) for i,row in enumerate(b.matrix_basis) for j,x in enumerate(row))>1e-6],flush=True)
assert poseerr<1e-6
assert all(abs(v-1)<1e-6 for o in [a,m] for v in o.scale)
assert all(list(n.image.size)==[512,512] for mat in m.data.materials for n in mat.node_tree.nodes if n.type=='TEX_IMAGE')
dg=bpy.context.evaluated_depsgraph_get();evaluated=m.evaluated_get(dg); em=evaluated.to_mesh()
resterr=max((v.co-w.co).length for v,w in zip(m.data.vertices,em.vertices));evaluated.to_mesh_clear();assert resterr<1e-5
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb';data=glb.read_bytes();length=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+length]);bindata=data[28+length:]
assert len(g['skins'][0]['joints'])==66
images=[]
for im in g['images']:
 b=g['bufferViews'][im['bufferView']];raw=bindata[b.get('byteOffset',0):b.get('byteOffset',0)+b['byteLength']];assert raw[:8]==b'\x89PNG\r\n\x1a\n';size=list(struct.unpack('>II',raw[16:24]));assert size==[512,512];images.append(size)
report={'reopened_model_rest_error_m':resterr,'glb_skin_joints':len(g['skins'][0]['joints']),'glb_embedded_images':images,'animation_count':len(g.get('animations',[]))}
(p/'reopen_audit_v002.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('FAT_ZOMBIE03_REOPEN_V002_OK',report)
