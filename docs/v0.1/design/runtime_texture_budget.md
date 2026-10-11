# 运行贴图尺寸与共享规则

FeatureID：ASSET-PIPELINE。来源：2026-10-11 用户要求删除重复内容，玩家贴图1024、怪物贴图512，全部运行贴图不超过1024。

玩家运行贴图最长边不超过1024，敌人域（普通怪、精英、Boss）不超过512，其余运行贴图不超过1024。保持长宽比，小图不放大。Godot导入参数`process/size_limit`同步设上限；Windows S3TC和Android ETC2导入产物均检查实际尺寸。

共享的依据是解码后的像素完全相同、尺寸预算相同、导入参数相同；或者Windows与Android两个平台的导入产物均逐字节完全相同。颜色贴图与法线贴图分开；法线缩图后重新归一化。不因名字相似合并不同画面。共享运行贴图在`assets/art/shared/textures/{player,enemies,general}/`，GLB引用外部图片，不再携带重复图片字节。模型、骨架、动作、运行PackedScene路径保持原有契约。

`.blend`制作母版及其外链图片仍为制作真源。替换前文件保存到工程上层`ShellStorm2-backup/2026-10-11_texture_optimization/before/`，逐文件校验备份。Blender使用的原路径色盘保留，并通过`.gdignore`从Godot运行环境隔离。

机器追溯在`assets/registry/runtime_texture_policy.json`，记录原图片到共享图片的映射、尺寸、来源和母版依赖。重新导出GLB后，若带回内嵌贴图，必须重新外置、共享并导入；不得删除仍被运行模型引用的文件。

验证入口：`python scripts/check_runtime_texture_policy.py`。检查导入上限、两种压缩产物尺寸、GLB外部图片路径及内嵌图片回归。该检查不能代替原生Godot模型加载和实际PCK验收。
