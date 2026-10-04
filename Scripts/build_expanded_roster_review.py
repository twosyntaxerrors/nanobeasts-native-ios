#!/usr/bin/env python3
"""Build a local, single-animation-at-a-time gallery for the staged roster."""
import json
from pathlib import Path
from prepare_expanded_roster_animations import ROSTER, REVIEW, manifest

records=[]
for item in manifest():
    p=Path(item['folder'])/f"{item['key']}.json"
    if p.exists(): records.append(json.loads(p.read_text()))
REVIEW.mkdir(exist_ok=True)
(REVIEW/'asset-verification.json').write_text(json.dumps(records,indent=2)+'\n')
families=json.loads((ROSTER/'names-and-lore.json').read_text())['families']
(REVIEW/'families.json').write_text(json.dumps(families,indent=2)+'\n')
html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Nanobeasts · Animation review</title><style>
*{box-sizing:border-box}body{margin:0;background:#09090f;color:#eeeaf9;font:15px system-ui;padding:28px 20px}main{max-width:1060px;margin:auto}h1{font-size:28px;margin:8px 0}p{color:#b5acc6;line-height:1.5}.layout{display:grid;grid-template-columns:240px minmax(0,1fr);gap:24px;margin-top:22px}.stage{width:min(100%,480px,60vh);display:grid;place-items:center;border:1px solid #42375e;border-radius:28px;aspect-ratio:1;background:#0c0c12;overflow:hidden}.stage img{width:100%;height:100%;object-fit:contain;display:block}.controls{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}button,select,a{color:inherit}button,select{border:1px solid #58466f;border-radius:18px;padding:10px 14px;background:#1c162b;cursor:pointer}button[aria-pressed=true]{background:#a98cf0;color:#110b20}select{width:100%;border-radius:12px;font-size:15px}#clips{display:flex;flex-direction:column;gap:8px;margin-top:16px}#clips button{text-align:left;border-radius:12px;line-height:1.5}small{color:#aaa0bc}.light{background:#f5f5f5}.checker{background-color:#e2e2e2;background-image:conic-gradient(#bdbdbd 25%,transparent 0 50%,#bdbdbd 0 75%,transparent 0);background-size:32px 32px}.stats{display:flex;gap:20px;flex-wrap:wrap;color:#c9bedc}a{color:#cbb4ff}h2{font-size:20px;margin:0 0 14px}@media(max-width:700px){.layout{grid-template-columns:1fr}#clips{display:grid;grid-template-columns:1fr 1fr;gap:6px}.stage{max-height:70vh}}
</style><main><small>EXPANDED ROSTER · TRANSPARENT ANIMATIONS</small><h1>Animation review</h1><p id="summary">Loading prepared animations…</p><div class="layout"><aside><label for="family">Family</label><select id="family"></select><nav id="clips" aria-label="Animation selection"></nav></aside><section><h2 id="title"></h2><div id="stage" class="stage"><img id="art" alt=""></div><div class="controls"><button data-bg="" aria-pressed="true">App dark</button><button data-bg="light" aria-pressed="false">Light</button><button data-bg="checker" aria-pressed="false">Transparency</button><button id="replay">Replay</button><button id="still">Show still</button></div><div class="stats" id="stats"></div><p><a id="download" download>Download transparent WebP</a></p><small>Idle animations repeat. Hatches and evolutions play once and hold their final frame. Original playback speed is preserved. These approved files are published to R2 and included in the updated app roster.</small></section></div></main><script>
let all=[],families=[],current=null,still=false;
const el=id=>document.getElementById(id),url=p=>'../'+p.split('/').map(encodeURIComponent).join('/');
function label(r){let names=families.find(f=>f.number===r.family).stages.map(s=>s.name);if(r.kind==='egg-idle')return'Egg idle';if(r.kind==='hatch')return'Egg → '+names[0];if(r.kind==='idle')return names.find(n=>r.key===n.toLowerCase()+'-idle')+' · Idle';return r.key.replace('-evolution','').split('-').map(n=>n[0].toUpperCase()+n.slice(1)).join(' → ')}
function show(r){current=r;still=false;el('still').textContent='Show still';el('title').textContent=label(r);el('art').src=url(r.output)+'?play='+Date.now();el('art').alt=label(r);el('download').href=url(r.output);el('stats').innerHTML='<span>480 × 480</span><span>'+r.fps+' fps</span><span>'+(r.duration_ms/1000).toFixed(2)+' seconds</span><span>'+(r.bytes/1048576).toFixed(2)+' MB</span>';document.querySelectorAll('#clips button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.key===r.key)))}
function selectFamily(){const rows=all.filter(r=>r.family===+el('family').value);el('clips').replaceChildren();rows.forEach(r=>{const b=document.createElement('button');b.textContent=label(r);b.dataset.key=r.key;b.onclick=()=>show(r);el('clips').appendChild(b)});if(rows.length)show(rows[0])}
Promise.all([fetch('asset-verification.json').then(r=>r.json()),fetch('families.json').then(r=>r.json())]).then(([a,f])=>{all=a;families=f;el('summary').textContent=all.length+' prepared animations across '+new Set(all.map(r=>r.family)).size+' families. Select a clip to review its motion, edges, and effects.';families.forEach(f=>{const o=document.createElement('option');o.value=f.number;o.textContent=f.number+' · '+f.stages.map(s=>s.name).join(' / ');el('family').appendChild(o)});selectFamily()});
el('family').onchange=selectFamily;el('replay').onclick=()=>current&&show(current);el('still').onclick=()=>{if(!current)return;still=!still;el('art').src=url(still?current.output.replace('.webp','-poster.png'):current.output)+'?play='+Date.now();el('still').textContent=still?'Play animation':'Show still'};document.querySelectorAll('[data-bg]').forEach(b=>b.onclick=()=>{el('stage').className='stage '+b.dataset.bg;document.querySelectorAll('[data-bg]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)))})
</script></html>'''
(REVIEW/'index.html').write_text(html)
print(f'Gallery includes {len(records)} assets.')

# Compact family sheets complement the full dark/light per-clip inspections.
from PIL import Image
(REVIEW/'Contact Sheets').mkdir(exist_ok=True)
for family in families:
    rows=[r for r in manifest() if r['family']==family['number']]
    images=[]
    for record in rows:
        p=REVIEW/'Frames'/f"{record['key']}.jpg"
        if p.exists():images.append(Image.open(p).crop((0,0,1440,255)).resize((1080,192)))
    if images:
        sheet=Image.new('RGB',(1080,192*len(images)))
        for i,im in enumerate(images):sheet.paste(im,(0,192*i))
        sheet.save(REVIEW/'Contact Sheets'/f"family-{family['number']:02}.jpg",quality=93)
