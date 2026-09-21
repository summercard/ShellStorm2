import bpy, sys, os, math, json, hashlib
from mathutils import Vector, Matrix, Quaternion
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/fix_aim_render.log"
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
ANIM = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v001.blend")
OUT = ANIM
PREV = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/previews")
os.makedirs(PREV, exist_ok=True)
SKELETON_ID = "SKEL-MELEE-FUNGBOAR01-002"
RIGHT_ARM = ["L_Upperarm", "L_Forearm", "L_Hand"]

bpy.ops.wm.open_mainfile(filepath=MDL)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
print("arm=%r mesh=%r skeleton_id=%r" % (arm.name, mesh.name, arm.data.get("skeleton_id")))
# clean rebuild: drop any pre-existing actions to avoid dup naming with appended melee actions
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
# append fresh melee v003 actions and rename to ranged
with bpy.data.libraries.load(MELEE_ANIM, link=False) as (src, dst):
    dst.actions = src.actions
print("appended melee actions: %d" % len(bpy.data.actions))
CLIPS = [
    ("anim_melee_fungboar01_idle_v002",     "anim_ranged_sporeshooter01_idle",     97, True),
    ("anim_melee_fungboar01_walking_v002",  "anim_ranged_sporeshooter01_walking",  49, True),
    ("anim_melee_fungboar01_running_v003",  "anim_ranged_sporeshooter01_running",  25, True),
    ("anim_melee_fungboar01_attack_v003",   "anim_ranged_sporeshooter01_attack",   52, False),
    ("anim_melee_fungboar01_hurt_v002",     "anim_ranged_sporeshooter01_hurt",     25, False),
    ("anim_melee_fungboar01_dead_v002",     "anim_ranged_sporeshooter01_dead",     73, False),
]
for a in list(bpy.data.actions):
    for m, n, _, _ in CLIPS:
        if a.name == m:
            a.name = n
            print("renamed -> %r" % a.name)

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
    y = y_dir_w.normalized()
    x = rest_x_w - y * rest_x_w.dot(y)
    if x.length < 1e-6:
        x = Vector((1,0,0)) - y * y.dot(Vector((1,0,0)))
        if x.length < 1e-6:
            x = Vector((0,0,1)) - y * y.dot(Vector((0,0,1)))
    x.normalize()
    z = x.cross(y).normalized()
    x = y.cross(z).normalized()
    W = Matrix(((x.x, x.y, x.z, 0.0),(y.x, y.y, y.z, 0.0),(z.x, z.y, z.z, 0.0),(0.0, 0.0, 0.0, 1.0)))
    W.translation = head_w
    return W

# reset to rest, read rest shoulder
bpy.context.view_layer.objects.active = arm
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
Su, _, L1 = rest_world("L_Upperarm")
_, _, L2 = rest_world("L_Forearm")
_, _, Lh = rest_world("L_Hand")
print("REST shoulder Su=%s L1=%.4f L2=%.4f Lh=%.4f" % (tuple(round(c,4) for c in Su), L1, L2, Lh))

# aim target: forward (+Y) in front of chest, within arm reach (L1+L2=%.3f) % (L1+L2)
fwd = Vector((0.0, 1.0, 0.0))
TARGET = Su + fwd * 0.26 + Vector((-0.04, 0.02, 0.0))
aim_dir = Vector((0.0, 1.0, 0.0))
pole_dir = Vector((0.05, -0.25, -0.70)).normalized()   # elbow bends down/back
print("TARGET=%s (reach=%.3f)" % (str(tuple(round(c,4) for c in TARGET)), L1+L2))

# ---- 2-bone analytic IK ----
T2 = TARGET - aim_dir * Lh
d = (T2 - Su).length
d = min(max(d, abs(L1 - L2) + 1e-4), L1 + L2 - 1e-4)
u = (T2 - Su).normalized()
axis = u.cross(pole_dir)
if axis.length < 1e-6:
    axis = u.cross(Vector((0,0,1)))
    if axis.length < 1e-6:
        axis = u.cross(Vector((0,1,0)))
