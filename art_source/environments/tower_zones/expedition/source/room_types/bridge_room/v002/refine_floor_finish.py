import bpy,math,json
from pathlib import Path
p=Path(bpy.data.filepath).parent
for o in bpy.data.objects:
    if o.type!='MESH': continue
    is_source=o.name.startswith('分块耐磨钢板')
    is_output=o.name.startswith('地砖_') and o.name.endswith('_主体')
    if not (is_source or is_output): continue
    uv=o.data.uv_layers.get('PaletteUV')
    if is_source:
        o.data.materials.clear();o.data.materials.append(bpy.data.materials['01_精工金属_紫色骨架']);o['material_role']=0;o['palette_cell']=[9,1]
    for f in o.data.polygons:
        if is_source or (f.area>1 and f.normal.z>.9):
            f.material_index=0
            for j,li in enumerate(f.loop_indices):
                a=j*math.pi*2/len(f.loop_indices); uv.data[li].uv=(.95+.022*math.cos(a),.85+.022*math.sin(a))
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('FLOOR_FINISH_UNIFIED')
