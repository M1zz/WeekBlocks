//
//  TaskTimer.swift
//  무지개 공방
//
//  지금 하고 있는 하나와, 거기 남은 시간.
//
//  한 주를 짜는 일과 하루를 사는 일은 다르다. 계획은 "운동 1시간"이라고 적혀 있지만,
//  막상 시작하면 그 한 시간이 어디까지 왔는지는 아무 데도 적혀 있지 않았다.
//  타이머는 계획에 적힌 길이를 그대로 가져와 거꾸로 센다 — 60:00 에서 0:00 으로.
//  일정에 묶어 켜면 **끝나는 시각이 일정의 끝과 같다** — 늦게 켜든 일찍 켜든 멈췄다 이어가든 (→ binding).
//
//  ⚠️ **기기에만 남는다.** CloudKit으로 오가는 SwiftData 스키마에는 손대지 않는다.
//     "지금 이 자리에서 하고 있다"는 사실은 다른 기기로 건너갈 이유가 없고,
//     스키마를 건드리면 iOS '욕망의 무지개'와의 마이그레이션이 걸린다(→ BacklogItem.swift).
//     그래서 상태는 UserDefaults에 JSON 한 덩어리로 둔다.
//

import Foundation
import Observation
import AppKit

// MARK: - 세고 있는 일

/// 타이머가 붙잡고 있는 대상. 모델을 직접 들지 않는다 —
/// 블록이 지워지거나 앱이 꺼졌다 켜져도 타이머는 자기 힘으로 서 있어야 하기 때문이다.
struct TimerTarget: Codable, Equatable {
    /// 되찾는 열쇠. 계획 블록은 `PlanBlock.dragToken`, 고정 루틴은 `routine:<이름>`.
    /// 같은 일을 두 번 시작하려 할 때 "이미 세고 있다"고 알아보는 데 쓴다.
    var token: String
    var title: String
    /// 팔레트 색 이름(→ Theme.paletteColor). 루틴이면 그 루틴 색, 계획 블록이면 nil = 액센트.
    var colorName: String?
    var iconName: String
    /// 일정에 적힌 길이(초). 여기서부터 거꾸로 센다.
    var plannedSeconds: Double
    /// 일정 한가운데서 켠 타이머가 따르는 **일정의 끝.** 이 시각이 지나면 타이머는 스스로 물러난다 —
    /// 끝난 일정을 계속 세고 있으면 지금 하는 일을 가린다. nil이면 일정과 묶이지 않은 타이머.
    var scheduledEnd: Date? = nil
}

// MARK: - 스토어

@Observable
final class TaskTimer {
    static let shared = TaskTimer()

    /// 지금 세고 있는 일. nil이면 타이머가 서 있지 않다.
    private(set) var target: TimerTarget?
    /// 지금 흐르고 있는 구간의 시작. nil이면 멈춰 있다(일시정지).
    private(set) var runningSince: Date?
    /// 멈추기 전까지 이미 흘려보낸 시간.
    private(set) var accumulated: TimeInterval = 0
    /// 화면을 다시 그리게 하는 심장. 0.5초마다 뛴다.
    private(set) var now: Date = Date()

    /// 0을 지나며 한 번만 울린다. 초과 시간을 세는 동안 계속 울리면 안 된다.
    private var didRingZero = false
    private var ticker: Timer?

    private init() { restore() }

    // MARK: 읽기

    var isActive: Bool { target != nil }
    var isRunning: Bool { runningSince != nil }

    /// 시작한 뒤 실제로 흐른 시간. 멈춰 있는 동안은 늘지 않는다.
    var elapsed: TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// 남은 시간. 계획보다 오래 붙잡고 있으면 음수가 된다 — 그것도 사실이므로 감추지 않는다.
    var remaining: TimeInterval { (target?.plannedSeconds ?? 0) - elapsed }

    var isOvertime: Bool { remaining < 0 }

