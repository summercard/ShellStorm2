# 2026-10-08 命运卡运行效果补全

- FeatureID：`FATE-RULES`
- 工程版本：`0.1.0`
- 来源/状态：用户要求修复审计中“功能不满足”和“接线有问题”的48张运行卡；本轮运行消费者、正式Bridge、角色/世界生命周期和续档已补全并通过专项，FATE总体仍为 `partial`。
- Owner：`FateCardEngine`负责效果参数与战斗命令；`WeaponAssemblyTree`/`WeaponModel3D`/`Projectile3D`/`Enemy3D`负责武器末端；`Player3D`负责角色命运；`Dungeon3D`负责世界规则及房间生命周期；`FateCardGameBridge`负责正式应用事务；`RunPersistenceService`沿既有快照入口保存运行状态。

## 本轮修复范围

### 武器22张

- 修复力量、权杖·王牌/国王的伤害、护盾、碰撞体积和 `bullet_speed` 消费；修复附属枪属性污染主枪、主副枪交替及携枪弹命中触发。
- 接通命运之轮首发/弹匣规则、死神命中/未命中成长、高塔吸引与换弹时长、恶魔仅作用于附枪、星星最远可见筛选。
- 补齐配件命中/换弹事件、移动炮台、返航固定倍率/回填、复制波延迟或后向、火/冰/毒独立状态与真实tick。
- 王后奖励改为按来源枪和实际持牌判定，击杀归属不再由Dungeon无条件增加必暴。

### 角色12张

- 修复女祭司逆位生命上限/治疗、恋人伤害与暴击、隐者冲刺无敌、倒吊人反射、月亮首次/后三次受伤、审判付魂救助。
- 接通圣杯·二进房扣血/清房治疗、圣杯·三精英进战护盾、圣杯·四首次换弹、圣杯·五正逆血线连续计时。
- 愚者改为抽卡后持久十杀触发，走正式身份/方位/事务链；取消环境层白送战斗卡。
- 切枪按武器实例保留运行树临时状态；新局和结算清理命运临时状态。

### 世界14张及生命周期

- 皇后/星币·二/星币·三按 `04 §21` 的单件规则执行“追加候选、择优、仍落一件”，补齐真实稀有度排序和上限。
- 接通皇帝波次/精英预约、教皇临时钥匙、正义/节制/太阳/世界倍率、撤离区域敌速、赏金队列、地图隐藏类型和当前/未来波诅咒。
- 星币·王牌遵循 `14 §5.4`：只由抽卡触发，清房后明确拒绝，不恢复旧环境五杀白送规则。
- 角色进房回调改为在streaming判定前按全局房键幂等触发；清房、真实精英进入战斗、祝福计时均接入正式生命周期。

### 正式应用、来源和续档

- `FateCardGameBridge` 对 WORLD 使用 `Dungeon3D.apply_world_fate_card(card)` 唯一命令；只有真实成功才登记持卡、发观察事件和消费选择，失败保留卡片。
- 魔术师、战车、权杖·三接入真实来源选择；来源不转移、不消耗，不伪造背包节点；静态配件若没有事件契约则明确拒绝，不吞卡。
- 愚者固定奖励提供待领取入口，失败保留稳定ID/方位，不重抽。
- 在既有 `runtime_player_state_v2.fate_run_state.version=1` 中保存/恢复角色、世界、Bridge、持牌方位、待领取、运行枪树和真实 `weapon_instance_id`；恢复不重放即时效果、不重复扣魂或登记。

## 验证

所有Godot专项使用4.6.3 console，并在进程启动前隔离 `APPDATA`/`LOCALAPPDATA`；未触碰正式用户档。通过判据为退出码0、成功标记和无脚本错误同时成立。

- `verify_fate_weapon_completion`：专项通过，标记 `FATE_WEAPON_COMPLETION_OK`。
- `verify_fate_character_completion`：127项通过，标记 `FATE_CHARACTER_COMPLETION_OK`。
- `verify_fate_world_completion`：113项通过，标记 `FATE_WORLD_COMPLETION_OK`。
- `verify_fate_integration_completion`：728项通过，标记 `FATE_INTEGRATION_COMPLETION_OK`。
- `verify_fate_resume_completion`：JSON roundtrip、重载和reset专项通过，标记 `FATE_RESUME_COMPLETION_OK`；另有writer/resumer两进程证据。
- 既有 `verify_tarot_fate_runtime`、`verify_celestial_fate_scope_flow`、`verify_3d_fate_weapon_flow`、`verify_weapon_instance_fate_ownership_flow`、`verify_dual_weapon_quick_map_fate_flow`：主回归退出码0、成功标记存在、无脚本错误。
- 中间一次主回归的3个失败是Windows反斜线导致的测试隔离路径断言误报；将世界专项统一为路径规范化后重跑通过，未放宽玩法断言。

## 当前遗留与边界

1. 精英名册受楼层/seed/唯一预约限制；不可用时按正式契约拒绝，未伪造任意层都可用的精英。
2. 静态瞄具/弹匣/枪托如何转换为命中或换弹事件尚无冻结设计；当前不再伪造配件效果。
3. 背包散装来源必须先通过既有装备事务装配，尚无独立“从背包选来源并转移”的命运耗材契约。
4. 未完成真实窗口输入、来源面板鼠标操作和完整游戏流程视觉QA；headless专项不替代这些验收。
5. 文档总门禁仍有既有CHANGELOG断链、范围外未注册用例及环境缺少`openpyxl`；资产命名门禁仍有既有版本化资产债务，本轮未修改资产、不将全局状态标绿。
