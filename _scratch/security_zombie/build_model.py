import bpy, sys, os, math, hashlib
from mathutils import Vector, Matrix, kdtree

_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/build_model.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s)
        try: sys.__stdout__.write(s)
        except Exception: pass
        try: sys.__stderr__.write(s)
        except Exception: pass
    def flush(self):
        _logf.flush()
sys.stdout = _Tee()
sys.stderr = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MELEE = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend")
FBX = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_source_v001.fbx")
JPG = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/textures/enm_ranged_sporeshooter01_basecolor_v001.jpeg")
OUT_BLEND = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v002.blend")

TARGET_H = 1.857143
MELEE_BBOX_X = 1.2819
MELEE_BBOX_Y = 0.9535
SKELETON_ID = "SKEL-MELEE-FUNGBOAR01-002"
YAW_DEG = 90.0    # verified against source preview: FBX -X raw -> Rz(+90) => +Y front
TOL = 1e-4

def vbb_obj(o):
    lo = Vector((1e18,)*3); hi = Vector((-1e18,)*3)
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
    return lo, hi

print("=" * 72)
print("BUILD ranged_caster model v001 (保安僵尸 -> enm_ranged_sporeshooter01)")
print("=" * 72)

bpy.ops.wm.open_mainfile(filepath=MELEE)
arm_obj = bpy.data.objects["enm_melee_fungboar01_armature"]
melee_mesh = bpy.data.objects["enm_melee_fungboar01_mesh"]
melee_mat = bpy.data.materials["enm_melee_fungboar01_mat"]
# locate base-color image via material node links (robust to naming)
old_img = None
for n in melee_mat.node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image:
        # pick the image feeding the Principled BSDF 'Base Color' input
        for out in n.outputs["Color"].links:
            if out.to_socket.name == "Base Color":
                old_img = n.image
                break
    if old_img:
        break
if old_img is None:
    # fallback: first tex_image found
    for n in melee_mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            old_img = n.image
            break
print("melee basecolor img = %r" % old_img.name)
print("melee mesh verts=%d vgroups=%d armature bones=%d" % (
    len(melee_mesh.data.vertices), len(melee_mesh.vertex_groups), len(arm_obj.data.bones)))

# ---- import FBX ----
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=FBX)
fbx_mesh = [o for o in bpy.data.objects if o not in before and o.type == "MESH"][0]
print("fbx mesh imported: %r verts=%d polys=%d" % (fbx_mesh.name, len(fbx_mesh.data.vertices), len(fbx_mesh.data.polygons)))

# clear object transform into data
fbx_mesh.data.transform(fbx_mesh.matrix_world)
fbx_mesh.matrix_world.identity()

me = fbx_mesh.data
# rotate / uniform scale / center / ground
R = Matrix.Rotation(math.radians(YAW_DEG), 3, 'Z')
xs = [v.co.x for v in me.vertices]; zs = [v.co.z for v in me.vertices]
h = max(zs) - min(zs)
s = TARGET_H / h
print("raw h=%.4f uniform scale=%.6f yaw=%.0f deg" % (h, s, YAW_DEG))
for v in me.vertices:
    v.co = (R @ v.co) * s
xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
cx, cy, z0 = (min(xs)+max(xs))/2.0, (min(ys)+max(ys))/2.0, min(zs)
for v in me.vertices:
    v.co.x -= cx; v.co.y -= cy; v.co.z -= z0
me.update()
xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
ux, uy, uz = max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs)
print("uniform-height bbox: X=%.4f Y=%.4f Z=%.6f foot=%.6f" % (ux, uy, uz, min(zs)))

# ---- non-uniform fit to melee bbox (体型适配，不仅套高度) ----
fx = MELEE_BBOX_X / ux
fy = MELEE_BBOX_Y / uy
print("fit factors: fx=%.6f fy=%.6f" % (fx, fy))
for v in me.vertices:
    v.co.x *= fx
    v.co.y *= fy
