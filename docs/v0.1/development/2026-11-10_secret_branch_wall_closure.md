# 远征01隐藏房间外围封闭与空门洞修订

日期：2026-11-10；记录ID：`2026-11-10_secret_branch_wall_closure`；功能ID：`WORLD-SECRET`；工程版本：`0.1.0`。
设计依据与修订：[支线秘密房间设计 §3.5.2、§11.1](../design/支线秘密房间设计.md)；施工对照：[05 技术施工 §5.5](../05_技术施工_关卡生成与爬楼.md#55-远征关卡传送支线2026-10-18-冻结2026-11-10-外围封闭与门净空无头验收通过表现待真机)；代码基线：`src/world3d/SecretBranch3D.gd` 新增约 160 行 `_reconcile_branch_shell` 及 helper，`_spawn_branch_room` 在 `ensure_shell_built` 后调用；交付提交：未提交，工作区状态。

## 变更与原因

问题表现：远征01隐藏房间复用正式房壳后，烘焙候选门、旧共享边或缺墙段可能留下空门洞；玩家从真实地砖边界走出外围后掉落。仅补门扇不能形成可通行的门墙，按矩形包围盒铺满又会错误填平 L 形凹口和桥坑。

本轮已完成代码与测试接线，不是仅文档更新：

- `SecretBranch3D._reconcile_branch_shell` 在 `ensure_shell_built` 后执行，配套 helper 递归处理共享壳嵌套层。
- 先封烘焙候选门、旧共享边与缺墙段，再按真实连接 `door side + lane` 保留唯一真实开口；正式 prefab 门槽使用正式通透门墙，门扇、门墙与碰撞成套表达。
- 沿真实地砖边界补外围实墙；L 形凹口、桥坑和护栏按真实可走面/阻挡边界保留，不按包围盒铺满，不加隐形空气墙。
- 移除碰撞净空内的 `safe_box_proxy` 烘焙半隔断/陈设；永久结构才算闭合，家具不作为闭合依据。
- 新墙标记 `camera_lower_wall`，流程幂等，重复装配不会继续增墙或改变已认领门槽。
- 新增 `tests/verification/probe_secret_branch_wall_gaps.gd/.tscn/.uid`，`verify_secret_branch_flow` 已接入 A31/A32；A12/A13 继续未实现。

### 根因与代码策略记录

根因定位在共享房壳装配收口：正式布局中的烘焙门墙、共享边和缺墙必须在壳体完成后统一识别，先封旧门/旧边，再按真实连接门槽替换正式通透门墙，最后沿真实地砖边界补外围实墙。该策略递归覆盖共享壳嵌套层，并复用正式墙/门墙 prefab 的实体碰撞；不得用包围盒围栏、隐藏大平面或透明/空气墙掩盖几何缺口。L 形凹口与桥坑不属于可走面，必须继续保持空缺；桥坑护栏属于真实阻挡边界，必须保留。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `probe_secret_branch_wall_gaps` 默认配置 | `ShellStorm2-work/sessions/2026-11-10_secret_branch_wall_closure`；`APPDATA` 与 `LOCALAPPDATA` 在进程启动前隔离至同一 session 下不同子目录 | `final_probe.log` exit 0；四房型 × 东单/西单/双门 = 12 样本，A31/A32 全通过；427 资源 UID 警告，0 `SCRIPT ERROR`/`ERROR` | `final_probe.log` |
| `SS2_FULL_LEVEL=1 probe_secret_branch_wall_gaps` | 同上；最终版探针关闭单房快捷路径并覆盖全关 | `final_full_level.log` exit 0；正式远征场景两条子图共 7 房，A31/A32 通过；1900 资源 UID 警告，0 `SCRIPT ERROR`/`ERROR` | `final_full_level.log` |
| `SS2_BREAK_WALL=1 probe_secret_branch_wall_gaps` | 同上；删除撤离房补墙后注入缺墙故障（不删除房间） | `negative.log` exit 1，符合预期；检出 15 条漏空，0 脚本错误/`ERROR` | `negative.log` |
| `verify_secret_branch_flow` full-flow | 同上 | `full_flow.log` exit 0，`SECRET_BRANCH_FLOW_OK`；两条子图共 7 房，含 2 撤离房；A31/A32 实跑，0 脚本错误/`ERROR`，1970 资源 UID 警告 | `full_flow.log` |
| 静态解耦检查 | 当前工作区 | `check_level_decoupling` exit 0，`violations=0` | 命令输出 |
| 运行时资产命名检查 | 当前工作区 | `check_asset_runtime_naming` exit 0，无新增命名债 | 命令输出 |
| `git diff --check` | 当前工作区 | exit 0；仅有 LF 行尾提示 | 命令输出 |
| `python3 scripts/check_documentation_contracts.py` | 当前工作区 | 最终 exit 1，11 条既有断链；支线设计自身 3 个 development 链已修复，本事务新增链接均可定位（并发工作区的总数会变化） | 命令输出 |

`final_probe.log` 与 `full_flow.log` 的资源 UID 警告不等于脚本错误；本事务没有将其写成零警告。真实渲染、手动游玩与 Android 均未执行，因此当前状态只能写为：**外围与门净空无头验收通过，表现待真机**。

## 遗留与状态更新

- 最终正式场景专项已通过；默认专项覆盖房型与门向组合，全流程另外覆盖传送、编成与存档往返。
- 文档契约检查仍受 11 条既有断链阻断，不宣称全局文档门禁通过。
- A12、A13 仍未实现，不因本轮外围封闭修订改变。
- 真实渲染、手动游玩与 Android 尚未执行，不宣称视觉验收。
- 不把整个 `WORLD-SECRET` 标记为完结；本记录只确认本轮外围封闭与真门净空的无头测试边界。
