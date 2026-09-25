# 0726 远征01 完成情况巡检（只读）

- 只读巡检，未改任何仓库文件（工作区除 `Godot/app_userdata/…/base_save.json` 的运行残留外干净）。本地与 `origin/0.1.2` **已同步**（#42-B 阻断记账 `6f2bf419` 已推）。

## 实测绿灯（本轮亲跑）

| 入口 | 结果 |
|---|---|
| `verify_expedition_level01_flow` | `EXPEDITION_LEVEL01_FLOW_OK`（13 房 entry+room_01..06+boss+extraction+branch_01..04，constrained 按种子房型、15×15 v007 安全屋 2 门、刷怪、可搜容器、命运卡 3 选 1、弃局门、STANDARD 撤离信标、默认塔楼未变） |
| `verify_level_plan_design_source` | `LEVEL_PLAN_VALIDATE_OK levels=3 checks=234 rooms=33` ＋ `LEVEL_PLAN_RUNTIME_GUARD_OK` |
| `probe_expedition01_bridge_multi_level` | `BRIDGE_MULTI_LEVEL_OK checks=95` |
| `probe_expedition01_authored_shell` | `PROBE_OK`（轮廓房 38、角件账目复核 144 房、`multi_level_component=1350`、`solid_wall=3098`） |
| `probe_expedition01_constrained` | `PROBE_DONE`（30 种子房型分布均衡、包围盒 200~250 内） |
| `check_expedition_room_footprints.py` | `EXPEDITION_FOOTPRINTS_OK templates=8 contours=4 pit_templates=1` |
| `check_expedition_room_asset_status.py` | `EXPEDITION_ASSET_STATUS_OK`（账本远征行仅 2 条） |

## 未完成 / 待办（按优先级）

1. **#42-B 通道桥「只短边开门」——阻断待业主裁决**（见 `0112`）。四方案 A/B/C/D，建议 A（新增第二模板 `bridge_50x60`）。落 A 要连带改：设计页 §3.1/§3.4「8 模板」契约、房型池 `content_template_pool`、`check_expedition_room_footprints.py`、flow 门禁尺寸集合。
2. **#43 账本登记未做**：账本里远征行**只有 2 条**（`ENV-EXPEDITION-L01-BOSS-ARENA`、`ENV-EXPEDITION-L01-L-CORRIDOR`）。缺行：Boss 房房间种类源 `boss_room/v001`+`v002`（各 214 包，manifest 自称 `3D-场景通用` 却查无行）、6 件 Boss 专属件（`ENV-EXPEDITION-BOSSROOM-*`，已在 `shared/runtime/shell_component_catalog.json` 里 `kind=exclusive` 参与运行时解析）、远征通用组件库（214 包）。改完须同轮同步设计页 §3.1.1（门禁盯着）。
3. **美术真缺口**：8 房型里仅安全屋可玩（复用 v007）；拐角走廊 45×40 有源**未导出**（`l_corridor/v003` 下无任何 GLB/PackedScene）；Boss 房半途；**数据库 70×50 / 办公室 60×70 / 通道桥 60×50 / 撤离屋 25×25 / 标准房间 25×25 连源都没有**。
4. **Boss 房首领身份未指派**（留空合法，运行时提示"首领房未指派首领 · 区域已放行"）。
5. **Boss 房门位仍未裁决**（设计页 §4.4：美术源「南进西出」vs 生成算法贴合方向）。
6. **文档漂移**：`docs/v0.1/12_全游戏完成度清单.md` 仍写「单层 7 房 / room_01…05 各 25×25」（2026-09-19 旧口径），未随 13 房 constrained 更新；`docs/v0.2/PLAN.md` A16 措辞过期（"设计源只有 7 房、无 Boss 房席位"）。两者都不是本轮门禁能抓到的（完成度清单无门禁）。
7. `verify_3d_parity_core` 两条既有基线红仍未补进 triage 基线清单（历史遗留）。
