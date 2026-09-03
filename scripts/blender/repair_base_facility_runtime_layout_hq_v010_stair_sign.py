from pathlib import Path
import importlib.util, math
import bpy

PROJECT=Path("/Users/summercards/ShellStorm2")
BLEND=PROJECT/"source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v010.blend"
spec=importlib.util.spec_from_file_location("v010",PROJECT/"scripts/blender/build_base_facility_runtime_layout_hq_v010.py")
v010=importlib.util.module_from_spec(spec); spec.loader.exec_module(v010)

def main():
    for name in ("L梯v010_STAY_CURIOUS标识_自发光","L梯v010_STAY_CURIOUS标识_自发光__源"):
        obj=bpy.data.objects.get(name)
        if obj: obj.rotation_mode="XYZ"; obj.rotation_euler=(math.pi/2,0,-math.pi/2)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    v010.render(bpy.data.objects["基地微缩模型_楼梯接口验收相机"],v010.VERIFY/"base_facility_runtime_layout_hq_v010_stair_interfaces.png")
    v010.render(bpy.data.objects["基地微缩模型_二楼参考验收相机"],v010.VERIFY/"base_facility_runtime_layout_hq_v010_loft_facilities.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print("V010_STAIR_SIGN_REPAIRED")

if __name__=="__main__": main()
