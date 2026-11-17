"""可编辑母版：确定性RGBA贴图和独立粒子Prefab；仅离线执行，运行时不读取此目录。"""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
SIDE = 512
FINAL_SIDE = 256
VERSION = "v002"
# v002源参数清单：中心box覆盖弹身，出生足尺寸，+Z温和漂移以透明度衰减形成短尾。
# 轴向仅由实例缩放box.z；单GPU、24/N预算、local_coords防池化旧轨迹残留。
# 每件具有独立AssetID、类和Prefab；不生成运行时kind分支。
RECIPES = {
    'fire': {'class': 'Fire', 'life': 0.28, 'quad': (0.32, 0.44), 'velocity': (0.2, 0.42), 'spread': 18, 'scale': (1.1, 1.25), 'color': (1, 0.22, 0.06), 'alpha': 0.86, 'box': (0.075, 0.075, 0.12)},
    'ice': {'class': 'Ice', 'life': 0.34, 'quad': (0.28, 0.38), 'velocity': (0.16, 0.32), 'spread': 22, 'scale': (1.1, 1.25), 'color': (0.52, 0.86, 1), 'alpha': 0.9, 'box': (0.08, 0.08, 0.12)},
    'poison': {'class': 'Poison', 'life': 0.38, 'quad': (0.38, 0.38), 'velocity': (0.12, 0.28), 'spread': 26, 'scale': (1.1, 1.25), 'color': (0.42, 0.9, 0.26), 'alpha': 0.43, 'box': (0.085, 0.085, 0.13)},
    'lightning': {'class': 'Lightning', 'life': 0.16, 'quad': (0.34, 0.46), 'velocity': (0.2, 0.4), 'spread': 24, 'scale': (1.1, 1.25), 'color': (0.52, 0.78, 1), 'alpha': 0.88, 'box': (0.085, 0.085, 0.13)},
    'bounce': {'class': 'Bounce', 'life': 0.23, 'quad': (0.30, 0.34), 'velocity': (0.18, 0.36), 'spread': 20, 'scale': (1.1, 1.25), 'color': (1, 0.66, 0.3), 'alpha': 0.66, 'box': (0.075, 0.075, 0.12)},
    'homing': {'class': 'Homing', 'life': 0.25, 'quad': (0.30, 0.40), 'velocity': (0.18, 0.36), 'spread': 16, 'scale': (1.1, 1.25), 'color': (0.36, 1, 0.78), 'alpha': 0.62, 'box': (0.075, 0.075, 0.12)},
    'return': {'class': 'Return', 'life': 0.3, 'quad': (0.34, 0.38), 'velocity': (0.16, 0.32), 'spread': 20, 'scale': (1.1, 1.25), 'color': (0.78, 0.56, 1), 'alpha': 0.66, 'box': (0.08, 0.08, 0.12)},
}


def flame() -> Image.Image:
    image = Image.new("RGBA", (SIDE, SIDE))
    pixels = image.load()
    for y in range(SIDE):
        v = y / (SIDE - 1)
        for x in range(SIDE):
            u = x / (SIDE - 1)
            energy = 0.0
            # 三支错高火舌，弯曲轮廓、暗红外缘、金黄内核，不是圆形光斑。
            for center, top, width, phase in [(0.49, 0.08, 0.24, 0), (0.31, 0.30, 0.12, 2), (0.70, 0.23, 0.12, 4)]:
                t = (v - top) / (0.92 - top)
                if not 0 < t < 1:
                    continue
                c = center + 0.06 * math.sin(t * 7 + phase) * (1 - t)
                w = width * math.sin(math.pi * t) ** 0.72 * (0.4 + t)
                r = abs(u - c) / max(w, 0.001)
                edge = max(0.0, min(1.0, (1 - r) * 10))
                e = edge * math.sin(math.pi * t) ** 0.35
                energy = max(energy, e)
            if energy <= 0:
                continue
            core = max(0.0, 1 - abs(u - 0.50) / 0.17) * max(0.0, 1 - abs(v - 0.70) / 0.33)
            flicker = 0.93 + 0.07 * math.sin(x * 0.08 + math.sin(y * 0.05) * 3)
            pixels[x, y] = (255, int(65 + 180 * core + 35 * energy), int(7 + 130 * core ** 2), int(255 * energy * flicker))
    return image


