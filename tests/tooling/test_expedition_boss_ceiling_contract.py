#!/usr/bin/env python3
"""Boss 房全封顶契约的门禁：摆位源 → 组件碰撞 → 静态场景，整链逐环断言。

## 为什么需要这个测试

Boss 房封顶是**唯一一处绕过 Blender 归并管线、由人工审计加入的房型实例**
（`component_instances.json` 的 `audited_additions`）。它同时依赖三件互相看不见的事：

  1. 摆位源里那 10 条 `ceiling_deck` 实例（房型布局），
  2. 该组件 prefab 里**带 `layer=1` 碰撞盒**（封顶拦太阳射线的唯一手段），
  3. 静态场景 TSCN 里真落成同名的 10 个节点 + 对得上的计数。

任何一环掉链子都**不会报错**，只会静默退化回「Boss 房白天全场受阳光、每秒掉血」——
正是这条契约要消灭的病症。所以三者必须一起被钉住。

## 背景（2026-10-12）

  · 封顶前实测：Boss 房 75/75 个身体采样点全部直达太阳（判 `sunlight`）。
  · 根因：`v011` 布局一件顶盖都没有；而且**画面上有阴影 ≠ 能挡住太阳射线**
    —— 阴影是渲染层的事，`EnemyIllumination3D._evaluate_sunlight` 只认
    `occlusion_mask = 1` 层上带 `CollisionShape3D` 的静态刚体。
  · 处置：复用 DB 房已验收的 `ENV-EXPEDITION-L01-DB-CEILING_DECK_40M`
    （同一族、同一条顶盖遮光规范），10 条 5m 宽板转 90° 后铺满 50×40。
"""
from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_LAYOUT = (
    ROOT
    / "art_source/environments/tower_zones/expedition/source/common_components"
    / "v011/component_instances.json"
)
RUNTIME_LAYOUT = ROOT / "data/layouts/expedition/v011/component_instances.json"
BOSS_SCENE = (
    ROOT
    / "assets/art/environments/tower_zones/expedition/runtime/room_instances"
    / "expedition_01/f00_boss_static_layout.tscn"
)
DECK_COMPONENT_ID = "ENV-EXPEDITION-L01-DB-CEILING_DECK_40M"
DECK_PREFAB = (
    ROOT
    / "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
    / "db_room/ceiling_deck_40m/ceiling_deck_40m_root_top3d.tscn"
)
ROOM_SIZE_M = (50.0, 40.0)
COVER_Y_M = 11.38
## 封顶前 v011 的 `authored_layout_room_type_component_count`（2026-10-12 实测）。
## 封顶只应在此基础上 +10，用于钉住「只加了顶盖、没有顺手改动别的分类」。
BOSS_ROOM_TYPE_BEFORE_CEILING = 58


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def ceiling_instances(doc: dict) -> list[dict]:
    return [
        item
        for item in doc["instances"]
        if str(item.get("component_id", "")) == DECK_COMPONENT_ID
    ]


def test_layout_has_full_cover() -> None:
    """摆位源里必须真的铺满屋顶：10 条、90°、同一标高、x 向无缝隙。"""
    for path in (SOURCE_LAYOUT, RUNTIME_LAYOUT):
        doc = read_json(path)
        decks = ceiling_instances(doc)
        assert len(decks) == 10, f"{path.name}: 封顶条数应为 10，实得 {len(decks)}"
        xs: list[float] = []
        for deck in decks:
            by, bz = float(deck["position_m"][1]), float(deck["position_m"][2])
            assert by == 0.0, f"{path.name}: {deck['instance_id']} 的 by 应为 0（屋顶跨 z 居中）"
            assert abs(bz - COVER_Y_M) < 1e-6, (
                f"{path.name}: {deck['instance_id']} 顶盖标高应为 {COVER_Y_M}，实得 {bz}"
            )
            assert float(deck.get("rotation_y_deg", 0.0)) == 90.0, (
                f"{path.name}: {deck['instance_id']} 必须转 90° 才能让 40m 长轴跨满房间纵深"
            )
            xs.append(float(deck["position_m"][0]))
        xs.sort()
        assert xs[0] - 2.5 == pytest_approx(-ROOM_SIZE_M[0] / 2), f"{path.name}: 西端没铺到墙"
        assert xs[-1] + 2.5 == pytest_approx(ROOM_SIZE_M[0] / 2), f"{path.name}: 东端没铺到墙"
        for left, right in zip(xs, xs[1:]):
            assert abs((right - left) - 5.0) < 1e-6, (
                f"{path.name}: {left} 与 {right} 之间有缝，太阳会从缝里漏进来"
            )


def pytest_approx(value: float) -> float:
    return round(value, 6)


