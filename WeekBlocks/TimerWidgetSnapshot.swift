//
//  TimerWidgetSnapshot.swift
//  무지개 공방
//
//  앱이 위젯에 건네는 **오늘의 타임라인 한 장.**
//
//  위젯은 SwiftData store를 못 연다(앱 샌드박스 안이다). 그래서 앱이 오늘·내일의 일정 조각과
//  따로 세는 타이머를 App Group에 적어 두고, 위젯은 그걸 읽어 **일정 경계마다 스스로 넘어간다.**
//  남은 시간은 위젯이 매초 그리지 않는다 — 끝 시각만 건네면 시스템이 센다 (Text(timerInterval:)).
//
//  ⚠️ 앱과 위젯 **두 타깃에 같이 들어간다** (→ WeekBlocks.project.yml). Foundation·SwiftUI 말고는
//     아무것도 부르지 말 것 — 앱의 모델·테마를 부르면 위젯이 빌드되지 않는다.
//

import Foundation
import SwiftUI

struct TimerWidgetSnapshot: Codable, Equatable {
    /// 타임라인의 한 조각 (→ ScheduleSlot).
    struct Item: Codable, Equatable, Hashable {
        var title: String
        var iconName: String
        /// 무지개·루틴 색. nil이면 액센트.
        var colorHex: String?
        var start: Date
        var end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
        func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// 일정 없이 따로 세는 타이머 (→ TaskTimer). 일정에 있는 일은 여기 오지 않는다 — 타임라인이 센다.
    struct Direct: Codable, Equatable {
        var title: String
        var iconName: String
        var colorHex: String?
        var planned: TimeInterval
        /// 흐르는 중이면 끝나는 시각. 멈춰 있으면 nil.
        var end: Date?
        /// 멈춰 있을 때 남은 시간.
        var pausedRemaining: TimeInterval?
    }

    var items: [Item]
    var direct: Direct?

    static let empty = TimerWidgetSnapshot(items: [], direct: nil)

    // MARK: 읽기 — 앱의 ScheduleClock과 같은 규칙

    /// 지금 하고 있는 것. 겹쳐 있으면 가장 짧은 것 (→ ScheduleClock.current).
    func current(at date: Date) -> Item? {
        items.filter { $0.contains(date) }.min { $0.duration < $1.duration }
    }

    /// 그 뒤에 올 것들 (시작 순).
    func upcoming(after date: Date, limit: Int) -> [Item] {
        Array(items.filter { $0.start > date }.sorted { $0.start < $1.start }.prefix(limit))
    }

    // MARK: 저장

    static let appGroupID = "QGAQ3AY3R3.group.com.devkoan.ScheduleDensity"
    static let widgetKind = "TimerWidget"
    private static let key = "timerWidget.snapshot"

    static func load() -> TimerWidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: key),
              let snap = try? JSONDecoder().decode(TimerWidgetSnapshot.self, from: data)
        else { return .empty }
        return snap
    }

    /// 적는다. 전과 같으면 안 적고 false — 위젯을 괜히 다시 그리게 하지 않으려고 (새로 고침에는 하루 한도가 있다).
    @discardableResult
    func save() -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self) else { return false }
        if defaults.data(forKey: Self.key) == data { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    // MARK: 색

    static func color(_ hex: String?) -> Color {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return .accentColor }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return .accentColor }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
