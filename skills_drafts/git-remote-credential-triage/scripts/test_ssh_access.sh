#!/usr/bin/env bash
# 测试各 HTTPS 远程能否改用 SSH（只读 ls-remote，不改动任何仓库）
export PATH="/c/Program Files/Git/usr/bin:$PATH"
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10"

REPOS="
summercards/theone
summercards/myfarm
summercards/galgamemaster
summercards/music
summercards/zhuochong
summercards/myfarmunity
summercards/Godzilla
summercards/hillhouse
summercards/3Dgame-desgin
summercard/ocbananaInstaller
summercard/godcraft_v3
summercard/match3-godot
summercard/match3-cocos
summercard/ShellStorm2
jwu/ui-design
jwu/ai-canvas
anthropics/claude-plugins-official
openai/skills
"

printf "%-42s %s\n" "仓库" "SSH 可用性"
printf '%s\n' "----------------------------------------------------------------------------"
for r in $REPOS; do
  if git ls-remote "git@github.com:$r.git" HEAD >/dev/null 2>&1; then
    printf "%-42s %s\n" "$r" "OK  可切 SSH"
  else
    printf "%-42s %s\n" "$r" "NO  不能切"
  fi
done
