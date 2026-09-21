import bpy, sys, os, math, json, hashlib
from mathutils import Vector, Matrix, Quaternion
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/build_animation.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s)
        try: sys.__stdout__.write(s)
        except Exception: pass
    def flush(self): _logf.flush()
sys.stdout = _Tee(); sys.stderr = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MDL = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v001.blend")
MELEE_ANIM = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend")
OUT = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v001.blend")

SKELETON_ID = "SKEL-MELEE-FUNGBOAR01-002"
RIGHT_ARM = ["L_Upperarm", "L_Forearm", "L_Hand"]   # L_* = character right hand (gun hand)
# clip -> (melee action name, new name, frame_end, loop)
CLIPS = [
    ("anim_melee_fungboar01_idle_v002",     "anim_ranged_sporeshooter01_idle",     97, True),
    ("anim_melee_fungboar01_walking_v002",  "anim_ranged_sporeshooter01_walking",  49, True),
    ("anim_melee_fungboar01_running_v003",  "anim_ranged_sporeshooter01_running",  25, True),
    ("anim_melee_fungboar01_attack_v003",   "anim_ranged_sporeshooter01_attack",   52, False),
    ("anim_melee_fungboar01_hurt_v002",     "anim_ranged_sporeshooter01_hurt",     25, False),
    ("anim_melee_fungboar01_dead_v002",     "anim_ranged_sporeshooter01_dead",     73, False),
]

print("=" * 72)
print("BUILD ranged_caster animation v001 (reuse 6 + armed/shoot)")
print("=" * 72)

# 1) open model as base (armature + mesh + skeleton_id), then append melee actions
bpy.ops.wm.open_mainfile(filepath=MDL)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
print("base arm=%r mesh=%r skeleton_id=%r" % (arm.name, mesh.name, arm.data.get("skeleton_id")))

with bpy.data.libraries.load(MELEE_ANIM, link=False) as (src, dst):
    dst.actions = src.actions
print("appended actions: %d" % len(bpy.data.actions))
for a in bpy.data.actions:
    print("   action %r frames=[%.0f..%.0f]" % (a.name, a.frame_range[0], a.frame_range[1]))

# 2) rename melee actions -> ranged
rename_map = {m: n for (m, n, _, _) in CLIPS}
for a in list(bpy.data.actions):
    if a.name in rename_map:
        a.name = rename_map[a.name]
        print("renamed -> %r" % a.name)

# helper: skeleton signature (matrix_local) for cross-check
def sig(arm_obj):
    return [(b.name, b.parent.name if b.parent else '',
             [round(x, 6) for row in b.matrix_local for x in row]) for b in arm_obj.data.bones]
model_sig = sig(arm)
print("model/animation skeleton sig bones=%d (first=%r)" % (len(model_sig), model_sig[0][0]))

if arm.animation_data is None:
    arm.animation_data_create()

# ---- build gun-aim pose via deterministic analytic 2-bone IK (no constraint eval needed) ----
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
arm.data.pose_position = 'POSE'
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

M = arm.matrix_world.copy()

def rest_world(bone_name):
    b = arm.data.bones[bone_name]
    head = (M @ b.matrix_local @ b.head_local).copy()
    tail = (M @ b.matrix_local @ b.tail_local).copy()
    y = (tail - head).normalized()
    return head, y, (tail - head).length

def rest_x_world(bone_name):
    R = M @ arm.data.bones[bone_name].matrix_local
    return (R @ Vector((1,0,0)) - R @ Vector((0,0,0))).normalized()

def build_W_world(head_w, y_dir_w, rest_x_w):
    """World-space bone matrix with translation=head_w and +Y aligned to y_dir_w, roll ~ rest."""
    y = y_dir_w.normalized()
    x = rest_x_w - y * rest_x_w.dot(y)
    if x.length < 1e-6:
        x = Vector((1,0,0)) - y * y.dot(Vector((1,0,0)))
        if x.length < 1e-6:
            x = Vector((0,0,1)) - y * y.dot(Vector((0,0,1)))
    x.normalize()
    z = x.cross(y).normalized()
    x = y.cross(z).normalized()
    W = Matrix(((x.x, x.y, x.z, 0.0),
                (y.x, y.y, y.z, 0.0),
                (z.x, z.y, z.z, 0.0),
                (0.0, 0.0, 0.0, 1.0)))
    W.translation = head_w
    return W

# hand target = grip point (L_Hand tail) in front of chest, right (-X), forward (+Y)
# kept within arm reach of shoulder (~0.329) so the pose bends naturally
hand_target = Vector((-0.30, 0.90, 1.12))
aim_dir = Vector((0.0, 1.0, 0.0))        # gun points forward (+Y world)
pole_dir = Vector((-0.35, -0.30, 0.40)).normalized()  # elbow bends down/back/right

Su, _, L1 = rest_world("L_Upperarm")
_, _, L2 = rest_world("L_Forearm")
_, _, Lh = rest_world("L_Hand")