def ice() -> Image.Image:
    image = Image.new("RGBA", (SIDE, SIDE))
    draw = ImageDraw.Draw(image)
    draw.polygon([(261, 30), (343, 190), (304, 408), (220, 478), (154, 292)], fill=(70, 171, 236, 235))
    draw.polygon([(261, 30), (254, 246), (154, 292)], fill=(160, 236, 255, 250))
    draw.polygon([(261, 30), (343, 190), (254, 246)], fill=(231, 255, 255, 255))
    draw.polygon([(254, 246), (304, 408), (220, 478)], fill=(121, 210, 250, 245))
    draw.line([(261, 30), (254, 246), (220, 478)], fill=(235, 255, 255, 255), width=9)
    draw.line([(254, 246), (343, 190)], fill=(206, 249, 255, 245), width=5)
    draw.polygon([(107, 133), (140, 177), (109, 239), (88, 187)], fill=(164, 237, 255, 210))
    return image


def poison() -> Image.Image:
    image = Image.new("RGBA", (SIDE, SIDE))
    pixels = image.load()
    for y in range(SIDE):
        v = (y / (SIDE - 1) - 0.5) * 2
        for x in range(SIDE):
            u = (x / (SIDE - 1) - 0.5) * 2
            angle = math.atan2(v, u)
            edge = 0.72 + 0.09 * math.sin(angle * 5 + 1) + 0.06 * math.sin(angle * 9)
            r = math.hypot(u, v) / edge
            if r >= 1:
                continue
            swirl = 0.55 + 0.25 * math.sin(u * 12 + math.cos(v * 10) * 2) + 0.12 * math.sin(u * 27 - v * 15)
            alpha = (1 - r * r) ** 1.3 * (0.5 + swirl * 0.5)
            pixels[x, y] = (int(55 + 105 * swirl), int(125 + 115 * swirl), int(30 + 58 * swirl), int(225 * alpha))
    return image


def glyph(kind: str) -> Image.Image:
    image = Image.new("RGBA", (SIDE, SIDE))
    draw = ImageDraw.Draw(image)
    if kind == "lightning":
        points = [(271, 35), (178, 158), (291, 197), (194, 293), (278, 321), (211, 477)]
        draw.line(points, fill=(102, 171, 255, 190), width=24, joint="curve")
        draw.line(points, fill=(214, 242, 255, 255), width=10, joint="curve")
        draw.line([(291, 197), (365, 252), (330, 300), (387, 351)], fill=(153, 222, 255, 245), width=7)
        draw.line([(194, 293), (124, 322), (142, 377)], fill=(153, 222, 255, 220), width=6)
    elif kind == "bounce":
        draw.line([(104, 365), (256, 145), (408, 365)], fill=(255, 189, 92, 245), width=28, joint="curve")
        draw.line([(108, 267), (256, 62), (404, 267)], fill=(255, 231, 165, 230), width=14, joint="curve")
    elif kind == "homing":
        draw.line([(114, 404), (256, 230), (398, 404)], fill=(134, 255, 213, 245), width=27, joint="curve")
        draw.line([(168, 183), (256, 76), (344, 183)], fill=(211, 255, 238, 235), width=15, joint="curve")
    else:
        draw.arc((94, 81, 416, 414), 25, 300, fill=(211, 159, 255, 245), width=24)
        draw.polygon([(341, 65), (404, 162), (294, 158)], fill=(240, 209, 255, 255))
    glow = image.filter(ImageFilter.GaussianBlur(11))
    return Image.alpha_composite(glow, image)


