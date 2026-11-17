# 胖子僵尸03正式入口替换为2.1

日期：2026-11-17；记录ID：FAT-ZOMBIE21-REPLACEMENT；功能ID：ENEMY-AI / ASSET-PIPELINE / VFX-POOL；工程版本：0.1.0。
设计依据：[胖子僵尸运行配置](../design/胖子僵尸03运行配置.md)、[怪物设计](../design/怪物设计.md)、用户本轮明确批准；交付基线：本轮开始时的未提交工作区，完整差异已备份；不提交、不推送。

## 1. 替换关系与边界

- **旧ID映射到新视觉**：投放/实体/存档 `fat_zombie03`、兼容资产 `ENM-NORMAL-FAT-ZOMBIE03` 保持；普通与强化胖子由 EnemyAvatar3D 正式入口加载 `ENM-NORMAL-FAT-ZOMBIE21` v006 稳定包装。
- 路径：`MonsterInjector / SpawnBoxCatalog / 固定波次 / TrainingSpawnPad3D / EnemyWarmup / 关卡monster_rules → fat_zombie03 → Enemy3D → EnemyAvatar3D → fat_zombie21运行包装 → 稳定GLB`。没有改怪物投放数据为新ID，也没有修改Enemy3D；原伤害/碰撞/关卡覆盖/掉落/预爆/存档分支保留。源碰撞半径0.88、高3.142857及外层缩放不变。
- `fat_zombie03_strong` 按原MonsterVariants回基类并采用新视觉；`fat_zombie21`保留此前已存在的候选入口，不把它冒称完整玩法兼容别名，不加入随机池或触发盒。
- 远征03的 `egt_mimic / egt_gun_nut / egt_chain_gunner` 仍加载旧03视觉与原染色，避免无关借皮怪一起改变。
- `scenes/enemies/fat_zombie03.tscn` 增加兼容/视觉资产元数据；未改其玩法kind。旧03运行目录和制作源文件均不修改、不删除。

## 2. 实际修复

1. 修正新包装GLB引用缺少 `components/enm_normal_fat_zombie21/` 子目录的问题。
2. 新表现适配器补足游戏必调 `flash_hit()`，实例化材质并复用HitFlash；无hurt/hit_light剪辑，只闪白，不伪造受击动作。
3. 补足 `sync_death_warning()`，单向消费原计时，使用原表现根颤抖和额外能量 `0.35*p²`；不接管死亡判定或伤害。
4. 源F78/60fps接触映射至原1.2秒玩法边界；恢复仍1.3秒，采到GLB实际末帧。动画不会改变Enemy3D伤害时刻。修复浮点边界漏触发，attack/recovery连续采样每轮仅一次砸地事件。
5. 保留透明PNG Sprite3D烟尘、火焰与外扩波纹；覆盖材质显式绑定各自贴图，避免material_override使贴图消失。砸地VFX仅包含 VFX root 与 DustSprite/RippleSprite/FlameSprite 三个 Sprite3D，不含 MeshInstance3D、碰撞或特效伤害。火焰只在砸地短瞬间出现，约0.22秒后淡出；烟尘与波纹由 VfxFatZombieSlam3D 所有，伤害仍由 Enemy3D，波纹半径公式保持0.18→1.40m。
6. 保留六段源动作；起停按已制作move_start/move_stop，idle可正常采样，移动参考实际速度。缺失hurt/dead/awaken/alert/turn_l/turn_r/hit_light明确回退idle，不沿用旧13段已验收声明。

## 3. 不可隐瞒的源/登记冲突

原manifest/transfer声明walking/running/attack为2.5/2.0/2.0秒；当前GLB原始accessor及Godot导入实测为 **2.0/1.2/2.5秒**，attack末帧F150。六段名称与41骨/1180三角匹配，但这不能证明源动作与清单语义一致。

**没有覆盖或重导Blend/GLB，没有篡改原声明。** 新增 `runtime_measured_clip_seconds / source_metadata_conflict` 独立字段记录差异；运行适配按实际导入时长，保留替换候选并阻止accepted。需源制作方确认v006实际时长和动作对应，再决定是否修订源或清单。旧开发记录按原时点保留，不回改历史结论。

## 4. 本轮砸地贴图来源与验真事实

本轮范围锁定为胖子砸地特效的贴图替换，不替换模型几何、不新增VFX AssetID、不改变Enemy3D玩法与伤害。

| 表现 | 资产库来源 | 工程外原图SHA-256 | 运行贴图 | 尺寸/模式/alpha | 运行贴图SHA-256 |
|---|---|---|---|---|---|
| 火焰 | `aleksei-starter-vfx-lite/tex_flame_01.png` | `dc6b5decd0e7e99900b0493fa1496f80e34d272f5603081634d0e99235ea9d2b` | `assets/art/vfx/combat_3d/textures/enm_normal_fat_zombie21_slam_flame.png` | `256×256 RGBA`，alpha `0..228` | `03554e5a28210dd9dc3bfcd554e2f44eafb9f6491ac6914c8829c36272253fb7` |
| 烟尘 | `kenney_particle_pack/smoke_06.png` | `74968cd44ba5c72bdaf1ebfc50d6113a401aae0ffded43f785055b4eeb9399df` | `assets/art/vfx/combat_3d/textures/enm_normal_fat_zombie21_slam_dust.png` | `256×256 RGBA`，alpha `0..190` | `40bda546472f524746dde171f0c48d177864302820e3c0a119ff941d310d84f0` |

