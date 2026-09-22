# -*- coding: utf-8 -*-
# 事务「命运卡界面手柄不能操控」反向对照：
# 逐条把修复点打回缺陷态，确认对应断言精准变红，然后逐行还原。
# 纪律：只做**行级替换**（读最新 -> 改目标行 -> 写回），绝不整档覆写，避免顶掉并行会话的改动。
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path("I:/工作项目/shellstrom2/ShellStorm2")
DUNGEON = ROOT / "src/world3d/Dungeon3D.gd"
GODOT = "I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
LOG_DIR = ROOT / "_scratch/fate_focus"
SCENE = "res://tests/verification/verify_dual_weapon_quick_map_fate_flow.tscn"

# (变体名, 注入时把 old 换成 new, 预期命中的断言关键字)
VARIANTS = [
    (
        "no_focus",
        "\t_maybe_focus_fate_card(button)\n",
        "\tpass  # RC: focus init disabled\n",
        "no gui focus owner",
    ),
    (
        "no_neighbor",
        "\t_configure_fate_card_focus_navigation(card_buttons)\n",
        "\tpass  # RC: neighbour wiring disabled\n",
        "no left focus neighbour",
    ),
    (
        "hardcoded_esc",
        '\tif _door_fate_active and event.is_action_pressed("ui_cancel"):\n',
        "\tif _door_fate_active and event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:\n",
        "ui_cancel did not cancel",
    ),
    (
        "no_detach",
        "\t\t\toverlay_parent.remove_child(_fate_overlay)\n",
        "\t\t\tpass  # RC: detach before queue_free disabled\n",
        "Fate overlay node is missing",
    ),
]


def patch(old: str, new: str) -> None:
    # 读时把 CRLF 归一成 LF 便于匹配，写回时统一还原成 CRLF（该档已验证是纯 CRLF）。
    text = DUNGEON.read_bytes().decode("utf-8").replace("\r\n", "\n")
    count = text.count(old)
    if count != 1:
        raise SystemExit("PATCH-FAIL anchor count=%d for %r" % (count, old[:60]))
    DUNGEON.write_bytes(text.replace(old, new).replace("\n", "\r\n").encode("utf-8"))


def run_godot(tag: str) -> str:
    log_path = LOG_DIR / ("rc_%s.log" % tag)
    env = os.environ.copy()
    env["APPDATA"] = "I:/_ss_appdata_fatefocus"
    with open(log_path, "wb") as handle:
        proc = subprocess.run(
            [GODOT, "--headless", "--path", ".", "--scene", SCENE],
            cwd=str(ROOT),
            env=env,
            stdout=handle,
            stderr=subprocess.STDOUT,
            timeout=600,
        )
    text = log_path.read_text(encoding="utf-8", errors="replace")
    return text


results = []
for tag, old, new, marker in VARIANTS:
    patch(old, new)
    try:
        log = run_godot(tag)
    finally:
        patch(new, old)  # 逐行还原
    hits = [
        line.strip()
        for line in log.splitlines()
        if line.startswith("ERROR:") and "BaseManager" not in line and "invalid UID" not in line
    ]
    ok_marker = "_OK" in log
    marker_hit = any(marker in line for line in hits)
    results.append((tag, len(hits), marker_hit, ok_marker))
    print("[%s] errors=%d marker_hit=%s printed_OK=%s" % (tag, len(hits), marker_hit, ok_marker))
    for line in hits:
        print("    " + line[:160])

print("--- restore check ---")
text = DUNGEON.read_bytes().decode("utf-8").replace("\r\n", "\n")
for tag, old, new, marker in VARIANTS:
    print("  %s: old_present=%d new_left=%d" % (tag, text.count(old), text.count(new)))
bad = [r for r in results if not (r[2] and not r[3])]
print("ALL_VARIANTS_HIT_EXPECTED" if not bad else "SOME_VARIANT_MISSED: %s" % bad)
sys.exit(0 if not bad else 1)
