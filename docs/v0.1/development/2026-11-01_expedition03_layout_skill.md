# 11号远征03场景工坊布局Skill与流程安装

日期：2026-11-01；工程版本：0.1.0；FeatureID：TOOL-SCENE-EDITOR、WORLD-PLAN、ASSET-PIPELINE。

用户要求把当前远征03布局/陈设逻辑固化为带编号Skill和流程，并安装到Codex、WorkBuddy和项目。新增`11-expedition03-scene-workshop-layout`，显示名“11 远征03｜场景工坊布局与陈设”。[项目流程文档](../11_远征03场景工坊布局与陈设流程.md)维护流程，主设计仍拥有规则；Skill不替代远征01或00–04通用链路。

## 内容与安装

Skill包含SKILL.md、agents/openai.yaml、references/verification.md以及两个执行助手：

- check_room_scope.py：只读检查正式文件属于03运行房间目录且根metadata为03，记录SHA，不复制运行时资源键逻辑。
- prepare_isolated_project.py：工程外独立case、显式设置独立用户目录、每case唯一命名空间、生成OS用户路径与BaseManager实际存档路径guard；不启动游戏、不修改正式project.godot。资源链接不保证操作系统只读，写fixture须另选工程外路径。

Skill正本为用户WorkBuddy目录，另四处为镜像：

| 位置 | 用途 |
|---|---|
| `~/.workbuddy/skills/11-expedition03-scene-workshop-layout/` | WorkBuddy用户级正本 |
| `~/.codex/skills/11-expedition03-scene-workshop-layout/` | Codex用户级 |
| `.codex/skills/11-expedition03-scene-workshop-layout/` | 项目Codex |
| `.workbuddy/skills/11-expedition03-scene-workshop-layout/` | 项目WorkBuddy，当前工作区根就是仓库根 |
| `skills_drafts/11-expedition03-scene-workshop-layout/` | 项目镜像归档 |

仅安装此新目录，未全量覆盖其他Skill，未修改原00–04或远征01相关文件。五处各5文件，CRLF及SHA逐文件一致。新增项目检查入口`scripts/check_expedition03_layout_skill.py`，默认查项目三处，--installed另查用户两处；独立clone不依赖本机全局目录。

本轮不编辑房间、游戏逻辑或资产账本：只整理已批准的布局要求。固定数量/间距/墙边比例在流程中标为当前案例及偏好，不自动升级为所有房型生产配额。资料包括唯一TSCN、门墙/地砖所有权、墙边柜架与会客陈列、易碎受击/房间账、全合法门位净空、单位缩放/实际标高、原生画面、生命周期及哈希登记。

## 验证

| 检查 | 结果 |
|---|---|
| skill-creator quick_validate | 五个安装位置退出0；frontmatter、名称、包内引用与UI元数据有效 |
| Python脚本语法 | 两个Skill助手及镜像检查器通过；未向Skill包写入pycache |
| 范围正向 | 三份当前远征03正式文件通过，退出0 |
| 范围负向 | 实际远征01文件被拒绝，退出1（预期） |
| 隔离准备/引擎guard | headless/native两case独立UUID，准备退出0；实际Godot guard均退出0且无脚本ERROR，实际存档路径解析到工程外隔离数据目录 |
| 拒绝覆盖/路径穿越 | 已有case拒绝覆盖，恶意../标签拒绝，均退出1（预期）；旧case配置哈希保持不变 |
| 不影响远征01/正式配置 | 原project.godot字节不变，19份远征01目录TSCN哈希不变 |
| 镜像检查与负向自证 | 五处一致退出0；工程外三副本夹具故意修改一份SKILL.md后退出1（预期），未改正式安装 |

最终门禁：Skill验证/五处镜像检查/关卡解耦/git diff --check均退出0。文档检查退出1，仍为44项既有问题（43断链及1组3个未登记验证）；运行资产命名检查退出1，为既有bunny v022/v023/v024三处版本目录。本轮新增文档引用未报错，未修改这些历史问题。没有重跑房间游戏/破碎/通关验收；此次只改Skill、制作流程及安装检查器，不沿用旧结果声称新的游戏验收。安装后需要工具刷新Skill列表或新会话才能重新发现，未重启用户应用。

验证产物在工程外ShellStorm2-work/sessions/2026-11-01_expedition03_layout_skill/。修改前项目文档备份在ShellStorm2-backup/2026-11-01_expedition03_layout_skill/before_edits/。临时PyYAML依赖也在工程外；未安装到系统Python。未提交或推送。
