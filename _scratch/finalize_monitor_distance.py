from pathlib import Path
s=Path('_scratch/finalize_monitor034.py').read_text(encoding='utf-8')
s=s.replace('_scratch/monitor034_ledger','_scratch/monitor_distance_ledger').replace("'room_flow_checks':25","'room_flow_checks':29,'activation_distance_m':10").replace('Add activation clip/ownership, preserve old motion, correct static keyboard grip.','10 world meter activation gate; full intro before battle.')
exec(compile(s,'finalize_monitor_distance','exec'))
