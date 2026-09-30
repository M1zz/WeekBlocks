//
//  TimerWidget.swift
//  무지개 공방 타이머 위젯
//
//  **지금 하고 있는 일정과 거기 남은 시간** — 앱의 맨 위 타이머 알약과 같은 것을 바탕화면에.
//
//  앱이 적어 둔 오늘의 타임라인(→ TimerWidgetSnapshot)을 읽어 **일정이 시작하고 끝나는 순간마다
//  한 장씩** 미리 만들어 둔다. 숫자는 위젯이 매초 그리지 않는다 — 끝 시각만 주면 시스템이 센다.
//  그래서 앱이 꺼져 있어도 3번째 인터뷰가 11:30에 시작하면 위젯도 11:30에 넘어간다.
//

import SwiftUI
import WidgetKit

// MARK: - 타임라인

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerWidgetSnapshot
}

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        let now = Date()
        return TimerEntry(date: now, snapshot: TimerWidgetSnapshot(items: [
            .init(title: String(localized: "집중"), iconName: "square.stack.3d.up", colorHex: "#FF3B30",
                  start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800)),
        ], direct: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        let snap = TimerWidgetSnapshot.load()
        completion(context.isPreview && snap.items.isEmpty ? placeholder(in: context)
                                                           : TimerEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let now = Date()
        let snap = TimerWidgetSnapshot.load()
        let horizon = now.addingTimeInterval(36 * 3600)

        // 무엇을 보여 줄지가 바뀌는 순간들 — 일정의 시작과 끝, 따로 세는 타이머의 끝.
        var moments = Set<Date>()
        for item in snap.items {
            if item.start > now, item.start < horizon { moments.insert(item.start) }
            if item.end > now, item.end < horizon { moments.insert(item.end) }
        }
        if let end = snap.direct?.end, end > now { moments.insert(end) }

        let dates = [now] + moments.sorted().prefix(80)
        let entries = dates.map { TimerEntry(date: $0, snapshot: snap) }
        // 다 쓰면 다시 묻는다. 그 사이에 앱이 바뀐 것을 적으면 앱이 먼저 다시 그리게 한다.
        let policy: TimelineReloadPolicy = moments.isEmpty ? .after(now.addingTimeInterval(3600)) : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }
}

// MARK: - 보여 줄 것

/// 한 장에 크게 서는 것. 따로 세는 타이머가 있으면 그게, 없으면 타임라인의 지금 일정이.
private struct Focus {
    let title: String
    let iconName: String
    let tint: Color
    let start: Date
    let end: Date?
    /// 멈춰 있는 타이머의 남은 시간.
    let paused: TimeInterval?

    init?(_ entry: TimerEntry) {
        let snap = entry.snapshot
        if let d = snap.direct {
            title = d.title
            iconName = d.iconName
            tint = TimerWidgetSnapshot.color(d.colorHex)
            if let end = d.end {
                guard end > entry.date else { return nil }
                self.end = end
                start = end.addingTimeInterval(-d.planned)
                paused = nil
            } else {
                end = nil
                start = entry.date
                paused = d.pausedRemaining
            }
            return
        }
        guard let item = snap.current(at: entry.date) else { return nil }
        title = item.title
        iconName = item.iconName
        tint = TimerWidgetSnapshot.color(item.colorHex)
        start = item.start
        end = item.end
        paused = nil
    }
}

// MARK: - 위젯

struct TimerWidgetView: View {
    let entry: TimerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 16) {
                    main
                        .frame(maxWidth: .infinity, alignment: .leading)
                    upcoming
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                main
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    }

    @ViewBuilder
    private var main: some View {
        if let focus = Focus(entry) {
            VStack(alignment: .leading, spacing: 6) {
                Label(focus.title, systemImage: focus.iconName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(focus.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let end = focus.end {
                    // 남은 시간 — 시스템이 센다. 앱이 꺼져 있어도 흐른다.
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(focus.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ProgressView(timerInterval: focus.start...end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(focus.tint)
                    Text("\(end.formatted(date: .omitted, time: .shortened))에 끝")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let paused = focus.paused {
                    Text(Duration.seconds(max(0, paused)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(focus.tint)
                    Label("멈춤", systemImage: "pause.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            idle
        }
    }

    /// 지금은 비어 있을 때 — 다음이 언제인지.
    private var idle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("지금은 일정이 없습니다", systemImage: "cup.and.saucer")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let next = entry.snapshot.upcoming(after: entry.date, limit: 1).first {
                Text("다음")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(next.title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(TimerWidgetSnapshot.color(next.colorHex))
                    .lineLimit(1)
                Text(next.start, style: .time)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 중간 크기의 오른쪽 — 그 뒤에 올 것 셋.
    private var upcoming: some View {
        let next = entry.snapshot.upcoming(after: entry.date, limit: 3)
        return VStack(alignment: .leading, spacing: 6) {
            Text("다음")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            if next.isEmpty {
                Text("남은 일정이 없습니다")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(next, id: \.self) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(TimerWidgetSnapshot.color(item.colorHex))
                            .frame(width: 7, height: 7)
                        Text(item.start, style: .time)
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.body)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TimerWidgetSnapshot.widgetKind, provider: TimerProvider()) { entry in
            TimerWidgetView(entry: entry)
        }
        .configurationDisplayName("지금 타이머")
        .description("지금 하고 있는 일정과 남은 시간을 타임라인 그대로 보여 줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerWidget()
    }
}
