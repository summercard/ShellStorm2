from __future__ import annotations

import json
from pathlib import Path


LIBRARIES = (
    ("office_room", "v009"),
    ("bridge_room", "v010"),
    ("boss_room", "v011"),
    ("db_room", "v014"),
    ("l_corridor", "v012"),
)
CATALOG_PATH = Path(
    "assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)
RUNTIME_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
)
COMPONENT_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/components/room_type_components"
)
SOURCE_ROOT = Path(
    "art_source/environments/tower_zones/expedition/source/common_components"
)
IMPORT_SCRIPT = (
    "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
)

# 仅按稳定房型 + AssetID 命中。不要改成只按 slug，否则同名组件会被误分段。
SEGMENTED_COLLISION_BOXES = {
    (
        "db_room",
        "ENV-EXPEDITION-L01-DB-WORKBENCH_A",
    ): (
        {
            "name": "BackArm",
            "shape_id": "BoxShape3D_back_arm",
            "size": (14.1, 3.565, 1.75),
            "position": (0.0, 1.7825, -2.75),
        },
        {
            "name": "SideArm",
            "shape_id": "BoxShape3D_side_arm",
            "size": (1.85, 3.565, 5.5),
            "position": (6.125, 1.7825, 0.875),
        },
    ),
}

## —— 顶盖遮光件（TOP COVER）——
##
## 玩法口径（唯一消费方 `EnemyIllumination3D._evaluate_sunlight`）：不读画面、不读材质，
## 只从怪物身体采样点沿主太阳方向打一条 `occlusion_mask = 1`（关卡静态世界层）的物理射线。
## 命中 ⇒ 该采样点在投影里；未命中 ⇒ 判 `sunlight`。**能投阴影 ≠ 能挡住这条射线**：
## 阴影是渲染层的事，射线只认同层带 `CollisionShape3D` 的静态刚体。所以
## 「封顶天花板画面上有影、僵尸照样受阳光」的根因永远是「这件顶盖的 prefab 里没有碰撞体」。
##
## 本表按**稳定房型 + slug**冻结「哪几件是顶盖」。命中即统一按顶盖规范下发：
##   slot_role        = room_type_component —— 水平顶盖不是墙：不进墙/门槽 lane 台账
##                      （`classify_door_lane`），也不写 `tower_wall_direction`
##                      （那条 meta 是四向墙的语义）。
##   collision_owner  = self
##   collision_policy = structural_box_proxy
##   ⇒ prefab 内嵌 1 个 `layer = 1` 的 BoxShape3D，尺寸 = 组件全包络，位于 y = +高/2。
##
## 为什么用「全包络盒」而不是照几何切段：顶盖全在 y ≈ 11.15~11.87，远高于玩家与子弹的
## 常用高度，包络盒不会造成空阻挡；而房型顶盖件（`wall_top_service` / `ceiling_ring_beam`）
## 本身是**中空周圈**，包络盒恰好把周圈内侧封成整片顶盖 —— 这正是封顶想要的结果。
##
## 🔴 本条规范的前身是 `office_room` 的 `slug.startswith("wall_t")`：`wall_top_service`
## 因为**前缀撞上墙族**而恰好拿到了碰撞。靠命名巧合生效的契约必须消灭，所以现在两件事
## 分开登记：墙族走显式名单 `*_SOLID_WALL_SLUGS`，顶盖走本表。
## 守卫：`main()` 会断言本表每个 slug 在对应库里真实存在，且最终确实产出碰撞体。
TOP_COVER_OCCLUDER_SLUGS = {
    "office_room": {
        "wall_top_service",
        "ceiling_deck_5m",
        "ceiling_ring_beam",
        "ceiling_lighting",
        "ceiling_service_cable_tray",
        "ceiling_service_duct",
        "ceiling_service_pipe_run",
    },
    "db_room": {
        "wall_top_service",
        "ceiling_deck_40m",
        "ceiling_deck_10m",
        "ceiling_ring_beam",
        "ceiling_lighting",
        "ceiling_service_a",
        "ceiling_service_b",
        "ceiling_service_c",
    },
}
TOP_COVER_CLASSIFICATION = ("room_type_component", "self", "structural_box_proxy")

