"""Offline authoring: broad overlapping cloud banks and conservative R8 building mask.

Run with bundled Python/NumPy, then bake_cloud_textures.gd with Godot. No runtime baking.
"""
import argparse
import hashlib
import json
import random
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[7]
ASSET = ROOT / "assets/art/vfx/environment_3d/cloud_sea"
SOURCE = ASSET / "source/v001"
PREFAB = ASSET / "vfx_env_cloud_sea_root_top3d.tscn"
ASSET_ID = "VFX-ENV-CLOUD-SEA-3D"
SEED = 990930
MASK_ORIGIN = np.array([-240.0, -110.0, -320.0])
MASK_SIZE = np.array([480.0, 160.0, 540.0])
MASK_DIMS = np.array([256, 80, 288])


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


def mask_bake(keepouts):
    voxel = MASK_SIZE / MASK_DIMS
    occupied = np.zeros(tuple(MASK_DIMS[::-1]), dtype=bool)
    for box in keepouts:
        lo = np.maximum(np.floor((np.array(box["min"]) - 1.5 - MASK_ORIGIN) / voxel).astype(int), 0)
        hi = np.minimum(np.ceil((np.array(box["max"]) + 1.5 - MASK_ORIGIN) / voxel).astype(int), MASK_DIMS)
        if np.all(hi > lo):
            occupied[lo[2]:hi[2], lo[1]:hi[1], lo[0]:hi[0]] = True
    distance = np.where(occupied, 0.0, 16.0).astype(np.float32)
    for _pass in range(6):
        for axis, step in enumerate(voxel[::-1]):
            left, right = [slice(None)] * 3, [slice(None)] * 3
            left[axis], right[axis] = slice(1, None), slice(None, -1)
            l, r = tuple(left), tuple(right)
            np.minimum(distance[l], distance[r] + step, out=distance[l])
            np.minimum(distance[r], distance[l] + step, out=distance[r])
    (SOURCE / "keepout.raw").write_bytes(np.floor(np.clip(distance / 16.0, 0, 1) * 255).astype(np.uint8).tobytes())
    noise = np.random.default_rng(SEED).random((32, 32, 32), dtype=np.float32)
    for _pass in range(4):
        noise = (noise * 2 + sum(np.roll(noise, sign, axis) for axis in range(3) for sign in [-1, 1])) / 8
    noise = (noise - noise.min()) / (noise.max() - noise.min())
    (SOURCE / "noise.raw").write_bytes((noise * 255).astype(np.uint8).tobytes())
    write_text(SOURCE / "texture_bake.json", json.dumps({"keepout": {"dimensions": MASK_DIMS.tolist()}, "noise": {"dimensions": [32, 32, 32]}}) + "\n")


