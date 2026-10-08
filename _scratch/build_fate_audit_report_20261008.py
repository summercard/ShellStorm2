from pathlib import Path
import json, re, html, hashlib
base = Path('I:/工作项目/shellstrom2/ShellStorm2')
out = base / 'outputs/fate_effect_audit_20261008'
rows = json.loads((out / 'audit_rows.json').read_text(encoding='utf-8'))
runtime = json.loads((out / 'runtime_observations.json').read_text(encoding='utf-8'))
catalog = {c['id']: c for c in runtime['catalog']}
assert len(rows) == len(catalog) == 48
assert {r['id'] for r in rows} == set(catalog)
tests = json.loads((out / 'test_results.json').read_text(encoding='utf-8'))
markers = {'consumer_probe': 'FATE_EFFECT_AUDIT_PROBE_DONE', 'tarot_runtime': 'TAROT_FATE_RUNTIME_OK', 'celestial_scope': 'CELESTIAL_FATE_SCOPE_FLOW_OK', 'weapon_adapter': '3D_FATE_WEAPON_FLOW_OK'}
for t in tests:
    text = (out / (t['name'] + '.log')).read_text(encoding='utf-8-sig', errors='replace')
    t['marker_found'] = markers[t['name']] in text
    t['unexpected_errors'] = [line for line in text.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR' in line or 'Parse Error' in line or 'leaked at exit' in line]
    t['warnings'] = len([line for line in text.splitlines() if 'WARNING:' in line])
(out / 'verified_test_results.json').write_text(json.dumps(tests, ensure_ascii=False, indent=2), encoding='utf-8')
design = (base / 'docs/v0.1/14_技术施工_命运塔罗牌组.md').read_text(encoding='utf-8-sig')
design_by_id = {}
missing = []
for line in design.splitlines():
    if not line.startswith('|'):
        continue
    cells = [x.strip() for x in line.strip('|').split('|')]
    ids = [(i, re.fullmatch(r'`(fate_[a-z_]+)`', cell)) for i, cell in enumerate(cells)]
    ids = [(i, m.group(1)) for i, m in ids if m]
    if not ids:
        continue
    i, id = ids[0]
    if i + 2 >= len(cells):
        continue
    design_by_id[id] = {'name': cells[1] if i == 3 else cells[0], 'upright': cells[i+1], 'reversed': cells[i+2]}
    if id not in catalog:
        missing.append({'id': id, **design_by_id[id]})
assert len(missing) == 30
files = ['src/weapons/FateCard.gd', 'src/weapons/FateCardPresets.gd', 'src/weapons/TarotFateCatalog.gd', 'src/weapons/FateCardEngine.gd', 'src/weapons/AssemblyNode.gd', 'src/weapons/WeaponAssemblyTree.gd', 'src/game/FateCardGameBridge.gd', 'src/game/MapFateTriggers.gd', 'src/player3d/Player3D.gd', 'src/combat3d/WeaponModel3D.gd', 'src/combat3d/Projectile3D.gd', 'src/enemy3d/Enemy3D.gd', 'src/world3d/Dungeon3D.gd', 'docs/v0.1/14_技术施工_命运塔罗牌组.md', 'docs/v0.1/04_技术施工_战斗与局内成长.md']
snapshot = [{'path': f, 'sha256': hashlib.sha256((base/f).read_bytes()).hexdigest()} for f in files]
(out / 'source_snapshot.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding='utf-8')
H = lambda x: html.escape(str(x))
status_class = {'主链存在':'good', '部分/偏差':'partial', '触发受限':'partial', '规则不符':'bad', '无设计效果':'bad'}
body = []
for row in rows:
    c = catalog[row['id']]
    d = design_by_id[row['id']]
    diff_note = ''
    if row['id'] in ['fate_sun_extra_loot', 'fate_extra_loot', 'fate_lucky_chest', 'fate_sun_quality']:
        diff_note = '<p class="note">掉落口径：04 §21 的单件候选择优覆盖旧加件描述；原表文字与当前 Catalog 部分仍漂移，不能以地面只有一件直接判错。</p>'
    if row['id'] == 'fate_reinforce':
        diff_note = '<p class="note">触发口径：14 §5.4 的2026-10-08裁定保留抽卡立即追加路径，和同节旧“五连杀”文字不一致。缺少五杀不独立作为已裁定缺陷；但清房抽牌成功无增援，以及逆位精英/奖魂缺失是独立事实。</p>'
    proof = '<span class="proof">针对性运行证据</span>' if row.get('probe') else '<span class="proof static">静态消费者追踪</span>'
    body.append(f'''<article class="card" data-scope="{H(c['scope'])}" data-text="{H(c['name']+' '+row['id']+' '+row['ua']+' '+row['ra'])}">
<header><div><h3>{H(c['name'])}</h3><code>{H(row['id'])}</code></div><span class="scope">{H(c['scope'])}</span>{proof}</header>
<div class="sides"><section><h4>正位 <span class="badge {status_class[row['u']]}">{H(row['u'])}</span></h4><p class="target"><b>原表目标：</b>{H(d['upright'])}</p><p><b>实际：</b>{H(row['ua'])}</p></section><section><h4>逆位 <span class="badge {status_class[row['r']]}">{H(row['r'])}</span></h4><p class="target"><b>原表目标：</b>{H(d['reversed'])}</p><p><b>运行卡面：</b>{H(c['reversed_description'])}</p><p><b>实际：</b>{H(row['ra'])}</p></section></div>{diff_note}<footer>源码：{H(row['source'])}</footer></article>''')
missing_html = ''.join(f'<tr><td>{H(m["name"])}</td><td><code>{H(m["id"])}</code></td><td>{H(m["upright"])}</td><td>{H(m["reversed"])}</td></tr>' for m in missing)
test_html = ''.join(f'<tr><td>{H(t["name"])}</td><td>{t["exit_code"]}</td><td>{"有" if t["marker_found"] else "无"}</td><td>{len(t["unexpected_errors"])}</td><td>{t["warnings"]}</td></tr>' for t in tests)
obs_html = ''.join(f'<details><summary>{H(o["check"])}</summary><pre>{H(json.dumps(o["values"], ensure_ascii=False, indent=2))}</pre></details>' for o in runtime['observations'])
page = '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ShellStorm2 命运卡实际效果审计</title><style>
:root{color-scheme:light;--bg:#f5f7fa;--ink:#182334;--muted:#586879;--line:#dce3eb;--blue:#2365b2}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1240px;margin:auto;padding:42px 24px}h1{font-size:32px;margin:8px 0}h2{margin-top:32px;font-size:23px}h3{font-size:20px;margin:0}h4{margin:0 0 12px;font-size:17px}p{margin:8px 0}.lead{font-size:17px;color:#40536b}.eyebrow{font-size:12px;font-weight:700;letter-spacing:1px;color:var(--blue)}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:24px 0}.stat,.panel{border:1px solid var(--line);background:#fff;border-radius:12px;padding:18px}.stat strong{display:block;font-size:30px}.stat span{color:var(--muted)}.alert{background:#fff3e7;border:1px solid #ecd0ad;border-radius:10px;padding:16px 20px}.findings li{padding:4px 0}.controls{position:sticky;top:0;background:#f5f7faf2;backdrop-filter:blur(8px);z-index:3;padding:14px 0;display:flex;flex-wrap:wrap;gap:9px;align-items:center}input{padding:10px 14px;border:1px solid #bdcbdc;border-radius:8px;flex:1;min-width:180px;font:inherit}button{background:#fff;border:1px solid #bdcbdc;border-radius:8px;padding:9px 14px;color:var(--ink);cursor:pointer;font:inherit}button.active{background:#e5effe;border-color:#2365b2;color:#175396}.card{background:#fff;border:1px solid var(--line);border-radius:12px;margin:15px 0;overflow:hidden}.card header{display:flex;align-items:center;gap:14px;padding:18px 22px;border-bottom:1px solid var(--line);flex-wrap:wrap}.card header>div{flex:1}.scope{font-size:12px;font-weight:700;color:#485e77;background:#eef3f8;padding:4px 10px;border-radius:5px}.proof{font-size:12px;color:#18549b}.proof.static{color:var(--muted)}code{font-family:Consolas,monospace;font-size:12px;color:#4f6177;overflow-wrap:anywhere}.sides{display:grid;grid-template-columns:1fr 1fr}.sides section{padding:18px 22px}.sides section+section{border-left:1px solid var(--line)}.badge{font-size:12px;font-weight:500;padding:4px 8px;border-radius:5px;margin-left:8px;display:inline-block}.good{background:#e6f4ed;color:#24654a}.partial{background:#fff3da;color:#805a14}.bad{background:#fae8e8;color:#983d3d}.target{color:var(--muted)}.note{margin:0;padding:14px 22px;background:#eef5fe;color:#355276;font-size:13px}.card footer{font-size:12px;color:var(--muted);padding:12px 22px;background:#fafbfd;border-top:1px solid var(--line)}table{width:100%;border-collapse:collapse;background:#fff;font-size:14px}th,td{border:1px solid var(--line);text-align:left;vertical-align:top;padding:10px}th{background:#edf2f8}.scroll{overflow-x:auto}details{background:#fff;border:1px solid var(--line);border-radius:8px;margin:8px 0;padding:10px 15px}summary{cursor:pointer;font-weight:600}pre{font:13px/1.55 Consolas,monospace;overflow-x:auto;background:#f3f6fa;padding:15px}.small{font-size:13px;color:var(--muted)}a{color:var(--blue)}.hidden{display:none}@media(max-width:750px){.stats{grid-template-columns:1fr 1fr}.sides{grid-template-columns:1fr}.sides section+section{border-left:0;border-top:1px solid var(--line)}main{padding:24px 14px}h1{font-size:26px}}@media print{.controls{display:none}.card{break-inside:avoid}.hidden{display:block}body{background:white}}
</style></head><body><main><div class="eyebrow">FATE-RULES · 0.1.0 · 2026-10-08 工作区快照</div><h1>命运卡：哪些真的生效？</h1><p class="lead">对照设计表和正式执行链，拆开正位、逆位；不把卡面、参数快照或 success=true 当作玩法已经兑现。</p>
<div class="stats"><div class="stat"><strong>78</strong><span>目标设计牌数</span></div><div class="stat"><strong>48</strong><span>当前运行池身份</span></div><div class="stat"><strong>96</strong><span>本次逐一审查的方位</span></div><div class="stat"><strong>30</strong><span>设计存在但未入池</span></div></div>
<div class="alert"><b>结论：</b>不是“48张全部有效”。有真实主链，也有仅部分数值生效、触发被挡住、效果方向错误和记录成功却没有实际改变。逆位问题尤其集中。这里的“主链存在”只表示找到真实末端消费，不是完整端到端验收通过，也不代表叠牌/读档/多场景无缺陷。</div>
<section class="panel" style="margin-top:20px"><h2 style="margin-top:0">最重要的实测结果</h2><ul class="findings"><li><b>女祭司逆位：</b>HP上限100→100，当前HP50→50，没有−10上限或恢复50。</li><li><b>恋人逆位：</b>状态记录0.92，但正式武器伤害14→14，实际倍率仍1。</li><li><b>太阳／正义／世界逆位：</b>相关魂、下房敌伤、下房魂、撤离倍率均保持1。</li><li><b>权杖·王牌逆位：</b>缩放0.75有效，但伤害14→17、弹速18.4→18.4；不是减伤20%、提速25%。</li><li><b>新敌对房 main_01：</b>进房HP50→50、弹匣0→0；直接调用同一消费者才回到56HP和20发。问题在进房事件接线。</li><li><b>清房抽星币·王牌：</b>返回成功，但增援队列0→0。</li><li><b>圣杯·五逆位：</b>90%血不触发、50%血触发+8%，高血收益被执行成低血收益。</li></ul></section>
<h2>审计边界与设计裁决</h2><p>主对照为 <code>docs/v0.1/14_技术施工_命运塔罗牌组.md</code>，并结合 <code>04_技术施工_战斗与局内成长.md</code> 的后续规则；本轮没有直接读写XLSX账本，不冒称完成逐格账本校验。</p><p><b>掉落：</b>04 §21 明确单件结算，额外掉落改为追加候选择优。皇后与星币·三“只落一件”不是缺陷；实际按 loot_table_tier 排序，稀有度保证、逆位稀有上限或升品仍存在缺口。</p><p><b>增援：</b>14 §5.4 的2026-10-08新裁定保留抽卡立即追加路径，与同节旧“五连杀”说明冲突。需要协调文案与时机，不能自行恢复旧环境自动增援。清房选卡拒绝、精英与奖魂缺失独立于该冲突。</p><p><b>状态描述：</b>14 §8 的“48张可玩牌双向执行通过”超出了现有测试实际覆盖。三个现成专项全通过，与本次实测缺陷并不矛盾。</p>
<h2>48张正逆位逐卡对照</h2><p class="small">主链存在＝有末端消费者；部分/偏差＝只实现部分或数值不符；触发受限＝入口/场景限制；规则不符＝真实有变化但不是设计规则；无设计效果＝没有兑现目标。运行标记表示该卡有针对性证据，不代表该卡全部行为都实测。</p>
<div class="controls"><input id="search" placeholder="搜索卡名、ID、问题关键词" aria-label="搜索卡牌"><button class="active" data-filter="ALL">全部48</button><button data-filter="WEAPON">枪械22</button><button data-filter="CHARACTER">角色12</button><button data-filter="WORLD">世界14</button><span id="shown" class="small"></span></div><div id="cards">''' + ''.join(body) + '''</div>
<h2>30张设计已登记、当前未入运行池</h2><p>宝剑全部14张；圣杯·六至国王9张；星币·八至国王7张。这是已知待施工范围，不混入48张执行错误统计。</p><div class="scroll"><table><thead><tr><th>名称</th><th>stable_card_id</th><th>正位设计</th><th>逆位设计</th></tr></thead><tbody>''' + missing_html + '''</tbody></table></div>
<h2>运行证据与测试边界</h2><p>Godot 4.6.3，启动前各进程独立设置 APPDATA / LOCALAPPDATA；不使用真实存档。headless 只核查数值、状态及直接消费者，不证明渲染、输入操作或完整战斗平衡。探针暂停自动过程，用真实桥接和消费者调用采样。</p><div class="scroll"><table><thead><tr><th>入口</th><th>退出码</th><th>完成标记</th><th>非预期错误</th><th>警告</th></tr></thead><tbody>''' + test_html + '''</tbody></table></div>
<p>tarot_runtime：身份、名称、方位参数、概率及环境战斗旁路禁用；celestial_scope：角色/世界状态与部分搜索/下一房消费；weapon_adapter：行为字段、射速与相对缩放。<b>没有96方位的真实末端效果全覆盖。</b>consumer_probe退出0仅代表观测完成，不是设计一致性通过。</p>''' + obs_html + '''
<p class="note"><b>工程文档总门禁未通过：</b>本轮重跑仍发现4个范围外未注册用例（verify_base99_swivel_chairs、verify_expedition01_spawn_ramp、verify_expedition_resume_entry、verify_pushable_base_chairs），以及媒体检查子进程缺少 openpyxl。未修改这些依赖或注册项；这不影响四份命运专项的完成标记与零非预期错误，但不能宣称全工程门禁通过。日志见 documentation_contracts.log。</p><h2>优先处理建议（本轮未修）</h2><ol><li><b>先收口空效果与反向效果：</b>女祭司、恋人、正义、太阳、世界逆位；圣杯·五血线方向；星币·四逆位字段错配。</li><li><b>修正式事件接线：</b>进房回血/补弹/首次伤害重置；明确清房选卡后的增援与当前房诅咒如何落地，不改回环境白送。</li><li><b>修字段消费契约：</b>伤害比例、弹速、主副枪交替、换弹首发、移动炮台、折返补弹、最远追踪等不能只留快照。</li><li><b>修共用状态与越权：</b>无王后也加必暴；火冰毒共享错误DOT；混合增伤取最大、赏金串档、附枪聚合污染。</li><li><b>补逐卡末端验收：</b>每方位测实际HP/伤害/弹药/掉落/触发条件，并增加未持牌反向对照、叠牌和读档。未补前不再用“48双向通过”描述玩法完成度。</li></ol>
<h2>交付文件与源定位</h2><p>报告：<code>命运卡实际效果审计.html</code>；机器可读对照：<code>audit_rows.json</code>；观测与运行卡面参数：<code>runtime_observations.json</code>；测试核验：<code>verified_test_results.json</code>；源文件哈希：<code>source_snapshot.json</code>。所有文件位于本报告同目录，日志保留 consumer_probe / tarot_runtime / celestial_scope / weapon_adapter 四份。</p><p>源码表内：引擎与节点位于 <code>src/weapons/</code>；武器和弹体位于 <code>src/combat3d/</code>；玩家 <code>src/player3d/Player3D.gd</code>；世界 <code>src/world3d/Dungeon3D.gd</code>；敌人 <code>src/enemy3d/Enemy3D.gd</code>；桥接/环境触发位于 <code>src/game/</code>。</p><p class="small">本轮只增加审计探针和证据文件，不修改命运玩法、设计正文、内容账本或现成专项。哈希为报告制作时快照，不是未来工作区的永久有效凭据。未运行全验收套件、真实渲染、逐卡叠牌/存档回读；未实测的末端行为仍明确为静态追踪。</p></main><script>
let scope='ALL';const search=document.getElementById('search'),cards=[...document.querySelectorAll('.card')];function update(){const q=search.value.toLowerCase().trim();let n=0;cards.forEach(c=>{let show=(scope==='ALL'||c.dataset.scope===scope)&&c.dataset.text.toLowerCase().includes(q);c.classList.toggle('hidden',!show);if(show)n++});document.getElementById('shown').textContent='显示 '+n+' 张'}search.addEventListener('input',update);document.querySelectorAll('button[data-filter]').forEach(b=>b.addEventListener('click',()=>{scope=b.dataset.filter;document.querySelectorAll('button[data-filter]').forEach(x=>x.classList.toggle('active',x===b));update()}));update();
</script></body></html>'''
(out / '命运卡实际效果审计.html').write_text(page, encoding='utf-8')
print(json.dumps({'rows':len(rows), 'missing':len(missing), 'scopes': {s:sum(c['scope']==s for c in catalog.values()) for s in ['WEAPON','CHARACTER','WORLD']}, 'tests':tests, 'output':str(out/'命运卡实际效果审计.html')}, ensure_ascii=False, indent=2))