axis.normalize()
a = math.acos(min(max((L1*L1 + d*d - L2*L2) / (2.0*L1*d), -1.0), 1.0))
E = Su + (Quaternion(axis, a) @ (u * L1))
if (E - Su).normalized().dot(pole_dir) < 0:
    axis.negate()
    E = Su + (Quaternion(axis, a) @ (u * L1))
print("d=%.4f elbow E=%s" % (d, tuple(round(c,4) for c in E)))

chain = ["L_Upperarm", "L_Forearm", "L_Hand"]
desired = {
    "L_Upperarm": (Su, (E - Su)),
    "L_Forearm":  (E,  (T2 - E)),
    "L_Hand":     (T2, aim_dir),
}
Wmap = {}
for bn in chain:
    head_w, ydir_w = desired[bn]
    Wmap[bn] = build_W_world(head_w, ydir_w, rest_x_world(bn))

# ---- apply via matrix_basis (PoseBone.matrix is READ-ONLY) ----
arm.data.pose_position = 'POSE'
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

def parent_world(bn):
    p = arm.pose.bones[bn].parent
    if p is None:
        return Matrix.Identity(4)
    return p.matrix.copy()

solved = {}
for bn in chain:
    pb = arm.pose.bones[bn]
    pw = parent_world(bn)
    pb.matrix_basis = pw.inverted() @ Wmap[bn]
    bpy.context.view_layer.update()
    solved[bn] = pb.rotation_quaternion.copy()
    # report world head for verification
    wb = pb.matrix
    print("  %-12s world_head=%s Yaxis=%s" % (bn, str(tuple(round(c,4) for c in wb.translation)), str(tuple(round(c,4) for c in wb.col[1]))))

# verify hand tip world
hb = arm.pose.bones["L_Hand"]
hand_world = M @ hb.matrix @ Vector((0, hb.length, 0))
print("aim TARGET=%s solved hand tip world=%s dist=%.4f" % (
    str(tuple(round(c,4) for c in TARGET)), str(tuple(round(c,4) for c in hand_world)), (hand_world - TARGET).length))

# ---- bake armed variants: freeze right arm across all frames ----
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
    src = bpy.data.actions[src_name]
    # if exists, remove first
    if new_name in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[new_name])
    dup = src.copy()
    dup.name = new_name
    dup.use_frame_range = True
    dup.frame_start = 1
    dup.frame_end = frames
    clear_arm_curves(dup)
    for f in range(1, frames + 1):
        keyframe_arm(dup, f)
    print("armed variant %r frames=%d (arm frozen to aim)" % (new_name, frames))
    return dup

make_armed_variant("anim_ranged_sporeshooter01_idle", "anim_ranged_sporeshooter01_armed_idle", 97)
make_armed_variant("anim_ranged_sporeshooter01_walking", "anim_ranged_sporeshooter01_walking_armed", 49)
make_armed_variant("anim_ranged_sporeshooter01_running", "anim_ranged_sporeshooter01_running_armed", 25)

# ---- shoot action (24f, recoil at f10) ----
shoot_name = "anim_ranged_sporeshooter01_shoot"
if shoot_name in bpy.data.actions:
    bpy.data.actions.remove(bpy.data.actions[shoot_name])
shoot = bpy.data.actions.new(shoot_name)
shoot.use_frame_range = True
shoot.frame_start = 1
shoot.frame_end = 24
kick = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(-22.0))  # forearm kicks back/up
arm.animation_data.action = shoot
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
def set_arm_at(frame, extra_forearm=None, extra_hand=None):
    arm.animation_data.action = shoot
    for bn in RIGHT_ARM:
        pb = arm.pose.bones[bn]
        q = solved[bn]
        if bn == "L_Forearm" and extra_forearm is not None:
            q = extra_forearm @ q
        if bn == "L_Hand" and extra_hand is not None:
            q = extra_hand @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert('rotation_quaternion', frame=frame)
set_arm_at(1); set_arm_at(7); set_arm_at(10, extra_forearm=kick); set_arm_at(14); set_arm_at(24)
print("shoot action frames=24 (recoil at f10)")

# ---- preview gun (long barrel, +Y forward) parented to L_Hand; remove before GLB export ----
bpy.ops.object.mode_set(mode='OBJECT')
gun = bpy.data.objects.get("preview_gun_doubledbarrel")
if gun is None:
    import bmesh
    gn = bpy.data.meshes.new("preview_gun_mesh")
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=0.1); bm.to_mesh(gn); bm.free()
    gun = bpy.data.objects.new("preview_gun_doubledbarrel", gn)
    bpy.context.scene.collection.objects.link(gun)
