//
//  CalendarImport.swift
//  WeekBlocks
//
//  **맥 캘린더에 이미 적혀 있는 것을 한 주에 옮겨 놓는다.**
//
//  회의·약속처럼 이미 시각이 박힌 일정을 손으로 또 적게 하면, 앱이 계획을 돕는 게 아니라
//  베껴 쓰기를 시킨다. 그래서 읽어 온다.
//
//  ⚠️ **남의 캘린더에는 쓰지 않는다.** 가져오기는 캘린더 → 앱 한 방향이다.
//     앱 → 캘린더(→ CalendarExport.swift)는 사람이 켰을 때만, 앱이 만든 '무지개 공방'
//     캘린더 하나에만 쓴다. 그 캘린더는 가져오기에서 빠진다 — 안 빼면 쓴 것을 다시 읽어 두 벌이 된다.
//
//  ⚠️ 고르는 단위는 **캘린더**다 (일정 하나하나가 아니라). 한 번 정해두면 손이 안 가고,
//     '업무만 가져오기' 같은 실제 쓰임과도 맞는다.
//

import Foundation
import AppKit
import EventKit
import SwiftData

@MainActor
@Observable
final class CalendarBridge {
    static let shared = CalendarBridge()

    let store = EKEventStore()
    private static let selectionKey = "calendar.selectedIDs"
    private static let autoKey = "calendar.autoImport"
    private static let importedKey = "calendar.importedKeys"
    private static let exportKey = "calendar.export"
    static let exportCalendarKey = "calendar.exportCalendarID"

    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// 권한이 있을 때만 채워진다.
    private(set) var calendars: [EKCalendar] = []
    private(set) var isWorking = false
    /// 막혔을 때 화면에 그대로 보여줄 말. 조용히 실패하면 단추가 고장 난 줄 안다.
    /// 쓰기(→ CalendarExport.swift)도 여기에 적는다.
    var failureMessage: String?

    /// 시스템 설정의 캘린더 권한 화면. 거부한 뒤에는 앱이 다시 물어도 macOS가 창을 띄우지
    /// 않으므로, 켜는 자리로 곧장 보낸다.
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    /// 종일 일정의 날 수 (→ allDaySpanDays). 캘린더가 바뀌면 비운다.
    @ObservationIgnored private var spanCache: [String: Int] = [:]
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?

