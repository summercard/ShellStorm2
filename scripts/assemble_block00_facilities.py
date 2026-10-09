"""One-time initialization of authored facility scenes; never overwrite room edits."""
from pathlib import Path
import json,math,hashlib,random
R=Path(__file__).resolve().parents[1];B=R/'assets/art/environments/master_office_3d'
M=B/'source/env_block00_story_rooms/export/v001/import_manifest.json'
m=json.loads(M.read_text('utf8'));by={d['slug']:d for d in m['components']}
v=lambda p:'Vector3('+', '.join(f'{x:.7f}' for x in p)+')'
solid={'sofa','display_case','display_console','side_table','bookcase_fallen','sculpture_foundry','sculpture_turbine','sculpture_pylon'}
for d in m['components']:
 p=R/d['prefab_path'];p.parent.mkdir(parents=True,exist_ok=True)
 s=d['slug'];a=d['bounds_min'];b=d['bounds_max'];size=[b[i]-a[i] for i in range(3)]
 # Sculptures use only the solid pedestal; open steel wings remain walkable.
 box=[size[0],size[2],size[1]];pos=[(a[0]+b[0])/2,(a[2]+b[2])/2,-(a[1]+b[1])/2]
 if s.startswith('sculpture_'):box=[3.8,.55,2.6];pos=[0,.275,0]
 if s=='sofa':box=[2.4,1.65,11.7];pos=[0,.825,0]
 d['collision_policy']='pedestal_box' if s.startswith('sculpture_') else 'fitted_box' if s in solid else 'external_room_boundary' if s=='wall_fractured' else 'visual_only'
 text='[gd_scene load_steps=%d format=3]\n\n'%(3 if s in solid else 2)
 text+='[ext_resource type="PackedScene" path="res://'+d['glb_path']+'" id="1"]\n\n'
 if s in solid:text+='[sub_resource type="BoxShape3D" id="Box"]\nsize = '+v(box)+'\n\n'
 text+='[node name="'+s+'" type="Node3D"]\nmetadata/asset_id = "'+d['asset_id']+'"\nmetadata/asset_version = "'+d['version']+'"\nmetadata/collision_policy = "'+d['collision_policy']+'"\nmetadata/source_blend = "res://'+d['source_path']+'"\nmetadata/semantic_type = "'+('wall_component' if s=='wall_fractured' else 'facility_decoration')+'"\n\n[node name="Visual" parent="." instance=ExtResource("1")]\n'
 if s in solid:text+='\n[node name="Collision" type="StaticBody3D" parent="."]\ncollision_layer = 1\ncollision_mask = 0\n\n[node name="Shape" type="CollisionShape3D" parent="Collision"]\nposition = '+v(pos)+'\nshape = SubResource("Box")\n'
 assert not p.exists(),p
 p.write_text(text,encoding='utf8')
 ip=R/(d['glb_path']+'.import');res='res://'+d['glb_path'];cache='res://.godot/imported/'+Path(d['glb_path']).name+'-'+hashlib.md5(res.encode()).hexdigest()+'.scn'
 ip.write_text('[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="'+cache+'"\n\n[deps]\nsource_file="'+res+'"\ndest_files=["'+cache+'"]\n\n[params]\nnodes/root_scale=1.0\nmeshes/generate_lods=false\nmeshes/ensure_tangents=true\nanimation/import=false\nimport_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"\ngltf/embedded_image_handling=0\n',encoding='utf8')
inst=json.loads((B/'source/env_block00_story_rooms/v001/component_instances.json').read_text('utf8'))['instances']
inst=[i for i in inst if i['slug'] in by]
def add(s,r,p,angle=0):inst.append({'instance_id':'added_%s_%03d'%(s,len(inst)),'slug':s,'room_id':r,'position_m':p,'rotation_euler_rad':[0,0,angle],'source':'user_requested_reuse'})
add('rubble_large','meeting_room',[-19,-.9,.08],.3);add('rubble_large','meeting_room',[8,6,.08],1.7)
# Cabinets run along the narrow third room; leave its east-west doorway band clear.
add('bookcase_fallen','corridor',[17.1,-6.1,.08],math.pi/2)
add('bookcase_fallen','lobby',[24,-3.45,.08],-.1)
rng=random.Random(980034)
for room,cx,cy in [('corridor',17.6,-7.2),('lobby',25,-3.2)]:
 for k in range(12):add('rubble_large' if k<5 else 'rubble_small',room,[cx+rng.uniform(-1.1,1.1),cy+rng.uniform(-1.2,1.2),.08],rng.uniform(-3,3))
centers={'master_office':[-32.5,0],'meeting_room':[-5,2.5],'corridor':[17.5,0],'lobby':[27.5,2.5]}
layouts=[]
for room,center in centers.items():
 rows=[i for i in inst if i['room_id']==room];slugs=sorted(set(i['slug'] for i in rows));ids={s:str(j+1) for j,s in enumerate(slugs)}
 p=B/'runtime/room_instances'/room/(room+'_facilities.tscn');p.parent.mkdir(parents=True,exist_ok=True);assert not p.exists(),p
 text='[gd_scene load_steps=%d format=3]\n\n'%(len(slugs)+1)
 for s in slugs:text+='[ext_resource type="PackedScene" path="res://'+by[s]['prefab_path']+'" id="'+ids[s]+'"]\n'
 text+='\n[node name="AuthoredFacilities" type="Node3D"]\nmetadata/room_id = "'+room+'"\nmetadata/facility_count = '+str(len(rows))+'\n'
 for j,i in enumerate(rows):
  x,y,z=i['position_m'];rx,ry,rz=i['rotation_euler_rad']
  # Source rotations are Z only except fallen decor: use basis conversion for full Euler.
  import numpy as np
  def rot(axis,t):
   c=math.cos(t);s=math.sin(t)
   return np.array([[1,0,0],[0,c,-s],[0,s,c]]) if axis==0 else np.array([[c,0,s],[0,1,0],[-s,0,c]]) if axis==1 else np.array([[c,-s,0],[s,c,0],[0,0,1]])
  cv=np.array([[1,0,0],[0,0,1],[0,-1,0]]);mat=cv@rot(2,rz)@rot(1,ry)@rot(0,rx)@cv.T
  nums=list(mat.T.flatten())+[x-center[0],z,-(y-center[1])]
  text+='\n[node name="%s_%03d" parent="." instance=ExtResource("%s")]\ntransform = Transform3D(%s)\nmetadata/placement_source = "%s"\n'%(i['slug'],j,ids[i['slug']],', '.join(f'{n:.7f}' for n in nums),i['source'])
 p.write_text(text,encoding='utf8');layouts.append({'room_id':room,'scene_path':str(p.relative_to(R)).replace('\\','/'),'instances':len(rows)})
m['rooms']=layouts;m['placements']=inst
M.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf8')
pal=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import';t=pal.read_text('utf8');pal.write_text(t.replace('compress/mode=2','compress/mode=0').replace('mipmaps/generate=true','mipmaps/generate=false'),encoding='utf8')
ig=R/'.gitignore';t=ig.read_text('utf8');rule='!assets/art/environments/master_office_3d/components/**/*.glb.import'
if rule not in t:ig.write_text(t+'\n# 98F facilities reproducible palette import contracts\n'+rule+'\n!assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import\n',encoding='utf8')
print('FACILITY_SCENES_CREATED',len(by),layouts)