OFFICE_BOX_COLLISION = {
    "filing_run",
    "locker_bank",
    "power_cabinet_bank",
    "prep_bench",
    "printer_station",
    "shelving",
    "totem_column",
    "water_and_supply_corner",
    "work_cluster",
}
## 办公室**墙族**的显式名单。原实现是 `slug.startswith("wall_t")`，会把 `wall_top_service`
## （顶盖，非墙）一起吞进来并当成实墙 —— 顶盖因此被写进墙/门槽 lane 台账、还挂上一条
## 无意义的 `tower_wall_direction`。这里逐个列出真正是墙的三件，不再按前缀猜。
OFFICE_SOLID_WALL_SLUGS = {"wall_t1110_5m", "wall_t615_5m", "wall_t970_5m"}
BRIDGE_BOX_COLLISION = {
    "bank_crate",
    "bridge_guardrail",
    "end_crate",
    "end_power",
    "half_partition",
    "lower_control",
    "near_crate",
    "near_server",
    "partition_box",
    "pit_end",
    "pit_side",
    "platform_edge",
    "shaft_column",
    "upper_bank_z5450",
    "upper_bank_z6197",
    "upper_console",
    "vertical_service",
}
BOSS_BOX_COLLISION = {
    "server_rack",
    "server_rack_tall",
    "server_rack_mid",
    "server_rack_damaged",
    "server_rack_damaged_tall",
    "server_rack_wide",
    "server_rack_wide_tall",
    "server_rack_wide_damaged",
    "server_rack_wide_damaged_tall",
    "server_rack_compact",
    "server_rack_compact_damaged",
    "server_rack_under_screen",
    "server_rack_under_screen_damaged",
    "workstation_a",
    "workstation_b",
    "workstation_c",
    "chair",
    "plant_a",
    "plant_b",
    "plant_c",
    "archive_shelf",
    # 门垛 / 门楣：Boss 房自有的门位三件，必须给碰撞（挡住门洞两侧与上方），
    # 但**不能**登记成 solid_wall —— 门楣中心正好落在本局门槽车道上，
    # 走 solid_wall 会被运行时提升成整樘门墙，把已留好的 2.2×2.8 门洞重新封死。
    "wall_door_pier_5m",
    "wall_door_lintel_5m",
}
BOSS_VISUAL_ONLY = {
    "debris_large",
    "debris_medium",
    "debris_small",
    "floor_base",
    "main_fault_screen",
    "heavy_conduits",
    "wall_typography",
    "floor_marking",
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_text_crlf(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    path.write_bytes(normalized.replace("\n", "\r\n").encode("utf-8"))


def write_json_crlf(path: Path, data: dict) -> None:
    write_text_crlf(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def godot_bounds(bounds: list[float]) -> list[float]:
    return [float(bounds[0]), float(bounds[2]), float(bounds[1])]


def classify(room_slug: str, slug: str) -> tuple[str, str, str]:
    # 顶盖遮光件优先于所有房型分支：office / db 都有同名 `wall_top_service`，
    # 且它必须在两个库里拿到同一条规范，不能被各自的房型分支各判一次。
    if slug in TOP_COVER_OCCLUDER_SLUGS.get(room_slug, ()):
        return TOP_COVER_CLASSIFICATION
    if room_slug == "boss_room":
        # Boss 房主层地砖 = floor_tile（进刷怪格）；墙/装甲墙 = solid_wall（参与门槽判定）。
        if slug.startswith("floor_tile_5m"):
            return "floor_tile", "floor_support", "external_floor_support"
        if slug == "wall_solid_5m" or slug.startswith("wall_skin_"):
            return "solid_wall", "self", "structural_box_proxy"
        if slug in BOSS_BOX_COLLISION:
            return "room_type_component", "self", "safe_box_proxy"
        if slug in BOSS_VISUAL_ONLY:
            return "room_type_component", "none", "visual_only"
        raise RuntimeError(f"未分类的 Boss 房组件 slug: {slug}")
    if room_slug == "db_room":
        if slug.startswith("floor_tile_5m"):
            return "floor_tile", "floor_support", "external_floor_support"
        if slug in {
            "server_rack_a", "server_rack_b", "server_rack_c", "server_rack_d",
            "service_cart", "shelf", "island_cart", "raised_service_a", "raised_service_b",
            "cable_reel", "workbench_a", "workbench_b", "repair_island", "equipment_rack",
            "service_terminal", "shelving",
        }:
            return "room_type_component", "self", "safe_box_proxy"
        return "room_type_component", "none", "visual_only"
    if room_slug == "l_corridor":
        if slug.startswith("floor_tile_5m"):
            return "floor_tile", "floor_support", "external_floor_support"
        if slug.startswith("wall_5m"):
            return "solid_wall", "self", "structural_box_proxy"
        if slug in {
            "access_console_a", "access_console_b", "crate", "planter", "server_rack",
            "service_cart_a", "service_cart_b",
        }:
            return "room_type_component", "self", "safe_box_proxy"
        return "room_type_component", "none", "visual_only"
    if room_slug == "office_room":
        if slug == "door_wall":
            return "door_wall", "room_door_owned", "split_door_wall_proxy"
        if slug == "floor_tile_5m":
            return "floor_tile", "floor_support", "external_floor_support"
        if slug in OFFICE_SOLID_WALL_SLUGS:
            return "solid_wall", "self", "structural_box_proxy"
        if slug in OFFICE_BOX_COLLISION:
            return "room_type_component", "self", "safe_box_proxy"
        return "room_type_component", "none", "visual_only"
    if slug == "tile_upper":
        return "floor_tile", "floor_support", "external_floor_support"
    if slug == "tile_lower":
        return "room_type_component", "none", "lower_level_visual_only"
    if slug in {"wall_x670", "wall_x780"}:
        return "solid_wall", "self", "structural_box_proxy"
    if slug in BRIDGE_BOX_COLLISION:
        return "room_type_component", "self", "safe_box_proxy"
    return "room_type_component", "none", "visual_only"


def tscn_text(
    room_slug: str,
    version: str,
    package: dict,
    slot_role: str,
    collision_owner: str,
    collision_policy: str,
) -> str:
    slug = str(package["slug"])
    component_id = str(package["component_id"])
    bounds = godot_bounds(package["bounds_size_m"])
    bx, by, bz = bounds
    visual_path = (
        f"res://{COMPONENT_ROOT.as_posix()}/{room_slug}/{slug}/"
        f"{slug}_visual_top3d.glb"
    )
    source_blend = (
        f"res://{SOURCE_ROOT.as_posix()}/{version}/component_packages/{slug}/{slug}.blend"
    )
    subresources: list[str] = []
    collision_nodes: list[str] = []
    load_steps = 2
    segmented_boxes = SEGMENTED_COLLISION_BOXES.get((room_slug, component_id))
    if segmented_boxes is not None:
        load_steps += len(segmented_boxes)
        for box in segmented_boxes:
            sx, sy, sz = box["size"]
            subresources.extend(
                [
                    f'[sub_resource type="BoxShape3D" id="{box["shape_id"]}"]',
                    f"size = Vector3({sx:g}, {sy:g}, {sz:g})",
                    "",
                ]
            )
        collision_nodes.extend(
            [
                '[node name="CollisionBody" type="StaticBody3D" parent="."]',
                "collision_layer = 1",
                "collision_mask = 0",
                "",
            ]
        )
        for box in segmented_boxes:
            px, py, pz = box["position"]
            collision_nodes.extend(
                [
                    f'[node name="{box["name"]}" type="CollisionShape3D" parent="CollisionBody"]',
                    f"position = Vector3({px:g}, {py:g}, {pz:g})",
                    f'shape = SubResource("{box["shape_id"]}")',
                    "",
                ]
            )
    elif collision_policy in {"safe_box_proxy", "structural_box_proxy"}:
        load_steps += 1
        subresources.extend(
            [
                '[sub_resource type="BoxShape3D" id="BoxShape3D_proxy"]',
                f"size = Vector3({bx:g}, {by:g}, {bz:g})",
                "",
            ]
        )
        collision_nodes.extend(
            [
                '[node name="CollisionBody" type="StaticBody3D" parent="."]',
                "collision_layer = 1",
                "collision_mask = 0",
                "",
                '[node name="CollisionShape" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3(0, {by * 0.5:g}, 0)",
                'shape = SubResource("BoxShape3D_proxy")',
                "",
            ]
        )
    elif collision_policy == "split_door_wall_proxy":
        load_steps += 3
        jamb_width = max((bx - 2.2) * 0.5, 0.1)
        header_height = max(by - 2.5, 0.1)
        subresources.extend(
            [
                '[sub_resource type="BoxShape3D" id="BoxShape3D_jamb"]',
                f"size = Vector3({jamb_width:g}, 2.5, {bz:g})",
                "",
                '[sub_resource type="BoxShape3D" id="BoxShape3D_header"]',
                f"size = Vector3({bx:g}, {header_height:g}, {bz:g})",
                "",
            ]
        )
        jamb_x = 1.1 + jamb_width * 0.5
        collision_nodes.extend(
            [
                '[node name="CollisionBody" type="StaticBody3D" parent="."]',
                "collision_layer = 1",
                "collision_mask = 0",
                "",
                '[node name="LeftJamb" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3({-jamb_x:g}, 1.25, 0)",
                'shape = SubResource("BoxShape3D_jamb")',
                "",
                '[node name="RightJamb" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3({jamb_x:g}, 1.25, 0)",
                'shape = SubResource("BoxShape3D_jamb")',
                "",
                '[node name="Header" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3(0, {2.5 + header_height * 0.5:g}, 0)",
                'shape = SubResource("BoxShape3D_header")',
                "",
            ]
        )
    root_name = "RoomTypeComponent" + "".join(part.title() for part in slug.split("_"))
    lines = [
        f"[gd_scene load_steps={load_steps} format=3]",
        "",
        f'; Stable AssetID: {component_id}',
        f'; 房型组件 {room_slug} / {version} / {slug}',
        f'[ext_resource type="PackedScene" path="{visual_path}" id="1_visual"]',
        "",
        *subresources,
        f'[node name="{root_name}" type="Node3D"]',
        f'metadata/asset_id = "{component_id}"',
        f'metadata/asset_version = "{version}"',
        f'metadata/room_type = "{package["room_type"]}"',
        f'metadata/component_slug = "{slug}"',
        f'metadata/display_name_zh = "{package["name_zh"]}"',
        f'metadata/source_blend = "{source_blend}"',
        'metadata/origin_contract = "bottom_center"',
        f'metadata/front_axis_blender = "{package["front_axis"]}"',
        'metadata/up_axis = "+Y"',
        f"metadata/bounds_size_m = Vector3({bx:g}, {by:g}, {bz:g})",
        f'metadata/slot_role = "{slot_role}"',
        f'metadata/collision_owner = "{collision_owner}"',
        f'metadata/collision_policy = "{collision_policy}"',
        f"metadata/collision_shape_count = {len([line for line in collision_nodes if 'type=\"CollisionShape3D\"' in line])}",
        'metadata/runtime_instantiation = "per_instance_prefab"',
        "",
        '[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]',
        "",
        *collision_nodes,
    ]
    return "\n".join(lines).rstrip() + "\n"


def patch_import(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    text = path.read_text(encoding="utf-8")
    if 'import_script/path=""' in text:
        text = text.replace(
            'import_script/path=""', f'import_script/path="{IMPORT_SCRIPT}"'
        )
    elif "import_script/path=" not in text:
        raise RuntimeError(f"missing import_script/path in {path}")
    else:
        lines = text.splitlines()
        lines = [
            f'import_script/path="{IMPORT_SCRIPT}"'
            if line.startswith("import_script/path=")
            else line
            for line in lines
        ]
        text = "\n".join(lines) + "\n"
    text = text.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=0")
    write_text_crlf(path, text)


## 故意**不**承担遮光的 `ceiling_*` 组件（留空 = 所有顶盖件都必须遮光）。
## 门禁 3 会拦住每一个未登记的 `ceiling_*`；确有不遮光意图的（纯装饰吊顶）写在这里，
## 而不是靠「不写就默认不遮光」—— 那种默认值正是封顶漏光的成因。
TOP_COVER_OPT_OUT: set[tuple[str, str]] = set()


def assert_top_cover_contract(
    seen_slugs: dict[str, set[str]],
    top_cover_hits: dict[tuple[str, str], tuple[str, str, str]],
) -> None:
    """顶盖遮光契约的三道门禁，全部硬失败（`RuntimeError`），不静默降级。

    1. **声明了却查无此件** —— 组件被改名/删除后契约会静默失效：房间照样装配成功，
       僵尸又开始晒太阳，没有任何一处报错。这是「看不见的退化」，必须断言。
    2. **命中却没拿到碰撞** —— 顶盖只投阴影、挡不住太阳射线，正是本契约要消灭的病症；
       同时钉住 `slot_role` 不能退回 `solid_wall`（水平顶盖不是墙，不该进墙/门槽 lane 台账）。
    3. **叫 `ceiling_*` 却没登记** —— 将来新增吊顶件不会自动继承规范。默认值必须是
       「必须表态」，而不是「默认不遮光」；确有不遮光意图的写进 `TOP_COVER_OPT_OUT`。
    """
    declared = {
        (room_slug, slug)
        for room_slug, slugs in TOP_COVER_OCCLUDER_SLUGS.items()
        for slug in slugs
    }
    missing = sorted(
        (room_slug, slug)
        for room_slug, slug in declared
        if slug not in seen_slugs.get(room_slug, set())
    )
    if missing:
        raise RuntimeError(f"顶盖遮光契约登记的组件在源库里不存在: {missing}")
    expected_role, expected_owner, expected_policy = TOP_COVER_CLASSIFICATION
    for (room_slug, slug), classification in sorted(top_cover_hits.items()):
        slot_role, collision_owner, collision_policy = classification
        if (collision_owner, collision_policy) != (expected_owner, expected_policy):
            raise RuntimeError(
                f"顶盖 {room_slug}/{slug} 未按规范下发碰撞: {classification}"
            )
        if slot_role != expected_role:
            raise RuntimeError(
                f"顶盖 {room_slug}/{slug} 的 slot_role 必须是 {expected_role}"
                f"（水平顶盖不是墙）: 实得 {slot_role}"
            )
    unregistered = sorted(
        (room_slug, slug)
        for room_slug, slugs in seen_slugs.items()
        for slug in slugs
        if slug.startswith("ceiling_")
        and (room_slug, slug) not in declared
        and (room_slug, slug) not in TOP_COVER_OPT_OUT
    )
    if unregistered:
        raise RuntimeError(
            f"这些 ceiling_* 组件没登记进顶盖遮光契约，封顶会漏光: {unregistered}"
        )


def main(root: Path | None = None) -> None:
    root = root or Path(__file__).resolve().parents[1]
    runtime_catalog_path = root / CATALOG_PATH
    runtime_catalog = read_json(runtime_catalog_path)
    existing = [
        entry
        for entry in runtime_catalog.get("components", [])
        if not str(entry.get("component_id", "")).startswith(
            (
                "ENV-EXPEDITION-L01-OFFICE-",
                "ENV-EXPEDITION-L01-BRIDGE-",
                "ENV-EXPEDITION-L01-BOSS-",
                "ENV-EXPEDITION-L01-DB-",
                "ENV-EXPEDITION-L01-CORRIDOR-",
            )
        )
    ]
    generated: list[dict] = []
    manifest_records: list[dict] = []
    seen_slugs: dict[str, set[str]] = {}
    top_cover_hits: dict[tuple[str, str], tuple[str, str, str]] = {}
    for room_slug, version in LIBRARIES:
        catalog_path = root / SOURCE_ROOT / version / "component_catalog.json"
        catalog = read_json(catalog_path)
        seen_slugs.setdefault(room_slug, set())
        for package in catalog["packages"]:
            slug = str(package["slug"])
            seen_slugs[room_slug].add(slug)
            component_id = str(package["component_id"])
            slot_role, collision_owner, collision_policy = classify(room_slug, slug)
            if slug in TOP_COVER_OCCLUDER_SLUGS.get(room_slug, ()):
                top_cover_hits[(room_slug, slug)] = (slot_role, collision_owner, collision_policy)
            runtime_rel = RUNTIME_ROOT / room_slug / slug / f"{slug}_root_top3d.tscn"
            component_rel = COMPONENT_ROOT / room_slug / slug / f"{slug}_visual_top3d.glb"
            import_rel = Path(f"{component_rel.as_posix()}.import")
            if not (root / component_rel).is_file():
                raise FileNotFoundError(root / component_rel)
            write_text_crlf(
                root / runtime_rel,
                tscn_text(
                    room_slug,
                    version,
                    package,
                    slot_role,
                    collision_owner,
                    collision_policy,
                ),
            )
            patch_import(root / import_rel)
            bounds = godot_bounds(package["bounds_size_m"])
            entry = {
                "component_id": component_id,
                "kind": "room_type",
                "aliases": [],
                "slug": slug,
                "category": str(package["name_zh"]),
                "room_type": str(package["room_type"]),
                "slot_role": slot_role,
                "source_package_id": str(package.get("source_package_id", component_id)),
                "prefab_asset_id": component_id,
                "prefab_path": f"res://{runtime_rel.as_posix()}",
                "bounds_size_m_godot": bounds,
                "collision_owner": collision_owner,
                "collision_policy": collision_policy,
                "note": "房型组件默认布局重放；坐标由 component_instances.json 唯一提供。",
            }
            generated.append(entry)
            manifest_records.append(
                {
                    "component_id": component_id,
                    "room_type": str(package["room_type"]),
                    "version": version,
                    "slug": slug,
                    "slot_role": slot_role,
                    "collision_owner": collision_owner,
                    "collision_policy": collision_policy,
                    "bounds_size_m_godot": bounds,
                    "visual_glb": f"res://{component_rel.as_posix()}",
                    "prefab_path": f"res://{runtime_rel.as_posix()}",
                    "source_blend": (
                        f"res://{SOURCE_ROOT.as_posix()}/{version}/component_packages/"
                        f"{slug}/{slug}.blend"
                    ),
                }
            )
    assert_top_cover_contract(seen_slugs, top_cover_hits)

    ids = [str(entry["component_id"]) for entry in existing + generated]
    if len(ids) != len(set(ids)):
        raise RuntimeError("duplicate component_id after catalog merge")
    runtime_catalog["component_count"] = len(existing) + len(generated)
    # 来源清单随 LIBRARIES 走，避免版本升版后再出现写死的旧版本号。
    runtime_catalog["room_type_sources"] = [
        f"{SOURCE_ROOT.as_posix()}/{version}/component_catalog.json"
        for _room_slug, version in LIBRARIES
    ]
    runtime_catalog["components"] = existing + generated
    write_json_crlf(runtime_catalog_path, runtime_catalog)
    manifest = {
        "schema": "shellstorm2.expedition.room_type_component_runtime.v001",
        "component_count": len(manifest_records),
        "catalog_component_count": len(existing) + len(generated),
        "import_script": IMPORT_SCRIPT,
        # 组件库清单是**库级**的，不声明逐房间装配分支；`assembly_route` 属具体房间，
        # 写在各房间的 runtime/room_instances/<room_id>/room_runtime_manifest.json 里。
        "room_runtime_manifests": (
            "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/"
        ),
        "assembly_route_scope": "per_room_instance",
        "records": manifest_records,
    }
    write_json_crlf(root / RUNTIME_ROOT / "runtime_manifest.json", manifest)
    print(f"ROOM_TYPE_PREFABS_WRITTEN:{len(manifest_records)}")
    print(f"SHELL_COMPONENT_CATALOG_COUNT:{runtime_catalog['component_count']}")


if __name__ == "__main__":
    main()
