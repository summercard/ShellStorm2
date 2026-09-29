"""Extend the original bunny animation source with an alternating ladder climb loop."""
from pathlib import Path

import bpy

source = Path(bpy.data.filepath).resolve()
assert source.name == "chr_bunny01_animation_v023.blend", source
target = source.parents[2].parent / "v024/source/animation/chr_bunny01_animation_v024.blend"
target.parent.mkdir(parents=True, exist_ok=True)

scene = next(s for s in bpy.data.scenes if s.get("preview_clip") == "moving")
bpy.context.window.scene = scene
rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
original = next(a for a in bpy.data.actions if a.get("state_id") == "moving")
action = original.copy()
action.name = "anim_bunny01_climbing_v024"
action["state_id"] = "climbing"
action["duration"] = 0.8
action["loop"] = True
action.use_fake_user = True
rig.animation_data.action = action

for frame, phase in ((1, 0), (13, 1), (25, 0), (37, 1), (49, 0)):
    scene.frame_set(frame)
    for suffix, side in (("l", 1), ("r", -1)):
        hand = rig.pose.bones[f"hand_{suffix}"]
        foot = rig.pose.bones[f"foot_{suffix}"]
        hand.location.y = 0.32
        hand.location.z = 0.31 * side * (1 if phase == 0 else -1)
        foot.location.y = 0.17
        foot.location.z = 0.24 * side * (1 if phase == 1 else -1)
        hand.keyframe_insert(data_path="location", frame=frame, group=hand.name)
        foot.keyframe_insert(data_path="location", frame=frame, group=foot.name)

scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(target))
print("CLIMBING_V024_AUTHORED", target)