me.update()
xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
print("fitted bbox: X=%.4f Y=%.4f Z=%.6f foot=%.6f" % (
    max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs), min(zs)))

# ---- weight transfer: nearest vertex from melee mesh (复用蒙皮) ----
mw = melee_mesh.matrix_world
mverts = [mw @ v.co for v in melee_mesh.data.vertices]
tree = kdtree.KDTree(len(mverts))
for i, vv in enumerate(mverts):
    tree.insert(vv, i)
tree.balance()

# create same-named groups on fbx mesh
vg_index = {}
for g in melee_mesh.vertex_groups:
    vg_index[g.name] = fbx_mesh.vertex_groups.new(name=g.name)

unbound = 0
for i, v in enumerate(me.vertices):
    co, idx, dist = tree.find(mverts_src := (fbx_mesh.matrix_world @ v.co))
    mv = melee_mesh.data.vertices[idx]
    total = 0.0
    pairs = []
    for g in mv.groups:
        name = melee_mesh.vertex_groups[g.group].name
        pairs.append((name, g.weight))
        total += g.weight
    if total < 1e-4 or not pairs:
        unbound += 1
        continue
    for name, w in pairs:
        vg_index[name].add([i], w / total, 'REPLACE')
me.update()
print("weight transfer done: verts=%d unbound=%d" % (len(me.vertices), unbound))

if unbound > 0:
    print("ERROR: %d unbound verts after transfer" % unbound)
    raise SystemExit(2)

# sanity: per-group weight sums
group_sums = {g.name: 0.0 for g in fbx_mesh.vertex_groups}
wsum = [0.0] * len(me.vertices)
for poly in me.polygons:
    pass
for vi, v in enumerate(me.vertices):
    for ge in v.groups:
        w = ge.weight
        gname = fbx_mesh.vertex_groups[ge.group].name
        group_sums[gname] += w
        wsum[vi] += w
bad_sum = sum(1 for w in wsum if abs(w - 1.0) > 1e-3)
print("verts with weight sum != 1 (tol 1e-3): %d" % bad_sum)
for gname in sorted(group_sums):
    print("   %-16s total=%.3f" % (gname, group_sums[gname]))

# ---- parent to armature + armature modifier (existing groups kept) ----
fbx_mesh.parent = arm_obj
mod = fbx_mesh.modifiers.new("Armature", 'ARMATURE')
mod.object = arm_obj
mod.use_vertex_groups = True

# ---- remove melee mesh + stale data ----
old_me = melee_mesh.data
bpy.data.objects.remove(melee_mesh, do_unlink=True)
bpy.data.meshes.remove(old_me)

# remove FBX-imported material & image (desktop-referenced), swap in library texture
fbx_mats = list(me.materials)
for m in fbx_mats:
    if m and m is not melee_mat:
        me.materials.clear()
        me.materials.append(melee_mat)
        if m.users == 0:
            bpy.data.materials.remove(m)
for img in list(bpy.data.images):
    if img.filepath and ("保安僵尸" in img.filepath or "4b763a81" in img.filepath):
        bpy.data.images.remove(img)

# repoint melee material texture to security JPEG
new_img = bpy.data.images.load(JPG)
new_img.name = "enm_ranged_sporeshooter01_basecolor"
new_img.colorspace_settings.name = 'sRGB'
found_tex = False
for node in melee_mat.node_tree.nodes:
    if node.type == "TEX_IMAGE" and node.image is old_img:
        node.image = new_img
        found_tex = True
print("texture node repointed: %s" % found_tex)
if not found_tex:
    raise SystemExit(3)
if old_img.users == 0:
    bpy.data.images.remove(old_img)

