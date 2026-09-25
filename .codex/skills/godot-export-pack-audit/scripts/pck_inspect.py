# -*- coding: utf-8 -*-
"""解析 Godot 4 PCK pack format v3（索引在尾部，dir_offset 存于 header）。
自校验：解析完 N 条后位置必须正好等于文件大小。
"""
import struct, sys, os, collections

PACK_HEADER_MAGIC = 0x43504447


def parse(path):
    d = open(path, "rb").read()
    sz = len(d)
    assert d[:4] == b"GDPC", "bad magic"
    ver = struct.unpack_from("<I", d, 4)[0]
    eng = struct.unpack_from("<III", d, 8)
    flags = struct.unpack_from("<I", d, 20)[0]
    file_base = struct.unpack_from("<Q", d, 24)[0]
    dir_off = struct.unpack_from("<Q", d, 32)[0]
    print(f"PCK fmt={ver} engine={eng[0]}.{eng[1]}.{eng[2]} flags={flags:#x} file_base={file_base} dir_off={dir_off} filesize={sz}")

    p = dir_off
    count = struct.unpack_from("<I", d, p)[0]
    p += 4
    print(f"file_count={count}")
    entries = []
    for _ in range(count):
        (plen,) = struct.unpack_from("<I", d, p)
        p += 4
        name = d[p:p + plen].rstrip(b"\x00").decode("utf-8", "replace")
        p += plen
        off, size = struct.unpack_from("<QQ", d, p)
        p += 16
        p += 16
        p += 4
        entries.append((name, off, size))
    print(f"解析终点={p}  文件大小={sz}  {'✅ 吻合' if p == sz else '❌ 差 %d' % (sz - p)}")
    return entries


def main():
    entries = parse(sys.argv[1])
    total = sum(e[2] for e in entries)
    print(f"包内总字节: {total/1048576:.1f} MB")
    print()
    keys = [
        "assets/art/environments/tower_zones/expedition/source",
        "assets/art/environments/tower_zones/battle/source",
        "assets/art/environments/tower_zones/rooftop/source",
        "assets/art/environments/tower_zones/shared/source",
        "assets/art/environments/tower_zones/expedition",
        "assets/art/environments/tower_zones",
        "assets/art/",
        "assets/audio/",
        "src/", "scenes/", "tests/", "docs/", "tools/", "source/", "_scratch/", ".godot/",
    ]
    g = collections.Counter()
    gs = collections.Counter()
    for name, off, size in entries:
        hit = "其他"
        for k in keys:
            if name.startswith(k):
                hit = k
                break
        g[hit] += 1
        gs[hit] += size
    print(f"{'分组':52s} {'文件数':>7s} {'体积':>12s}")
    print("-" * 78)
    for k, c in gs.most_common(18):
        print(f"{k:52s} {g[k]:7d} {c/1048576:10.2f} MB")
    print()
    print("按扩展名：")
    for ext in (".blend", ".blend1", ".json", ".png", ".import", ".tscn", ".gd", ".ctex", ".ogg"):
        sel = [e for e in entries if e[0].endswith(ext)]
        if sel or ext in (".blend", ".json"):
            print(f"  {ext:9s} {len(sel):6d} 个  {sum(e[2] for e in sel)/1048576:9.2f} MB")
    print()
    am = [e for e in entries if "asset_manifest.json" in e[0]]
    print(f"★ asset_manifest.json 在包内: {len(am)} 个 / {sum(e[2] for e in am)/1024:.1f} KB")
    for e in am[:3]:
        print("     ", e[0])
    src = [e for e in entries if "/source/" in e[0]]
    print(f"★ 含 '/source/' 的条目: {len(src)} 个 / {sum(e[2] for e in src)/1048576:.1f} MB")
    for e in src[:8]:
        print("     ", e[0], f"{e[2]/1024:.0f}KB")
    # boss layout json 是否在
    tgt = [e for e in entries if "boss_room_50x40_v002.layout.json" in e[0]]
    print(f"★ 运行时硬依赖 boss layout.json: {'✅ 在包内' if tgt else '❌ 不在包内'} {[(t[0], t[2]) for t in tgt]}")


if __name__ == "__main__":
    main()
