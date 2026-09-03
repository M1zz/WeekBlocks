//
//  CalendarImport.swift
//  WeekBlocks
//
//  **맥 캘린더에 이미 적혀 있는 것을 한 주에 옮겨 놓는다.**
//
//  회의·약속처럼 이미 시각이 박힌 일정을 손으로 또 적게 하면, 앱이 계획을 돕는 게 아니라
//  베껴 쓰기를 시킨다. 그래서 읽어 온다.
//
//  ⚠️ **한 방향이다.** 캘린더 → 앱. 이 앱은 사용자의 진짜 캘린더에 한 글자도 쓰지 않는다.
//     권한도 그렇게 말하고, 실제로도 `EKEventStore`에 저장 계열 호출이 없다.
//     양방향으로 바꾸고 싶어지면 그때는 '사고가 나면 남의 일정이 지워진다'를 먼저 풀 것.
//
//  ⚠️ 고르는 단위는 **캘린더**다 (일정 하나하나가 아니라). 한 번 정해두면 손이 안 가고,
//     '업무만 가져오기' 같은 실제 쓰임과도 맞는다.
//

import Foundation
import EventKit
import SwiftData

@MainActor
@Observable
final class CalendarBridge {
    static let shared = CalendarBridge()

    private let store = EKEventStore()
    private static let selectionKey = "calendar.selectedIDs"

    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// 권한이 있을 때만 채워진다.
    private(set) var calendars: [EKCalendar] = []
    private(set) var isWorking = false
    /// 막혔을 때 화면에 그대로 보여줄 말. 조용히 실패하면 단추가 고장 난 줄 안다.
    private(set) var failureMessage: String?

    private init() { reloadCalendarsIfAllowed() }

