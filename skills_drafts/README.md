# ShellStorm2 工程 Skill 存放目录

本目录用于在 **ShellStorm2 游戏工程内** 集中存放、维护与版本化项目相关的 Codex Skill。

这里的 Skill 是项目工作规范：它们定义模型制作、资产导入、角色换装等任务的适用范围、目录约定、验收要求和交付标准，供项目开发与资产生产时查阅和复用。

## 使用约定

- 新增或修改项目规范时，优先维护本目录中的对应 Skill。
- 每个 Skill 使用独立子目录，并以 `SKILL.md` 作为入口文档；可附带 `references/`、`scripts/` 与 `agents/` 等支持文件。
- `player-avatar-asset-standard` 当前为草稿规范；其余已同步的 Skill 以 `.codex/skills/` 中对应版本为基准。
- 此目录服务于工程资料管理，不等同于 Codex 自动加载目录。需要让 Codex 在会话中可用时，应将相应 Skill 安装或同步到项目的 `.codex/skills/`。
- 修改 Skill 前应确认影响范围；修改后应同步相关副本，避免工程内规范出现版本分叉。

## 当前内容

- `blender-game-prop-standard`：场景、关卡组件与固定设施的 Blender 制作规范。
- `godot-model-asset-import-standard`：场景、关卡组件与固定设施的 Godot 导入规范。
- `game-character-model-pipeline`：角色建模、动画、导出与 Godot 集成规范。
- `game-prop-model-pipeline`：可拾取或可移动普通道具的资产流程规范。
- `game-weapon-model-pipeline`：枪械与近战武器的资产流程规范。
- `player-avatar-asset-standard`：ShellStorm2 玩家角色与换装配件规范（草稿）。

## Skill 同步规则

- 同一 Skill 的项目生效副本为 `.codex/skills/<skill-name>/`。
- 工程版本化副本为 `skills_drafts/<skill-name>/`。
- 修改用户级 Skill 后，必须将对应 Skill 文件同步到上述项目内两个目录。
- 修改项目内 Skill 后，也必须同步两个项目副本；如项目规则面向所有 ShellStorm2 会话，还应同步用户级 Skill。
- 同步范围包括 `SKILL.md` 及其 `references/`、`scripts/`、`agents/` 支持文件。
- 完成后必须校验副本内容或 SHA-256 一致，禁止只更新其中一份。
