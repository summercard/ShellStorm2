import bpy,os,json,sys
res={'blend':bpy.data.filepath,'images':[],'materials':[]}
for i in bpy.data.images:
    ap=bpy.path.abspath(i.filepath) if i.filepath else ''
    res['images'].append({'name':i.name,'filepath':i.filepath,'abspath':ap,'packed':bool(i.packed_file),'exists':bool(ap) and os.path.exists(ap),'size':list(i.size),'has_data':i.has_data})
for m in bpy.data.materials:
    rec={'name':m.name,'use_nodes':m.use_nodes,'img_nodes':[],'uv_nodes':[]}
    if m.use_nodes and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type=='TEX_IMAGE': rec['img_nodes'].append({'node':n.name,'image':n.image.name if n.image else None,'interpolation':n.interpolation})
            if n.type=='UVMAP': rec['uv_nodes'].append(n.uv_map)
    res['materials'].append(rec)
print('INSPECT_JSON_BEGIN')
print(json.dumps(res,ensure_ascii=False,indent=1))
print('INSPECT_JSON_END')
