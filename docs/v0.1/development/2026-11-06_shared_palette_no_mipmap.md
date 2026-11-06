# 公共场景色盘恢复无损、无 Mipmap

日期：2026-11-06。工程：0.1.0。FeatureID：ASSET-PIPELINE。来源：用户反馈游戏贴图出现网格，明确禁止 Mipmap。主契约：[资产与内容规范](../10_资产与内容规范.md#公共色盘无-mipmap-硬约束)。

## 诊断与责任边界

检查时公共色盘 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` 为 `compress/mode=2`、`mipmaps/generate=true`、`process/size_limit=0`，违反无损、无 Mipmap 的原有规范。公共场景色盘被多处模型共用，风险不限于门。

Git 提交 `3bb2a7c7`（2026-10-31）的该文件及检查时 HEAD 都已有上述配置；不是2026-11-05 Boss门制作脚本直接设置。该脚本使用 Blender Closest 采样、不写公共PNG或其导入参数；通用门导入后处理仍设置 `TEXTURE_FILTER_NEAREST`。上轮门组件交付漏跑共享色盘专项，未发现已经存在的导入契约违例，原“资产验收完成”不能代表色盘专项通过。

Mipmap和VRAM块压缩均可造成色盘采样串色、块状网格或条纹，但本轮未获取用户问题画面的同机位前后对照，不将全部可见网格都归因于单一因素。

## 最小修改

- 公共 `.png.import`：`compress/mode=0`、`mipmaps/generate=false`、`detect_3d/compress_to=0`；尺寸上限512，与原图512×512相同，不改变图像尺寸。
- 正式重新导入后由Godot生成单一无损 `.ctex`，`metadata.vram_texture=false`。
- `scripts/check_runtime_texture_policy.py`：原有无损/无Mipmap检查追加禁用3D自动转换判据。
- `tests/verification/verify_scene_facility_shared_palette.gd`：追加实际导入Image无Mipmap、无块压缩检查；材质禁止重复采样；纳入远征03普通门和Boss门的稳定GLB。
- 资产规范写明导入参数与实际缓存必须同时验证；开发索引和变更入口同步。

公共PNG、UID、GLB、材质后处理脚本、Prefab、正式房间摆位、账本资产ID/哈希及玩法均未修改。不批量改动其他普通纹理的Mipmap策略，不重生成正式房间。

## 验收与隔离

正式导入使用与当前编辑器一致的Godot 4.7.2，独立APPDATA；资源专项使用工程外最小项目，无Autoload，读取正式资产与实际 `.godot/imported` 缓存，不启动游戏、不读写正式存档。

| 检查 | 退出码 | 结果 |
|---|---:|---|
| Godot正式导入 | 0 | 公共色盘 `.ctex` 与导入映射已更新，日志0 SCRIPT ERROR/ERROR |
| 实际资源Image | 0 | 512×512，`has_mipmaps=false`、`is_compressed=false`；运行Image与原PNG像素字节完全相同 |
| 共享色盘材质专项 | 0 | 118个GLB、915个材质；包括普通门和Boss门，共享纹理、最近邻无Mipmap及不重复采样通过；0 SCRIPT ERROR/ERROR |
| 反向故障注入 | 0 | 三个错误导入参数分别被拒，实际含Mipmap的ImageTexture缓存被拒，共4项；只在隔离夹具注入 |
| 全工程纹理策略 | 1 | 同一当前缓存下以改前配置作对照：问题10→6，新增0；公共色盘契约问题清零 |
| 文档合同 | 1 | 15处历史破链；子检查调用的python3环境缺openpyxl。无本次新增文件的破链 |
| 指定文件git diff --check | 0 | 无空白错误 |

全工程纹理门禁剩余6项：NPC色盘尺寸限制1项、收租人GLB内嵌图片3项、启动图尺寸限制及1920×1080超预算2项。与改前配置对照全部存在，不为全绿改动它们。第一次与正在导入并行的扫描记录了7项；正式导入后重新对照为6项，以后者为准。

既有公共色盘旧UID回退WARNING仍在（历史契约登记 `uid://c8tfkc8nrnge7`，检查时公共导入UID已为 `uid://dujor0htha6rn`）；本轮保持当前UID，不扩展到全模型UID迁移。这些警告不是Mipmap开启的证据。

原PNG SHA-256修改前后均为 `a6b1838fb80ad3ce7764e998bb1dfb70edf2b9315a4282da0fb2ae35ed266ce3`。配置保留当前UID `uid://dujor0htha6rn`。

## 产物与未执行项

过程证据：工程外 `ShellStorm2-work/sessions/2026-11-06_palette_no_mipmap/`，含 `runtime_report.json`、`material_validation.log`、`formal_import.log`、`texture_policy_before.json` / `texture_policy_after.json` 及隔离夹具。

备份：工程外 `ShellStorm2-backup/2026-11-06_palette_no_mipmap/before_edits/`。不覆盖并发会话的门模型、房间与其他资产变更。

未执行：正式运行中游戏进程的热刷新、用户问题画面的同机位渲染对比、整关回归。当前已经打开的游戏可能持有旧纹理，应停止该次运行后重启游戏，再核对画面；若仍有网格，需区分模型共面闪面、阴影或其他贴图问题，不宣称本轮已消除所有视觉瑕疵。
