"""Record the explicit unverified v010 delivery and its retained v009 dependencies."""
from pathlib import Path
import hashlib
import json

root=Path(__file__).resolve().parents[2]
base=root/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
path=base/'v010/character_transfer_ledger_v010.json'
ledger=json.loads(path.read_text())
ledger.update(status='integrated_unverified_user_requested', validation_status='skipped_by_user',
              active_consumer='scenes/Player3D.tscn', validation=[],
              validation_note='用户明确要求不进行验收和验证，直接导入交付；不继承v009的通过结论。',
              redesigned_clips=['idle','moving','armed_idle','armed_moving'],
              retained_state_clips=['dashing','hurt','locked','falling','landing','dead'],
              model_change='Geometry, topology, UV, material slots and proportions unchanged; rigid weights rebound.',
              binding={'body':'waist','head':'head','hands':'hand_l / hand_r','feet':'foot_l / foot_r','ears':'ear_l / ear_r','unweighted':'chest, upper_arm, forearm, thigh, shin, thumb, index, fingers'},
              transition_seconds=.18)
dependency=base/'v009/exports/anim_bunny01_library_v009.json'
ledger['dependencies']=[{'path':str(dependency.relative_to(root)),'sha256':hashlib.sha256(dependency.read_bytes()).hexdigest(),'purpose':'retained six state clips'}]
ledger['presentation_code']=[{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest()} for p in ['src/player3d/CharacterMotionLibrary3D.gd','src/player3d/PlayerAvatar3D.gd']]
path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('V010_DELIVERY_RECORDED_UNVERIFIED')