# forearm tail (= hand head) target: shift back by hand length along aim
T2 = hand_target - aim_dir * Lh
S = Su
d = (T2 - S).length
d = min(max(d, abs(L1 - L2) + 1e-4), L1 + L2 - 1e-4)
u = (T2 - S).normalized()
axis = u.cross(pole_dir)
if axis.length < 1e-6:
    axis = u.cross(Vector((0,0,1)))
    if axis.length < 1e-6:
        axis = u.cross(Vector((0,1,0)))
axis.normalize()
a = math.acos(min(max((L1*L1 + d*d - L2*L2) / (2.0*L1*d), -1.0), 1.0))
E = S + (Quaternion(axis, a) @ (u * L1))
if (E - S).normalized().dot(pole_dir) < 0:
    axis.negate()
    E = S + (Quaternion(axis, a) @ (u * L1))

# chain solve: set each bone's WORLD pose matrix directly (Blender resolves parent chain).
# parent bones are set first so child world matrices chain correctly.
chain = ["L_Upperarm", "L_Forearm", "L_Hand"]
desired = {
    "L_Upperarm": (Su, (E - Su)),
    "L_Forearm":  (E,  (T2 - E)),
    "L_Hand":     (T2, aim_dir),
}
solved = {}
for bn in chain:
    head_w, ydir_w = desired[bn]
    W = build_W_world(head_w, ydir_w, rest_x_world(bn))
    arm.pose.bones[bn].rotation_mode = 'QUATERNION'
    arm.pose.bones[bn].matrix = W
    bpy.context.view_layer.update()
    solved[bn] = arm.pose.bones[bn].rotation_quaternion.copy()

# apply solved quats and verify reach numerically
print("DEBUG M =", tuple(round(c,3) for c in M.translation), "R=", tuple(round(c,3) for c in M.to_euler()))
print("DEBUG Su=%s E=%s T2=%s" % (tuple(round(c,3) for c in Su), tuple(round(c,3) for c in E), tuple(round(c,3) for c in T2)))
for bn in RIGHT_ARM:
    arm.pose.bones[bn].rotation_mode = 'QUATERNION'
    arm.pose.bones[bn].rotation_quaternion = solved[bn]
bpy.context.view_layer.update()
for bn in RIGHT_ARM:
    pm = arm.pose.bones[bn].matrix
    print("  %-12s pose.matrix.trans=%-20s Yaxis=%s" % (bn, tuple(round(c,3) for c in pm.translation), tuple(round(c,3) for c in pm.col[1])))
hb = arm.pose.bones["L_Hand"]
hand_world = M @ hb.matrix @ Vector((0, hb.length, 0))
print("aim target=%s solved L_Hand tip world=%s dist=%.3f" % (
    tuple(round(c,3) for c in hand_target),
    tuple(round(c,3) for c in hand_world),
    (hand_world - hand_target).length))
print("solved quats:")
for bn in RIGHT_ARM:
    q = solved[bn]
    print("   %-12s q=(%.4f,%.4f,%.4f,%.4f)" % (bn, q.w, q.x, q.y, q.z))

# ---- override helper: clear arm bone rotation_quaternion curves, set constant ----
def clear_arm_curves(action):
    for bname in RIGHT_ARM:
        dp = 'pose.bones["%s"].rotation_quaternion' % bname
        for fc in list(action.fcurves):
            if fc.data_path == dp:
                action.fcurves.remove(fc)

def keyframe_arm(action, frame):
    arm.animation_data.action = action
    for bn in RIGHT_ARM:
        pb = arm.pose.bones[bn]
        pb.rotation_quaternion = solved[bn]
        pb.keyframe_insert('rotation_quaternion', frame=frame)

def make_armed_variant(src_name, new_name, frames):
    """duplicate a clip, freeze right arm to aim pose across all frames."""
    src = bpy.data.actions[src_name]
    dup = src.copy()
    dup.name = new_name
    dup.use_frame_range = True
    dup.frame_start = 1
    dup.frame_end = frames
    clear_arm_curves(dup)
    keyframe_arm(dup, 1)
    keyframe_arm(dup, frames)
    # also pin every integer frame so no stray sampling drift
    for f in range(2, frames):
        keyframe_arm(dup, f)
    print("armed variant %r frames=%d (arm frozen to aim)" % (new_name, frames))
    return dup

# 3) armed_idle (from idle), walking_armed, running_armed
make_armed_variant("anim_ranged_sporeshooter01_idle", "anim_ranged_sporeshooter01_armed_idle", 97)
make_armed_variant("anim_ranged_sporeshooter01_walking", "anim_ranged_sporeshooter01_walking_armed", 49)
make_armed_variant("anim_ranged_sporeshooter01_running", "anim_ranged_sporeshooter01_running_armed", 25)

