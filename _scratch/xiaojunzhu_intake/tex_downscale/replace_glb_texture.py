"""把 GLB 内嵌贴图替换为指定 PNG，几何 / 骨架 / 动画字节保持逐位一致。

只重排 bufferView 偏移，不重新导出，因此不引入 Blender 重导的任何差异。
"""
import argparse
import hashlib
import json
import pathlib
import struct

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
ALIGN = 4


def read_glb(path):
    data = pathlib.Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF", magic
    assert length == len(data), (length, len(data))
    off = 12
    js, bin_chunk = None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        payload = data[off:off + clen]
        if ctype == JSON_CHUNK:
            js = json.loads(payload.decode("utf-8"))
        elif ctype == BIN_CHUNK:
            bin_chunk = payload
        off += clen
    assert js is not None and bin_chunk, "missing chunk"
    return js, bin_chunk


def build_glb(js, bin_chunk):
    jbytes = json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    jbytes += b" " * ((-len(jbytes)) % ALIGN)
    bbytes = bin_chunk + b"\x00" * ((-len(bin_chunk)) % ALIGN)
    total = 12 + 8 + len(jbytes) + 8 + len(bbytes)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<II", len(jbytes), JSON_CHUNK) + jbytes
    out += struct.pack("<II", len(bbytes), BIN_CHUNK) + bbytes
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--png", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    js, old_bin = read_glb(args.glb)
    png = pathlib.Path(args.png).read_bytes()
    print("old glb bytes:", pathlib.Path(args.glb).stat().st_size, "sha256:",
          hashlib.sha256(pathlib.Path(args.glb).read_bytes()).hexdigest())
    print("new png bytes:", len(png), "sha256:", hashlib.sha256(png).hexdigest())

    images = js.get("images", [])
    assert len(images) == 1, f"expected exactly 1 image, got {len(images)}"
    tex_bv = images[0]["bufferView"]
    views = js["bufferViews"]
    print("image bufferView:", tex_bv, "old len:", views[tex_bv]["byteLength"])

    # 记录替换前的结构快照，用于事后断言
    before = {
        "bufferViews": [(v.get("byteOffset", 0), v["byteLength"]) for v in views],
        "bufferViews_n": len(views),
        "accessors_n": len(js.get("accessors", [])),
        "meshes": [(m.get("name"), len(m.get("primitives", []))) for m in js.get("meshes", [])],
        "animations": [a.get("name") for a in js.get("animations", [])],
        "skins": [(s.get("name"), len(s.get("joints", []))) for s in js.get("skins", [])],
    }

    # 按原顺序重建 BIN：除贴图 bufferView 外逐字节原样搬运
    parts, cursor, new_offsets = [], 0, {}
    for i, bv in enumerate(views):
        pad = (-cursor) % ALIGN
        if pad:
            parts.append(b"\x00" * pad)
            cursor += pad
        if i == tex_bv:
            blob = png
        else:
            s = bv.get("byteOffset", 0)
            blob = old_bin[s:s + bv["byteLength"]]
        new_offsets[i] = cursor
        bv["byteOffset"] = cursor
        bv["byteLength"] = len(blob)
        parts.append(blob)
        cursor += len(blob)

    new_bin = b"".join(parts)
    js["buffers"][0]["byteLength"] = len(new_bin)

    out_bytes = build_glb(js, new_bin)
    pathlib.Path(args.out).write_bytes(out_bytes)
    print("new glb bytes:", len(out_bytes), "sha256:", hashlib.sha256(out_bytes).hexdigest())

    # ---- 复核 ----
    js2, bin2 = read_glb(args.out)
    views2 = js2["bufferViews"]
    assert len(views2) == before["bufferViews_n"], "bufferView 数量变了"
    assert len(js2["accessors"]) == before["accessors_n"], "accessor 数量变了"
    assert [(m.get("name"), len(m.get("primitives", []))) for m in js2["meshes"]] == before["meshes"]
    assert [a.get("name") for a in js2["animations"]] == before["animations"], "动画名变了"
    assert [(s.get("name"), len(s.get("joints", []))) for s in js2["skins"]] == before["skins"], "骨架变了"

    # 除贴图外，每个 bufferView 的原始字节必须与旧文件一致
    changed = 0
    for i in range(len(views2)):
        s_new = views2[i]["byteOffset"]
        blob_new = bin2[s_new:s_new + views2[i]["byteLength"]]
        if i == tex_bv:
            assert blob_new == png, "新贴图字节不符"
            changed += 1
            continue
        s_old, l_old = before["bufferViews"][i]
        blob_old = old_bin[s_old:s_old + l_old]
        assert blob_new == blob_old, f"bufferView {i} 数据被改动"
        assert views2[i]["byteLength"] == l_old, f"bufferView {i} 长度被改动"
    assert changed == 1, "应且仅应替换 1 个 bufferView"

    ext = js2.get("extensionsUsed")
    print("extensionsUsed:", ext)
    print("贴图 bufferView:", views2[tex_bv]["byteOffset"], "-> len", views2[tex_bv]["byteLength"])
    print("geometry/animation bufferViews 逐字节一致：通过")

    # 解出新贴图，确认是 512
    from PIL import Image
    import io
    im = Image.open(io.BytesIO(bin2[views2[tex_bv]["byteOffset"]:
                                    views2[tex_bv]["byteOffset"] + views2[tex_bv]["byteLength"]]))
    print("内嵌贴图尺寸:", im.size)
    assert im.size == (512, 512), im.size
    print("OK")


if __name__ == "__main__":
    main()