    /// 0~1. 초과해도 1을 넘지 않는다(고리가 두 바퀴 돌지 않게).
    var progress: Double {
        guard let planned = target?.plannedSeconds, planned > 0 else { return 0 }
        return min(1, max(0, elapsed / planned))
    }

    /// 이대로 가면 끝나는 시각. 멈춰 있으면 "지금부터 남은 만큼"으로 본다.
    var projectedEnd: Date { now.addingTimeInterval(max(0, remaining)) }

    /// 이 열쇠의 일을 지금 세고 있는가.
    func isTiming(_ token: String) -> Bool { target?.token == token }

    // MARK: 쓰기

    /// 새로 시작한다. 이미 다른 일을 세고 있었다면 그건 그대로 끝난다 —
    /// 한 번에 하나만 센다. 두 개를 동시에 세면 어느 쪽도 믿을 수 없다.
    ///
    /// `scheduledStart` — 이 일정이 적힌 시작 시각. 오늘 아직 안 끝난 일정이면 타이머가 **그 일정의 끝**에
    /// 묶인다: 90분 일정에 45분 남았다면 90분 중 45분이 흐른 타이머로, 시작 전에 켜면 끝까지 남은 만큼으로 선다.
    func start(token: String, title: String, plannedSeconds: Double,
               scheduledStart: Date? = nil,
               iconName: String = "timer", colorName: String? = nil) {
        let t0 = Date()
        let bind = Self.binding(scheduledStart: scheduledStart, planned: plannedSeconds, now: t0)
        // **지금 진행 중인 일정은 따로 세지 않는다.** 타임라인이 이미 세고 있다 (→ ScheduleClock).
        // 따로 세는 타이머를 하나 더 세우면 그게 알약을 차지하고, 일정과 어긋나기 시작한다.
        if bind != nil, let scheduledStart, t0 >= scheduledStart {
            stop()
            return
        }
        let planned = bind?.planned ?? max(60, plannedSeconds)
        target = TimerTarget(token: token, title: title, colorName: colorName,
                             iconName: iconName, plannedSeconds: planned,
                             scheduledEnd: bind?.end)
        now = t0
        runningSince = t0
        // 남은 시간 = 일정의 끝 − 지금. 같은 t0으로 셈해야 끝이 한 치도 안 어긋난다.
        accumulated = bind.map { planned - $0.end.timeIntervalSince(t0) } ?? 0
        didRingZero = false
        persist()
        startTicking()
    }

    func pause() {
        guard let since = runningSince else { return }
        accumulated += Date().timeIntervalSince(since)
        runningSince = nil
        now = Date()
        persist()
        stopTicking()
    }

    func resume() {
        guard isActive, runningSince == nil else { return }
        now = Date()
        runningSince = now
        // 일정에 묶인 타이머는 멈춘 동안에도 일정이 흘렀다 — 끝은 그대로, 남은 시간을 다시 맞춘다.
        if let end = target?.scheduledEnd, let planned = target?.plannedSeconds {
            accumulated = planned - end.timeIntervalSince(now)
        }
        persist()
        startTicking()
    }

    func toggle() { isRunning ? pause() : resume() }

    /// 끝낸다. 세던 것을 지우고 자리를 비운다.
    func stop() {
        target = nil
        runningSince = nil
        accumulated = 0
        didRingZero = false
        persist()
        stopTicking()
    }

    /// 시간을 더 준다. 계획을 늘리는 것이지 이미 쓴 시간을 지우는 게 아니다.
    func extend(minutes: Double) {
        guard var t = target else { return }
        t.plannedSeconds += minutes * 60
        // 일부러 더 준 시간이다 — 일정의 끝도 그만큼 밀어야 곧바로 물러나지 않는다.
        t.scheduledEnd = t.scheduledEnd?.addingTimeInterval(minutes * 60)
        target = t
        // 다시 0 위로 올라왔으면 종이 한 번 더 울릴 자격이 있다.
        if remaining > 0 { didRingZero = false }
        persist()
    }

