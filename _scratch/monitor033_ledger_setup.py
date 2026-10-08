from pathlib import Path
R=Path.cwd();s=(R/'_scratch/prepare_monitor032_ledger.py').read_text(encoding='utf-8').replace('032','033')
a=s.index("note='");b=s.index("\nlr=",a)
s=s[:a]+"note='v033：回到v031原版move，仅底座最大侧翘23°减为10°并重算接地高度。原横移、机身、双臂、腕部节奏保留，1.6s/48帧。其余15剪辑完全不变。源97采样及Godot专项、真实渲染证据见previews/move_v033。远征01投放、四技能、三阶段规则保留。'"+s[b:]
s=s.replace('v033 贴地横移与机身扭转；正式16剪辑/十二态/四技能/三阶段','v033 老版move仅减小底座侧翘；正式16剪辑/十二态/四技能/三阶段').replace('2026-10-08_boss002_grounded_move.md','2026-10-08_boss002_reduced_lift.md')
s=s.replace("s=(R/'_scratch/monitor_spawn_ledger_20261007'/name)","s=(R/'_scratch/monitor032_ledger'/name)").replace("replace('_scratch/monitor_spawn_ledger_20261007','_scratch/monitor033_ledger')","replace('_scratch/monitor032_ledger','_scratch/monitor033_ledger')")
(R/'_scratch/prepare_monitor033_ledger.py').write_text(s,encoding='utf-8')
