import json,hashlib,shutil,math
from pathlib import Path
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001';B=R/'assets/art/environments/rooftop_courtyard_3d';V=O/'runtime_probe'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
assert m['exported'] and m['source_unchanged']
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return Path(p).relative_to(R).as_posix()
def put(path,text):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text,encoding='utf-8')
def gdv(x):return 'Vector3('+', '.join(str(round(v,7)) for v in x)+')'
component_paths=[]
# Conservative physical geometry; no total courtyard AABB blocker.
for p in m['packages']:
    slug=p['package_id'];glb=Path(p['expected_glb']);rt=B/'runtime'/slug/('prp_'+slug+'_root_top3d.tscn');component_paths.append(rt)
    script='res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd'
    import_path=Path(str(glb)+'.import')
    # Seed reproduction import options; Godot regenerates remap/deps normally.
    put(import_path,'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\nsource_file="res://'+rel(glb)+'"\n\n[params]\nnodes/root_type="Node3D"\nnodes/root_name=""\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=false\nmeshes/light_baking=0\nmaterials/extract=0\nimport_script/path="'+script+'"\ngltf/embedded_image_handling=0\n')
    txt='[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://'+rel(glb)+'" id="1"]\n\n[node name="prp_'+slug+'" type="Node3D"]\nmetadata/package_id = "'+slug+'"\nmetadata/asset_version = "v002"\nmetadata/block_id = "rooftop"\nmetadata/fixed_display_attachment = true\n\n[node name="Visual" parent="." instance=ExtResource("1")]\n'
    # Boxes only for actual solid objects; decorative wires / fans / paper never block.
    if slug in ['courtyard_slab','parapet_back','parapet_left','weathered_wall','timber_deck','corduroy_sofa','side_table','crt_television']:
        dims=p['dimensions'];sx,sz,sy=dims
        if slug=='courtyard_slab':sx,sy,sz=15,.32,10
        elif slug=='timber_deck':sy=.1
        txt=txt.replace('load_steps=2','load_steps=3')
        shape='\n[sub_resource type="BoxShape3D" id="box"]\nsize = '+gdv([sx,sy,sz])+'\n'
        txt=txt.replace('\n[node name="prp_',shape+'\n[node name="prp_',1)
        txt+='\n[node name="Body" type="StaticBody3D" parent="."]\n\n[node name="CollisionShape3D" type="CollisionShape3D" parent="Body"]\nposition = '+gdv([0,sy/2,0])+'\nshape = SubResource("box")\n'
    put(rt,txt);p['prefab']=str(rt);p['prefab_sha256']=sha(rt)
# Aggregate asset references components, never whole-room GLB.
agg=B/'runtime/prp_rooftop_courtyard/prp_rooftop_courtyard_root_top3d.tscn'
motion=B/'runtime/prp_rooftop_courtyard/prp_rooftop_courtyard_motion.gd'
put(motion,'''extends Node3D
# Presentation-only micromotion. No inventory, service, save or gameplay dependency.
var elapsed := 0.0
var _moving: Array[Node3D] = []
var _base: Array[Transform3D] = []
func _ready() -> void:
    for c in get_children():
        if c is Node3D and c.has_meta("motion_spec"):
            _moving.append(c)
            _base.append(c.transform)
    for node in find_children("*", "AnimationPlayer", true, false):
        var ap := node as AnimationPlayer
        for animation in ap.get_animation_list():
            if animation != "RESET":
                ap.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
                ap.play(animation)
                break
func _process(delta: float) -> void:
    elapsed += delta
    for i in _moving.size():
        var c := _moving[i]
        var spec := JSON.parse_string(str(c.get_meta("motion_spec"))) as Array
        c.transform = _base[i]
        for item in spec:
            var kind := str(item.get("type", ""))
            if kind == "rotation":
                var axis := int(item["axis"])
                var vector := Vector3.RIGHT if axis == 0 else (Vector3.BACK if axis == 1 else Vector3.UP)
                c.rotate_object_local(vector, elapsed * TAU * float(item["turns_per_10s"]) / 10.0)
            elif kind == "sway":
                var axis := int(item["axis"])
                var vector := Vector3.RIGHT if axis == 0 else (Vector3.BACK if axis == 1 else Vector3.UP)
                c.rotate_object_local(vector, float(item["amplitude_rad"]) * sin(elapsed * TAU * 24.0 / float(item["period_frames"])))
            elif kind == "tuning":
                c.position.x += float(item["amplitude_m"]) * sin(elapsed * TAU / 10.0)
            elif kind == "breathing_indicator":
                c.scale = Vector3.ONE * (1.0 + float(item["amplitude"]) * sin(elapsed * TAU / 5.0))
            elif kind == "water_ripple":
                var k := 1.0 + float(item["amplitude"]) * sin(elapsed * TAU / 5.0)
                c.scale = Vector3(k,1.0,k)
            elif kind == "tv_static":
                c.position.y += 0.004 * sin(floor(elapsed * 6.0) * 12.31)
    for light in find_children("*", "OmniLight3D", true, false):
        if light.has_meta("base_energy"):
            light.light_energy = float(light.get_meta("base_energy")) * (1.0 + 0.06 * sin(elapsed * 3.7) + 0.02 * sin(elapsed * 11.1))
''')
txt='[gd_scene load_steps='+str(len(component_paths)+2)+' format=3]\n\n'
for i,rt in enumerate(component_paths):txt+='[ext_resource type="PackedScene" path="res://'+rel(rt)+'" id="c'+str(i)+'"]\n'
txt+='[ext_resource type="Script" path="res://'+rel(motion)+'" id="motion"]\n\n[node name="RooftopCourtyard" type="Node3D"]\nscript = ExtResource("motion")\nmetadata/asset_id = "PRP-ROOFTOP-COURTYARD-3D"\nmetadata/asset_version = "v002"\nmetadata/block_id = "rooftop"\nmetadata/floor_range = "100F"\nmetadata/facility_kind = "fixed_decorative_facility"\nmetadata/gameplay_service = false\nmetadata/design_footprint = Vector2(15,10)\n'
for i,p in enumerate(m['packages']):
    x,y,z=p['component_origin_blender'];txt+='\n[node name="'+p['package_id']+'" parent="." instance=ExtResource("c'+str(i)+'")]\nposition = '+gdv([x,z,-y])+'\n'
    if p['animations']:txt+='metadata/motion_spec = '+json.dumps(json.dumps(p['animations']))+'\n'
