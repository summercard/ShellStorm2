#!/usr/bin/env bash
# 把本仓库的 cli/ 安装到机器级路径（零依赖 Node CLI）。
# 用法：bash scripts/setup.sh   （在本仓库根目录执行，也可在任意位置用绝对路径调用）
set -euo pipefail

REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${ARTFLOW_CLI_BIN:-$HOME/.artflow-cli-bin}"

if [ ! -f "$REPO_PATH/scripts/artflow.mjs" ]; then
  echo "错误：$REPO_PATH/scripts/artflow.mjs 不存在（仓库结构异常）" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "错误：未安装 Node.js（需要 >= 18）。安装后重试。" >&2
  exit 1
fi

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "错误：Node 版本过低（$(node --version)，需要 >= 18）。" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp "$REPO_PATH"/scripts/*.mjs "$DEST_DIR/"
echo "已安装 CLI 到 $DEST_DIR/artflow.mjs"

echo "首次使用请先登录（飞书设备码，与网页同账号）："
echo "  node $DEST_DIR/artflow.mjs login --feishu"
echo "登录后自检：node $DEST_DIR/artflow.mjs doctor"
echo "用法示例：node $DEST_DIR/artflow.mjs types minimax_h3"
