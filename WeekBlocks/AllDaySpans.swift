//
//  AllDaySpans.swift
//  무지개 공방
//
//  **종일 일정을 날짜 위의 막대로.**
//
//  캘린더 가져오기는 여러 날에 걸친 종일 일정(3일짜리 출장)을 첫날에만 블록 하나로 세운다.
//  그대로 두면 출장이 월요일 칩 하나로만 보이고 화·수는 아무 일 없는 날처럼 보였다.
//  여기서 며칠에 걸치는지 되살려, 주간은 요일 칸을 가로지르는 막대로, 일간은 "3일 중 2일째"로 세운다.
//
//  - 캘린더에서 온 것: 끝나는 날을 캘린더에서 다시 읽는다 (→ CalendarBridge.allDaySpanDays).
//  - 사람이 만든 것: 이어진 날에 같은 제목 · 같은 종류(배경/할 일)로 서 있으면 하나로 본다.
//

import SwiftUI

struct AllDaySpan: Identifiable {
    /// 막대를 대표하는 블록 — 누르면 이것을 연다.
    let block: PlanBlock
    /// 같은 막대로 묶인 블록들 (사람이 날마다 따로 만든 것).
    let members: [PlanBlock]
    /// 첫날 0시.
    let start: Date
    let days: Int

    var id: String { block.dragToken }
    var title: String { block.title }
    var isBackground: Bool { block.isBackground }

    /// 그날이 이 막대 안인가.
    func covers(_ date: Date) -> Bool { dayIndex(of: date) != nil }

    /// 그날이 몇 번째 날인가 (1부터). 막대 밖이면 nil.
    func dayIndex(of date: Date) -> Int? {
        let cal = Calendar.current
        guard let n = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day,
              n >= 0, n < days else { return nil }
        return n + 1
    }

    /// "출장 · 3일 중 2일째" — 하루짜리면 제목만.
    func label(on date: Date) -> String {
        guard days > 1, let i = dayIndex(of: date) else { return title }
        return String(localized: "\(title) · \(days)일 중 \(i)일째")
    }

    /// **쉬는 날인가** — 휴가·연차·출장·공휴일처럼 그날 회사 같은 루틴이 서지 않을 법한 배경 일정.
    /// 제목의 낱말로 짐작한다. 틀려도 잃는 것은 '회사를 뺄까요?' 한 번 묻는 것뿐이다.
    var looksLikeDayOff: Bool {
        guard isBackground else { return false }
        let t = title.lowercased()
        return Self.dayOffWords.contains { t.contains($0) }
    }

    private static let dayOffWords = [
        "휴가", "연차", "반차", "휴무", "휴일", "공휴일", "대체공휴일", "출장", "방학", "워크숍", "쉬는 날",
        "설날", "추석", "명절", "크리스마스", "성탄절", "신정", "어린이날", "현충일", "광복절", "개천절", "한글날",
        "vacation", "holiday", "pto", "ooo", "out of office", "day off", "leave", "business trip",
    ]

    // MARK: 만들기

    /// 한 주의 종일 블록에서 막대를 만든다. `dateOf`는 그 블록이 선 날의 0시.
    @MainActor
    static func spans(from blocks: [PlanBlock], dateOf: (PlanBlock) -> Date) -> [AllDaySpan] {
        let cal = Calendar.current
        let allDay = blocks.filter(\.isAllDay).sorted { dateOf($0) < dateOf($1) }
        var result: [AllDaySpan] = []
        var used = Set<String>()

        for block in allDay where !used.contains(block.dragToken) {
            let start = cal.startOfDay(for: dateOf(block))
            if let key = block.calendarEventID {
                used.insert(block.dragToken)
                let days = CalendarBridge.shared.allDaySpanDays(forKey: key) ?? 1
                result.append(AllDaySpan(block: block, members: [block], start: start, days: days))
                continue
            }
            // 사람이 날마다 같은 이름으로 세운 것은 이어 붙인다.
            var members = [block]
            used.insert(block.dragToken)
            var next = cal.date(byAdding: .day, value: 1, to: start)!
            func continues(_ other: PlanBlock) -> Bool {
                guard !used.contains(other.dragToken), other.calendarEventID == nil else { return false }
                guard other.title == block.title, other.isBackground == block.isBackground else { return false }
                return cal.isDate(dateOf(other), inSameDayAs: next)
            }
            while let follow = allDay.first(where: continues) {
                members.append(follow)
                used.insert(follow.dragToken)
                next = cal.date(byAdding: .day, value: 1, to: next)!
            }
            result.append(AllDaySpan(block: block, members: members, start: start, days: members.count))
        }
        return result
    }

