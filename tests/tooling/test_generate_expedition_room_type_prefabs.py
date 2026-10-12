#!/usr/bin/env python3
"""生成器的最小回归：只验证 workbench_a 分段与其它输出零漂移。"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "scripts/generate_expedition_room_type_prefabs.py"
CATALOG_PATH = Path(
    "assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)
SOURCE_ROOT = Path(
    "art_source/environments/tower_zones/expedition/source/common_components"
)
COMPONENT_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/components/room_type_components"
)
RUNTIME_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
)
LIBRARIES = (
    ("office_room", "v009"),
    ("bridge_room", "v010"),
    ("boss_room", "v011"),
    ("db_room", "v014"),
    ("l_corridor", "v012"),
)
TARGET_ID = "ENV-EXPEDITION-L01-DB-WORKBENCH_A"
TARGET_SLUG = ("db_room", "workbench_a")


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_head_module(temp_dir: Path):
    head_path = temp_dir / "generate_expedition_room_type_prefabs_head.py"
    result = subprocess.run(
        ["git", "show", f"HEAD:{GENERATOR.relative_to(ROOT).as_posix()}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    head_path.write_bytes(result.stdout)
    return load_module(head_path, "generator_head")


def packages():
    for room_slug, version in LIBRARIES:
        path = ROOT / SOURCE_ROOT / version / "component_catalog.json"
        for package in json.loads(path.read_text(encoding="utf-8"))["packages"]:
            yield room_slug, version, package


## 常量取自**当前**生成器（不是 HEAD）——门禁与合法变更集必须跟着现行契约走。
CONTRACT = load_module(GENERATOR, "generator_contract")
TOP_COVER_OCCLUDER_SLUGS = CONTRACT.TOP_COVER_OCCLUDER_SLUGS


def expected_changed_slugs() -> set[tuple[str, str]]:
    """本生成器相对 HEAD **合法**发生文本变更的组件集合。

    · `db_room/workbench_a` —— 分段碰撞盒（`SEGMENTED_COLLISION_BOXES`）；
    · 顶盖遮光件 —— 从 `visual_only` 改成 `structural_box_proxy`，补出 `layer=1` 的碰撞盒
      （封顶挡太阳射线的唯一手段，见生成器 `TOP_COVER_OCCLUDER_SLUGS`）。

    除这两类之外任何组件发生漂移都是回归，必须失败。
    """
    changed = {TARGET_SLUG}
    for room_slug, slugs in TOP_COVER_OCCLUDER_SLUGS.items():
        for slug in slugs:
            changed.add((room_slug, slug))
    return changed


def test_target_and_non_targets() -> None:
    generator = load_module(GENERATOR, "generator_current")
    changed = expected_changed_slugs()
    seen: set[tuple[str, str]] = set()
    with tempfile.TemporaryDirectory() as temp_dir:
        head = load_head_module(Path(temp_dir))
        for room_slug, version, package in packages():
            slug = str(package["slug"])
            seen.add((room_slug, slug))
            classification = generator.classify(room_slug, slug)
            current = generator.tscn_text(room_slug, version, package, *classification)
            baseline_classification = head.classify(room_slug, slug)
            baseline = head.tscn_text(
                room_slug, version, package, *baseline_classification
            )
            if str(package["component_id"]) == TARGET_ID:
                assert 'load_steps=4' in current
                assert 'metadata/collision_shape_count = 2' in current
                assert 'size = Vector3(14.1, 3.565, 1.75)' in current
                assert 'id="BoxShape3D_proxy"' not in current
                assert 'position = Vector3(0, 1.7825, -2.75)' in current
                assert 'size = Vector3(1.85, 3.565, 5.5)' in current
                assert 'position = Vector3(6.125, 1.7825, 0.875)' in current
                assert 'shape = SubResource("BoxShape3D_proxy")' not in current
            elif (room_slug, slug) in changed:
                assert current != baseline, (
                    f"顶盖件 {room_slug}/{slug} 相对 HEAD 没有任何变更 —— 碰撞没补上"
                )
                assert 'metadata/collision_policy = "structural_box_proxy"' in current
                assert "metadata/collision_shape_count = 1" in current
                assert 'metadata/slot_role = "room_type_component"' in current
                assert 'shape = SubResource("BoxShape3D_proxy")' in current
            else:
                assert current == baseline, (
                    f"非目标组件生成文本发生漂移: {room_slug}/{package['slug']}"
                )

        # 顶盖契约登记的名字必须全部真实存在（改名不能静默让契约失效）。
        missing = sorted(changed - seen)
        assert not missing, f"顶盖遮光契约登记了源库里不存在的组件: {missing}"

        same_slug_other_identity = next(
            package
            for _room, _version, package in packages()
            if package["slug"] != "workbench_a"
        ).copy()
        same_slug_other_identity["slug"] = "workbench_a"
        same_slug_other_identity["component_id"] = "ENV-TEST-OTHER-WORKBENCH_A"
        classification = generator.classify("db_room", "workbench_a")
        output = generator.tscn_text(
            "db_room", "v014", same_slug_other_identity, *classification
        )
        assert 'load_steps=3' in output
        assert 'metadata/collision_shape_count = 1' in output
        assert 'shape = SubResource("BoxShape3D_proxy")' in output


def test_top_cover_guard_fails_loudly() -> None:
    """顶盖遮光契约的三道门禁都必须**会失败**，不能静默降级。"""
    generator = load_module(GENERATOR, "generator_guard")
    declared = {
        (room_slug, slug)
        for room_slug, slugs in generator.TOP_COVER_OCCLUDER_SLUGS.items()
        for slug in slugs
    }
    # 正常情况：全部命中且按规范下发。
    hits = {
        key: generator.TOP_COVER_CLASSIFICATION for key in declared
    }
    seen = {room_slug: set(slugs) for room_slug, slugs in generator.TOP_COVER_OCCLUDER_SLUGS.items()}
    generator.assert_top_cover_contract(seen, hits)

    # 门禁 1：登记了却查无此件（组件被改名/删除）⇒ 契约静默失效，必须炸。
    renamed = {room: set(slugs) for room, slugs in seen.items()}
    renamed["db_room"].discard("ceiling_deck_40m")
    try:
        generator.assert_top_cover_contract(renamed, hits)
    except RuntimeError as error:
        assert "不存在" in str(error), str(error)
    else:
        raise AssertionError("顶盖件被改名后门禁没有失败")

    # 门禁 2：命中却没拿到碰撞（退回 visual_only）⇒ 封顶只投阴影、挡不住射线，必须炸。
    no_collision = dict(hits)
    no_collision[("db_room", "ceiling_deck_40m")] = (
        "room_type_component",
        "none",
        "visual_only",
    )
    try:
        generator.assert_top_cover_contract(seen, no_collision)
    except RuntimeError as error:
        assert "未按规范下发碰撞" in str(error), str(error)
    else:
        raise AssertionError("顶盖退回 visual_only 后门禁没有失败")

    # 门禁 3：叫 ceiling_* 却没登记 ⇒ 新增吊顶件不会自动继承规范，必须炸。
    with_unknown = {room: set(slugs) for room, slugs in seen.items()}
    with_unknown["office_room"].add("ceiling_deck_9m")
    try:
        generator.assert_top_cover_contract(with_unknown, hits)
    except RuntimeError as error:
        assert "漏光" in str(error), str(error)
    else:
        raise AssertionError("未登记的 ceiling_* 组件没有让门禁失败")


def make_isolated_project(temp_dir: Path) -> Path:
    project = temp_dir / "project"
    for room_slug, version in LIBRARIES:
        source_dir = project / SOURCE_ROOT / version
        source_dir.mkdir(parents=True)
        source_catalog = ROOT / SOURCE_ROOT / version / "component_catalog.json"
        (source_dir / "component_catalog.json").write_bytes(source_catalog.read_bytes())
        for package in json.loads(source_catalog.read_text(encoding="utf-8"))["packages"]:
            slug = str(package["slug"])
            component_dir = project / COMPONENT_ROOT / room_slug / slug
            component_dir.mkdir(parents=True, exist_ok=True)
            (component_dir / f"{slug}_visual_top3d.glb").write_bytes(b"test")
            (component_dir / f"{slug}_visual_top3d.glb.import").write_text(
                'import_script/path=""\ngltf/embedded_image_handling=1\n',
                encoding="utf-8",
            )

    runtime_catalog = ROOT / CATALOG_PATH
    target_catalog = project / CATALOG_PATH
    target_catalog.parent.mkdir(parents=True, exist_ok=True)
    target_catalog.write_bytes(runtime_catalog.read_bytes())
    return project


def snapshot_tree(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob("*")
        if path.is_file()
    }


def test_isolated_generation_is_idempotent_and_changes_only_target_prefab() -> None:
    generator = load_module(GENERATOR, "generator_isolated")
    with tempfile.TemporaryDirectory() as temp_dir:
        project = make_isolated_project(Path(temp_dir))
        before = snapshot_tree(project)
        generator.main(project)
        after_first = snapshot_tree(project)
        generator.main(project)
        after_second = snapshot_tree(project)

        assert after_first == after_second, "临时目录重跑生成不幂等"
        changed = {
            path
            for path in set(before) | set(after_first)
            if before.get(path) != after_first.get(path)
        }
        target_prefab = (
            RUNTIME_ROOT
            / "db_room"
            / "workbench_a"
            / "workbench_a_root_top3d.tscn"
        ).as_posix()
        assert target_prefab in changed
        assert all(
            path.startswith("assets/art/environments/tower_zones/expedition/runtime/")
            or path.endswith(".import")
            or path == CATALOG_PATH.as_posix()
            for path in changed
        )
        generated = (
            project / RUNTIME_ROOT / "db_room" / "workbench_a" / "workbench_a_root_top3d.tscn"
        )
        text = generated.read_text(encoding="utf-8")
        assert 'metadata/collision_shape_count = 2' in text
        assert 'position = Vector3(6.125, 1.7825, 0.875)' in text


if __name__ == "__main__":
    test_target_and_non_targets()
    test_isolated_generation_is_idempotent_and_changes_only_target_prefab()
    test_top_cover_guard_fails_loudly()
    print("GENERATE_EXPEDITION_ROOM_TYPE_PREFABS_OK")
