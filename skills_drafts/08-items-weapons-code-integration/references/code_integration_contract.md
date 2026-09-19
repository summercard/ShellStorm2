# 功能代码引用契约

本文件是 `08-items-weapons-code-integration` 的消费者清单、映射写法与台账回写口径。

## 1. 消费者检索

引用点必须读代码确认。先跑检索：

```bash
rg -n "assets/art/(props|weapons|items_weapons)" --glob '*.gd' src scenes
rg -n "GUN_VISUAL_SCENES|MELEE_VISUAL_SCENES|ItemModelFactory3D" --glob '*.gd' src
```

当前已知消费者：

| 消费者 | 路径 | 拥有什么 |
|---|---|---|
| 道具模型工厂 | `src/world3d/ItemModelFactory3D.gd` | 世界拾取、背包图标、贩卖机卡共用的道具外观；`create_model()` 按 `model_kind` 分支 |
| 枪械表现层 | `src/combat3d/WeaponModel3D.gd` | `GUN_VISUAL_SCENES`、`MELEE_VISUAL_SCENES`、`GUN_PROFILES`、`BULLET_COLORS` |
| 近战原型 | `src/combat3d/MeleeWeaponVisual3D.gd` | 三把近战的原型网格（`weapon_style` 枚举） |
| 玩家角色 | `src/player3d/Player3D.gd` | 手持与背负表现装配 |
| 训练场 | `src/training3d/TrainingRack3D.gd` | 训练架展示 |

**不得新增第二套并行映射表**。已有常量表就改已有那张；需要新表时先确认是否真的没有既有入口。

## 2. 映射写法

```gdscript
const GUN_VISUAL_SCENES := {
	"bp_pistol": preload("res://assets/art/items_weapons/weapons/pea_pistol/runtime/wpn_pea_pistol_root_top3d.tscn"),
	"bp_rifle": preload("res://assets/art/items_weapons/weapons/broom_rifle/runtime/wpn_broom_rifle_root_top3d.tscn"),
}
```

- 用 `const` + `preload` 常量表，不散落 `load("res://...")` 字符串。
- 路径不含版本号。替换资产时这一行不改。
- 一个内容ID映射一个稳定路径；多个内容ID可复用同一路径，但复用的是路径，不是复制文件。
- 尚未接入的内容ID保持占位来源，并在表内以注释标明「未接入」，不指向不存在的路径。
- 映射键必须能对上账本《资产主表》E 列「逻辑ID/源键」。

## 3. 同一实例快照规则

- 同一武器实例的**手持、地面、背包图标、商店预览、表现页**必须从同一 `WeaponInstance` 快照重建同一模型；
  不同 LOD 场景不能各自指向不同外观来源。
- 世界掉落物与背包图标共享同一内容ID。
- 禁止为近战或某件道具另做「只在测试场可见」的旁路模型。

## 4. 跨文件断言

链接三元组：**内容ID ↔ 稳定路径 ↔ 文件存在性**。

- 三者不一致必须显式失败，不能静默跳过、不能回退到旧模型。
- 断言要有会失败的具体判据（例如：遍历映射表，任一 `resource_path` 的不存在则 `push_error` 并计失败）。
- 新增或替换资产后，这条断言是唯一能自动发现断链的地方，不得省略。

## 5. 已知缺口（引用时必须核对，不要当成已完成）

| 缺口 | 现状 | 影响 |
|---|---|---|
| 可拾取道具无真实 3D 资产 | `ItemModelFactory3D` 用程序网格生成外观 | 接入正式道具时，需把 `create_model()` 对应分支改为优先取稳定 PackedScene，程序网格退为占位回退 |
| 地面与背包使用通用套件 | `ItemModelFactory3D.WEAPON_SCENE` 与 `Player3D` 两处指向 `weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn` | 与「同一实例快照重建同一模型」存在张力，接入前先确认设计意图 |
| 三把近战是程序原型 | `melee_3d/` 只有 tscn，无 `source/`、`components/` | 正式美术替换后应移除 `MeleeWeaponVisual3D` 的原型分支 |
| 18 把枪的 GLB 三版并存 | `components/<名>/` 有 v001 / v002 / v003，runtime 只引用 v001 | 属存量债务，替换时按稳定路径覆盖，不新增版本 |

## 6. 验收命令

```bash
python scripts/check_asset_registry.py --ledger 道具
python scripts/check_asset_registry.py --ledger 武器
godot --headless --path "<项目目录>" res://tests/verification/verify_formal_3d_asset_import.tscn
godot --headless --path "<项目目录>" res://tests/verification/verify_formal_3d_asset_gallery_visual.tscn
godot --headless --path "<项目目录>" res://tests/verification/verify_player3d_weapon_grip_visual.tscn
godot --headless --path "<项目目录>" res://tests/verification/verify_formal_asset_placement_visual.tscn
```

判据：日志中的 `*_OK`、`VERIFICATION_SUITE_OK`、`FAILED_SCENE`；不迷信裸退出码。
`visual` / `renderer` 类验收不用 headless。验收图输出到 `outputs/verification/`。

## 7. 台账回写

《资产主表》：`制作状态`、`版本`、`文件路径`、`SHA-256`、`源编号（Blender collection）`、
`状态/动画`、`更新时间`。

3D 分页：`Prefab路径`、`GLB模型路径`、`Blender源文件`、`功能说明`、`功能脚本路径`、
`碰撞开关`、`碰撞归属`、`碰撞方式`、`标准尺寸`、`原点与朝向`、`使用位置`、`制作状态`、`版本`。

规则：

- 只写**所属域分账本**，路径经 `ledger_index.json` 解析，不写死文件名。
- 总目录只放索引，资产行不得写入总目录。
- 每个 AssetID 全库恰好出现一次，由 `check_asset_registry.py` 强制。
- 只有独立加载、正式引用、玩法通行与真实渲染全部通过，才把状态改为「正式可用」。

## 8. 报告格式

```text
已接入：<AssetID> / <内容ID>
稳定路径：<..._root_top3d.tscn>
代码引用：<文件:行>
验收：<命令> → <判据>
台账：<分账本> / <分页> 已更新
未执行：<项及原因>
```
