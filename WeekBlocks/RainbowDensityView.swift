//
//  RainbowDensityView.swift
//  무지개 공방
//
//  **날짜를 가로로 늘어놓고, 그날 겹친 일정의 수를 무지개 줄로 쌓는다.**
//
//  아이폰 '욕망의 무지개'의 첫 화면을 맥에 옮긴 것이다. 아이폰은 날짜가 아래로 흐르고 줄이 옆으로 서지만,
//  맥은 화면이 가로로 넓어서 날짜를 옆으로 흘리고 줄을 위아래로 쌓는다.
//  빨강 줄부터 채우므로, 한 날의 칸이 보라 쪽까지 차오를수록 그날이 빽빽하다는 뜻이다.
//
//  · 하는 날은 진하게, 기간 안이지만 쉬는 날(요일 · 패턴 · 뺀 날)은 옅게 — 아이폰과 같다.
//  · 줄은 일곱 개(무지개 일곱 빛). 그보다 많이 겹치면 맨 아래에 "+N"으로 센다.
//  · 일정 색은 그 일정의 색이 아니라 **줄의 색**이다. 아이폰도 줄로 칠한다 — 색이 곧 밀도의 눈금이다.
//  · 무지개 일정만이 아니라 **계획 블록도 하루짜리 한 줄로** 선다 (→ RainbowDensityItem). 아이폰 무지개가
//    맥 계획(캘린더에서 가져온 회의 포함)을 함께 세우기 때문이다. 무지개 일정만 넣었더니 아이폰은 빽빽한데
//    맥 판은 텅 비었다. 루틴 이름의 블록 · 배경 종일은 요일 아래 점처럼 세지 않는다 (→ PlanBlock.isTodo).
//

import SwiftUI

/// 무지개 판의 한 줄 — 여러 날에 걸친 무지개 일정이거나, 하루짜리 계획 블록.
enum RainbowDensityItem {
    case event(RainbowEvent)
    /// 블록과 그 블록이 선 날(0시).
    case block(PlanBlock, date: Date)

    init(_ block: PlanBlock) {
        let date = Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: block.day.rawValue, to: block.weekStartDate) ?? block.weekStartDate
        self = .block(block, date: Calendar.current.startOfDay(for: date))
    }

    /// 어느 기기에서 그려도 같은 줄이 나오게 하는 마지막 열쇠.
    var key: String {
        switch self {
        case .event(let e): e.uuid
        case .block(let b, _): b.dragToken
        }
    }

    var title: String {
        switch self {
        case .event(let e): e.title
        case .block(let b, _): b.title
        }
    }

    func spans(_ day: Date) -> Bool {
        switch self {
        case .event(let e): e.spans(day)
        case .block(_, let date): Calendar.current.isDate(date, inSameDayAs: day)
        }
    }

    func occurs(on day: Date) -> Bool {
        switch self {
        case .event(let e): e.occurs(on: day)
        case .block(_, let date): Calendar.current.isDate(date, inSameDayAs: day)
        }
    }
}

struct RainbowDensityView: View {
    let events: [RainbowDensityItem]
    /// 보여 줄 첫날 (그 주의 첫날).
    let start: Date
    let weeks: Int
    let onOpen: (RainbowDensityItem) -> Void
    let onAdd: (Date) -> Void
    /// 날짜 · 칸을 가로로 끌어 고른 기간 (첫날, 끝날).
    let onAddRange: (Date, Date) -> Void

    /// 끌고 있는 동안 고른 칸 (시작 번호, 지금 번호).
    @State private var dragRange: (from: Int, to: Int)?
    /// 마우스를 올려 둔 칸 — 무슨 일정인지 작은 카드로 보여 준다 (→ `hoverCard`).
    @State private var hovered: HoverCell?

    private struct HoverCell: Equatable {
        let lane: Int
        let day: Int
    }

    private static let laneCount = 7
    private static let cellWidth: CGFloat = 30
    private static let cellHeight: CGFloat = 22
    private static let gap: CGFloat = 2

