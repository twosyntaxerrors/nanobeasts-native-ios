from pathlib import Path
import re
p=Path(__file__).parent/'index.html'
s=p.read_text().replace('<strong>ALEX</strong>','<strong>SINATRA</strong>')
assert 'id="stats-page"' not in s
css='''
/* Stats uses the same current-app hierarchy as the Home and Dex demo views. */
.stats-viewport{position:absolute;left:0;top:72px;bottom:126px;width:552px;overflow:hidden;mask-image:linear-gradient(to bottom,transparent,black 12px,black calc(100% - 14px),transparent)}
.stats-scroll{width:100%;padding:8px 25px 25px;display:flex;flex-direction:column;gap:24px}
.stats-title{font:37px Aldrich;letter-spacing:2.2px;margin:0 0 8px}.stats-subtitle{font:18px Aldrich;color:var(--muted)}
.history-card{padding:24px;border:1.5px solid #59e5d369;border-radius:30px;background:linear-gradient(125deg,#59e5d323,#18181b 80%)}.history-head{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}.history-head label{font:17px Aldrich;letter-spacing:2px;color:var(--teal)}.history-total{font:54px Aldrich;margin:11px 0;line-height:1.05;font-variant-numeric:tabular-nums}.history-head small{font:14px Aldrich;color:var(--muted);letter-spacing:1.1px}.history-icon{flex-shrink:0;width:74px;height:74px;padding:18px;background:#59e5d311;border:1.5px solid #59e5d369;border-radius:24px;color:var(--teal)}.history-icon svg{width:100%;height:100%}.history-metrics{display:flex;gap:18px;padding:22px 0;border-top:1px solid #59e5d335;border-bottom:1px solid #59e5d335;margin-top:23px}.history-metric{flex:1;display:flex;gap:12px;align-items:center}.history-metric+.history-metric{border-left:1px solid #59e5d345;padding-left:17px}.history-metric svg{width:27px;height:27px;flex-shrink:0;color:var(--teal)}.history-metric b{font:28px Aldrich;white-space:nowrap}.history-metric b small{font:14px Aldrich;color:var(--muted)}.history-metric label{font:11px Aldrich;letter-spacing:.8px;color:#a1a1aa;display:block;margin-top:4px}.badge-meter{margin-top:21px}.badge-meter .meter-label{display:flex;justify-content:space-between;font:15px Aldrich;letter-spacing:1px;color:var(--muted)}.badge-meter .meter-label span:last-child{color:var(--teal)}.badge-meter .progress{height:9px;margin-top:11px}.badge-meter .fill{width:42.1875%}
.consistency-row{display:flex;align-items:center;justify-content:space-between;gap:12px;font:19px Aldrich;letter-spacing:.8px}.month-switch{display:flex;align-items:center;border:1px solid #33383a;background:#18181b;padding:4px;border-radius:26px;font:14px Aldrich;letter-spacing:0}.month-switch span{padding:12px 14px;color:var(--muted)}.month-switch .on{color:#09090b;background:var(--teal);border-radius:23px}
.calendar-card{border:1.5px solid #59e5d343;background:#18181b;border-radius:30px;padding:23px}.month-name{display:flex;align-items:center;justify-content:space-between;font:27px Aldrich;margin-bottom:22px}.month-arrow{display:flex;align-items:center;justify-content:center;background:#242527;width:39px;height:39px;border-radius:12px;font:32px NanoText}.calendar-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:7px}.calendar-weekday{font:15px Aldrich;color:var(--teal);text-align:center;padding-bottom:8px}.calendar-cell{height:58px;border-radius:14px;border:1px solid #59e5d355;background:#59e5d321;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;transform-origin:center}.calendar-cell b{font:20px Aldrich}.calendar-cell small{font:12px Aldrich;color:var(--teal)}.calendar-cell.hit{background:var(--teal);border-color:var(--teal);color:#09090b}.calendar-cell.hit small{color:#12312d}.calendar-cell.medium{background:#59e5d34d}.calendar-blank{height:58px}
.insights-card{padding:24px;border:1.5px solid #59e5d363;border-radius:30px;background:linear-gradient(120deg,#59e5d313,#18181b 85%)}.insights-head{display:flex;justify-content:space-between;align-items:center}.insights-head h3{font:29px Aldrich;margin:0 0 7px}.insights-head p{font:14px/1.45 NanoText;color:var(--muted);margin:0}.insights-chevron{display:grid;place-items:center;width:41px;height:41px;border:1px solid #59e5d349;border-radius:50%;color:var(--teal);background:#59e5d317;font:27px NanoText}.insight-range{display:flex;gap:5px;padding:4px;background:#09090bbb;border:1px solid #353639;border-radius:28px;margin-top:23px}.insight-range span{flex:1;padding:14px 0;text-align:center;font:15px Aldrich;color:var(--muted)}.insight-range .on{background:var(--teal);border-radius:24px;color:#09090b}.average{margin-top:23px}.average label{display:block;font:15px Aldrich;letter-spacing:1px;color:var(--muted)}.average strong{font:55px Aldrich;display:inline-block;margin:7px 0 5px;font-variant-numeric:tabular-nums}.average em{font:19px Aldrich;font-style:normal;color:var(--muted);margin-left:8px}.average small{display:block;font:13px NanoText;color:var(--muted)}
.insight-chart{position:relative;margin-top:25px;padding-left:32px;height:260px}.chart-axis{position:absolute;left:0;top:0;height:224px;width:27px;display:flex;flex-direction:column;justify-content:space-between;font:12px Aldrich;color:#a1a1aa}.chart-plot{position:relative;width:100%;height:224px;border-bottom:1px solid #59676066}.chart-grid{position:absolute;inset:0;background:repeating-linear-gradient(to top,transparent 0,transparent 110px,#ffffff0c 111px,#ffffff0c 112px)}.insight-bars{display:flex;justify-content:space-around;align-items:flex-end;width:100%;height:100%;gap:14px;padding:0 8px}.insight-bar{width:36px;flex-shrink:0;border-radius:5px 5px 0 0;background:var(--teal);transform-origin:bottom}.insight-bar.under{background:#59e5d36b}.goal-rule{position:absolute;left:0;right:0;bottom:124.444px;border-top:1.5px dashed #fb7716d9;transform-origin:left}.goal-rule span{position:absolute;right:2px;top:-23px;color:#ffa669;font:11px Aldrich;background:#18181b;padding-left:4px}.chart-days{display:flex;justify-content:space-around;margin-top:10px;font:13px Aldrich;color:#a1a1aa}.insight-comparison{display:flex;gap:12px;align-items:flex-start;margin-top:24px}.insight-comparison .arrow{color:var(--teal);background:#59e5d31e;border-radius:50%;width:36px;height:36px;display:grid;place-items:center;flex-shrink:0;font:26px NanoText}.insight-comparison p{font:18px/1.5 NanoText;margin:0}.insight-metrics{display:flex;gap:12px;margin-top:24px}.insight-metric{flex:1;border:1px solid #303333;background:#09090b88;border-radius:20px;padding:18px 15px}.insight-metric label{display:block;font:13px Aldrich;letter-spacing:.7px;color:var(--muted)}.insight-metric strong{font:29px Aldrich;display:block;margin:10px 0}.insight-metric small{font:12px/1.45 NanoText;display:block;color:var(--muted)}.best-day{display:flex;gap:11px;font:15px NanoText;color:#b5babe;margin-top:23px}.best-day span{color:#fb9b3c}.stats-status{position:absolute;top:0;left:0;right:0;background:#09090b;z-index:2}.stats-note{font:17px Aldrich;letter-spacing:1.5px;color:var(--teal);padding:3px 0 12px}
'''
s=s.replace('</style>',css+'\n</style>')
s=s.replace('data-duration="20"','data-duration="27"')
headline='<h1 id="hstats" class="headline later" data-layout-allow-overlap><span>Reach your goals</span><span class="accent">with personalized insights.</span></h1>\n'
s=s.replace('<div class="phone-wrap" id="phone">',headline+'<div class="phone-wrap" id="phone">')
# Reuse the actual demo navigation with Stats selected.
nav=re.findall(r'<div class="nav">.*?</div></div>\n',s)[0]
nav=nav.replace('<div class="selected">','<div>',1).replace('<div><span class="nav-symbol"><svg viewBox="0 0 32 32" fill="currentColor"><rect x="2" y="17"','<div class="selected"><span class="nav-symbol"><svg viewBox="0 0 32 32" fill="currentColor"><rect x="2" y="17"',1)
bar_icon='<svg viewBox="0 0 32 32" fill="currentColor"><rect x="2" y="17" width="8" height="13" rx="2"/><rect x="12" y="10" width="8" height="20" rx="2"/><rect x="22" y="3" width="8" height="27" rx="2"/></svg>'
# Example calendar, preserving the physical capture's visible August pattern.
values=[13000,790,4900,5300,5700,7100,958,2200,2400,1400,1200,923,1000,3100,271,5600,11000,4700,6000,1800,3100,6900,3000,4200,4700,6500,5700,8200,7100,6900,5000]
cal=''.join(f'<div class="calendar-weekday">{x}</div>' for x in 'SMTWTFS')+'<div class="calendar-blank"></div>'*6
for d,v in enumerate(values,1):
 cls=' hit' if v>=5000 else ' medium' if v>=3000 else ''
 txt=f'{v/1000:g}K' if v>=1000 else str(v)
 cal+=f'<div class="calendar-cell{cls}"><b>{d}</b><small>{txt}</small></div>'
