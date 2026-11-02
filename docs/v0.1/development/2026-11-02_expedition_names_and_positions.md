# 远征情报室入口轮换与正式名称

FeatureID：WORLD-ENTRY / WORLD-PLAN / ASSET-PIPELINE。工程版本0.1.0。来源：2026-11-02用户明确要求。

## 设计与变更

现行规则见[全息城市r7](../design/远征全息城市交互设计.md#关卡正式名称与入口位置r7)、[01设计](../design/远征关卡01设计.md)、[03设计](../design/远征关卡03设计.md)。

- 原99槽位(5,2.9,1) → expedition_01，牌面CloseAI数据库。
- 原01槽位(-5,2.7,2) → expedition_03，牌面无限公馆。
- 原03槽位(4.4,2.8,-5.2) → 99，名称测试关卡99保留。
- 槽位的牌面比例、偏移、挖空和视廊一起轮换。配色按身份，01/03青色、99洋红；编号徽标保留。导航/解锁/生成/存档ID、关卡内容与资源路径不变。
- GameDesignConfig显示名与setting_name、01/03场景display_name同步；level_code保留代号。塔3确认文案也从同一配置取名。旧设计源level_name_zh保留代号，避免改动设计数据/存档指纹。
- 场景账本新增《关卡名称对照》，按代号/level_id索引，包含01/03/99及未改动02；ledger_index同步声明分页。既有场景账本所有单元格逐格相同。UI-SCREEN-LEVEL-SELECT仅N13/Q13/V13/Y13四格元数据修改并追加域变更日志；公式、AssetID、SHA和制作状态不动。无损基线只更新本UI行摘要和受影响列摘要，其余1416条资产摘要保留。
- 原02相对前排的验收改为按03查左前槽位，匹配新布局，不改变其后排坐标或放宽视廊标准。

## 验证

所有Godot进程在Autoload前设置独立APPDATA/LOCALAPPDATA/USERPROFILE，未使用正式用户档。

| 检查 | 退出码 | 结果 |
|---|---|---|
| verify_expedition_hologram_city，真实OpenGL，02未解锁 | 0 | EXPEDITION_HOLOGRAM_CITY_OK；鼠标逐入口目标ID、键盘/手柄、视廊、关闭恢复通过 |
| 同场景，02已解锁 | 0 | 同上；四入口及02原位通过 |
| verify_expedition_hologram_city，真实Forward+，02未解锁 | 0 | 原生画面已目视核对，三入口牌面与编号完整可见，点击/输入/视廊/关闭恢复通过；0脚本ERROR、0引擎ERROR，109条既有UID WARNING |
| 账本结构，改前/改后 | 0 / 0 | 1417条资产；新增分页已声明 |
| 分账本无损，改前/改后 | 0 / 0 | 无资产丢失、无额外资产、无列摘要漂移 |
| UI分账本full检查 | 1 | 7条既有sha_mismatch；逐条核对改前账本的路径/记录SHA一致，七份目标资源本轮均未修改；未回填无关漂移 |
| check_level_decoupling.py | 0 | 七个通用机制容器零违规 |
| check_documentation_contracts.py | 1 | 44项既有问题：43处坏链接、1组未登记验收。改动文件中的坏链接已逐条与改前备份对照存在；其余位于未改文件。 |
| check_asset_runtime_naming.py | 1 | 既有带版本运行资产/引用；本次未新增运行资产路径，未扩大豁免。 |

预期故障：无。OpenGL两次均0条SCRIPT ERROR、0条ERROR，各110条WARNING（缓存资源UID及TAA渲染器提示）。未执行：完整远征游玩、完整全局套件、移动端；本轮不提升整关partial状态。

证据：工程外 `ShellStorm2-work/sessions/2026-11-02_expedition_names/`（qa截图/日志、门禁日志、文档旧问题对照）。改前副本：`ShellStorm2-backup/2026-11-02_expedition_names/before_edits/`。
