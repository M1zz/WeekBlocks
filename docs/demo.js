// 무지개 공방 웹 체험: 고정 루틴을 깔고 남은 시간에 할 일을 놓아 본다.
// 루틴 값은 앱의 첫 실행 안내(OnboardingView 의 제안)와 같다: 잠 매일 23:00부터 8시간, 끼니 주 17.5시간(하루 세 번),
// 일·학교 평일 9시간, 운동 월·수·금 1시간. 한 주는 168시간. 요일 칸의 무지개는 그날 할 일 하나에 한 칸,
// 빨강부터 차례로 찬다 (TodoRainbow). 할 일 길이는 체험용 예시다.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);
  const lang = document.documentElement.lang;

  // [요일별 시간(월~일)]
  const ROUTINES = [
    { color: "#5856D6", days: [8, 8, 8, 8, 8, 8, 8] },
    { color: "#34C759", days: [2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5] },
    { color: "#007AFF", days: [9, 9, 9, 9, 9, 0, 0] },
    { color: "#FF9500", days: [1, 0, 1, 0, 1, 0, 0] },
  ];
  const TODO_HOURS = [3, 1.5, 2, 1, 0.5];
  const SPECTRUM = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#5856D6", "#AF52DE"];

  const on = ROUTINES.map(() => true);
  const placed = TODO_HOURS.map(() => -1);   // 할 일마다 놓인 요일 (-1 = 목록)
  let picked = -1;

  const num = new Intl.NumberFormat(lang, { maximumFractionDigits: 1 });
  const h = n => T.h.replace("{n}", num.format(n));
  const dayName = new Intl.DateTimeFormat(lang, { weekday: "short" });
  const DAYS = [...Array(7)].map((_, i) => dayName.format(new Date(2024, 0, 1 + i)));   // 2024-01-01 은 월요일

  root.innerHTML = `
    <div class="wb-top">
      <div class="wb-stats">
        <div><small>${T.week}</small><b>${h(168)}</b></div>
        <div><small>${T.fixed}</small><b data-k="fixed"></b></div>
        <div><small>${T.planned}</small><b data-k="planned"></b></div>
        <div class="left"><small>${T.left}</small><b data-k="left"></b></div>
      </div>
      <div class="wb-bar" aria-hidden="true"><i class="fixed"></i><i class="planned"></i></div>
      <div class="wb-routines" role="group" aria-label="${T.routinesLabel}">
        ${T.routines.map((r, i) => `<button type="button" class="wb-routine" data-routine="${i}" aria-pressed="true"
          style="--c:${ROUTINES[i].color}"><span>${r.name}</span><small>${r.detail}</small></button>`).join("")}
      </div>
    </div>
    <div class="wb-week">${DAYS.map((d, i) => `<div class="wb-day" data-day="${i}" role="button" tabindex="0">
        <b>${d}</b><small class="wb-free"></small><div class="wb-rainbow" aria-hidden="true">${SPECTRUM.map(() => "<i></i>").join("")}</div>
        <div class="wb-placed"></div></div>`).join("")}</div>
    <div class="wb-list">
      <p class="muted small">${T.hint}</p>
      <div class="wb-todos"></div>
    </div>`;

  const $ = s => root.querySelector(s), $$ = s => [...root.querySelectorAll(s)];
  const todoBtn = i => `<button type="button" class="wb-todo${picked === i ? " picked" : ""}" draggable="true" data-todo="${i}"
      aria-pressed="${picked === i}">${T.todos[i]} <small>${h(TODO_HOURS[i])}</small></button>`;

  function render() {
    const routineDay = d => ROUTINES.reduce((s, r, i) => s + (on[i] ? r.days[d] : 0), 0);
    const planDay = d => TODO_HOURS.reduce((s, x, i) => s + (placed[i] === d ? x : 0), 0);
    const fixed = [...Array(7)].reduce((s, _, d) => s + routineDay(d), 0);
    const planned = TODO_HOURS.reduce((s, x, i) => s + (placed[i] >= 0 ? x : 0), 0);
    $('[data-k="fixed"]').textContent = h(fixed);
    $('[data-k="planned"]').textContent = h(planned);
    $('[data-k="left"]').textContent = h(168 - fixed - planned);
    $(".wb-bar .fixed").style.width = `${fixed / 1.68}%`;
    $(".wb-bar .planned").style.width = `${planned / 1.68}%`;
    $$(".wb-routine").forEach((b, i) => b.setAttribute("aria-pressed", on[i]));

    $$(".wb-day").forEach((el, d) => {
      const free = 24 - routineDay(d) - planDay(d);
      const mine = TODO_HOURS.map((_, i) => i).filter(i => placed[i] === d);
      el.querySelector(".wb-free").textContent = T.dayLeft.replace("{h}", h(Math.max(0, free)));
      el.classList.toggle("over", free < 0);
      el.classList.toggle("target", picked >= 0);
      el.setAttribute("aria-label", `${DAYS[d]}, ${el.querySelector(".wb-free").textContent}`);
      [...el.querySelectorAll(".wb-rainbow i")].forEach((c, k) =>
        c.style.background = k < mine.length ? SPECTRUM[k] : "");
      el.querySelector(".wb-placed").innerHTML = mine.map((i, k) =>
        `<button type="button" class="wb-todo in" data-back="${i}" style="--c:${SPECTRUM[Math.min(k, 6)]}">${T.todos[i]} <small>${h(TODO_HOURS[i])}</small></button>`).join("");
    });
    $(".wb-todos").innerHTML = TODO_HOURS.map((_, i) => i).filter(i => placed[i] < 0).map(todoBtn).join("")
      || `<p class="muted small">${T.allPlaced}</p>`;
  }

  function place(i, d) { placed[i] = d; picked = -1; render(); }

  root.addEventListener("click", e => {
    const r = e.target.closest("[data-routine]"), t = e.target.closest("[data-todo]"),
          back = e.target.closest("[data-back]"), day = e.target.closest("[data-day]");
    if (r) { on[r.dataset.routine] = !on[r.dataset.routine]; render(); }
    else if (t) { picked = picked === +t.dataset.todo ? -1 : +t.dataset.todo; render(); }
    else if (back) { placed[back.dataset.back] = -1; render(); }
    else if (day && picked >= 0) place(picked, +day.dataset.day);
  });
  root.addEventListener("keydown", e => {
    const day = e.target.closest("[data-day]");
    if (day && (e.key === "Enter" || e.key === " ") && picked >= 0) { e.preventDefault(); place(picked, +day.dataset.day); }
  });
  root.addEventListener("dragstart", e => {
    const t = e.target.closest("[data-todo]");
    if (t) { e.dataTransfer.setData("text/plain", t.dataset.todo); picked = +t.dataset.todo; }
  });
  root.addEventListener("dragover", e => { if (e.target.closest("[data-day]")) e.preventDefault(); });
  root.addEventListener("drop", e => {
    const day = e.target.closest("[data-day]");
    if (!day) return;
    e.preventDefault();
    place(+e.dataTransfer.getData("text/plain"), +day.dataset.day);
  });

  render();
})();
