//
//  CalendarMerge.swift
//  WeekBlocks
//
//  **같은 일이 두 번 서지 않게.** 캘린더에서 가져온 일정과 사람이 세운 블록이 같은 시간대에
//  겹치면, 대개 같은 일을 두 자리에 적은 것이다 (캘린더에 회의가 있는데 앱에도 '회의'를 놓았다).
//  그대로 두면 하루의 시간이 두 번 깎이고, 캘린더에 쓰기를 켜 두면 캘린더에도 두 번 선다.
//
//  두 갈래로 다룬다.
//   - **거의 확실한 것**(시작이 15분 안, 제목이 같거나 한쪽이 다른 쪽을 품는다) → 가져올 때
//     새 블록을 만들지 않고 사람의 블록에 캘린더를 **짝지어 붙인다** (→ CalendarBridge.importWeek).
//   - **시간만 겹치는 것**(제목이 다르다) → 같은 일인지 앱은 모른다. 배너로 알리고
//     사람이 짝마다 '합치기'·'따로 두기'를 고른다 (→ CalendarMergeSheet).
//
//  합치면 **사람의 블록이 남는다** — 성공 기준·회고처럼 사람이 적은 것은 거기 있다.
//  시각은 캘린더를 따른다(캘린더가 바뀌면 따라가야 하므로). 제목은 사람이 지은 것을 지킨다.
//

import SwiftUI
import SwiftData

enum CalendarMerge {
    private static let keptApartKey = "calendar.keptApartPairs"
    private static let ownTitleKey = "calendar.ownTitleKeys"

    /// 겹치는 짝 하나 — 캘린더에서 온 블록과 사람이 세운 블록.
    struct Pair: Identifiable {
        let imported: PlanBlock
        let mine: PlanBlock
        var id: String { "\(imported.calendarEventID ?? "")|\(CalendarBridge.exportID(for: mine))" }
    }

    // MARK: 같은 일로 보는 기준