    /// 처음부터 다시 센다.
    func restart() {
        guard isActive else { return }
        // 처음부터 세겠다는 것은 일정을 떠나겠다는 것이다.
        target?.scheduledEnd = nil
        accumulated = 0
        now = Date()
        runningSince = now
        didRingZero = false
        persist()
        startTicking()
    }

    // MARK: 심장

    private func startTicking() {
        stopTicking()
        // 0.5초 — 초 단위 표시가 한 박자 늦게 넘어가는 것을 막을 만큼만 자주.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // 창을 끌거나 메뉴를 열어 둔 동안에도 숫자가 멈추지 않게 common 모드로.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        if !didRingZero, isActive, remaining <= 0 {
            didRingZero = true
            NSSound(named: "Glass")?.play()
            Telemetry.record(.timerFinished)
        }
        releaseIfScheduleEnded()
    }

    /// 따르던 일정이 끝났으면 물러난다. 그 뒤로는 일정 기준 얼굴이 다음 것을 센다.
    private func releaseIfScheduleEnded() {
        guard let end = target?.scheduledEnd, Date() >= end else { return }
        stop()
    }

    /// **타임라인에 맞춘다.** 세고 있는 일이 오늘 일정에 서 있다면 타이머는 그 일정을 따른다:
    /// - 지금 그 일정 안이면 → 따로 세던 것을 거둔다. 타임라인이 센다.
    /// - 오늘 아직 안 온 일정이면(일찍 시작) → 그 일정의 끝에 묶는다.
    /// - 오늘 그 일정이 이미 다 끝났으면 → 물러난다. 끝난 인터뷰를 다음 인터뷰 시간에 세고 있으면 안 된다.
    /// 일정에 없는 일(다른 날의 블록 등)은 건드리지 않는다. 우측 상단 알약이 매분 부른다.
    func reconcile(with slots: [ScheduleSlot], now date: Date = Date()) {
        guard let t = target else { return }
        // 열쇠로 먼저 찾고, 못 찾으면 이름으로. 블록 열쇠(persistentModelID)는 앱을 다시 켜면 글자가
        // 달라질 수 있다 — 그러면 되살아난 타이머가 제 일정을 못 찾아 '일정에 없는 일'로 남아
        // 다음 일정 시간까지 끝난 일을 세고 있었다.
        var mine = slots.filter { $0.id == t.token }
        if mine.isEmpty {
            let today = slots.filter { Calendar.current.isDate($0.start, inSameDayAs: date) || $0.contains(date) }
            mine = today.filter { $0.title == t.title }
        }
        guard !mine.isEmpty else { return }
        // 그 일정이 시작됐다 — 이제 타임라인이 센다. 따로 세던 것은 물러난다.
        if mine.contains(where: { $0.contains(date) }) {
            stop()
            return
        }
        let live = mine.filter { $0.start > date && Calendar.current.isDate($0.start, inSameDayAs: date) }
            .min { $0.start < $1.start }
        guard let slot = live else {
            // 오늘 서 있던 자리가 전부 지나갔다.
            if mine.contains(where: { $0.end <= date }) { stop() }
            return
        }
        if let end = t.scheduledEnd, abs(end.timeIntervalSince(slot.end)) < 1 { return }
        // 묶이지 않았거나 다른 자리에 묶여 있었다 — 이 일정의 끝으로 다시 맞춘다.
        guard let bind = Self.binding(scheduledStart: slot.start, planned: slot.duration, now: date) else { return }
        target?.scheduledEnd = bind.end
        target?.plannedSeconds = bind.planned
        now = date
        if isRunning { runningSince = date }
        accumulated = bind.planned - bind.end.timeIntervalSince(date)
        didRingZero = remaining <= 0
        persist()
    }

    // MARK: 남겨두기

    private struct Snapshot: Codable {
        var target: TimerTarget
        var runningSince: Date?
        var accumulated: TimeInterval
        var didRingZero: Bool
    }

    private static let key = "taskTimer.snapshot"

    private func persist() {
        guard let target else {
            UserDefaults.standard.removeObject(forKey: Self.key)
            return
        }
        let snap = Snapshot(target: target, runningSince: runningSince,
                            accumulated: accumulated, didRingZero: didRingZero)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// 앱을 껐다 켜도 세던 것을 이어 센다. 흐른 시간은 `runningSince`에서 다시 계산되므로
    /// 꺼져 있던 동안의 시간도 그대로 지나간 것으로 본다 — 실제로 지나갔기 때문이다.
    ///
    /// 다만 하루를 넘긴 것은 "끄고 잊어버린 타이머"다. 되살리지 않는다.
    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }

        target = snap.target
        runningSince = snap.runningSince
        accumulated = snap.accumulated
        didRingZero = snap.didRingZero
        now = Date()

        if elapsed > snap.target.plannedSeconds + 12 * 3600 {
            stop()
            return
        }
        // 꺼져 있는 동안 따르던 일정이 끝났다.
        if let end = snap.target.scheduledEnd, Date() >= end {
            stop()
            return
        }
        if isRunning { startTicking() }
    }
}

