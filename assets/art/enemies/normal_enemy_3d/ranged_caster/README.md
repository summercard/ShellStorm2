# 保安僵尸（ranged_caster）表现包

AssetID：`ENM-RANGED-SPORESHOOTER01`

逻辑 ID：`ranged_caster`；目标名称：保安僵尸

运行资产版本：`v004`；制作源版本：`v002`（不改源）

状态：`active`；v004已通过源/正式表现L1及Forward+/Vulkan真实渲染L2；未代签全关卡与Android设备验收。

## 交付与目录契约

用户已授权将警察僵尸2.5替换既有 ranged_caster 并将运行贴图压至256，不新增敌人逻辑类型。AI、生命、碰撞、伤害、三弹散布、弹丸出生位置、冷却、掉落与刷怪池仍由 `Enemy3D` 持有。

- 模型母版：`art_source/enemies/normal_enemy_3d/police_zombie25/source/model/police_zombie_25_model_v002.blend`。
- 动作母版：`art_source/enemies/normal_enemy_3d/police_zombie25/source/animation/police_zombie_25_animation_v002.blend`。
- 稳定组件：`assets/art/enemies/normal_enemy_3d/ranged_caster/components/enm_ranged_sporeshooter01_visual_top3d.glb`，一体蒙皮枪，无碰撞。
- 运行贴图：`assets/art/shared/textures/enemies/tex_color_ec827f2a2c65836f15cc.png`，实际 PNG 为 `256×256`，GLB 外链此文件，不嵌入大图。
- `runtime/` 保留既有 Prefab、表现脚本与 `character_transfer_ledger.json`；正式表现脚本已适配新骨架、融合枪与缺片回退。
- 源 Blend、原始贴图不改；过程导出、预览和 QA 位于工程外 `ShellStorm2-work/`。源索引只追加上述两份 Blend，保留其它项。

## 骨架、朝向与尺寸

- 新模型为65骨 `mixamorig`，不再声称复用旧36骨 `SKEL-MELEE-FUNGBOAR01-002`。
- 现有联合几何/蒙皮/rest签名为 `6218d2e45ba85c29b24c828cad78fd006f3e4ec79e5a2e2805322f92fba2b629`；独立重开双母版的骨架签名为 `b3feb75b3488678b7611e93b72eb56be711db629f0ba8c8f84098968d7cf2345`，两源完全一致；联合签名不充当骨架签名。
- Blender源朝向保持 `-Y`；Godot `-Z` 契约由 `VisualGLB` wrapper 的 yaw `180°` 完成。
- 未缩放源rest高约 `0.9995118976m`；仅 wrapper 统一倍率 `1.85804992`，视觉rest高 `1.857143m`；游戏侧乘 `0.7` 后约 `1.30m`。表现根scale为 `(1,1,1)`，不改碰撞；正式普通/强化目标契约与真实渲染已复核；CPU蒙皮全动作最小y约-0.000722m。
- 旧 `L_Hand` 外挂枪取消；新枪已融合进身体蒙皮网格，源骨为 `mixamorig:RightHand`，Godot导入名为 `mixamorig_RightHand`，不实例化第二把枪或玩家 `WeaponModel3D`。

## 四动画与状态映射

制作源30fps，仅有以下四段真实剪辑，不保留旧六段基础动作或伪造缺失动作。

| 动画 | 秒 | 源帧范围 | 循环 |
|---|---:|---|---|
| armed_idle | 3.2 | 0–96 | 是 |
| walking_armed | 1.6 | 0–48 | 是 |
| running_armed | 0.8 | 0–24 | 是 |
| shoot | 0.8 | 0–24 | 否 |

`dormant/idle/alert` → `armed_idle`；`patrol` → `walking_armed`；`chase/search/return` → `running_armed`；`telegraph/attack/recovery` → `shoot`。移动段沿用当前表现脚本的实际速度重判、迟滞、相位与交叉淡化，不再沿用旧文档“不按速度切段”的结论。

射击视觉采样点为 `shoot@0.384s`（48%，源帧11.52）；动画只负责表现，弹丸与伤害判定仍由 `Enemy3D._perform_attack()` 执行。

## 缺片与限制

- 缺少 `hurt`：stagger或受击姿态请求固定回退 `armed_idle@0`，停止循环相位及交叉淡化；受击仍闪白，不宣称有真实受击动画。
- 缺少 `dead`：接口请求固定回退 `armed_idle@0`；正式玩法为无尸体死亡，不展示伪造倒地。保留2.4秒接口时长不代表存在死亡剪辑或尸体。
- 缺少 `reload`，不接入弹药或玩家换弹规则；融合手指未制作独立开合。
- 正式表现12态、四动画、普通/强化及10代理、移动明暗连续性、攻击站定、攻击恢复均通过；详见独立开发记录和工程外证据。

