# 2026-09-24 事务索引

| 时间 | 事务 | 摘要 |
| --- | --- | --- |
| 1858 | [`1858_expedition01_boss_components_prefab.md`](1858_expedition01_boss_components_prefab.md) | 远征01 Boss房 6 件专属组件：导出 GLB（Task #37）＋ 建范式 B 自包含 PackedScene（Task #38）；探针 pass=96 fail=0；6 件全部按设计无内嵌阻挡 |
| 1911 | [`1911_expedition01_shell_component_catalog.md`](1911_expedition01_shell_component_catalog.md) | 壳体组件改注册表驱动（Task #39）：新建跨区运行时注册表 `shared/runtime/shell_component_catalog.json`＋探针 pass=82 fail=0；区块00 回归保持 checks=230 |
| 1949 | [`1949_expedition01_shell_layout_builder.md`](1949_expedition01_shell_layout_builder.md) | 通用壳体组合器（Task #41）：新建 `RoomShellLayoutBuilder3D.gd`（**区块级** lane 归属：共角去重 → L 臂预留 → 共面去重，顺序不能换）＋探针 pass=1619 fail=0（重放区块00 逐值一致＋运行时形状对照）；区块00 回归 checks=230、classname 172 无重复 |
| 2052 | [`2052_expedition01_boss_layout_source.md`](2052_expedition01_boss_layout_source.md) | Boss房专属件摆位源（Task #40）＋门位/旋转判定：产 6 件专属件摆位 JSON（`--check` 门禁）；钉死房间局部换算 y **须取 bz**（区块00 的 y=0 常量不可照抄，主屏/墙面标识悬空）；判定「旋转90度」**不能靠 template_rotation_deg 落地**（旋转不参与几何），通道桥短边只能开门须做**放置约束**；push 被凭据阻塞 |

| 2144 | [`2144_expedition01_shell_layout_wiring.md`](2144_expedition01_shell_layout_wiring.md) | 远征01 壳体装配接线前半（Task #42-A）：注册表纳入 6 件 Boss 专属件（`component_count` 6→12，加 `kind`/`alias_policy` 契约）＋探针补 G 段断言 `pass=148 fail=0`；补齐 `normalize_floor`/`room_from_source` 两道 `authored_layout_*` 透传（门禁 `checks=234 rooms=33`、区块00 `checks=230` 无回归）。**钉死：constrained 模式会把 `floor_source` 整份换成现算几何 ⇒ 设计源的 `authored_layout_*` 只作兜底样例，第 4 环必须写在 `_generate_constrained_floor` 之后**；门位须与 `_plan_room_layout()` 同源、`to_runtime_instances()` 的 y=0 只对落地件成立 |
| 2156 | [`2156_expedition01_irregular_footprint.md`](2156_expedition01_irregular_footprint.md) | 业主裁决「外轮廓本身不规则 ＋ 本轮连内部一起做」，推翻上一轮据模板注释的判断；实证形状**早已在文档渲染层**（`plans/03-数据库房间01.svg` 房体是倒 T 形多边形），真源在 `render_expedition01_plan_sheet.py::build_details()`（仅 2 模板 / 4 变体带轮廓）；**钉死落点：轮廓须挂「模板+变体」写进 `room_templates/*.json`，不能写 `floor_00.json`**（constrained 下内容房型每局随机抽、floor_00 整份被替换）；摆位算法可不动，只在装配层按轮廓裁切 |

> 早于本目录的单文件日记 `../2026-09-24.md` 若存在则为旧格式，不再追加。
