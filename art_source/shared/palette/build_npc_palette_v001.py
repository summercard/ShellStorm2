"""Build the shared NPC/monster palette and an editable grouped, layered PSD.

The scene palette is deliberately untouched. Row numbers in the recipe start at
the top of the PNG; Blender UV V therefore uses 1-(row+0.5)/10.
"""
from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
PNG = ROOT / "assets/art/shared/palette/npc_palette_10x10_512.png"
PSD = Path(__file__).with_name("npc_palette_10x10_512_v001.psd")
RECIPE = Path(__file__).with_name("npc_palette_recipe_v001.json")
ROWS = [
    ("01_Infected_Cloth_Skin_Mouth", ["D9CFB0", "C4B99A", "A89A7F", "7E8873", "626F60", "393331", "4A4240", "432326", "AD514C"]),
    ("02_Infected_Eyes_Dirt_Details", ["F2E5BC", "302A28", "A84D3D", "877762", "9D493F", "647065", "AEA78B", "ECE1C1", "5C4D43"]),
    ("03_Human_Skin_Warm", ["F0D4B8", "DDB99A", "C89C7D", "AC7C61", "8E604D", "704A3D", "53382F", "D59580", "AA6D64"]),
    ("04_Human_Skin_Cool_Undead", ["D6D2C0", "BBBFA7", "A0AD95", "85967D", "6B826D", "546B5C", "43574F", "918F9C", "726A80"]),
    ("05_Clothing_Earth_Warm", ["E8DBBE", "D0BB95", "B39A72", "9E805B", "806646", "654F38", "B7956B", "A66F54", "855244"]),
    ("06_Clothing_Cool_Blue_Green", ["B2C5BD", "91AFA4", "6D9388", "50766D", "395B56", "8CA6B6", "6A879F", "4F6783", "374B63"]),
    ("07_Clothing_Red_Purple", ["C6958B", "B3766D", "955850", "75433F", "552F31", "A18DAB", "826D90", "65526F", "4A3A52"]),
    ("08_Leather_Hair_Dark", ["A98666", "8C694D", "704F3A", "543A2D", "3C2A23", "D1C39F", "A79773", "6C6551", "37382F"]),
    ("09_Eyes_Teeth_Accent", ["F8F0D9", "E4D8B4", "BDAD88", "B79C50", "B97144", "A64842", "72A8A0", "7A96BB", "9983AF"]),
    ("10_Neutral_Cloth_Stone", ["E2DED0", "C7C2B3", "ABA596", "918A7B", "776F64", "5D574F", "49443F", "353332", "252626"]),
]
COOL_GRAY = ["1B2533", "263242", "324052", "3F4F62", "4D5E72", "5D6E82", "718195", "8998AA", "A5B2C1", "C5CED8"]
NAMES = [
    ["shirt", "shirt_shadow", "shirt_deep", "skin", "skin_shadow", "pants", "pants_light", "mouth", "tongue"],
    ["ivory", "pupil", "iris", "stain", "tongue_shadow", "belly", "khaki", "cloth_light", "leather"],
]


def rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def b32(value):
    return struct.pack(">I", value)


def tag(key, data):
    return b"8BIM" + key + b32(len(data)) + data + b"\0" * (len(data) % 2)