def overlaps(a, b, margin=0.0):
    return all(a["max"][i] > b["min"][i] - margin and a["min"][i] < b["max"][i] + margin for i in range(3))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--boundaries", type=Path, required=True)
    args = parser.parse_args()
    measured = json.loads(args.boundaries.read_text(encoding="utf-8"))
    keepouts = [{"min": [-50.0, -100000.0, -35.0], "max": [50.0, 100000.0, 45.0]}] + measured["route_all"]["parts"] + measured["city"]
    rng = random.Random(SEED)
    clouds = []
    for z in [-240, -100, 40, 180]:
        for x in [-165, -55, 55, 165]:
            clouds.append({"name": f"CloudBank_{len(clouds):02d}", "kind": "CloudSea", "position": [x + rng.uniform(-3, 3), -34 + rng.uniform(-3, 3), z + rng.uniform(-3, 3)],
                           "size": [180, 34, 218], "opacity": round(rng.uniform(0.82, 0.90), 3), "density": 4.8, "seed": round(rng.uniform(1, 120), 3), "sheet": 1.0})
    for index in range(24):
        for _attempt in range(10000):
            size = [rng.uniform(20, 43), rng.uniform(5, 11), rng.uniform(15, 30)]
            pos = [rng.uniform(-150, 150), rng.uniform(-10, 29), rng.uniform(-235, 135)]
            box = {"min": [pos[i] - size[i]/2 for i in range(3)], "max": [pos[i] + size[i]/2 for i in range(3)]}
            if any(overlaps(box, k, 1.7) for k in keepouts):
                continue
            if any(sum((pos[i] - c["position"][i])**2 for i in (0, 2)) < 20**2 for c in clouds if c["kind"] == "AirWisps"):
                continue
            clouds.append({"name": f"AirWisp_{index:02d}", "kind": "AirWisps", "position": [round(v, 3) for v in pos], "size": [round(v, 3) for v in size],
                           "opacity": round(rng.uniform(0.22, 0.34), 3), "density": 3.5, "seed": round(rng.uniform(1, 120), 3), "sheet": 0.0})
            break
        else:
            raise RuntimeError("No safe air-wisp placement")
    mask_bake(keepouts)
    layout = {"asset_id": ASSET_ID, "asset_version": "v001", "seed": SEED, "floor_99_y": -12,
              "clearance_m": 1.5, "mask_origin": MASK_ORIGIN.tolist(), "mask_size": MASK_SIZE.tolist(), "mask_dimensions": MASK_DIMS.tolist(),
              "mask_zero_distance_m": 3.0, "mask_feather_end_m": 7.0, "sea_count": 16, "wisp_count": 24,
              "reference": "User skyline illustration and broad fluid fog screenshots; original shader",
              "route_snapshot_sha256": measured["snapshot_route_sha256"], "keepouts": keepouts, "clouds": clouds}
    write_text(ASSET / "cloud_layout.json", json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
    lines = ['[gd_scene format=3]', '',
             '[ext_resource type="Script" path="res://src/vfx/VfxCloudSea3D.gd" id="cloud_script"]',
             '[ext_resource type="Shader" path="res://assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader" id="cloud_shader"]',
             '[ext_resource type="Texture3D" path="res://assets/art/vfx/environment_3d/cloud_sea/cloud_keepout.res" id="keepout"]',
             '[ext_resource type="Texture3D" path="res://assets/art/vfx/environment_3d/cloud_sea/cloud_noise.res" id="noise"]', '',
             '[sub_resource type="BoxMesh" id="CloudVolumeBox"]', 'size = Vector3(1, 1, 1)', '']
    for index, c in enumerate(clouds):
        lines += [f'[sub_resource type="ShaderMaterial" id="CloudMaterial_{index:03d}"]', 'resource_local_to_scene = true', 'shader = ExtResource("cloud_shader")',
                  'shader_parameter/building_distance = ExtResource("keepout")', 'shader_parameter/shape_noise = ExtResource("noise")',
                  f'shader_parameter/cloud_opacity = {c["opacity"]}', f'shader_parameter/density_scale = {c["density"]}',
                  f'shader_parameter/shape_seed = {c["seed"]}', f'shader_parameter/sheet_mode = {c["sheet"]}', '']
    lines += ['[node name="VfxCloudSea3D" type="Node3D"]', 'script = ExtResource("cloud_script")', 'lifetime = 0.0',
              f'metadata/asset_id = "{ASSET_ID}"', 'metadata/asset_version = "v001"', 'metadata/lifecycle = "scene_owned_persistent"', 'metadata/outdoor_only = true', '',
              '[node name="CloudSea" type="Node3D" parent="."]', '', '[node name="AirWisps" type="Node3D" parent="."]', '']
    for index, c in enumerate(clouds):
        vec = lambda value: "Vector3(" + ", ".join(str(round(v, 3)) for v in value) + ")"
        lines += [f'[node name="{c["name"]}" type="MeshInstance3D" parent="{c["kind"]}"]', f'position = {vec(c["position"])}', f'scale = {vec(c["size"])}',
                  'cast_shadow = 0', 'visibility_range_end = 650.0', f'material_override = SubResource("CloudMaterial_{index:03d}")', 'mesh = SubResource("CloudVolumeBox")', '']
    write_text(PREFAB, "\n".join(lines))
    manifest = {"asset_id": ASSET_ID, "asset_version": "v001", "status": "awaiting_runtime_verification", "prefab": str(PREFAB.relative_to(ROOT)).replace("\\", "/"),
                "script": "src/vfx/VfxCloudSea3D.gd", "shader": "assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader", "source": "assets/art/vfx/environment_3d/cloud_sea/source/v001/build_outdoor_clouds.py",
                "layout": "assets/art/vfx/environment_3d/cloud_sea/cloud_layout.json", "sea_count": 16, "air_wisp_count": 24, "bank_dimensions_m": [180, 34, 218],
                "quality_ray_steps": {"high": 16, "balanced": 12, "low": 8}, "prefab_sha256": hashlib.sha256(PREFAB.read_bytes()).hexdigest(), "mask_texture_bytes": int(np.prod(MASK_DIMS)),
                "collision": "none", "lifecycle": "scene_owned_persistent", "license": "Project original; user style reference"}
    write_text(ASSET / "asset_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"OUTDOOR_CLOUDS_AUTHORED sea=16 air_wisps=24 keepouts={len(keepouts)} mask_bytes={int(np.prod(MASK_DIMS))}")


if __name__ == "__main__":
    main()