# 4) shoot action (new, short, with recoil)
shoot = bpy.data.actions.new("anim_ranged_sporeshooter01_shoot")
shoot.use_frame_range = True
shoot.frame_start = 1
shoot.frame_end = 24
# body at rest; arm aim; recoil at frames 8-12
arm.animation_data.action = shoot
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
# small forearm recoil rotation (local) around X to kick hand back/up
kick = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(-25.0))  # forearm kicks back/up
def set_arm_at(frame, extra_forearm=None, extra_hand=None):
    for bn in RIGHT_ARM:
        pb = arm.pose.bones[bn]
        q = solved[bn]
        if bn == "L_Forearm" and extra_forearm is not None:
            q = extra_forearm @ q
        if bn == "L_Hand" and extra_hand is not None:
            q = extra_hand @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert('rotation_quaternion', frame=frame)
# frames: aim hold, recoil peak at 10, settle
set_arm_at(1)
set_arm_at(7)
set_arm_at(10, extra_forearm=kick)     # recoil kick
set_arm_at(14)
set_arm_at(24)
print("shoot action frames=24 (recoil at f10)")

# 5) temporary gun preview (long barrel, +Y forward) parented to L_Hand; removed on GLB export
bpy.ops.object.mode_set(mode='OBJECT')
import bmesh
gn = bpy.data.meshes.new("preview_gun_mesh")
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=0.1)
bm.to_mesh(gn)
bm.free()
gun = bpy.data.objects.new("preview_gun_doubledbarrel", gn)
bpy.context.scene.collection.objects.link(gun)
bpy.context.view_layer.objects.active = gun
gun.scale = (0.30, 2.6, 0.30)        # thin & long along local +Y
gun.location = (0.0, 0.12, 0.0)       # start at palm, extend forward along bone +Y
gun.parent = arm
gun.parent_type = 'BONE'
gun.parent_bone = 'L_Hand'
print("preview gun added (name=%r parent_bone=L_Hand); removed on GLB export" % gun.name)

# 6) final skeleton check
bpy.ops.object.mode_set(mode='OBJECT')
anim_sig = sig(arm)
assert len(anim_sig) == len(model_sig), "bone count mismatch"
for a, b in zip(anim_sig, model_sig):
    assert a[0] == b[0] and a[1] == b[1], "bone name/parent mismatch %s vs %s" % (a[:2], b[:2])
    assert a[2] == b[2], "bone matrix mismatch %s" % a[0]
assert arm.data.get("skeleton_id") == SKELETON_ID, "skeleton_id mismatch"
print("SKELETON MATCH model==animation: OK")

# clip length summary
all_actions = {}
for a in bpy.data.actions:
    all_actions[a.name] = (int(a.frame_range[0]), int(a.frame_range[1]))
print("ALL ACTIONS (%d):" % len(all_actions))
for k, v in sorted(all_actions.items()):
    print("   %-44s [%d..%d]" % (k, v[0], v[1]))

# 7) save animation blend
bpy.context.preferences.filepaths.save_version = 0
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED -> %r" % OUT)

# write clip meta for export (in _scratch, not asset runtime dir)
meta = {
    "model": MDL,
    "animation": OUT,
    "skeleton_id": SKELETON_ID,
    "skeleton_signature": hashlib.sha256(b"".join(str(x).encode() for x in model_sig)).hexdigest(),
    "clips": [
        {"id": "anim_ranged_sporeshooter01_idle",          "action": "anim_ranged_sporeshooter01_idle",          "frames": 97, "loop": True},
        {"id": "anim_ranged_sporeshooter01_walking",       "action": "anim_ranged_sporeshooter01_walking",       "frames": 49, "loop": True},
        {"id": "anim_ranged_sporeshooter01_running",       "action": "anim_ranged_sporeshooter01_running",       "frames": 25, "loop": True},
        {"id": "anim_ranged_sporeshooter01_attack",        "action": "anim_ranged_sporeshooter01_attack",        "frames": 52, "loop": False},
        {"id": "anim_ranged_sporeshooter01_hurt",          "action": "anim_ranged_sporeshooter01_hurt",          "frames": 25, "loop": False},
        {"id": "anim_ranged_sporeshooter01_dead",          "action": "anim_ranged_sporeshooter01_dead",          "frames": 73, "loop": False},
        {"id": "anim_ranged_sporeshooter01_armed_idle",    "action": "anim_ranged_sporeshooter01_armed_idle",    "frames": 97, "loop": True},
        {"id": "anim_ranged_sporeshooter01_shoot",         "action": "anim_ranged_sporeshooter01_shoot",         "frames": 24, "loop": False},
        {"id": "anim_ranged_sporeshooter01_walking_armed", "action": "anim_ranged_sporeshooter01_walking_armed", "frames": 49, "loop": True},
        {"id": "anim_ranged_sporeshooter01_running_armed", "action": "anim_ranged_sporeshooter01_running_armed", "frames": 25, "loop": True},
    ],
}
with open("I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/animation_meta_ranged.json", "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)
print("BUILD_ANIMATION_OK")