gun.scale = (0.30, 2.6, 0.30)
gun.location = (0.0, 0.12, 0.0)
gun.parent = arm
gun.parent_type = 'BONE'
gun.parent_bone = 'L_Hand'
print("preview gun parented to L_Hand")

# ---- skeleton signature recheck ----
def sig(arm_obj):
    return [(b.name, b.parent.name if b.parent else '', [round(x,6) for row in b.matrix_local for x in row]) for b in arm_obj.data.bones]
model_sig = sig(arm)
anim_sig = sig(arm)
assert len(anim_sig) == len(model_sig)
for a, b in zip(anim_sig, model_sig):
    assert a[0] == b[0] and a[1] == b[1] and a[2] == b[2], "sig mismatch %s" % a[0]
print("SKELETON MATCH OK (bones=%d)" % len(model_sig))

# save animation blend (with preview gun; export script strips it)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED %r" % OUT)

# ============ RENDER PREVIEWS ============
def setup_camera(name, loc, look, up=(0,0,1)):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cd = bpy.data.cameras.new(name); cam = bpy.data.objects.new(name, cd)
        bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    direction = Vector(look) - Vector(loc)
    # point camera -Z toward target
    rot_q = direction.to_track_quat('-Z', 'Y')
    # apply up: build matrix
    m = rot_q.to_matrix().to_4x4()
    cam.matrix_world = m
    cam.matrix_world.translation = Vector(loc)
    cam.data.lens = 50
    return cam

def render(clip_action, frame, out_path, cam_setup, res=512):
    arm.animation_data.action = clip_action
    arm.data.pose_position = 'POSE'
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    cam = cam_setup()
    bpy.context.scene.camera = cam
    bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in dir(bpy.context.scene.render) else 'BLENDER_EEVEE'
    bpy.context.scene.render.resolution_x = res
    bpy.context.scene.render.resolution_y = res
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.filepath = out_path
    bpy.context.scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    print("rendered -> %s" % out_path)

# find actions
A = {a.name: a for a in bpy.data.actions}
idle_a = A.get("anim_ranged_sporeshooter01_idle")
armed_a = A.get("anim_ranged_sporeshooter01_armed_idle")
shoot_a = A.get("anim_ranged_sporeshooter01_shoot")
center = (0.0, 0.0, 0.93)
# 6 views of armed_idle
render(armed_a, 48, os.path.join(PREV, "sec_front.png"), lambda: setup_camera("cam_front", (0.0, -2.6, 0.95), center))
render(armed_a, 48, os.path.join(PREV, "sec_side.png"), lambda: setup_camera("cam_side", (2.6, 0.0, 0.95), center))
render(armed_a, 48, os.path.join(PREV, "sec_top.png"), lambda: setup_camera("cam_top", (0.0, 0.0, 3.2), center))
render(armed_a, 48, os.path.join(PREV, "sec_3q.png"), lambda: setup_camera("cam_3q", (1.9, -1.9, 1.05), center))
render(armed_a, 48, os.path.join(PREV, "sec_back.png"), lambda: setup_camera("cam_back", (0.0, 2.6, 0.95), center))
# grip closeup of right hand (armed_idle)
hw = M @ arm.pose.bones["L_Hand"].matrix @ Vector((0, Lh*0.5, 0))
render(armed_a, 48, os.path.join(PREV, "sec_grip_idle.png"), lambda: setup_camera("cam_grip", (hw + Vector((-0.5, -0.5, 0.25))), hw), res=512)
# shoot frame (recoil)
render(shoot_a, 10, os.path.join(PREV, "sec_shoot.png"), lambda: setup_camera("cam_shoot", (0.0, -2.6, 0.95), center))
# rest/idle front for orientation reference (unarmed idle)
render(idle_a, 48, os.path.join(PREV, "sec_idle_front.png"), lambda: setup_camera("cam_ifront", (0.0, -2.6, 0.95), center))

print("FIX_AIM_RENDER_OK")
