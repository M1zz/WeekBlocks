//
//  ReflectionTrendsView.swift
//  WeekBlocks
//
//  **지난 주들을 겹쳐 본다** — Pro.
//
//  한 주 회고는 "이번 주에 무엇을 했나"에 답한다. 여러 주를 모으면 다른 질문에 답이 선다:
//  나는 무슨 요일에 잘 해내는가, 몇 시대에 무너지는가, 무엇을 번번이 미루는가.
//  다음 주를 짤 때 쓸모 있는 건 이쪽이다.
//
//  새로 저장하는 것은 없다. 매일 찍어 둔 `PlanBlock.reviewStatus`를 주마다 모아 셀 뿐이다
//  (→ DayReflectionPanel · ReflectionView). 그래서 Pro를 산 날부터가 아니라
//  **그동안 찍어 둔 회고가 전부** 추세로 선다.
//

import SwiftUI
import Charts

/// 추세의 셈. 화면과 떼어 둔다 — 같은 숫자를 다른 자리(요약·알림)에서 다시 셀 일이 생긴다.
enum ReflectionTrends {
    /// 몇 주를 거슬러 보는가 (Pro).
    static let weekCount = 8
    /// **무료로 보이는 주 수.** 두 주면 "지난주보다 나아졌나"는 알 수 있다 — 값을 치르기 전에
    /// 이 화면이 무엇을 해 주는지 알 만큼은 열어 둔다. 쌓여야 보이는 것(요일·시간대·자주 미루는 일)은
    /// 그다음이다.
    static let freeWeekCount = 2

    struct Week: Identifiable {
        let start: Date
        let planned: Int
        let reviewed: Int
        let rate: Double?
        var id: Date { start }
    }

    struct Share: Identifiable {
        let label: String
        let reviewed: Int
        let rate: Double?
        var id: String { label }
    }

    struct Skipped: Identifiable {
        let title: String
        let count: Int
        var id: String { title }
    }

    /// 달성률 — 회고를 찍은 것 중에서. 부분 달성은 반으로 센다.
    ///
    /// 안 찍은 블록은 분모에 넣지 않는다. 그걸 넣으면 "안 했다"와 "안 돌아봤다"가 섞여
    /// 회고를 게을리한 주가 곧 못 한 주로 보인다. 회고를 얼마나 찍었는지는 따로 적는다.
    static func rate(_ blocks: [PlanBlock]) -> Double? {
        let reviewed = blocks.filter { $0.reviewStatus != nil }
        guard !reviewed.isEmpty else { return nil }
        let score = reviewed.reduce(0.0) { acc, b in
            switch b.reviewStatus {
            case .done: acc + 1
            case .partial: acc + 0.5
            default: acc
            }
        }
        return score / Double(reviewed.count)
    }

    /// `ending` 주까지 거슬러 `count`주. 오래된 주가 앞이다.
    static func weekStarts(ending: Date, count: Int = weekCount) -> [Date] {
        let cal = Calendar(identifier: .iso8601)
        return (0..<max(1, count)).reversed().compactMap {
            cal.date(byAdding: .weekOfYear, value: -$0, to: ending)
        }
    }

    /// 그 주들에 속한 블록. 캘린더에서 가져온 회의는 뺀다 — 내가 짠 계획이 아니다.
    static func blocks(_ all: [PlanBlock], in starts: [Date]) -> [PlanBlock] {
        let cal = Calendar(identifier: .iso8601)
        return all.filter { b in
            b.calendarEventID == nil && starts.contains { cal.isDate($0, inSameDayAs: b.weekStartDate) }
        }
    }

    static func weeks(_ all: [PlanBlock], ending: Date, count: Int = weekCount) -> [Week] {
        let cal = Calendar(identifier: .iso8601)
        let starts = weekStarts(ending: ending, count: count)
        let inRange = blocks(all, in: starts)
        return starts.map { start in
            let mine = inRange.filter { cal.isDate($0.weekStartDate, inSameDayAs: start) }
            return Week(start: start, planned: mine.count,
                        reviewed: mine.filter { $0.reviewStatus != nil }.count,
                        rate: rate(mine))
        }
    }

