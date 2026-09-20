from pathlib import Path
P=Path(__file__).parent
s=(P/'package_animation.py').read_text(encoding='utf-8').replace("P/'animation_meta.json'","P/'animation_meta_v003.json'").replace('little_zombie_animations_v001','little_zombie_animations_v003').replace("P/'animation_frames'","P/'animation_frames_v003'").replace("P/'animation_validation.json'","P/'animation_validation_v003.json'").replace('animation_transfer_ledger_v001','animation_transfer_ledger_v003').replace('独立动画源 v001','独立动画源 v003')
exec(compile(s,str(P/'package_animation.py'),'exec'))
