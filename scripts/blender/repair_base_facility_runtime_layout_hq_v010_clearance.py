from pathlib import Path
import importlib.util
import bpy

PROJECT=Path("/Users/summercards/ShellStorm2")
BLEND=PROJECT/"source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v010.blend"
spec=importlib.util.spec_from_file_location("v010",PROJECT/"scripts/blender/build_base_facility_runtime_layout_hq_v010.py")
v010=importlib.util.module_from_spec(spec); spec.loader.exec_module(v010)

def shift_package(slug, dx):
    root=bpy.data.collections[v010.OUT10]
    pack=next(p for p in v010.leaf_packages(root) if p.get("资产包键")==slug)
    for obj in pack.objects:
        obj.location.x += dx
        src=bpy.data.objects.get(obj.name+"__源")
        if src: src.location.x += dx

def main():
    if Path(bpy.data.filepath).resolve()!=BLEND.resolve(): raise RuntimeError("open v010")
    # Establish >0.2m clearance to the east stair side beam.
    shift_package("loft_storage_crate_01",-.15)
    shift_package("loft_storage_crate_02",-.25)
    root=bpy.data.collections[v010.OUT10]
    v010.write_catalog(root)
    bpy.context.scene["v010_east_stair_storage_clearance_m"]=0.215
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    for cam,name in (("基地微缩模型_英雄相机","base_facility_runtime_layout_hq_v010.png"),("基地微缩模型_顶视相机","base_facility_runtime_layout_hq_v010_top.png"),("基地微缩模型_二楼参考验收相机","base_facility_runtime_layout_hq_v010_loft_facilities.png")):
        v010.render(bpy.data.objects[cam],v010.VERIFY/name)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print("V010_CLEARANCE_REPAIRED")

if __name__=="__main__": main()