    static func byDay(_ blocks: [PlanBlock]) -> [Share] {
        DayOfWeek.allCases.map { day in
            let mine = blocks.filter { $0.day == day }
            return Share(label: day.shortLabel,
                         reviewed: mine.filter { $0.reviewStatus != nil }.count,
                         rate: rate(mine))
        }
    }

    static func byBand(_ blocks: [PlanBlock]) -> [Share] {
        TimeBand.allCases.map { band in
            let mine = blocks.filter { $0.timeBand == band }
            return Share(label: band.shortLabel,
                         reviewed: mine.filter { $0.reviewStatus != nil }.count,
                         rate: rate(mine))
        }
    }

    /// 두 번 이상 건너뛴 일. 단계를 올린 블록("할 일 · 단계")은 할 일 이름으로 모은다.
    static func mostSkipped(_ blocks: [PlanBlock], limit: Int = 5) -> [Skipped] {
        var counts: [String: Int] = [:]
        for b in blocks where b.reviewStatus == .skipped {
            let root = b.title.components(separatedBy: " · ").first ?? b.title
            counts[root, default: 0] += 1
        }
        return counts.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { Skipped(title: $0.key, count: $0.value) }
    }
}

struct ReflectionTrendsView: View {
    /// 보고 있는 주. 여기까지 거슬러 센다.
    let weekStart: Date
    let allBlocks: [PlanBlock]

    @State private var purchases = PurchaseManager.shared
    @State private var showingPaywall = false

    /// 무료는 2주, Pro는 8주.
    private var weekCount: Int {
        purchases.isPro ? ReflectionTrends.weekCount : ReflectionTrends.freeWeekCount
    }

    private var weeks: [ReflectionTrends.Week] {
        ReflectionTrends.weeks(allBlocks, ending: weekStart, count: weekCount)
    }
    private var rangeBlocks: [PlanBlock] {
        ReflectionTrends.blocks(allBlocks, in: ReflectionTrends.weekStarts(ending: weekStart, count: weekCount))
    }

    var body: some View {
        content
            .sheet(isPresented: $showingPaywall) {
                PaywallView(reason: WeekBlocksSpec.Gate.trends)
            }
    }