原图已归档到 `art_source/vfx/combat_3d/fat_zombie_slam/source/v002_assetlib/`。火焰运行图按灰度亮度转alpha以去除黑底；烟尘保留资产库透明度并转换为运行用RGBA。火焰只在砸地短瞬间出现，表现脚本约0.22秒后淡出；烟尘与波纹均属于 `VFX-FAT-ZOMBIE-SLAM-3D` / `VfxFatZombieSlam3D`，不拥有伤害或碰撞，伤害归 `Enemy3D`，波纹仍按半径 `0.18→1.40m` 外扩。该状态为 `replaced_pending_acceptance`，未写 `accepted`。

## 5. 账本与源索引

敌人分账本《资产主表》仅修改既有 **r19 ENM-NORMAL-FAT-ZOMBIE03、r57 ENM-NORMAL-FAT-ZOMBIE21**；总行数52不变，不新增/改名AssetID。r19路径指向2.1稳定包装，r57主路径仍为稳定GLB；两行版本/规格/来源追溯/路径SHA和备注已同步，域变更日志追加 v0.1.56。砸地VFX不在特效账本新增独立AssetID。

两行制作状态均为 `exported_pending_godot_validation`，业务语义为 **已替换待验收**。域变更日志追加 **v0.1.56**；不修改《敌人动画与状态》《3D-敌人》历史专表。专表旧03行仅作保留资源的历史登记，不代表当前Avatar正式入口。

仅用openpyxl写账本；R/S公式逐行与权威函数核对，原ZIP层全部公式及DataValidation与备份比较；未插行/新增资产，DV范围不应扩张。基线只更新两个目标资产指纹，重算九域列摘要/类别计数，不接纳其它资产或专表漂移。源索引保留旧源条目，用current/superseded_by标记2.1动作v006为当前，并登记旧玩法ID到新视觉映射。

砸地VFX在现有特效账本尚无独立AssetID行，本事务不擅自新增重复/未授权登记；当前由敌人两行备注追溯。若要求VFX独立转正，需另做特效域登记事务。

## 6. 验证与门禁

完整结果、命令、原始stdout及逐项退出码：
`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-17_fat_zombie21_texture_update/`。

运行前在Autoload之前隔离APPDATA/LOCALAPPDATA，Godot 4.6.3 headless；不触碰正式存档。最终逐项结果见同目录 `verification_report.json`，逻辑专项见 `godot/runtime_report.json`。命令退出0但存在SCRIPT ERROR或报告缺失不算通过。

| 检查 | 退出码 | 结论 |
|---|---:|---|
| Godot headless import | 0 | 最终导入命令退出0；目标火焰/烟尘无Failed loading输出 |
| VFX scene check-only | 0 | VFX root加载；3个Sprite3D，0个MeshInstance3D |
| fat_zombie03入口 check-only | 0 | `scenes/enemies/fat_zombie03.tscn`退出0，映射到2.1包装元数据保留 |
| fat_zombie21包装 check-only | 0 | 包装场景退出0，无SCRIPT ERROR |
| VFX/入口真实headless运行 | 0 | 命令退出0；日志保留既有NarrativeDirector缺失剧本ERROR，不能算全无错误 |
| 文档契约 | 1 | 既有断链/追溯债务；本次记录链接有效，失败项见报告 |
| 运行资源命名 | 0 | 稳定包装/GLB不含版本号；既有债务未更新 |
| 敌人structure | 1 | 既有r55 `开发中（partial）` 非法状态，目标胖子行未引入该问题 |
| 敌人full | 1 | 同上，目标胖子行未引入该问题 |
| 分账本无损 | 1 | 既有24项/2个额外资产差异；目标胖子行未出现在失败项中 |
| git diff --check | 0 | 通过 |

早期editor模式check-only虽然exit0，退出时报3条DummyRenderer RID泄漏，不作为无错误通过；最终不用editor模式复测。早期探针曾错误假定0.6m/s及清单时长，随后按GLB实测与全局0.85速度系数修正断言：注入链实际HP696/伤害19/速度0.5100000007；未为满足旧断言修改玩法。全工程旧palette UID警告保留。

未执行：Forward+连续动态/真实游戏镜头、四足轮廓与旧碰撞可玩兼容、双红眼新骨位、完整远征人工流程/目标设备/core/full。不能用headless代签渲染或用户接受。全局功能partial不提升。

## 7. 备份与回滚

按用户指定位置保留125文件的初始备份和SHA清单：
`I:/工作项目/shellstrom2/ShellStorm2-work/backup/2026-11-17_fat_zombie03_replaced/`。

`manifest.json`记录原路径与SHA；`before_edits/`含旧03全部运行目录/制作源、新21候选、VFX及受影响登记和文档；session的 `before.diff / before_status.txt`冻结本轮前既有改动。

回滚应先比较后续并行编辑，再逐文件恢复本次Avatar映射、实体元数据、新包装/脚本/VFX以及本次目标登记与文档。禁止整树覆盖/清空git工作区；旧03资产仍原位可用，保留源与账本原ID，故无需存档迁移。最终资源审计须证明旧03目录全部文件SHA不变、Enemy3D本轮字节不变、新GLB和双母版未被本轮改写。
