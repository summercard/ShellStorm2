"""从既有抠图裁切运行纹理，并冻结本件家具/粒子节点；不创作新图。"""
from pathlib import Path
import hashlib
import json
from PIL import Image
ROOT = Path(__file__).resolve().parents[6]
SOURCE = Path(__file__).resolve().parent
TEXTURES = ROOT / 'assets/art/vfx/textures'
PREFAB = ROOT / 'assets/art/vfx/combat_3d/vfx_fat_entry_breach_root_top3d.tscn'
VISUALS = [
 'assets/art/environments/tower_zones/expedition/components/room_type_components/boss_room/chair/chair_visual_top3d.glb',
 'assets/art/environments/rooftop_courtyard_3d/components/side_table/prp_side_table_visual_top3d.glb',
 'assets/art/environments/tower_zones/expedition/components/room_type_components/office_room/locker_bank/locker_bank_visual_top3d.glb',
]

def build():
    assert TEXTURES.is_dir() and PREFAB.parent.is_dir()
    sheet = Image.open(SOURCE / 'sprite_sheet_matted.png').convert('RGBA')
    manifest_path = SOURCE / 'asset_manifest.json'
    previous = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    previous_textures = {row['path']: row for row in previous.get('textures', [])}
    stats = []
    for name, box in [('flame_a',(0,0,512,512)),('flame_b',(512,0,1024,512)),('smoke',(0,512,512,1024)),('dust',(512,512,1024,1024))]:
        round_source = SOURCE / ('flame_round_' + name[-1] + '.png')
        if name.startswith('flame_') and round_source.exists():
            image = Image.open(round_source)
            assert image.mode == 'RGBA' and image.size == (384, 384), name
            path = TEXTURES / ('vfx_fat_entry_breach_' + name + '.png')
            path.write_bytes(round_source.read_bytes())
            row = dict(previous_textures.get(path.relative_to(ROOT).as_posix(), {}))
            row.update({'path':path.relative_to(ROOT).as_posix(), 'source_final':round_source.name, 'size':[384,384], 'alpha_extrema':image.getchannel('A').getextrema(), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
            stats.append(row)
            continue
        image = sheet.crop(box)
        alpha = image.getchannel('A')
        # 抠图服务保留了极弱背景透明度；只裁主体包络，保留软边和空白边距。
        bbox = alpha.point(lambda x: 255 if x > 6 else 0).getbbox()
        assert bbox, name
        bbox = (max(0,bbox[0]-10),max(0,bbox[1]-10),min(512,bbox[2]+10),min(512,bbox[3]+10))
        image = image.crop(bbox)
        image.thumbnail((384,384), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA',(384,384))
        canvas.paste(image,((384-image.width)//2,(384-image.height)//2))
        path = TEXTURES / ('vfx_fat_entry_breach_'+name+'.png')
        canvas.save(path,optimize=True)
        stats.append({'path':path.relative_to(ROOT).as_posix(), 'crop':bbox, 'size':[384,384], 'alpha_extrema':canvas.getchannel('A').getextrema(), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    text = ['[gd_scene format=3]', '', '[ext_resource type="Script" path="res://src/vfx/VfxFatEntryBreach3D.gd" id="script"]']
    for i,path in enumerate(VISUALS):
        text.append(f'[ext_resource type="PackedScene" path="res://{path}" id="visual{i}"]')
    for name in ['flame_a','flame_b','smoke','dust']:
        text.append(f'[ext_resource type="Texture2D" path="res://assets/art/vfx/textures/vfx_fat_entry_breach_{name}.png" id="{name}"]')
    for name in ['flame_a','flame_b','smoke','dust']:
        text += [f'\n[sub_resource type="StandardMaterial3D" id="mat_{name}"]', 'transparency = 1','shading_mode = 0','vertex_color_use_as_albedo = true',f'albedo_texture = ExtResource("{name}")','billboard_mode = 1','cull_mode = 2','disable_receive_shadows = true',f'\n[sub_resource type="QuadMesh" id="quad_{name}"]',f'material = SubResource("mat_{name}")','size = Vector2(1, 1)']
    text += ['\n[sub_resource type="Gradient" id="fade"]','offsets = PackedFloat32Array(0, 0.12, 0.65, 1)','colors = PackedColorArray(1,1,1,0, 1,1,1,1, 1,1,1,0.7, 1,1,1,0)', '\n[sub_resource type="GradientTexture1D" id="fade_texture"]','gradient = SubResource("fade")']
    profiles = {'blast':(2.4,3.6,2.8,4.8,0.3,0.95), 'flame':(.55,1.05,.2,.7,.4,.94),'smoke':(.65,1.20,.2,.6,.65,.55),'dust':(1.1,1.9,.5,1.2,.35,.8)}
    for name,(lo,hi,vlo,vhi,g,opacity) in profiles.items():
        text += [f'\n[sub_resource type="ParticleProcessMaterial" id="process_{name}"]','resource_local_to_scene = true','emission_shape = 1','emission_sphere_radius = 0.16','direction = Vector3(0, 1, 0)',f'spread = {85 if name in ["blast","dust"] else 28}.0',f'initial_velocity_min = {vlo}',f'initial_velocity_max = {vhi}',f'gravity = Vector3(0, {g}, 0)',f'scale_min = {lo}',f'scale_max = {hi}','angle_min = -25.0','angle_max = 25.0','angular_velocity_min = -45.0','angular_velocity_max = 45.0','color_ramp = SubResource("fade_texture")']
    text += ['\n[node name="VfxFatEntryBreach3D" type="Node3D"]','script = ExtResource("script")','lifetime = 3.65','metadata/asset_id = "VFX-FAT-ENTRY-BREACH-3D"','metadata/asset_version = "v001"','metadata/asset_category = "combat_vfx"','metadata/prefab_path = "res://assets/art/vfx/combat_3d/vfx_fat_entry_breach_root_top3d.tscn"','metadata/source_manifest = "art_source/vfx/combat_3d/fat_entry_breach/source/v001/asset_manifest.json"','metadata/runtime_save_excluded = true','metadata/visual_only = true','metadata/collision_policy = "none"','metadata/particle_budget = 92','metadata/default_landing_distance_m = 4.0','metadata/initial_layout = "固定五角；桌柜长轴径向；中心半径1.56m"','metadata/push_radius_max_m = 1.72','metadata/host_min_landing_distance_m = 3.5','metadata/host_envelope_m = 1.25','metadata/host_max_height_m = 5.7','metadata/origin = "地面爆心；局部-Z对齐forward"','\n[node name="Furniture" type="Node3D" parent="."]']
    for i,visual in enumerate([0,1,2,0,1]):
        ratio = [0.68,1.0,0.68,0.68,1.0][i]
        text += [f'\n[node name="Piece{i}" type="Node3D" parent="Furniture"]',f'\n[node name="Visual" parent="Furniture/Piece{i}" instance=ExtResource("visual{visual}")]',f'scale = Vector3({ratio}, {ratio}, {ratio})']
    text += ['\n[node name="Trails" type="Node3D" parent="."]','\n[node name="Impacts" type="Node3D" parent="."]']
    def emitter(name,parent,profile,texture,amount,life,one_shot):
        lo,hi,vlo,vhi,g,opacity=profiles[profile]
        text.extend([f'\n[node name="{name}" type="GPUParticles3D" parent="{parent}"]','emitting = false',f'amount = {amount}',f'lifetime = {life}',f'one_shot = {str(one_shot).lower()}',f'explosiveness = {1.0 if one_shot else 0.0}','randomness = 0.25','local_coords = false','fixed_fps = 60','interpolate = true','use_fixed_seed = true','seed = 20261116','cast_shadow = 0','visibility_aabb = AABB(-12, -6, -12, 24, 18, 24)',f'process_material = SubResource("process_{profile}")',f'draw_pass_1 = SubResource("quad_{texture}")',f'metadata/scale_min = {lo}',f'metadata/scale_max = {hi}',f'metadata/speed_min = {vlo}',f'metadata/speed_max = {vhi}',f'metadata/gravity_y = {g}',f'metadata/opacity = {opacity}'])
    emitter('Blast','.','blast','flame_b',12,.65,True)
    for i in range(5):
        emitter(f'Flame{i}','Trails','flame','flame_a' if i%2==0 else 'flame_b',6,.42,False)
        emitter(f'Smoke{i}','Trails','smoke','smoke',6,.72,False)
        emitter(f'Dust{i}','Impacts','dust','dust',4,1.3,True)
    text += ['\n[node name="BreachLight" type="OmniLight3D" parent="."]','visible = false','light_color = Color(1, 0.48, 0.12, 1)','light_energy = 0.0','shadow_enabled = false','omni_range = 5.0']
    PREFAB.write_text('\n'.join(text)+'\n',encoding='utf-8')
    manifest = {'asset_id':'VFX-FAT-ENTRY-BREACH-3D','version':'v001','prefab':PREFAB.relative_to(ROOT).as_posix(), 'script':'src/vfx/VfxFatEntryBreach3D.gd','generation_source':{'provided_original':'Create_a_technical_VFX_sprite__2026-11-16T05-03-01.png','generator':'用户上游图片能力生成；本子任务没有生成新美术','original_mode':'RGB，无真实alpha','matting_operation':'buddy-image-processing matting 白底去除','matting_task_id':'1439661065-ProcessImageAsync-73b922078fe47fa418f73681027fddedt','original':'generated_sprite_sheet_original.png','matted':'sprite_sheet_matted.png','matting_note':'整图抠图漏掉烟尘，分别裁切原图下两格后单独抠图并合并，未生成新图','smoke_matting_task_id':'1439661065-ProcessImageAsync-62e348b57685186b16e3bf8d6203bb64t','dust_matting_task_id':'1439661065-ProcessImageAsync-0d1d680aaaedb29b71340645ab77abf0t'},'textures':stats,'visual_glbs':VISUALS,'visual_scales':[.68,1,.68,.68,1],'piece_count':5,'triangle_count':3996,'particle_budget':92,'lifetime_sec':3.65,'stages_sec':{'push':[0,.4],'burst':[.4,1.05],'flight':[.4,1.91],'impact_and_settle':[1.52,2.21],'tail_dust':[2.21,3.3],'retire':3.65},'context':{'seed':20261116,'floor_y':'世界高度，缺省出生点Y','forward':'XZ方向，局部-Z对齐','landing_distance_m':'缺省4m，爆心到落点中心的米数；Host提供合法距离，不进行物理查询'},'safety':{'visual_only':True,'collision':False,'damage':False,'drops':False,'real_furniture_mutation':False,'light_count':1,'shadows':False},'host_integration':'由主线程负责；本子任务不修改Host或账本','rebuild':'python art_source/vfx/combat_3d/fat_entry_breach/source/v001/build_prefab.py'}
    manifest_path = SOURCE / 'asset_manifest.json'
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding='utf-8'))
        for key in ['verification', 'ledger', 'geometry_contract', 'dependencies_sha256', 'flame_texture_revision', 'flame_texture_design', 'flame_generation_source', 'host_integration', 'context']:
            if key in previous:
                manifest[key] = previous[key]
        for row in stats:
            manifest.setdefault('dependencies_sha256', {})[row['path']] = row['sha256']
        manifest['dependencies_sha256'][PREFAB.relative_to(ROOT).as_posix()] = hashlib.sha256(PREFAB.read_bytes()).hexdigest()
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(stats,ensure_ascii=False))
if __name__=='__main__':
    build()
