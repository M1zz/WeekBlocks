//
//  TimerWidgetBridge.swift
//  무지개 공방
//
//  타임라인과 타이머를 위젯에 건넨다 (→ TimerWidgetSnapshot, WeekBlocksWidget).
//
//  맨 위 타이머 알약이 분마다 부른다. 내용이 바뀌었을 때만 적고 위젯을 다시 그리게 한다 —
//  위젯은 받은 한 장으로 일정 경계마다 스스로 넘어가므로, 앱이 분마다 깨울 필요가 없다.
//

import Foundation
import WidgetKit

enum TimerWidgetBridge {
    static func publish(slots: [ScheduleSlot], timer: TaskTimer, focus: String = "", now: Date = Date()) {
        // 지금부터 내일 끝까지. 지나간 조각은 위젯이 쓸 일이 없다.
        let items = slots
            .filter { $0.end > now }
            .map { TimerWidgetSnapshot.Item(title: $0.title, iconName: $0.iconName,
                                            colorHex: $0.colorName.flatMap(paletteHex),
                                            start: $0.start, end: $0.end) }
        // 같은 조각이 두 번(자정을 넘긴 잠 등) 오면 하나로.
        var seen = Set<TimerWidgetSnapshot.Item>()
        let unique = items.filter { seen.insert($0).inserted }.sorted { $0.start < $1.start }

        let direct = timer.target.map { t in
            TimerWidgetSnapshot.Direct(
                title: t.title, iconName: t.iconName,
                colorHex: t.colorName.flatMap(paletteHex),
                planned: t.plannedSeconds,
                // 끝은 분 단위로 자른다 — 매번 몇 ms씩 달라져 '바뀌었다'고 새로 그리는 일을 막는다.
                end: timer.isRunning ? Date(timeIntervalSince1970: (now.addingTimeInterval(timer.remaining)
                    .timeIntervalSince1970).rounded()) : nil,
                pausedRemaining: timer.isRunning ? nil : timer.remaining.rounded())
        }

        // 겹친 것 중 사람이 고른 것 — 위젯도 같은 것을 센다. 그 일정이 끝나면 위젯이 스스로 기본 규칙으로 돌아간다.
        let chosen = ScheduleClock.current(slots, at: now, focus: focus).flatMap { slot -> TimerWidgetSnapshot.Item? in
            guard !focus.isEmpty, ScheduleFocus.key(of: slot) == focus else { return nil }
            return TimerWidgetSnapshot.Item(title: slot.title, iconName: slot.iconName,
                                            colorHex: slot.colorName.flatMap(paletteHex),
                                            start: slot.start, end: slot.end)
        }

        let snap = TimerWidgetSnapshot(items: unique, direct: direct, chosen: chosen)
        if snap.save() {
            WidgetCenter.shared.reloadTimelines(ofKind: TimerWidgetSnapshot.widgetKind)
        }
    }
}