for name,co,en in [('WarmBulb',[-2.23,2.64,-.65],1.1),('WarmTableLamp',[2.43,1.21,-.14],.6),('WarmRadio',[-.86,1.7,-2.39],.18)]:
    txt+='\n[node name="'+name+'" type="OmniLight3D" parent="."]\nposition = '+gdv(co)+'\nlight_color = Color(1,0.58,0.2,1)\nlight_energy = '+str(en)+'\nomni_range = 3.0\nmetadata/base_energy = '+str(en)+'\n'
put(agg,txt)
m['runtime_prefab']=str(agg);m['runtime_script']=str(motion);m['prefab_sha256']=sha(agg);m['runtime_integrated']=False;m['runtime_status']='exported_pending_godot_validation'
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
# Isolated probe project: no game autoload, saves or production import cache access.
for path in [*B.rglob('*.glb'),*B.rglob('*.glb.import'),*B.rglob('*.tscn'),*B.rglob('*.gd'),R/'tools/asset_pipeline/scene_facility_shared_palette_post_import.gd',Path(m['palette'])]:
    dest=V/path.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,dest)
put(V/'project.godot','config_version=5\n[application]\nconfig/name="Rooftop courtyard isolated acceptance"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[display]\nwindow/size/viewport_width=1400\nwindow/size/viewport_height=1000\n')
put(V/'verify.gd','''extends SceneTree
var frames := 0
var model: Node3D
func _initialize() -> void:
    var scene := load("res://'''+rel(agg)+'''") as PackedScene
    assert(scene != null)
    model = scene.instantiate()
    root.add_child(model)
    call_deferred("check")
func check() -> void:
    var meshes := model.find_children("*", "MeshInstance3D", true, false)
    var triangle_count := 0
    var material_names: Dictionary = {}
    for node in meshes:
        var mi := node as MeshInstance3D
        assert(mi.mesh != null)
        for i in mi.mesh.get_surface_count():
            var arrays := mi.mesh.surface_get_arrays(i)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            triangle_count += indices.size()/3
            var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
            assert(mat != null and mat.albedo_texture != null)
            assert(mat.albedo_texture.resource_path == "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
            material_names[mat.resource_name] = true
    assert(triangle_count < 200000)
    assert(model.get_child_count() >= 73)
    print("COURTYARD_RUNTIME_OK ",JSON.stringify({"triangles":triangle_count,"meshes":meshes.size(),"components":model.get_child_count(),"materials":material_names.size(),"production_scene_modified":false}))
    model.queue_free()
    call_deferred("finish")
func finish() -> void:
    quit(0)
''')
print('COURTYARD_PACKAGING_OK',len(component_paths),str(agg))
