"""小菌猪 Tripo 模型入库：内部命名规范化 + 贴图路径重指向。

作用对象是**已复制到目标目录的副本**，就地保存；
桌面上的 Tripo 原始文件不被触碰。本脚本不移动、不缩放任何顶点。

运行：
  blender.exe --background --factory-startup "<目标 blend>" --python intake_model.py
"""

import bpy

PREFIX = "enm_melee_fungboar01"
TEX_REL = "//textures/%s_basecolor_v001.jpg" % PREFIX
EXPECTED_TEX_SIZE = (2048, 2048)

print("=" * 72)
print("INTAKE: rename + texture repath")
print("=" * 72)
print("blend filepath = %r" % bpy.data.filepath)

changes = []


def note(kind, old, new):
    changes.append((kind, old, new))


# ---- 1) 对象命名 ----------------------------------------------------------
for obj in list(bpy.data.objects):
    if obj.type == "ARMATURE":
        old = obj.name
        obj.name = "%s_armature" % PREFIX
        note("armature", old, obj.name)
    elif obj.type == "MESH":
        old = obj.name
        obj.name = "%s_mesh" % PREFIX
        note("mesh", old, obj.name)
        old_data = obj.data.name
        obj.data.name = "%s_mesh" % PREFIX
        note("mesh_data", old_data, obj.data.name)

# ---- 2) 材质命名（清掉 0 引用的 Tripo 空壳材质） --------------------------
for mat in list(bpy.data.materials):
    if mat.users == 0:
        note("material(drop)", mat.name, "<removed, users=0>")
        bpy.data.materials.remove(mat)
        continue
    old = mat.name
    mat.name = "%s_mat" % PREFIX
    note("material", old, mat.name)

# ---- 3) 贴图命名 + 路径重指向到目标目录 -----------------------------------
for img in list(bpy.data.images):
    if img.name == "Render Result":
        continue
    old = img.name
    img.name = "%s_basecolor" % PREFIX
    img.filepath = TEX_REL
    reload_ok = True
    try:
        img.reload()
    except Exception as exc:  # noqa: BLE001
        reload_ok = False
        print("  !! reload raised: %r" % (exc,))
    note(
        "image",
        old,
        "%s | filepath=%s | resolved=%s | reload_ok=%s | size=%s"
        % (img.name, img.filepath, bpy.path.abspath(img.filepath), reload_ok, tuple(img.size)),
    )

print("\n[CHANGES]")
for kind, old, new in changes:
    print("  %-16s %s\n                   -> %s" % (kind, old, new))

# ---- 4) 落盘前自检（防假绿哨兵） ------------------------------------------
print("\n[SELF-CHECK]")
failures = []

mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
arm_objs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
print("  mesh objects   = %d  %s" % (len(mesh_objs), [o.name for o in mesh_objs]))
print("  armature objs  = %d  %s" % (len(arm_objs), [o.name for o in arm_objs]))
if len(mesh_objs) != 1:
    failures.append("期望 1 个 mesh 对象，实际 %d" % len(mesh_objs))
if len(arm_objs) != 1:
    failures.append("期望 1 个 armature 对象，实际 %d" % len(arm_objs))
if mesh_objs:
    print("  mesh verts     = %d" % len(mesh_objs[0].data.vertices))
    print("  mesh polys     = %d" % len(mesh_objs[0].data.polygons))
    print("  mesh materials = %s" % [m.name if m else None for m in mesh_objs[0].data.materials])
    print("  mesh dims      = (%.4f, %.4f, %.4f)" % tuple(mesh_objs[0].dimensions))
    print("  armature modifier obj = %r" % [
        (m.name, m.object.name if m.object else None)
        for m in mesh_objs[0].modifiers if m.type == "ARMATURE"
    ])

for img in bpy.data.images:
    if img.name == "Render Result":
        continue
    resolved = bpy.path.abspath(img.filepath)
    size = tuple(img.size)
    print("  image %-32s size=%s packed=%s" % (img.name, size, img.packed_file is not None))
    if size != EXPECTED_TEX_SIZE:
        failures.append("贴图 %s 尺寸 %s != 期望 %s（reload 失败）" % (img.name, size, EXPECTED_TEX_SIZE))

if failures:
    print("\nSELF-CHECK FAILED:")
    for item in failures:
        print("  - " + item)
    print("=" * 72)
    raise SystemExit("INTAKE_ABORTED")

print("\nSAVING -> %r" % bpy.data.filepath)
bpy.ops.wm.save_mainfile()
print("INTAKE_OK")
print("=" * 72)