# ---- internal rename ----
arm_obj.name = "enm_ranged_sporeshooter01_armature"
arm_obj.data.name = "enm_ranged_sporeshooter01_armature"
arm_obj.data["skeleton_id"] = SKELETON_ID
fbx_mesh.name = "enm_ranged_sporeshooter01_mesh"
me.name = "enm_ranged_sporeshooter01_mesh"
melee_mat.name = "enm_ranged_sporeshooter01_mat"
new_img.filepath = JPG
new_img.reload()
new_img.pack()
new_img.filepath = "//textures/enm_ranged_sporeshooter01_basecolor_v001.jpeg"
print("renamed: arm=%r mesh=%r mat=%r img=%r path=%r packed=%s" % (
    arm_obj.name, fbx_mesh.name, melee_mat.name, new_img.name, new_img.filepath, new_img.packed_file is not None))

# ---- final checks ----
bpy.context.view_layer.update()
lo, hi = vbb_obj(fbx_mesh)
size = hi - lo
print("FINAL bbox: min=%s max=%s size=(X=%.4f Y=%.4f Z=%.6f) foot=%.6f" % (
    tuple(round(c,4) for c in lo), tuple(round(c,4) for c in hi),
    size.x, size.y, size.z, lo.z))
for o in (fbx_mesh, arm_obj):
    rmax = max(abs(c) for c in o.rotation_euler)
    lmax = max(abs(c) for c in o.location)
    # snap negligible float noise (< 1e-4) to exact zero so object transform is clean
    if rmax < 1e-4:
        o.rotation_euler = (0.0, 0.0, 0.0)
    if lmax < 1e-4:
        o.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    print("obj %-40r loc=%s rot=%s scale=%s" % (
        o.name, tuple(round(c,6) for c in o.location),
        tuple(round(c,6) for c in o.rotation_euler), tuple(round(c,6) for c in o.scale)))
    assert max(abs(c) for c in o.scale - Vector((1,1,1))) < 1e-9, "object scale != 1"
    assert max(abs(c) for c in o.rotation_euler) < 1e-9, "object rot != 0"

fails = []
if abs(size.z - TARGET_H) > TOL: fails.append("height %.6f != %.6f" % (size.z, TARGET_H))
if abs(lo.z) > TOL: fails.append("foot minz %.6f != 0" % lo.z)
if abs(size.x - MELEE_BBOX_X) > 1e-3: fails.append("bbox X %.4f != %.4f" % (size.x, MELEE_BBOX_X))
if abs(size.y - MELEE_BBOX_Y) > 1e-3: fails.append("bbox Y %.4f != %.4f" % (size.y, MELEE_BBOX_Y))
if fails:
    for f in fails: print("CHECK FAILED: " + f)
    raise SystemExit(4)

# ---- skeleton signature ----
def skel_sig(ad):
    # roll lives on EditBone; enter edit mode to read it reliably
    prev_mode = bpy.context.object.mode if bpy.context.object else 'OBJECT'
    bpy.context.view_layer.objects.active = bpy.data.objects[arm_obj.name]
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {e.name: e for e in ad.edit_bones}
    h = hashlib.sha256()
    h.update(("unit=%.4f|scale_length=%.4f|bones=%d" % (
        bpy.context.scene.unit_settings.scale_length, 1.0, len(ad.bones))).encode())
    for b in ad.bones:
        p = b.parent.name if b.parent else "-"
        e = eb[b.name]
        h.update(("%s|%s|" % (b.name, p)).encode())
        for c in b.head_local: h.update(("%.6f," % c).encode())
        for c in b.tail_local: h.update(("%.6f," % c).encode())
        h.update(("roll=%.6f|" % e.roll).encode())
    bpy.ops.object.mode_set(mode=prev_mode if prev_mode in ('OBJECT','POSE','EDIT') else 'OBJECT')
    return h.hexdigest()

sig_model = skel_sig(arm_obj.data)
print("SKELETON_SIG model = %s" % sig_model)
print("skeleton_id prop = %r" % arm_obj.data.get("skeleton_id"))

# ---- save ----
bpy.context.preferences.filepaths.save_version = 0
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("SAVED -> %r" % OUT_BLEND)
with open("I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/skeleton_sig_model.txt", "w") as f:
    f.write(sig_model + "\n")
print("BUILD_MODEL_OK")
