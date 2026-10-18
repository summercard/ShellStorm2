# 远征01命运卡范围与元素表现落地

日期：2026-10-18；FeatureID：FATE-RULES / VFX-POOL；工程版本：0.1.0；交付为工作区修改，未提交。
主设计：[六关投放](../design/命运卡六关投放设计.md)、[特效契约](../14.6_特效系统与制作规范.md)。来源：用户要求先限制01卡池，再制作火冰毒电低粒子特效及伤害字体颜色/飘动；配色速度授权按技能感受决定。

## 实施与边界

- `data/fate/level_pools.json` schema 1：`policies.expedition_01` 包含 `policy_id / revision / upright_only / card_ids`，唯一只读策略 `FateOfferPolicy`，21稳定身份且新报价仅正位。门后、工作台、占卜及愚者随机奖励复用策略，Bridge从已绑定玩家祖先取得地图，不使用后台current_scene猜测。缺失01策略时拒绝全池回退。
- `Dungeon3D` 继续独占门报价/已购快照与经济冻结；schema 1新增可选policy字典。旧冻结报价保持原身份/方位，下一门采用新策略，不重抽、不重扣；支付/失败退款沿用Bridge。01白名单与稀有度交集初期仅权杖王牌/八两张，展示两张且可退出，不扩池或偷偷改稀有度。
- 02—06规则、前两门核心教学保底、可支付性教学方案、来源和剩余兑现机会过滤未实现；通用无策略地图仍保留原抽取规则。21张表示本关允许身份总量，不表示开局就能抽到所有稀有度。
- 四个独立Prefab均继承 `VfxEffectBase3D`、由池注册AssetID引用、无碰撞。火焰4枚错相跳动火舌，冰霜4晶体加脚底薄霜，毒雾4团半透明绿雾环绕；Enemy3D现有状态驱动跟随/刷新/到期/死亡/离树回收，无第二套伤害计时，叠层不增粒子。
- 连锁每跳4火星（起终点各2）、6段电弧与光晕、飞行头；飞出0.045秒、收尾0.20秒、每跳视觉延迟0.025秒。位置使用真实链目标的世界快照；不延迟玩法伤害；替代链目标原通用命中碎片，避免再叠一套粒子。光源回收归零，复借重置位置尺寸。
- 伤害色：普通`fff1d5`、暴击`ffd34e`、火`ff783d`、冰`8ee5ff`、毒`8de85b`、电`c2faff`；暴击优先金色，多元素直击按火/冰/毒顺序取第一项，周期伤害按自身元素。寿命基线0.56秒（调用方原随机比例仍保留）、上升0.90m、显字0.04秒、先快后慢淡出。字体和描边不变。正式池与兜底共用DamageNumberStyle；不改伤害数值。

## 资产登记

| AssetID | 制作编号 | 版本 | 运行Prefab |
|---|---|---|---|
| VFX-FATE-FIRE-3D | FX01-29 | v001 | assets/art/vfx/combat_3d/vfx_fate_fire_root_top3d.tscn |
| VFX-FATE-FROST-3D | FX01-30 | v001 | assets/art/vfx/combat_3d/vfx_fate_frost_root_top3d.tscn |
| VFX-FATE-POISON-3D | FX01-31 | v001 | assets/art/vfx/combat_3d/vfx_fate_poison_root_top3d.tscn |
| VFX-FATE-LIGHTNING-3D | FX01-32 | v001 | assets/art/vfx/combat_3d/vfx_fate_lightning_root_top3d.tscn |
| VFX-DAMAGE-NUMBER-3D | FX02-01 | v005 | assets/art/vfx/combat_3d/vfx_damage_number_root_top3d.tscn |

源参数清单在 `art_source/vfx/fate_elements/v001/asset_manifest.json`，使用Godot几何与脚本，无Blender源。特效账本主表48—52行（四个新资产、补齐既有3D数字缺失主表项）；3D专表49—52新增、16行更新数字。旧2D占位 `VFX-DAMAGE-NUMBER` 保留。更新R/S公式范围、总览、下拉验证、筛选、域变更日志v0.1.27，逐格保证历史主表内容及3D非目标行未改。