    /// 읽어 올 캘린더들. 비어 있으면 **아무것도 안 가져온다** — 전부 가져오는 것보다
    /// 아무것도 안 가져오는 쪽이 낫다. 남의 개인 일정이 주간 계획에 쏟아지는 사고를 막는다.
    var selectedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.selectionKey) }
    }

    var hasAccess: Bool { status == .fullAccess }

    func toggle(_ calendar: EKCalendar) {
        var ids = selectedIDs
        if ids.contains(calendar.calendarIdentifier) {
            ids.remove(calendar.calendarIdentifier)
        } else {
            ids.insert(calendar.calendarIdentifier)
        }
        selectedIDs = ids
    }

    func isSelected(_ calendar: EKCalendar) -> Bool {
        selectedIDs.contains(calendar.calendarIdentifier)
    }

    /// 권한을 청한다.
    ///
    /// ⚠️ 일정을 **읽으려면** macOS 14부터 전체 접근(full access)이어야 한다.
    ///    쓰기 전용(write-only)은 말 그대로 쓰기만 되는 권한이라 읽어 올 수가 없다.
    ///    그래서 Info.plist에 `NSCalendarsFullAccessUsageDescription`이 필요하고,
    ///    그 문구에 "읽기만 한다"고 분명히 적어 둔다.
    func requestAccess() async {
        isWorking = true
        failureMessage = nil
        defer { isWorking = false }
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            failureMessage = "캘린더 권한을 얻지 못했습니다: \(error.localizedDescription)"
        }
        status = EKEventStore.authorizationStatus(for: .event)
        reloadCalendarsIfAllowed()
        if status == .denied || status == .restricted {
            failureMessage = "시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 '무지개 공방'을 켜주세요."
        }
    }

    func reloadCalendarsIfAllowed() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            calendars = []
            return
        }
        calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: - 가져오기

    struct ImportResult {
        var added = 0
        var updated = 0
        var removed = 0
        /// 사라진 일정인데 사람이 손을 댄 흔적이 있어 남겨 둔 것.
        var keptOrphans = 0
        var allDay = 0

        var isEmpty: Bool { added == 0 && updated == 0 && removed == 0 }

        var summary: String {
            if isEmpty { return "바뀐 일정이 없습니다." }
            var parts: [String] = []
            if added > 0 { parts.append("\(added)개 가져옴") }
            if updated > 0 { parts.append("\(updated)개 갱신") }
            if removed > 0 { parts.append("\(removed)개 정리") }
            if keptOrphans > 0 { parts.append("손댄 \(keptOrphans)개는 남겨둠") }
            return parts.joined(separator: " · ")
        }
    }

    /// 고른 캘린더의 이번 주 일정을 계획 블록으로 옮긴다.
    ///
    /// 세 갈래로 움직인다. **손댄 것은 건드리지 않는다**가 전부를 관통하는 규칙이다.
    ///  - 처음 보는 일정 → 새 블록
    ///  - 이미 있는 일정 → 시각·길이·제목만 맞춘다 (성공 기준·산출물은 사람 것이라 안 건드린다)
    ///  - 캘린더에서 사라진 일정 → 블록도 지운다. **단, 사람이 손댄 블록은 남긴다**
    ///    (캘린더 연결만 끊는다). 남의 일정이 없어졌다고 사람이 쓴 글까지 지우면 안 된다.
    @discardableResult
    func importWeek(_ weekStart: Date, into context: ModelContext) -> ImportResult {
        var result = ImportResult()
        guard hasAccess else {
            failureMessage = "캘린더 접근 권한이 없습니다."
            return result
        }
        let chosen = calendars.filter { isSelected($0) }
        guard !chosen.isEmpty else {
            failureMessage = "가져올 캘린더를 먼저 고르세요."
            return result
        }
        failureMessage = nil

        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return result }

        let predicate = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: chosen)
        let events = store.events(matching: predicate)

        // 이 주에 이미 들어와 있는, 캘린더에서 온 블록들.
        let existing = ((try? context.fetch(FetchDescriptor<PlanBlock>())) ?? [])
            .filter { cal.isDate($0.weekStartDate, inSameDayAs: weekStart) && $0.calendarEventID != nil }
        var byKey = Dictionary(existing.map { ($0.calendarEventID!, $0) }, uniquingKeysWith: { a, _ in a })

        for event in events {
            guard let key = Self.key(for: event), let start = event.startDate else { continue }
            guard let day = Self.day(of: start, in: weekStart) else { continue }
            if event.isAllDay { result.allDay += 1 }

            let hour = event.isAllDay ? -1 : Self.hourOfDay(start, calendar: cal)
            let duration = Self.duration(of: event, startHour: hour)
            let title = (event.title ?? "").isEmpty ? "(제목 없는 일정)" : event.title!

            if let block = byKey.removeValue(forKey: key) {
                var changed = false
                if block.day != day { block.day = day; changed = true }
                if block.startHour != hour { block.startHour = hour; changed = true }
                if block.durationHours != duration { block.durationHours = duration; changed = true }
                if block.title != title { block.title = title; changed = true }
                let band = TimeBand.containing(hour >= 0 ? hour : 9)
                if block.timeBand != band { block.timeBand = band; changed = true }
                if changed { result.updated += 1 }
            } else {
                let block = PlanBlock(
                    day: day,
                    timeBand: .containing(hour >= 0 ? hour : 9),
                    durationHours: duration,
                    title: title,
                    successCriteria: "",
                    deliverable: "",
                    weekStartDate: weekStart,
                    concreteVerified: false,
                    withinRoutine: false,
                    startHour: hour
                )
                block.calendarEventID = key
                context.insert(block)
                result.added += 1
            }
        }

        // 남은 것 = 캘린더에서 사라진 일정.
        for (_, orphan) in byKey {
            if Self.wasTouchedByPerson(orphan) {
                orphan.calendarEventID = nil   // 연결만 끊고 글은 남긴다.
                result.keptOrphans += 1
            } else {
                context.delete(orphan)
                result.removed += 1
            }
        }

        try? context.save()
        return result
    }

    /// 사람이 이 블록에 무언가를 보탰는가. 보탰으면 캘린더가 사라져도 지우지 않는다.
    private static func wasTouchedByPerson(_ block: PlanBlock) -> Bool {
        block.concreteVerified
            || !block.successCriteria.isEmpty
            || !block.deliverable.isEmpty
            || block.reviewStatus != nil
    }

    /// 일정 하나를 가리키는 이름.
    ///
    /// ⚠️ `eventIdentifier` 하나로는 모자란다. **반복 일정은 모든 회차가 같은 값**을 갖기
    ///    때문에, 매주 회의가 한 블록으로 뭉개진다. 시작 시각을 붙여 회차를 가른다.
    private static func key(for event: EKEvent) -> String? {
        guard let id = event.eventIdentifier, let start = event.startDate else { return nil }
        return "\(id)|\(Int(start.timeIntervalSince1970))"
    }

    private static func day(of date: Date, in weekStart: Date) -> DayOfWeek? {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: weekStart),
                                      to: cal.startOfDay(for: date)).day ?? -1
        guard (0...6).contains(days) else { return nil }
        return DayOfWeek(rawValue: days)
    }

    private static func hourOfDay(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// 블록 길이.
    ///
    /// 종일 일정을 24시간짜리로 들이면 그 요일의 자유 시간이 통째로 사라져 하루가
    /// 빨갛게 물든다. 종일은 '이 날 안에 해야 하는 것'이지 '하루를 다 쓰는 것'이 아니므로
    /// 한 시간으로 놓고 시각은 비워 둔다(→ `startHour = -1`).
    private static func duration(of event: EKEvent, startHour: Double) -> Double {
        guard !event.isAllDay,
              let start = event.startDate, let end = event.endDate else { return 1 }
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return 1 }
        // 자정을 넘기는 일정은 그날 남은 만큼만 차지한다.
        return min(max(hours, 0.25), max(0.25, 24 - startHour))
    }
}
