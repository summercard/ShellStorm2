"""Restore only Boss002's runtime move clip from the verified v031 source."""
import bpy
import json
from pathlib import Path
from mathutils import Matrix

ROOT = Path("I:/工作项目/shellstrom2/ShellStorm2")
BOSS = ROOT / "assets/art/enemies/bosses/enm_boss_monitor002"
COMPONENTS = BOSS / "components/enm_boss_monitor002"
SOURCE = BOSS / "source/enm_boss_monitor002_animation_v031.blend"
CONVERSION = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.data.scenes["BOSS002_STUDIO"]
bpy.context.window_manager.windows[0].scene = scene
rig = bpy.data.objects["Boss002_Rig"]
rig.animation_data.action = bpy.data.actions["move"]

motion_path = COMPONENTS / "monitor_motion.json"
motion = json.loads(motion_path.read_text(encoding="utf-8"))
frames = []
probes = []
bounds = {}
for frame in range(1, 50):
    scene.frame_set(frame)
    frames.append({
        "bones": [[round(value, 7) for row in CONVERSION @ pose_bone.matrix for value in row]
                  for pose_bone in rig.pose.bones],
        "expression": int(round(rig.get("expression_state", 0))),
        "face_scale": {
            slot: [bpy.data.objects["Texture " + slot].scale.x,
                   bpy.data.objects["Texture " + slot].scale.z]
            for slot in ["large_eye", "round_eye", "mouth"]
        },
    })
    probes.append({bone: [round(value, 6) for value in CONVERSION @ rig.pose.bones[bone].head]
                   for bone in ["hand.L", "hand.R", "cable_16", "monitor_tilt"]})
    if frame - 1 in [0, 24, 47]:
        depsgraph = bpy.context.evaluated_depsgraph_get()
        frame_bounds = {}
        for object_name in ["Portrait display", "Sculpted glove L", "Sculpted glove R",
                            "Keyboard outer shell", "Long data cable whip"]:
            evaluated = bpy.data.objects[object_name].evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            points = [CONVERSION @ evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            evaluated.to_mesh_clear()
            frame_bounds[object_name] = [
                [min(point[index] for point in points) for index in range(3)],
                [max(point[index] for point in points) for index in range(3)],
            ]
        bounds[str(frame - 1)] = frame_bounds

motion["clips"]["move"]["frames"] = frames
motion_path.write_text(json.dumps(motion, separators=(",", ":")), encoding="utf-8")

for filename, restored in [("source_pose_probes.json", probes), ("source_mesh_bounds.json", bounds)]:
    path = BOSS / "previews/runtime" / filename
    data = json.loads(path.read_text(encoding="utf-8"))
    data["move"] = restored
    path.write_text(json.dumps(data), encoding="utf-8")

print("RESTORED_V031_MOVE", len(frames))