只更新五个目标ID的基线指纹，未接受其他资产哈希漂移；3D专表此前已有摘要漂移，本轮记录原记录值、实际前值和实际后值，并保留历史单元格。登记脚本首次因把追加区域原空白单元格也作为不可变内容而中止，未落盘；调整为允许追加区域空白写入后通过。登记脚本与原表备份留在工程外。

## 验证结果

Godot 4.7.2；物理克隆工程在启动Autoload前配置独立用户目录 `ShellStormFateElements20261018`，Windows路径断言另提供工程外APPDATA/LOCALAPPDATA，不依赖场景test_mode保护存档。新增两项已注册core。

| 验证 | 退出码 | 结果 |
|---|---|---|
| 隔离工程editor import | 0 | 无脚本错误 |
| verify_fate_level01_pool | 0 | 1849检查：21可达/无越界/无逆位、不重复、正式门/Bridge宿主、冻结和旧快照 |
| verify_fate_element_vfx | 0 | 34检查：跟随、颗粒、复用、生命周期、真实链调用/颜色、两端爆发、灯灭、速度 |
| verify_fate_economy_service | 0 | 680检查；真实清房拾金币、冻结报价、购买、销毁重建、继续购买 |
| verify_fate_card_purchase_flow | 0 | 正式购买/全槽拒绝/退出回归 |
| verify_fate_weapon_completion | 0 | 武器规则回归 |
| verify_fate_integration_completion | 0 | 729检查，无失败 |
| verify_damage_number_style_flow | 0 | 字形/描边/位移/随机化回归 |
| verify_vfx_pool_lifecycle | 0 | 回收/复借/场景清理回归 |
| 负向：断开Enemy跟随 | 1（预期） | 6项失败；无SCRIPT ERROR，不以解析错误充当负测成功 |
| 负向：闪电回收不熄灯 | 1（预期） | 灯灭断言失败；无SCRIPT ERROR；恢复后重新通过 |
| OpenGL真实渲染预览 | 0 | 正式Enemy/Projectile调用，120帧/30fps；已查看闪电及元素数字帧 |
| check_asset_registry --scope structure | 0 | 1298资产、9分账本结构通过 |
| verify_ledger_split | 0 | 1298资产、9分账本，无缺漏/列漂移 |
| check_asset_registry --scope full --ledger vfx | 1（历史问题） | 28条既有sha_mismatch，ID集合和前测一致，新/更新五项无错误 |
| check_asset_runtime_naming | 1（历史问题） | bunny01 production/v022、v023、v024及3个.import路径；本批无带版本运行资产 |

正常机制/回归最终均无SCRIPT ERROR或ERROR。初次经济回归仍断言必须买满3张，改为必须买满本门实际候选数后通过，未改变价格或扩大池。初次渲染缺隔离工程icon.svg，补复制正式图标后重跑退出0且无ERROR；OpenGL的TAA不可用警告与正式远征既有Boss南侧门扇共享警告保留，不算脚本错误。未运行全量套件、完整01人工游玩、满屏多敌压力或Forward+渲染；预览是独立展示台而非整关体验验收。

原始证据：工程外 `ShellStorm2-work/probes/2026-10-18_fate_elements/`，包含 `final_checks.json`、各专项日志、`visual_final.log`、`fate_elements_preview.mp4`及截图；备份在 `ShellStorm2-backup/2026-10-18_fate_elements/before_edits/`。文档门禁最终结果见本页末段。

文档门禁：按要求运行 `python3 scripts/check_documentation_contracts.py` 退出1，28项（27历史断链＋默认Python缺openpyxl），归一化行号后与前测问题集合相同，无新增。将bundled Python加入PATH后重跑退出1，仅余27历史断链，媒体域检查通过。命名门禁前后文本仅stdout/stderr排序不同，失败路径相同。`git diff --check` 通过。