    /// 겹치지 않게 줄을 나눈다 — 막대마다 몇 번째 줄인가. `firstIndex`는 보이는 주의 첫날 기준 칸 번호.
    static func rows(_ spans: [AllDaySpan], firstIndex: (AllDaySpan) -> Int) -> [String: Int] {
        var rowEnds: [Int] = []
        var result: [String: Int] = [:]
        for span in spans.sorted(by: { firstIndex($0) < firstIndex($1) }) {
            let s = firstIndex(span), e = s + span.days
            if let r = rowEnds.firstIndex(where: { $0 <= s }) {
                rowEnds[r] = e
                result[span.id] = r
            } else {
                rowEnds.append(e)
                result[span.id] = rowEnds.count - 1
            }
        }
        return result
    }
}

// MARK: - 주간: 요일 칸을 가로지르는 막대

/// 주간 블록 보기의 요일 칸 위에 서는 종일 줄. 칸과 같은 폭·같은 틈으로 나눈다.
struct AllDayLane: View {
    let spans: [AllDaySpan]
    /// 보이는 요일들의 0시 (왼쪽부터).
    let dates: [Date]
    let spacing: CGFloat
    let onOpen: (PlanBlock) -> Void

    private static let rowHeight: CGFloat = 26

    /// 보이는 첫날 기준 몇 번째 칸에서 시작하는가. 보이는 주 밖에서 시작했으면 음수.
    private func first(_ s: AllDaySpan) -> Int {
        Calendar.current.dateComponents([.day], from: dates.first ?? s.start, to: s.start).day ?? 0
    }

    var body: some View {
        let visible = spans.filter { s in
            let f = first(s)
            return f < dates.count && f + s.days > 0
        }
        let rows = AllDaySpan.rows(visible, firstIndex: first)
        let rowCount = (rows.values.max() ?? -1) + 1

        GeometryReader { geo in
            let n = CGFloat(max(1, dates.count))
            let col = (geo.size.width - spacing * (n - 1)) / n
            ZStack(alignment: .topLeading) {
                ForEach(visible) { span in
                    let f = first(span)
                    let from = max(0, f), to = min(dates.count, f + span.days)
                    let x = CGFloat(from) * (col + spacing)
                    let width = CGFloat(to - from) * col + CGFloat(max(0, to - from - 1)) * spacing
                    AllDayBar(span: span, clippedLeft: f < 0, clippedRight: f + span.days > dates.count) {
                        onOpen(span.block)
                    }
                    .frame(width: width, height: Self.rowHeight - 4)
                    .offset(x: x, y: CGFloat(rows[span.id] ?? 0) * Self.rowHeight)
                }
            }
        }
        .frame(height: CGFloat(rowCount) * Self.rowHeight)
        .animation(Motion.squish, value: visible.map(\.id))
    }
}

/// 막대 하나. 배경은 흐린 회색에 달력 표시, 할 일은 무지개 대신 액센트 테두리.
struct AllDayBar: View {
    let span: AllDaySpan
    var clippedLeft = false
    var clippedRight = false
    var tint: Color? = nil
    let onOpen: () -> Void

    @State private var hovering = false

    private var color: Color { span.isBackground ? .secondary : (tint ?? .accentColor) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                if clippedLeft { Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)) }
                Image(systemName: span.looksLikeDayOff ? "sun.max" : (span.isBackground ? "calendar" : "checklist"))
                    .font(.system(size: 12, weight: .semibold))
                Text(span.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if span.days > 1 {
                    Text("\(span.days)일")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
                if clippedRight { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundStyle(span.isBackground ? Color.primary.opacity(0.75) : color)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(color.opacity(hovering ? 0.2 : 0.13), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { AllDayKindMenu(block: span.block) }
        .help(span.isBackground
              ? String(localized: "그날의 배경 일정 — 할 일로 세지 않습니다. 우클릭해서 바꿀 수 있습니다")
              : String(localized: "그날 해야 할 일 (시각 없음)"))
    }
}
