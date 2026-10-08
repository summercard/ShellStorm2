import bpy, json, hashlib, struct
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2'); O=P/'outputs/base99_radio_v005'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
before=json.loads((O/'resume_before.json').read_text(encoding='utf-8'))
protected=[p for p in before['hashes'] if 'v004.blend' in p or 'shared/palette' in p or 'layout_top3d.tscn' in p or 'zone_base.tscn' in p or p=='src/base3d/Base99Radio3D.gd']
assert all(sha(P/p)==before['hashes'][p] for p in protected)

def world(o):return o.matrix_basis if not o.parent else world(o.parent)@o.matrix_parent_inverse@o.matrix_basis

def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=path);bpy.context.view_layer.update()
    outputs=[o for o in bpy.data.objects['ItemRoot'].children if o.type=='MESH']
    data={}
    for o in outputs:
        key='StatusLight' if o.name.startswith('StatusLight') else o.name
        data[key]={'vertices':[list(world(o)@v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'uv':[list(v.uv) for v in o.data.uv_layers['PaletteUV'].data],'materials':[mat.name for mat in o.data.materials],'indices':[f.material_index for f in o.data.polygons]}
    comps=[o for o in bpy.data.collections['01_制作组件_已统一材质'].all_objects if o.type=='MESH']
    cp=[world(o)@v.co for o in comps for v in o.data.vertices]
    op=[world(o)@v.co for o in outputs for v in o.data.vertices]
    error=max(min((a-b).length for b in op) for a in cp)
    assert error<1e-6, error
    assert len(bpy.data.materials)==4
    assert all(im.packed_file is None for im in bpy.data.images if im.source=='FILE')
    assert tuple(bpy.data.objects['ItemRoot'].scale)==(1,1,1)
    return data,{'component_output_vertex_error_m':error,'faces':sum(len(o.data.polygons) for o in outputs)}

a,ea=snapshot(m['source_blend']);b,eb=snapshot(m['optimized_blend']);assert a==b
assert sha(m['source_blend'])==m['hashes_sha256']['source'] and sha(m['optimized_blend'])==m['hashes_sha256']['optimized']
blob=Path(m['component_glb']).read_bytes();n=struct.unpack_from('<I',blob,12)[0];g=json.loads(blob[20:20+n])
tris=sum(g['accessors'][p['indices']]['count']//3 for mesh in g['meshes'] for p in mesh['primitives'])
assert tris==m['triangles'] and not g.get('images') and not g.get('textures')
assert sorted(n['name'] for n in g['nodes'])==['Antenna','ItemRoot','StatusLight','Visual']
assert len(g['materials'])==4
report={'passed':True,'source_optimized_geometry_uv_material_equal':True,'source_evidence':ea,'optimized_evidence':eb,'glb_triangles':tris,'faces':m['faces'],'four_materials':True,'glb_images_textures_zero':True,'locked_hashes_unchanged':{p:before['hashes'][p] for p in protected},'source_sha256':m['hashes_sha256']['source'],'optimized_sha256':m['hashes_sha256']['optimized'],'glb_sha256':sha(m['component_glb'])}
(O/'optimization_evidence_resume.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V005_INDEPENDENT_AUDIT_OK')
