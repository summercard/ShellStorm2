"""Apply the shared development exclusions to local Godot export presets.

The local preset file remains ignored by Git; signing settings are preserved.
"""
import argparse
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
EXCLUDES='addons/shellstorm_scene_builder/*,art_source/*,tests/*,tools/*,scripts/*,docs/*,skills_drafts/*,assets/registry/*,assets/*/qa/*,assets/*/reference/*,assets/*/references/*'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true');args=parser.parse_args()
    path=ROOT/'export_presets.cfg'
    if not path.is_file():
        print('Create local export presets in Godot, then run this tool.')
        return 1
    original=path.read_text(encoding='utf-8')
    desired=re.sub(r'^exclude_filter="[^"]*"','exclude_filter="'+EXCLUDES+'"',original,flags=re.M)
    desired=re.sub(r'^export_path="build/([^"]*)"',r'export_path="../ShellStorm2-work/build/\1"',desired,flags=re.M)
    if args.check and desired!=original:
        print('EXPORT_BOUNDARY_DRIFT');return 1
    if not args.check and desired!=original:path.write_text(desired,encoding='utf-8')
    print('EXPORT_BOUNDARIES_OK');return 0

if __name__=='__main__':raise SystemExit(main())