    /// 제목이 같은 일을 말하는가. 띄어쓰기·문장부호·대소문자는 보지 않는다.
    /// 한쪽이 다른 쪽을 품어도 같다고 본다 ('주간 회의' ↔ '회의'). 한 글자짜리는 품는 것으로 치지 않는다.
    static func similarTitles(_ a: String, _ b: String) -> Bool {
        let x = normalized(a), y = normalized(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        return short.count >= 2 && long.contains(short)
    }

    private static func normalized(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// 두 블록의 시간이 겹치는 길이(시간). 시각이 없거나 종일이면 0.
    static func overlapHours(_ a: PlanBlock, _ b: PlanBlock) -> Double {
        guard a.startHour >= 0, b.startHour >= 0, !a.isAllDay, !b.isAllDay else { return 0 }
        let start = max(a.startHour, b.startHour)
        let end = min(a.startHour + a.durationHours, b.startHour + b.durationHours)
        return max(0, end - start)
    }

    /// 가져오는 일정과 짝지을 사람의 블록 — **거의 확실한 것만.** 묻지 않고 붙이므로 기준이 좁다.
    static func autoMatch(title: String, day: DayOfWeek, startHour: Double,
                          among blocks: [PlanBlock]) -> PlanBlock? {
        blocks.first { (b: PlanBlock) -> Bool in
            guard b.calendarEventID == nil, b.day == day, !b.isAllDay else { return false }
            let sameStart = b.startHour < 0 || abs(b.startHour - startHour) <= 0.25
            return sameStart && similarTitles(b.title, title)
        }
    }

    /// 사람이 골라야 하는 짝들 — 같은 요일에 시간이 겹치는데 같은 일인지 모르는 것.
    /// 짧은 쪽 길이의 절반 넘게 겹칠 때만 센다. 10분 물린 것까지 물으면 매번 배너가 선다.
    static func pairs(in blocks: [PlanBlock], routineNames: Set<String>) -> [Pair] {
        let keptApart = keptApartPairs
        let imported = blocks.filter { $0.calendarEventID != nil }
        let mine = blocks.filter { $0.calendarEventID == nil && !$0.isRoutineKind(routineNames) }
        var result: [Pair] = []
        var used = Set<ObjectIdentifier>()
        for i in imported.sorted(by: { $0.sortHour < $1.sortHour }) {
            let match = mine
                .filter { (m: PlanBlock) -> Bool in
                    guard m.day == i.day, m.weekStartDate == i.weekStartDate,
                          !used.contains(ObjectIdentifier(m)) else { return false }
                    return overlapHours(i, m) > 0.5 * min(i.durationHours, m.durationHours)
                }
                .max { overlapHours(i, $0) < overlapHours(i, $1) }
            guard let match else { continue }
            let pair = Pair(imported: i, mine: match)
            guard !keptApart.contains(pair.id) else { continue }
            used.insert(ObjectIdentifier(match))
            result.append(pair)
        }
        return result
    }

    // MARK: 합치기 · 따로 두기

    /// **합친다.** 사람의 블록이 캘린더 일정을 맡고, 가져온 블록은 지운다.
    static func merge(_ pair: Pair, in context: ModelContext) {
        let mine = pair.mine, imported = pair.imported
        guard let key = imported.calendarEventID else { return }
        mine.calendarEventID = key
        mine.startHour = imported.startHour
        mine.durationHours = imported.durationHours
        mine.timeBand = imported.timeBand
        // 가져온 쪽에 사람이 적은 것이 있으면 빈 칸만 채운다 — 어느 쪽 글도 버리지 않는다.
        if mine.successCriteria.isEmpty { mine.successCriteria = imported.successCriteria }
        if mine.deliverable.isEmpty { mine.deliverable = imported.deliverable }
        if (mine.nextAction ?? "").isEmpty { mine.nextAction = imported.nextAction }
        if mine.reviewStatus == nil, imported.reviewStatus != nil {
            mine.reviewStatus = imported.reviewStatus
            mine.reviewNote = imported.reviewNote
            mine.reviewedAt = imported.reviewedAt
        }
        keepOwnTitle(for: key)
        context.delete(imported)
        try? context.save()
    }

    /// **따로 둔다.** 이 짝은 다시 묻지 않는다 (기기마다 기억한다).
    static func keepApart(_ pair: Pair) {
        var set = keptApartPairs
        set.insert(pair.id)
        UserDefaults.standard.set(Array(set.suffix(1000)), forKey: keptApartKey)
    }

    private static var keptApartPairs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: keptApartKey) ?? [])
    }

    // MARK: 사람이 지은 제목

    /// 합친 블록의 제목은 사람 것이다. 가져오기가 캘린더 제목으로 덮지 않는다.
    static func keepOwnTitle(for key: String) {
        var set = Set(UserDefaults.standard.stringArray(forKey: ownTitleKey) ?? [])
        set.insert(key)
        UserDefaults.standard.set(Array(set.suffix(3000)), forKey: ownTitleKey)
    }

    static func hasOwnTitle(_ key: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: ownTitleKey) ?? []).contains(key)
    }
}

/// **겹치는 짝을 하나씩 보고 고르는 창.** 왼쪽은 캘린더, 오른쪽은 내 계획.
struct CalendarMergeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let pairs: [CalendarMerge.Pair]
    /// 고른 짝은 목록에서 빠진다. 다 고르면 창이 닫힌다.
    @State private var decided: Set<String> = []

    private var remaining: [CalendarMerge.Pair] { pairs.filter { !decided.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("캘린더 일정과 겹치는 계획")
                    .font(.title3.weight(.semibold))
                Text("같은 일이면 합치세요. 내 계획이 남고, 시각은 캘린더를 따라갑니다. 다른 일이면 따로 두면 다시 묻지 않습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(remaining) { pair in
                        row(pair)
                            .transition(.disclose)
                    }
                }
                .animation(Motion.row, value: decided)
            }

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .onChange(of: remaining.isEmpty) { _, empty in if empty { dismiss() } }
    }

    private func row(_ pair: CalendarMerge.Pair) -> some View {
        HStack(spacing: 12) {
            side(pair.imported, symbol: "calendar", label: String(localized: "캘린더"))
            Image(systemName: "arrow.left.and.right")
                .foregroundStyle(.tertiary)
            side(pair.mine, symbol: "square.stack", label: String(localized: "내 계획"))
            VStack(spacing: 6) {
                Button("합치기") {
                    CalendarMerge.merge(pair, in: context)
                    decided.insert(pair.id)
                }
                .buttonStyle(.borderedProminent)
                Button("따로 두기") {
                    CalendarMerge.keepApart(pair)
                    decided.insert(pair.id)
                }
            }
            .frame(width: 88)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: .soft(Corner.card))
    }

    private func side(_ block: PlanBlock, symbol: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(block.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            Text("\(block.day.shortLabel) \(block.whenLabel) · \(shortHours(block.durationHours))")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
