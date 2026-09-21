# 远程怪 ranged_caster 换模型 —— 警察僵尸重定向 v005（绑定 + 动作 + 尺寸）

日期：2026-09-21 14:01　事务 slug：`ranged_caster_v005_retarget`

## 本轮目标（用户明确三条）
1. 丢掉之前全部 v001~v004 模型源（用户："这个我把骨骼绑错了…blender 的源文件不要了"）。
2. 用 `警察僵尸.zip` 的 FBX 重做：**不改绑定、不改蒙皮**，仅对照小僵尸骨骼做**重定向**。
3. 让新骨架**能播放小僵尸动作**；**整体尺寸一起校准**。

## 交付物
| 文件 | 状态 |
| --- | --- |
| `assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend` | ✅ 模型源 |
| `assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend` | ✅ 动作源（10 段） |
| `_scratch/security_zombie/retarget_preview/` | 46 张预览（斜视 + 正面） |
| `_scratch/security_zombie/bound_preview_v005/bone_overlay_{front,side}.png` | 骨骼叠加（正面/侧面） |

骨骼叠加肉眼确认：脊柱沿体轴、肩臂沿手臂延伸、腿链穿大腿到脚、脚骨指向 +Y（正面）；正面渲染是完整正脸 ⇒ 朝向契约成立。

模型源实测：66 骨，小僵尸契约 36 骨**全命中**（`contract_missing=[]`），顶点组 50，未绑定顶点 0，权重和异常 0，
**高 1.857143 m（源高契约）**、脚底 z=0、居中、正面 Blender **+Y**，`skeleton_id=SKEL-MELEE-FUNGBOAR01-002`。

## 关键结论
- **保持原绑定**的正确含义：只做「骨名 1:1 改名 + 顶点组同名跟随 + 朝向/缩放是对骨与网格施加同一个变换」，
  不重算骨架数据、不重新分权重。⇒ 蒙皮关系按定义不变。
- 原始警察 FBX 自带 **15 根骨无顶点组**（所有 `*4` 指尖骨、`Toe_End`、`HeadTop_End`），
  其中包含契约骨 `L_Middle2` / `R_Pinky2`（左右不对称，原始就如此）。这是**源数据特性，非本次引入**，
  改名后 1:1 沿用。⇒ 审计出现「契约骨无权重组」不算缺陷，但要能说出原因。
- 重定向实现 = 改名 + 朝向校正(-Y→+Y) + uniform 缩放 + 补 `Root` 骨（父级为 Hip，head 原点、tail +0.12、roll π）。
  非契约的 30 根骨（Spine01、各 `*3/*4` 指骨、ToeBase/Toe_End、HeadTop_End、Ring 链）走 `EXTRA_MAP` 保留原名式命名，
  **不与契约名混淆**。

## 两个必须记住的坑

### 1. 重定向公式（方向别写反）
```
M_t = M_s @ R_s⁻¹ @ R_t          # R = matrix_local.to_3x3()（静止旋转）
```
- 先**解出源姿态相对源静止的局部旋转**，再乘**目标静止旋转**。
- 错误写法 `R_t @ R_s⁻¹ @ M_s` 会系统性产生 80~141° 偏差（曾据此误判"重定向失败"）。
- `_scratch/security_zombie/debug_retarget_formula.py` 单帧对照可判方向：正解 `ideal_vs_src` 降到 2.5~27°。

### 2. Hip 位移必须显式搬运（曾静默丢全身位移）
- 小僵尸动作**只有 `Hip` 带 location 通道**（`Root` 无动画），全身位移都在 Hip 上。
- 新骨架里 **Hip 的父骨是 Root（非 None）**，若把位移搬运写在 `parent is None` 分支里 ⇒ **永不执行**。
- 现象：`hip_path_err_m` **恰好等于** `melee_hip_travel_m`（目标位移恒 0）——走路起伏、倒地后滑全丢。
- 判据就是这个等式；出现即命中本坑。

## 验证判据（换掉不适用的旧判据）
- ❌ **骨指向轴（bone Y 方向角）不适用**：两套骨架静止 roll 不同（多数骨 x/z 轴差 ~90°），
  轴指向必然有差，26.9° 属正常静止差，不是重定向误差。