    /// **캘린더가 바뀌면 알아서 가져온다.** 끄면 예전처럼 '더 보기 → 캘린더에서 가져오기'를 눌러야 한다.
    ///
    /// 켜 두는 것이 기본이다 — 무엇을 가져올지는 이미 캘린더를 **골라서** 정했으므로,
    /// 고른 뒤에 또 단추를 누르게 하는 것은 같은 허락을 두 번 받는 일이다.
    var autoImport: Bool = UserDefaults.standard.object(forKey: CalendarBridge.autoKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoImport, forKey: Self.autoKey)
            if autoImport { changeTick += 1 }
        }
    }

    /// 가져올 거리가 생겼다는 신호. 캘린더가 바뀌거나 고른 캘린더가 바뀌면 하나 오른다.
    /// 화면(ContentView)이 이 값을 지켜보다가 가져온다 — 이 다리는 어느 주를 보는지 모른다.
    private(set) var changeTick = 0

    /// **계획을 '무지개 공방' 캘린더에 쓴다** (→ CalendarExport.swift). 사람이 켜야만 쓴다 —
    /// 캘린더는 아이폰·워치·다른 사람과의 공유로 번지는 자리라, 묻지 않고 채우면 안 된다.
    var exportEnabled: Bool = UserDefaults.standard.bool(forKey: CalendarBridge.exportKey) {
        didSet {
            UserDefaults.standard.set(exportEnabled, forKey: Self.exportKey)
            exportTick += 1
        }
    }

    /// 쓸 거리가 생겼다는 신호. 켜는 순간 한 번 쓰게 한다 (블록이 바뀐 것은 화면이 따로 본다).
    private(set) var exportTick = 0

    /// 앱이 만든 캘린더의 id. 기기마다 따로 적힌다 — 다른 맥은 제목으로 같은 캘린더를 찾는다.
    var exportCalendarID: String? {
        get { UserDefaults.standard.string(forKey: Self.exportCalendarKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.exportCalendarKey) }
    }

    /// 가져오기에서 고를 수 있는 캘린더 — 앱이 쓰는 캘린더는 뺀다.
    var importableCalendars: [EKCalendar] {
        calendars.filter { !isExportCalendar($0) }
    }

    /// 자동으로 가져올 수 있는 상태인가.
    var isAutoReady: Bool { autoImport && hasAccess && !selectedIDs.isEmpty }

    private init() {
        reloadCalendarsIfAllowed()
        // ⚠️ 권한은 **앱 밖(시스템 설정)에서** 바뀐다. 켤 때 한 번만 읽으면 설정에서 켜고
        //    돌아와도 화면은 계속 '권한 없음'이다. 앱으로 돌아올 때마다 다시 읽는다.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        // 캘린더 앱에서 고치든, 아이폰에서 고친 것이 iCloud로 내려오든 여기로 온다.
        // 한 번 고칠 때 여러 번 울리므로 몇 번 울렸는지는 보지 않는다 — 부르는 쪽이 잠깐 기다렸다 한 번 가져온다.
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spanCache = [:]
                self?.changeTick += 1
            }
        }
    }

    /// 읽어 올 캘린더들. 비어 있으면 **아무것도 안 가져온다** — 전부 가져오는 것보다
    /// 아무것도 안 가져오는 쪽이 낫다. 남의 개인 일정이 주간 계획에 쏟아지는 사고를 막는다.
    var selectedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.selectionKey) }
    }

    var hasAccess: Bool { status == .fullAccess }

    /// 시스템 창을 띄워 물어볼 수 있는가.
    /// 쓰기 전용으로 받아 둔 상태도 읽지는 못하므로 여기 넣는다 — 전체 접근을 다시 청하면 창이 뜬다.
    var canAsk: Bool { status == .notDetermined || status == .writeOnly }

    func toggle(_ calendar: EKCalendar) {
        var ids = selectedIDs
        if ids.contains(calendar.calendarIdentifier) {
            ids.remove(calendar.calendarIdentifier)
        } else {
            ids.insert(calendar.calendarIdentifier)
        }
        selectedIDs = ids
        changeTick += 1
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
            failureMessage = String(localized: "캘린더 권한을 얻지 못했습니다: \(error.localizedDescription)")
        }
        // 거부했을 때 무엇을 할 수 있는지는 설정 화면이 상태를 보고 직접 말한다
        // (→ SettingsView.calendarSection). 여기서 한 번 더 말하면 같은 안내가 두 번 선다.
        refreshStatus()
    }

    /// 권한 상태를 다시 읽는다. 앱으로 돌아올 때마다 불린다.
    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
        reloadCalendarsIfAllowed()
        if hasAccess { failureMessage = nil }
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

    /// **한 번이라도 가져온 일정들.** 블록이 없어졌는데 이 목록에 있으면 사람이 앱에서 지운 것이다.
    ///
    /// ⚠️ 이것이 없으면 자동 가져오기가 지운 블록을 곧바로 되살린다 — 캘린더에는 그 일정이
    ///    그대로 있으니까. 캘린더는 건드리지 않는 앱이라, '이 일정은 안 들이기로 했다'를 여기에 적는다.
    ///    기기마다 따로 적힌다(UserDefaults). 다른 맥에서 지운 것은 그 맥이 기억한다.
    private var importedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.importedKey) ?? []) }
        set {
            // 끝없이 쌓이지 않게 자른다. 한 주에 수십 개라 이만큼이면 한 해를 넘게 담는다.
            UserDefaults.standard.set(Array(newValue.suffix(3000)), forKey: Self.importedKey)
        }
    }

    struct ImportResult {
        var added = 0
        var updated = 0
        var removed = 0
        /// 사라진 일정인데 사람이 손을 댄 흔적이 있어 남겨 둔 것.
        var keptOrphans = 0
        /// 사람이 이미 세운 같은 일에 짝지어 붙인 것 (→ CalendarMerge.autoMatch).
        var linked = 0
        var allDay = 0
        /// 캘린더에서 사라졌지만 **아직 안 지운** 블록들.
        ///
        /// ⚠️ 여기 담아서 돌려보내는 이유: 지우면 그 삭제가 CloudKit을 타고 **아이폰까지
        ///    건너간다.** 되돌릴 수 없는 일을 묻지도 않고 하면 안 된다. 부르는 쪽이
        ///    사람에게 물어본 뒤 `removeOrphans`로 지운다.
        var pendingRemovals: [PlanBlock] = []

        var isEmpty: Bool {
            added == 0 && updated == 0 && removed == 0 && linked == 0 && pendingRemovals.isEmpty
        }

        var summary: String {
            if isEmpty { return String(localized: "바뀐 일정이 없습니다.") }
            var parts: [String] = []
            if added > 0 { parts.append(String(localized: "\(added)개 가져옴")) }
            if updated > 0 { parts.append(String(localized: "\(updated)개 갱신")) }
            if linked > 0 { parts.append(String(localized: "내 계획 \(linked)개와 짝지음")) }
            if removed > 0 { parts.append(String(localized: "\(removed)개 지움")) }
            if keptOrphans > 0 { parts.append(String(localized: "손댄 \(keptOrphans)개는 남겨둠")) }
            return parts.joined(separator: " · ")
        }
    }

    /// 고른 캘린더의 이번 주 일정을 계획 블록으로 옮긴다.
    ///
    /// 세 갈래로 움직인다. **손댄 것은 건드리지 않는다**가 전부를 관통하는 규칙이다.
    ///  - 처음 보는 일정 → 새 블록
    ///  - 이미 있는 일정 → 시각·길이·제목만 맞춘다 (성공 기준·산출물은 사람 것이라 안 건드린다)
    ///  - 캘린더에서 사라진 일정 → **지울 후보로 담아서 돌려준다.** 여기서 지우지 않는다.
    ///    사람이 손댄 블록은 후보에도 안 넣고 캘린더 연결만 끊는다 —
    ///    남의 일정이 없어졌다고 사람이 쓴 글까지 지우면 안 된다.
    @discardableResult
    func importWeek(_ weekStart: Date, into context: ModelContext) -> ImportResult {
        var result = ImportResult()
        guard hasAccess else {
            failureMessage = String(localized: "캘린더 접근 권한이 없습니다.")
            return result
        }
        let chosen = importableCalendars.filter { isSelected($0) }
        guard !chosen.isEmpty else {
            failureMessage = String(localized: "가져올 캘린더를 먼저 고르세요.")
            return result
        }
        failureMessage = nil

        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return result }

        let predicate = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: chosen)
        let events = store.events(matching: predicate)
        Self.migrateAllDayToBackground(in: context)

        // 이 주의 블록들. 캘린더에서 온 것은 맞춰 갈 대상, 사람이 세운 것은 짝지을 후보다.
        let allBlocks = (try? context.fetch(FetchDescriptor<PlanBlock>())) ?? []
        let weekBlocks = allBlocks.filter { cal.isDate($0.weekStartDate, inSameDayAs: weekStart) }
        let existing = weekBlocks.filter { $0.calendarEventID != nil }
        var mine = weekBlocks.filter { $0.calendarEventID == nil }
        var byKey = Dictionary(existing.map { ($0.calendarEventID!, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = importedKeys
        // 다른 기기에서 사람이 지운 캘린더 블록 (→ DeletionMark.swift). importedKeys는 이 맥에만 있어서,
        // 저쪽 맥에서 지운 일정을 이쪽이 처음 가져오면 도로 세웠다.
        let deletedElsewhere = DeletionLog.marks(in: context)
        // 이 기능 전에 들어온 블록도 '가져온 것'으로 적어 둔다 — 그래야 지우면 안 돌아온다.
        seen.formUnion(byKey.keys)

        // ── 1차: 이름(키)으로 짝짓는다. ──
        // ⚠️ 모든 일정을 이름으로 먼저 짝지은 뒤에야 2차(같은 날·시각·제목)로 넘어간다.
        //    섞어 돌리면 앞 일정이 뒤 일정의 '제 이름 블록'을 제목만 보고 가로챈다.
        var matches: [Match] = []
        for event in events {
            guard let key = Self.key(for: event), let start = event.startDate,
                  let day = Self.day(of: start, in: weekStart) else { continue }
            let legacy = Self.legacyKey(for: event)
            let allDay = Self.isWholeDay(event)
            let hour = allDay ? PlanBlock.backgroundHour : Self.hourOfDay(start, calendar: cal)
            let title = (event.title ?? "").isEmpty ? String(localized: "(제목 없는 일정)") : event.title!

            var block = byKey.removeValue(forKey: key)
            // 옛 이름(이 맥의 eventIdentifier)으로 적힌 블록 → 새 이름으로 옮겨 적는다 (한 번뿐인 이행).
            if block == nil, let legacy, legacy != key, let old = byKey.removeValue(forKey: legacy) {
                Self.relink(old, to: key)
                block = old
            }
            // 옛 이름에 붙어 있던 '사람이 지은 제목' 표시도 새 이름으로 넘긴다.
            if let legacy, legacy != key, CalendarMerge.hasOwnTitle(legacy) { CalendarMerge.keepOwnTitle(for: key) }
            matches.append(Match(event: event, key: key, legacy: legacy, day: day, hour: hour,
                                 allDay: allDay, title: title, block: block))
        }

        // ── 1차 뒤: 시각을 옮긴 일정. ──
        // 시각을 옮기면 이름(= id + 시작 시각)이 바뀐다. 같은 id의 블록을 찾아 그 블록을 옮긴다 —
        // 안 그러면 새 블록 하나와 '사라진 일정' 하나로 갈린다.
        // ⚠️ 이름이 그대로 맞는 짝을 **모든 일정에 대해 먼저** 지은 뒤에 한다. 반복 일정은 회차마다 id가
        //    같아서, 섞어 돌리면 옮긴 회차가 제자리에 있는 다른 회차의 블록을 가로챈다.
        //    남은 같은 id 블록 중 **시각이 가장 가까운 것**을 고른다 — 반복 일정의 한 회차만 옮긴 경우도 따라간다.
        for i in matches.indices where matches[i].block == nil {
            let event = matches[i].event
            guard let start = event.startDate else { continue }
            let same = byKey.filter { Self.names($0.key, event) }
            guard let nearest = same.min(by: {
                abs(Double((Self.parse($0.key)?.start ?? 0)) - start.timeIntervalSince1970)
                    < abs(Double((Self.parse($1.key)?.start ?? 0)) - start.timeIntervalSince1970)
            }) else {
                // 다른 주에서 이 주로 옮겨 온 일정 — 그 주에 있던 블록을 데려온다 (반복 일정은 회차를 가릴 수 없어 빼고).
                guard !event.hasRecurrenceRules,
                      let from = allBlocks.first(where: { b in
                          !cal.isDate(b.weekStartDate, inSameDayAs: weekStart)
                              && b.calendarEventID.map { Self.names($0, event) } == true
                      }) else { continue }
                from.weekStartDate = weekStart
                Self.relink(from, to: matches[i].key)
                matches[i].block = from
                continue
            }
            byKey.removeValue(forKey: nearest.key)
            Self.relink(nearest.value, to: matches[i].key)
            matches[i].block = nearest.value
        }

        // ── 2차: 같은 날 · 같은 시작 분 · 같은 제목으로 한 번 더 맞춘다. ──
        // 다른 맥이 가져온 블록은 그 맥의 이름이 적혀 있어 1차에 안 걸린다 (옛 이름은 기기마다 다르다).
        // 이것을 안 하면 맥마다 한 벌씩 두 벌이 서고, 서로 상대 것을 '사라진 일정'으로 지우자고 한다.
        // 이미 두 벌이 선 것도 여기서 하나로 줄인다.
        for i in matches.indices {
            let slot = Self.slot(day: matches[i].day, minute: Self.minute(matches[i].hour, allDay: matches[i].allDay),
                                 title: matches[i].title)
            let twins = byKey.filter { Self.slot(of: $0.value) == slot }
            guard !twins.isEmpty else { continue }
            for k in twins.keys { byKey.removeValue(forKey: k) }
            let all = (matches[i].block.map { [$0] } ?? []) + twins.values
            // ⚠️ 남길 쪽은 **동기화되는 값으로만** 고른다 — 두 맥이 각자 골라도 같은 블록이 남아야
            //    서로 상대가 남긴 것을 지우는 일이 없다.
            //    이름으로 짝지은 블록이 사람 것이면 그것이 남는다 (사람 것은 어차피 안 지운다).
            let named = matches[i].block.flatMap { Self.isPrecious($0, eventTitle: matches[i].title) ? $0 : nil }
            guard let keeper = named ?? all.min(by: { Self.keeps($0, over: $1, eventTitle: matches[i].title) })
            else { continue }
            for loser in all where loser !== keeper {
                // 사람이 손댄 것(또는 제목을 바꿔 둔 것)은 지우지 않는다. 손 안 댄 사본만 치운다 —
                // 같은 일정을 베낀 것이라 잃는 것이 없다.
                guard !Self.isPrecious(loser, eventTitle: matches[i].title) else { continue }
                context.delete(loser)
                mine.removeAll { $0 === loser }
                result.removed += 1
            }
            // 이름이 기기와 무관할 때만 옮겨 적는다. 이 맥에만 있는 id로 덮으면 다른 맥이 다시 못 찾는다.
            if Self.isPortable(matches[i].key) { Self.relink(keeper, to: matches[i].key) }
            matches[i].block = keeper
        }

        // ── 맞춘 대로 반영한다. ──
        for m in matches {
            let key = m.key, day = m.day, hour = m.hour, title = m.title, allDay = m.allDay
            // 가져온 적 있는데 블록이 없다 = 사람이 앱에서 지웠다. 되살리지 않는다.
            if m.block == nil, seen.contains(key) || m.legacy.map(seen.contains) == true { continue }
            if m.block == nil, deletedElsewhere.contains("calendar:\(key)") { seen.insert(key); continue }
            seen.insert(key)
            if allDay { result.allDay += 1 }

            // 종일 일정은 '종일' 블록으로 — 시간을 차지하지 않는다 (→ PlanBlock.isAllDay).
            // 캘린더의 종일은 대개 공휴일·생일·휴가 같은 '그날이 어떤 날'이다 — 배경으로 들인다 (→ PlanBlock.isBackground).
            let duration = Self.duration(of: m.event, startHour: hour)

            if let block = m.block {
                var changed = false
                if block.day != day { block.day = day; changed = true }
                // 종일끼리는 시각을 건드리지 않는다 — 사람이 배경 ↔ 할 일로 바꿔 둔 것을 덮지 않게.
                if block.startHour != hour, !(allDay && block.isAllDay) { block.startHour = hour; changed = true }
                if block.durationHours != duration { block.durationHours = duration; changed = true }
                // 합친 블록의 제목은 사람 것이다 — 캘린더 제목으로 덮지 않는다 (→ CalendarMerge).
                // ⚠️ '사람이 지은 제목' 표시는 기기마다 따로 적힌다. 다른 기기에서 난 블록은 그 표시를
                //    이 맥이 모르므로 제목을 건드리지 않는다 — 제목 맞추기는 난 자리가 한다.
                if block.title != title, !CalendarMerge.hasOwnTitle(key), TodoSharing.isMine(block) {
                    block.title = title; changed = true
                }
                let band = TimeBand.containing(hour >= 0 ? hour : 9)
                if block.timeBand != band { block.timeBand = band; changed = true }
                if changed { result.updated += 1 }
            } else if !allDay,
                      let match = CalendarMerge.autoMatch(title: title, day: day, startHour: hour, among: mine) {
                // 사람이 이미 같은 일을 세워 두었다 — 새로 만들지 않고 그 블록이 이 일정을 맡는다.
                // 시각은 캘린더를 따르고, 제목과 사람이 적은 것은 그대로 둔다.
                match.calendarEventID = key
                match.startHour = hour
                match.durationHours = duration
                match.timeBand = .containing(hour)
                CalendarMerge.keepOwnTitle(for: key)
                mine.removeAll { $0 === match }
                result.linked += 1
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
        //
        // ⚠️ **여기서 지우지 않는다.** 지우면 그 삭제가 CloudKit을 타고 아이폰까지 건너가
        //    거기서도 사라진다. 되돌릴 수 없는 일이라, 무엇을 지울 참인지 사람에게
        //    보여주고 물어본 뒤에 지운다 (→ ContentView.importFromCalendar).
        let chosenIDs = Set(chosen.map(\.calendarIdentifier))
        for (key, orphan) in byKey {
            // ⚠️ **다른 기기에서 가져온 블록은 그 기기가 판정한다.** 캘린더 고르기는 기기마다 따로라,
            //    이 맥이 안 읽는 캘린더(또는 이 맥에 없는 계정)의 일정은 여기서 늘 '사라진' 것으로 보인다.
            //    이 맥이 그 일정의 캘린더를 읽고 있는데도 없을 때만(= 확실히 사라졌을 때만) 묻는다.
            if !TodoSharing.isMine(orphan) {
                let homes = Set(linkedEvents(forKey: key).compactMap { $0.calendar?.calendarIdentifier })
                guard !homes.isDisjoint(with: chosenIDs) else { continue }
            }
            // 다른 주로 옮긴 일정 — 사라진 게 아니다. 블록을 그 주·그 요일·그 시각으로 따라 옮긴다.
            if let moved = movedElsewhere(key: key, from: weekStart, among: chosenIDs) {
                if let k = follow(orphan, to: moved, key: key) { seen.insert(k) }
                result.updated += 1
                continue
            }
            if Self.wasTouchedByPerson(orphan) {
                orphan.calendarEventID = nil   // 연결만 끊고 글은 남긴다.
                result.keptOrphans += 1
            } else {
                result.pendingRemovals.append(orphan)
            }
        }

        importedKeys = seen
        try? context.save()
        // 고르기만 하고 아무것도 안 들어온 주가 흔하다. '가져왔다'는 들어왔을 때만이다.
        if result.added > 0 || result.updated > 0 { Telemetry.record(.calendarImported) }
        return result
    }

    /// 이 이름의 일정이 **이 주 밖으로** 옮겨 갔으면 그 일정. 반복 일정은 회차를 가릴 수 없어 보지 않는다.
    private func movedElsewhere(key: String, from weekStart: Date, among calendars: Set<String>) -> EKEvent? {
        guard let event = linkedEvents(forKey: key).first(where: {
            !$0.hasRecurrenceRules && calendars.contains($0.calendar?.calendarIdentifier ?? "")
        }), let start = event.startDate else { return nil }
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        return (start < weekStart || start >= end) ? event : nil
    }

    /// 블록을 옮겨 간 일정에 맞춘다 — 주 · 요일 · 시각 · 길이 · 이름. 사람이 적은 것과 제목은 그대로다
    /// (제목은 그 주를 가져올 때 늘 하던 규칙대로 맞춘다).
    @discardableResult
    private func follow(_ block: PlanBlock, to event: EKEvent, key old: String) -> String? {
        guard let start = event.startDate, let newKey = Self.key(for: event) else { return nil }
        let cal = Calendar.current
        let week = start.shownWeekStart(sundayFirst: WeekStartSetting.sundayFirst)
        guard let day = Self.day(of: start, in: week) else { return nil }
        let allDay = Self.isWholeDay(event)
        let hour = allDay ? PlanBlock.backgroundHour : Self.hourOfDay(start, calendar: cal)
        block.weekStartDate = week
        block.day = day
        if !(allDay && block.isAllDay) { block.startHour = hour }
        block.durationHours = Self.duration(of: event, startHour: hour)
        block.timeBand = .containing(hour >= 0 ? hour : 9)
        Self.relink(block, to: newKey)
        return newKey
    }

    /// 이번 가져오기에서 캘린더 일정 하나와, 그 일정을 맡을 블록.
    private struct Match {
        let event: EKEvent
        let key: String
        let legacy: String?
        let day: DayOfWeek
        let hour: Double
        let allDay: Bool
        let title: String
        var block: PlanBlock?
    }

    /// 물어본 뒤에 지운다 (→ `ImportResult.pendingRemovals`).
    /// 이 삭제는 CloudKit을 타고 같은 계정의 다른 기기에서도 사라진다.
    @discardableResult
    func removeOrphans(_ blocks: [PlanBlock], in context: ModelContext) -> Int {
        guard !blocks.isEmpty else { return 0 }
        for block in blocks { context.delete(block) }
        try? context.save()
        return blocks.count
    }

    /// 캘린더에서 사라졌지만 **남겨 두기로 한** 블록들. 캘린더 연결을 끊어 사람이 세운 블록이 된다 —
    /// 그러지 않으면 자동 가져오기가 돌 때마다 같은 것을 또 묻는다.
    func unlink(_ blocks: [PlanBlock], in context: ModelContext) {
        guard !blocks.isEmpty else { return }
        for block in blocks { block.calendarEventID = nil }
        try? context.save()
    }

    /// 사람이 이 블록에 무언가를 보탰는가. 보탰으면 캘린더가 사라져도 지우지 않는다.
    ///
    /// ⚠️ 예전에는 편집창이 성공 기준·산출물을 **채워야만** 저장을 열어 줘서, 한 번 손댄
    ///    블록은 반드시 여기 걸렸다. 그 조건을 푼 뒤로는 비워 둔 채 저장할 수 있으므로,
    ///    사람이 적을 수 있는 칸을 빠짐없이 본다. 못 보면 손댄 블록이 '안 손댄 것'으로
    ///    읽혀 지울 후보로 올라간다 (지우기 전에 묻기는 하지만, 이름만 보고 판단해야 한다).
    private static func wasTouchedByPerson(_ block: PlanBlock) -> Bool {
        block.concreteVerified
            || !block.successCriteria.isEmpty
            || !block.deliverable.isEmpty
            || !(block.nextAction ?? "").isEmpty
            || block.actualMinutes != nil
            || block.reviewStatus != nil
    }

    /// 배경 종일(→ PlanBlock.backgroundHour)이 생기기 전에 가져온 종일 일정을 한 번만 배경으로 옮긴다.
    /// 그 전에는 생일·공휴일이 할 일로 세여 무지개 칸을 차지하고 '끝냈나요?'까지 물었다.
    private static func migrateAllDayToBackground(in context: ModelContext) {
        let flag = "calendar.allDayBackgroundMigrated"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let all = (try? context.fetch(FetchDescriptor<PlanBlock>())) ?? []
        for block in all where block.calendarEventID != nil && block.isAllDay && !block.isBackground {
            block.setBackground(true)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: flag)
    }

    /// **캘린더에서 가져온 종일 일정이 며칠에 걸치는가.** 가져오기는 첫날에만 블록을 세우므로,
    /// 한 주를 가로지르는 막대를 그리려면 끝나는 날을 캘린더에서 다시 읽는다. 모르면 nil.
    func allDaySpanDays(forKey key: String) -> Int? {
        if let cached = spanCache[key] { return cached }
        let found = linkedEvents(forKey: key)
        // 반복 종일(생일 등)은 회차마다 같은 길이다. 시작이 맞는 회차가 없으면 아무 회차나 쓴다.
        let start0 = Self.parse(key)?.start
        guard hasAccess,
              let event = found.first(where: { $0.startDate.map { Int($0.timeIntervalSince1970) } == start0 }) ?? found.first,
              Self.isWholeDay(event), let start = event.startDate, let end = event.endDate else { return nil }
        let cal = Calendar.current
        let last = end.addingTimeInterval(-1)
        let days = (cal.dateComponents([.day], from: cal.startOfDay(for: start),
                                       to: cal.startOfDay(for: last)).day ?? 0) + 1
        let result = max(1, days)
        spanCache[key] = result
        return result
    }

    /// **종일로 보는가.** 캘린더에서 '종일'로 체크한 것뿐 아니라, 자정에 시작해 자정에 끝나는 일정
    /// (00:00–24:00, 여러 날이면 00:00–다음 날 00:00…)도 종일이다. 23:59에 끝나는 것도 같게 본다.
    /// 그대로 두면 24시간짜리 블록이 되어 그날 남은 시간이 통째로 사라진다.
    static func isWholeDay(_ event: EKEvent) -> Bool {
        if event.isAllDay { return true }
        guard let start = event.startDate, let end = event.endDate, end > start else { return false }
        let cal = Calendar.current
        guard cal.startOfDay(for: start) == start else { return false }
        if cal.startOfDay(for: end) == end { return true }
        let c = cal.dateComponents([.hour, .minute], from: end)
        return c.hour == 23 && c.minute == 59
    }

    // MARK: - 일정의 이름

    /// 일정 하나를 가리키는 이름 — `"ext:<calendarItemExternalIdentifier>|<시작 시각 초>"`.
    ///
    /// ⚠️ 예전에는 `eventIdentifier`를 썼다. 그것은 **이 기기의 캘린더 DB 안에서만 통하는 id**라
    ///    아이맥과 맥북이 같은 회의에 서로 다른 이름을 붙였다 → 맥마다 한 벌씩 두 벌이 서고,
    ///    서로 상대 것을 '캘린더에서 사라진 일정'으로 지우자고 했다. 외부 id(CalDAV의 UID)는
    ///    같은 계정의 기기끼리 같다.
    /// ⚠️ id 하나로는 모자란다. **반복 일정은 모든 회차가 같은 값**을 갖기 때문에, 매주 회의가
    ///    한 블록으로 뭉개진다. 시작 시각을 붙여 회차를 가른다.
    /// 외부 id가 없는 캘린더(드물다)는 옛 이름을 쓴다 — 그때는 같은 날·시각·제목 맞추기가 받친다.
    private static func key(for event: EKEvent) -> String? {
        guard let start = event.startDate else { return nil }
        if let ext = event.calendarItemExternalIdentifier, !ext.isEmpty {
            return "\(externalPrefix)\(ext)|\(Int(start.timeIntervalSince1970))"
        }
        return legacyKey(for: event)
    }

    private static let externalPrefix = "ext:"

    /// 옛 이름 `"<eventIdentifier>|<시작 시각 초>"`. 이미 저장된 블록·importedKeys를 알아보는 데만 쓴다.
    /// ⚠️ 아이폰(CalendarMirror.PlannedCopies)도 이 꼴을 읽는다 — 새 이름은 거기서 같은 날·시각·제목으로 걸린다.
    private static func legacyKey(for event: EKEvent) -> String? {
        guard let id = event.eventIdentifier, let start = event.startDate else { return nil }
        return "\(id)|\(Int(start.timeIntervalSince1970))"
    }

    /// 이름을 id와 시작 시각으로 나눈다. ⚠️ 외부 id에 `|`가 들어 있을 수 있어 **마지막** `|`로 자른다.
    private static func parse(_ key: String) -> (id: String, start: Int, external: Bool)? {
        guard let bar = key.lastIndex(of: "|"), let start = Int(key[key.index(after: bar)...]) else { return nil }
        let head = String(key[..<bar])
        return head.hasPrefix(externalPrefix)
            ? (String(head.dropFirst(externalPrefix.count)), start, true)
            : (head, start, false)
    }

    /// 기기와 무관한 이름인가 (외부 id로 지은 것). 이런 이름만 남의 블록에 옮겨 적는다.
    private static func isPortable(_ key: String) -> Bool { key.hasPrefix(externalPrefix) }

    /// 이름(시작 시각은 빼고)이 이 일정을 가리키는가 — 시각을 옮긴 일정을 찾을 때.
    private static func names(_ key: String, _ event: EKEvent) -> Bool {
        guard let p = parse(key) else { return false }
        return p.external ? p.id == event.calendarItemExternalIdentifier : p.id == event.eventIdentifier
    }

    /// 이 이름이 가리키는 일정들 (이 기기 캘린더에서). 반복 일정은 여러 회차가 나올 수 있다.
    private func linkedEvents(forKey key: String) -> [EKEvent] {
        guard let p = Self.parse(key) else { return [] }
        if p.external {
            return store.calendarItems(withExternalIdentifier: p.id).compactMap { $0 as? EKEvent }
        }
        return store.event(withIdentifier: p.id).map { [$0] } ?? []
    }

    /// 블록의 이름을 바꿔 적는다. 옛 이름에 붙은 '사람이 지은 제목' 표시도 따라간다.
    private static func relink(_ block: PlanBlock, to key: String) {
        guard let old = block.calendarEventID, old != key else { return }
        if CalendarMerge.hasOwnTitle(old) { CalendarMerge.keepOwnTitle(for: key) }
        block.calendarEventID = key
    }

    // MARK: - 같은 날 · 같은 시작 분 · 같은 제목
    //
    // 이름이 안 맞을 때 받치는 기준 (아이폰 CalendarMirror.PlannedCopies와 같은 기준).
    // 시각까지 같아야 하므로 이름만 같은 다른 날·다른 시각 일정은 안 걸린다.

    private static func slot(day: DayOfWeek, minute: Int, title: String) -> String {
        "\(day.rawValue)|\(minute)|\(title)"
    }

    /// 종일은 시각이 없으니 -1 자리 하나로 — 같은 날 · 같은 제목으로만 맞춘다.
    private static func minute(_ hour: Double, allDay: Bool) -> Int {
        allDay ? -1 : Int((hour * 60).rounded())
    }

    private static func slot(of block: PlanBlock) -> String {
        slot(day: block.day, minute: minute(block.startHour, allDay: block.isAllDay), title: block.title)
    }

    /// 사람 것으로 볼 블록 — 손댔거나 제목을 캘린더와 다르게 바꿔 두었다. 사본 치우기에서 지우지 않는다.
    /// ⚠️ 기기마다 따로 적히는 '사람이 지은 제목' 표시(UserDefaults) 대신 **동기화되는 제목**을 본다 —
    ///    두 맥이 같은 결론을 내야 한다.
    private static func isPrecious(_ block: PlanBlock, eventTitle: String) -> Bool {
        wasTouchedByPerson(block) || block.title != eventTitle
    }

    /// 같은 일정의 사본 중 무엇을 남기나. 사람 것 → 먼저 만든 것 → 이름 순.
    /// ⚠️ 동기화되는 값만 쓴다. 시각은 밀리초로 자른다 — CloudKit을 건너온 Date는 정밀도가 줄어,
    ///    만든 기기와 받은 기기가 미세하게 다른 값을 들고 있을 수 있다.
    private static func keeps(_ a: PlanBlock, over b: PlanBlock, eventTitle: String) -> Bool {
        let pa = isPrecious(a, eventTitle: eventTitle), pb = isPrecious(b, eventTitle: eventTitle)
        if pa != pb { return pa }
        let ta = Int64((a.createdAt.timeIntervalSince1970 * 1000).rounded())
        let tb = Int64((b.createdAt.timeIntervalSince1970 * 1000).rounded())
        if ta != tb { return ta < tb }
        return (a.calendarEventID ?? "") < (b.calendarEventID ?? "")
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
    /// 빨갛게 물든다. 한때는 한 시간으로 놓았는데, 그 한 시간도 자유 시간에서 빠져서
    /// 기념일 하나가 할 일 한 시간을 밀어냈다 (레딧 피드백). 종일은 '이 날의 일'이지
    /// '시간을 쓰는 일'이 아니므로 길이 0으로 들인다 (→ `PlanBlock.makeAllDay`).
    private static func duration(of event: EKEvent, startHour: Double) -> Double {
        if isWholeDay(event) { return 0 }
        guard let start = event.startDate, let end = event.endDate else { return 1 }
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return 1 }
        // 자정을 넘기는 일정은 그날 남은 만큼만 차지한다.
        return min(max(hours, 0.25), max(0.25, 24 - startHour))
    }
}
