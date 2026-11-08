# 远征03 大回廊撤除作者宝箱

日期：2026-11-08。FeatureID：`WORLD-PLAN` / `ASSET-PIPELINE`。按业主当日裁定执行：**通道房不应该有宝箱，其他不变**。

## 问题与根因

大回廊 `combat_45x40_6351962d84c2_007418` 每局都固定刷一只宝箱，品质恒为 `common`，不受 `treasure_chests` 的品质权重与拟态配置影响。

原因不是生成器，而是作者美术自带标记。正式 TSCN 里有一个 `Marker3D`：

```
[node name="GalleryCache" type="Marker3D" parent="ArtComponents/WorkshopLayout"]
metadata/slot_role = "treasure_chest"
metadata/treasure_chest_config = {"id": "gallery_cache", "quality": "common", ...}
```

`DungeonRoom3D._build_treasure_chests()` 除读房间的 `chest_placements` 外，还会扫描 `AuthoredLayoutArtRoot` 下所有带 `treasure_chest_config` 的 `Marker3D` 并无条件建箱。该美术文件按「房型模板 + 几何签名 + 原型指纹」复用，同名资源被所有 45×40 普通战斗房命中（枢纽 45×40 用的是另一个原型指纹 `_68065f`，不含此标记），所以表现为「通道房固定刷箱」。

## 改动

- 从正式 TSCN 删除 `GalleryCache` 这一 `Marker3D` 节点及其 `metadata/slot_role`、`metadata/treasure_chest_config`。文件其余节点、`Transform`、组件引用逐字不变。
- 中央书架围岛、可倒书柜 `cache_entrance` 的受击/倒塌/掉书、导航遮挡与持久化全部保留；中央仍是单入口，不形成穿心捷径。
- 生成器、`TreasureChest3D`、开箱协议、`treasure_chests` 配置、其他房间的宝箱均未改动。两间独立 `REWARD` 宝箱房与 Boss 保底箱照旧。
- 验证断言同步：`tests/verification/verify_expedition03_workshop_layouts.gd` 的 `combat_45` 分支由「恰好一只作者宝箱」改为「没有作者宝箱」，删除 `gallery_cache` 开箱状态断言，保留书架倒塌与围岛可达性断言。

## 验证

| 项目 | 结果 |
| --- | --- |
| 工坊布局专项（headless，隔离 APPDATA） | `EXP03_WORKSHOP_LAYOUTS OK checks=1198 failures=0`，退出 0；大回廊 36 件可交互、20 件内部护墙、26 个候选门位全部通过。 |
| 作者宝箱 | `room.get_treasure_chests()` 为空，`gallery_cache` 不再存在。 |
| 书架围岛 | 倒塌后释放 8 本书、`reactive_props` 状态入账；围岛内部 `(0,-8)` 可达。 |

场景账本《房间运行登记》已同步该房间 SHA（撤除前 `acb232bb…`，撤除后 `3a2c2df5…`，均为 LF 规范化内容哈希）、更新时间、备注、验收依据与本轮状态；域变更日志记 `v0.1.79`。组件实例数、陈设件数、家具碰撞数不变 —— 被删的是 `Marker3D`，不是 Prefab 实例。

## 未执行项

- 未做整关战斗体验实机复核；其他房型与本轮无关，未改动。
- 未评估「中央围岛失去奖励后是否需要一个非宝箱的回报点」这一设计问题，留待业主决定。整关状态维持 `partial`。
