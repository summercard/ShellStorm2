from pathlib import Path
idx = Path(r'I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-22\_INDEX.md')
row = Path(r'I:\工作项目\shellstrom2\ShellStorm2\_scratch\boss_datacore_index_row.txt').read_bytes()
b = idx.read_bytes()
sep = b'|---|---|---|---|\r\n'
assert b.count(sep) == 1, b.count(sep)
assert b'1738_远征01Boss房种类美术源制作.md' not in b
idx.write_bytes(b.replace(sep, sep + row, 1))
print('INDEX_UPDATED', idx)
