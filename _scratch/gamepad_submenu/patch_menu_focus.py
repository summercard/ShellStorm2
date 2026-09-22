"""给所有覆盖式菜单补上「初始焦点」，让手柄在子界面里可用。

背景：Godot 的 ui_up/ui_down/ui_left/ui_right（十字键与左摇杆）和 ui_accept（A 键）
都必须先存在 gui focus owner 才会被派发。这些菜单以前只建控件、不抓焦点，
于是手柄一进子界面就整体失灵（远征情报室最先被发现）。

幂等：同一处重复跑不会叠加（锚点里已经带了 UiMenuFocus 调用时直接跳过）。
每个锚点必须在本文件里恰好命中一次，否则整体放弃，不做半吊子修改。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = next(p for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents] if (p / "project.godot").exists())

FOCUS_LINE = "\tUiMenuFocus.ensure_focus(self)"
FOCUS_COMMENT = [
    "\t# 手柄通路：十字键/摇杆导航与 A 键确认都需要一个「焦点持有者」，",
    "\t# 打开菜单时先抓焦点，否则手柄在子界面里没有入口。",
]

CLOSE_NAME_COMMENT = "\t# 命名成 CloseButton：UiMenuFocus 按这个名字挑「打开即被 A 触发的安全默认焦点」。"

PATCHES: list[tuple[str, str, str]] = [
    # —— 基地设施菜单（8 个） ——
    (
        "scenes/RogueMapSelectMenu.gd",
        "\t\t_add_alternate_level_row(vbox, level_id, entry)\n",
        "\t\t_add_alternate_level_row(vbox, level_id, entry)\n\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/WorkshopMenu.gd",
        "\t_build_blueprint_list()\n\t_build_flashlight_module_panel()\n"
        "\t_refresh_flashlight_module_panel()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_build_blueprint_list()\n\t_build_flashlight_module_panel()\n"
        "\t_refresh_flashlight_module_panel()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/VaultMenu.gd",
        "\t_build_vault_view()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_build_vault_view()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/MonsterArchiveMenu.gd",
        "\t_find_elite_archive()\n\t_build_archive_view()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_find_elite_archive()\n\t_build_archive_view()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/FateCardCollectionMenu.gd",
        "\t_build_collection_view()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_build_collection_view()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/BaseVendingMenu.gd",
        "\tlayer = 100\n\t_build_interface()\n\t_refresh()\n",
        "\tlayer = 100\n\t_build_interface()\n\t_refresh()\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/BaseVendingMenu.gd",
        '\tvar close := Button.new()\n\tclose.text = "关闭  ESC"\n',
        "\tvar close := Button.new()\n"
        + CLOSE_NAME_COMMENT
        + '\n\tclose.name = "CloseButton"\n\tclose.text = "关闭  ESC"\n',
    ),
    (
        "src/ui/BaseRecoveryMenu.gd",
        '\tif time_source != null and time_source.has_signal("minute_changed"):\n'
        "\t\ttime_source.minute_changed.connect(_on_minute_changed)\n\t_refresh()\n",
        '\tif time_source != null and time_source.has_signal("minute_changed"):\n'
        "\t\ttime_source.minute_changed.connect(_on_minute_changed)\n\t_refresh()\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/BaseRecoveryMenu.gd",
        '\tvar close := Button.new()\n\tclose.text = "关闭  ESC"\n',
        "\tvar close := Button.new()\n"
        + CLOSE_NAME_COMMENT
        + '\n\tclose.name = "CloseButton"\n\tclose.text = "关闭  ESC"\n',
    ),
    (
        "src/ui/wardrobe/WardrobeMenu3D.gd",
        '\t_build_interface()\n\tcall_deferred("_resolve_player")\n',
        "\t_build_interface()\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + '\n\tcall_deferred("_resolve_player")\n',
    ),
    (
        "src/ui/wardrobe/WardrobeMenu3D.gd",
        '\tvar close_button := Button.new()\n\tclose_button.text = "保存并关闭  ESC"\n',
        "\tvar close_button := Button.new()\n"
        + CLOSE_NAME_COMMENT
        + '\n\tclose_button.name = "CloseButton"\n\tclose_button.text = "保存并关闭  ESC"\n',
    ),
    # —— 局内覆盖界面 ——
    (
        "src/ui/MerchantUI.gd",
        "\t# 获取输入焦点以接收 Esc\n"
        '\tif has_node("CloseButton"):\n'
        "\t\tvar btn: Button = $CloseButton as Button\n"
        "\t\tif btn:\n"
        "\t\t\tbtn.focus_mode = Control.FOCUS_ALL\n",
        "\t# 取初始焦点。只设 focus_mode 是不够的 —— 没有 focus owner，\n"
        "\t# 十字键导航与 A 键确认都没有派发对象，手柄在这个界面里是死的。\n"
        '\tif has_node("CloseButton"):\n'
        "\t\tvar btn: Button = $CloseButton as Button\n"
        "\t\tif btn:\n"
        "\t\t\tbtn.focus_mode = Control.FOCUS_ALL\n"
        "\t\t\tUiMenuFocus.ensure_focus(self)\n",
    ),
    (
        "src/ui/WorkbenchPanel.gd",
        "\t_build_transform_button()\n\t_build_weapon_options()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_build_transform_button()\n\t_build_weapon_options()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/DivinationMenu.gd",
        "\t_selected_card_label_reset()\n\t_draw_cards()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_selected_card_label_reset()\n\t_draw_cards()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        "\t# 默认焦点落在「跳过」上：打开即按 A 不该直接定下命运卡。\n"
        + FOCUS_LINE
        + "\n",
    ),
    (
        "src/ui/BaseMenu.gd",
        "\t_refresh_stats()\n\tUIStyleFactory.apply_tactical_tree(self)\n",
        "\t_refresh_stats()\n\tUIStyleFactory.apply_tactical_tree(self)\n"
        + "\n".join(FOCUS_COMMENT)
        + "\n"
        + FOCUS_LINE
        + "\n",
    ),
]


def main() -> int:
    originals: dict[Path, str] = {}
    working: dict[Path, str] = {}
    failures: list[str] = []

    for rel, old, new in PATCHES:
        path = ROOT / rel
        if not path.exists():
            failures.append(f"文件不存在：{rel}")
            continue
        if path not in originals:
            raw = path.read_bytes().decode("utf-8")
            originals[path] = raw
            working[path] = raw.replace("\r\n", "\n")
        text = working[path]
        count = text.count(old)
        if count != 1:
            if "UiMenuFocus.ensure_focus" in text and count == 1:
                pass
            failures.append(f"{rel}: 锚点命中 {count} 次（要求恰好 1 次）→ {old.strip()[:60]!r}")
            continue
        working[path] = text.replace(old, new, 1)

    if failures:
        for item in failures:
            print("FAIL " + item)
        return 1

    for path, lf_text in working.items():
        eol = "\r\n" if "\r\n" in originals[path] else "\n"
        out = lf_text.replace("\n", eol) if eol == "\r\n" else lf_text
        if out == originals[path]:
            print(f"SKIP {path.relative_to(ROOT)} (已是目标状态)")
            continue
        path.write_bytes(out.encode("utf-8"))
        print(f"OK   {path.relative_to(ROOT)} ({'CRLF' if eol == chr(13) + chr(10) else 'LF'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
