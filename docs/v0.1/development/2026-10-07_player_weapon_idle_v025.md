# 玩家三类持枪站立待机源 v025

日期：2026-10-07；记录ID：PLAYER-WEAPON-IDLE-V025；功能ID：PLAYER-STATE / ENTRY-AVATAR / ASSET-PIPELINE；工程版本：0.1.0。
设计依据与修订：用户本轮要求、[03 §4.0–4.1](../03_技术施工_玩家与操作.md)、[16.1 顶部设计冻结](../16.1_角色美术制作与动作导入流程.md)。代码基线：`dd7d40a8` 的现有工作区；交付提交：工作区，未提交。

## 变更与原因

移动动作按局部前进、左移、右移、后退区分；持枪类型先分 `sidearm / longgun / machinegun`。本轮仅制作三条站立待机，不制作24条持枪移动循环，不改状态机、移动、弹道、碰撞、存档或现有运行入口。

| Blender 场景 | Action / 循环时长 | 站立姿态 |
|---|---|---|
| `14_短枪_站立待机_枪口朝上` | `anim_bunny01_sidearm_idle_v025` / 3.2s | 右手单手、枪口约76°朝上，左手自然放松 |
| `15_长枪_站立待机_胸前斜持` | `anim_bunny01_longgun_idle_v025` / 3.6s | 双手斜持身体前方，枪口约12°上倾，不贴腮 |
| `16_机枪_站立待机_低位承重` | `anim_bunny01_machinegun_idle_v025` / 4s | 双手低位承重，枪口约10°下倾，降低枪体避免挡住面部 |

动作母版：`assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation/chr_bunny01_animation_v025.blend`。沿用相对路径链接的 `production/v021/source/model/chr_bunny01_model_v021.blend`，模型与静止绑定未修改。骨架 `SKEL-BUNNY01-004`，签名 `203cbcaf9a7d4eaa55baacc6ea4d2093e157ad853ecab5bf08abb8a38f41edb8`。

三条动作分别制作呼吸、头耳轻微跟随和手臂承重曲线；root不移，双脚固定，肩肘腕两段求解保持骨长与单位缩放。长枪、机枪左手跟随实际Prefab的SupportHandSocket，右掌跟随主握点。预览复用吹风机、扫帚步枪、水箱爆能枪的真实GLB及Prefab偏移，比例沿用现有作者空间1.5/2.475。枪模、相机和枪体预览曲线标记 `preview_only`，禁止作为角色骨骼动作导出。

制作脚本 `scripts/blender/author_bunny_weapon_idles_v025.py`；预览打包 `scripts/blender/package_bunny_idle_previews.py`；登记 `scripts/register_bunny_weapon_idles_v025.py`。保留原有14条Action曲线和历史场景；v024中“02_正常移动_小跑”预览场景原本挂climbing动作的历史问题未顺带修改，原moving Action仍完整保留。用户打开的Boss Blender会话有未保存内容，本轮全程独立后台制作，未替换其当前文件。

## 验证结果

| 命令 / 检查 | 环境及存档隔离 | 结果 | 证据 |
|---|---|---|---|
| Blender 4.5后台制作、保存重开 | 独立factory-startup；不启动游戏、不触碰存档 | 退出0；原14动作曲线摘要一致，3个新循环骨架签名一致 | `outputs/character_pipeline/weapon_idle_v025/original_actions.json` |
| 每0.25帧检查 | 三循环共2595采样时点 | 单位缩放、臂链连续、右握点、长枪/机枪左支撑、脚底静止、root固定、首尾与两周期重复通过 | 同目录 `validation.json` |
| 每4帧可见网格接地检查 | 165采样时点；原生Blender求值网格 | 角色最低值为约0.0001mm浮点误差；机枪最低点离地约5.8mm | 同上 |
| 原生Workbench渲染 | 正面/侧面/斜前共9图，三循环各32帧 | 退出0；检查实际持枪轮廓与脸部可见性。灰模预览不代表最终材质或游戏镜头 | 同目录 `standing_weapon_idles.png`、三个 `*_idle.gif` |
| 资产与文档门禁 | Python；不启动游戏 | 结果见下方门禁摘要；既有失败按改前/改后比较 | 同目录 `before_*`、`after_*` 日志 |

源级中转摘要与文件SHA：`source/animation/chr_bunny01_weapon_idles_v025.json`。登记沿用 `CHR-PLY-CAPSULE01-3D-BUNNY01`，源级状态 `authored`（中转待导出标签 `authored_pending_export`）；主表活动版本、路径与制作状态不变。角色分账本按 `ledger_index.json` 解析，主表仅追加源依据/备注并更新日期，动画专表和中转专表另事务追加；不新增Prefab行。

门禁摘要：

- `check_asset_registry --scope structure`：改前/改后均退出0，1008资产、9域；`verify_ledger_split`：均退出0，无损基线通过。逐格对照只改变主表P13/V13/Y13、动作61–63行、中转106–107行及域日志16行；只更新本角色行及两个专表指纹，其他资产身份、指纹、合并区和数据验证保持。
- `check_asset_registry --scope full --ledger characters`：改前/改后均退出1，日志完全相同；仅既有 `CHR-PLY-BUNNY01-HEAD-CHIBI-ANIME-3D` 的v021包装SHA不符，本轮未修改该行或文件。
- `check_documentation_contracts`：统一父子Python解释器及UTF-8环境后，改前/改后均退出1，日志相同；仅四条既有验收入口未登记：`verify_base99_swivel_chairs`、`verify_expedition01_spawn_ramp`、`verify_expedition_resume_entry`、`verify_pushable_base_chairs`。本轮无断链或新文档结构问题；初次系统python3缺openpyxl/输出编码异常不计作有效检查结论。
- `check_asset_runtime_naming` 首轮退出1：14个已有版本化运行文件、v022/v023/v024三个目录和tscn引用计数上升。本轮只增加source内Blender/JSON，没有新增运行资产或运行引用；未重写命名债务快照。后续重复扫描耗时过长中断，不算再次通过。
- `check_ledger_refs` 全仓扫描耗时过长中断，未取得完整结论；本轮登记脚本通过 `LedgerIndex` 解析分账本，无硬编码旧单体资产表。Python语法与文档差异空白检查通过。未执行失败注入。
- 账本随机访问误用只读加载造成登记缓慢，已改为正常加载并从备份验证后续接主表事务；最终两个事务和无损门禁均完成，没有重置其他资产基线。原v024动作文件SHA仍为 `d0fc18ea212d14adb38179615e9fd36c8e56388e0009024c6402bafe08272f71`。

## 遗留与状态更新

- 尚未导出GLB、生成新运行采样库或切换Godot；现有v021包装仍读取v024动作库。下一段需要把 `idle + weapon_family` 映射到新动作，并实现可见枪体朝向跟随，现有仅跟随右掌位置的路径不足以还原本源姿态。
- 四方向慢走/正常移动、瞄准/射击/换弹等覆盖动作仍待制作。未进行Godot、游戏真实镜头或整项目完整套件验收，不据此宣称运行效果已完成。
- 预览枪仅作动作配合参考；当前水箱爆能枪体积较大，机枪采用较低持握高度。未宣称角色和所有枪模组合零穿插，后续运行换枪仍需专项适配。
- 源级回退直接使用保留的v024；运行文件未变化。账本改前副本位于 `_scratch/bunny_weapon_idles_v025_ledger_before/`。`MODULE_INDEX`仅更新源动画子项状态。