def layer_record(name, rect, color=None, section=None):
    top, left, bottom, right = rect
    channels = [] if color is None else [(i, bytes([color[i]]) * ((bottom-top)*(right-left))) for i in range(3)]
    record = struct.pack(">4iH", *rect, len(channels))
    for cid, data in channels:
        record += struct.pack(">hI", cid, len(data) + 2)
    record += b"8BIMnorm" + bytes([255, 0, 0, 0])
    ascii_name = name.encode("ascii", "replace")[:255]
    pascal = bytes([len(ascii_name)]) + ascii_name
    pascal += b"\0" * ((-len(pascal)) % 4)
    unicode_name = name.encode("utf-16-be")
    extra = b32(0) + b32(0) + pascal + tag(b"luni", b32(len(unicode_name)//2) + unicode_name)
    if section is not None:
        extra += tag(b"lsct", b32(section))
    record += b32(len(extra)) + extra
    data = b"".join(b"\0\0" + plane for _, plane in channels)
    return record, data


def write_psd(image):
    records, channels = [], []
    # Author top-to-bottom, then reverse records and their channel data for
    # PSD's bottom-to-top storage. Section dividers create real editable groups.
    for row, (group_name, colors) in enumerate(ROWS):
        record, channel = layer_record(group_name, (0,0,0,0), section=1)
        records.append(record); channels.append(channel)
        for col, value in enumerate(colors + [COOL_GRAY[row]]):
            x0, x1 = round(col*51.2), round((col+1)*51.2)
            y0, y1 = round(row*51.2), round((row+1)*51.2)
            name = f"R{row+1:02d}C{col+1:02d}_#{value}"
            if row < 2 and col < 9:
                name += "_" + NAMES[row][col]
            record, channel = layer_record(name, (y0,x0,y1,x1), rgb(value))
            records.append(record); channels.append(channel)
        record, channel = layer_record("</Layer group>", (0,0,0,0), section=3)
        records.append(record); channels.append(channel)
    records.reverse()
    channels.reverse()
    layer_info = struct.pack(">h", len(records)) + b"".join(records) + b"".join(channels)
    layer_info += b"\0" * (len(layer_info) % 2)
    layer_mask = b32(len(layer_info)) + layer_info + b32(0)
    header = b"8BPS" + struct.pack(">H6sHIIHH", 1, b"\0"*6, 3, 512, 512, 8, 3)
    composite = b"\0\0" + b"".join(channel.tobytes() for channel in image.split())
    PSD.write_bytes(header + b32(0) + b32(0) + b32(len(layer_mask)) + layer_mask + composite)


def main():
    for path in (PNG, PSD, RECIPE):
        if path.exists():
            raise FileExistsError(f"Refusing to replace existing palette: {path}")
    image = Image.new("RGB", (512,512))
    swatches = []
    named_colors = {}
    for row, (group, colors) in enumerate(ROWS):
        for col, value in enumerate(colors + [COOL_GRAY[row]]):
            bounds = [round(col*51.2), round(row*51.2), round((col+1)*51.2), round((row+1)*51.2)]
            image.paste(rgb(value), tuple(bounds))
            name = NAMES[row][col] if row < 2 and col < 9 else f"r{row+1:02d}c{col+1:02d}"
            entry = {"name":name,"row":row,"column":col,"hex":"#"+value,"bounds_px":bounds,"uv_center":[(col+.5)/10,1-(row+.5)/10],"group":group}
            swatches.append(entry)
            named_colors[name] = {"row":row,"col":col,"hex":"#"+value}
    PNG.parent.mkdir(parents=True, exist_ok=True)
    image.save(PNG, optimize=False)
    write_psd(image)
    recipe = {"schema":"shellstorm2_npc_palette_v1","version":"v001","scope":"shared NPC and monster character assets","png":PNG.relative_to(ROOT).as_posix(),"psd":PSD.relative_to(ROOT).as_posix(),"resolution":[512,512],"grid":[10,10],"row_origin":"top","uv_layer":"PaletteUV","interpolation":"Closest","packing":"external only; do not embed or duplicate","face_island_rule":"nonzero area; one cell per face; 45-65% cell extent; >=10% safety border","material_limit":4,"source":"User-authorized new NPC palette; infected swatches selected from supplied reference","named_colors":named_colors,"swatches":swatches,"sha256":{PNG.name:hashlib.sha256(PNG.read_bytes()).hexdigest(),PSD.name:hashlib.sha256(PSD.read_bytes()).hexdigest()}}
    RECIPE.write_text(json.dumps(recipe, ensure_ascii=False, indent=2)+"\n",encoding="utf-8")
    reopened = Image.open(PNG).convert("RGB")
    for entry in swatches:
        assert set(reopened.crop(tuple(entry["bounds_px"])).getdata()) == {rgb(entry["hex"][1:])}
    assert len(swatches)==100
    print(json.dumps({"png":str(PNG),"psd":str(PSD),"recipe":str(RECIPE),"swatches":100,"psd_groups":10,"psd_image_layers":100,"pixel_validation":"PASS"},ensure_ascii=False))


if __name__ == "__main__":
    main()
