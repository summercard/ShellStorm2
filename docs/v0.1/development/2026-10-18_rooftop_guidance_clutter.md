# 天台首次登顶杂物引导交付

日期：2026-10-18。FeatureID：WORLD-BLOCKS / ASSET-ROOFTOP / ASSET-PIPELINE；版本0.1.0。设计依据：[首次登顶杂物引导r1](../design/rooftop_first_visit_guidance.md)。来源：用户红线图及“倾倒花盆、花圃、木头、石块围住，缺模型可白盒，未来可移动清除”要求。

## 本次改动

- 独立布局 `assets/art/environments/tower_zones/rooftop/runtime/guidance/env_rooftop_guidance_layout_root_top3d.tscn`：130实例、7类组件，57件存在俯仰或侧倾，其余也有错斜朝向。西侧上下段/分叉、北侧堆场、东侧上下段、西北角分区可直接在Godot编辑。
- 现有大盆栽、长花箱稳定Prefab复用；木料、石堆A/B/C和破损花圃为授权白盒。原有20件贴墙绿化保留。布局中的盆栽是倒置实例，新增碰撞针对盆体/箱体；石堆木料逐可视块碰撞，合计327个形状，不用一堵横跨空地的隐形墙。
- 每件拥有稳定 `roof_clutter_NNN` 身份、`scene_interactive_content` 分组与未来动作声明。当前实际功能是独立物件的实体阻挡；移动/清除条件、玩家操作与持久化均未实现，未自动解锁或自动清场。
- `TowerFloorStage3D` 只增加常量引用与真正100F分支内的一次挂载；远征、99F/98F不装配。原装饰JSON、桥口剧情、门、电梯、存档与战斗规则没有改变。
- 真实锚点：西侧出口(-28,0,2.5)，剧情点(5.4,0,-23.5)、半径13.5m，桥前守卫(20,0,-28)。胶囊通路从出口进入机房西侧，再沿北面通向桥口，覆盖既有剧情范围。南侧阻挡接到机房，东侧接缝补齐，出口净空保留。
- 对所有网格逐顶点变换测量并贴地，修正边缘越界。倾倒物不能用先求局部AABB再旋转的放大包络判断落地；验收改为实际顶点全量测量，并同时断言不穿地和不悬空。

## 账本与追溯

场景分账本《资产主表》更新8项：原929破损花圃、931–933石堆A/B/C推进到“原型已接入”；新增963木料、964倾倒花盆包装、965花箱包装、966布局。每行明确白盒或复用模型、未来交互未实现，回填稳定TSCN与SHA。R/S、总览范围、下拉与过滤范围随末行扩展；域日志v0.1.39。锁定Prefab专页保持逐格摘要不变；非目标旧行内容列逐格保持。

无损基线仅补录/更新这8个AssetID及并集列摘要；其他资产行指纹与专页摘要未被接受或覆盖。

改前备份：工程外 `ShellStorm2-backup/2026-10-18_rooftop_guidance/before_edits/`。过程清单、日志与截图：`ShellStorm2-work/sessions/2026-10-18_rooftop_guidance/`。过程构建脚本仅初始化本次布局，后续手调以正式TSCN为准，禁止直接重跑覆盖。

## 验收记录

存档隔离：工具直跑前设置独立APPDATA；套件使用独立项目与自定义用户目录，均在Autoload启动前隔离。新增场景已登记到 `run_verification_suite.sh` 的真实渲染名单。

| 检查 | 结果 |
|---|---|
| 130实例专项与真实Forward+渲染 | `VERIFICATION_SUITE_OK suite=scene count=1`；130实例/57倾斜件/327形状；出口→桥口胶囊通路、触发区覆盖、南侧阻挡、东侧接缝、东门净空、ID/单位缩放/逐顶点范围与落地全部通过；`final_suite.log` |
| 原装饰stage-only回归（120原装饰/20碰撞） | `VERIFICATION_SUITE_OK suite=scene count=1`；原120件、20碰撞保持；`regression.log` |
| 账本structure | exit 0，1297资产/9域 |
| 账本full scenes | exit 1，仅既有第962行 `ENV-OPENWORLD-UNDERGROUND-STREET` 源Blend哈希不符；本次8行无问题。962行内容及记录SHA与改前副本逐格一致，源文件不在本次差异内；`ledger_full_final.log` |
| 无损基线 | exit 1，唯一既有 `vfx / 3D-特效 moved_sheet_mutated`；本次未改特效账本，专页基线与改前副本逐字一致 |
| 运行资产命名 | exit 0，无新增带版本路径 |
| 文档契约 | exit 0，327文档/1816链接/38功能/101测试引用，0 issue；初次子进程调用另一个无openpyxl的Python，设置依赖路径后重跑通过；`documentation_final.log` |

初轮127实例验证中发现落地包络判据和4件边界问题，已改按实际顶点贴地/收边；该轮失败不算验收通过。第二轮127实例Forward+正式场景通路与ID/范围通过，之后补3件闭合东侧与北侧接缝，须以最终130实例结果为准。

全场景卸载存在 `WARNING: ObjectDB instances leaked at exit`，改前只读探针同样出现；其为WARNING而非ERROR，日志门禁不计为exit4。不将此警告隐藏或声称全工程无泄漏。

收尾时另一项并行工作在同一本场景账本追加了秘密门967–968行及两条Prefab专页记录；因此 `ledger_split_final.log` 的时点结果增加两条 `asset_not_in_baseline` 和场景专页摘要漂移，共4项。该工作不属于本次天台改动，不覆盖其账本或擅自接受其基线。本次8条仍全部存在，最终逐条SHA与基线行指纹复查为 `ROOFTOP_LEDGER_TARGETS_OK rows=8 hashes=8 baseline=8`。上表1297资产及唯一特效专页漂移是并行追加前的检查时点，不能当作整库最新全绿声明。

未执行：全量core/aggregate/full；未来移动/清除/存档验收（能力尚未实现）；正式木料、石块与破损花圃美术验收。剧情内容本次沿用，仅验证空间通路覆盖已有触发区，不把此项表述为新编剧情或整段演出端到端验收。

## 自然摆放修订 v002（2026-10-18）

根据用户“自然、疏密结合、轮廓自然”反馈，直接修订正式布局TSCN的130件实例变换，保留全部稳定ID、组件引用和327套逐件形状。边界以不等间距、不同厚度和折转衔接，杂物向几个局部中心聚集并散落到外缘；北侧空心围圈改为实心多团堆积。现有模型和白盒组件没有变更，未来移动/清除的待实现状态保持。

专项重新通过 `VERIFICATION_SUITE_OK suite=scene count=1`：130实例、67倾斜件、327形状；玩家胶囊路线、现有剧情触发区覆盖、关键阻挡点、东门净空、逐顶点落地与范围检查通过。真实Forward+俯视及出口截图已查看，确认疏密和轮廓变化。日志和截图位于工程外 `ShellStorm2-work/sessions/2026-10-18_rooftop_guidance/natural_v002/`，改前布局备份位于 `ShellStorm2-backup/2026-10-18_rooftop_guidance_natural/before_edits/`。

仅更新场景账本 `ENV-ROOFTOP-GUIDANCE-LAYOUT` 为v002及新SHA、规格、备注和域日志，同步该行无损基线；回读确认其他资产行及专页保持不变。文档契约与运行资产命名检查通过。原装饰与组件本轮未改，不重复上轮已通过的旧装饰专项；本轮也未重复执行全域资产检查，上一节的无关账本问题不在此修订范围。
