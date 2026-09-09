// Builds the App Store screenshot mockups for Rainbow Workshop / 무지개 공방 (macOS),
// in both languages the app speaks: English (en/) and Korean (ko/).
//
// The Mac app cannot be built or run here (no macOS/Xcode), so these are pixel
// mockups drawn from the real SwiftUI views: the layout, the strings and the
// palette all come from the source.
//   palette   → WeekBlocks/Theme.swift            (Rainbow, Apple system colors)
//   strings   → WeekBlocks/Localizable.xcstrings  (the "en" side verbatim; the
//               Korean side is the key itself)
//   layout    → ContentView / WeekGridView / DayTimelineView / TodoStepsView /
//               TimerView / ReflectionView
//   copy      → docs/STORE_NOTES_1.1.2.txt        (the store description)
//
// Sample data is the app's own onboarding suggestion set: Sleep 23:00+8h daily,
// Meals 17.5h/week in 3 flexible sessions, Work weekdays 09:00+9h, Exercise
// Mon/Wed/Fri 07:00+1h.  Routines 121.5h → 46.5h free of 168.
//
//   node build.mjs          write index-<locale>.html and render en/*.png, ko/*.png
//   node build.mjs --html   write the HTML only

import { writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

// ── fonts ───────────────────────────────────────────────────────────────────
// SF Pro and Apple SD Gothic Neo are not redistributable. Inter stands in for
// the Latin, Pretendard for the Hangul; both are SIL OFL. Fetched on demand and
// left out of git — see .gitignore.
const FONTS = {
  'inter-400.ttf':'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf',
  'inter-500.ttf':'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuI6fMZg.ttf',
  'inter-600.ttf':'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYMZg.ttf',
  'inter-700.ttf':'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZg.ttf',
  'inter-800.ttf':'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuDyYMZg.ttf',
}
const PRETENDARD = 'https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/packages/pretendard/dist/web/static/woff2'
for (const [w, name] of [[400,'Regular'], [500,'Medium'], [600,'SemiBold'], [700,'Bold'], [800,'ExtraBold']])
  FONTS[`pretendard-${w}.woff2`] = `${PRETENDARD}/Pretendard-${name}.woff2`

async function ensureFonts() {
  mkdirSync(join(HERE, 'fonts'), { recursive: true })
  for (const [file, url] of Object.entries(FONTS)) {
    const path = join(HERE, 'fonts', file)
    if (existsSync(path)) continue
    console.log('fetching', file)
    const res = await fetch(url)
    if (!res.ok) throw new Error(`${file} failed: ${res.status}`)
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

// ── words ───────────────────────────────────────────────────────────────────
// The Korean side is the key in Localizable.xcstrings; the English side is its
// "en" value, copied verbatim. Names of things (routines, to-dos, steps) are
// sample data, so they are simply written in each language.
const STRINGS = {
  en: {
    lang:'en', app:'Rainbow Workshop',
    timer:'Timer', review:'Review', settings:'Settings', more:'More',
    weekRange:'Mar 3 – Mar 9', thisWeek:'This week',
    lensPlan:'Block view', lensDay:'Timeline view',
    summary:'Summary', hideSummary:'Hide summary',
    mWeek:'The week', mWeekSub:'24h a day',
    mFixed:'Fixed routines', mFixedSub:'about 17.4h a day',
    mFree:'Free time left', mFreeSub:'about 6.6h a day',
    legRoutines:'Routines 122h', legPlanned:'Planned 10h', legFree:'Free (unplanned) 37h',
    days:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
    rSleep:'Sleep', rMeals:'Meals', rWork:'Work', rGym:'Exercise',
    rSleepWhen:'Every day · 23:00 · 8h', rSleepSum:'56h a week',
    rMealsWhen:'17.5h a week · 3× a day', rMealsSum:'flexible hours',
    rWorkWhen:'Mon–Fri · 09:00 · 9h', rWorkSum:'45h a week',
    rGymWhen:'Mon, Wed, Fri · 07:00 · 1h', rGymSum:'3h a week',
    routinesHead:"Fixed routines · what can't move", addRoutine:'Add routine',
    todos:'To-dos', newTodo:'New to-do', showAll:'Show all', todoCount:'4 · 11h 30m',
    hoursLeft: v => `${v}h left`,
    blocks:['Learn Swift Combine', 'Draft the Q2 proposal', 'Review the PR backlog',
            'Call the dentist', 'Rewrite the onboarding copy', 'Ship the release notes',
            'Deep Work, chapter 4', 'Groceries for the week', 'Plan next week'],
    todoList:[
      { t:'Learn Swift Combine', step:'Write up sink vs assign', hrs:'4h', on:'Monday' },
      { t:'Draft the Q2 proposal', step:'Pull last quarter’s numbers', hrs:'6h', on:'Tuesday' },
      { t:'Ship the release notes', step:'Post it to the site', hrs:'1h', frag:'5 min' },
      { t:'Call the dentist', hrs:'0.5h' },
    ],
    currentStep:'Current step', done:'Done', allDone:v => `${v} when it's all done`,
    splitAcross:'= 100%, split across 4 steps', steps:'Steps',
    fragment:'Pick up in five minutes', addStep:'Add a step', splitHelper:'Split it for me',
    stepList:[['ok','Collect the sample projects','1','25'],
              ['cur','Write up sink vs assign','1.5','38'],
              ['','Get the sample running','1','25'],
              ['frag','Push the notes to the repo','0.5','12']],
    totalHours:'4h',
    tRange:'20:00–21:00 · 1 hour', tLeft:'left', tEnds:'Ends at 21:00',
    tPause:'Pause', tPlus5:'+5 min', tPlus10:'+10 min', tStop:'Stop',
    tRest:'The rest of the day from here',
    tUpNext:[['calendar', C.orange, 'Call the dentist', '21:30 · 30m'],
             ['moon', C.indigo, 'Sleep', '23:00 · 8h']],
    rvTitle:'Weekly review', rvDone:'Done', rvPartial:'Partial',
    rvSkipped:'Skipped', rvPending:'Not reviewed',
    rvNotePlaceholder:"One line of review — what went well, what didn't",
    rvRows:[['done',0,0,'Evening · 1.5h','Notes written and the sample runs'],
            ['done',1,1,'Evening · 2.0h','Outline plus the numbers section'],
            ['part',2,2,'Evening · 1.0h','Got through 6 of 11'],
            ['skip',2,3,'Evening · 0.5h',''],
            ['done',3,4,'Evening · 1.5h','First screen rewritten'],
            ['done',4,5,'Evening · 1.0h','Published to the site']],
    caps:[
      ['Lay down the hours you can’t take back',
       'A week is 168 hours. Sleep, meals and work take their share — the app shows you what is actually left.'],
      ['Drag a to-do onto the day it fits',
       'It lands as a plan block. Move it to another day, drop it into a gap, or drag it back to the list.'],
      ['See a whole day on a 24-hour ruler',
       'Drag sideways to move the time, up or down to move the day. Gaps and collisions show up at a glance.'],
      ['Split a job into steps that close',
       'Two questions per step: can you start without spinning up, and does it finish within five minutes?'],
      ['Always know what’s left',
       'The timer follows the times in your plan, so what you are doing now — and how much of it remains — is never a guess.'],
      ['Close the week with a checklist',
       'Mark what you did, what you half did and what you skipped, and build the next week out of the answer.'],
    ],
  },
  ko: {
    lang:'ko', app:'무지개 공방',
    timer:'타이머', review:'회고', settings:'설정', more:'더 보기',
    weekRange:'3월 3일 – 3월 9일', thisWeek:'이번 주',
    lensPlan:'블록으로 보기', lensDay:'시간축으로 보기',
    summary:'요약', hideSummary:'요약 접기',
    mWeek:'한 주', mWeekSub:'하루 24h',
    mFixed:'고정 루틴', mFixedSub:'하루 약 17.4h',
    mFree:'남은 자유 시간', mFreeSub:'하루 약 6.6h',
    legRoutines:'루틴 122h', legPlanned:'계획 10h', legFree:'남은 자유 (계획 없음) 37h',
    days:['월','화','수','목','금','토','일'],
    rSleep:'잠', rMeals:'끼니', rWork:'일', rGym:'운동',
    rSleepWhen:'매일 · 23:00 · 8시간', rSleepSum:'주 56h',
    rMealsWhen:'주 17.5시간 · 하루 3회', rMealsSum:'시각은 유연하게',
    rWorkWhen:'월–금 · 09:00 · 9시간', rWorkSum:'주 45h',
    rGymWhen:'월·수·금 · 07:00 · 1시간', rGymSum:'주 3h',
    routinesHead:'고정 루틴 · 중요한 일', addRoutine:'루틴 추가',
    todos:'할 일', newTodo:'새 할 일', showAll:'전체 보기', todoCount:'4개 · 11시간 30분',
    hoursLeft: v => `남은 시간 ${v}h`,
    blocks:['Swift Combine 학습', '2분기 제안서 초안', 'PR 밀린 것 검토',
            '치과 예약 전화', '온보딩 문구 다시 쓰기', '릴리즈 노트 배포',
            '딥 워크 4장', '이번 주 장보기', '다음 주 계획'],
    todoList:[
      { t:'Swift Combine 학습', step:'sink·assign 차이 정리', hrs:'4시간', on:'월요일' },
      { t:'2분기 제안서 초안', step:'지난 분기 숫자 뽑기', hrs:'6시간', on:'화요일' },
      { t:'릴리즈 노트 배포', step:'사이트에 올리기', hrs:'1시간', frag:'5분' },
      { t:'치과 예약 전화', hrs:'30분' },
    ],
    currentStep:'지금 단계', done:'완료', allDone:v => `다 하면 ${v}`,
    splitAcross:'= 100%, 단계 4개가 나눠 가짐', steps:'단계',
    fragment:'5분에 집기', addStep:'단계 추가', splitHelper:'쪼개기 도우미',
    stepList:[['ok','예제 프로젝트 모으기','1','25'],
              ['cur','sink·assign 차이 정리','1.5','38'],
              ['','예제 실행 성공시키기','1','25'],
              ['frag','노트를 저장소에 올리기','0.5','12']],
    totalHours:'4시간',
    tRange:'20:00–21:00 · 1시간', tLeft:'남음', tEnds:'21:00에 끝납니다',
    tPause:'일시정지', tPlus5:'+5분', tPlus10:'+10분', tStop:'정지',
    tRest:'여기서부터 남은 하루',
    tUpNext:[['calendar', C.orange, '치과 예약 전화', '21:30 · 30분'],
             ['moon', C.indigo, '잠', '23:00 · 8시간']],
    rvTitle:'주간 회고', rvDone:'달성', rvPartial:'부분',
    rvSkipped:'건너뜀', rvPending:'미회고',
    rvNotePlaceholder:'한 줄 회고 — 무엇이 잘 됐고 무엇이 안 됐는지',
    rvRows:[['done',0,0,'저녁 · 1.5h','노트 정리하고 예제도 돌아감'],
            ['done',1,1,'저녁 · 2.0h','뼈대와 숫자 절까지'],
            ['part',2,2,'저녁 · 1.0h','11개 중 6개'],
            ['skip',2,3,'저녁 · 0.5h',''],
            ['done',3,4,'저녁 · 1.5h','첫 화면은 고쳤다'],
            ['done',4,5,'저녁 · 1.0h','사이트에 올림']],
    caps:[
      ['빼놓을 수 없는 시간부터 세웁니다',
       '한 주는 168시간. 잠·끼니·일이 가져가고 남는 것이 이번 주에 쓸 수 있는 전부입니다.'],
      ['할 일을 요일에 끌어다 놓으면 계획이 됩니다',
       '다른 요일로 옮기고, 일정 사이의 틈에 끼워 넣고, 목록으로 도로 끌어 내립니다.'],
      ['하루를 24시간 자 위에 펼칩니다',
       '좌우로 끌어 시각을, 위아래로 끌어 요일을 옮깁니다. 틈과 겹침이 한눈에 보입니다.'],
      ['끝이 닫히는 크기로 쪼갭니다',
       '단계마다 두 가지를 묻습니다. 지금 바로 시작할 수 있나, 5분 안에 끝까지 가나.'],
      ['지금 하는 일과 남은 시간',
       '타이머가 계획에 적힌 시각을 따라갑니다. 무엇을 하는 중이고 얼마 남았는지 짐작하지 않아도 됩니다.'],
      ['한 주를 체크리스트로 닫습니다',
       '한 것과 하다 만 것과 건너뛴 것을 표시하고, 그 답으로 다음 주를 세웁니다.'],
    ],
  },
}

// ── week data ───────────────────────────────────────────────────────────────
const DAY_NUM = [3, 4, 5, 6, 7, 8, 9]
const TODAY = 2                        // Wednesday
const NOW = 14.6                       // 14:36
const MEALS = [8, 13, 19]              // 3 flexible sessions a day
const isWeekday = i => i < 5
const hasGym = i => i === 0 || i === 2 || i === 4

/** Plan blocks per weekday, as indices into L.blocks. ok → accent blue, else orange. */
const BLOCKS = [
  [{ b:0, h:1.5, at:20,   ok:true }],
  [{ b:1, h:2,   at:20,   ok:true }],
  [{ b:2, h:1,   at:20,   ok:true }, { b:3, h:0.5, at:21.5, ok:false }],
  [{ b:4, h:1.5, at:20,   ok:true }],
  [{ b:5, h:1,   at:20,   ok:true }],
  [{ b:6, h:1.5, at:10,   ok:true }, { b:7, h:1,   at:15,   ok:false }],
  [{ b:8, h:0.5, at:17,   ok:true }],
]

/** Timeline segments for a day, in the order TimelineLayout would produce them. */
function segmentsFor(L, i) {
  const s = [{ a:0, b:7, c:C.indigo, t:L.rSleep }]        // 23:00 + 8h, split at midnight
  if (hasGym(i)) s.push({ a:7, b:8, c:C.orange, t:L.rGym })
  if (isWeekday(i)) s.push({ a:9, b:18, c:C.blue, t:L.rWork })
  for (const m of MEALS) s.push({ a:m, b:m + 0.8333, c:C.green, t:L.rMeals, flex:true })
  for (const b of BLOCKS[i]) s.push({ a:b.at, b:b.at + b.h, c:b.ok ? C.blue : C.orange, t:L.blocks[b.b] })
  s.push({ a:23, b:24, c:C.indigo, t:L.rSleep })
  return s
}

/** Hours left = 24 − union of the drawn segments (DayTimelineRow.freeHours). */
function freeHours(i) {
  const iv = segmentsFor(STRINGS.en, i).map(s => [s.a, s.b]).sort((x, y) => x[0] - y[0])
  let used = 0, end = -1
  for (const [a, b] of iv) { const s = Math.max(a, end); if (b > s) { used += b - s; end = b } }
  return 24 - used
}

/** Block-view column items: the timeline order, with meals that overlap folded away. */
function columnFor(L, i) {
  const out = [{ k:'r', name:L.rSleep, sub:'7h', c:C.indigo, icon:'moon' }]
  const occupied = [[0, 7], ...(hasGym(i) ? [[7, 8]] : []), ...(isWeekday(i) ? [[9, 18]] : []),
                    ...BLOCKS[i].map(b => [b.at, b.at + b.h]), [23, 24]]
  const overlaps = (a, b) => occupied.some(([x, y]) => a < y - 1e-6 && x < b - 1e-6)
  const evts = []
  if (hasGym(i)) evts.push({ at:7, o:0, v:{ k:'r', name:L.rGym, sub:'1h', c:C.orange, icon:'run' } })
  if (isWeekday(i)) evts.push({ at:9, o:0, v:{ k:'r', name:L.rWork, sub:'9h', c:C.blue, icon:'calendar' } })
  for (const m of MEALS)
    if (!overlaps(m, m + 0.8333))
      evts.push({ at:m, o:2, v:{ k:'q', name:L.rMeals, sub:'0.8h', c:C.green, icon:'fork' } })
  for (const b of BLOCKS[i]) evts.push({ at:b.at, o:1, v:{ k:'b', t:L.blocks[b.b], h:b.h, ok:b.ok } })
  evts.sort((x, y) => x.at - y.at || x.o - y.o)

  const cut = i === TODAY ? evts.findIndex(e => e.at > NOW) : -1
  evts.forEach((e, n) => { if (n === cut) out.push({ k:'now' }); out.push(e.v) })
  if (i === TODAY && cut < 0) out.push({ k:'now' })
  out.push({ k:'r', name:L.rSleep, sub:'1h', c:C.indigo, icon:'moon' })
  return out
}

const h1 = h => (Math.round(h * 10) / 10).toFixed(1)

// ── window chrome ───────────────────────────────────────────────────────────
const toolbar = L => `
  <div class="tools">
    ${[['timer', L.timer], ['checklist', L.review], ['gear', L.settings], ['ellipsis', L.more]]
      .map(([i, t]) => `<div class="tool">${ic(i, '')}<span>${t}</span></div>`).join('')}
  </div>`

const win = (L, inner, cls = '', title = null, tools = null) => `
  <div class="win ${cls}">
    <div class="titlebar">
      <div class="lights"><i class="r"></i><i class="y"></i><i class="g"></i></div>
      <div class="wtitle">${title ?? L.app}</div>${tools ?? toolbar(L)}
    </div>
    ${inner}
  </div>`

const weekHeader = (L, lens = 'plan', summaryOpen = false) => `
  <div class="wkhead">
    <div class="chev">${ic('chevL', '')}</div>
    <div class="wkrange">${L.weekRange}</div>
    <div class="chev">${ic('chevR', '')}</div>
    <div class="wksub">${L.thisWeek}</div>
    <div class="spacer"></div>
    <div class="seg">
      <div class="${lens === 'plan' ? 'on' : ''}">${ic('calendar', '')}${L.lensPlan}</div>
      <div class="${lens === 'day' ? 'on' : ''}">${ic('clock', '')}${L.lensDay}</div>
    </div>
    <div class="plainbtn" style="margin-left:14px">
      ${ic(summaryOpen ? 'chevU' : 'chart', '')}${summaryOpen ? L.hideSummary : L.summary}
    </div>
  </div>`

const ROUTINE_H = 121.5, PLANNED_H = 9.5
const summary = L => `
  <div>
    <div class="metrics">
      <div class="metric"><div class="lbl">${L.mWeek}</div>
        <div class="val">168<span>h</span></div><div class="sub">${L.mWeekSub}</div></div>
      <div class="metric"><div class="lbl">${L.mFixed}</div>
        <div class="val">121.5<span>h</span></div><div class="sub">${L.mFixedSub}</div></div>
      <div class="metric"><div class="lbl">${L.mFree}</div>
        <div class="val">46.5<span>h</span></div><div class="sub">${L.mFreeSub}</div></div>
    </div>
    <div class="bar" style="margin-top:10px">
      <i style="width:${ROUTINE_H / 168 * 100}%;background:rgba(0,0,0,.4)"></i>
      <i style="width:${PLANNED_H / 168 * 100}%;background:rgba(0,122,255,.8)"></i>
      <i style="flex:1;background:rgba(0,0,0,.05)"></i>
    </div>
    <div class="legend">
      <span><b style="background:rgba(0,0,0,.5)"></b>${L.legRoutines}</span>
      <span><b style="background:${C.blue}"></b>${L.legPlanned}</span>
      <span><b style="background:rgba(0,0,0,.12)"></b>${L.legFree}</span>
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

const weekGrid = (L, dropCol = -1) => `
  <div>
    <div class="grid">
      ${DAY_NUM.map((n, i) => `
        <div class="col ${i === dropCol ? 'drop' : ''}">
          <div class="dayhead ${i === TODAY ? 'today' : ''}">
            <div class="d">${L.days[i]}</div><div class="n">${n}</div></div>
          <div class="items">${columnFor(L, i).map(chip).join('')}</div>
          <div class="addbtn">${ic('plus', '')}</div>
        </div>`).join('')}
    </div>
  </div>`

// ── to-dos ──────────────────────────────────────────────────────────────────
const TODO_STYLE = [
  { c:C.blue, n:2, of:4, pct:40 },
  { c:C.purple, n:1, of:3, pct:12 },
  { lane:'now', n:4, of:4, pct:80 },
  { lane:'errand' },
]
const todoCard = (d, s) => `
  <div class="todo ${s.lane === 'now' ? 'now' : s.lane === 'errand' ? 'errand' : ''}" style="--c:${s.c || C.blue}">
    <div class="lane"></div>
    <div style="min-width:0;flex:1">
      <div class="tt">${d.t}</div>
      ${d.step ? `<div class="step" style="color:${d.frag ? 'var(--now-green)' : C.orange}">
            ${ic(d.frag ? 'boltCircle' : 'playCircle', '')}<span>${d.step}</span></div>` : ''}
      <div class="meta">
        ${d.step ? `<span>${s.n}/${s.of}</span><span class="prog"><i style="width:${s.pct}%"></i></span>` : ''}
        <span>${d.hrs}</span>${d.on ? `<span class="pill">${d.on}</span>` : ''}
        ${d.frag ? `<span class="pill" style="color:var(--teal)">${d.frag}</span>` : ''}
      </div>
    </div>
  </div>`

const todoSection = L => `
  <div>
    <div class="sect">
      <span>${L.todos}</span>
      <div class="btn-p">${ic('plus', '')}${L.newTodo}</div>
      <div class="btn-b">${ic('tray', '')}${L.showAll}</div>
      <span class="count">${L.todoCount}</span>
      <div class="spacer"></div>
      ${ic('ellipsis', 'icb')}
    </div>
    <div class="todos" style="margin-top:10px">
      ${L.todoList.map((d, i) => todoCard(d, TODO_STYLE[i])).join('')}</div>
  </div>`

const routineSection = L => `
  <div>
    <div class="sect">${ic('lock', '')}<span>${L.routinesHead}</span>
      <div class="spacer"></div><div class="plainbtn">${ic('plus', '')}${L.addRoutine}</div></div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin-top:10px">
      ${[[L.rSleep,'moon',C.indigo,L.rSleepWhen,L.rSleepSum],
         [L.rMeals,'fork',C.green,L.rMealsWhen,L.rMealsSum],
         [L.rWork,'calendar',C.blue,L.rWorkWhen,L.rWorkSum],
         [L.rGym,'run',C.orange,L.rGymWhen,L.rGymSum]].map(([n, i, c, s1, s2]) => `
        <div class="chip" style="--c:${c};align-items:flex-start;padding:9px 10px">
          ${ic(i, '')}
          <div class="ctext"><div class="cname">${n}</div>
            <div class="csub">${s1}</div><div class="csub">${s2}</div></div>
        </div>`).join('')}
    </div>
  </div>`

// ── timeline ────────────────────────────────────────────────────────────────
const x = h => (h / 24 * 100).toFixed(3) + '%'
const timeline = L => `
  <div class="tl">
    ${DAY_NUM.map((n, i) => `
      <div class="tlrow">
        <div class="tlday ${i === TODAY ? 'today' : ''}">
          <div class="d">${L.days[i]}</div><div class="n">${n}</div></div>
        <div class="track">
          ${Array.from({ length: 23 }, (_, k) => k + 1).map(hh =>
            `<div class="g ${hh % 3 === 0 ? 'maj' : ''}" style="left:${x(hh)}"></div>`).join('')}
          ${segmentsFor(L, i).map(s => {
            const w = s.b - s.a
            return `<div class="seg2 ${s.flex ? 'flex' : ''} ${w < 1.6 ? 'tiny' : ''}"
                         style="--c:${s.c};left:${x(s.a)};width:${x(w)}">
                      ${w > 0.7 ? `<span>${s.t}</span>` : ''}</div>`
          }).join('')}
          ${i === TODAY ? `<div class="nowbar" style="left:${x(NOW)}"></div>` : ''}
        </div>
        <div class="tlfree">${L.hoursLeft(h1(freeHours(i)))}</div>
      </div>`).join('')}
    <div class="axis">
      <div class="tlday"></div>
      <div class="ruler">${[0, 3, 6, 9, 12, 15, 18, 21, 24].map(hh =>
        `<b style="left:${x(hh)}">${hh}</b>`).join('')}</div>
      <div class="tlfree"></div>
    </div>
  </div>`

// ── panels ──────────────────────────────────────────────────────────────────
const stepsSheet = L => `
  <div class="sheet">
    <div class="panel">
      <div class="phead" style="background:var(--card)">
        <div style="display:flex;align-items:flex-start;gap:12px">
          <div style="flex:1">
            <h3 style="font-size:19px;font-weight:600">${L.todoList[0].t}</h3>
            <div style="display:flex;align-items:center;gap:6px;margin-top:6px">
              <span class="tag" style="background:rgba(255,149,0,.15);color:var(--orange)">${L.currentStep}</span>
              <span style="font-size:14px;font-weight:500">${L.todoList[0].step}</span>
            </div>
          </div>
          <div style="font-size:30px;font-weight:600;color:${C.blue};font-variant-numeric:tabular-nums">40%</div>
          <div class="btn-def">${L.done}</div>
        </div>
        <div style="height:5px;border-radius:3px;background:rgba(0,0,0,.09);overflow:hidden">
          <i style="display:block;height:100%;width:40%;background:${C.blue}"></i></div>
        <div style="display:flex;align-items:center;gap:8px;color:var(--ink2)">
          ${ic('sum', 'icb')}<span style="font-size:14px;font-weight:600">${L.allDone(L.totalHours)}</span>
          <span style="font-size:11px;color:rgba(0,0,0,.35)">${L.splitAcross}</span>
        </div>
      </div>
      <div class="hr"></div>
      <div class="steps">
        <div style="font-size:13px;font-weight:600;color:var(--ink2);padding:0 8px 4px">${L.steps}</div>
        ${L.stepList.map(([k, t, hr, pc]) => `
          <div class="steprow ${k === 'ok' ? 'ok' : k === 'cur' ? 'cur' : ''}">
            ${ic(k === 'ok' ? 'checkCircle' : k === 'cur' ? 'playCircle' : 'circle', 'num')}
            <div style="flex:1">
              <div class="st" style="${k === 'cur' ? 'font-weight:600' : ''}">${t}</div>
              ${k === 'frag' ? `<div class="tag frag" style="display:inline-flex;margin-top:4px">
                   ${ic('boltFill', '')}${L.fragment}</div>` : ''}
            </div>
            <div class="hrs">${hr} h</div><div class="pct">${pc}%</div>
          </div>`).join('')}
      </div>
      <div class="hr"></div>
      <div style="padding:12px 20px;display:flex;align-items:center;gap:8px;background:var(--window)">
        <div style="flex:1;height:26px;border-radius:6px;background:#fff;border:.5px solid rgba(0,0,0,.18);
                    display:flex;align-items:center;padding:0 9px;font-size:13px;color:rgba(0,0,0,.32)">
          ${L.addStep}</div>
        <div class="btn-b">${ic('wand', '')}${L.splitHelper}</div>
      </div>
    </div>
  </div>`

const reviewSheet = L => `
  <div class="sheet">
    <div class="panel">
      <div class="phead">
        <h3>${L.rvTitle}</h3>
        <div class="tiles">
          <div class="tile"><div class="lbl">${L.rvDone}</div><div class="v" style="color:${C.green}">5</div></div>
          <div class="tile"><div class="lbl">${L.rvPartial}</div><div class="v" style="color:${C.yellow}">2</div></div>
          <div class="tile"><div class="lbl">${L.rvSkipped}</div><div class="v" style="color:${C.red}">1</div></div>
          <div class="tile"><div class="lbl">${L.rvPending}</div><div class="v" style="color:var(--ink2)">1</div></div>
        </div>
      </div>
      <div class="hr"></div>
      <div class="rows">
        ${L.rvRows.map(([k, d, b, band, note]) => `
          <div class="row ${k === 'done' ? 'done' : ''}">
            ${ic(k === 'done' ? 'checkCircle' : k === 'part' ? 'halfCircle' : k === 'skip' ? 'slashCircle' : 'circle', 'ck')
              .replace('class="ck"', `class="ck" style="color:${k === 'done' ? C.green : k === 'part' ? C.yellow : k === 'skip' ? C.red : 'rgba(0,0,0,.3)'}"`)}
            <div class="dw">${L.days[d]}</div>
            <div style="flex:1">
              <div class="rt">${L.blocks[b]}</div>
              <div class="rs">${band}</div>
              <div class="note ${note ? '' : 'empty'}">${note || L.rvNotePlaceholder}</div>
            </div>
          </div><div class="hr"></div>`).join('')}
      </div>
      <div class="pfoot"><div class="btn-def">${L.done}</div></div>
    </div>
  </div>`

const timerWindow = L => win(L, `
  <div class="timer" style="--c:${C.blue}">
    <div class="tname">${ic('calendar', '')}<span>${L.blocks[2]}</span></div>
    <div class="trange">${L.tRange}</div>
    <div class="big">23:41<em>${L.tLeft}</em></div>
    <div class="ends">${L.tEnds}</div>
    <div class="ring"><i style="width:61%"></i></div>
    <div class="acts">
      <div class="btn-b">${ic('pause', '')}${L.tPause}</div>
      <div class="btn-b">${L.tPlus5}</div>
      <div class="btn-b">${L.tPlus10}</div>
      <div class="btn-b">${ic('stop', '')}${L.tStop}</div>
    </div>
  </div>
  <div class="upnext">
    <div class="ttl">${L.tRest}</div>
    ${L.tUpNext.map(([i, c, n, t]) => `
      <div class="uprow" style="--c:${c}">${ic(i, '')}<div class="un">${n}</div><div class="ut">${t}</div></div>`).join('')}
  </div>`, 'sm', L.timer, '')

// ── shots ───────────────────────────────────────────────────────────────────
const body = (...parts) => `<div class="body">${parts.join('')}</div>`

const shots = L => [
  { id:'01-week', bg:['#5856D6', '#0A84FF'],
    inner: win(L, body(weekHeader(L, 'plan', true), summary(L), weekGrid(L))) },

  { id:'02-drag', bg:['#0A84FF', '#32ADE6'],
    inner: win(L, body(weekHeader(L), weekGrid(L, 3), todoSection(L)) +
      `<div class="ghost" style="left:526px;top:353px;width:206px">
         <div class="todo" style="--c:${C.purple};background:#fff;border-color:rgba(0,0,0,.14)">
           <div class="lane"></div>
           <div style="min-width:0;flex:1"><div class="tt">${L.todoList[1].t}</div>
             <div class="meta"><span>${L.todoList[1].hrs}</span></div></div>
         </div></div>
       <div class="cursor" style="left:616px;top:411px">${ic('cursor', '')}</div>`) },

  { id:'03-timeline', bg:['#FF9500', '#FF3B30'],
    inner: win(L, body(weekHeader(L, 'day'), timeline(L), todoSection(L), routineSection(L))) },

  { id:'04-steps', bg:['#34C759', '#30B0C7'],
    inner: `<div class="stack">${win(L, body(weekHeader(L), weekGrid(L), todoSection(L)), 'dim')}${stepsSheet(L)}</div>` },

  { id:'05-timer', bg:['#AF52DE', '#5856D6'],
    inner: `<div class="stack">${win(L, body(weekHeader(L, 'day'), timeline(L), todoSection(L), routineSection(L)), 'dim')}
            <div class="float">${timerWindow(L)}</div></div>` },

  { id:'06-review', bg:['#FF2D55', '#FF9500'],
    inner: `<div class="stack">${win(L, body(weekHeader(L), weekGrid(L), todoSection(L)), 'dim')}${reviewSheet(L)}</div>` },
]

const EXTRA = `
.stack { position:relative; display:flex; justify-content:center; width:1300px; flex:0 0 auto }
.win.dim::after { content:""; position:absolute; inset:0; background:rgba(0,0,0,.17); z-index:2 }
.sheet { position:absolute; top:64px; left:50%; transform:translateX(-50%); width:780px; z-index:3;
         border-radius:12px; overflow:hidden; box-shadow:0 26px 60px rgba(0,0,0,.34) }
.float { position:absolute; top:78px; right:26px; z-index:3 }
.float .win { box-shadow:0 26px 60px rgba(0,0,0,.38) }
`

const page = L => {
  const list = shots(L)
  return `<!doctype html>
<html lang="${L.lang}"><head><meta charset="utf-8">
<title>${L.app} — App Store screenshots (${L.lang})</title>
<link rel="stylesheet" href="style.css"><style>${EXTRA}</style></head>
<body>
${list.map((s, i) => `<section class="shot" id="${s.id}"
   style="background:linear-gradient(158deg, ${s.bg[0]}, ${s.bg[1]})">
  <div class="cap"><h2>${L.caps[i][0]}</h2><p>${L.caps[i][1]}</p></div>
  ${s.inner}
</section>`).join('\n')}
</body></html>`
}

const LOCALES = Object.keys(STRINGS)
for (const loc of LOCALES) {
  writeFileSync(join(HERE, `index-${loc}.html`), page(STRINGS[loc]))
  console.log(`wrote index-${loc}.html`)
}

if (!process.argv.includes('--html')) {
  // Local install first; fall back to a global one (NPM_GLOBAL_ROOT=$(npm root -g)).
  const { chromium } = await import('playwright')
    .catch(() => import(join(process.env.NPM_GLOBAL_ROOT || '', 'playwright/index.mjs')))
  const browser = await chromium.launch()
  const page_ = await browser.newPage({ viewport:{ width:1440, height:900 }, deviceScaleFactor:2 })
  for (const loc of LOCALES) {
    const outDir = join(HERE, loc)
    mkdirSync(outDir, { recursive: true })
    await page_.goto('file://' + join(HERE, `index-${loc}.html`))
    await page_.waitForTimeout(700)
    // One scale for the whole set, so every window reads the same size.
    const fit = await page_.evaluate(() => {
      const els = [...document.querySelectorAll('.shot')].map(shot =>
        [shot, shot.querySelector('.stack') || shot.querySelector('.win')])
      const k = Math.min(...els.map(([shot, el]) =>
        (900 - (el.getBoundingClientRect().top - shot.getBoundingClientRect().top) - 20) / el.offsetHeight), 1)
      for (const [, el] of els) { el.style.transformOrigin = 'top center'; el.style.transform = `scale(${k})` }
      return +k.toFixed(3)
    })
    console.log(`${loc}: fit ${fit}`)
    for (const s of shots(STRINGS[loc])) {
      const path = join(outDir, `${s.id}.png`)
      await page_.locator(`[id="${s.id}"]`).screenshot({ path })
      console.log('rendered', path)
    }
  }
  await browser.close()
}
