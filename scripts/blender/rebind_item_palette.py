"""Migrate item Blender mothers without changing geometry, UVs or material roles."""
import bpy, json, hashlib, sys, os, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/asset_pipeline'),str(ROOT/'scripts')]
from item_palette import TARGET, sha, MATERIAL_ROLES, SATURATION_MULTIPLIER, VALUE_MULTIPLIER
from workspace_paths import work_path
OUT=work_path('sessions/2026-10-15_item_materials/blender_result.json').parent
BACKUP=ROOT.parent/'ShellStorm2-backup/2026-10-15_item_materials/before_edits'

def geometry_signature():
    h=hashlib.sha256()
    for obj in sorted(bpy.data.objects,key=lambda o:o.name):
        h.update(str((obj.name,obj.type,tuple(obj.location),tuple(obj.rotation_euler),tuple(obj.scale),obj.parent.name if obj.parent else '')).encode())
        if obj.type=='MESH':
            m=obj.data
            h.update(str([(tuple(v.co)) for v in m.vertices]).encode())
            h.update(str([(tuple(p.vertices),p.material_index,p.use_smooth) for p in m.polygons]).encode())
            for uv in m.uv_layers:
                h.update(str((uv.name,[tuple(l.uv) for l in uv.data])).encode())
    return h.hexdigest()

paths=sorted((ROOT/'art_source/items_weapons/props').rglob('*.blend'))+sorted((ROOT/'art_source/items_weapons/weapons').rglob('*.blend'))
paths.append(ROOT/'art_source/items_weapons/_templates/prp/prp_template_source_v001.blend')
results=[]
for path in paths:
    backup=BACKUP/path.relative_to(ROOT);backup.parent.mkdir(parents=True,exist_ok=True)
    if not backup.exists():shutil.copy2(path,backup)
    before=sha(backup)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    signature=geometry_signature()
    # Legacy reference kits may retain several copies of a role from appended assets.
    for i,name in enumerate(MATERIAL_ROLES):
        role_materials=[m for m in bpy.data.materials if m.name.startswith(f'{i+1:02}_')]
        if not role_materials:continue
        canonical=next((m for m in role_materials if m.name==name),role_materials[0])
        for other in role_materials:
            if other!=canonical:
                other.user_remap(canonical)
                bpy.data.materials.remove(other)
        canonical.name=name
    images=[]
    for mat in bpy.data.materials:
        if not mat.use_nodes:continue
        role=int(mat.name[:2])-1 if mat.name[:2].isdigit() else -1
        if 0 <= role < 4:
            mat.name=MATERIAL_ROLES[role]
            for node in mat.node_tree.nodes:
                if node.type=='BSDF_PRINCIPLED':
                    node.inputs['Metallic'].default_value=[.86,.02,.18,0][role]
                    node.inputs['Roughness'].default_value=[.28,.72,.16,.4][role]
                    node.inputs['Coat Weight'].default_value=[.15,0,.65,0][role]
                    node.inputs['Emission Strength'].default_value=1.3 if role==3 else 0
        for node in mat.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image:
                im=node.image
                if '色盘' in im.name or 'palette' in im.name.lower() or '色盘' in im.filepath:
                    im.filepath='//'+os.path.relpath(ROOT/TARGET,path.parent).replace('\\','/')
                    if im.packed_file:im.unpack(method='REMOVE')
                    im.name='ItemHighVisibilityPalette'
                    im.reload()
                    node.interpolation='Closest'
                    if im.name not in images:images.append(im.name)
    assert images, str(path)+' has no palette nodes'
    bpy.context.scene['item_palette']=TARGET
    bpy.context.scene['item_palette_recipe']=f'sRGB HSV: S*{SATURATION_MULTIPLIER},V*{VALUE_MULTIPLIER}, clamp1; hue/alpha unchanged'
    bpy.context.scene['item_material_roles']=';'.join(MATERIAL_ROLES)
    assert geometry_signature()==signature
    bpy.context.preferences.filepaths.save_version=0
    temp=OUT/(path.stem+'_updated.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(temp),relative_remap=False)
    shutil.copy2(temp,path)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    assert geometry_signature()==signature, 'geometry/UV changed:'+str(path)
    checked=0
    for mat in bpy.data.materials:
        if not mat.use_nodes:continue
        if mat.name[:2].isdigit():assert mat.name in MATERIAL_ROLES, mat.name
        for node in mat.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image:
                assert Path(bpy.path.abspath(node.image.filepath)).resolve()==(ROOT/TARGET).resolve(),(str(path),node.image.filepath)
                assert not node.image.packed_file and node.interpolation=='Closest'
                checked+=1
    results.append(dict(path=path.relative_to(ROOT).as_posix(),old_sha256=before,sha256=sha(path),bytes=path.stat().st_size,geometry_uv_unchanged=True,material_nodes=checked))
    (OUT/'blender_result.json').write_text(json.dumps(dict(passed=True,sources=results),ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('ITEM_PALETTE_SOURCE_OK',len(results),path.name,flush=True)
print('ITEM_PALETTE_ALL_SOURCES_OK',len(results),flush=True)
