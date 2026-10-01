"""Derive a replaceable face accessory from the unchanged v021 head surface.

Run Blender --background --factory-startup --python this_file.py.
The incremental static accessory lists v021 model/animation as dependencies.
"""
import bpy, bmesh, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
BUNNY = ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01'
MODEL = BUNNY/'production/v021/source/model/chr_bunny01_model_v021.blend'
ANIMATION = BUNNY/'production/v021/source/animation/chr_bunny01_animation_v021.blend'
ASSET = BUNNY/'components/face/electronic_mask'
ID = 'CHR-PLY-BUNNY01-FACE-ELECTRONIC-MASK'
SHIFT = .009

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def signature(rig):
    data=[{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in rig.data.bones]
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()

def material(name, color, metallic, roughness, emission=None):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metallic; p.inputs['Roughness'].default_value=roughness
    p.inputs['Coat Weight'].default_value=.45 if emission is None else .0
    p.inputs['Coat Roughness'].default_value=.12
    if emission:
        p.inputs['Emission Color'].default_value=(*emission,1); p.inputs['Emission Strength'].default_value=5
    return m

def tag(o):
    o['slot_id']='glasses'; o['variant_id']='electronic_mask'; o['component_id']='electronic_mask'; o['bone_id']='head'

def main():
    for d in ['source','components','runtime','previews','references']: (ASSET/d).mkdir(parents=True,exist_ok=True)
    reference=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-1ecbb56f-1239-4be2-b4e3-af8e6167c8f0.png')
    if reference.exists(): shutil.copy2(reference,ASSET/'references/electronic_mask_reference.png')
    before={str(p):sha(p) for p in [MODEL,ANIMATION]}
    bpy.ops.wm.open_mainfile(filepath=str(MODEL))
    head=bpy.data.objects['SRC_Head']; rig=bpy.data.objects['RIG_bunny01']
    sig=signature(rig)
    original_mesh=([tuple(v.co) for v in head.data.vertices],[tuple(p.vertices) for p in head.data.polygons])
    pivot=Matrix(json.loads(bpy.context.scene['runtime_component_rest'])['head']).translation
    branch=bpy.data.collections['眼镜']
    variant=bpy.data.collections.new('眼镜__electronic_mask'); branch.children.link(variant)
    variant['slot_id']='glasses'; variant['variant_id']='electronic_mask'; variant['asset_id']=ID

    # The dome has outward radial normals; the recessed hood seam has inward
    # normals. Flood only the connected dome, leaving the original hood intact.
    bm=bmesh.new(); bm.from_mesh(head.data); bm.faces.ensure_lookup_table(); bm.normal_update()
    def on_face(f):
        c=f.calc_center_median(); n=f.normal
        return c.y>.05 and n.y>.045 and n.x*c.x+n.z*(c.z-.72)>-.002
    candidates={f for f in bm.faces if on_face(f)}
    seeds=[min(candidates,key=lambda f:(f.calc_center_median()-Vector((x,.296,.72))).length) for x in [-.04,.04]]
    selected=set(seeds); stack=list(seeds)
    while stack:
        for e in stack.pop().edges:
            for f in e.link_faces:
                if f in candidates and f not in selected: selected.add(f); stack.append(f)
    # Keep the narrow original chin surface, which contains a small recess
    # outside the convex dome flood. Its copy hides the white tab at the base.
    for f in bm.faces:
        c=f.calc_center_median()
        if abs(c.x)<.065 and .477<c.z<.53 and c.y>.12 and f.normal.y>.1:
            selected.add(f)
    indexes=sorted(f.index for f in selected); assert len(indexes)>300,len(indexes)
    bm.free()
    # Copy the source mesh, then remove faces only from the copy.
    shell=head.copy(); shell.data=head.data.copy(); shell.name='SRC_Face_ElectronicMask_Shell'
    variant.objects.link(shell); shell.modifiers.clear(); shell.parent=None; shell.matrix_world=Matrix.Identity(4)
    cut=bmesh.new(); cut.from_mesh(shell.data); cut.faces.ensure_lookup_table()
    bmesh.ops.delete(cut,geom=[f for f in cut.faces if f.index not in indexes],context='FACES')
    bmesh.ops.delete(cut,geom=[v for v in cut.verts if not v.link_faces],context='VERTS')
    cut.to_mesh(shell.data); cut.free(); shell.data.update()
    black=material('MAT_ElectronicMask_BlackGlass',(.006,.008,.011),.25,.16)
    blue=material('MAT_ElectronicMask_CyanPixels',(.003,.05,.45),.1,.28,(.001,.10,1))
    shell.data.materials.clear(); shell.data.materials.append(black)
    for p in shell.data.polygons: p.material_index=0; p.use_smooth=True
    for v in shell.data.vertices: v.co.y+=SHIFT
    solid=shell.modifiers.new('面具壳体厚度_4mm','SOLIDIFY'); solid.thickness=.004; solid.offset=-1
    tag(shell); shell['copied_from']='SRC_Head'; shell['source_polygon_indices']=json.dumps(indexes)
    shell['forward_offset_m']=SHIFT
    surface=BVHTree.FromPolygons([v.co for v in shell.data.vertices],[list(p.vertices) for p in shell.data.polygons])

    pixels=[]
    # Reference: two upright rectangular cyan eyes, no mouth. Four by fourteen
    # independent square cells per eye; every cell follows the original dome.
    for side,x0 in [('L',-.098),('R',.098)]:
        for row in range(14):
            for col in range(4):
                x=x0+(col-1.5)*.0078; z=.735+(row-6.5)*.0078
                hit,normal,_,_=surface.ray_cast(Vector((x,2,z)),Vector((0,-1,0)))
                assert hit is not None,(side,row,col)
                bpy.ops.mesh.primitive_cube_add(size=1, location=hit+normal*.0034)
                o=bpy.context.object; o.name=f'SRC_Face_Pixel_{side}_{row:02d}_{col:02d}'
                o.rotation_mode='QUATERNION'; o.rotation_quaternion=normal.to_track_quat('Y','Z')
                o.scale=(.0058,.0025,.0058)
                bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
                for c in list(o.users_collection): c.objects.unlink(o)
                variant.objects.link(o); o.data.materials.append(blue); pixels.append(o); tag(o)
    # Join pixel cells into one mesh; disconnected cubes retain visible spacing.
    bpy.ops.object.select_all(action='DESELECT')
    for o in pixels: o.select_set(True)
    bpy.context.view_layer.objects.active=pixels[0]; bpy.ops.object.join()
    eye=bpy.context.object; eye.name='SRC_Face_ElectronicMask_Pixels'; tag(eye)
    objects=[shell,eye]
    for o in objects:
        group=o.vertex_groups.get('head') or o.vertex_groups.new(name='head')
        group.add(list(range(len(o.data.vertices))),1,'REPLACE')
        arm=o.modifiers.new('共享骨架绑定','ARMATURE'); arm.object=rig
    assert original_mesh==([tuple(v.co) for v in head.data.vertices],[tuple(p.vertices) for p in head.data.polygons])
    assert signature(rig)==sig
    bpy.context.scene['electronic_mask_contract']='Copied front dome, +Y 9mm; glasses slot; original v021 geometry, rig and animation unchanged.'
    source=ASSET/'source/chr_bunny01_electronic_mask_model_v001.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(source))

    bpy.ops.object.select_all(action='DESELECT'); copies=[]
    for o in objects:
        dup=o.copy(); dup.data=o.data.copy(); dup.parent=None
        bpy.context.scene.collection.objects.link(dup)
        # Bake only local shape/thickness; head animation is supplied by the
        # existing HeadJoint, so the accessory GLB contains no armature.
        for m in list(dup.modifiers):
            if m.type=='ARMATURE': dup.modifiers.remove(m)
        bpy.context.view_layer.objects.active=dup
        for m in list(dup.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
        dup.data.transform(Matrix.Translation(-pivot) @ dup.matrix_world)
        dup.matrix_world=Matrix.Identity(4); dup.name='MaskShell' if o==shell else 'ExpressionPixels'
        if 'source_polygon_indices' in dup: del dup['source_polygon_indices']
        dup.vertex_groups.clear(); dup.select_set(True); copies.append(dup)
    glb=ASSET/'components/chr_bunny01_electronic_mask_visual.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=False,export_yup=True,export_extras=True)
    bounds=[[min(v.co[i] for o in copies for v in o.data.vertices) for i in range(3)],[max(v.co[i] for o in copies for v in o.data.vertices) for i in range(3)]]
    for o in copies: bpy.data.objects.remove(o,do_unlink=True)
    files=[source,glb,MODEL,ANIMATION]
    ledger={'schema':1,'asset_id':ID,'version':'v001','status':'exported_pending_godot_validation','classification':'child_variant','slot_id':'glasses','variant_id':'electronic_mask','skeleton_id':rig.get('skeleton_id'),'skeleton_sha256':sig,'source_model':str(source.relative_to(ROOT)).replace('\\','/'),'dependency_contract':'Static incremental accessory; v021 model and animation supply the unchanged head rest/poses. No new animation master or clips.','files':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(p),'bytes':p.stat().st_size,'role':'dependency' if p in [MODEL,ANIMATION] else 'output'} for p in files],'attachment_anchor':'VisualRoot/BunnyRig/HeadJoint/FaceAccessorySocket','blender_forward':'+Y','godot_forward':'-Z','root_scale':1,'forward_offset_m':SHIFT,'shell_thickness_m':.004,'pixel_grid':[2,4,14],'pixel_count':112,'source_polygon_count':len(indexes),'blender_local_bounds':bounds,'collision_owner':'scenes/Player3D.tscn','original_source_hashes_preserved':all(sha(Path(p))==s for p,s in before.items()),'validation_status':'not_run'}
    (ASSET/'character_transfer_ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (ASSET/'asset_manifest.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Authoring previews: show original character + authored accessory, excluding
    # chibi variant and all export/preview meshes.
    for o in bpy.data.objects:
        o.hide_render=not (o.name.startswith('SRC_') and o.get('variant_id')!='chibi_anime')
        if o.type=='ARMATURE': o.data.pose_position='REST'
    scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=900; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
    world=bpy.data.worlds.new('MaskPreviewWorld'); world.use_nodes=True
    world.node_tree.nodes.get('Background').inputs[0].default_value=(.075,.085,.11,1)
    world.node_tree.nodes.get('Background').inputs[1].default_value=.4; scene.world=world
    target=Vector((0,0,.79))
    bpy.ops.object.camera_add(location=(0,3,.90)); cam=bpy.context.object; cam.data.type='ORTHO'; scene.camera=cam
    lights=[]
    for pos,power,size in [((-1.2,1.8,2.4),180,1.2),((1.2,1.2,1.4),90,.7),((0,-1.3,1.8),140,1)]:
        bpy.ops.object.light_add(type='AREA',location=pos); l=bpy.context.object; l.data.energy=power; l.data.size=size
        l.rotation_euler=(target-l.location).to_track_quat('-Z','Y').to_euler(); lights.append(l)
    for name,loc,aim,scale in [('front',(0,3,.85),(0,0,.77),1.72),('three_quarter',(1.8,3,1.15),(0,0,.77),1.72),('face_closeup',(.18,3,.93),(0,.1,.77),.86)]:
        cam.location=loc; cam.rotation_euler=(Vector(aim)-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.ortho_scale=scale
        scene.render.filepath=str(ASSET/f'previews/{name}.png'); bpy.ops.render.render(write_still=True)
    print('ELECTRONIC_MASK_AUTHORED:'+json.dumps({'faces':len(indexes),'pixels':112,'bounds':bounds,'original_unchanged':ledger['original_source_hashes_preserved']}))

if __name__=='__main__': main()
