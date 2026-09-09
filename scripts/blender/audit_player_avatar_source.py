"""Read-only audit for the open model or animation Blend."""
import json
import bpy
from mathutils import Vector

def visible_mesh_bounds():
    points = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH' or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not points:
        return {}
    minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return {'minimum': list(minimum), 'maximum': list(maximum), 'dimensions': list(maximum-minimum)}

scene=bpy.context.scene
payload={'file':bpy.data.filepath,'role':scene.get('file_role','legacy'),'units':scene.unit_settings.system,'unit_scale':scene.unit_settings.scale_length,'objects':[],'collections':[],'actions':[]}
for collection in scene.collection.children:
    payload['collections'].append({'name':collection.name,'children':[{'name:c.name,'variants':[v.name for v in c.children]} for c in collection.children]})
for obj in scene.objects:
    payload['objects'].append({'name':obj.name,'type':obj.type,'parent':obj.parent.name if obj.parent else None,'location':list(obj.location),'rotation':list(obj.rotation_euler),'scale':list(obj.scale),'hidden':obj.hide_get(),'binding':[(m.type,m.object.name if m.object else None) for m in obj.modifiers if m.type=='ARMATURE']})
for action in bpy.data.actions:
    payload['actions'].append({'name':action.name,'state':action.get('state_id'),'range':list(action.frame_range),'loop':action.get('loop',False)})
print('CHARACTER_SOURCE_AUDIT='+json.dumps(payload,ensure_ascii=False))
# Preserve the original audit record for existing tooling.
legacy = {'blender_version': bpy.app.version_string,
          'unit_system': scene.unit_settings.system,
          'scale_length': scene.unit_settings.scale_length,
          'visible_mesh_bounds': visible_mesh_bounds(),
          'collections': [c.name for c in bpy.data.collections],
          'objects': [{'name': o.name, 'type': o.type,
                       'parent': o.parent.name if o.parent else '',
                       'location': list(o.location), 'rotation_euler': list(o.rotation_euler),
                       'scale': list(o.scale), 'hidden_viewport': o.hide_viewport,
                       'hidden_render': o.hide_render} for o in scene.objects]}
print('PLAYER_AVATAR_SOURCE_AUDIT='+json.dumps(legacy,ensure_ascii=False,sort_keys=True))
