# 宝箱出现反馈 · 自带地面光 · 头顶提示让位 · 2026-11-09

FeatureID：`WORLD-LOOT`（表现层）。设计口径见[战斗奖励与物品流转设计](../design/战斗奖励与物品流转设计.md#表现层口径2026-11-09)，特效登记见[特效规范 §3.10.6](../14.6_特效系统与制作规范.md)，基地救援箱侧见[基地NPC §14.4](../20_技术施工_基地NPC.md)。

## 1. 来源

业主 2026-11-09 三条，按先后：

> ① 我的救援宝箱，不是有个消失特效嘛？帮我改个颜色，放在关卡宝箱出现的时候，适当放大一点。这样我宝箱出来的时候不会很突兀。
>
> ② 还有就是宝箱上面的 E 开启宝箱这个去掉，和靠近后的文字重复了。或者靠近后出现开启宝箱的白字后，这个消失。
>
> ③ 宝箱上方加一个灯，和宝箱模型绑定，不然宝箱在里头根本看不见。

三条都是**表现层**，不碰奖励解析、开箱链、房间账、存档字段。

## 2. 实现

### 2.1 出现特效：用 FX01-35 IN，不是 FX01-34 OUT

业主说的是"救援箱那个消失特效"，但直接用 OUT 会读错语义：它是同一个脚本
（`src/vfx/VfxTeleport3D.gd`，`mode = out|in`）的配对，**OUT 的环从 1.35 向内收拢到 0.15**，
播在"凭空出现"上读作"被吸走"。IN 才是环 0.15 → 1.50 向外炸开、竖丝向上冒出。

| 项 | 值 | 依据 |
|---|---|---|
| AssetID | `VFX-TELEPORT-IN-3D`（FX01-35） | 与 OUT 同一套几何，曲线方向正确 |
| 颜色 | `Color(1.00, 0.78, 0.32)` 暖金 | 不按品质分色：品质由箱边描边回答 |
| 尺寸 | **2.0** | = 救援箱消失那档 `1.6 × 1.25`；1.6 只够包住箱子（碰撞宽 1.45 m），出现要超出箱子一圈 |
| 贴地 | `+0.05 m` | 地面环本来就躺在地板上，贴零与地板 z-fighting |

**资产本身零改动**：Prefab / 脚本 / `metadata/asset_version` 全是 v001。

### 2.2 触发点：玩家进房那一刻，不是建箱子那一刻

第一版把播放写在 `_build_treasure_chests()` 里，**是错的**，两个后果：

1. 房间 detail 会被提前建好 —— `Dungeon3D._prebuild_entry_room_details()` 在加载页预热开局房与邻房，
   流送还会预热相邻房。那时玩家还在读条，特效播完就没了；
2. 旗标一置就再也不会补，玩家进房时反而看不到。

改成：

- `TreasureChest3D.play_appear_effect()` —— 唯一实现，内含"已开箱早退"守卫；
- `DungeonRoom3D.play_chest_appear_effects()` —— 遍历本房在册且**未开**的宝箱各播一次，
  首次播成功才置 `_chest_appear_fx_played`；
- `Dungeon3D._on_room_entered()` → `room.ensure_detail_built()` → `room.play_chest_appear_effects()`；
- `spawn_runtime_chest()`（清房 / 首领阵亡掉落）建完当场播。

**三个刻意不播**：流送走远再回来按账重建（那不是"出现"，是"还在"）；装配期
`_build_treasure_chests()`；基地救援箱（玩家正趴着听绿苔说话，金光会抢戏）。

### 2.3 头顶提示牌：聚焦时让位

原来两处同时显示同一句「[E] 开启宝箱」：箱子头顶的 `Label3D`，与交互圆点下方的功能词
（`InteractionDot3D.extract_action_verb()` 从同一条 `prompt` 文案抽出来）。

选**让位**而不是删除头顶牌：没靠近时圆点还没聚焦、功能词不显示，玩家仍需要远远就看得出
"那是个能开的箱子"。`set_interaction_focus(candidate, focused)` 里按 `focused` 收起/淡回。

判定条件用"有没有被聚焦"而不是"距离多少"：聚焦与圆点功能词的显示条件本来就是同一个
（`provider == _focused_provider`）。本类若另算一条距离阈值，两条口径迟早漂开，
会出现"牌没了、白字也没出来"的空档。

`_opened` 一旦为真，之后任何一次失焦回调都不许把牌子亮回来。

### 2.4 自带地面光

`OmniLight3D` 挂在 `_visual_root` 下（= 宝箱模型），不是挂在 `Area3D` 自己或房间上。

| 项 | 值 | 依据 |
|---|---|---|
| 颜色（普通箱） | `Color(1.00, 0.87, 0.64)` 暖白 | 照见，不染色 |
| 颜色（平涂箱） | `body_tint.lightened(0.5)` | 浅灰救援箱不能被暖黄打回彩箱（业主 2026-11-08 点名要浅灰） |
| 能量 | `1.1` | 略低于命运卡谱的 1.25：宝箱房可能同时 1~3 只，逐只按 1.25 会堆出过曝白斑 |
| 半径 | `3.0 m` | 灯高 = 1.02 + 0.45 = 1.47 m；斜照到 1.0 m 外的地板边缘 √(1.47²+1.0²) ≈ 1.78 m，3.0 给出约 2.6 m 地面光斑，又不越过 5 m 房间网格打亮隔壁家具 |
| 高度偏移 | `+0.45 m`（在箱体高之上） | 低于 0.3 把箱盖木纹打爆成白，高于 0.6 够不到地面 |
| 阴影 | **关** | 2026-11-08 帧时归因那轮：27 盏灯里 24 盏 `light_energy == 0` 却仍每帧渲一张完整阴影贴图，白烧 35% 帧时 |

幂等（重复 `_build_visual()` 不叠第二盏灯）；拟态吞箱 / 演出 `despawn()` 只关
`_visual_root.visible`，灯作为子节点自动跟着灭，不需要在三条消失路径上各写一次。

## 3. 验收

新增 `tests/verification/verify_chest_appear_fx_prompt.tscn`（core）。

| 组 | 断言 |
|---|---|
| 特效本体 | 池里借出 1 件；`mode == "in"`；尺寸 2.0；暖金色；贴地 0.05 |
| 进房触发 | 首次进房各播一次；二次进房不重播；已开箱不补播（房间过滤 + 箱子自身守卫两层各有用例） |
| 接线 | `Dungeon3D.gd` 源码里确实有 `room.play_chest_appear_effects()` |
| 地面光 | 存在 `ChestLootLight`；父节点是 `_visual_root`；不投影；半径 3.0 / 能量 1.1；灯高 ≈1.47；拟态消失后一起灭；浅灰箱灯色跟身板 |
| 提示牌 | 初态可见且文案未变；聚焦后收起；失焦后淡回；开箱后失焦不许恢复 |

命令与结果：

```text
Godot_v4.6.3 --headless --path <工程> res://tests/verification/verify_chest_appear_fx_prompt.tscn
CHEST_APPEAR_FX_PROMPT_OK: ... exit 0
```

**反向对照 8 组，全部精准变红后还原复绿**：

| 组 | 改动 | 红在哪 |
|---|---|---|
| MUT1 | `APPEAR_FX_ASSET` 换成 `FX01_TELEPORT_OUT` | 池计数 0→0 与方向断言同时红 |
| MUT2 | `set_interaction_focus` 里去掉 `_set_prompt_shown(not focused)` | 「聚焦后头顶提示牌必须收起」 |
| MUT3 | 房间不按 `is_opened()` 过滤 | **不红**（箱子自身守卫兜住）—— 故另加箱子侧用例，见 MUT5 |
| MUT4 | 删掉 `Dungeon3D` 的 `room.play_chest_appear_effects()` | 接线源码断言 |
| MUT5 | 箱子 `play_appear_effect()` 去掉 `_opened` 判据 | 「已开箱的 play_appear_effect 必须自己早退」 |
| MUT6 | `light.shadow_enabled = true` | 「宝箱地面光必须关阴影」 |
| MUT7 | 灯的父节点改成 `self` | 父节点断言 + 「视觉消失后灯必须一起灭」 |
| MUT8 | 浅灰箱也用固定暖白 | 「浅灰箱的地面光应跟身板色」 |

MUT3 不红不是缺陷：这条契约由两层守卫共同兑现（房间挡"批量补播"、箱子挡"被直接调用"），
单拆一层另一层会兜住。两层各自有独立断言，所以仍然抓得住"两层一起去掉"。

## 4. 账本

《3D-特效》FX01-35 只改三格：`J 复用范围`（加"关卡宝箱出现（贴地金环 · 尺寸 2.0）"）、
`V 更新时间`、`Y 备注`（追加一段说明）。`版本` 仍 `v001`（Prefab 与脚本都没动），
行数不变、`总览` 区间不变、`DataValidation` 不变。

域变更日志 `v0.1.39`。脚本 `tools/asset_pipeline/update_chest_appear_fx_ledger.py`（幂等，可重跑补基线）。

**基线的处理是本次刻意偏离模板的地方**：`update_base99_telescopic_ladder_ledger.py` 那类脚本
在末尾会重算 `column_digests` 与 `category_counts`；本次**不重算**，只更新该行指纹。
理由：工作区里有并行会话未提交的账本改动，重算会把它们一并吃进基线 —— 等于用"当前文件"
掩盖差异，违反 AGENTS.md 那条「哈希漂移先核对变更来源，不批量接受当前文件」。
保留旧指纹的代价只是校验报告里多一条 `column_digest_drift`（报告项，不 fail）。

## 5. 门禁与既有红项（与本批无关，逐格自证）

```text
check_asset_runtime_naming.py            ASSET_RUNTIME_NAMING_OK                exit 0
verify_ledger_split.py                   failures=40 / missing=0                exit 1（既有）
check_asset_registry.py --scope structure issues=312                            exit 1（既有）
check_documentation_contracts.py         既有 14 条断链 + media 子进程缺 openpyxl  exit 1（既有）
check_verification_registry.py           VERIFICATION_REGISTRY_OK scenes=290     exit 0
check_feature_traceability.py            FEATURE_TRACEABILITY_OK features=46     exit 0
```

- **账本逐格对照**：冻结副本 vs 当前 xlsx，`资产主表` 只有 `row 55` 的 `J / V / Y` 三格变化；
  `总览`、`3D-特效` 页 0 差异；`域变更日志` 只多 1 行。R/S 列公式形态未变（仍是 `==`，**改前就这样**）。
- **`verify_ledger_split` 的 40 条**：`enemies` 账本 R 列被写成 `==LOWER(...)`（20 条）、
  S 列变成数组公式（19 条）、`ENM-TRAP-SPIKEWORM01` 行内容既有漂移（1 条）。
  用**改前基线**重跑同一脚本，failure 集合逐条相同 ⇒ 非本次引入。
  `extra_assets` 是两只 `PRP-3D-REWARD-CHEST-*`（2026-11-08 那批新增，基线从未登记）。
- **`check_asset_registry` 的 312 条**：同样是 `enemies` 的 R/S 公式 + `vfx` 总览 8 格
  `==COUNTA(...$61)`（应为 `$62`，且多一个 `=`）。这三处都是**编辑器保存过台账留下的损坏**，
  与本批无关。**建议单独开一次事务修**（去重前导 `=`、把 vfx 总览区间从 `$61` 扩到 `$62`），
  不要和功能改动混在一起。
- **`check_documentation_contracts` 的 14 条断链全是既有**（`CHANGELOG` 历史行、
  `支线秘密房间设计` 引用的 10-18/10-19 记录、`07.3` 指向的 v010 数据库等），
  本批四份文档（14.6 / 20 / 战斗奖励 / 本记录）零新增断链。
  `check_media_asset_domains` 那条是**子进程环境问题**：外层父进程用隔离 venv（有 openpyxl 3.1.5）
  跑，但它内部 `subprocess` 调的是 PATH 上的 `python3`，那个环境没装 openpyxl。
- **验证用例要登记两处，不是一处**（复查时发现并补齐）：
  ① `docs/v0.1/feature_registry.json` 的 `WORLD-LOOT.verification`（`{kind: scene, id: …}`）
  —— 供 `check_feature_traceability` 认；② `scripts/run_verification_suite.sh` 的
  `core_scenes` 数组 —— 供 `check_verification_registry` 认。只补 ① 时
  `check_documentation_contracts` 仍报 `unregistered: verify_chest_appear_fx_prompt`，
  因为它把 `check_verification_registry.py` 的输出原样收进 issues。补完两处后
  `VERIFICATION_REGISTRY_OK scenes=290`、`FEATURE_TRACEABILITY_OK features=46`。
  教训：**新增 `verify_*.tscn` 后两处都要动，只补 JSON 会留一条红**。

## 6. 未做 / 明确不做的

- **没有真渲染出图**：本次只有 headless 契约验收。灯的实际观感（尤其暗房里 1.1 能量够不够、
  三只箱子同房会不会堆白）必须真窗口看一眼，目前是 partial 的依据。
- 没有改 `_prompt_text()` 文案、没有改交互协议、没有动 `InteractionDot3D`。
- 没有按品质给灯换色（理由见 §2.4）。