def test_runtime_layout_is_source_projection() -> None:
    """`data/` 是 `art_source/` 的逐字节投影，不允许手工在 data/ 里改。"""
    assert SOURCE_LAYOUT.read_bytes() == RUNTIME_LAYOUT.read_bytes(), (
        "v011 组件实例布局发生了投影漂移；请跑 "
        "scripts/sync_runtime_design_data.py 重新投影"
    )


def test_resolved_count_matches_instances() -> None:
    """`resolved_instance_count` 是运行时期望值，不符会让整房回退成通用壳体。"""
    doc = read_json(RUNTIME_LAYOUT)
    validation = doc.get("validation", {})
    declared = int(
        validation.get("resolved_instance_count", validation.get("instance_count", -1))
    )
    assert declared == len(doc["instances"]), (
        f"resolved_instance_count={declared} 与实际实例数 {len(doc['instances'])} 不符"
    )


def test_deck_prefab_blocks_sun() -> None:
    """顶盖 prefab 必须内嵌 `layer = 1` 的碰撞盒 —— 这是拦太阳射线的唯一手段。"""
    text = DECK_PREFAB.read_text(encoding="utf-8")
    assert 'metadata/collision_policy = "structural_box_proxy"' in text, (
        "天花承板必须是 structural_box_proxy：visual_only 只投阴影、挡不住太阳射线"
    )
    assert "metadata/collision_shape_count = 1" in text
    assert "[node name=\"CollisionBody\" type=\"StaticBody3D\"" in text
    assert "collision_layer = 1" in text, "碰撞盒不在静态世界层，遮光射线穿不过去"
    assert "type=\"CollisionShape3D\"" in text


def test_boss_static_scene_carries_ceiling() -> None:
    """静态场景必须真落成 10 个封顶节点，且与摆位源计数对得上。"""
    # 场景一律 CRLF；先归一到 LF 再做逐块解析。
    text = BOSS_SCENE.read_bytes().decode("utf-8").replace("\r\n", "\n")
    blocks = {
        match.group(1): match.group(0)
        for match in re.finditer(
            r'^\[node name="(ceiling_deck_\d+)"[^\n]*\n(?:(?!\n\[node)[\s\S])*', text, re.M
        )
    }
    names = sorted(blocks)
    assert names == ["ceiling_deck_%02d" % i for i in range(10)], (
        f"Boss 静态场景的封顶节点不是 10 个：{names}"
    )
    for name in names:
        block = blocks[name]
        assert 'metadata/authored_slot_role = "room_type_component"' in block, (
            f"{name} 的 slot_role 必须是 room_type_component（水平顶盖不是墙）"
        )
        assert f'metadata/authored_component_id = "{DECK_COMPONENT_ID}"' in block, (
            f"{name} 引用的不是天花承板组件"
        )
        assert "11.38" in block, f"{name} 不在 11.38m 顶盖标高上"

    doc = read_json(RUNTIME_LAYOUT)
    expected_total = len(doc["instances"])
    total = re.search(r"metadata/layout_instance_total = (\d+)", text)
    assert total and int(total.group(1)) == expected_total, (
        f"场景 layout_instance_total 应为 {expected_total}"
    )
    room_type = int(
        re.search(
            r"metadata/authored_layout_room_type_component_count = (\d+)", text
        ).group(1)
    )
    # 封顶前 v011 的房型件计数是 58；封顶只应带来 +10 条天花承板。
    # 这条断言同时挡住两件事：漏算封顶件、以及顺手把别的件改了分类。
    assert room_type == BOSS_ROOM_TYPE_BEFORE_CEILING + len(names), (
        f"房型件计数应为 {BOSS_ROOM_TYPE_BEFORE_CEILING} + {len(names)} 条封顶 = "
        f"{BOSS_ROOM_TYPE_BEFORE_CEILING + len(names)}，实得 {room_type}"
    )


def test_audited_addition_is_declared() -> None:
    """人工加入的实例必须显式声明来源与重跑警告，否则下次归并会被静默覆盖。"""
    doc = read_json(RUNTIME_LAYOUT)
    additions = doc.get("audited_additions")
    assert isinstance(additions, list) and additions, (
        "封顶是人工审计加入的，必须在 audited_additions 里声明；"
        "否则重跑 regroup_room_type_components.py 会把整段覆盖掉且无人察觉"
    )
    entry = additions[0]
    assert entry.get("provenance") == "manual_audit"
    assert DECK_COMPONENT_ID in str(entry.get("component_reuse", ""))
    assert "regroup_room_type_components" in str(entry.get("regen_warning", ""))


if __name__ == "__main__":
    test_layout_has_full_cover()
    test_runtime_layout_is_source_projection()
    test_resolved_count_matches_instances()
    test_deck_prefab_blocks_sun()
    test_boss_static_scene_carries_ceiling()
    test_audited_addition_is_declared()
    print("EXPEDITION_BOSS_CEILING_CONTRACT_OK")
