"""Independent disk reload comparison, including locked geometry and presentation."""
import bpy,json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[2]; parent=R/'assets/art/environments/open_world/source/tower_02'
def snapshot(path):
 bpy.ops.wm.open_mainfile(filepath=str(path))
 cat=json.loads((path.parent/'catalog.json').read_text(encoding='utf8')); result={}
 for pack in cat['packages']:
  if pack['category']=='roof' or pack['slug'].startswith('crane_'): continue
  for name in pack['objects']:
   o=bpy.data.objects[name]; h=hashlib.sha256()
   h.update(str(tuple(tuple(v) for v in o.matrix_world)).encode())
   for v in o.data.vertices: h.update(str(tuple(v.co)).encode())
   for face in o.data.polygons: h.update(str((tuple(face.vertices),face.material_index)).encode())
   for uv in o.data.uv_layers:
    for d in uv.data: h.update(str(tuple(d.uv)).encode())
   h.update(str([m.name for m in o.data.materials]).encode()); result[name]=h.hexdigest()
 for o in bpy.context.scene.objects:
  if o.type=='CAMERA': result[o.name]=str((tuple(o.location),tuple(o.rotation_euler),o.data.type,o.data.ortho_scale,o.data.lens))
  if o.type=='LIGHT': result[o.name]=str((tuple(o.location),tuple(o.rotation_euler),o.data.type,o.data.energy,tuple(o.data.color)))
 return result
a=snapshot(parent/'v001/塔2_施工高楼_70x50m_v001.blend'); b=snapshot(parent/'v002/塔2_施工高楼_70x50m_v002.blend')
diff=[k for k,v in a.items() if b.get(k)!=v]
report=dict(passed=not diff,compared=len(a),differences=diff,scope='all unchanged package meshes; original cameras and lights; independent reload')
(parent/'v002/qa/independent_lock.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8'); print(report); assert not diff
