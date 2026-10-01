# Bunny01 默认电子面饰

- FeatureID：ENTRY-AVATAR、ASSET-PIPELINE；工程版本：0.1.0；日期：2026-10-01。
- 用户范围：原头部不改变，复制前侧脸部曲面、略微前移，制作黑色面具与参考图中两列蓝色方块眼睛；归类为角色配件，默认佩戴且可替换。
- AssetID：`CHR-PLY-BUNNY01-FACE-ELECTRONIC-MASK`；组件版本：v001；角色及动作仍使用既有版本。

## 制作与接入

从当前 `production/v021/source/model/chr_bunny01_model_v021.blend` 复制并连通提取前侧面，保留原曲面1448个顶点，沿前向+Y平移9mm，加4mm壳体厚度。两组4×14网格方块共112个，独立方块合并为单个眼睛网格，保留每颗之间的间距。黑色亮面材质与蓝色发光材质只属于新配件。模型源保留原11个网格、UV、材质、变换、权重及共享骨架；原角色和动作Blend字节哈希不变。

Blender集合为 `01_部件/眼镜/眼镜__electronic_mask`，与兔耳的“部件/样式”层级一致。正式源、纯视觉GLB、独立PackedScene归档到 [电子面具组件目录](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/README.md)。GLB仅含壳体/方块两个网格；没有新骨架、动作和碰撞。静态增量包在 [中转记录](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/character_transfer_ledger.json)显式登记既有模型与动作依赖，分类 `child_variant`。

复用 `glasses` 稳定槽与原换装入口、目录和BaseData总档；衣柜显示“面饰”。`PlayerAvatar3D`创建独立 `HeadJoint/FaceAccessorySocket`，直接实例化稳定Prefab并继承头部动作。默认款变为电子面具；合法旧存档（含 `none`）保留选择；缺失/非法ID回退默认。女仆头按既有规则隐藏面饰，不丢失选择。没有修改玩家碰撞、武器、状态机或原模型/动画包。

## 验收

- Blender独立重新打开源文件，原11个网格的几何/UV/材质/变换/权重逐项匹配，模型与动作静止骨架签名相同，1448个面具顶点均来自原头部；112个方块及集合、所有记录哈希通过。
- `asset_guard.py` 分类 `child_variant` 通过。
- `verify_electronic_mask_flow`：无头装配/换装/保存读档通过；Forward+真实渲染56项通过，蓝光眼睛11032像素可见。旧头部可见、默认兔耳可见，面饰独立替换/卸下、切头隐藏/恢复、重复选择不增生节点；既有四种头部动画下保持挂点对齐；碰撞及武器挂点不变。
- 回归：`verify_player3d_avatar_bounds`、`verify_player3d_animation_flow`、`verify_wardrobe_preview_fill_flow`、`verify_avatar_return_persistence_flow`、`verify_character_authoring_bundle`，各退出0。原角色边界专项显式卸下面饰后核对原十个网格，面具使用独立专项。
- 角色账本《资产主表》第22行、《角色组件》第44行、《3D-角色》第9行登记，分别执行主资产行与专表事务；既有987个资产指纹保留，查重/统计公式扩展，专表基线只更新本次新增内容。结构与分账本无损门禁通过。
- 角色全量哈希门禁仍报告既有女仆头第21行哈希不符；写前/写后该行内容及原Prefab均未改变。本次新增面具行没有路径或哈希问题。运行资产命名门禁仍报告工作区其他带版本资产/引用的欠账，面具两个稳定运行路径无版本号；不扩大接受历史欠账。
- 全局文档门禁已执行，退出1：仅报告既有三个未注册场景 `verify_base99_swivel_chairs`、`verify_expedition01_spawn_ramp`、`verify_pushable_base_chairs`；本次面具专项已注册，新增文档链接、功能追溯和媒体域检查通过。Windows `python3`默认落在不含openpyxl的3.14解释器，最终检查通过临时PYTHONPATH读取已配置运行依赖，未安装包或修改全局环境。
- 最终无头面具专项55项通过，真实Forward+专项56项通过，各日志经 `check_verification_log.py` 检查无非预期脚本错误；工程资源导入存在既有色盘UID回退警告。`git diff --check` 对本次修改通过。

## 预览和限制

[Blender正面](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/front.png)、[三分之四](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/three_quarter.png)、[面部近景](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/face_closeup.png)；[Godot正面](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_front.png)、[Godot近景](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_face_closeup.png)。真实截图为隔离存档、无手持武器的专项舞台；不代表主场景灯光完全相同。未执行整游戏full套件和目标移动设备性能测试。没有提交或推送。
