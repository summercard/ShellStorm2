import bpy, json, os, math, hashlib

ROOT='/Users/summercards/ShellStorm2'
OUT=ROOT+'/assets/art/environments/tower_zones/battle/source/room_types/l_corridor/v001'
with open(OUT+'/room_type_manifest.json') as f: manifest=json.load(f)
with open(OUT+'/component_packages_v001/catalog.json') as f: catalog=json.load(f)
game=bpy.data.collections.get('02_游戏输出_独立资产包_v001')
palette=os.path.realpath(ROOT+'/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png')
issues=[]; meshes=[]; face_count=0; good_faces=0; empty=[]; names=set()
for entry in catalog:
    path=OUT+'/'+entry['path']+'/asset_manifest.json'
    if not os.path.isfile(path): issues.append('missing_manifest:'+entry['path']); continue
    with open(path) as f: rec=json.load(f)
    col=bpy.data.collections.get(rec['collection'])
    if col is None: issues.append('missing_collection:'+rec['collection']); continue
    obs=[o for o in col.objects if o.type=='MESH']
    if not obs: empty.append(entry['path'])
    if len(obs)!=entry['object_count']: issues.append('count_mismatch:'+entry['path'])
    if len(obs)!=len(rec['objects']): issues.append('manifest_objects:'+entry['path'])
    for ob in obs:
        if ob.name in names: issues.append('multi_package:'+ob.name)
        names.add(ob.name); meshes.append(ob)
        uv=ob.data.uv_layers.get('PaletteUV')
        if uv is None or ob.data.uv_layers.active!=uv or not uv.active_render:
            issues.append('uv_layer:'+ob.name); continue
        if len(ob.data.uv_layers)!=1: issues.append('extra_uv:'+ob.name)
        for poly in ob.data.polygons:
            face_count+=1
            points=[uv.data[i].uv for i in poly.loop_indices]
            us=[p.x for p in points]; vs=[p.y for p in points]
            cu=int(min(us)*10); cv=int(min(vs)*10)
            cross=any(int(min(9,max(0,u*10)))!=cu or int(min(9,max(0,v*10)))!=cv for u,v in points)
            area=abs(sum(points[i].x*points[(i+1)%len(points)].y-points[(i+1)%len(points)].x*points[i].y for i in range(len(points))))/2
            margin=min(min(us)-cu/10,(cu+1)/10-max(us),min(vs)-cv/10,(cv+1)/10-max(vs))
            if cross or area<1e-7 or margin<.009: issues.append('bad_face_uv:'+ob.name+':'+str(poly.index))
            else: good_faces+=1
if empty: issues += ['empty_package:'+p for p in empty]
if len(catalog)!=manifest['package_count']: issues.append('package_total')
if len([x for x in catalog if '/floor/' in x['path']])!=28: issues.append('tile_count')
if len(bpy.data.materials)!=4: issues.append('material_count')
for mat in bpy.data.materials:
    if not mat.name.startswith(('01_','02_','03_','04_')): issues.append('material_name:'+mat.name)
    nodes=mat.node_tree.nodes if mat.use_nodes else []
    imgs=[n for n in nodes if n.type=='TEX_IMAGE']
    if len(imgs)!=1 or os.path.realpath(bpy.path.abspath(imgs[0].image.filepath))!=palette or imgs[0].interpolation!='Closest' or imgs[0].image.packed_file:
        issues.append('palette:'+mat.name)
    uvs=[n for n in nodes if n.type=='UVMAP']
    if len(uvs)!=1 or uvs[0].uv_map!='PaletteUV': issues.append('material_uv:'+mat.name)
report={'status':'pass' if not issues else 'fail','source_blend':bpy.data.filepath,'mesh_objects':len(meshes),'packages':len(catalog),'floor_tile_packages':28,'faces_total':face_count,'faces_valid_palette_uv':good_faces,'materials':len(bpy.data.materials),'wall_visual_height_m':11.9,'wall_logic_height_m':12,'door_centers_m':manifest['door_centers_m'],'scope_lock':'new source, no previous asset to compare','issues':issues[:100]}
with open(OUT+'/qa_report.json','w') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False))
if issues: raise SystemExit(1)
