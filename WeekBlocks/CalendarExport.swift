//
//  CalendarExport.swift
//  WeekBlocks
//
//  **짠 계획을 캘린더에도 세운다.** 앱에서 블록을 놓으면 '무지개 공방' 캘린더에 같은 일정이 선다.
//  아이폰 캘린더·워치·위젯처럼 이 앱이 닿지 않는 자리에서도 오늘 할 일이 보이게.
//
//  ⚠️ 규칙 세 가지.
//   1. **앱이 만든 캘린더 하나에만 쓴다.** 다른 캘린더의 일정은 읽기만 한다 (→ CalendarImport.swift).
//   2. **앱이 쓴 일정만 고치고 지운다.** 어느 블록에서 왔는지를 일정의 URL에 적어 두고,
//      그 표시가 있는 것만 만진다. 사람이 그 캘린더에 직접 넣은 일정은 건드리지 않는다.
//   3. **앱이 원본이다.** 캘린더에서 그 일정을 고쳐도 다음에 쓸 때 앱의 계획으로 되돌아간다.
//
//  ⚠️ 블록의 신원은 `createdAt`이다. 새 CloudKit 필드를 더하지 않는다 — 필드 하나가 Production
//     스키마에 없어서 맥 → 아이폰 동기화가 통째로 멈춘 적이 있다 (2026-09-22). `createdAt`은
//     이미 동기화되는 값이라 맥 두 대가 같은 캘린더에 써도 같은 블록을 같은 일정으로 본다.
//

import Foundation
import AppKit
import SwiftUI
import EventKit
import SwiftData

extension CalendarBridge {
    /// 앱이 만드는 캘린더의 이름. 언어를 바꿔도 찾을 수 있게 모든 언어의 이름을 알아본다.
    static var exportCalendarTitle: String { String(localized: "무지개 공방") }
    private static let exportCalendarTitles: Set<String> = ["무지개 공방", "Rainbow Craft", "彩虹工坊"]
    private static let urlScheme = "rainbowcraft"

    func isExportCalendar(_ calendar: EKCalendar) -> Bool {
        calendar.calendarIdentifier == exportCalendarID
            || Self.exportCalendarTitles.contains(calendar.title)
    }