def scene_text(kind: str, recipe: dict) -> str:
    class_name = "VfxProjectileEnchant" + recipe["class"] + "3D"
    red, green, blue = recipe["color"]
    width, height = recipe["quad"]
    velocity_min, velocity_max = recipe["velocity"]
    scale_min, scale_max = recipe["scale"]
    box_x, box_y, box_z = recipe["box"]
    return f'''[gd_scene load_steps=10 format=3]

[ext_resource type="Script" path="res://src/vfx/projectile_enchant/{class_name}.gd" id="1_script"]
[ext_resource type="Texture2D" path="res://assets/art/vfx/textures/projectile_enchant_{kind}.png" id="2_texture"]

[sub_resource type="Gradient" id="Gradient_alpha"]
offsets = PackedFloat32Array(0, 0.12, 0.65, 1)
colors = PackedColorArray({red}, {green}, {blue}, {recipe["alpha"]}, {red}, {green}, {blue}, {recipe["alpha"]}, {red}, {green}, {blue}, {recipe["alpha"] * 0.65}, {red}, {green}, {blue}, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture_alpha"]
gradient = SubResource("Gradient_alpha")

[sub_resource type="Curve" id="Curve_scale"]
_data = [Vector2(0, 1), 0.0, 0.0, 0, 0, Vector2(1, 1), 0.0, 0.0, 0, 0]
point_count = 2

[sub_resource type="CurveTexture" id="CurveTexture_scale"]
curve = SubResource("Curve_scale")

[sub_resource type="ParticleProcessMaterial" id="Particle_material"]
resource_local_to_scene = true
particle_flag_rotate_y = false
emission_shape = 3
emission_box_extents = Vector3({box_x}, {box_y}, {box_z})
direction = Vector3(0, 0, 1)
spread = {recipe["spread"]}.0
gravity = Vector3(0, 0, 0)
initial_velocity_min = {velocity_min}
initial_velocity_max = {velocity_max}
angular_velocity_min = -65.0
angular_velocity_max = 65.0
scale_min = {scale_min}
scale_max = {scale_max}
scale_curve = SubResource("CurveTexture_scale")
color_ramp = SubResource("GradientTexture_alpha")
collision_mode = 0

[sub_resource type="StandardMaterial3D" id="Quad_material"]
transparency = 1
shading_mode = 0
vertex_color_use_as_albedo = true
albedo_texture = ExtResource("2_texture")
billboard_mode = 3
billboard_keep_scale = true
cull_mode = 2
texture_filter = 2

[sub_resource type="QuadMesh" id="Quad_mesh"]
material = SubResource("Quad_material")
size = Vector2({width}, {height})

[node name="{class_name}" type="Node3D"]
visible = false
script = ExtResource("1_script")
lifetime = 0.0
metadata/asset_id = "VFX-PROJECTILE-ENCHANT-{kind.upper()}-3D"
metadata/asset_version = "{VERSION}"
metadata/lifecycle_owner = "Projectile3D"

[node name="Particles" type="GPUParticles3D" parent="."]
visible = false
position = Vector3(0, 0, 0)
cast_shadow = 0
emitting = false
amount = 24
lifetime = {recipe["life"]}
preprocess = 0.0
local_coords = true
speed_scale = 0.0
visibility_aabb = AABB(-1, -1, -1, 2, 2, 3)
use_fixed_seed = true
seed = 160116
process_material = SubResource("Particle_material")
draw_passes = 1
draw_pass_1 = SubResource("Quad_mesh")
trail_enabled = false
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true", help="通过workspace_paths保存工程外贴图预览")
    parser.add_argument("--prefabs-only", action="store_true", help="仅重建Prefab，不生成或覆盖纹理")
    args = parser.parse_args()
    textures = ROOT / "assets/art/vfx/textures"
    prefabs = ROOT / "assets/art/vfx/combat_3d"
    assert textures.is_dir() and prefabs.is_dir()
    images = {}
    for kind, recipe in RECIPES.items():
        if not args.prefabs_only:
            image = flame() if kind == "fire" else ice() if kind == "ice" else poison() if kind == "poison" else glyph(kind)
            image = image.resize((FINAL_SIDE, FINAL_SIDE), Image.Resampling.LANCZOS)
            # 明确透明边界，避免缩小过滤将外缘污染成方框。
            ImageDraw.Draw(image).rectangle((0, 0, FINAL_SIDE - 1, FINAL_SIDE - 1), outline=(0, 0, 0, 0), width=2)
            image.save(textures / f"projectile_enchant_{kind}.png", optimize=True)
            images[kind] = image
        elif args.preview:
            with Image.open(textures / f"projectile_enchant_{kind}.png") as image:
                images[kind] = image.convert("RGBA")
        (prefabs / f"vfx_projectile_enchant_{kind}_root_top3d.tscn").write_text(scene_text(kind, recipe), encoding="utf-8")
    if args.preview:
        sys.path.insert(0, str(ROOT / "scripts"))
        import workspace_paths as wp
        sheet = Image.new("RGB", (FINAL_SIDE * len(images), FINAL_SIDE + 32), (22, 27, 39))
        draw = ImageDraw.Draw(sheet)
        for index, (kind, image) in enumerate(images.items()):
            sheet.paste(image, (index * FINAL_SIDE, 0), image)
            draw.text((index * FINAL_SIDE + 12, FINAL_SIDE + 8), kind, fill=(224, 232, 242))
        target = wp.work_path("sessions/2026-11-17_projectile_enchant_wrap/texture_contact_sheet.png")
        sheet.save(target)
        print(target)
    print(f"已生成{len(RECIPES)}份独立Prefab；" + ("纹理未写入。" if args.prefabs_only else f"已生成{len(images)}张RGBA贴图。") + "未运行Godot。")


if __name__ == "__main__":
    main()
