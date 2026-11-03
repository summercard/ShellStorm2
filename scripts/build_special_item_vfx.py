"""Build stable, editable prefab geometry offline; gameplay only routes AssetIDs."""
import math
from special_items_workspace import write

BASE='assets/art/vfx/combat_3d/'
fire='''[gd_scene load_steps=8 format=3]
[ext_resource type="Script" path="res://src/vfx/VfxSpecialFire3D.gd" id="1"]
[sub_resource type="StandardMaterial3D" id="outer"]
shading_mode = 0
albedo_color = Color(1, 0.19, 0.015, 1)
emission_enabled = true
emission = Color(1, 0.09, 0.005, 1)
emission_energy_multiplier = 1.8
[sub_resource type="StandardMaterial3D" id="inner"]
shading_mode = 0
albedo_color = Color(1, 0.82, 0.18, 1)
emission_enabled = true
emission = Color(1, 0.56, 0.04, 1)
emission_energy_multiplier = 1.6
[sub_resource type="StandardMaterial3D" id="char"]
transparency = 1
albedo_color = Color(0.055, 0.022, 0.008, 0.72)
roughness = 1.0
[sub_resource type="CylinderMesh" id="flame"]
material = SubResource("outer")
top_radius = 0.025
bottom_radius = 0.22
height = 0.85
radial_segments = 7
[sub_resource type="SphereMesh" id="core"]
material = SubResource("inner")
radius = 0.15
height = 0.48
radial_segments = 8
rings = 4
[sub_resource type="CylinderMesh" id="scorch"]
material = SubResource("char")
top_radius = 1.0
bottom_radius = 1.0
height = 0.006
radial_segments = 24
[node name="VfxSpecialFire3D" type="Node3D"]
script = ExtResource("1")
metadata/asset_id = "VFX-SPECIAL-FIRE-3D"
metadata/asset_version = "v001"
[node name="Scorch" type="MeshInstance3D" parent="."]
mesh = SubResource("scorch")
cast_shadow = 0
[node name="Flames" type="Node3D" parent="."]
'''
for i in range(9):
    angle=i*math.tau/8
    radius=.64 if i<8 else 0
    x=math.cos(angle)*radius;z=math.sin(angle)*radius
    fire+=f'''[node name="Flame{i}" type="Node3D" parent="Flames"]
position = Vector3({x:.5f}, 0, {z:.5f})
[node name="Tongue" type="MeshInstance3D" parent="Flames/Flame{i}"]
position = Vector3(0, 0.43, 0)
rotation = Vector3(0.1, {angle:.5f}, 0.17)
mesh = SubResource("flame")
cast_shadow = 0
[node name="HotCore" type="MeshInstance3D" parent="Flames/Flame{i}"]
position = Vector3(0, 0.22, -0.025)
mesh = SubResource("core")
cast_shadow = 0
'''
fire+='''[node name="FireLight" type="OmniLight3D" parent="."]
position = Vector3(0, 0.55, 0)
light_color = Color(1, 0.33, 0.035, 1)
light_energy = 0.0
shadow_enabled = false
'''
write(BASE+'vfx_special_fire_root_top3d.tscn',fire)

write('assets/art/vfx/special_items/oil_surface.gdshader','''shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float angle = atan(p.y, p.x);
    float rim = 0.86 + sin(angle * 7.0) * 0.05 + cos(angle * 11.0) * 0.03;
    float d = length(p);
    ALPHA = (1.0 - smoothstep(rim - 0.1, rim, d)) * 0.92;
    float slick = sin(p.x * 9.0 + p.y * 7.0 + sin(p.y * 12.0) + TIME * 0.25);
    ALBEDO = mix(vec3(0.018, 0.026, 0.035), vec3(0.11, 0.22, 0.24), slick * 0.5 + 0.5);
    METALLIC = 0.5;
    ROUGHNESS = 0.16;
    EMISSION = vec3(0.02, 0.055, 0.06) * smoothstep(0.65, 0.83, d);
}
''')
write(BASE+'vfx_special_oil_root_top3d.tscn','''[gd_scene load_steps=5 format=3]
[ext_resource type="Script" path="res://src/vfx/VfxSpecialOil3D.gd" id="1"]
[ext_resource type="Shader" path="res://assets/art/vfx/special_items/oil_surface.gdshader" id="2"]
[sub_resource type="ShaderMaterial" id="oil"]
shader = ExtResource("2")
[sub_resource type="PlaneMesh" id="surface"]
material = SubResource("oil")
size = Vector2(2, 2)
[node name="VfxSpecialOil3D" type="Node3D"]
script = ExtResource("1")
metadata/asset_id = "VFX-SPECIAL-OIL-3D"
metadata/asset_version = "v001"
[node name="OilSurface" type="MeshInstance3D" parent="."]
mesh = SubResource("surface")
cast_shadow = 0
''')
blast='''[gd_scene load_steps=7 format=3]
[ext_resource type="Script" path="res://src/vfx/VfxSpecialBlast3D.gd" id="1"]
[sub_resource type="StandardMaterial3D" id="hot"]
shading_mode = 0
albedo_color = Color(1, 0.5, 0.035, 1)
emission_enabled = true
emission = Color(1, 0.26, 0.01, 1)
emission_energy_multiplier = 3.0
[sub_resource type="StandardMaterial3D" id="dark"]
albedo_color = Color(0.14, 0.10, 0.07, 1)
roughness = 0.9
[sub_resource type="TorusMesh" id="ring"]
material = SubResource("hot")
inner_radius = 0.92
outer_radius = 1.0
rings = 32
ring_segments = 6
[sub_resource type="SphereMesh" id="core"]
material = SubResource("hot")
radius = 0.5
height = 0.7
radial_segments = 12
rings = 5
[sub_resource type="BoxMesh" id="debris"]
material = SubResource("dark")
size = Vector3(0.12, 0.12, 0.12)
[node name="VfxSpecialBlast3D" type="Node3D"]
script = ExtResource("1")
metadata/asset_id = "VFX-SPECIAL-BLAST-3D"
metadata/asset_version = "v001"
[node name="Shockwave" type="MeshInstance3D" parent="."]
mesh = SubResource("ring")
cast_shadow = 0
[node name="Core" type="MeshInstance3D" parent="."]
position = Vector3(0, 0.2, 0)
mesh = SubResource("core")
cast_shadow = 0
[node name="Debris" type="Node3D" parent="."]
'''
for i in range(10):
    blast+=f'''[node name="D{i}" type="MeshInstance3D" parent="Debris"]
mesh = SubResource("debris")
cast_shadow = 0
'''
blast+='''[node name="BlastLight" type="OmniLight3D" parent="."]
position = Vector3(0, 0.65, 0)
light_color = Color(1, 0.48, 0.08, 1)
light_energy = 0.0
shadow_enabled = false
'''
write(BASE+'vfx_special_blast_root_top3d.tscn',blast)
print('SPECIAL_ITEM_VFX_PREFABS_OK')
