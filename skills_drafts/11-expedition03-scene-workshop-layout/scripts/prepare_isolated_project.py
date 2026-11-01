#!/usr/bin/env python3
"""Prepare one isolated Godot case; never starts the engine or edits game files."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import uuid


def config_text(original, namespace, renderer):
    lines, output, section, app_seen = original.splitlines(), [], "", False
    for line in lines:
        if line.startswith("[") and line.endswith("]"):
            section = line
            if section == "[application]":
                app_seen = True
                output.extend([line, "config/use_custom_user_dir=true", f'config/custom_user_dir_name="{namespace}"'])
                continue
        if section == "[application]" and re.match(r"config/(use_custom_user_dir|custom_user_dir_name)\s*=", line):
            continue
        output.append(line)
    if not app_seen:
        raise ValueError("project.godot has no [application] section")
    if renderer:
        output = [line for line in output if not re.match(r"renderer/rendering_method\s*=", line)]
        rendering = output.index("[rendering]") if "[rendering]" in output else len(output)
        if rendering == len(output):
            output.extend(["", "[rendering]"])
            rendering = len(output) - 1
        output.insert(rendering + 1, f'renderer/rendering_method="{renderer}"')
    result = "\n".join(output) + "\n"
    assert result.count("config/use_custom_user_dir=true") == 1
    assert result.count(f'config/custom_user_dir_name="{namespace}"') == 1
    return result


def profile_root():
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support"
    if os.name == "nt":
        if not os.environ.get("APPDATA"):
            raise ValueError("APPDATA is not set")
        return Path(os.environ["APPDATA"])
    return Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))


def prepare(args):
    root = args.project_root.resolve()
    source = root / "project.godot"
    original = source.read_bytes()
    for value in [args.session, args.case]:
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value):
            raise ValueError("session/case must contain only letters, digits, '_' or '-'")
    module_path = root / "scripts/workspace_paths.py"
    spec = importlib.util.spec_from_file_location("exp03_workspace_paths", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    case = module.work_path(f"sessions/exp03_layout_{args.session}/{args.case}")
    # Never reuse a namespace or overwrite an old case, even when a previous run failed.
    case.mkdir(exist_ok=False)
    project, userdata = case / "project", case / "userdata"
    project.mkdir()
    userdata.mkdir()
    namespace = f"ShellStorm2Exp03Layout_{uuid.uuid4().hex}"
    config = config_text(original.decode("utf-8-sig"), namespace, args.renderer)
    (project / "project.godot").write_text(config, encoding="utf-8")
    for name in ["assets", "src", "tools", "addons", "scenes", "data", "tests", "scripts", "icon.svg"]:
        path = root / name
        if path.exists():
            (project / name).symlink_to(path, target_is_directory=path.is_dir())
    cache = project / ".godot"
    cache.mkdir()
    for name in ["global_script_class_cache.cfg", "uid_cache.bin"]:
        path = root / ".godot" / name
        if not path.is_file():
            raise ValueError(f"missing Godot cache: {path}; prepare an isolated import before testing")
        shutil.copy2(path, cache / name)
    imported = root / ".godot/imported"
    if not imported.is_dir():
        raise ValueError("missing imported resources; do not run against the live project as a fallback")
    (cache / "imported").symlink_to(imported, target_is_directory=True)
    link = profile_root() / namespace
    link.parent.mkdir(parents=True, exist_ok=True)
    link.symlink_to(userdata, target_is_directory=True)
    expected = json.dumps(link.as_posix(), ensure_ascii=False)
    guard = f'''extends SceneTree
func _initialize() -> void:
 _verify.call_deferred()
func _verify() -> void:
 var actual := OS.get_user_data_dir().replace("\\\\", "/").simplify_path()
 var expected := {expected}.simplify_path()
 var manager := root.get_node_or_null("BaseManager")
 var save_path := "" if manager == null else ProjectSettings.globalize_path(str(manager.get("save_path"))).replace("\\\\", "/").simplify_path()
 var ok := actual == expected and save_path.begins_with(expected + "/")
 print("EXP03_ISOLATION_GUARD ", JSON.stringify({{"ok":ok,"actual":actual,"expected":expected,"save_path":save_path}}))
 quit(0 if ok else 1)
'''
    (project / "_exp03_isolation_guard.gd").write_text(guard, encoding="utf-8")
    assert source.read_bytes() == original, "formal project.godot changed during preparation"
    result = {
        "isolated_project": str(project), "namespace": namespace,
        "user_data_link": str(link), "user_data_target": str(userdata),
        "formal_config_sha256": hashlib.sha256(original).hexdigest(),
        "guard_args": ["--headless", "--path", str(project), "--script", "res://_exp03_isolation_guard.gd"],
        "status": "prepared_only_run_guard_before_any_test",
    }
    (case / "isolation_manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("--session", required=True)
    parser.add_argument("--case", required=True)
    parser.add_argument("--renderer", choices=["gl_compatibility", "mobile", "forward_plus"])
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args), ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, AssertionError) as exc:
        print(json.dumps({"error": str(exc), "status": "not_ready_do_not_run_tests"}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
