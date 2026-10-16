# sofunny-resource-sharing

把本地文件发布成**内网可分享链接**：HTML / 静态站点，以及 **APK、ZIP、安装包等资源包**。支持**原地更新**（重新推送后 URL 不变）与查询/删除自己发布的内容。发布通过 token 鉴权的部署 API 完成（免 SSH），**客户端与服务端都不做内容凭据检查**（发布内容由发布者自行确认），强制路径穿越防护、归属隔离、包体限额与原子部署，多人使用时按 token 强制归属隔离。对外统一 **HTTPS**：公开域名走 443 与自动续期的受信证书，明文 80 端口只做 301 跳转。

- HTML 单文件 → `https://sofunny-resource-sharing.hnfunny.com/site-id.html`
- HTML 目录 → `https://sofunny-resource-sharing.hnfunny.com/site-id/`
- **资源单文件（如 APK）→ 直链 `https://sofunny-resource-sharing.hnfunny.com/site-id.apk`**（另附含大小与 SHA256 的入口页）
- **资源目录（多个文件）→ `https://sofunny-resource-sharing.hnfunny.com/site-id/`**（自动生成资源索引页）

本 skill 由 [sofunny-publish-html](https://git.sofunny.io/skill-libs/sofunny-publish-html) 演进而来并替代它。两者共用同一套服务器与存储，旧技能的站点、token、链接全部继续有效，本 skill 首次运行会自动接管旧技能的 `state/`（复用 token、导入发布记录）。

这是一个通用 Skill（适用于 Claude Code、Codex 等 Agent），由 `SKILL.md` 描述触发时机与工作流，由 `scripts/publish.py` 提供可执行入口。

**本仓库只有客户端**：打包本地内容、调 API 上传、维护本地发布记录。服务器（部署 daemon、静态文件服务、HTTPS 证书、管理后台、token 管理）在独立仓库 [sofunny-resource-sharing-server](https://git.sofunny.io/skill-libs/sofunny-resource-sharing-server)，由服务器操作员维护。

> 本文件仅供人类快速了解；AI 安装 / 使用请以 [SKILL.md](SKILL.md) 为唯一权威定义。

## 安装与迁移（AI 可直接按此执行）

本仓库是 GitLab public 仓库，SSH 与 HTTPS 都能直接拉取，无需额外凭据：

```bash
# 安装本 skill（自动软链到已检测到的各 Agent 目录）
npx skills add git@git.sofunny.io:skill-libs/sofunny-resource-sharing.git -g -y
```

安装位置：`~/.agents/skills/sofunny-resource-sharing`；各 Agent（Claude Code、Codex 等）目录下是对它的软链。入口脚本：`<安装目录>/scripts/publish.py`（下文以 `${SKILL_DIR}` 代指）。依赖 Python 3.9+（纯标准库）。

### 从 sofunny-publish-html 换过来（AI 按顺序执行，别跳步）

```bash
# 1) 安装新技能
npx skills add git@git.sofunny.io:skill-libs/sofunny-resource-sharing.git -g -y

# 2) 先让新技能跑一次，接管旧技能的 state（token 与发布记录）
python3 ~/.agents/skills/sofunny-resource-sharing/scripts/publish.py status
#    期望看到：提示: 已接管旧技能的运行状态（token 配置、N 条发布记录）
#    以及历史站点列表

# 3) 确认历史站点可见、可管后再卸载旧技能
npx skills remove sofunny-publish-html -g -y
```

**第 2 步必须在第 3 步之前。** 旧技能的 token 与发布记录存在它自己的 `state/` 里，卸载会把它们一起删掉：先卸载就再也拿不回原 token（具名 token 用户会失去历史站点的管理权，`--update` 也会失效）。第 2 步的接管是一次性拷贝，跑完新技能自己就有一份完整 state。

**若第 3 步报 `No matching skills found`**：说明旧技能不是用 `npx skills` 装的（手工软链或直接拷贝），安装器扫描不到软链。此时直接删链接即可，**不要删链接指向的目录**：

```bash
rm -f ~/.claude/skills/sofunny-publish-html ~/.codex/skills/sofunny-publish-html
```

迁移后的状态：

- **历史站点无需重发**：token 已复用，`status` / `server-sites` 能看到，`--update` 能原地更新（链接不变），`remove-server` 能删除。
- **链接域名**：新发布的链接用 `https://sofunny-resource-sharing.hnfunny.com`；旧域名 `sofunny-html.hnfunny.com` 在保留期内继续可用——它的明文链接会被 301 跳到同域名的 HTTPS，证书同时覆盖两个域名，老链接不会失效（两个域名同一台服务器、同一份内容）。
- **旧技能仓库**（`skill-libs/sofunny-publish-html`）保留作历史版本与手工兜底，不再接受新功能；已升级到 v2.5.0，其 SKILL.md 也会把 AI 引导到本技能。

## 仓库结构

```
sofunny-resource-sharing/          # 客户端
├── SKILL.md                       # Skill 描述：何时使用、工作流、错误处理（权威）
├── README.md                      # 本文件（人类概述）
├── scripts/
│   └── publish.py                 # 可执行入口：发布 / 更新 / 查询 / 删除 / TLS 巡检 / 管理后台地址
├── references/
│   └── security-boundary.md       # 发布者安全边界：能力链接、不做内容检查、上限、自查清单
└── agents/
    └── openai.yaml                # Agent 描述元数据（display_name / default_prompt）

sofunny-resource-sharing-server/   # 服务端（另一个仓库，操作员维护）
├── scripts/publish-daemon.py      # 部署 API（41740）+ 管理后台 + token 管理
├── scripts/safe-static-server.py  # 静态服务（41739 / 80 / 443）
├── scripts/setup-tls.py           # HTTPS 证书签发与续期
├── scripts/server.py              # 操作员 SSH 入口：install / upgrade / token-*
└── references/server-security.md  # 服务器安全模型与剩余风险
```

两代技能（本 skill 与它的前身 sofunny-publish-html）与两个仓库共用**同一台服务器、同一份存储、同一个 token 库**，服务器上的目录与系统服务名沿用历史命名（`~/.publish-html/`、`com.publish-html.api`、`com.publish-html.static80`），不要重命名。

## 配置

运行状态保存在 skill 根目录的 `state/` 下（发布记录在 `state/runs/`，API 配置与 token 在 `state/server/`），跨会话可见可管。

**普通用户无需任何配置**：首次发布自动连接内置部署服务器（`http://10.41.0.2:41740`）申领 token（身份 label 形如 `auto-<用户名>`）并保存。

可选覆盖：

- 持有操作员签发的具名 token 时，可手工指定：

  ```bash
  python3 ${SKILL_DIR}/scripts/publish.py \
    config-server --base-url http://10.41.0.2:41740 --token ph_tok_xxxxx
  ```

- 环境变量：`PUBLISH_HTML_API_BASE_URL`、`PUBLISH_HTML_API_TOKEN`（沿用旧技能的环境变量名，两代通用）。
- 公开地址覆盖：发布时加 `--public-base-url https://...`，用于域名尚未解析时应急。通常不需要——客户端优先采用服务器通过 `/api/v1/health` 公布的地址。

## 模式速查

| 模式 | 说明 | 使用者 |
|------|------|--------|
| `server SOURCE` | 发布 HTML / 静态目录 / 资源包，返回内网 URL | 所有人 |
| `server SOURCE --update` | 原地更新该来源上次发布的站点，URL 不变（`--site-id` 可显式指定） | 所有人 |
| `server SOURCE --no-index` | 单文件资源发布时不生成入口页，只给直链 | 所有人 |
| `server-sites` | 列出当前 token 部署的站点（含类型） | 所有人 |
| `status` | 查看本地部署缓存与站点存活状态 | 所有人 |
| `tls-status` | 检查公开域名证书、覆盖域名、剩余天数与 80 跳转 | 所有人 |
| `remove-server SITE_ID --confirm-site-id SITE_ID` | 删除站点（双确认，仅限自己的） | 所有人 |
| `admin-url` | 打印服务器管理后台地址（用管理员 token 打开，看全部链接） | 所有人 |
| `config-server` | 可选：手工指定 base_url 与操作员签发的 token | 所有人 |

服务器的 `install` / `upgrade` / `token-*` 与 HTTPS 证书命令在 [sofunny-resource-sharing-server](https://git.sofunny.io/skill-libs/sofunny-resource-sharing-server) 仓库，由操作员执行。

常用参数：`--entry demo.html`（非默认入口）、`--root`（显式指定静态根目录）、`--name`（站点名提示）、`--public-base-url`（覆盖默认公开地址）。

## 快速用法

发布安装包（APK / ZIP / dmg / exe …），得到可直接分享的下载直链：

```bash
python3 ${SKILL_DIR}/scripts/publish.py server /absolute/path/to/App-Release.apk
# URL: https://sofunny-resource-sharing.hnfunny.com/app-release-20261008-160142.apk
# 入口页: https://sofunny-resource-sharing.hnfunny.com/app-release-20261008-160142/
# SHA256: fec3238d...
```

发布一整批文件（目录内没有 `index.html` 时自动生成资源索引页）：

```bash
python3 ${SKILL_DIR}/scripts/publish.py server /absolute/path/to/release-dir
# URL: https://sofunny-resource-sharing.hnfunny.com/release-dir-20261008-160234/
```

发布单个 HTML / 静态目录：

```bash
python3 ${SKILL_DIR}/scripts/publish.py server /absolute/path/to/index.html
python3 ${SKILL_DIR}/scripts/publish.py server /absolute/path/to/dist
```

管理已发布内容：

```bash
python3 ${SKILL_DIR}/scripts/publish.py status
python3 ${SKILL_DIR}/scripts/publish.py server-sites
python3 ${SKILL_DIR}/scripts/publish.py remove-server SITE_ID --confirm-site-id SITE_ID
```

完整参数说明、发布前检查与错误处理见 [SKILL.md](SKILL.md)。

## 工作流

1. `server` 对来源做快照：按后缀与文件名白名单跳过隐藏文件、符号链接、`.env`、私钥、数据库与依赖缓存，限制文件数与总体积，然后把内容原样打包上传。**不对内容做任何凭据检查** —— 文本里的 key、压缩包里的 `.env`、签名文件都不会被识别或拦截，是否可公开由发布者自行确认。
2. 目录没有 HTML 入口时按资源包处理，自动生成资源索引页（文件名、大小、SHA256）；单文件资源发布额外给出 `/<site-id>.<后缀>` 下载直链，复合后缀（`.tar.gz` 等）在直链里整体保留。
3. 打包为 tar / tar.gz **分块流式上传**到部署 API（端口 `41740`，默认上限 2 GiB / 5000 文件）；服务端边收边落盘、重新校验归档成员后原子写入 `~/.publish-html/sites/<site-id>/`，并把 token label 写入站点 meta 作为 owner。
4. 共享静态服务提供能力链接，资源后缀带 `Content-Disposition: attachment` 触发浏览器下载并返回正确的 MIME（如 `.apk` → `application/vnd.android.package-archive`）；发布记录写入 `state/runs/`，任何会话可用 `status` 查看、`remove-server` 删除。

## 支持的资源类型

`.apk .apks .aab .ipa .dmg .pkg .exe .msi .deb .rpm .appimage .jar .aar .whl .zip .7z .rar .tar .gz .tgz .bz2 .xz .iso`（以及原有静态资源：HTML、CSS、JS、图片、音视频、PDF、字体、GLB 等）。

发布前需人工确认包内无敏感内容：这条链路不做任何内容检查。上面的体积上限是服务器侧的发布限额，与内容无关。

## 部署环境

| 组件 | 地址 | 说明 |
|------|------|------|
| 公开站点（新） | `https://sofunny-resource-sharing.hnfunny.com/`（→ `10.41.0.2:443`） | 需 IT 在内网 DNS 增加解析 |
| 公开站点（旧） | `https://sofunny-html.hnfunny.com/`（→ `10.41.0.2:443`） | 保留期内旧链接继续可用 |
| 明文跳转 | `http://<上述域名>/`（→ `10.41.0.2:80`） | 301 跳到同域名的 HTTPS |
| 部署 API | `http://10.41.0.2:41740` | 客户端自动连接并申领 token（明文，内网 IP 直连） |
| **管理后台** | `http://10.41.0.2:41740/admin` | 看服务器上全部已发布链接（需管理员 token，只读）；`publish.py admin-url` 打印地址 |
| 静态服务 | `10.41.0.2:41739` | 兼容旧链接保留（明文，内网 IP 直连） |

两个域名指向同一台机器的 443 端口，共用同一张证书，静态服务按路径取文件、不看 Host，因此内容天然一致、无需双份部署。DNS 未覆盖的机器可临时在 `/etc/hosts` 加一行 `10.41.0.2 sofunny-resource-sharing.hnfunny.com`。

### HTTPS 证书（操作员）

证书由 **acme.sh + 阿里云 DNS（DNS-01 挑战）+ ZeroSSL** 签发，覆盖上述两个域名，90 天有效、每日自动续期并自动重启 443 实例。不选 Let's Encrypt 是因为这张网络挡住了它的 `172.65.0.0/16`。

```bash
# 在服务器上一次性安装（需要阿里云 RAM 用户，仅 AliyunDNSFullAccess）
export Ali_Key=<AccessKeyId>; export Ali_Secret=<AccessKeySecret>
python3 ~/.publish-html/setup-tls.py install --email <你的邮箱>

# 随时查看现状：服务器上用 setup-tls.py status，客户端上：
python3 ${SKILL_DIR}/scripts/publish.py tls-status
```

脚本来自服务端仓库，完整说明见其 README；客户端巡检与出错处置见 [SKILL.md](SKILL.md) 的「HTTPS 证书与续期」。

## 重要约束

- **链接是 HTTPS 能力链接，有加密但没有登录鉴权**：传输已加密且带一年 HSTS，但持有完整 URL 的任何人（可转发出内网）都能读取或下载内容。不得发布密码、客户隐私、商业机密或生产数据。
- **加密只覆盖公开域名**：`10.41.0.2:41739`（静态）与 `10.41.0.2:41740`（部署 API）仍是明文，靠内网边界保护；不要把这些 IP 直连地址当作对外分享链接。
- **单文件默认只发布该文件**：需要 CSS / JS / 图片时传专用静态目录；只有人工确认目录内容后才使用 `--root`，避免误传父目录。
- **不做内容凭据检查**：客户端与服务端都只有路径安全、归属校验、包体限额、后缀白名单四条非内容类约束。包里的密钥、`.env`、签名文件、内部资料不会被识别或拦截，**发布者必须自行确认**。
- **没有补偿性内容控制**：服务端也不做「扫描后记日志」——发布链路完全不读内容做匹配。能访问部署 API 的人可以直接上传任何内容。
- **删除不可恢复**：必须由用户明确给出准确 Site ID 并双确认；不得批量删除或猜测 Site ID。
- **归属隔离由服务端强制**：`server-sites` / `remove-server` 只作用于当前 token 部署的站点，无法通过 API 触碰他人站点。
- **下载不支持断点续传**：静态服务不处理 Range 请求，中断后需重新下载。
- **CSP 默认禁止页面外联**，目录列表与隐藏路径一律 404；发布者边界与自查清单详见 [references/security-boundary.md](references/security-boundary.md)，服务器侧安全模型见服务端仓库的 `references/server-security.md`。
- **管理后台是全量视图**：管理员 token 能列出所有人的链接，且只在**内网明文端口** `41740` 上提供，只发给需要「看得全」的人；它只读，删除仍走 `remove-server`。
