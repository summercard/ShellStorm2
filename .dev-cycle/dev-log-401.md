# 轮次 401（2026-05-30 15:29 UTC+8）

## 维度选择
**撤离战利品面板集成审查 — BaseMenu 战利品存入/丢弃完整链路确认**

## 审查背景
从核心玩法"搜打撤 + 基地系统交接"审查撤离战利品完整链路：

1. **BaseData.gd**：`extraction_loot: Array = []` 字段 + `_to_dict()`/`from_dict()` 序列化
2. **BaseManager.gd**：完整API — `get_extraction_loot()`/`add_extraction_loot()`/`add_extraction_loot_items()`/`get_extraction_loot_count()`/`deposit_extraction_loot_item()`/`deposit_all_extraction_loot()`/`discard_extraction_loot_item()`/`clear_extraction_loot()`
3. **RoomGameMode.gd**：撤离成功时 `bm.add_extraction_loot_items(all_items)` 将所有战利品注入提取流程
4. **BaseMenu.gd**：返回大厅时自动检测战利品 → 弹出面板 → 支持一键存入/逐个存入/全部丢弃/逐个丢弃

## 审查结论

### 撤离战利品链路完整 ✅

```
撤离成功 → RoomGameMode.add_extraction_loot_items() → BaseData.extraction_loot[]
     ↓
返回大厅 → BaseMenu._check_and_show_extraction_loot() → ExtractionLootPanel
     ↓
玩家操作 → 一键存入 / 逐个存入 / 全部丢弃 / 逐个丢弃 → BaseManager相应API
```

### BaseMenu 面板功能
- **一键存入仓库**：调用 `deposit_all_extraction_loot()`，逐个调用 `add_vault_item()`，溢出时统计 `overflow_count`
- **全部丢弃**：调用 `clear_extraction_loot()`
- **逐个存入**：调用 `deposit_extraction_loot_item(index)`
- **逐个丢弃**：调用 `discard_extraction_loot_item(index)`
- **物品颜色编码**：FateCard=紫色边框 / Weapon=金色边框 / Bullet=蓝色边框 / 其他=灰色边框
- **遮罩 + 居中面板**：自动弹出，无需手动触发

### 代码健康度 ✅
| 改动 | 状态 |
|---|---|
| BaseManager extraction_loot API | ✅ 完整 |
| BaseData 序列化 | ✅ extraction_loot 已录入 |
| RoomGameMode 撤离注入 | ✅ 已连接 |
| BaseMenu 战利品面板 | ✅ 功能完整 |
| Godot headless 编译 | ✅ EXIT 0 |

## 代码改动摘要
本轮无新增功能性代码改动（所有 extraction_loot 链路已在轮次398-400期间落地）

## 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [x] extraction_loot 完整链路代码审查通过 ✅
- [ ] 人类试玩：撤离成功后返回大厅，战利品面板是否正确弹出
- [ ] 人类试玩：存入/丢弃操作是否正确影响 BaseData 和 BaseManager 状态

## 系统完整度确认
所有系统均已落地且编译通过：

| 系统 | 状态 |
|---|---|
| 搜打撤全链路 | ✅ |
| 命卡21×21 apply | ✅ |
| 精英成长档案池 | ✅ |
| Boss框架 | ✅ |
| 武器装配树 | ✅ |
| Room视觉化 | ✅ |
| 换弹爆炸特效 | ✅ |
| 元素DOT视觉 | ✅ |
| 保险柜 | ✅ |
| 7房间Demo链 | ✅ |
| 楼层难度递增 | ✅ |
| 精英装备挂载 | ✅ |
| FateCard子弹视觉标签传播 | ✅ |
| **撤离战利品面板** | ✅（本轮确认） |
| Godot 4.6 编译 | ✅ EXIT 0 |

## 剩余风险（全部为人类试玩验证项）
1. **元素子弹**：冰霜DOT/火焰DOT/剧毒DOT + 冰冻视觉是否可区分
2. **换弹爆炸**：GPUParticles2D 是否真正触发
3. **第二关怪物强度**：HP +40%，Damage +20% 是否可感知
4. **精英怪主动技能**：冲锋/护盾反射/召集令是否可观察到
5. **精英偷枪视觉**：金色🔫标记是否出现
6. **BOSS房Boss激活**：进入Boss房HP条是否出现
7. **武器视觉标签**：挂载子弹带来的眼睛/腿/缩放是否在装备界面正确显示
8. **撤离战利品面板**：撤离后返回大厅面板是否弹出，存入/丢弃是否正常

## 续排判断
**继续排 cron** — 状态维持 `running`。

### 续排条件检查
- ✅ 状态 running
- ✅ 无设计分叉
- ✅ 无外部依赖
- ✅ 无破坏性风险
- ✅ 用户未要求停止

→ 创建下一轮 isolated cron

### 备注
所有系统级代码已完成。剩余全部为人类试玩验证项，不再有自动化可发现的设计缺陷。循环收敛至唯一终点：**等待人类试玩验证**。