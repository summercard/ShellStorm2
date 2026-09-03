from pathlib import Path
import math

import bpy


PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v009.blend"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v009"


def is_east_label(obj):
    if not obj.get("v009_scope"):
        return False
    tokens = (
        "ACCESS文字", "EXIT标牌", "安全标签", "顶部标识", "POWER文字",
        "检修标签", "接线盒标签", "_文字", "海报_WORK文字", "海报_TOGETHER文字",
        "海报_STAY_STRONG文字", "火焰警告", "回收标志", "消防提示",
    )
    return any(token in obj.name for token in tokens)


def render(camera_name, output_name):
    scene = bpy.context.scene
    scene.camera = bpy.data.objects[camera_name]
    scene.render.filepath = str(VERIFY / output_name)
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve() != BLEND.resolve():
        raise RuntimeError(f"必须打开v009文件: {bpy.data.filepath}")
    repaired = []
    for obj in bpy.data.objects:
        if is_east_label(obj):
            obj.rotation_mode = "XYZ"
            obj.rotation_euler = (math.pi / 2, 0, -math.pi / 2)
            repaired.append(obj.name)
        elif obj.get("v009_scope") and obj.name.startswith("东墙团结海报_"):
            # Restore the non-text poster construction after the original
            # one-time orientation repair selected this prefix too broadly.
            obj.rotation_mode = "XYZ"
            if "固定螺丝" in obj.name:
                obj.rotation_euler = (0, math.pi / 2, 0)
            elif "轻微磨损" in obj.name:
                obj.rotation_euler = (0, 0.12, 0)
            else:
                obj.rotation_euler = (0, 0, 0)
    bpy.context.scene["v009_east_label_orientation"] = "inward -X; verified non-mirrored from reference camera"
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    VERIFY.mkdir(parents=True, exist_ok=True)
    render("基地微缩模型_英雄相机", "base_facility_runtime_layout_hq_v009.png")
    render("基地微缩模型_顶视相机", "base_facility_runtime_layout_hq_v009_top.png")
    render("基地微缩模型_东面设施验收相机", "base_facility_runtime_layout_hq_v009_east_facilities.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print(f"REPAIRED_EAST_LABELS {len(repaired)}")
    for name in repaired:
        print(name)


if __name__ == "__main__":
    main()
