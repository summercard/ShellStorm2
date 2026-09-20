from pathlib import Path
P=Path(__file__).parent
s=(P/'verify_animations.py').read_text(encoding='utf-8').replace("P/'animation_meta.json'","P/'animation_meta_v002.json'").replace("P/'animation_frames'","P/'animation_frames_v002'").replace("P/'animation_validation.json'","P/'animation_validation_v002.json'")
exec(compile(s,str(P/'verify_animations.py'),'exec'))
