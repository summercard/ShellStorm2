"""Resolve authoring paths without changing stable Godot resource paths."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def source_path(path):
    """Map former authoring locations, including paths constructed by old tools."""
    path = Path(path)
    text = path.as_posix()
    marker = '/assets/art/'
    if marker in text:
        prefix, relative = text.split(marker, 1)
        if 'source' in relative.split('/') or path.suffix.lower() in {'.blend', '.psd', '.kra', '.xcf'}:
            return Path(prefix) / 'art_source' / relative
    if '/source/art/' in text:
        prefix, relative = text.split('/source/art/', 1)
        return Path(prefix) / 'art_source/design' / relative
    if text.endswith('/source/art'):
        return Path(text[:-len('/source/art')]) / 'art_source/design'
    if '/source/' in text and path.is_relative_to(ROOT / 'source'):
        return ROOT / 'art_source' / path.relative_to(ROOT / 'source')
    if text == (ROOT / 'source').as_posix():
        return ROOT / 'art_source'
    return path
