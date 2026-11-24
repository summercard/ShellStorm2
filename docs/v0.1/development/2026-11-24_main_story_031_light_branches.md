# 2026-11-24 主线3.1：99F灯光双分支

FeatureID：`NARRATIVE-TRIGGER / BASE-NPC / WORLD-ENTRY`

## 本次变更

- 3.1不再要求玩家靠近绿苔或按E触发。
- 亮灯分支：真实墙灯启动完成后，镜头环视99F基地，绿苔主动走到玩家身前，再进入原15句对白。
- 摸黑分支：玩家越过门边开关区域、进入基地内侧后，剧情锁住玩家；绿苔从暗处走来，显示独立手电并说“居然有人想要摸黑前进，这可是很危险的。”随后走到真实墙灯开关处点灯，灯稳后环视基地、关闭手电、走回玩家，再进入同一份15句对白。
- 两路共用 `nar_main_031_green_briefing`、同一历史ID和同一完成提交，不新增存档字段。
- 导演增加按 `branch` 过滤同一剧本cue的能力，且 `actor.say wait=true` 会形成真实对白屏障。
- 绿苔增加一次性演出手电和开关按压手势；墙灯启动等待不再错误等待异步返回值，避免开关永久处于 transitioning。

## 设计与文档同步

- `docs/v0.1/design/主线剧情剧本.md`
- `docs/v0.1/design/主线剧情3.1至3.3与四钥匙设计.md`
- `docs/v0.1/design/主线剧情节点表.md`
- `docs/v0.1/08_技术施工_剧情触发.md`
- `docs/v0.1/20_技术施工_基地NPC.md`

## 代码与内容

- `src/narrative/MainStoryChapter3D.gd`
- `src/narrative/NarrativeDirector3D.gd`
- `src/narrative/NarrativeAdapter3D.gd`
- `src/npc/NpcCharacter3D.gd`
- `src/world3d/DungeonRoom3D.gd`
- `src/world3d/RoomLightSwitch3D.gd`
- `data/narrative/nar_main_031_green_briefing.json`
- `tests/verification/verify_main_story_narrative.gd`

## 验收结果

- 通过：双分支脚本可加载，分支cue过滤、真实墙灯启动接口、绿苔演出手电、灯光完成屏障和中止释放路径均已加入专项。
- 已定位并修复：基地墙灯启动协程错误等待异步返回值，导致 `transitioning` 永不结束。
- 已定位并修复：剧情走位不应调用通用刷怪可达性网格；该网格会因陈设阻挡清单拒绝可见上可走的演出路径。3.1改为使用基地演出站位的真实直线走位，并在到位屏障中继续等待。
- 未完成：本机全量 `verify_main_story_narrative` 仍受工作树并行改动中的 `FateCardGameBridge.gd` 未定义函数（`_fate_size_multiplier`、`_finish_flight`）阻塞；该错误不由本次改动引入。双分支专项此前已分别暴露灯光等待与摸黑走位问题，修复后需在干净可编译工作树上重新跑真渲染验收。
- 文档契约检查已执行；工程已有历史断链清单仍会使脚本退出码为1，未把这些历史问题伪装为本次通过。
