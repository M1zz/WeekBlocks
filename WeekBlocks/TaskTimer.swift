//
//  TaskTimer.swift
//  무지개 공방
//
//  지금 하고 있는 하나와, 거기 남은 시간.
//
//  한 주를 짜는 일과 하루를 사는 일은 다르다. 계획은 "운동 1시간"이라고 적혀 있지만,
//  막상 시작하면 그 한 시간이 어디까지 왔는지는 아무 데도 적혀 있지 않았다.
//  타이머는 계획에 적힌 길이를 그대로 가져와 거꾸로 센다 — 60:00 에서 0:00 으로.
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
    func start(token: String, title: String, plannedSeconds: Double,
               iconName: String = "timer", colorName: String? = nil) {
        target = TimerTarget(token: token, title: title, colorName: colorName,
                             iconName: iconName, plannedSeconds: max(60, plannedSeconds))
        accumulated = 0
        now = Date()
        runningSince = now
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
        target = t
        // 다시 0 위로 올라왔으면 종이 한 번 더 울릴 자격이 있다.
        if remaining > 0 { didRingZero = false }
        persist()
    }

    /// 처음부터 다시 센다.
    func restart() {
        guard isActive else { return }
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
        }
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
        if isRunning { startTicking() }
    }
}

// MARK: - 계획에서 바로 시작하기

extension TaskTimer {
    /// 계획 블록을 센다. 길이는 블록에 적힌 그대로.
    func start(block: PlanBlock) {
        start(token: block.dragToken,
              title: block.title,
              plannedSeconds: block.durationHours * 3600,
              iconName: "square.stack.3d.up")
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
