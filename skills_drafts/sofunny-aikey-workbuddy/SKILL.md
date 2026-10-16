---
name: sofunny-aikey-workbuddy
version: 1.0.0
agent_created: true
description: >-
  安装/更新 WorkBuddy 的 Sofunny AIKey 自定义模型配置：拉取 git.sofunny.io/skill-libs/sofunny-aikey-workbuddy，
  用用户已有的 AIKey 一键写入或刷新 ~/.workbuddy/models.json（48 个模型，含上下文预算），
  并做端点连通性与真实推理冒烟验证。当用户说"更新 AIKey 配置""装/刷新 WorkBuddy 模型""AIKey 接入 WorkBuddy"
  "模型列表过期/预算不对"时使用。
---

# sofunny-aikey-workbuddy

把 Sofunny AIKey 中转（`https://llm-api-proxy.hnfunny.com/v1`）的模型清单写入 WorkBuddy 的 `~/.workbuddy/models.json`。
上游仓库：`git@git.sofunny.io:skill-libs/sofunny-aikey-workbuddy.git`（public，可免密 SSH 拉取；HTTPS 地址 `https://git.sofunny.io/skill-libs/sofunny-aikey-workbuddy.git`）。
**2026-10-10 起本仓从 `libs/` 组迁至 `skill-libs/` 组**，旧路径仅做重定向，不要依赖；默认分支为 `develop`。

## 使用原则

- **绝不把 API Key 写进本技能、脚本或对话正文。** Key 只从现有 `~/.workbuddy/models.json` 复用，或由用户当次提供，仅经环境变量 `SOFUNNY_AI_API_KEY` 传给 `install.sh`。
- **优先复用已有 Key**：本机装过就直接取，不要为了"确认"让用户重发密钥。
- 更新是幂等的：脚本会备份原配置并按 `id` 全覆盖刷新 AIKey 模型，同时保留用户自己加的非 AIKey 模型。
- 不修改 WorkBuddy 应用包，不添加未验证的自定义字段。

## 关键路径

| 项 | 值 |
|---|---|
| 目标配置 | `$HOME/.workbuddy/models.json` |
| 备份 | 同目录 `models.json.bak.<YYYYmmddHHMMSS>` |
| 清单模板 | 仓库根 `models.json`（`apiKey` 为占位符 `__SOFUNNY_AI_API_KEY__`） |
| 端点 | `https://llm-api-proxy.hnfunny.com/v1`（`useCustomProtocol: false`，走 `/chat/completions`） |

## 流程

### 1. 取到仓库

```bash
WORKDIR=$(mktemp -d) && cd "$WORKDIR"
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
  git clone --depth 1 git@git.sofunny.io:skill-libs/sofunny-aikey-workbuddy.git
cd sofunny-aikey-workbuddy
```

`BatchMode=yes` 很关键：SSH 需要交互时会快速失败而不是卡住。若内网不可达，先连 Sofunny VPN。

### 2. 确定 API Key（按优先级）

1. 复用现有配置里的 Key：`python3 -c "import json;print(json.load(open('$HOME/.workbuddy/models.json'))[0]['apiKey'])"`
2. 环境变量 `SOFUNNY_AI_API_KEY` 已设置则直接用。
3. 都没有 → **停下来问用户要**（向 AI Lab 申请，形如 `sk-...`）。不要猜、不要用占位符硬装。

### 3. 先验证 Key 与后端，再动配置

```bash
curl -sS -o /tmp/aikey_models.json -w "HTTP %{http_code}\n" --max-time 25 \
  -H "Authorization: Bearer $KEY" https://llm-api-proxy.hnfunny.com/v1/models
```

`HTTP 200` 才继续。`401/403` 说明 Key 失效，先让用户换 Key。

### 4. 执行安装

```bash
export SOFUNNY_AI_API_KEY="<key>"   # 只在本次 shell 内生效，不要落盘
./install.sh                        # macOS / Linux；Windows 用 install.bat
```

### 5. 校验（必做，不要只看脚本的"完成"）

```bash
python3 <本技能目录>/scripts/verify_config.py
```

脚本检查：JSON 合法、条目数、与仓库清单逐字段一致（除 `apiKey`）、`url`/`vendor`/`useCustomProtocol` 无异常、`apiKey` 唯一且已注入。
再跑一次真实推理冒烟，确认 Key 在 WorkBuddy 实际使用的端点上能出内容：

```bash
python3 <本技能目录>/scripts/smoke_test.py deepseek-v4-flash glm-4.7 qwen3.7-max
```

### 6. 交付

告诉用户：写入了多少模型、备份文件路径、哪些模型预算被刷新、冒烟结果（含失败模型）。
WorkBuddy 支持 `models.json` 热更新，无需重启。

## 上游滞后：清单里没有 ≠ 后端没有（高频问题）

