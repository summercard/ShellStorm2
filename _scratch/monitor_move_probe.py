import bpy,json
r=bpy.data.objects['Boss002_Rig'];a=bpy.data.actions['move']
print(json.dumps({'file':bpy.data.filepath,'action':a.name,'frames':list(a.frame_range),'bones':[{'name':b.name,'parent':b.parent.name if b.parent else None} for b in r.data.bones][:18],'curves':[(f.data_path,f.array_index,len(f.keyframe_points)) for f in a.fcurves if any(x in f.data_path for x in ['pedestal','support','monitor'])],'scenes':list(bpy.data.scenes.keys()),'actions':list(bpy.data.actions.keys())}))
