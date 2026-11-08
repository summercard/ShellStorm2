# 收租人契约与账本同步记录（2026-11-07）

## 范围

本记录只覆盖收租人相关的设计、施工索引、开发追溯与资产账本同步。未修改 `runtime`、`tests` 或 `.workbuddy/memory`；工程中其他代理的并发修改保留原样。

设计页只写目标规则与接口契约；本记录只写本次实际完成的文档/账本动作和可核验证据，不代表收租人整体完成、整体通过或已验收。

## 本次实际修改

- 修订 `design/精英02收租人状态与动作契约.md`：
  - 将目标契约升级为 r13，明确目标规则与现状证据分离；
  - 增加独立库存、提交成功后才生成“抛落→飞向收租人”的纯视觉实体、拖尾完成门禁与失败整体回滚；
  - 明确完整 `WeaponInstance` 属性保留、两个悬浮枪挂点、下一关且非本关才真实装备；
  - 明确绿色血瓶样式 `+N` 并复用 `VFX-HEAL-NUMBER-3D`；
  - 增加 XP 四来源、等级对生命/伤害/攻击频率/体型的影响和 1 级体型 `1.0`；
  - 增加同阵营但收租人可主动攻击普通怪、普通怪不自动仇恨的目标规则；
  - 增加实际伤害 10% 触发真实门边撤离、闪现/转移 VFX 完成后才可提交；
  - 增加生命不高于 20% 时库存 50% 掉落、单件至少 1、`kneel` 战败、战败非死亡和跪地后消失。
- 修订 `design/怪物设计.md`：补充收租人阵营、成长、独立库存、转移、治疗、武器实例、战败目标口径。
- 修订 `06_技术施工_怪物精英与Boss.md`：将收租人整体状态明确为 `partial/development`，保留既有接入证据并列出新增目标契约待主代理实现/验收项。
- 修订 `MODULE_INDEX.md` 与 `feature_registry.json`：待同步到本记录后仍保持 `ELITE-ROSTER` 为 `partial`，不新增未执行测试结果。
- 修订 `CHANGELOG.md`：追加本次文档/账本同步事实，历史记录中的旧体型和旧夺取口径保留为历史，不回写成当前目标规则。
- 按 `assets/registry/ledger_index.json` 定位并备份敌人、武器、特效、物品道具、道具五个分账本；账本写入结果以保存后重新读取为准。

## 已核对的既有证据

- 收租人正式场景已存在两个 Marker3D 挂点 `WeaponMountLeft` / `WeaponMountRight`；当前并发场景 SHA-256 为 `5b63de8d11ff2f9ded71d00ce12253092e51f2fc14273369257c848838d9fe69`，本次不修改该 runtime 文件。
- 拖尾 Prefab 已存在：`assets/art/vfx/combat_3d/vfx_elite_rent_transfer_trail_root_top3d.tscn`，AssetID 为 `VFX-ELITE-RENT-TRANSFER-TRAIL-3D`；本次不修改该 runtime 文件。
- `VFX-HEAL-NUMBER-3D` 已存在并作为共享治疗数字特效；本次不创建重复治疗资产。
- `EliteRentTransfer3D` 的既有快照口径为纯视觉、不使用地面拾取事务；本记录不把它扩写成事务已完成。

## 账本与基线

- 账本路径以 `assets/registry/ledger_index.json` 为唯一来源；未根据猜测新增武器、物品或道具资产。
- 敌人账本 `资产主表` 第 55 行已保存并复读：`ENM-ELITE-ARMS-TAKER-3D` 状态为 `开发中（partial）`，正式场景 SHA-256 为 `5b63de8d11ff2f9ded71d00ce12253092e51f2fc14273369257c848838d9fe69`，备注含 `WeaponMountLeft` / `WeaponMountRight`。
- 特效账本 `资产主表` 第 62 行和 `3D-特效` 第 257 行已保存并复读：新增真实存在的 `VFX-ELITE-RENT-TRANSFER-TRAIL-3D`，Prefab 为 `assets/art/vfx/combat_3d/vfx_elite_rent_transfer_trail_root_top3d.tscn`，SHA-256 为 `1bafa7b431aa50d92b9c0af144ed28cdd55360e4438dbeb39822f0ae1331d2bc`，查重结果为 `唯一`。
- 未登记没有独立正式 `.tscn` 的主视觉 `VFX-ELITE-RENT-TRANSFER-3D`；治疗继续复用既有 `VFX-HEAL-NUMBER-3D`，没有创建重复治疗资产。
- `assets/registry/ledger_split_baseline.json` 仅更新收租人正式场景 SHA，并新增拖尾 AssetID 基线；未批量接受其他域或其他资产的无关 SHA 漂移。
- `docs/v0.1/14.6_特效系统与制作规范.md` 新增转移参数与基线章节，明确八条公式、提交门禁和当前未验收边界。

## 待主代理完成或复核

- runtime 事务：提交时序、完整转移 VFX 完成门禁、保存失败回滚、XP 事件幂等、真实门边撤离、下一关武器装备和 kneel 战败。
- tests：收租人真实契约、账本写入后公式/基线校验、正式场景渲染与跨关行为。
- 本记录最终状态只由主代理结合实际测试证据补充，不由文档同步动作推断。