// MARK: - 계획에서 바로 시작하기

extension TaskTimer {
    /// 계획 블록을 센다. 길이는 블록에 적힌 그대로, 일정이 이미 흘렀으면 그만큼 지난 채로.
    func start(block: PlanBlock, scheduledStart: Date? = nil, colorName: String? = nil) {
        let planned = block.durationHours * 3600
        start(token: block.dragToken,
              title: block.title,
              plannedSeconds: planned,
              scheduledStart: scheduledStart,
              iconName: "square.stack.3d.up",
              colorName: colorName)
    }

    /// 이 일정에 묶어 켜면 타이머가 어떻게 서는가. 묶을 수 없으면 nil — 적힌 길이를 지금부터 센다.
    ///
    /// - 지금이 일정 안: 길이는 적힌 그대로, 끝은 일정의 끝 (이미 흐른 몫은 지난 채로).
    /// - 오늘 아직 안 온 일정: 끝은 일정의 끝, 길이는 지금부터 그 끝까지.
    /// - 끝난 일정 · 다른 날 일정: 묶지 않는다.
    static func binding(scheduledStart start: Date?, planned: TimeInterval, now: Date = Date())
    -> (planned: TimeInterval, end: Date)? {
        guard let start, planned > 0 else { return nil }
        let end = start.addingTimeInterval(planned)
        guard end > now else { return nil }
        if now >= start { return (planned, end) }
        guard Calendar.current.isDate(start, inSameDayAs: now) else { return nil }
        return (end.timeIntervalSince(now), end)
    }

    /// 고정 루틴을 센다. 길이는 루틴 한 번의 길이.
    /// 쿼터(끼니 등)는 회당 시간을 따로 넘겨 받는다 — 루틴 자체에는 주간 합계만 적혀 있다.
    func start(routine: Routine, hours: Double? = nil) {
        start(token: Self.token(for: routine),
              title: routine.name,
              plannedSeconds: (hours ?? routine.durationHours) * 3600,
              iconName: routine.iconName,
              colorName: routine.colorName)
    }

    static func token(for routine: Routine) -> String { "routine:\(routine.name)" }
}

// MARK: - 표기

/// 남은 시간을 타이머 숫자로. 두 시간 미만은 분:초(1시간 → `60:00`),
/// 그 위는 시:분:초로 적는다 — `180:00`은 사람이 한눈에 읽지 못한다.
/// 계획을 넘겼으면 앞에 `+`를 달아 초과분을 센다.
func formatCountdown(_ seconds: Double) -> String {
    let over = seconds < 0
    let total = Int(abs(seconds).rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    let body = abs(seconds) < 7200
        ? String(format: "%d:%02d", total / 60, s)
        : String(format: "%d:%02d:%02d", h, m, s)
    return over ? "+" + body : body
}
