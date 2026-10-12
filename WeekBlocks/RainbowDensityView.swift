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
//

import SwiftUI

struct RainbowDensityView: View {
    let events: [RainbowEvent]
    /// 보여 줄 첫날 (그 주의 첫날).
    let start: Date
    let weeks: Int
    let onOpen: (RainbowEvent) -> Void
    let onAdd: (Date) -> Void

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
                    }
                    countRow(days, packed: packed)
                }
                .padding(.bottom, 6)
            }
            legend
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
                .help("두 번 눌러 이날부터 무지개 일정 추가")
            }
        }
    }

    // MARK: 줄

    private func laneRow(_ lane: Int, days: [Date], packed: RainbowPacking.Result) -> some View {
        let color = Color(hex: Rainbow.spectrum[lane].hex) ?? .accentColor
        return HStack(spacing: Self.gap) {
            ForEach(days, id: \.self) { day in
                let event = packed.event(lane: lane, on: day)
                let state = event.map { $0.occurs(on: day) ? 2 : ($0.spans(day) ? 1 : 0) } ?? 0
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(state == 2 ? color : (state == 1 ? color.opacity(0.28) : Color.primary.opacity(0.045)))
                    .frame(width: Self.cellWidth, height: Self.cellHeight)
                    .overlay {
                        // 그 줄에서 이 일정이 보이기 시작하는 칸에만 제목 첫 글자 — 칸이 좁아 긴 글은 말풍선(help)으로.
                        // (보는 기간보다 먼저 시작한 일정도 첫 칸에 이름이 선다)
                        if let event, state > 0, packed.startsHere(lane: lane, on: day) {
                            Text(event.title.prefix(1))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(state == 2 ? Color.white : color)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if let event { onOpen(event) } }
                    .help(event?.title ?? "")
            }
        }
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
        var lanes: [[(event: RainbowEvent, from: Int, to: Int)]]
        var days: [Date]
        /// 줄에 못 들어간 일정.
        var overflowed: [(event: RainbowEvent, from: Int, to: Int)]

        func event(lane: Int, on day: Date) -> RainbowEvent? {
            guard lane < lanes.count, let i = days.firstIndex(of: day) else { return nil }
            return lanes[lane].first { $0.from <= i && i <= $0.to }?.event
        }

        func startsHere(lane: Int, on day: Date) -> Bool {
            guard lane < lanes.count, let i = days.firstIndex(of: day) else { return false }
            return lanes[lane].contains { $0.from == i }
        }

        func overflow(on day: Date) -> Int {
            guard let i = days.firstIndex(of: day) else { return 0 }
            return overflowed.filter { $0.from <= i && i <= $0.to && $0.event.occurs(on: day) }.count
        }
    }

    static func pack(_ events: [RainbowEvent], days: [Date], lanes: Int) -> Result {
        // 보는 기간 안에서 차지하는 칸 (기간 안인 첫날 ~ 마지막 날).
        let spans: [(RainbowEvent, Int, Int)] = events.compactMap { e in
            let hits = days.indices.filter { e.spans(days[$0]) }
            guard let a = hits.first, let b = hits.last else { return nil }
            return (e, a, b)
        }
        .sorted { l, r in
            // 먼저 시작한 것 → 긴 것 → 만든 차례. 어느 기기에서 그려도 같은 줄이 나오게 uuid로 끝낸다.
            if l.1 != r.1 { return l.1 < r.1 }
            if (l.2 - l.1) != (r.2 - r.1) { return (l.2 - l.1) > (r.2 - r.1) }
            return l.0.uuid < r.0.uuid
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
