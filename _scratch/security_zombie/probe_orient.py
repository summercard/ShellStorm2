import bpy, sys, os
from mathutils import Vector, Matrix

_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/probe_orient.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s); sys.__stdout__.write(s)
    def flush(self):
        _logf.flush(); sys.__stdout__.flush()
sys.stdout = _Tee()

FBX = r"C:/Users/zhuangmenghong/Desktop/保安僵尸/tripo_convert_4b763a81-adc3-4d88-95dc-f269024b8c4b.fbx"
OUTDIR = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/previews_probe"
os.makedirs(OUTDIR, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)

obj = None
for o in bpy.data.objects:
    if o.type == "MESH":
        obj = o
print("mesh:", obj.name, "verts", len(obj.data.vertices))

# scale to target height, center X/Y, foot at Z=0
def world_bb(o):
    lo = Vector((1e18,)*3); hi = Vector((-1e18,)*3)
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
    return lo, hi

lo, hi = world_bb(obj)
h = hi.z - lo.z
factor = 1.857143 / h
for v in obj.data.vertices:
    v.co = (v.co - lo) * factor   # also shift so min Z=0 and center X/Y? keep X/Y for now
obj.data.update()
# recompute, then center X/Y and zero Z base
lo2, hi2 = world_bb(obj)
cx = (lo2.x + hi2.x) / 2.0
cy = (lo2.y + hi2.y) / 2.0
for v in obj.data.vertices:
    v.co.x -= cx
    v.co.y -= cy
obj.data.update()
obj.location = (0, 0, 0)
obj.scale = (1, 1, 1)
obj.rotation_euler = (0, 0, 0)
obj.data.update()
lo3, hi3 = world_bb(obj)
print("after scale: min=%s max=%s size=(%.4f,%.4f,%.4f)" % (
    tuple(round(x,4) for x in lo3), tuple(round(x,4) for x in hi3),
    hi3.x-lo3.x, hi3.y-lo3.y, hi3.z-lo3.z))

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 360
scene.render.resolution_y = 540
scene.render.film_transparent = True

target = Vector((0.0, 0.0, 0.928))
def render_view(name, campos):
    cam_data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    cam.location = campos
    cam.rotation_euler = (0, 0, 0)
    # look at target
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUTDIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(cam_data)
    print("rendered", name)

d = 4.5
render_view("fbx_front_plusY", Vector((0, d, 0.928)))
render_view("fbx_back_minusY", Vector((0, -d, 0.928)))
render_view("fbx_side_plusX", Vector((d, 0, 0.928)))
render_view("fbx_side_minusX", Vector((-d, 0, 0.928)))
render_view("fbx_top_plusZ", Vector((0, 0, 5.0)))
print("PROBE END")