- ✅ **世界旋转增量 Δ = M_pose · R_rest⁻¹ 逐帧比对**：本流程"保持原绑定+只重定向旋转"⇒ Δ_t ≡ Δ_s。
  实测 10 段全部 **0.0000°**；髋部位移误差也 **0.0000 m**。
  脚本：`_scratch/security_zombie/verify_retarget_v005.py` → `delta_compare_v005.json`。
- ✅ **自运动幅度确认非冻结帧**（`check_motion_range.py` → `motion_range.json`）：
  v005 与 v003 逐值一致，v003 的 6 段基础动作与小僵尸逐值一致；`shoot` step=4.17°/range=10.3°（有内容）。
- ✅ **局部性探针**（`audit_v005_full.py`）：旋转单骨，被移动顶点必须落在该骨主导组内（证明"动对了地方"，
  而非只证明"会动"）。L_Hand/R_Hand/Head/L_Foot/R_Thigh 全过。

## 为什么必须重定向、不能直接套用小僵尸动作（实测）

关键：**动作通道是相对该骨自身"静止坐标系"表达的**，不是绝对世界旋转。
骨名改成一样只保证通道**能绑定上**（能播、不报错），不保证**播对**——这正是最危险的地方。

两套骨架实测：骨名相同、骨骼指向 Y 轴差 2~27°（接近），但**本地 X/Z 轴差 85~141°**
（`rest_axis_compare.json`；L_Upperarm 的 x/z 各差 90°）⇒ 静止 roll 不同。

直接把 melee 动作赋给 v005 骨架实测（`direct_reuse_test.py`、`direct_vs_retarget.py`）：

| 骨 | 直接套用 Δ 偏差 | 重定向后 |
| --- | --- | --- |
| R_Hand | **184.66°** | 0.00° |
| L_Forearm / L_Hand | 144.05° / 143.57° | 0.00° |
| L_Upperarm | 104.35° | 0.00° |
| R_Upperarm / R_Forearm | 76.99° / 183.54° | 0.00° |
| L_Thigh / L_Calf / L_Foot | 38.73° / 36.49° / 30.20° | 0.00° |
| Spine02 / Neck / Head | 19.27° / 13.64° / 10.14° | 0.00° |

末端位置偏差（同一套骨架、同一帧，两版相减）：**头 0.9586 m、右手 0.9095 m、
左脚 0.5467 m、右脚 0.5421 m、左手 0.4254 m**（角色总高仅 1.857 m）⇒ 完全不可用。

⇒ 所以不是"多余的一步"，而是**保绑定不动**这个前提的必然代价：
- 路径 A（套小僵尸自己的骨架）：动作可直接复用，但要**重做绑定与权重**。
- 路径 B（保留原 FBX 绑定 + 重定向）：绑定/蒙皮一字未改，代价是动作要做一次换算。

本任务用户明确要求"不改绑定和蒙皮" ⇒ 只能走 B。

## 脚本清单（`_scratch/security_zombie/`）
| 脚本 | 作用 |
| --- | --- |
| `build_police_model_v005.py` | 模型重定向（改动→数据、朝向、缩放、补 Root、改名、包贴图） |
| `retarget_anim_v005.py` | 动作重定向（两道门禁 + 正确公式 + Hip 位移搬运） |
| `verify_retarget_v005.py` | Δ 一致性 + 髋位移端到端验证 |
| `audit_v005_full.py` | 骨骼命名 / 局部性 / 尺寸 / 持枪差异 综合审计 |
| `check_motion_range.py` | 逐剪辑自运动幅度（防冻结帧） |
| `direct_reuse_test.py` / `direct_vs_retarget.py` | 直接套用 vs 重定向的偏差实测（回答"为什么不直接套用"） |
| `render_preview_v005.py` / `render_front_armed.py` | 预览渲染 |


## 尚未做（用户"其它后面再说"）
导出 GLB → `components/enm_ranged_sporeshooter01_visual_top3d.glb`；
更新 `runtime/character_transfer_ledger.json`、`runtime/enm_ranged_sporeshooter01_root_top3d.tscn`、
敌人账本 `ShellStorm2_敌人账本_v001.xlsx`；跑 Godot 专项验收 `verify_security_zombie_presentation` 与 registry 门禁。