    /// 안 산 사람에게 여는 자리와 잠그는 자리를 가르는 한 줄.
    ///
    /// **무료로도 지난 2주는 그대로 보인다** — 숫자가 제 것이어야 살지 말지를 정할 수 있다.
    /// 잠그는 것은 여러 주가 쌓여야 비로소 말이 되는 것들이다: 8주 추세, 요일·시간대의 결,
    /// 번번이 미루는 일.
    private var proBanner: some View {
        HStack(spacing: 10) {
            GlyphBadge(symbol: "sparkles", color: .accentColor, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("지난 \(ReflectionTrends.weekCount)주까지 넓혀 보기")
                    .font(.system(size: 14, weight: .semibold))
                Text("잘 되는 요일과 시간대, 번번이 미루는 일은 몇 주가 쌓여야 보입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                showingPaywall = true
            } label: {
                Label("Pro 보기", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.09), in: .soft(Corner.card))
        .overlay(RoundedRectangle.soft(Corner.card).strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1))
    }

    // MARK: 추세

    private var content: some View {
        let weeks = self.weeks
        let blocks = rangeBlocks
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary(weeks)
                weeklyChart(weeks)
                if purchases.isPro {
                    HStack(alignment: .top, spacing: 14) {
                        shareCard(title: "요일별", shares: ReflectionTrends.byDay(blocks))
                        shareCard(title: "시간대별", shares: ReflectionTrends.byBand(blocks))
                    }
                    skippedCard(ReflectionTrends.mostSkipped(blocks))
                } else {
                    proBanner
                }
            }
            .padding(20)
        }
    }

    /// 앞뒤 절반을 견준다. 한 주는 들쭉날쭉해서 방향이 안 읽힌다 (8주면 4주씩, 2주면 1주씩).
    private func summary(_ weeks: [ReflectionTrends.Week]) -> some View {
        let half = max(1, weeks.count / 2)
        let recent = ReflectionTrends.rate(rangeBlocksIn(weeks.suffix(half)))
        let earlier = ReflectionTrends.rate(rangeBlocksIn(weeks.prefix(max(0, weeks.count - half))))
        let reviewed = weeks.reduce(0) { $0 + $1.reviewed }
        let planned = weeks.reduce(0) { $0 + $1.planned }

        return HStack(spacing: 10) {
            tile(label: "최근 달성률", value: recent.map(percent) ?? "–", color: .green)
            tile(label: "그 앞과 비교", value: delta(recent, earlier), color: deltaColor(recent, earlier))
            tile(label: "회고한 블록", value: "\(reviewed)/\(planned)", color: .secondary)
        }
    }

    private func rangeBlocksIn<S: Sequence>(_ weeks: S) -> [PlanBlock] where S.Element == ReflectionTrends.Week {
        ReflectionTrends.blocks(allBlocks, in: weeks.map(\.start))
    }

    private func weeklyChart(_ weeks: [ReflectionTrends.Week]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("주별 달성률")
                .font(.subheadline.weight(.semibold))
            Chart(weeks) { week in
                BarMark(
                    x: .value("주", weekLabel(week.start)),
                    y: .value("달성률", week.rate ?? 0)
                )
                .foregroundStyle(week.rate == nil ? AnyShapeStyle(Color.secondary.opacity(0.2)) : AnyShapeStyle(Color.green.gradient))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 2) {
                    Text(week.rate.map(percent) ?? "")
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(percent(v)) }
                    }
                }
            }
            .frame(height: 170)
            Text("회고를 찍은 블록 중에서 셉니다. 부분 달성은 반으로 칩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: .soft(Corner.card))
    }

    private func shareCard(title: LocalizedStringKey, shares: [ReflectionTrends.Share]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(shares) { share in
                HStack(spacing: 8) {
                    Text(share.label)
                        .font(.caption.weight(.medium))
                        .frame(width: 30, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            if let rate = share.rate {
                                Capsule()
                                    .fill(Color.green.opacity(0.75))
                                    .frame(width: max(4, geo.size.width * rate))
                            }
                        }
                    }
                    .frame(height: 8)
                    Text(share.rate.map(percent) ?? "–")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .help(String(localized: "회고한 블록 \(share.reviewed)개"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: .soft(Corner.card))
    }

    private func skippedCard(_ skipped: [ReflectionTrends.Skipped]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("자주 건너뛴 일")
                .font(.subheadline.weight(.semibold))
            if skipped.isEmpty {
                Text("두 번 넘게 건너뛴 일이 없습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(skipped) { item in
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                        Text(item.title)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)번")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Text("번번이 미루는 일은 크기가 너무 크거나 시간대가 안 맞는 경우가 많습니다. 단계로 쪼개거나 잘 되는 시간대로 옮겨 보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: .soft(Corner.card))
    }

    private func tile(label: LocalizedStringKey, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .soft(Corner.card))
    }

    // MARK: 글자

    private func percent(_ v: Double) -> String {
        v.formatted(.percent.precision(.fractionLength(0)))
    }

    private func delta(_ recent: Double?, _ earlier: Double?) -> String {
        guard let recent, let earlier else { return "–" }
        let points = Int(((recent - earlier) * 100).rounded())
        if points == 0 { return String(localized: "그대로") }
        return points > 0 ? "+\(points)%p" : "\(points)%p"
    }

    private func deltaColor(_ recent: Double?, _ earlier: Double?) -> Color {
        guard let recent, let earlier else { return .secondary }
        let d = recent - earlier
        if abs(d) < 0.005 { return .secondary }
        return d > 0 ? .green : .orange
    }

    private func weekLabel(_ start: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: start)
    }
}
