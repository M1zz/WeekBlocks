// Builds the English App Store screenshot mockups for Rainbow Workshop (macOS).
//
// The Mac app cannot be built or run here (no macOS/Xcode), so these are
// pixel mockups drawn from the real SwiftUI views: the layout, the strings and
// the palette all come from the source.
//   palette   → WeekBlocks/Theme.swift            (Rainbow, Apple system colors)
//   strings   → WeekBlocks/Localizable.xcstrings  (the "en" side, verbatim)
//   layout    → ContentView / WeekGridView / DayTimelineView / TodoStepsView /
//               TimerView / ReflectionView
//   copy      → docs/STORE_NOTES_1.1.2.txt        (the English description)
//
// Sample data is the app's own onboarding suggestion set: Sleep 23:00+8h daily,
// Meals 17.5h/week in 3 flexible sessions, Work weekdays 09:00+9h, Exercise
// Mon/Wed/Fri 07:30+1h.  Routines 121.5h → 46.5h free of 168.
//
//   node build.mjs          write index.html and render en/*.png
//   node build.mjs --html   write index.html only

import { writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

// Inter stands in for SF Pro, which is not redistributable. Fetched on demand
// (SIL Open Font License) and left out of git — see .gitignore.
const INTER = {
  400:'UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf',
  500:'UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuI6fMZg.ttf',
  600:'UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYMZg.ttf',
  700:'UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZg.ttf',
  800:'UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuDyYMZg.ttf',
}
async function ensureFonts() {
  mkdirSync(join(HERE, 'fonts'), { recursive: true })
  for (const [w, file] of Object.entries(INTER)) {
    const path = join(HERE, 'fonts', `inter-${w}.ttf`)
    if (existsSync(path)) continue
    const url = `https://fonts.gstatic.com/s/inter/v20/${file}`
    console.log('fetching', url)
    const res = await fetch(url)
    if (!res.ok) throw new Error(`Inter ${w} failed: ${res.status}`)
    writeFileSync(path, Buffer.from(await res.arrayBuffer()))
  }
}
await ensureFonts()

// ── icons (SF Symbols redrawn as plain strokes) ─────────────────────────────
const ICONS = {
  moon:      '<path d="M21 12.9A9 9 0 1 1 11.1 3a7 7 0 0 0 9.9 9.9Z"/>',
  fork:      '<path d="M7 3v6a2 2 0 0 0 4 0V3M9 11v10M17.5 3c-1.4 1.2-2 3-2 5s.6 3 2 3v10"/>',
  calendar:  '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  run:       '<circle cx="14" cy="4.5" r="1.8"/><path d="M11.5 21l1.4-5.3 3-2.2 1 4.2 3.1 2M5.5 12.4l4.4-3.3 3.2 1.1 2.2 3.2"/>',
  lock:      '<rect x="5" y="10.5" width="14" height="10.5" rx="2.4"/><path d="M8 10.5V7.6a4 4 0 0 1 8 0v2.9"/>',
  arrowsLR:  '<path d="M4 12h16M8.5 7.5 4 12l4.5 4.5M15.5 7.5 20 12l-4.5 4.5"/>',
  plus:      '<path d="M12 5v14M5 12h14"/>',
  chevL:     '<path d="M15 4 7 12l8 8"/>',
  chevR:     '<path d="M9 4l8 8-8 8"/>',
  chevU:     '<path d="M4 15l8-8 8 8"/>',
  chart:     '<path d="M3.5 20.5h17M7 17.5V10M12 17.5V5.5M17 17.5v-5"/>',
  timer:     '<circle cx="12" cy="13.5" r="7.8"/><path d="M12 13.5V9.2M9.2 2.4h5.6"/>',
  checklist: '<path d="M3.2 6.2 4.8 7.8 8 4.6M3.2 13 4.8 14.6 8 11.4M3.2 19.8l1.6 1.6L8 18.2M11.5 6.2H21M11.5 13H21M11.5 19.8H21"/>',
  gear:      '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.6v3M12 18.4v3M21.4 12h-3M5.6 12h-3M18.6 5.4l-2.1 2.1M7.5 16.5l-2.1 2.1M18.6 18.6l-2.1-2.1M7.5 7.5 5.4 5.4"/>',
  ellipsis:  '<circle cx="12" cy="12" r="9"/><circle cx="8" cy="12" r="1.1" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.1" fill="currentColor" stroke="none"/><circle cx="16" cy="12" r="1.1" fill="currentColor" stroke="none"/>',
  tray:      '<path d="M3 14.2 5.7 5.8h12.6L21 14.2v3.6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/><path d="M3 14.2h5.2l1 2h5.6l1-2H21"/>',
  clock:     '<circle cx="12" cy="12" r="8.6"/><path d="M12 6.6V12l3.6 2.2"/>',
  boltCircle:'<circle cx="12" cy="12" r="8.6"/><path d="M13 6.6 8.8 13H12l-1 4.4L15.2 11H12Z"/>',
  playCircle:'<circle cx="12" cy="12" r="8.6" fill="currentColor" stroke="none"/><path d="M10 8.5 16 12l-6 3.5Z" fill="#fff" stroke="none"/>',
  checkCircle:'<circle cx="12" cy="12" r="8.6" fill="currentColor" stroke="none"/><path d="m8.2 12.2 2.6 2.6 5-5.4" stroke="#fff" stroke-width="2.1"/>',
  circle:    '<circle cx="12" cy="12" r="8.6"/>',
  slashCircle:'<circle cx="12" cy="12" r="8.6" fill="currentColor" stroke="none"/><path d="M8.4 8.4 15.6 15.6M15.6 8.4 8.4 15.6" stroke="#fff" stroke-width="2.1"/>',
  halfCircle:'<circle cx="12" cy="12" r="8.6" fill="currentColor" stroke="none"/><path d="M8 12h8" stroke="#fff" stroke-width="2.2"/>',
  boltFill:  '<path d="M13.4 2 5 13.4h5.4L9.6 22 19 10.2h-5.6Z" fill="currentColor" stroke="none"/>',
  sum:       '<path d="M18 5H6l7 7-7 7h12"/>',
  hand:      '<path d="M9 11V5.4a1.6 1.6 0 0 1 3.2 0V11m0-1.4a1.6 1.6 0 0 1 3.2 0V11m0-.6a1.6 1.6 0 0 1 3.2 0v4.2c0 3.6-2.6 6.4-6.2 6.4-2.4 0-4-1-5.2-2.8L4 13.6a1.7 1.7 0 0 1 2.7-2l2.3 2.6"/>',
  wand:      '<path d="M4 20 16 8M14.5 3.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8ZM20 12l.6 1.5 1.5.6-1.5.6-.6 1.5-.6-1.5-1.5-.6 1.5-.6Z"/>',
  pause:     '<path d="M9 5v14M15 5v14" stroke-width="2.6"/>',
  stop:      '<rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="currentColor" stroke="none"/>',
  cursor:    '<path d="M5.5 3.2 18.4 12l-5.2.9 3 5.7-2.4 1.2-2.9-5.7-3.4 3.6Z" fill="#fff" stroke="rgba(0,0,0,.55)" stroke-width="1.2"/>',
}
const ic = (n, cls = 'icb') =>
  `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${ICONS[n]}</svg>`

// ── palette (Theme.swift) ───────────────────────────────────────────────────
const C = { red:'#FF3B30', orange:'#FF9500', yellow:'#FFCC00', green:'#34C759',
            blue:'#007AFF', indigo:'#5856D6', purple:'#AF52DE', pink:'#FF2D55', teal:'#30B0C7' }

// ── week data ───────────────────────────────────────────────────────────────
const DAYS = [
  { s:'Mon', n:3 }, { s:'Tue', n:4 }, { s:'Wed', n:5, today:true },
  { s:'Thu', n:6 }, { s:'Fri', n:7 }, { s:'Sat', n:8 }, { s:'Sun', n:9 },
]
const NOW = 14.6                       // Wednesday, 14:36

/** Plan blocks per weekday index. verified → accent blue, otherwise orange. */
const BLOCKS = [
  [{ t:'Learn Swift Combine',    h:1.5, at:20,   ok:true }],
  [{ t:'Draft the Q2 proposal',   h:2,   at:20,   ok:true }],
  [{ t:'Review the PR backlog',   h:1,   at:20,   ok:true },
   { t:'Call the dentist',        h:0.5, at:21.5, ok:false }],
  [{ t:'Rewrite the onboarding copy', h:1.5, at:20, ok:true }],
  [{ t:'Ship the release notes',  h:1,   at:20,   ok:true }],
  [{ t:'Deep Work, chapter 4',    h:1.5, at:10,   ok:true },
   { t:'Groceries for the week',  h:1,   at:15,   ok:false }],
  [{ t:'Plan next week',          h:0.5, at:17,   ok:true }],
]

const MEALS = [8, 13, 19]   // 3 flexible sessions a day
const isWeekday = i => i < 5
const hasGym = i => i === 0 || i === 2 || i === 4

/** Timeline segments for a day, in the order TimelineLayout would produce them. */
function segmentsFor(i) {
  const s = []
  s.push({ a:0, b:7, c:C.indigo, t:'Sleep' })                            // 23:00 + 8h, split at midnight
  if (hasGym(i)) s.push({ a:7, b:8, c:C.orange, t:'Exercise' })
  if (isWeekday(i)) s.push({ a:9, b:18, c:C.blue, t:'Work' })
  for (const m of MEALS) s.push({ a:m, b:m + 0.8333, c:C.green, t:'Meals', flex:true })
  for (const b of BLOCKS[i]) s.push({ a:b.at, b:b.at + b.h, c:b.ok ? C.blue : C.orange, t:b.t })
  s.push({ a:23, b:24, c:C.indigo, t:'Sleep' })
  return s
}

/** Hours left = 24 − union of the drawn segments (DayTimelineRow.freeHours). */
function freeHours(i) {
  const iv = segmentsFor(i).map(s => [s.a, s.b]).sort((x, y) => x[0] - y[0])
  let used = 0, end = -1
  for (const [a, b] of iv) { const s = Math.max(a, end); if (b > s) { used += b - s; end = b } }
  return 24 - used
}

/** Block-view column items: the timeline order, with meals that overlap folded away. */
function columnFor(i) {
  const out = [{ k:'r', name:'Sleep', sub:'7h', c:C.indigo, icon:'moon' }]
  const occupied = [[0, 7], ...(hasGym(i) ? [[7, 8]] : []), ...(isWeekday(i) ? [[9, 18]] : []),
                    ...BLOCKS[i].map(b => [b.at, b.at + b.h]), [23, 24]]
  const overlaps = (a, b) => occupied.some(([x, y]) => a < y - 1e-6 && x < b - 1e-6)
  const evts = []
  if (hasGym(i)) evts.push({ at:7, o:0, v:{ k:'r', name:'Exercise', sub:'1h', c:C.orange, icon:'run' } })
  if (isWeekday(i)) evts.push({ at:9, o:0, v:{ k:'r', name:'Work', sub:'9h', c:C.blue, icon:'calendar' } })
  for (const m of MEALS)
    if (!overlaps(m, m + 0.8333)) evts.push({ at:m, o:2, v:{ k:'q', name:'Meals', sub:'0.8h', c:C.green, icon:'fork' } })
  for (const b of BLOCKS[i]) evts.push({ at:b.at, o:1, v:{ k:'b', ...b } })
  evts.sort((x, y) => x.at - y.at || x.o - y.o)

  const cut = DAYS[i].today ? evts.findIndex(e => e.at > NOW) : -1
  evts.forEach((e, n) => { if (n === cut) out.push({ k:'now' }); out.push(e.v) })
  if (DAYS[i].today && cut < 0) out.push({ k:'now' })
  out.push({ k:'r', name:'Sleep', sub:'1h', c:C.indigo, icon:'moon' })
  return out
}

const h1 = h => (Math.round(h * 10) / 10).toFixed(1)

// ── window chrome ───────────────────────────────────────────────────────────
const toolbar = `
  <div class="tools">
    <div class="tool">${ic('timer', '')}<span>Timer</span></div>
    <div class="tool">${ic('checklist', '')}<span>Review</span></div>
    <div class="tool">${ic('gear', '')}<span>Settings</span></div>
    <div class="tool">${ic('ellipsis', '')}<span>More</span></div>
  </div>`

const win = (inner, cls = '', title = 'Rainbow Workshop', tools = toolbar) => `
  <div class="win ${cls}">
    <div class="titlebar">
      <div class="lights"><i class="r"></i><i class="y"></i><i class="g"></i></div>
      <div class="wtitle">${title}</div>${tools}
    </div>
    ${inner}
  </div>`

const weekHeader = (lens = 'plan', summaryOpen = false) => `
  <div class="wkhead">
    <div class="chev">${ic('chevL', '')}</div>
    <div class="wkrange">Mar 3 – Mar 9</div>
    <div class="chev">${ic('chevR', '')}</div>
    <div class="wksub">This week</div>
    <div class="spacer"></div>
    <div class="seg">
      <div class="${lens === 'plan' ? 'on' : ''}">${ic('calendar', '')}Block view</div>
      <div class="${lens === 'day' ? 'on' : ''}">${ic('clock', '')}Timeline view</div>
    </div>
    <div class="plainbtn" style="margin-left:14px">
      ${ic(summaryOpen ? 'chevU' : 'chart', '')}${summaryOpen ? 'Hide summary' : 'Summary'}
    </div>
  </div>`

const ROUTINE_H = 121.5, PLANNED_H = 9.5, FREE_H = 168 - ROUTINE_H
const summary = () => `
  <div>
    <div class="metrics">
      <div class="metric"><div class="lbl">The week</div>
        <div class="val">168<span>h</span></div><div class="sub">24h a day</div></div>
      <div class="metric"><div class="lbl">Fixed routines</div>
        <div class="val">121.5<span>h</span></div><div class="sub">about 17.4h a day</div></div>
      <div class="metric"><div class="lbl">Free time left</div>
        <div class="val">46.5<span>h</span></div><div class="sub">about 6.6h a day</div></div>
    </div>
    <div class="bar" style="margin-top:10px">
      <i style="width:${ROUTINE_H / 168 * 100}%;background:rgba(0,0,0,.4)"></i>
      <i style="width:${PLANNED_H / 168 * 100}%;background:rgba(0,122,255,.8)"></i>
      <i style="flex:1;background:rgba(0,0,0,.05)"></i>
    </div>
    <div class="legend">
      <span><b style="background:rgba(0,0,0,.5)"></b>Routines 122h</span>
      <span><b style="background:${C.blue}"></b>Planned 10h</span>
      <span><b style="background:rgba(0,0,0,.12)"></b>Free (unplanned) 37h</span>
    </div>
  </div>`

const chip = it => it.k === 'now'
  ? `<div class="nowline"><i></i><u></u><span>14:36</span></div>`
  : it.k === 'b'
    ? `<div class="bchip" style="--c:${it.ok ? C.blue : C.orange}">
         <div class="brow"><span class="btitle">${it.t}</span><span class="bdur">${h1(it.h).replace('.0', '')}h</span></div>
       </div>`
    : `<div class="chip ${it.k === 'q' ? 'quota' : ''}" style="--c:${it.c}">
         ${ic(it.icon, '')}
         <div class="ctext"><div class="cname">${it.name}</div><div class="csub">${it.sub}</div></div>
         ${ic(it.k === 'q' ? 'arrowsLR' : 'lock', 'tail')}
       </div>`

const weekGrid = (dropCol = -1) => `
  <div>
    <div class="grid">
      ${DAYS.map((d, i) => `
        <div class="col ${i === dropCol ? 'drop' : ''}">
          <div class="dayhead ${d.today ? 'today' : ''}"><div class="d">${d.s}</div><div class="n">${d.n}</div></div>
          <div class="items">${columnFor(i).map(chip).join('')}</div>
          <div class="addbtn">${ic('plus', '')}</div>
        </div>`).join('')}
    </div>
  </div>`

// ── to-dos ──────────────────────────────────────────────────────────────────
const TODOS = [
  { t:'Learn Swift Combine', c:C.blue, step:'Write up sink vs assign', n:2, of:4, pct:40, hrs:'4h', on:'Monday' },
  { t:'Draft the Q2 proposal', c:C.purple, step:'Pull last quarter’s numbers', n:1, of:3, pct:12, hrs:'6h', on:'Tuesday' },
  { t:'Ship the release notes', lane:'now', step:'Post it to the site', n:4, of:4, pct:80, hrs:'1h', frag:true },
  { t:'Call the dentist', lane:'errand', hrs:'0.5h' },
]
const todoCard = d => `
  <div class="todo ${d.lane === 'now' ? 'now' : d.lane === 'errand' ? 'errand' : ''}" style="--c:${d.c || C.blue}">
    <div class="lane"></div>
    <div style="min-width:0;flex:1">
      <div class="tt">${d.t}</div>
      ${d.step ? `<div class="step" style="color:${d.frag ? 'var(--now-green)' : C.orange}">
            ${ic(d.frag ? 'boltCircle' : 'playCircle', '')}<span>${d.step}</span></div>` : ''}
      <div class="meta">
        ${d.step ? `<span>${d.n}/${d.of}</span><span class="prog"><i style="width:${d.pct}%"></i></span>` : ''}
        <span>${d.hrs}</span>${d.on ? `<span class="pill">${d.on}</span>` : ''}
        ${d.frag ? `<span class="pill" style="color:var(--teal)">5 min</span>` : ''}
      </div>
    </div>
  </div>`

const todoSection = () => `
  <div>
    <div class="sect">
      <span>To-dos</span>
      <div class="btn-p">${ic('plus', '')}New to-do</div>
      <div class="btn-b">${ic('tray', '')}Show all</div>
      <span class="count">4 · 11h 30m</span>
      <div class="spacer"></div>
      ${ic('ellipsis', 'icb')}
    </div>
    <div class="todos" style="margin-top:10px">${TODOS.map(todoCard).join('')}</div>
  </div>`

const routineSection = () => `
  <div>
    <div class="sect">${ic('lock', '')}<span>Fixed routines · what can't move</span>
      <div class="spacer"></div><div class="plainbtn">${ic('plus', '')}Add routine</div></div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin-top:10px">
      ${[['Sleep','moon',C.indigo,'Every day · 23:00 · 8h','56h a week'],
         ['Meals','fork',C.green,'17.5h a week · 3× a day','flexible hours'],
         ['Work','calendar',C.blue,'Mon–Fri · 09:00 · 9h','45h a week'],
         ['Exercise','run',C.orange,'Mon, Wed, Fri · 07:00 · 1h','3h a week']].map(
        ([n, i, c, s1, s2]) => `
        <div class="chip" style="--c:${c};align-items:flex-start;padding:9px 10px">
          ${ic(i, '')}
          <div class="ctext"><div class="cname">${n}</div>
            <div class="csub">${s1}</div><div class="csub">${s2}</div></div>
        </div>`).join('')}
    </div>
  </div>`

// ── timeline ────────────────────────────────────────────────────────────────
const x = h => (h / 24 * 100).toFixed(3) + '%'
const timeline = () => `
  <div class="tl">
    ${DAYS.map((d, i) => `
      <div class="tlrow">
        <div class="tlday ${d.today ? 'today' : ''}"><div class="d">${d.s}</div><div class="n">${d.n}</div></div>
        <div class="track">
          ${Array.from({ length: 23 }, (_, k) => k + 1).map(hh =>
            `<div class="g ${hh % 3 === 0 ? 'maj' : ''}" style="left:${x(hh)}"></div>`).join('')}
          ${segmentsFor(i).map(s => {
            const w = s.b - s.a
            return `<div class="seg2 ${s.flex ? 'flex' : ''} ${w < 1.6 ? 'tiny' : ''}"
                         style="--c:${s.c};left:${x(s.a)};width:${x(w)}">
                      ${w > 0.7 ? `<span>${s.t}</span>` : ''}</div>`
          }).join('')}
          ${d.today ? `<div class="nowbar" style="left:${x(NOW)}"></div>` : ''}
        </div>
        <div class="tlfree">${h1(freeHours(i))}h left</div>
      </div>`).join('')}
    <div class="axis">
      <div class="tlday"></div>
      <div class="ruler">${[0, 3, 6, 9, 12, 15, 18, 21, 24].map(hh =>
        `<b style="left:${x(hh)}">${hh}</b>`).join('')}</div>
      <div class="tlfree"></div>
    </div>
  </div>`

// ── panels ──────────────────────────────────────────────────────────────────
const stepsSheet = () => `
  <div class="sheet">
    <div class="panel">
      <div class="phead" style="background:var(--card)">
        <div style="display:flex;align-items:flex-start;gap:12px">
          <div style="flex:1">
            <h3 style="font-size:19px;font-weight:600">Learn Swift Combine</h3>
            <div style="display:flex;align-items:center;gap:6px;margin-top:6px">
              <span class="tag" style="background:rgba(255,149,0,.15);color:var(--orange)">Current step</span>
              <span style="font-size:14px;font-weight:500">Write up sink vs assign</span>
            </div>
          </div>
          <div style="font-size:30px;font-weight:600;color:${C.blue};font-variant-numeric:tabular-nums">40%</div>
          <div class="btn-def">Done</div>
        </div>
        <div style="height:5px;border-radius:3px;background:rgba(0,0,0,.09);overflow:hidden">
          <i style="display:block;height:100%;width:40%;background:${C.blue}"></i></div>
        <div style="display:flex;align-items:center;gap:8px;color:var(--ink2)">
          ${ic('sum', 'icb')}<span style="font-size:14px;font-weight:600">4h when it's all done</span>
          <span style="font-size:11px;color:rgba(0,0,0,.35)">= 100%, split across 4 steps</span>
        </div>
      </div>
      <div class="hr"></div>
      <div class="steps">
        <div style="font-size:13px;font-weight:600;color:var(--ink2);padding:0 8px 4px">Steps</div>
        ${[['ok','Collect the sample projects','1','25'],
           ['cur','Write up sink vs assign','1.5','38'],
           ['','Get the sample running','1','25'],
           ['frag','Push the notes to the repo','0.5','12']].map(([k, t, hr, pc]) => `
          <div class="steprow ${k === 'ok' ? 'ok' : k === 'cur' ? 'cur' : ''}">
            ${ic(k === 'ok' ? 'checkCircle' : k === 'cur' ? 'playCircle' : 'circle', 'num')}
            <div style="flex:1">
              <div class="st" style="${k === 'cur' ? 'font-weight:600' : ''}">${t}</div>
              ${k === 'frag' ? `<div class="tag frag" style="display:inline-flex;margin-top:4px">
                   ${ic('boltFill', '')}Pick up in five minutes</div>` : ''}
            </div>
            <div class="hrs">${hr} h</div><div class="pct">${pc}%</div>
          </div>`).join('')}
      </div>
      <div class="hr"></div>
      <div style="padding:12px 20px;display:flex;align-items:center;gap:8px;background:var(--window)">
        <div style="flex:1;height:26px;border-radius:6px;background:#fff;border:.5px solid rgba(0,0,0,.18);
                    display:flex;align-items:center;padding:0 9px;font-size:13px;color:rgba(0,0,0,.32)">
          Add a step</div>
        <div class="btn-b">${ic('wand', '')}Split it for me</div>
      </div>
    </div>
  </div>`

const reviewSheet = () => `
  <div class="sheet">
    <div class="panel">
      <div class="phead">
        <h3>Weekly review</h3>
        <div class="tiles">
          <div class="tile"><div class="lbl">Done</div><div class="v" style="color:${C.green}">5</div></div>
          <div class="tile"><div class="lbl">Partial</div><div class="v" style="color:${C.yellow}">2</div></div>
          <div class="tile"><div class="lbl">Skipped</div><div class="v" style="color:${C.red}">1</div></div>
          <div class="tile"><div class="lbl">Not reviewed</div><div class="v" style="color:var(--ink2)">1</div></div>
        </div>
      </div>
      <div class="hr"></div>
      <div class="rows">
        ${[['done','Mon','Learn Swift Combine','Notes written and the sample runs','1.5h'],
           ['done','Tue','Draft the Q2 proposal','Outline plus the numbers section','2h'],
           ['part','Wed','Review the PR backlog','Got through 6 of 11','1h'],
           ['skip','Wed','Call the dentist','','0.5h'],
           ['done','Thu','Rewrite the onboarding copy','First screen rewritten','1.5h'],
           ['done','Fri','Ship the release notes','Published to the site','1h'],
           ['part','Sat','Deep Work, chapter 4','Half the chapter','1.5h'],
           ['done','Sat','Groceries for the week','','1h'],
           ['','Sun','Plan next week','','0.5h']].map(([k, d, t, s, hr]) => `
          <div class="row ${k === 'done' ? 'done' : ''}">
            ${ic(k === 'done' ? 'checkCircle' : k === 'part' ? 'halfCircle' : k === 'skip' ? 'slashCircle' : 'circle', 'ck')
              .replace('class="ck"', `class="ck" style="color:${k === 'done' ? C.green : k === 'part' ? C.yellow : k === 'skip' ? C.red : 'rgba(0,0,0,.3)'}"`)}
            <div class="dw">${d}</div>
            <div style="flex:1"><div class="rt">${t}</div>${s ? `<div class="rs">${s}</div>` : ''}</div>
            <div class="rd">${hr}</div>
          </div><div class="hr"></div>`).join('')}
      </div>
      <div class="pfoot"><div class="btn-def">Done</div></div>
    </div>
  </div>`

const timerWindow = () => win(`
  <div class="timer" style="--c:${C.blue}">
    <div class="tname">${ic('calendar', '')}<span>Review the PR backlog</span></div>
    <div class="trange">20:00–21:00 · 1 hour</div>
    <div class="big">23:41<em>left</em></div>
    <div class="ends">Ends at 21:00</div>
    <div class="ring"><i style="width:61%"></i></div>
    <div class="acts">
      <div class="btn-b">${ic('pause', '')}Pause</div>
      <div class="btn-b">+5 min</div>
      <div class="btn-b">+10 min</div>
      <div class="btn-b">${ic('stop', '')}Stop</div>
    </div>
  </div>
  <div class="upnext">
    <div class="ttl">The rest of the day from here</div>
    ${[['calendar', C.orange, 'Call the dentist', '21:30 · 30m'],
       ['moon', C.indigo, 'Sleep', '23:00 · 8h']].map(([i, c, n, t]) => `
      <div class="uprow" style="--c:${c}">${ic(i, '')}<div class="un">${n}</div><div class="ut">${t}</div></div>`).join('')}
  </div>`, 'sm', 'Timer', '')

// ── shots ───────────────────────────────────────────────────────────────────
const body = (...parts) => `<div class="body">${parts.join('')}</div>`

const SHOTS = [
  { id:'01-week', bg:['#5856D6', '#0A84FF'],
    h:'Lay down the hours you can’t take back',
    p:'A week is 168 hours. Sleep, meals and work take their share — the app shows you what is actually left.',
    inner: win(body(weekHeader('plan', true), summary(), weekGrid())) },

  { id:'02-drag', bg:['#0A84FF', '#32ADE6'],
    h:'Drag a to-do onto the day it fits',
    p:'It lands as a plan block. Move it to another day, drop it into a gap, or drag it back to the list.',
    inner: win(body(weekHeader(), weekGrid(3), todoSection()) +
      `<div class="ghost" style="left:526px;top:353px;width:206px">
         <div class="todo" style="--c:${C.purple};background:#fff;border-color:rgba(0,0,0,.14)">
           <div class="lane"></div>
           <div style="min-width:0;flex:1"><div class="tt">Draft the Q2 proposal</div>
             <div class="meta"><span>6h</span></div></div>
         </div></div>
       <div class="cursor" style="left:616px;top:411px">${ic('cursor', '')}</div>`) },

  { id:'03-timeline', bg:['#FF9500', '#FF3B30'],
    h:'See a whole day on a 24-hour ruler',
    p:'Drag sideways to move the time, up or down to move the day. Gaps and collisions show up at a glance.',
    inner: win(body(weekHeader('day'), timeline(), todoSection(), routineSection())) },

  { id:'04-steps', bg:['#34C759', '#30B0C7'],
    h:'Split a job into steps that close',
    p:'Two questions per step: can you start without spinning up, and does it finish within five minutes?',
    inner: `<div class="stack">${win(body(weekHeader(), weekGrid(), todoSection()), 'dim')}${stepsSheet()}</div>` },

  { id:'05-timer', bg:['#AF52DE', '#5856D6'],
    h:'Always know what’s left',
    p:'The timer follows the times in your plan, so what you are doing now — and how much of it remains — is never a guess.',
    inner: `<div class="stack">${win(body(weekHeader('day'), timeline(), todoSection(), routineSection()), 'dim')}
            <div class="float">${timerWindow()}</div></div>` },

  { id:'06-review', bg:['#FF2D55', '#FF9500'],
    h:'Close the week with a checklist',
    p:'Mark what you did, what you half did and what you skipped, and build the next week out of the answer.',
    inner: `<div class="stack">${win(body(weekHeader(), weekGrid(), todoSection()), 'dim')}${reviewSheet()}</div>` },
]

const EXTRA = `
.stack { position:relative; display:flex; justify-content:center; width:1300px; flex:0 0 auto }
.win.dim::after { content:""; position:absolute; inset:0; background:rgba(0,0,0,.17); z-index:2 }
.sheet { position:absolute; top:64px; left:50%; transform:translateX(-50%); width:780px; z-index:3;
         border-radius:12px; overflow:hidden; box-shadow:0 26px 60px rgba(0,0,0,.34) }
.float { position:absolute; top:78px; right:26px; z-index:3 }
.float .win { box-shadow:0 26px 60px rgba(0,0,0,.38) }
`

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Rainbow Workshop — App Store screenshots (English)</title>
<link rel="stylesheet" href="style.css"><style>${EXTRA}</style></head>
<body>
${SHOTS.map(s => `<section class="shot" id="${s.id}"
   style="background:linear-gradient(158deg, ${s.bg[0]}, ${s.bg[1]})">
  <div class="cap"><h2>${s.h}</h2><p>${s.p}</p></div>
  ${s.inner}
</section>`).join('\n')}
</body></html>`

writeFileSync(join(HERE, 'index.html'), html)
console.log('wrote index.html')

if (!process.argv.includes('--html')) {
  // Local install first; fall back to a global one (NPM_GLOBAL_ROOT=$(npm root -g)).
  const { chromium } = await import('playwright')
    .catch(() => import(join(process.env.NPM_GLOBAL_ROOT || '', 'playwright/index.mjs')))
  const outDir = join(HERE, 'en')
  mkdirSync(outDir, { recursive: true })
  const browser = await chromium.launch()
  const page = await browser.newPage({ viewport:{ width:1440, height:900 }, deviceScaleFactor:2 })
  await page.goto('file://' + join(HERE, 'index.html'))
  await page.waitForTimeout(600)
  // Scale a window down only as far as it takes to keep it inside the frame.
  const fitted = await page.evaluate(() => {
    const els = [...document.querySelectorAll('.shot')].map(shot =>
      [shot, shot.querySelector('.stack') || shot.querySelector('.win')])
    const k = Math.min(...els.map(([shot, el]) =>
      (900 - (el.getBoundingClientRect().top - shot.getBoundingClientRect().top) - 20) / el.offsetHeight), 1)
    for (const [, el] of els) { el.style.transformOrigin = 'top center'; el.style.transform = `scale(${k})` }
    return +k.toFixed(3)
  })
  console.log('fit:', fitted)
  for (const s of SHOTS) {
    const path = join(outDir, `${s.id}.png`)
    await page.locator(`[id="${s.id}"]`).screenshot({ path })
    console.log('rendered', path)
  }
  await browser.close()
}
