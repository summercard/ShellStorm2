import bpy,json
from pathlib import Path
O=Path(__file__).resolve().parents[1]
p=O/'reference_assembly.json';data=json.loads(p.read_text())
for i,x in enumerate(data['placements']):
    if x['slug']=='plant_large':position=[4.6,-9.5,0]
    elif x['slug']=='plant_small' and x['position'][0]>0:position=[10.7,-9.5,0]
    else:continue
    x['position']=position;bpy.data.objects[f'拼装_{x["slug"]}_{i:03}'].location=position
p.write_text(json.dumps(data,ensure_ascii=False,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
