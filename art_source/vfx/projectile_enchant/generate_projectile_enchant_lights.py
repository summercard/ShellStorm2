"""仅生成七份独立附魔灯Prefab；不写粒子、贴图、文档或账本，不启动Godot。"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
KEYS = ("fire", "ice", "poison", "lightning", "bounce", "homing", "return")


def scene_text(key: str, rgb: tuple[str, str, str]) -> str:
    return f'''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/vfx/projectile_enchant/ProjectileEnchantLight3D.gd" id="1_script"]

[node name="VfxProjectileEnchantLight{key.title()}3D" type="Node3D"]
script = ExtResource("1_script")
preset_key = "{key}"
metadata/asset_id = "VFX-PROJECTILE-ENCHANT-LIGHT-{key.upper()}-3D"
metadata/asset_version = "v001"
metadata/lifecycle_owner = "Projectile3D"

[node name="EnchantmentLight" type="OmniLight3D" parent="."]
light_color = Color({", ".join(rgb)}, 1)
light_energy = 1.15
light_cull_mask = 3
shadow_enabled = false
shadow_caster_mask = 3
distance_fade_enabled = true
distance_fade_begin = 55.0
distance_fade_length = 15.0
omni_range = 1.75
'''


def main() -> None:
    source = (ROOT / "src/vfx/projectile_enchant/ProjectileEnchantmentVisuals3D.gd").read_text(encoding="utf-8")
    palette = source.split("const BODY_PALETTE := {", 1)[1].split("}", 1)[0]
    colors = {key: tuple(value.strip() for value in rgb.split(",")) for key, rgb in re.findall(r'"(\w+)": Color\(([^)]+)\)', palette)}
    target = ROOT / "assets/art/vfx/combat_3d"
    assert target.is_dir()
    assert set(colors) == set(KEYS) and all(len(rgb) == 3 for rgb in colors.values())
    for key in KEYS:
        path = target / f"vfx_projectile_enchant_light_{key}_root_top3d.tscn"
        path.write_text(scene_text(key, colors[key]), encoding="utf-8")
        print(path.relative_to(ROOT))
    print("已从BODY_PALETTE重建七份独立灯Prefab，未改粒子或贴图，未运行Godot。")


if __name__ == "__main__":
    main()
