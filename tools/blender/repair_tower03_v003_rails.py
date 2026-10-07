"""修复 v003 中导出规范化后低于 82% 的两个天台护栏，仍只写 v003 独立候选。"""
from __future__ import annotations
import bpy
from pathlib import Path

ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2')
SOURCE=ROOT/'assets/art/environments/open_world/source/tower_03/export/v001/env_tower_03-v001-runtime.blend'
BLEND=ROOT/'assets/art/environments/open_world/source/tower_03/export/v003/env_tower_03-v003-runtime_optimized.blend'
TARGETS=('上层周界护栏_1','上层周界护栏_3')

def main():
    assert Path(bpy.data.filepath).resolve()==BLEND.resolve()
    loaded=[]
    with bpy.data.libraries.load(str(SOURCE),link=False) as (data_from,data_to):
        data_to.objects=[name for name in TARGETS if name in data_from.objects]
    for src in list(data_to.objects):
        assert src is not None and src.name.split('.')[0] in TARGETS,src
        target=bpy.data.objects.get(src.name.split('.')[0])
        assert target is not None,target
        old=target.data
        target.data=src.data.copy()
        for index,slot in enumerate(target.material_slots):
            source_slot=target.data.materials[index] if index<len(target.data.materials) else None
            if source_slot:
                base=source_slot.name.split('.')[0]
                target.data.materials[index]=bpy.data.materials.get(base) or source_slot
        target.data.uv_layers.active=target.data.uv_layers.get('PaletteUV')
        if target.data.uv_layers.active: target.data.uv_layers.active.active_render=True
        bpy.data.objects.remove(src,do_unlink=True)
        if old.users==0:bpy.data.meshes.remove(old)
        loaded.append(target.name)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print('REPAIRED',loaded,flush=True)

if __name__=='__main__':main()
