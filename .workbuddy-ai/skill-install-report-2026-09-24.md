# 项目 Skill 安装报告

- 日期：2026-09-24
- 来源：`/Users/summercards/ShellStorm2/.codex/skills/`
- 目标：`/Users/summercards/.workbuddy-ai/skills/`
- 结果：**38 / 38 安装成功**，共 104 个文件，逐文件 sha256 与源一致

## 一、为什么选 `.codex/skills` 作为来源

项目内有三处 skill 副本，实际内容并不一致：

| 副本 | 数量 | 状态 |
|---|---|---|
| `skills_drafts/` | 35 | **落后** |
| `.codex/skills/` | 38 | **最新最全（本次来源）** |
| `~/.workbuddy/skills/` | 8 | 旧目录，mtime 2026-09-16，属遗留 |

两处差异：

1. `.codex/skills` 多出 3 个 skill：`audio-sfx-asset-pipeline`、`music-asset-pipeline`、`ui-asset-pipeline`。
2. 两个同名 skill 内容落后：
   - `xlsx-git-conflict-resolution/SKILL.md`：`skills_drafts` 仍写「总目录 + 7 个分账本」，`.codex/skills` 已是 2026-09-23 的「9 个独立域（UI/音效/音乐已从表现资源账本拆出）」。
   - `godot-model-asset-import-standard/SKILL.md`：分账本路由表同样停留在 7 账本旧版。

## 二、安装前结构校验

38 个 skill 全部通过：

- 每个目录均含 `SKILL.md`
- 均有 YAML frontmatter，且目录名与 `name:` 字段完全一致
- 均有 `description` 字段

## 三、安全审计

审计方式：`skill-security-audit` 静态扫描器（60+ 恶意特征模式）逐 skill 扫描 + 人工复核 SKILL.md 语义、脚本网络行为与文件访问。

**总体评级：SAFE（可安装）**

| 级别 | 原始命中 | 复核结论 |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 7 | **全部误报** |
| MEDIUM | 138 | **137 为误报**，1 为无害 |
| LOW | 39 | 均为内部 URL / 说明性文本 |

### HIGH 逐条复核（全部误报）

| 文件:行 | 命中模式 | 实际内容 |
|---|---|---|
| `sofunny-artflow/scripts/artflow.mjs:86` | 访问 `.env` 文件 | `process.env.ARTFLOW_CLI_QUIET` —— 读环境变量，非读 `.env` 文件 |
| `sofunny-artflow/scripts/config.mjs:12,49,56` | 访问 `.env` 文件 | 同上，`process.env.ARTFLOW_CLI_*` |
| `sofunny-artflow/scripts/output.mjs:32` | 访问 `.env` 文件 | 同上，`process.env.ARTFLOW_CLI_QUIET` |
| `sofunny-artflow/scripts/output.mjs:51` | `exec()` 动态执行代码 | `RegExp.exec(text)` —— 正则匹配，非代码执行 |
| `sofunny-artflow/references/troubleshooting.md:32` | 访问 `.env` 文件 | 文档说明「后端 `.env` 缺 FEISHU_APP_ID/SECRET/REDIRECT_URI」—— 项目自身后端配置说明 |

### MEDIUM 复核

- 137 条「引用加密货币平台」：正则含 `ledger`，全部命中的是项目自身的**台账 / ledger**（`06-character-ledger`、资产账本等）概念，与加密货币无关。
- 1 条「输出抑制 `>/dev/null 2>&1`」：位于 `sofunny-artflow/scripts/setup.sh:14` 的 `command -v node >/dev/null 2>&1`，标准静默探测写法。

### 外部网络与文件访问

全部外部目标均为内网 / 自有域名，无可疑外发通道：

| 目标 | 性质 |
|---|---|
| `artflow.hnfunny.com` | 公司内部 ArtFlow 服务 |
| `git.sofunny.io` | 公司内部 Git |
| `10.20.3.93:33500` | 内网 IP |

**未发现**：`curl\|bash`、`wget\|sh`、base64/hex 混淆、反向 shell（`nc`、`/dev/tcp`、`mkfifo`）、`ngrok`、pastebin/短链服务、`sudo`、`~/.ssh` / Keychain / `/etc/passwd` 访问、crontab / launchctl 持久化、可疑二进制（`.exe` / `.dll` / `.dylib` 等）。

`sofunny-artflow/scripts/setup.sh` 仅把 `scripts/*.mjs` 复制到 `$HOME/.artflow-cli-bin`，无提权、无远程下载。

## 四、已安装清单（38）

**战局房间链路**：`00-battle-room-layout-assembler`、`01-battle-room-type-art-authoring`、`02-battle-room-component-decomposer`、`03-battle-room-instance-layout-authoring`、`04-battle-room-runtime-assembler`

**角色链路**：`01-character-contract-authoring`、`02-character-export-transfer`、`03-character-godot-import`、`04-character-state-binding`、`05-character-verification`、`06-character-ledger`

**道具/武器链路**：`05-items-weapons-pipeline-entry`、`06-items-weapons-blender-authoring`、`07-items-weapons-godot-prefab-assembly`、`08-items-weapons-code-integration`

**关卡/叙事**：`09-level-plan-authoring`、`10-narrative-timeline-authoring`

**资产规范**：`blender-game-prop-standard`、`godot-model-asset-import-standard`、`game-character-model-pipeline`、`game-prop-model-pipeline`、`game-weapon-model-pipeline`、`normal-enemy-model-pipeline`、`player-avatar-asset-standard`、`scene-full-pipeline`

**表现/内容管线**：`audio-sfx-asset-pipeline`、`music-asset-pipeline`、`ui-asset-pipeline`、`vfx-combat-effect-authoring`、`scene-art-damage-variant-kit`、`scene-art-double-sided-component`、`scene-art-merge-into-shared-component`

**工具/验证**：`godot-runtime-probe`、`godot-verification-suite-triage`、`godzilla-pet-visual-probe`、`skill-mirror-sync`、`xlsx-git-conflict-resolution`、`sofunny-artflow`

## 五、遗留事项

1. **`skills_drafts/` 落后 `.codex/skills` 2 个文件**（上述两个 SKILL.md），未改动 —— 属项目 skill 同步范畴，需按 `skill-mirror-sync` 的规则决定以哪份为准后补齐。
2. **`skill-mirror-sync/SKILL.md` 的路径表已过时**：它把正本 A 写成 `~/.workbuddy/skills/`（本机该目录 mtime 2026-09-16、仅 8 个 skill，是旧目录），而本机 WorkBuddy 实际使用的 skill 目录是 `~/.workbuddy-ai/skills/`。该 skill 的四副本路径表（含 Windows 盘符路径 `C:/` `I:/`）需按 macOS 本机重写，否则下次同步会写错位置。
3. 本机不存在 `~/.codex/skills` 之外的 D 副本差异需处理；`~/.codex/skills` 已存在，未被本次安装改动。
