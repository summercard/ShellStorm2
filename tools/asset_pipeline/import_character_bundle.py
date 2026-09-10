"""Verify a transfer bundle and generate presentation wrappers. Never edits gameplay scenes.

Usage: python3 tools/asset_pipeline/import_character_bundle.py <production/vNNN>
Then run Godot verification on the generated wrapper before selecting it in Player3D.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('package',type=Path)
    parser.add_argument('--skip-validation',action='store_true',help='Explicit user waiver; never label the result validated')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    package=args.package.resolve()
    ledger_path=package/f'character_transfer_ledger_{package.name}.json'
    ledger=json.loads(ledger_path.read_text())
    for file in ([] if args.skip_validation else ledger['files']):
        path=root/file['path']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=file['sha256']:
            raise RuntimeError('Stale/missing source or export: '+str(path))
    version=ledger['version']
    base=package.parents[1]
    source=base/'chr_player_capsule01_bunny01_root_top3d_v008.tscn'
    text=source.read_text()
    exports='res://'+str((package/'exports').relative_to(root))+'/'
    for part in ['body','head','hand_l','hand_r','foot_l','foot_r']:
        text=re.sub(r'res://[^"\n]+/chr_player_capsule01_bunny01_'+part+r'_top3d_v007.glb', exports+f'chr_bunny01_{part}_{version}.glb',text)
    text=re.sub(r'res://[^"\n]+/chr_player_capsule01_bunny01_ear_top3d_v007.glb',exports+f'chr_bunny01_ear_r_{version}.glb',text)
    text=text.replace('[gd_scene load_steps=10','[gd_scene load_steps=11')
    text=text.replace('[node name="CapsuleAvatar3D"',f'[ext_resource type="PackedScene" path="{exports}chr_bunny01_ear_l_{version}.glb" id="10_ear_l"]\n\n[node name="CapsuleAvatar3D"',1)
    text=text.replace('[node name="CapsuleAvatar3D" instance=ExtResource("1_base")]','[node name="CapsuleAvatar3D" instance=ExtResource("1_base")]\nmetadata/assembly_version = "'+version+'"')
    # Exported components already use their rest bone pivot; remove former per-mesh compensations.
    blocks=text.split('\n[node ')
    for i,block in enumerate(blocks):
        header=block.split('\n',1)[0]
        if 'name="EarAccessory"' in header or ('name="Model"' in header and '/HandJoint' in header):
            block=re.sub(r'\n(?:position|scale) = Vector3\([^\n]+\)','',block)
            if '/EarSocketL' in header: block=block.replace('ExtResource("4_ear")','ExtResource("10_ear_l")')
            blocks[i]=block
    text='\n[node '.join(blocks)
    runtime=package/'runtime'
    runtime.mkdir(exist_ok=True)
    head_source=base/'accessories/head/chibi_anime_head_v002/runtime/chr_player_bunny01_head_chibi_anime_root_top3d_v002.tscn'
    head=head_source.read_text()
    head=re.sub(r'res://[^"\n]+\.glb',exports+f'chr_bunny01_chibi_anime_{version}.glb',head)
    head_path=runtime/f'chr_bunny01_chibi_anime_root_{version}.tscn'
    head_path.write_text(head)
    text=text.replace('res://'+str(head_source.relative_to(root)),'res://'+str(head_path.relative_to(root)))
    wrapper=runtime/f'chr_bunny01_root_{version}.tscn'
    wrapper.write_text(text)
    ledger['runtime_wrapper']=str(wrapper.relative_to(root))
    ledger['status']='imported_pending_validation'
    if args.skip_validation:
        ledger['status']='imported_unverified_user_requested'
        ledger['validation_status']='skipped_by_user'
        ledger['validation']=[]
        ledger['validation_note']='本次用户明确要求不进行验收和验证，直接导入交付。'
    ledger['runtime_files']=[{'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [wrapper,head_path]]
    ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
    print('CHARACTER_WRAPPER_READY',wrapper)

if __name__=='__main__': main()
