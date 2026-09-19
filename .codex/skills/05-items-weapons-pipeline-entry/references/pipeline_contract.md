# 道具与武器链路总契约

本文件是 `05-items-weapons-pipeline-entry` 的字段口径。所有下游 Skill 读这里，不各自解释一遍。

## 1. 归属判定

| 判定 | 依据 | 结果 |
|---|---|---|
| 属于道具域还是武器域 | 账本《资产主表》**「大类」列** | 决定读哪本分账本 |
| 走道具分支还是枪械分支 | 同上「大类」列，配合「子类」列 | 决定锚点、材质上限与源目录 |
| 属于哪本分账本 | `assets/registry/ledger_index.json` 的 `domain_for_category()` | 不写死文件名 |

前缀**不能**用来判归属：`PRP` 同时服务场景域与道具域，`ART` / `ENV` 同属场景域。
歧义前缀上用 `domain_for_asset_id()` 会返回 `None`，此时必须改用 `domain_for_category()`。

```python
from ledger_registry import LedgerIndex     # scripts/ledger_registry.py
index = LedgerIndex.load(project_root)
index.path_for_category("道具")               # -> 道具分账本路径
index.domain_for_category("道具")             # -> Domain(key='props', ...)
index.domain_for_sheet("3D-道具")             # -> Domain(key='props', ...)
index.path_for_asset_id("WPN-...")            # -> 武器分账本路径
index.rewrite_ref("<旧引用>")                  # 旧 master#分页 -> 分账本#分页（幂等）
```

分页归属：`3D-道具` / `3D-物品` → 道具账本；`3D-武器` → 武器账本。
一个 Prefab 只能出现在一个分类分页中。

## 2. 账本取数字段

### 2.1 《资产主表》（身份、状态、版本）

| 列 | 字段 | 用途 |
|---|---|---|
| A | AssetID | 唯一身份，版本升级不变 |
| B | 中文名 | 显示名与 Blender 根集合中文段 |
| C | 大类 | 归属判定与分账本路由 |
| D | 子类 | 分支与动画档位判定的主要依据 |
| E | 逻辑ID/源键 | 内容ID，08 阶段做代码映射 |
| F | 组件槽 | `root` / `root_3d`，决定输出根形态 |
| I | 状态/动画 | 动画档位留痕位置 |
| J | 复用范围 | 功能边界，写进 `asset_contract.json` |
| K | 制作状态 | 开工前必须确认当前状态 |
| M | 版本 | 本次产出的源版本 |
| X | 源编号（Blender collection） | 根集合名挂钩 |
| Y | 备注 | 临时复用、外部所有者、替换限制 |

### 2.2 3D 分页（尺寸、功能、碰撞、路径）

| 列 | 字段 | 用途 |
|---|---|---|
| AssetID | 与主表关联 | 关联键 |
| Prefab路径 | 稳定 `.tscn` | 07 阶段的产出位置 |
| GLB模型路径 | 视觉 GLB | 07 阶段 |
| Blender源文件 | 可维护 `.blend` | 06 阶段 |
| 功能说明 | 一句话功能；纯表现写「仅表现」 | 冻结进契约 |
| 功能脚本路径 | 外部 `.gd` 或空 | 08 阶段 |
| 碰撞开关 | `开` / `关` / `无` | 冻结进契约 |
| 碰撞归属 | `Prefab自身` / `外部脚本` / `混合` / `无` | 07 阶段 |
| 碰撞方式 | `BoxShape3D` / `CapsuleShape3D` / `手工Shape` / `模型生成` / `无` | 07 阶段 |
| **标准尺寸** | **米制尺寸，写 `宽×深×高m`** | 06 阶段的尺寸真值 |
| **原点与朝向** | 原点位置 + local 正面方向 | 06 阶段 |
| 使用位置 | 关卡、系统或复用范围 | 文档同步 |

### 2.3 尺寸与功能的解析规则

- 尺寸只从「标准尺寸」列取。写成结构化 `宽×深×高m`，例如 `0.42×0.28×0.30m`。
- 尺寸列缺失、或仍是「未声明」「PackedScene/类型与尺寸配置」这类自由文本时：
  **先补账本再开工**。补账本属于登记动作，不得顺手改资产。
- 功能从「功能说明」列 + 主表「复用范围」列合并理解：前者说这件东西是什么，后者说它出现在哪。
- 碰撞三列描述的是**运行时意图**，不是 Blender 里要不要建碰撞。Blender 侧不建碰撞。

## 3. 资产契约冻结字段

产出 `asset_contract.json`，结构见 `assets/asset_contract_template.json`。必填：

| 字段 | 来源 | 缺失后果 |
|---|---|---|
| `asset_id` | 主表 A 列 | 停止 |
| `display_name_zh` | 主表 B 列 | 停止 |
| `category` / `subclass` | 主表 C / D 列 | 停止 |
| `domain_ledger` | `ledger_index.json` 解析 | 停止 |
| `logical_id` | 主表 E 列 | 停止（08 阶段无法映射代码） |
| `dimensions_m` | 3D 分页「标准尺寸」 | 停止 |
| `origin_and_facing` | 3D 分页「原点与朝向」 | 停止 |
| `collision_intent` | 3D 分页碰撞三列 | 停止 |
| `function_note` | 3D 分页「功能说明」 | 停止 |
| `animation_tier` | 由 `subclass` 判定 | 停止 |
| `source_collection` | 主表 X 列 | 停止 |
| `anchor_contract` | 由分支决定 | 停止 |
| `material_roles` | 由分支决定 | 停止 |
| `source_dir` / `stable_glb` / `stable_prefab` | 由新根规范推导 | 停止 |

## 4. 动画档位判定细则

| 档位 | 典型子类 | 判定要点 |
|---|---|---|
| `tier_0_static` | `key`、`bullet_module`、`consumable`、`container`、纯装饰 | 没有任何独立可动结构 |
| `tier_1_articulated` | `gunbody`（有枪机/弹匣/扳机/折叠托）、有盖子或折页的容器、有按钮或屏幕开合的装置 | 存在至少一个自身可动件 |
| `tier_2_deform` | 需要形变或与角色动作联动的部位 | 需要蒙皮 |

- 判定不确定时取较低档，并在契约里写明理由；不放宽也不夸大。
- `gunbody` 默认 `tier_1_articulated`。近战武器无折叠/开合机构时取 `tier_0_static`，有折叠机构时取 `tier_1`。
- 档位写进账本《资产主表》I 列「状态/动画」。

## 5. 失败与回退

| 情况 | 处理 |
|---|---|
| 找不到 AssetID | 停止，报告查询过的账本与分页 |
| 资产在总目录里找 | 停止，说明总目录不含资产行，改查分账本 |
| 尺寸或功能缺失 | 停止，列出缺失列与当前值，要求先补账本 |
| 状态已是「正式可用」但要求「制作新版」 | 确认是替换还是新建变体，不直接覆盖 |
| 同一资产有多个候选条目 | 停止，列出候选 AssetID 请用户指定 |
| 用户要求改玩法/数值/掉落/存档 | 拒绝，指出应由对应规则流程负责 |
