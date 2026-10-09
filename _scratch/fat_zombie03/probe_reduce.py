import bpy,json
from pathlib import Path
p=Path(__file__).resolve().parents[2];pkg=p/'assets/art/enemies/normal_enemy_3d/fat_zombie03'
t=json.loads((pkg/'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(p/t['model_source']))
m=next(o for o in bpy.context.scene.objects if o.type=='MESH')
print('PROBE',json.dumps({'mesh':m.name,'verts':len(m.data.vertices),'tris':sum(len(x.vertices)-2 for x in m.data.polygons),'modifiers':[(x.name,x.type) for x in m.modifiers],'shapes':list(m.data.shape_keys.key_blocks.keys()),'groups':[x.name for x in m.vertex_groups],'attrs':[(x.name,x.data_type,x.domain) for x in m.data.attributes]},ensure_ascii=False),flush=True)
for key in list(m.data.shape_keys.key_blocks)[1:]:
 a=m.data.attributes.new('keep_'+key.name,'FLOAT_VECTOR','POINT')
 for i,v in enumerate(key.data):a.data[i].vector=v.co-m.data.vertices[i].co
m.shape_key_clear()
for mod in list(m.modifiers):m.modifiers.remove(mod)
bpy.context.view_layer.objects.active=m
mod=m.modifiers.new('Simplify','DECIMATE');mod.ratio=.348;mod.use_collapse_triangulate=True
bpy.ops.object.modifier_apply(modifier=mod.name)
print('REDUCED',len(m.data.vertices),len(m.data.polygons),[(a.name,a.data_type,a.domain) for a in m.data.attributes],flush=True)
print('ATTR',m.data.attributes.get('keep_BellyGroundCompression') is not None,flush=True)
