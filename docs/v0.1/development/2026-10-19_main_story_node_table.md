# 主线剧情节点表建立与 01—05 回填

日期：2026-10-19；记录ID：`2026-10-19_main_story_node_table`；FeatureID：`NARRATIVE-TRIGGER`；工程版本：0.1.0。
来源：用户要求「先回填，让两个文档一致」。
依据：`data/narrative/` 下 11 份运行剧本、[主线剧情剧本](../design/主线剧情剧本.md)、[剧情触发技术文档](../08_技术施工_剧情触发.md)。

## 变更

- 新增[主线剧情节点表](../design/主线剧情节点表.md)：以节点为行，列出楼层、房间/锚点、剧情编号、表演要点、时长、锁操作、触发方式与演出后的世界副作用。共 11 行，对应 11 份运行剧本。
- 该表同时登记三份文档的分工、编号体系现状、覆盖边界与「新增节点必改三处」的维护流程，作为增删主线的入口。
- 08 的编排契约表按节点拆为 11 行。原「02」拆成 02·第二房 / 02·第四房，原「2.5 / 03」拆成 2.5 / 03；契约文字保留，补上各节点的 `room_id` 与锚点偏移。表头前补三文对应关系。
- 剧本补登此前遗漏的 **2.3** 运行剧本对照行；2.3 地点补「走廊东端」，与 08 的 `point_offset:[34,0,−2.5]` 对齐；05 吊桥前的镜头表述由「平移」改为「移向并聚焦」，与运行剧本实际使用的 `camera.focus` 一致。
- 索引同步：`design/README.md`、`v0.1/README.md`、`MODULE_INDEX.md` 与 `feature_registry.json` 的 `design_docs` 加入节点表，顺序为编排 → 内容 → 系统契约。

## 回填依据

| 项 | 来源 | 结果 |
|---|---|---|
| 节点数量 | `data/narrative/*.json` 文件数 | 11，与节点表行数一致 |
| 触发与锚点 | 各 JSON `trigger` 字段 | 11 个节点逐条核对，含 `point_offset`、`radius`、`priority` |
| 时长与锁操作 | 各 JSON `duration` 与 `player.lock_input` | 一致；02·第二房因 `flow.wait_for_flashlight` 冻结时间轴，已注明实际时长由玩家决定 |
| 一次性怪物 | 各 JSON `scene.spawn` 的 `count` 与 `kind` | 8 / 3 / 3 / 15 / 6，与剧本文字一致 |
| 台词 | 各 JSON `actor.say`、`ui.subtitle`、`ui.hint` | 与剧本原文逐条一致 |

## 核对与限制

- `python scripts/check_documentation_contracts.py`：exit 1；本次新增文件 0 项问题，剩余 14 项全部位于本次未修改的文件（06 与 07.3 的链接、命运卡与支线文档的链接、CHANGELOG 五处链接、三条未登记验收脚本）。
- 功能溯源检查（`check_feature_traceability.py`）通过：MODULE_INDEX 新增链接与 `feature_registry.json` 的 `design_docs` 一致。
- 仅整理文档，未修改运行 JSON、代码、场景或存档；未运行 Godot 运行验收。

## 遗留

| 项 | 处置 |
|---|---|
| 编号缺 2.4 | 待裁决：新增段沿用 2.4，或整段重排显示号 |
| 01 台词「那是主人留下的礼物。。」双句号 | 待确认后与 JSON 同步修改 |
| 2.2 / 2.3 的「轰」借用 `boss_phase` 变调 | 待替换专门音效资产 |
| 吊桥之后的主线尚未编排 | 深化设计时从节点表第 12 行继续 |

修改前文档副本保存在 `ShellStorm2-backup/2026-10-19_main_story_node_table/before_edits/`。
