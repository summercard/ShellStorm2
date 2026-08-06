# 弹壳风暴2

Godot 4.6 顶视角 3D 搜打撤肉鸽。当前项目版本为 `0.1.0`，正式入口是 `scenes/TowerDescent3D.tscn`。

## 开始开发

1. 使用 Godot 4.6.x 打开仓库根目录。
2. 运行项目进入塔楼主循环。
3. 修改前先阅读 [游戏设计文档 v0.1](docs/v0.1/README.md)；性能施工同时阅读 [性能优化与热管理](docs/v0.1/13_技术施工_性能优化与热管理.md)。
4. 提交前运行 `./scripts/run_verification_suite.sh smoke`；涉及关卡、角色、战斗或资产时运行对应专项或 `full`。

## 目录

| 路径 | 职责 |
|---|---|
| `scenes/` | 可运行场景、UI 页面和场景装配入口 |
| `src/framework/` | 跨系统稳定契约，不保存具体玩法状态 |
| `src/core/` | 全局基础设施、状态机、存储与音频 |
| `src/world3d/` | 当前 3D 关卡、房间、门、撤离和塔楼生成 |
| `src/player3d/` / `src/enemy3d/` | 当前 3D 角色与怪物运行时 |
| `src/game/` | 可复用玩法模块；其中部分 2D 类属于兼容层 |
| `assets/art/` | 可替换美术资产及其源文件 |
| `assets/registry/` | 美术资产唯一登记源 |
| `tests/verification/` | 自动回归场景 |
| `docs/v0.1/` | 当前唯一有效开发文档 |

`outputs/`、`.dev-cycle/` 和 `.codex-tmp/` 都是可丢弃工作产物，不进入版本控制。
