# 2026-09-24 事务索引

| 时间 | 事务 | 摘要 |
| --- | --- | --- |
| 1858 | [`1858_expedition01_boss_components_prefab.md`](1858_expedition01_boss_components_prefab.md) | 远征01 Boss房 6 件专属组件：导出 GLB（Task #37）＋ 建范式 B 自包含 PackedScene（Task #38）；探针 pass=96 fail=0；6 件全部按设计无内嵌阻挡 |
| 1911 | [`1911_expedition01_shell_component_catalog.md`](1911_expedition01_shell_component_catalog.md) | 壳体组件改注册表驱动（Task #39）：新建跨区运行时注册表 `shared/runtime/shell_component_catalog.json`＋探针 pass=82 fail=0；区块00 回归保持 checks=230 |
| 1949 | [`1949_expedition01_shell_layout_builder.md`](1949_expedition01_shell_layout_builder.md) | 通用壳体组合器（Task #41）：新建 `RoomShellLayoutBuilder3D.gd`（**区块级** lane 归属：共角去重 → L 臂预留 → 共面去重，顺序不能换）＋探针 pass=1619 fail=0（重放区块00 逐值一致＋运行时形状对照）；区块00 回归 checks=230、classname 172 无重复 |

> 早于本目录的单文件日记 `../2026-09-24.md` 若存在则为旧格式，不再追加。
