import bpy,json,hashlib,math,struct
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v004'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
protected=json.loads((O/'before_hashes.json').read_text(encoding='utf-8'))
locked=[p for p in protected if 'layout_top3d' in p or 'zone_base.tscn' in p or 'shared/palette' in p or 'v003.blend' in p]
assert all(sha(P/p)==protected[p] for p in locked)
def world(o):return o.matrix_basis if not o.parent else world(o.parent)@o.matrix_parent_inverse@o.matrix_basis
def snapshot(path):
 bpy.ops.wm.open_mainfile(filepath=path)
 outputs=[o for o in bpy.data.objects['ItemRoot'].children if o.type=='MESH']
 data={}
 for o in outputs:
  data[o.name]={'vertices':[list(world(o)@v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'uv':[list(v.uv) for v in o.data.uv_layers['PaletteUV'].data],'materials':[mat.name for mat in o.data.materials],'indices':[f.material_index for f in o.data.polygons]}
 comps=[o for o in bpy.data.collections['01_制作组件_已统一材质'].all_objects if o.type=='MESH']
 cp=[world(o)@v.co for o in comps for v in o.data.vertices]
 op=[world(o)@v.co for o in outputs for v in o.data.vertices]
 error=max(min((a-b).length for b in op) for a in cp)
 assert error<1e-6, error
 assert len(bpy.data.materials)==4
 assert all(im.packed_file is None for im in bpy.data.images if im.source=='FILE')
 antenna=bpy.data.objects['Antenna']
 verts=[v.co for v in antenna.data.vertices]
 low=sorted(verts,key=lambda v:v.z)[:10];high=sorted(verts,key=lambda v:v.z)[-10:]
 delta=sum(high,Vector())/10-sum(low,Vector())/10
 tilt=math.degrees(math.atan2(math.hypot(delta.x,delta.y),delta.z))
 assert 25<tilt<40
 return data,{'component_output_vertex_error_m':error,'antenna_actual_axis_tilt_degrees':tilt,'faces':sum(len(o.data.polygons) for o in outputs)}
a,ea=snapshot(m['source_blend']);b,eb=snapshot(m['optimized_blend']);assert a==b
assert sha(m['source_blend'])==m['hashes_sha256']['source'] and sha(m['optimized_blend'])==m['hashes_sha256']['optimized']
blob=Path(m['component_glb']).read_bytes();n=struct.unpack_from('<I',blob,12)[0];g=json.loads(blob[20:20+n])
tris=sum(g['accessors'][p['indices']]['count']//3 for mesh in g['meshes'] for p in mesh['primitives'])
assert tris==m['triangles'] and not g.get('images') and not g.get('textures')
assert sorted(n['name'] for n in g['nodes'])==['Antenna','ItemRoot','StatusLight','Visual']
assert len(g['materials'])==4
report={'passed':True,'source_optimized_geometry_uv_material_equal':True,'source_evidence':ea,'optimized_evidence':eb,'glb_triangles':tris,'faces':m['faces'],'four_materials':True,'glb_images_textures_zero':True,'locked_hashes_unchanged':{p:protected[p] for p in locked},'source_sha256':m['hashes_sha256']['source'],'optimized_sha256':m['hashes_sha256']['optimized'],'glb_sha256':sha(m['component_glb'])}
(O/'optimization_evidence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V004_INDEPENDENT_AUDIT_OK')
