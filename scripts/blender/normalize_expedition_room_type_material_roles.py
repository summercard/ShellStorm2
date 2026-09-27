"""把远征办公室/通道桥房型组件的结构面角色从「精工金属」校正为「细腻哑光」。

背景：这两批房型源的建模脚本把精工金属（metallic 0.86）当成结构件的默认材质
（`box(..., mat=0, cell=PANEL)`），于是 60 个组件的全部结构面都成了高金属度材质。
Godot 侧没有反射来源（`reflected_light_source = SKY` 但无天空，全项目无 ReflectionProbe），
金属面只剩直接高光，大面积发黑 ⇒「打灯没有效果」。
项目其它房间的结构面统一用「细腻哑光」（metallic 0.03），本脚本把这两批对齐。

只改材质槽指向，不动几何、不动 UV、不动色盘格 ⇒ 房间配色不变，只是恢复受光。
幂等：重复执行不会二次改动。

Run with Blender 4.5+:
  blender --factory-startup --background --python <this> -- --project-root <root>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy

LIBRARIES = (
    ("office_room", "v006"),
    ("bridge_room", "v007"),
)
LIBRARY_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/source/common_components"
)
SHARED_PALETTE = Path("assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")

METAL_ROLE_PREFIX = "01_精工金属"
MATTE_ROLE = "02_细腻哑光_青绿大面"
## 与建模脚本 conf 表一致的 PBR 参数：角色 1 = 细腻哑光。
MATTE_CONF = {"office_room": (0.04, 0.72, 0.0), "bridge_room": (0.03, 0.70, 0.0)}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def ensure_matte_material(room_slug: str, palette_path: Path) -> bpy.types.Material:
    """取回「细腻哑光」材质；库里没有时按标准四角色口径新建。"""
    existing = bpy.data.materials.get(MATTE_ROLE)
    if existing is not None:
        return existing
    metallic, roughness, coat = MATTE_CONF[room_slug]
    material = bpy.data.materials.new(MATTE_ROLE)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    texture = nodes.new("ShaderNodeTexImage")
    if palette_path.is_file():
        texture.image = bpy.data.images.load(str(palette_path), check_existing=True)
    texture.interpolation = "Closest"
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Coat Weight"].default_value = coat
    links.new(uv.outputs["UV"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    print("  ! 新建材质 %s（metallic=%s rough=%s）" % (MATTE_ROLE, metallic, roughness))
    return material


def remap_blend(blend_path: Path, room_slug: str, palette_path: Path) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    matte = ensure_matte_material(room_slug, palette_path)
    slots_replaced = 0
    faces_affected = 0
    objects_touched = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.material_slots:
            continue
        touched = False
        for index, slot in enumerate(obj.material_slots):
            current = slot.material
            if current is None or not current.name.startswith(METAL_ROLE_PREFIX):
                continue
            slot.material = matte
            slots_replaced += 1
            touched = True
            faces_affected += sum(
                1 for polygon in obj.data.polygons if polygon.material_index == index
            )
        if touched:
            objects_touched += 1
    if slots_replaced:
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    return {
        "blend": blend_path.as_posix(),
        "objects_touched": objects_touched,
        "slots_replaced": slots_replaced,
        "faces_affected": faces_affected,
        "saved": bool(slots_replaced),
    }


def main() -> None:
    args = parse_args()
    root = Path(args.project_root).resolve()
    palette_path = root / SHARED_PALETTE
    records: list[dict] = []
    for room_slug, version in LIBRARIES:
        library_root = root / LIBRARY_ROOT / version
        catalog = json.loads(
            (library_root / "component_catalog.json").read_text(encoding="utf-8")
        )
        targets: list[Path] = []
        master = (
            library_root / f"expedition_{room_slug}_components_source_{version}.blend"
        )
        if master.is_file():
            targets.append(master)
        for package in catalog["packages"]:
            slug = package["slug"]
            blend = library_root / "component_packages" / slug / f"{slug}.blend"
            if not blend.is_file():
                raise FileNotFoundError(blend)
            targets.append(blend)
        print("==== %s / %s 目标 blend %d 个" % (room_slug, version, len(targets)))
        for blend in targets:
            record = remap_blend(blend, room_slug, palette_path)
            record.update({"room_type": room_slug, "version": version})
            records.append(record)
            print(
                "  %-46s 槽=%d 面=%d%s"
                % (
                    blend.name,
                    record["slots_replaced"],
                    record["faces_affected"],
                    "" if record["saved"] else "（已是哑光，跳过）",
                )
            )
    report_path = (
        root
        / "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
        / "material_role_correction.json"
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(
            {
                "schema": "shellstorm2.expedition.room_type_material_role_correction.v001",
                "reason": (
                    "这两批房型源把精工金属(metallic 0.86)当结构件默认材质；"
                    "Godot 无反射来源 ⇒ 大面积不受光。校正为细腻哑光(metallic 0.03)，"
                    "与其它房间口径一致。几何/UV/色盘格不变。"
                ),
                "from_role": METAL_ROLE_PREFIX,
                "to_role": MATTE_ROLE,
                "records": records,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    total_slots = sum(record["slots_replaced"] for record in records)
    total_faces = sum(record["faces_affected"] for record in records)
    print(
        "ROOM_TYPE_MATERIAL_ROLE_NORMALIZED:blends=%d slots=%d faces=%d => %s"
        % (len(records), total_slots, total_faces, report_path)
    )


if __name__ == "__main__":
    main()