**WorkBuddy 的自定义模型完全由 `models.json` 显式驱动，不会自动发现 AIKey 后端的新模型。**
后端 `/v1/models` 有的模型，只要没写进清单就不会出现在模型选择器里。用户问"XX 模型怎么没显示"，
先分清是三种情况：清单漏了 / 后端无渠道 / Key 无权限。

仓库的同步链是 **pi → sync → workbuddy**，由人工触发，**经常会滞后**。
`sofunny-aikey-pi` 加了新模型后，workbuddy 的 `models.json` 可能落后数周（实例：pi 于 2026-09-22
加 `qwen3.8-flash`，workbuddy 停在 2026-09-16，清单里完全没有）。

排查与补齐：

```bash
# 1. 拉 pi 仓库对比清单（pi 的模型定义在 extensions/index.ts 的 MODELS 数组）
GIT_SSH_COMMAND="ssh -o BatchMode=yes" git clone --depth 1 git@git.sofunny.io:skill-libs/sofunny-aikey-pi.git /tmp/pi-probe
python3 -c "
import json,re
src=open('/tmp/pi-probe/extensions/index.ts',encoding='utf-8').read()
pi=re.findall(r'^\s{8}id:\s*\"([^\"]+)\"',src,re.M)
wb=[m['id'] for m in json.load(open('$HOME/.workbuddy/models.json',encoding='utf-8'))]
print('pi 有 / workbuddy 缺:',[i for i in pi if i not in wb])
"

# 2. 用仓库自带的官方同步脚本算出正确清单（不要手写字段）
node skills/sync-aikey-models/scripts/sync_models.js --pi /tmp/pi-probe --dry-run   # 先看 diff
node skills/sync-aikey-models/scripts/sync_models.js --pi /tmp/pi-probe             # 写入仓库 models.json

# 3. 实测新增条目，剔除无渠道/无权限的，再跑 install.sh
```

- 补齐属于**本地先行**：上游未发布前，用户重新克隆跑 `install.sh` 会把补齐的模型冲掉
  （注意 `install.sh` 按 id 全覆盖 + 保留非清单模型，所以**增量**会被保留、**已收录的同名条目会被官方值覆盖**）。
  长期正解是给 workbuddy 仓库提 MR（改 `models.json` + 按 `--readme` 更新 README 模型表）。
- 别手改 `models.json` 的字段：官方脚本会处理 `INCOMPATIBLE_MODELS` 黑名单、`MODEL_SPECS` 覆盖表
  和系列排序，手写容易漏。
- **上游预算与 pi 原值不同时，以上游为准**。新模型进入 `CLIENT_CONTEXT_LIMITS` 后会被「等比例下调」，
  直接用 pi 的 `contextWindow`/`maxTokens` 会超出仓库的安全额度、长上下文被提前压缩。
  实例：`qwen3.8-flash` pi 原值 1,000,000/128,000，上游定稿 829,787/106,212。
- **别盲信 `sync_models.js` 的 `supportsImages` 结果**：它与上游 README / `models.json` 存在已知矛盾
  （`claude-fable-5`、`glm-5.1`、`qwen3.8-max` 三处，源于 pi 的 `input` 声明与上游 README 模态列不一致）。
  WorkBuddy 侧以 **README + `models.json` 一致的发布口径**为准；脚本改出的值只当参考。
- `claude-opus-5` / `claude-sonnet-4-6` 等 Anthropic 系模型当前实测 **Bedrock 无渠道权限**（HTTP 400），
  `gpt-5.3-codex` 是 **无可用渠道**（HTTP 503，且只支持 `/v1/responses`，已在脚本黑名单里）。
  这三种都要用冒烟结果判断，不要凭清单推测。

## 常见坑

- **只想"看差异"却直接装了**：更新前先 diff `models.json` 与仓库清单，把变更点讲给用户，再执行。历史变更多为上下文/输出预算调整（如 2026-09-16 的 27 模型等比例下调）。
- **`/v1/models` 只列 41 个 ≠ 清单里的 44 个不可用**：该端点不列全部模型（图像/视频类反而多列），清单以仓库为准，用冒烟测试判断实际可用性。
- **单模型 400 不一定是配置错**：例如 `claude-sonnet-4-6` 可能返回 Bedrock `Access to Anthropic models is not ...`（渠道权限问题），属后端侧，记录并向用户说明即可，不用回滚整份配置。
- **计费以 AIKey 后端账单为准**：WorkBuddy 本地不估算、不展示费用，阶梯计价 / 分组折扣 / 思考 token 都只在后端体现。别给用户报本地推算的价格。
- **Windows**：默认写 `%USERPROFILE%\.workbuddy\models.json`；配置目录不在该处时先设 `WORKBUDDY_HOME`。

## 文件

- `scripts/verify_config.py` — 配置一致性校验
- `scripts/smoke_test.py` — `/v1/chat/completions` 真实推理冒烟
