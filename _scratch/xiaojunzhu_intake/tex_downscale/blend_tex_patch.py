"""Blender 侧：把内嵌贴图替换为 512 PNG，并对骨架 / 几何做前后指纹比对。

用法（必须用 -- 分隔）：
  blender -b <file.blend> --python this.py -- probe  <out.json>
  blender -b <file.blend> --python this.py -- patch  <png512>
"""
import hashlib
import json
import pathlib
import struct
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
MODE = argv[0]


def h(*chunks):
    d = hashlib.sha256()
    for c in chunks:
        d.update(c)
    return d.hexdigest()


def fbytes(vals):
    return struct.pack("<%df" % len(vals), *vals)


def fingerprint():
    fp = {}
    for me in bpy.data.meshes:
        verts = []
        for v in me.vertices:
            verts.extend(v.co)
        polys = []
        for p in me.polygons:
            polys.extend(p.vertices)
        fp["mesh:" + me.name] = {
            "verts": len(me.vertices),
            "polys": len(me.polygons),
            "co_hash": h(fbytes(verts)),
            "topo_hash": h(struct.pack("<%di" % len(polys), *polys)),
            "uv_layers": [l.name for l in me.uv_layers],
            "vgroups": [g.name for g in me.vertices[0].groups] if False else None,
        }
    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob.data:
            names = [g.name for g in ob.vertex_groups]
            fp["objvg:" + ob.name] = {
                "groups": names,
                "weights": weight_hash(ob),
                "modifiers": [(m.name, m.type) for m in ob.modifiers],
            }
    for arm in bpy.data.armatures:
        names = [b.name for b in arm.bones]
        mats = []
        for b in arm.bones:
            mats.extend(b.matrix_local[0][:])
            mats.extend(b.matrix_local[1][:])
            mats.extend(b.matrix_local[2][:])
            mats.extend(b.matrix_local[3][:])
        fp["arm:" + arm.name] = {
            "bones": len(arm.bones),
            "name_hash": h("\n".join(names).encode("utf-8")),
            "matrix_hash": h(fbytes(mats)),
        }
    for act in bpy.data.actions:
        pts = []
        for fc in act.fcurves:
            pts.append(fc.data_path.encode("utf-8"))
            pts.append(struct.pack("<i", fc.array_index))
            for kp in fc.keyframe_points:
                pts.append(struct.pack("<ff", kp.co[0], kp.co[1]))
        fp["action:" + act.name] = {
            "fcurves": len(act.fcurves),
            "hash": h(*pts),
        }
    fp["images"] = {
        img.name: {"size": list(img.size), "packed": bool(img.packed_file),
                   "sample": [round(float(x), 6) for x in img.pixels[0:4]] if img.size[0] else None}
        for img in bpy.data.images
    }
    fp["counts"] = {
        "images": len(bpy.data.images),
        "actions": len(bpy.data.actions),
        "meshes": len(bpy.data.meshes),
        "armatures": len(bpy.data.armatures),
    }
    return fp


def weight_hash(ob):
    vals = []
    for v in ob.data.vertices:
        for g in v.groups:
            vals.append(struct.pack("<if", g.group, g.weight))
    return h(b"".join(vals))


if MODE == "probe":
    out = pathlib.Path(argv[1])
    fp = fingerprint()
    out.write_text(json.dumps(fp, indent=2, ensure_ascii=False), encoding="utf-8")
    print("PROBE_WRITTEN", out)
    for k, v in fp.items():
        print("FP", k, v if not isinstance(v, dict) else json.dumps(v, ensure_ascii=False)[:160])

elif MODE == "patch":
    png = pathlib.Path(argv[1]).read_bytes()
    before = fingerprint()
    touched = []
    for img in bpy.data.images:
        if img.source != "FILE":
            continue
        old = tuple(img.size)
        img.pack(data=png, data_len=len(png))
        img.reload()
        touched.append((img.name, old, tuple(img.size), len(img.packed_file.data)))
        print("PACKED", img.name, old, "->", tuple(img.size),
              "packed_bytes", len(img.packed_file.data))
    assert touched, "没有找到可替换的内嵌贴图"
    for name, old, new, _ in touched:
        assert new == (512, 512), f"{name} 尺寸未变为 512: {new}"
    after = fingerprint()
    # 只允许 images 段与 counts 之外变化
    diffs = []
    for k in set(before) | set(after):
        if k in ("images", "counts"):
            continue
        if before.get(k) != after.get(k):
            diffs.append(k)
    assert not diffs, f"以下数据被意外改动: {diffs}"
    assert before["counts"] == after["counts"], "datablock 数量变化"
    print("指纹比对通过：除贴图外无改动")

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_mainfile()
    print("SAVED", bpy.data.filepath)
else:
    raise SystemExit("unknown mode " + MODE)
