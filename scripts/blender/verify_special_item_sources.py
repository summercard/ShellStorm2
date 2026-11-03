"""Reopen both model roles from disk; validate actual topology, UV, materials and size."""
import bpy
import hashlib
import json
from mathutils import Vector
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from special_items_workspace import work_path
items=json.loads((ROOT/'data/special_items/catalog.json').read_text(encoding='utf-8'))['items']
results=[];failures=[]
for item in items:
    manifest=json.loads((ROOT/f"art_source/items_weapons/props/{item['id']}/source_manifest.json").read_text(encoding='utf-8'))
    for role,entry in manifest['roles'].items():
        path=ROOT/entry['source']
        actual_hash=hashlib.sha256(path.read_bytes()).hexdigest()
        bpy.ops.wm.open_mainfile(filepath=str(path))
        collection=bpy.data.collections['02_游戏输出_整合模型']
        output=[obj for obj in collection.objects if obj.type=='MESH']
        triangles=0;bounds=[]
        for obj in output:
            if (obj.scale-Vector((1,1,1))).length>0.00001:
                failures.append(f'{item["id"]}/{role}: nonidentity output scale')
            mesh=obj.data;mesh.calc_loop_triangles();triangles+=len(mesh.loop_triangles)
            bounds.extend([obj.matrix_world@Vector(corner) for corner in obj.bound_box])
            if len(mesh.uv_layers)!=1 or mesh.uv_layers.active.name!='PaletteUV' or not mesh.uv_layers['PaletteUV'].active_render:
                failures.append(f'{item["id"]}/{role}: invalid active UV')
            uv=mesh.uv_layers['PaletteUV']
            for polygon in mesh.polygons:
                vertices=[uv.data[index].uv for index in polygon.loop_indices]
                cells={(int(v.x*10),int(v.y*10)) for v in vertices}
                area=abs(sum(vertices[i].x*vertices[(i+1)%len(vertices)].y-vertices[(i+1)%len(vertices)].x*vertices[i].y for i in range(len(vertices))))*.5
                if len(cells)!=1 or area<1e-8:
                    failures.append(f'{item["id"]}/{role}: invalid UV island {polygon.index}')
            for material in mesh.materials:
                if material.name not in manifest['materials']:
                    failures.append(f'{item["id"]}/{role}: unregistered material {material.name}')
        dimensions=[max(v[i] for v in bounds)-min(v[i] for v in bounds) for i in range(3)]
        expected=item['dimensions_m']
        dimensions_godot=[dimensions[0],dimensions[2],dimensions[1]]
        expected_godot=[expected[0],expected[2],expected[1]]
        if any(abs(dimensions_godot[i]-expected_godot[i])/expected_godot[i]>.08 for i in range(3)):
            failures.append(f'{item["id"]}/{role}: size drift {dimensions_godot}')
        if role=='ground' and (not 100<=triangles<=200 or any(len(p.vertices)!=3 for obj in output for p in obj.data.polygons)):
            failures.append(f'{item["id"]}/{role}: ground budget {triangles}')
        if actual_hash!=entry['source_sha256']:
            failures.append(f'{item["id"]}/{role}: stale source hash')
        for image in bpy.data.images:
            if image.packed_file:
                failures.append(f'{item["id"]}/{role}: embedded image')
            if image.source=='FILE' and image.filepath and not Path(bpy.path.abspath(image.filepath)).exists():
                failures.append(f'{item["id"]}/{role}: missing external image {image.filepath}')
        results.append({'id':item['id'],'role':role,'triangles':triangles,'dimensions_xyz_m':dimensions_godot,'sha256':actual_hash})
report={'models':results,'failures':failures}
work_path('sessions/2026-11-03_special_items/blender_source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if failures:
    print('SPECIAL_ITEM_SOURCE_FAILED',failures,flush=True)
    raise RuntimeError('Special item source validation failed')
print('SPECIAL_ITEM_SOURCES_OK',json.dumps(results,ensure_ascii=False),flush=True)