## 当前追溯 SHA-256

| 文件 | SHA-256 |
|---|---|
| 模型v002 Blend | `e1eaa17e77bc1e52a17363d078a9da4793625fce65fdf45da201045bffb8e9c6` |
| 动画v002 Blend | `b05d58cd54b7ddcfb0598629e2be1d42c491be393657ef8891c8284ff5a4c3ea` |
| stable GLB | `fa2b7fd396d2d2244ecb9ca90b058790b5925e5f5e4b78b5e1600d7433813604` |
| 256 PNG文件字节 | `10fc9bccdaa4df76bf5aef380f18048c05f1e136c89e5d2087b7bb109c15d3e6` |

贴图像素SHA为 `ec827f2a2c65836f15cc43d0b4820853a5d96a8a722201dda7f80bd906a6acfa`，与PNG文件SHA不同；文件名只含像素SHA前缀。完整路径、字节数、Prefab/脚本SHA见中转JSON的 `files` 与源清单的 `runtime_files`。

## 本次验收与账本

- 正式表现专项、Forward+/Vulkan258图/12类、明暗移动、攻击站定、攻击恢复3278检查及普通/强化双瞳目标契约16检查均exit0、无非预期脚本错误。
- Windows S3TC与Android ETC2导入资源均为256×256，GLB无内嵌图像字节，原2048制作贴图未改。
- 敌人分账本主表row7、3D-敌人row8、敌人动画与状态row22及域日志v0.1.49/v0.1.50已最小同步，AssetID和逻辑ID不变，R/S公式及其它行不变。
- 全库红眼专项启动超时未通过，本警察目标双眼跟骨专项单独通过。全局文档11条旧断链、敌人row55旧状态及split/纹理旧债保留，不放宽或批量接受。
- 完整关卡人工体验、Android设备未执行，不提升全局ENEMY-AI/ASSET-PIPELINE的partial状态。
- 详细记录：`docs/v0.1/development/2026-11-16_police_zombie25_import.md`；证据：`../ShellStorm2-work/sessions/2026-11-16_police_zombie_import/`。

## Historical：旧版交付与验收（不适用于v004）

下文保留原README全文，包含旧版36骨、L_Hand外挂与旧通过标记，仅供历史追溯；不得视为当前实现或本次验收结果。中转JSON原v003记录及候选清单原记录完整保存在各自 `historical[].record`。

# 保安僵尸（ranged_caster）正式表现包

AssetID：`ENM-RANGED-SPORESHOOTER01`  
逻辑 ID：`ranged_caster`  
版本：`v002`  

## 交付口径

这是 `ranged_caster` 的正式视觉替换，不新增敌人逻辑类型。AI、生命、碰撞、伤害、三弹散布、弹丸出生位置、冷却、掉落与刷怪池仍由 `Enemy3D` 持有。

- 体型与小僵尸一致：源高 `1.857143m`，运行时统一倍率 `0.70`，展示高 `1.30m`。
- 复用小僵尸 `SKEL-MELEE-FUNGBOAR01-002`，36 骨；模型与动作骨架签名一致。
- 基础动作复用小僵尸六段：idle / walking / running / attack / hurt / dead。
- 新增 armed_idle / walking_armed / running_armed / shoot；远程攻击三个状态采样 shoot。
- 枪为双管炮纯视觉附件，挂在实际右手 `L_Hand`；不实例化玩家 `WeaponModel3D`，不接入弹药、换弹和玩家武器规则。

## 目录

- `source/model/`：FBX 入库副本、贴图、绑定后的模型 Blend。
- `source/animation/`：独立动作 Blend；与模型共享36骨。
- `components/`：无版本号视觉 GLB；不含枪、不含碰撞。
- `runtime/`：Prefab、表现脚本、中转账本。
- `previews/`：源级动作预览。

## 状态映射

`dormant/idle/alert` → `armed_idle`；`patrol` → `walking_armed`；`chase/search/return` → `running_armed`；`telegraph/attack/recovery` → `shoot`；`stagger` → `hurt`；`dead` → `dead`。

选段由状态决定，不按速度切段。动画只负责表现，开枪判定仍由 `Enemy3D._perform_attack()` 执行。

## 验收

- `SECURITY_ZOMBIE_PRESENTATION_OK animations=10 shotgun=true bone=L_Hand ranged_logic_preserved=true`
- `ASSET_GUARD_PASS`
- `ASSET_REGISTRY_CHECK_OK scope=full assets=12 ledgers=1`
- `verify_3d_enemy_behavior_flow` 的七条 floating-number 红项是既有基线问题；本次保安僵尸专项不新增该类错误。