    private var days: [Date] {
        let cal = Calendar.current
        let first = cal.startOfDay(for: start)
        return (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        let days = self.days
        let packed = RainbowPacking.pack(events, days: days, lanes: Self.laneCount)

        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Self.gap) {
                    monthRow(days)
                    dateRow(days)
                    ForEach(0..<Self.laneCount, id: \.self) { lane in
                        laneRow(lane, days: days, packed: packed)
                            // 카드가 아래 · 위 줄에 가리지 않게 올려 둔 줄을 앞으로.
                            .zIndex(hovered?.lane == lane ? 1 : 0)
                    }
                    countRow(days, packed: packed)
                }
                .coordinateSpace(name: Self.gridSpace)
                .overlay(alignment: .topLeading) { dragHighlight }
                // 가로로 끌어 기간을 고른다 — 놓으면 그 기간으로 장기 플랜 추가. 조금은 움직여야 끌기로 친다
                // (칸 누르기 · 날짜 두 번 누르기는 그대로).
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
                        .onChanged { value in
                            let from = column(at: value.startLocation.x, count: days.count)
                            let to = column(at: value.location.x, count: days.count)
                            if dragRange?.from != from || dragRange?.to != to { dragRange = (from, to) }
                        }
                        .onEnded { _ in
                            guard let range = dragRange else { return }
                            dragRange = nil
                            onAddRange(days[min(range.from, range.to)], days[max(range.from, range.to)])
                        }
                )
                .padding(.bottom, 6)
            }
            legend
        }
    }

    // MARK: 끌어 고르기

    private static let gridSpace = "rainbowGrid"

    private func column(at x: CGFloat, count: Int) -> Int {
        min(max(Int(x / (Self.cellWidth + Self.gap)), 0), count - 1)
    }

    /// 끌고 있는 기간 — 고른 날들의 세로 띠.
    @ViewBuilder private var dragHighlight: some View {
        if let range = dragRange {
            let lo = min(range.from, range.to), hi = max(range.from, range.to)
            let step = Self.cellWidth + Self.gap
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .frame(width: CGFloat(hi - lo + 1) * step - Self.gap)
                .offset(x: CGFloat(lo) * step)
                .allowsHitTesting(false)
        }
    }

    // MARK: 머리 — 달 · 날짜

    private func monthRow(_ days: [Date]) -> some View {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return HStack(spacing: Self.gap) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                let showsMonth = i == 0 || Calendar.current.component(.day, from: day) == 1
                Text(showsMonth ? f.string(from: day) : "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Self.cellWidth, alignment: .leading)
            }
        }
    }

    private func dateRow(_ days: [Date]) -> some View {
        let cal = Calendar.current
        let wf = DateFormatter()
        wf.setLocalizedDateFormatFromTemplate("EEEEE")
        return HStack(spacing: Self.gap) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let isWeekend = cal.isDateInWeekend(day)
                VStack(spacing: 1) {
                    Text(wf.string(from: day))
                        .font(.system(size: 9, weight: .medium))
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 12, weight: isToday ? .bold : .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.secondary : Color.primary))
                .frame(width: Self.cellWidth, height: 30)
                .background {
                    if isToday { RoundedRectangle(cornerRadius: 7).fill(Color.red) }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onAdd(day) }
                .help("가로로 끌어 기간을 고르거나, 두 번 눌러 이날부터 장기 플랜 추가")
            }
        }
    }

    // MARK: 줄

    private func laneRow(_ lane: Int, days: [Date], packed: RainbowPacking.Result) -> some View {
        let color = Color(hex: Rainbow.spectrum[lane].hex) ?? .accentColor
        return HStack(spacing: Self.gap) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                let event = packed.event(lane: lane, on: day)
                let state = event.map { $0.occurs(on: day) ? 2 : ($0.spans(day) ? 1 : 0) } ?? 0
                // 기간이 이어진 일정은 칸 사이 틈까지 메워 한 막대로 선다. 둥근 모서리는 처음과 끝에만.
                let joinsPrev = i > 0 && packed.joins(lane: lane, i - 1, i)
                let joinsNext = i + 1 < days.count && packed.joins(lane: lane, i, i + 1)
                let r: CGFloat = 5
                // 하는 날은 옅은 막대 위에 제 모서리가 둥근 칸으로 따로 선다 — 막대에 이어 붙이면 네모가 된다.
                ZStack(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: joinsPrev ? 0 : r,
                                           bottomLeadingRadius: joinsPrev ? 0 : r,
                                           bottomTrailingRadius: joinsNext ? 0 : r,
                                           topTrailingRadius: joinsNext ? 0 : r,
                                           style: .continuous)
                        .fill(state >= 1 ? color.opacity(0.28) : Color.primary.opacity(0.045))
                        .frame(width: Self.cellWidth + (joinsNext ? Self.gap : 0), height: Self.cellHeight)
                    if state == 2 {
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .fill(color)
                            .frame(width: Self.cellWidth, height: Self.cellHeight)
                    }
                }
                    .frame(width: Self.cellWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let event { onOpen(event) } }
                    .onHover { inside in
                        let cell = HoverCell(lane: lane, day: i)
                        if inside, event != nil { hovered = cell } else if hovered == cell { hovered = nil }
                    }
                    // 위 네 줄은 아래로, 아래 세 줄은 위로 — 판 밖으로 나가 잘리지 않게. 오른쪽 끝 주는 왼쪽으로 편다.
                    .overlay(alignment: Self.cardAlignment(lane: lane, day: i, count: days.count)) {
                        if let event, hovered == HoverCell(lane: lane, day: i), dragRange == nil {
                            hoverCard(event, on: day, color: color)
                                .alignmentGuide(VerticalAlignment.top) { $0[.top] - Self.cellHeight - 4 }
                                .alignmentGuide(VerticalAlignment.bottom) { $0[.bottom] + Self.cellHeight + 4 }
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .help(event == nil ? String(localized: "가로로 끌어 기간을 고르면 장기 플랜 추가") : "")
                    .zIndex(hovered == HoverCell(lane: lane, day: i) ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }

    // MARK: 올려 보기

    private static func cardAlignment(lane: Int, day: Int, count: Int) -> Alignment {
        let trailing = day >= count - 7
        switch (lane < 4, trailing) {
        case (true, false): return .topLeading
        case (true, true): return .topTrailing
        case (false, false): return .bottomLeading
        case (false, true): return .bottomTrailing
        }
    }

    /// 칸에 마우스를 올리면 뜨는 카드 — 누르지 않아도 무슨 일정인지, 언제인지, 이날 하는지가 보인다.
    private func hoverCard(_ item: RainbowDensityItem, on day: Date, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
            ForEach(Self.cardLines(item, on: day), id: \.self) { line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 210, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 카드의 둘째 줄부터 — 기간, 이날 하는 것.
    private static func cardLines(_ item: RainbowDensityItem, on day: Date) -> [String] {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMdE")
        switch item {
        case .event(let e):
            let start = df.string(from: RainbowEvent.day(e.startDate))
            let period = e.isInfinite
                ? String(localized: "\(start)부터 계속")
                : "\(start) – \(df.string(from: RainbowEvent.day(e.endDate)))"
            let today: String
            if let session = e.session(on: day) {
                let name = session.title.isEmpty ? df.string(from: day) : session.title
                let at = session.startHour.map { formatHour($0) + " · " } ?? ""
                today = "\(name) · \(at)\(hours(session.hours))"
            } else if e.occurs(on: day) {
                today = String(localized: "이날 하는 날 · \(hours(e.hoursPerDay))")
            } else {
                today = String(localized: "이날은 쉬는 날")
            }
            return [period, today]
        case .block(let b, let date):
            let when = b.isAllDay ? b.whenLabel : "\(b.whenLabel) · \(hours(b.durationHours))"
            var lines = [df.string(from: date), when]
            if b.reviewStatus == .done { lines.append(String(localized: "끝냄")) }
            return lines
        }
    }

    /// 2 → "2시간", 1.5 → "1시간 30분", 0.5 → "30분".
    private static func hours(_ h: Double) -> String {
        let minutes = Int((h * 60).rounded())
        let hh = minutes / 60, mm = minutes % 60
        if hh == 0 { return String(localized: "\(mm)분") }
        if mm == 0 { return String(localized: "\(hh)시간") }
        return String(localized: "\(hh)시간 \(mm)분")
    }

    /// 그날 실제로 하는 일정의 수. 일곱 줄을 넘으면 넘친 수를 함께 적는다.
    private func countRow(_ days: [Date], packed: RainbowPacking.Result) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(days, id: \.self) { day in
                let n = events.filter { $0.occurs(on: day) }.count
                let over = packed.overflow(on: day)
                Text(n > 0 ? "\(n)" : "")
                    .font(.system(size: 10, weight: over > 0 ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(over > 0 ? Color.red : Color.secondary)
                    .frame(width: Self.cellWidth, height: 16)
                    .help(over > 0 ? String(localized: "이날 \(n)개 중 \(over)개는 일곱 줄을 넘어 그리지 못했습니다") : "")
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: 12, height: 12)
                Text("하는 날").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.28)).frame(width: 12, height: 12)
                Text("기간 안 쉬는 날").font(.caption).foregroundStyle(.secondary)
            }
            Text("보라 쪽까지 차오를수록 빽빽한 날입니다").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 줄 나누기

/// 일정을 일곱 줄에 나눈다. **빨강 줄부터 채운다** — 겹친 수가 곧 몇 번째 줄까지 찼는지가 된다.
///
/// 아이폰은 칸 점수를 최대로 하는 더 복잡한 배치를 쓰지만(→ ScheduleViewModel.packLanes),
/// 같은 원칙(먼저 · 길게 시작한 것을 위 줄에)을 간단히 따른다. 보는 기간 안에서만 나눈다.
enum RainbowPacking {
    struct Result {
        /// 줄 → 그 줄의 일정과 차지한 날(보는 기간 안의 첫날 · 끝날 번호).
        var lanes: [[(event: RainbowDensityItem, from: Int, to: Int)]]
        var days: [Date]
        /// 줄에 못 들어간 일정.
        var overflowed: [(event: RainbowDensityItem, from: Int, to: Int)]

        func event(lane: Int, on day: Date) -> RainbowDensityItem? {
            guard lane < lanes.count, let i = days.firstIndex(of: day) else { return nil }
            return lanes[lane].first { $0.from <= i && i <= $0.to }?.event
        }

        /// 이웃한 두 날(번호)이 이 줄에서 같은 일정의 기간으로 이어지는가. 손으로 뺀 날에서는 끊긴다.
        func joins(lane: Int, _ a: Int, _ b: Int) -> Bool {
            guard lane < lanes.count, a >= 0, b < days.count else { return false }
            guard let entry = lanes[lane].first(where: { $0.from <= a && b <= $0.to }) else { return false }
            return entry.event.spans(days[a]) && entry.event.spans(days[b])
        }

        func overflow(on day: Date) -> Int {
            guard let i = days.firstIndex(of: day) else { return 0 }
            return overflowed.filter { $0.from <= i && i <= $0.to && $0.event.occurs(on: day) }.count
        }
    }

    static func pack(_ events: [RainbowDensityItem], days: [Date], lanes: Int) -> Result {
        // 보는 기간 안에서 차지하는 칸 (기간 안인 첫날 ~ 마지막 날).
        let spans: [(RainbowDensityItem, Int, Int)] = events.compactMap { e in
            let hits = days.indices.filter { e.spans(days[$0]) }
            guard let a = hits.first, let b = hits.last else { return nil }
            return (e, a, b)
        }
        .sorted { l, r in
            // 먼저 시작한 것 → 긴 것 → 만든 차례. 어느 기기에서 그려도 같은 줄이 나오게 uuid로 끝낸다.
            if l.1 != r.1 { return l.1 < r.1 }
            if (l.2 - l.1) != (r.2 - r.1) { return (l.2 - l.1) > (r.2 - r.1) }
            return l.0.key < r.0.key
        }

        var result = Result(lanes: Array(repeating: [], count: lanes), days: days, overflowed: [])
        var laneEnd = Array(repeating: -1, count: lanes)
        for (e, a, b) in spans {
            if let lane = laneEnd.firstIndex(where: { $0 < a }) {
                result.lanes[lane].append((e, a, b))
                laneEnd[lane] = b
            } else {
                result.overflowed.append((e, a, b))
            }
        }
        return result
    }
}

// MARK: - 펴져 내려오는 결

/// 윗변을 붙든 채 세로로 펴진다. 가로는 살짝 좁았다가 넓어져 — 일간 판의 출렁임(→ ExpandablePanel)처럼
/// 가로와 세로가 엇갈려 움직여야 '쫀득'하게 읽힌다. `.panelSpring`과 짝이다.
private struct Unroll: ViewModifier {
    let y: CGFloat
    let x: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: x, y: y, anchor: .top)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static let unroll = AnyTransition.modifier(
        active: Unroll(y: 0.02, x: 0.96, opacity: 0),
        identity: Unroll(y: 1, x: 1, opacity: 1)
    )
}