    /// 캘린더에 세울 블록 하나.
    struct ExportItem: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let notes: String?
    }

    /// 블록의 신원 — 만든 시각(밀리초). 동기화를 거쳐도 같은 값이 되도록 밀리초로 자른다.
    nonisolated static func exportID(for block: PlanBlock) -> String {
        String(Int64((block.createdAt.timeIntervalSince1970 * 1000).rounded()))
    }

    private static func url(for id: String) -> URL? { URL(string: "\(urlScheme)://block/\(id)") }

    private static func id(of event: EKEvent) -> String? {
        guard let url = event.url, url.scheme == urlScheme, url.host == "block" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty ? nil : id
    }

    /// 쓰는 범위 — 지난주부터 5주 뒤까지. 그 밖의 일정은 그대로 둔다(지난 기록을 지우지 않는다).
    static func exportWindow(now: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let week = now.weekStart()
        return (cal.date(byAdding: .day, value: -7, to: week) ?? week,
                cal.date(byAdding: .day, value: 35, to: week) ?? week)
    }

    /// 캘린더에 세울 블록들.
    ///
    /// 빼는 것: 시각이 안 정해진 것(캘린더는 시각이 있어야 선다), 종일, 캘린더에서 가져온 것
    /// (이미 캘린더에 있다), 루틴(수면·끼니까지 쓰면 캘린더가 날마다 같은 것으로 덮인다).
    static func exportItems(blocks: [PlanBlock], routineNames: Set<String>,
                            window: (start: Date, end: Date)) -> [ExportItem] {
        let iso = Calendar(identifier: .iso8601)
        let cal = Calendar.current
        return blocks.compactMap { block in
            guard block.startHour >= 0, !block.isAllDay, block.calendarEventID == nil,
                  !block.isRoutineKind(routineNames), block.durationHours > 0,
                  let date = iso.date(byAdding: .day, value: block.day.rawValue, to: block.weekStartDate),
                  let start = cal.date(byAdding: .minute, value: Int((block.startHour * 60).rounded()),
                                       to: cal.startOfDay(for: date))
            else { return nil }
            guard start >= window.start, start < window.end else { return nil }
            let end = start.addingTimeInterval(max(0.25, block.durationHours) * 3600)
            let criteria = block.successCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExportItem(id: exportID(for: block), title: block.title, start: start, end: end,
                              notes: criteria.isEmpty ? nil : criteria)
        }
    }

    /// 앱의 캘린더. 없으면 만든다 — iCloud에 두어 아이폰 캘린더에도 뜨게 하고, 없으면 이 맥에.
    private func exportCalendar() throws -> EKCalendar {
        if let id = exportCalendarID, let found = store.calendar(withIdentifier: id) { return found }
        // 다른 맥이 이미 만들었으면 그것을 쓴다. 두 벌을 만들면 아이폰에 같은 일정이 두 번 선다.
        if let found = store.calendars(for: .event).first(where: {
            Self.exportCalendarTitles.contains($0.title) && $0.allowsContentModifications
        }) {
            exportCalendarID = found.calendarIdentifier
            return found
        }
        let made = EKCalendar(for: .event, eventStore: store)
        made.title = Self.exportCalendarTitle
        made.cgColor = NSColor(Color(hex: Rainbow.indigo) ?? .indigo).cgColor
        let sources = store.sources
        made.source = store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .calDAV }
            ?? sources.first { $0.sourceType == .local }
        try store.saveCalendar(made, commit: true)
        exportCalendarID = made.calendarIdentifier
        reloadCalendarsIfAllowed()
        return made
    }

    /// **계획을 캘린더와 맞춘다.** 새 블록은 세우고, 바뀐 것은 고치고, 없어진 것은 지운다.
    /// 바꾼 일정 수를 돌려준다.
    @discardableResult
    func exportPlan(blocks: [PlanBlock], routineNames: Set<String>) -> Int {
        guard exportEnabled, hasAccess else { return 0 }
        do {
            let calendar = try exportCalendar()
            let window = Self.exportWindow()
            let wanted = Self.exportItems(blocks: blocks, routineNames: routineNames, window: window)
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end,
                                                     calendars: [calendar])
            var existing: [String: EKEvent] = [:]
            var changes = 0
            for event in store.events(matching: predicate) {
                guard let id = Self.id(of: event) else { continue }   // 사람이 넣은 일정 — 안 만진다.
                if existing[id] == nil {
                    existing[id] = event
                } else {
                    // 맥 두 대가 동시에 쓰면 한 블록이 두 번 설 수 있다. 하나만 남긴다.
                    try store.remove(event, span: .thisEvent, commit: false)
                    changes += 1
                }
            }

            for item in wanted {
                let event = existing.removeValue(forKey: item.id) ?? {
                    let made = EKEvent(eventStore: store)
                    made.calendar = calendar
                    made.url = Self.url(for: item.id)
                    return made
                }()
                guard event.title != item.title || event.startDate != item.start
                        || event.endDate != item.end || event.notes != item.notes
                        || event.isNew
                else { continue }
                event.title = item.title
                event.startDate = item.start
                event.endDate = item.end
                event.notes = item.notes
                try store.save(event, span: .thisEvent, commit: false)
                changes += 1
            }

            // 남은 것 = 앱에서 지웠거나, 시각을 뺐거나, 캘린더에서 온 것과 합친 블록.
            for (_, stale) in existing {
                try store.remove(stale, span: .thisEvent, commit: false)
                changes += 1
            }
            if changes > 0 { try store.commit() }
            return changes
        } catch {
            store.reset()
            failureMessage = String(localized: "캘린더에 쓰지 못했습니다: \(error.localizedDescription)")
            return 0
        }
    }
}
