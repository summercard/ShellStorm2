import bpy, sys, os, math
from mathutils import Vector, Matrix

_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/fit_probe.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s); sys.__stdout__.write(s)
    def flush(self):
        _logf.flush(); sys.__stdout__.flush()
sys.stdout = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MELEE = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend")
FBX = r"C:/Users/zhuangmenghong/Desktop/保安僵尸/tripo_convert_4b763a81-adc3-4d88-95dc-f269024b8c4b.fbx"
OUT = os.path.join(PROJ, "_scratch/security_zombie/previews_probe")
os.makedirs(OUT, exist_ok=True)

TARGET_H = 1.857143
YAW_DEG = -90.0   # guess: model faces -X -> rotate -90 to face +Y

bpy.ops.wm.open_mainfile(filepath=MELEE)
scene = bpy.context.scene
arm_obj = bpy.data.objects["enm_melee_fungboar01_armature"]
melee_mesh = bpy.data.objects["enm_melee_fungboar01_mesh"]

# import FBX
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=FBX)
new_objs = [o for o in bpy.data.objects if o not in before]
fbx_mesh = [o for o in new_objs if o.type == "MESH"][0]
print("fbx mesh:", fbx_mesh.name)

# clear its object transform into data
fbx_mesh.data.transform(fbx_mesh.matrix_world)
fbx_mesh.matrix_world.identity()

# rotate + scale + center in vertex data
def vbb(me):
    xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)

me = fbx_mesh.data
x0, x1, y0, y1, z0, z1 = vbb(me)
h = z1 - z0
s = TARGET_H / h
print("before: h=%.4f scale=%.6f" % (h, s))
R = Matrix.Rotation(math.radians(YAW_DEG), 3, 'Z')
for v in me.vertices:
    v.co = (R @ v.co) * s
x0, x1, y0, y1, z0, z1 = vbb(me)
cx, cy = (x0+x1)/2.0, (y0+y1)/2.0
for v in me.vertices:
    v.co.x -= cx; v.co.y -= cy; v.co.z -= z0
me.update()
x0, x1, y0, y1, z0, z1 = vbb(me)
print("after: size=(%.4f,%.4f,%.4f) minz=%.6f" % (x1-x0, y1-y0, z1-z0, z0))

# hide melee mesh (keep for later weight transfer in real build; here only probe)
melee_mesh.hide_render = True
melee_mesh.hide_viewport = True

# build bone reference boxes (preview only)
mat = bpy.data.materials.new("bone_ref")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (1.0, 0.05, 0.05, 1.0)
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 0.6

ref_coll = bpy.data.collections.new("90_骨架参考_不导出")
scene.collection.children.link(ref_coll)
for b in arm_obj.data.bones:
    hh = Vector(b.head_local); tt = Vector(b.tail_local)
    d = tt - hh
    L = d.length
    if L < 1e-6:
        continue
    bm = bpy.data.meshes.new("ref_%s" % b.name)
    # box: cross-section 0.02
    t = 0.012
    mid = (hh + tt) / 2.0
    # build a cube then transform: use from_pydata with oriented box
    q = d.to_track_quat('Z', 'Y')
    M = q.to_matrix().to_4x4()
    M.translation = mid
    base = [Vector((x, y, z)) for x in (-t, t) for y in (-t, t) for z in (-L/2, L/2)]
    verts = [M @ v0 for v0 in base]
    faces = [(0,1,3,2),(4,6,7,5),(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6)]
    bm.from_pydata([tuple(v) for v in verts], [], faces)
    bm.update()
    ob = bpy.data.objects.new("ref_%s" % b.name, bm)
    ob.data.materials.append(mat)
    ref_coll.objects.link(ob)

# render setup
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'TEXTURE'
scene.render.resolution_x = 480
scene.render.resolution_y = 640
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("W") if scene.world is None else scene.world

target = Vector((0.0, 0.0, 0.95))
def render_view(name, campos, ortho=None):
    cd = bpy.data.cameras.new(name)
    if ortho:
        cd.type = 'ORTHO'; cd.ortho_scale = ortho
    cam = bpy.data.objects.new(name, cd)
    scene.collection.objects.link(cam)
    cam.location = campos
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam); bpy.data.cameras.remove(cd)
    print("rendered", name)

d = 6.0
render_view("fit_front_%+d" % int(YAW_DEG), Vector((0, d, 0.95)), 2.4)
render_view("fit_back_%+d" % int(YAW_DEG), Vector((0, -d, 0.95)), 2.4)
render_view("fit_sideP_%+d" % int(YAW_DEG), Vector((d, 0, 0.95)), 2.4)
render_view("fit_sideM_%+d" % int(YAW_DEG), Vector((-d, 0, 0.95)), 2.4)
render_view("fit_threeq_%+d" % int(YAW_DEG), Vector((d*0.7, d*0.7, 1.4)), 2.6)
print("FIT PROBE END")
