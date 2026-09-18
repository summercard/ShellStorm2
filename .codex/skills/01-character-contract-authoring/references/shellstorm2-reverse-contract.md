# ShellStorm2 角色类资产 · 反推证据链与已知约定

本文件把 `01-character-contract-authoring` 的通用步骤落到 ShellStorm2 的具体入口上。**处理本项目时按此执行；处理其它项目时按同一证据顺序重建资料，不套用这里的数值。**

## 1. 反推起点（按顺序读）

| 顺序 | 入口 | 看什么 |
|---|---|---|
| 1 | `docs/v0.1/16.1_角色美术制作与动作导入流程.md` | 当前制作与导入的主设计；旧资料里的单文件、纯程序动作、v006 当前版本描述**不再作为生产规则** |
| 2 | `assets/registry/ledger_index.json` | 该资产属于哪个域、哪个大类、哪个责任 skill |
| 3 | 该域分账本《资产主表》 | 是否已登记、查重结果、现有版本与路径 |
| 4 | `src/` 下的消费者 | PackedScene、控制脚本、状态机、换装代码、碰撞拥有者 |
| 5 | `tests/verification/` | 针对该资产的 `verify_*_flow` / `verify_*_visual` 入口 |
| 6 | `assets/art/3D模型资产目录与命名规范.md` | 目录与命名总纲（与 `01-character-contract-authoring/references/naming-and-storage-contract.md` 互为补充，冲突时以本契约的 §3 为准） |

## 2. 三域现役契约基线

| 项 | 玩家 | NPC | 怪物 |
|---|---|---|---|
| 骨架 ID | `SKEL-BUNNY01-004` | 新建 `SKEL-NPC<NN>-<NNN>` | 由 `ENM-ECOSYSTEM-KIT-3D` 派生 |
| 状态集 | `Player3D` 八态 + 四变体 | `idle` / `talk` | `ENEMY_AI_12_STATES` 12 态 |
| 现役 AssetID | `CHR-PLY-CAPSULE01-3D-BUNNY01`（v021） | 无 | `ENM-ELITE-RIFT-BOAR-ARMED-3D` |
| 逻辑消费脚本 | `src/player3d/Player3D.gd` · `src/player3d/PlayerAvatar3D.gd` | `src/world3d/ThemedNPC3D.gd` | `src/enemy3d/Enemy3D.gd` · `src/enemy3d/EnemyAvatar3D.gd` |
| 母版路径 | `assets/art/characters/player/chr_player_avatar_template_3d/source/chr_player_avatar_template_source_v001.blend` | 待建 | `assets/art/enemies/elite_3d/rift_boar_armed/source/` |

**玩家母版基准**：参考高 1.50 m、脚底中心原点、Blender 前向 `-Y`、Godot 前向 `-Z`、根缩放 `1`。七制作槽与九挂点的稳定名称见 `player-avatar-asset-standard`。

## 3. 玩家侧现状（形态 B，D3 冻结）

```text
assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/
├─ production/v021/
│  ├─ source/model/chr_bunny01_model_v021.blend
│  ├─ source/animation/chr_bunny01_animation_v021.blend
│  ├─ exports/chr_bunny01_{body,head,hand,foot,...}_v021.glb
│  ├─ runtime/chr_bunny01_root_v021.tscn
│  └─ character_transfer_ledger_v021.json
└─ source/  components/  previews/            ← 早期形态，冻结
```

- v021 = **完整 12 动作库**接入；八个玩法基础状态与慢走/单手持枪变体均来自 Blender。
- **正式玩家从 v021 起禁止再叠加旧程序姿势**：Blender 动作是角色节点变换的唯一来源。
- `production/vNNN/` 是玩家专用的历史形态，**NPC 与怪物不得套用**。

## 4. 怪物侧现状（与玩家完全不同）

| 资产 | 路径 | 形态 | 问题 |
|---|---|---|---|
| 生态套件根 | `assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn` | 单文件躺平在套件目录 | 无 `source/components/runtime` 分离 |
| 精英 `rift_boar_armed` | `assets/art/enemies/elite_3d/rift_boar_armed/{source,components,runtime}/` | **规范三段式** | 无（**唯一样板**） |
| 3 只 Boss | `assets/art/enemies/bosses_v01/enm_boss_*_top3d_v001.glb` | **裸 GLB 扁平堆放** | ⚠️ 违反「禁止运行时直接加载裸 GLB」（总表列为 P0） |
| 7 类普通怪 | 无文件 | — | 全部 `程序占位` |

**怪物侧的硬事实**（决定了 S4 的起点）：

- 敌人账本 12 条的「骨架/动作库」列**全部**为「无 Blender 动作母版（程序驱动）」，「独立动作母版」全为「无」。
- `src/enemy3d/EnemyAvatar3D.gd` 的 `_process` 只做 bob 起伏、`scale` 压扁、`rotation.y` 自转、emission 脉冲；它**记录 `ai_state` 但从不采样动作**。
- 因此「状态 → 动作映射」这一层在怪物侧**代码里根本不存在**——不是缺资产，是缺接口。S4 在怪物侧要从零建立。
- `BossContentCatalog.gd` 的 `presentation_scene` 直指 `.glb` 裸文件，需改为指向 `runtime/` 包装场景。

## 5. 已确认的设计决策（2026-09-18 主人拍板）

| # | 决策 | 结论 |
|---|---|---|
| 1 | NPC 状态集 | 收敛为 **`idle` + `talk`** 两态；**未来可扩展**，适配层按可扩展方式写 |
| 2 | 怪物起步对象 | 用 **`elite_rift_boar_armed`**（唯一走通三段式的怪物）作标准样板，不重做 Bunny |
| 3 | Skill 粒度 | **6 段**（S1 契约反推并入母版制作） |
| 4 | `game-character-model-pipeline` | **废除**，由六段 skill 取代 |
| 5 | 资产管理核心 | **以账本为核心**：命名规范与存放路径都走账本记录，由 `ledger_index.json` 声明 |

## 6. 不要做的事

- 不要把状态机、碰撞、AI 写进 GLB 或 Prefab。
- 不要给 NPC / 怪物套用玩家的 `production/vNNN/` 形态。
- 不要新建 `bosses_v02/`、`v022/` 这类版本目录。
- 不要顺手去版本化存量资产（D3 冻结；门禁只查「不新增」）。
- 不要在没有 Blender 可执行文件时声称做过 Blender 验证。
