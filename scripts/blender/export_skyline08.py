"""仅导出指定SKYLINE v004；复用两塔已验收的逐包派生导出流程。"""
import argparse
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_openworld_towers import export_tower

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project-root', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    export_tower(Path(args.project_root).resolve(), 'skyline_08', 'v004')
