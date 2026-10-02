"""Exact immutable-object checks for the top-preserving lower-structure revision."""
import bpy,hashlib,json,numpy as np
def object_signature(o):
 h=hashlib.sha256()
 def j(v):h.update(json.dumps(v,ensure_ascii=False,sort_keys=True,default=str).encode('utf8'))
 def a(items,prop,width,dtype):
  data=np.empty(len(items)*width,dtype=dtype);items.foreach_get(prop,data);h.update(data.tobytes())
 j(dict(name=o.name,type=o.type,parent=o.parent.name if o.parent else None,
        matrix=[[round(float(v),6) for v in r] for r in o.matrix_world],
        collections=sorted(c.name for c in o.users_collection),hide=[o.hide_render,o.hide_viewport],
        properties={k:str(o[k]) for k in o.keys()},modifiers=[str(m) for m in o.modifiers],animation=str(o.animation_data)))
 if o.type=='MESH':
  m=o.data;j([len(m.vertices),len(m.edges),len(m.polygons),[v.name for v in m.materials]])
  a(m.vertices,'co',3,np.float32);a(m.edges,'vertices',2,np.int32);a(m.loops,'vertex_index',1,np.int32)
  for p in ('loop_start','loop_total','material_index'):a(m.polygons,p,1,np.int32)
  a(m.polygons,'use_smooth',1,np.bool_)
  for u in m.uv_layers:j([u.name,u.active_render,u==m.uv_layers.active]);a(u.data,'uv',2,np.float32)
 elif o.type=='CAMERA':j([o.data.lens,o.data.ortho_scale,o.data.clip_start,o.data.clip_end,o.data.type])
 elif o.type=='LIGHT':j([o.data.energy,list(o.data.color),o.data.type,getattr(o.data,'size',None),getattr(o.data,'angle',None)])
 return h.hexdigest()
