"""Deterministic item palette recipe; preserve the scene palette and UV cell layout."""
from pathlib import Path
import colorsys, hashlib, json, sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
TARGET = 'assets/art/shared/palette/item_high_visibility_palette_10x10_512.png'
IMPORT_SCRIPT = 'tools/asset_pipeline/item_shared_palette_post_import.gd'
RECIPE = 'art_source/shared/palette/item_palette_recipe_v001.json'
ASSET_ID = 'ITM-PALETTE-ITEM-HIGH-VISIBILITY'
SATURATION_MULTIPLIER = 1.4 * 1.15
VALUE_MULTIPLIER = 1.4 * 1.15
MATERIAL_ROLES = ['01_精工金属_道具骨架', '02_细腻哑光_道具大面', '03_清漆反光_道具点缀', '04_柔和自发光_道具UI']
MATERIAL_PATHS = ['assets/art/items_weapons/shared/materials/itm_' + role + '.tres'
                  for role in ['metal', 'matte', 'clearcoat', 'emissive']]
ICON_FILL_ENERGY = 0.45

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def generate():
    from PIL import Image
    src = Image.open(ROOT / SOURCE).convert('RGBA')
    colors = {}
    for rgba in set(src.getdata()):
        h,s,v = colorsys.rgb_to_hsv(*(c / 255 for c in rgba[:3]))
        rgb = colorsys.hsv_to_rgb(h, min(1., s * SATURATION_MULTIPLIER), min(1., v * VALUE_MULTIPLIER))
        colors[rgba] = tuple(round(c * 255) for c in rgb) + (rgba[3],)
    dst = Image.new('RGBA', src.size)
    dst.putdata([colors[p] for p in src.getdata()])
    dst.save(ROOT / TARGET)
    for i, path in enumerate(MATERIAL_PATHS):
        material = ROOT / path
        material.parent.mkdir(parents=True, exist_ok=True)
        material.write_text(f'''[gd_resource type="StandardMaterial3D" load_steps=2 format=3]
[ext_resource type="Texture2D" path="res://{TARGET}" id="1_palette"]
[resource]
resource_name = "{MATERIAL_ROLES[i]}"
texture_filter = 0
texture_repeat = false
albedo_texture = ExtResource("1_palette")
metallic = {[.86,.02,.18,0][i]}
roughness = {[.28,.72,.16,.4][i]}
clearcoat_enabled = {str(i in [0,2]).lower()}
clearcoat = {[.15,0,.65,0][i]}
emission_enabled = {str(i == 3).lower()}
emission = Color(1, 1, 1, 1)
emission_texture = ExtResource("1_palette")
emission_operator = 1
emission_energy_multiplier = {1.3 if i == 3 else 1.0}
metadata/item_material_role = "{MATERIAL_ROLES[i]}"
''', encoding='utf-8')
    recipe = dict(schema_version=1, asset_id=ASSET_ID, source=SOURCE, target=TARGET,
                  color_space='sRGB HSV', saturation_multiplier=SATURATION_MULTIPLIER, value_multiplier=VALUE_MULTIPLIER,
                  adjustment_history=[1.4, 1.15],
                  material_roles=MATERIAL_ROLES, material_paths=MATERIAL_PATHS,
                  icon_shadow_fill_energy=ICON_FILL_ENERGY,
                  clamp='S and V clamp to 1; preserve hue and alpha; round RGB to nearest byte',
                  dimensions=list(src.size), cells=[10,10], uv_layout_unchanged=True,
                  source_sha256=sha(ROOT/SOURCE), target_sha256=sha(ROOT/TARGET),
                  generator='tools/asset_pipeline/item_palette.py',
                  import_script=IMPORT_SCRIPT)
    (ROOT/RECIPE).write_text(json.dumps(recipe, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return recipe

if __name__ == '__main__':
    print(json.dumps(generate(), ensure_ascii=False, indent=2))
