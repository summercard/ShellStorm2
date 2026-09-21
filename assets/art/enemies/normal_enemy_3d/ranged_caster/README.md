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
