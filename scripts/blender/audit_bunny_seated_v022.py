"""Print the current seated Action's leg-bone contract for the next authored revision."""
import bpy

scene = next(s for s in bpy.data.scenes if s.get("preview_clip") == "seated")
bpy.context.window.scene = scene
rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
action = rig.animation_data.action
print("SEATED_SCENE", scene.name, "ACTION", action.name, "FRAME_RANGE", tuple(action.frame_range))
for frame in (1, 19, 37, 55, 73):
    scene.frame_set(frame)
    print("FRAME", frame)
    for name in ("root", "waist", "chest", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"):
        bone = rig.pose.bones.get(name)
        if bone is None:
            continue
        print(name, "loc", tuple(round(v, 5) for v in bone.location),
              "rot", tuple(round(v, 5) for v in bone.rotation_quaternion),
              "head", tuple(round(v, 5) for v in bone.head),
              "tail", tuple(round(v, 5) for v in bone.tail))