weekly=[4700,6500,5700,8200,7100,6900,5000]
bars=''.join(f'<div class="insight-bar{ " under" if v<5000 else ""}" style="height:{v/9000*224:.3f}px"></div>' for v in weekly)
page=f'''
  <div class="page app-grid later" id="stats-page">
   <div class="status stats-status" data-layout-allow-overlap><span>9:41</span><span class="status-right">▮▮▮ ▰</span></div>
   <div class="stats-viewport" data-layout-allow-overflow>
    <div class="stats-scroll" id="stats-scroll">
     <div><h2 class="stats-title">ACTIVITY STATS</h2><div class="stats-subtitle">Your movement powers evolution.</div></div>
     <div class="history-card">
      <div class="history-head"><div><label>MOVEMENT HISTORY</label><div class="history-total" id="history-total">135,971</div><small>SINCE JUL 31, 2026</small></div><div class="history-icon">{bar_icon}</div></div>
      <div class="history-metrics"><div class="history-metric"><svg viewBox="0 0 32 32" fill="currentColor"><path d="M27 3 4 13a2 2 0 0 0 1 4h10v10a2 2 0 0 0 4 1L29 5a2 2 0 0 0-2-2Z"/></svg><div><b>64.4 <small>MI</small></b><label>TOTAL DISTANCE</label></div></div><div class="history-metric"><svg viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="3" y="6" width="26" height="23" rx="4"/><path d="M3 13h26M10 3v6M22 3v6M9 18h3m5 0h3m5 0h1M9 24h3m5 0h3"/></svg><div><b>40</b><label>DAYS TRACKED</label></div></div></div>
      <div class="badge-meter"><div class="meter-label"><span>BADGE COLLECTION</span><span>27/64</span></div><div class="progress"><div class="fill" id="stats-badge-fill"></div></div></div>
     </div>
     <div class="consistency-row">ACTIVITY CONSISTENCY<div class="month-switch"><span class="on">MONTH</span><span>WEEK</span></div></div>
     <div class="calendar-card"><div class="month-name"><span class="month-arrow">‹</span>August 2026<span class="month-arrow">›</span></div><div class="calendar-grid">{cal}</div></div>
     <div class="insights-card" id="insights-card">
      <div class="insights-head"><div><h3>Step insights</h3><p>Your movement trends and goal history.</p></div><div class="insights-chevron">⌃</div></div>
      <div class="insight-range"><span class="on">WEEK</span><span>MONTH</span><span>YEAR</span></div>
      <div class="average"><label>DAILY AVERAGE</label><strong id="average-steps">6,300</strong><em>steps</em><small>Last 7 days</small></div>
      <div class="insight-chart"><div class="chart-axis"><span>9K</span><span>4.5K</span><span>0</span></div><div class="chart-plot"><div class="chart-grid"></div><div class="insight-bars">{bars}</div><div class="goal-rule" id="goal-rule"><span>GOAL · 5,000</span></div></div><div class="chart-days"><span>25</span><span>26</span><span>27</span><span>28</span><span>29</span><span>30</span><span>31</span></div></div>
      <div class="insight-comparison" id="insight-comparison"><span class="arrow">↗</span><p>You're averaging 1,400 more steps per day than the previous 7 days.</p></div>
      <div class="insight-metrics"><div class="insight-metric"><label>TOTAL STEPS</label><strong>44,100</strong><small>Last 7 days</small></div><div class="insight-metric"><label>GOAL DAYS</label><strong>6 of 7</strong><small>Reached 5,000 steps</small></div></div>
      <div class="best-day"><span>★</span>Best day: Friday with 8,200 steps.</div>
     </div>
     <div class="stats-note">YOUR WALKING HABIT, IN FOCUS</div>
    </div>
   </div>
   {nav}
  </div>
'''
s=s.replace('  <div class="page app-grid later" id="dex-page">',page+'  <div class="page app-grid later" id="dex-page">')
s=s.replace('<div class="chapter" id="chapter">','<div id="fstats" class="footer later" data-layout-allow-overlap>See your trends and daily goal history.</div>\n<div class="chapter" id="chapter">')
s=s.replace('rotation:360,duration:20','rotation:360,duration:27').replace('duration:10,yoyo:true','duration:13.5,yoyo:true').replace('duration:19.25,ease:', 'duration:26.25,ease:')
s=s.replace("exchange('#route-page','#dex-page','#h3','#h4','#f3','#f4',14.65);", "exchange('#route-page','#stats-page','#h3','#hstats','#f3','#fstats',14.65);\nexchange('#stats-page','#dex-page','#hstats','#h4','#fstats','#f4',21.65);")
s=s.replace("},15);", "},22);").replace("},16.7);", "},23.7);").replace("},16.75);", "},23.75);")
s=s.replace(",19.25);", ",26.25);").replace(",19.35);", ",26.35);")
s=s.replace("tl.to(chapter,{n:4,duration:0},14.65);", "tl.to(chapter,{n:4,duration:0},14.65);tl.to(chapter,{n:5,duration:0},21.65);")
s=s.replace("'03 / EXPLORE','04 / COLLECT'", "'03 / EXPLORE','04 / INSIGHTS','05 / COLLECT'")
# Use current panel offsets for a native-looking continuous scroll.
anim='''
const insightOffset=document.getElementById('insights-card').offsetTop-10;
const movement={total:118420,average:4900};
const updateMovement=()=>{document.getElementById('history-total').textContent=Math.round(movement.total).toLocaleString('en-US');document.getElementById('average-steps').textContent=Math.round(movement.average).toLocaleString('en-US');};
tl.to(movement,{total:135971,duration:1.25,ease:'power2.out',onUpdate:updateMovement},14.95);
tl.fromTo('#stats-badge-fill',{scaleX:0},{scaleX:1,duration:1.15,ease:'power3.out'},15.05);
tl.fromTo('.calendar-cell',{opacity:.2,scale:.9},{opacity:1,scale:1,duration:.45,stagger:.018,ease:'power2.out'},15.1);
tl.fromTo('#stats-scroll',{y:0},{y:-insightOffset,duration:1.05,ease:'power3.inOut'},17.3);
tl.to(movement,{average:6300,duration:1.1,ease:'power2.out',onUpdate:updateMovement},18.35);
tl.fromTo('.insight-bar',{scaleY:0},{scaleY:1,duration:.9,stagger:.075,ease:'power3.out'},18.35);
tl.fromTo('#goal-rule',{scaleX:0,opacity:0},{scaleX:1,opacity:1,duration:.75,ease:'power2.out'},18.6);
tl.fromTo('#insight-comparison',{opacity:0,y:16},{opacity:1,y:0,duration:.5,ease:'power3.out'},19.15);
'''
s=s.replace('window.__timelines.main=tl;',anim+'\nwindow.__timelines.main=tl;')
p.write_text(s)
print('Inserted Stats and Insights, renamed Sinatra, extended to 27 seconds.')
