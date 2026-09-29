"""Author forward-extended seated feet in a new v023 animation source."""
from pathlib import Path

import bpy

source = Path(bpy.data.filepath).resolve()
assert source.name == "chr_bunny01_animation_v022.blend", source
target = source.parents[2].parent / "v023/source/animation/chr_bunny01_animation_v023.blend"
target.parent.mkdir(parents=True, exist_ok=True)

scene = next(s for s in bpy.data.scenes if s.get("preview_clip") == "seated")
bpy.context.window.scene = scene
rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
action = rig.animation_data.action
assert action.get("state_id") == "seated"
action.name = "anim_bunny01_seated_v023"

# The bunny has intentionally detached shoes. Preserve their vertical seated
# height and lateral spacing; key both shoes out in front of the seat (+Y).
for frame in (1, 19, 37, 55, 73):
    scene.frame_set(frame)
    for suffix in ("l", "r"):
        foot = rig.pose.bones[f"foot_{suffix}"]
        foot.location.y = 0.72
        foot.keyframe_insert(data_path="location", frame=frame, group=foot.name)

scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(target))
print("SEATED_V023_AUTHORED", target)
