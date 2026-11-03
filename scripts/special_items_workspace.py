"""Shared file helpers for the SPECIAL-ITEMS feature's authoring tools."""
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from workspace_paths import work_path

BACKUP = ROOT.parent / 'ShellStorm2-backup/2026-11-03_special_items/before_edits'

def backup(relative):
    target = ROOT / relative
    original = BACKUP / relative
    if target.exists() and not original.exists():
        original.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, original)

def write(relative, content):
    target = ROOT / relative
    if target.exists():
        backup(relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    normalized = content.replace('\r\n', '\n').replace('\r', '\n')
    target.write_bytes(normalized.replace('\n', '\r\n').encode('utf-8'))

def replace(relative, old, new):
    text = (ROOT / relative).read_text(encoding='utf-8-sig')
    if old not in text:
        raise RuntimeError(f'Missing insertion anchor: {relative}: {old[:100]}')
    write(relative, text.replace(old, new, 1))
