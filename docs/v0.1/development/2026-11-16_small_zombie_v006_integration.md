# 小僵尸v006正式接入、256贴图与账本同步

- 日期：2026-11-16；FeatureID：`ENEMY-AI / ASSET-PIPELINE`；工程版本：`0.1.0`。
- 代码基线：`e81c3bc5` + 当前并行工作区（文档回填时 `git rev-parse --short=8 HEAD` 实取）；资产版本v006不等于工程升版。
- 来源：用户明确批准新小僵尸正式接入、贴图256、设计文档与账本更新；本记录汇总已执行接入/账本证据，文档事务不重跑运行验证。
- 状态：本资产正式接入专项通过；全局Feature仍partial，不能据此宣称整关、全档或全部门禁通过。
- 设计主源：[怪物设计·当前表现契约](../design/怪物设计.md#小僵尸当前表现契约v006)；施工：[角色美术制作与动作导入流程](../16.1_角色美术制作与动作导入流程.md)。

## 1. 当前交付与边界

`ENM-MELEE-FUNGBOAR01 / melee_chaser` 保持稳定身份；16骨/800三角面/402制作顶点（GLB UV拆点743）、每点最多4骨影响，无独立手脚指骨。
双母版均为v006、packed 256×256、无外链库，共用 `SKEL-MELEE-ZOMBIE01-005`。
静止骨架签名：`77a08b65bebd0e35bbda1c8c5095e3875b174297589900b78037efe08bd46622`（按Blender骨序、骨名/父名/静止矩阵7位小数JSON SHA256）。

| 文件角色 | 正式路径 / 摘要 |
|---|---|
| 模型母版 | `art_source/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v006.blend`；SHA256 `82affb03ed5add595938c0274bca0753f38d420f0664a245678d9736f1c5fe14` |
| 动作母版 | 同源树 `animation/enm_melee_fungboar01_animation_v006.blend`；SHA256 `05ff5bd1606b6aacc8498684b18e4f881e2adb8e3f4c73874c559ccf683f9f6e` |
| 稳定GLB | `assets/art/enemies/normal_enemy_3d/melee_chaser/components/enm_melee_fungboar01_visual_top3d.glb`；418764B，SHA256 `9be6ccc0e6f29042570c1f2107ce8da06a16bb832d73c4db2dccf6116121c8a3` |
| 共享贴图 | `assets/art/shared/textures/enemies/tex_color_85eaa809e59fa600fe6c.png`；256²，SHA256 `85eaa809e59fa600fe6cbf8ffe374e0f419080797cfa420571b7bd6b197e8626` |

六剪辑时长：idle3.2/walking1.6/running0.8秒循环，attack1.7/hurt0.8/dead2.4秒单次；当前修复后的候选曲线在最终双源整理中保留，不表示相对原始动作逐帧保真。
仅表现更新：碰撞、AI、HP、伤害、掉落、存档、名义尺寸/普通0.70倍率与攻击48%采样不改；共享此表现的强化怪也沿用新版。
现行14态消费六剪辑；巡逻按实际速度/满速0.62进入跑、低于0.50回走，追击/搜寻/归位仍跑。实际死亡沿goo链立即隐藏、帧末回收，dead剪辑存在不代表尸体保留2.4秒。

## 2. 受影响文件与协作范围

- 接入：上述双母版、GLB及其`.import`、共享PNG及其`.import`；同包`runtime/enm_melee_fungboar01_root_top3d.tscn`、`runtime/melee_chaser_formal_visual.gd`（snapshot来源改为blender_v006）；`tests/verification/verify_melee_zombie_presentation.gd`。
- 仅缓存：报告列出的四个目标`.godot/imported`文件复制回正式缓存；不修改全局`uid_cache.bin`，不作为源资产交付。
- 账本：敌人分账本及`assets/registry/ledger_split_baseline.json`已完成；主会话同步`current_source_index.json`本资产两条、`art_source_migration.json`四条归档、`runtime/character_transfer_ledger.json`当前文件/签名/验收，并新增同包`asset_manifest.json`。源索引其它条目保持；`.gitignore`仅放行新256共享图的`.png.import`，防止干净克隆丢失上限256/无损导入契约。
- 本文档事务仅改：`docs/v0.1/design/怪物设计.md`、`docs/v0.1/16.1_角色美术制作与动作导入流程.md`、包`README.md`、本记录、`development/README.md`、`development/CHANGELOG.md`、`MODULE_INDEX.md`、`feature_registry.json`。
- feature_registry只向ENEMY-AI/ASSET-PIPELINE追加本记录及缺失的既有`verify_melee_zombie_presentation` scene引用，按最新文本比较后局部替换，不重排或改全局partial。

## 3. 实际验证与负向对照

事实证据根目录：工程外 `ShellStorm2-work/sessions/2026-11-16_small_zombie_v006_256/`；下表路径均相对该目录。Godot最终引擎为 `4.7.2.stable.official.ed1daf0bf`。

| 项目 | 结果 / 证据 |
|---|---|
| 双源整理与原生重开 | `source_finalize`、`reopen_sources`均exit0/errors空；256 packed、骨架签名/几何权重一致 |
| 局部蒙皮 | `skin_5046` exit0/errors空，Blend与GLB各5046姿态；Root漂移0、反向法线面采样0，不等于无形变 |
| 定向导入与加载 | `targeted_import_warm`、`stage_load` exit0/errors空；原稳定路径与UID保留、原post-import脚本未改；120fps、贴图无损/上限256/Mipmap |
| 正式14态表现 | `presentation_final/runtime.log` exit0/errors空；固定输入逐态输出、六时长/循环、16骨/800面/256路径、48%及goo即时回收 |
| 正式CPU skin | `cpu_skin_formal_final/runtime.log` exit0/errors空；120Hz、1266采样、倍率0.70，最低世界Y `+0.00182276545092463m`（running 0.15s）、Root位移0 |
| 正式真实渲染 | `gallery_formal_final_opengl/runtime.log`、`live_death_final_opengl/runtime.log`均exit0/errors空；18姿态画廊、真实Enemy3D活体/死亡同帧；不是完整关卡跑通 |
| 贴图负测 | `presentation_negative_texture`模拟256→2048，预期/实得exit1，仅`albedo texture must load at 256x256` |
| 面数负测 | `presentation_negative_budget`模拟800→801，预期/实得exit1，仅`small zombie geometry must have exactly 800 triangles` |

局部形变非零：Blend/GLB最小面积比分别约0.332859/0.332860，主拉伸约0.313–2.541，最小蒙皮Jacobian行列式约0.753818/0.753816；采样与目检不是连续时间零自交证明。
截图为`gallery_formal_final_opengl/living_gallery.png`、`live_death_final_opengl/{living,impact}.png`、`face_closeup_lit_opengl/face_256.png`；报告注明已用ViewImage目检，可辨双黄眼/深嘴/浅牙，无明显尖刺断裂；本文档事务未重新签视觉审查。

## 4. 中间失败与测试语义纠正

- 初次console包装、直接引擎隔离初始化/Autoload及正式探针曾exit124：`targeted_import`、`targeted_import_463`、`targeted_import_direct`、`baseline_original_direct`、`baseline_presentation`、`presentation_positive`、`cpu_skin_120hz`、`gallery_opengl`、`live_death_opengl`；超时不算通过，最终复跑单列如上。
- 修改后测试先对旧资产运行的`baseline_direct`为exit1/23 errors（版本、骨架、256路径及Root判据），不是改前原测试通过证据。
- 备份原测试对新资产完整复跑`baseline_original_final`为exit1，仅两条旧巡逻断言红：`walking clip used outside patrol: []`与`high-speed patrol is not walking`；现有高速巡逻本就跑步，未改生产步态规则凑绿。
- 测试改为按`Enemy3D.VALID_STATES`动态覆盖14态、固定输入逐态断言；显式满速2m/s验证0.62/0.50及迟滞，另验低速追击仍跑。Root比较绑定静止矩阵，不错误要求导入轴向为单位旋转；死亡按现行goo即时回收而非旧尸体延时。
- 早期并行回写`commands.json`有竞态，原始每次`execution.json`保留引擎退出码；runner改逐运行目录独立报告并直接传播Godot返回码，总表重建为`commands_reconstructed.json`。
- 首张无补光脸部近景偏黑，失败证据保留；另补拍`face_closeup_lit_opengl`，未为拍摄修改模型。GLB stride、旧色盘UID及新纹理全局UID未登记警告仍在，路径加载/材质尺寸通过不等于无警告。

## 5. 已完成账本事务与既有红项

`ledger_update_report.json`为后续账本事实源，补足integration报告当时“xlsx未写”的阶段性状态；最终共41格，仅敌人《资产主表》r6（6格）、《3D-敌人》r7（5格）、《敌人动画与状态》r21/59–64（23格）及《域变更日志》r89（7格，v0.1.47）。
三个独立CAS事务为`01_main / 02_prefab_special / 03_animation_special`；专表摘要从匹配旧签名的Git快照只施加本资产增量，不吸收B33、石甲巨人、收租人的既有漂移。其余51行、总目录、其它8本账本及内容数据库字节/数据不变；121公式与原样式/验证/合并/筛选保留。

| 门禁 | before→after | 结论 |
|---|---|---|
| structure | 17→17，exit1 | 同一批既有结构红项 |
| full/enemies | 3→2，exit1 | 仅本资产sha_mismatch解除；收租人r55与保安r7旧红保留，两行25格不变；保安运行文件原已修改，不虚称Git干净 |
| verify_split | 24→24，exit1 | 既有失败逐项相同，column_digest_drift为空，未接受历史漂移 |
| naming | exit0→exit0 | 此项通过，不外推全局全绿 |

## 6. 限制、未执行与回滚

- 保留walking腿幅85%、running腿幅40%、attack臂幅50%、dead臂幅50%/腿幅75%；可读性、步速和打击距离需实际游玩评审，不承诺原动作逐帧保真。
- 待机右鞋底创作尺度离地约1.05–2.58cm、左脚支撑，阴影可能显悬浮；无独立腕踝，局部压缩与256近景软化保留，不宣称双脚贴地/零自交。
- 未执行全游戏/全关卡套件、移动端/APK、完整存档往返、人工交互游玩。主会话已运行全量文档门禁：before/after均exit1，顶层issue 27→16、内嵌追溯10→6；按路径与内容消除行号差异后，本事务新增问题0，其余均在改前基线；无关weapon_hologram缺文档由并行会话补齐，不计本事务成果。资产查重（version_increment）与运行时命名门禁均exit0；8项文件哈希、2条当前源、账本最终SHA与256图实际尺寸一致性断言通过。
- 桌面原始zip、候选原件与旧共享512图哈希保护未变；未控制用户Blender/Godot窗口，未commit/push。
- 备份根：`I:/工作项目/shellstrom2/ShellStorm2-backup/2026-11-16_small_zombie_v006_256/`；报告`backup_hash_verified=true`，旧model_v004/animation_v005及原JPG/PNG在`original_tree/`，改前正式文件在`before_edits/`。
- 本轮七份既有文档逐文件备份至`before_edits/docs_txn_200455_1053012/`，未覆盖已有备份；唯一新文档为本记录。
- 回滚须按报告哈希逐文件比对后恢复对应旧源、GLB/贴图/导入与包装、相关登记；文档及账本按各自事务备份逆向回填并重新验证，禁止整树覆盖并行工作或删除仍被引用共享图。

## 7. 事实源

- `I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-16_small_zombie_v006_256/integration_report.json`：正式文件/哈希、原件归档、验证命令/退出码、CPU蒙皮与截图、限制。
- 同目录`ledger_update_report.json`：41格before/after、三个CAS事务、专表受控摘要、门禁反向对照与未改项；不把完整工具输出复制到设计正文。
