import SwiftUI

// MARK: - 스냅숏 생성 (소유자 데이터 → 공유용 값 타입)

/// 현재 루틴·계획 블록을 공유용 주간 스냅숏으로 변환한다.
/// 소유자 쪽의 실제 TimelineLayout 결과를 그대로 담아 참가자가 동일하게 그린다.
enum ScheduleSnapshotBuilder {
    /// 계획이 있는 모든 주(+현재 보고 있는 주)의 스냅숏.
    static func snapshots(routines: [Routine], allBlocks: [PlanBlock], currentWeek: Date) -> [SharedScheduleSnapshot] {
        let cal = Calendar(identifier: .iso8601)
        var weeks: [Date] = []
        for b in allBlocks where !weeks.contains(where: { cal.isDate($0, inSameDayAs: b.weekStartDate) }) {
            weeks.append(b.weekStartDate)
        }
        if !weeks.contains(where: { cal.isDate($0, inSameDayAs: currentWeek) }) { weeks.append(currentWeek) }
        return weeks.sorted().map { snapshot(routines: routines, allBlocks: allBlocks, week: $0) }
    }

    static func snapshot(routines: [Routine], allBlocks: [PlanBlock], week: Date) -> SharedScheduleSnapshot {
        let cal = Calendar(identifier: .iso8601)
        let weekBlocks = allBlocks.filter { cal.isDate($0.weekStartDate, inSameDayAs: week) }
        var segs: [SharedScheduleSnapshot.Seg] = []
        let quota = routines.filter { $0.kind == .quota }

        for day in DayOfWeek.allCases {
            let fixed = routines
                .filter { $0.kind == .fixed && $0.selectedDays.contains(day) }
                .sorted { $0.startHour < $1.startHour }
            let dayBlocks = weekBlocks.filter { $0.day == day }
            let computed = TimelineLayout.segments(routines: fixed, blocks: dayBlocks, quota: quota)
            for seg in computed where !seg.isGhost {
                segs.append(.init(
                    day: day.rawValue,
                    start: seg.start,
                    end: seg.end,
                    title: seg.title,
                    color: colorToken(for: seg, fixed: fixed, quota: quota),
                    isRoutine: seg.isRoutine,
                    isFlexible: seg.isFlexible,
                    isNested: seg.isNested
                ))
            }
        }

        let rinfo = routines
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { SharedScheduleSnapshot.RoutineInfo(name: $0.name, color: $0.colorName, kind: $0.kindRaw, scheduleDesc: $0.scheduleDescription) }

        return SharedScheduleSnapshot(
            ownerName: NSFullUserName(),
            weekStartEpoch: week.timeIntervalSince1970,
            generatedAtEpoch: Date().timeIntervalSince1970,
            segments: segs,
            routines: rinfo
        )
    }

    /// 루틴·블록이 바뀌면 자동 재발행하도록 감지하는 시그니처.
    static func signature(routines: [Routine], allBlocks: [PlanBlock]) -> String {
        let r = routines.map { "\($0.name)|\($0.kindRaw)|\($0.dayMask)|\($0.startHour)|\($0.durationHours)|\($0.weeklyHours)|\($0.sessionsPerDay)|\($0.colorName)" }.joined(separator: ";")
        let b = allBlocks.map { "\($0.title)|\($0.dayRaw)|\(Int($0.weekStartDate.timeIntervalSince1970))|\($0.startHour)|\($0.durationHours)|\($0.timeBandRaw)|\($0.withinRoutine)|\($0.concreteVerified)" }.joined(separator: ";")
        return "\(r)#\(b)"
    }

    private static func colorToken(for seg: TimeSegment, fixed: [Routine], quota: [Routine]) -> String {
        switch seg.source {
        case .fixedRoutine(let name):
            return fixed.first { $0.name == name }?.colorName ?? "blue"
        case .quotaSession(let name, _):
            return quota.first { $0.name == name }?.colorName ?? "green"
        case .planBlock(let blk):
            if seg.isNested { return "accent" }
            return blk.concreteVerified ? "accent" : "orange"
        case .none:
            return "accent"
        }
    }
}

// MARK: - 색 토큰 → Color

func sharedTokenColor(_ token: String) -> Color {
    switch token {
    case "accent": return .accentColor
    case "orange": return .orange
    default:       return paletteColor(token)
    }
}

// MARK: - 메인 화면: 공유받은 일정 (있을 때만)

/// 다른 사람에게 공유받은 일정을 보여준다. 받은 일정이 없으면 아무것도 그리지 않는다.
/// (내 일정 공유 컨트롤은 설정 화면의 [[ScheduleShareSettingsSection]]에 있다.)
struct ReceivedSchedulesSection: View {
    @State private var store = ScheduleShareStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("공유받은 일정", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isBusy)
            }

            ForEach(store.received) { schedule in
                ReceivedScheduleCard(schedule: schedule) {
                    Task { await store.leave(schedule) }
                }
            }
        }
    }
}

// MARK: - 설정: 내 일정 공유 컨트롤

/// 설정 화면의 '일정 공유' 섹션 — 내 주간 일정을 읽기 전용 링크로 공유/중지한다.
struct ScheduleShareSettingsSection: View {
    /// 공유 시작·업데이트 시점의 최신 스냅숏을 만들어주는 클로저.
    let snapshotsProvider: () -> [SharedScheduleSnapshot]

    @State private var store = ScheduleShareStore.shared
    @State private var showingShareNotice = false

    var body: some View {
        Section {
            if !store.iCloudAvailable {
                Text("iCloud에 로그인하면 내 일정을 공유할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.isSharing {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("공유 중 · \(store.sharedWeekCount)개 주 (보기 전용)")
                    Spacer()
                }
                if let url = store.shareURL {
                    ShareLink(item: url) {
                        Label("초대 링크 보내기", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    Task { await store.publish(snapshotsProvider()) }
                } label: {
                    Label("지금 일정으로 업데이트", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isBusy)
                Button(role: .destructive) {
                    Task { await store.stopSharing() }
                } label: {
                    Label("공유 중지", systemImage: "person.crop.circle.badge.xmark")
                }
            } else {
                Button {
                    showingShareNotice = true
                } label: {
                    Label("내 일정 공유 시작", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(store.isBusy)
                .alert("내 일정 공유", isPresented: $showingShareNotice) {
                    Button("공유 시작") {
                        Task { await store.startSharing(publishing: snapshotsProvider()) }
                    }
                    Button("취소", role: .cancel) { }
                } message: {
                    Text("계획이 있는 모든 주의 일정을 링크로 공유합니다.\n링크를 받은 사람은 내 일정을 '보기 전용'으로 주를 넘겨가며 볼 수 있습니다.")
                }
            }
        } header: {
            Text("일정 공유")
        } footer: {
            if let message = store.errorMessage {
                Text(message).foregroundStyle(.orange)
            } else {
                Text("링크를 받은 사람은 내 주간 일정을 '보기 전용'으로만 봅니다. 일정이 바뀌면 자동으로 갱신됩니다.")
            }
        }
        .task { await store.refresh() }
    }
}

// MARK: - 공유받은 한 사람의 카드 (주 넘기기)

private struct ReceivedScheduleCard: View {
    let schedule: ReceivedSchedule
    let onLeave: () -> Void

    @State private var index: Int = 0

    var body: some View {
        let weeks = schedule.weeks
        let safeIndex = min(max(index, 0), max(0, weeks.count - 1))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text(schedule.ownerName)
                    .font(.callout.weight(.semibold))
                Text("보기 전용")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    index = safeIndex - 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(safeIndex <= 0)

                Text("\(safeIndex + 1) / \(weeks.count)주")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 52)

                Button {
                    index = safeIndex + 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(safeIndex >= weeks.count - 1)

                Button(action: onLeave) {
                    Label("나가기", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
            }

            if weeks.indices.contains(safeIndex) {
                SharedScheduleWeekView(snapshot: weeks[safeIndex])
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .onAppear { index = initialIndex(weeks) }
    }

    /// 처음 열 때 오늘이 포함된 주(없으면 가장 가까운 주)를 보여준다.
    private func initialIndex(_ weeks: [SharedScheduleSnapshot]) -> Int {
        guard !weeks.isEmpty else { return 0 }
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        if let i = weeks.firstIndex(where: { cal.isDate($0.weekStart, equalTo: today, toGranularity: .weekOfYear) }) {
            return i
        }
        var best = weeks.count - 1
        var bestDiff = Double.greatestFiniteMagnitude
        for (i, w) in weeks.enumerated() {
            let d = abs(w.weekStartEpoch - today.timeIntervalSince1970)
            if d < bestDiff { bestDiff = d; best = i }
        }
        return best
    }
}

// MARK: - 한 주의 읽기 전용 주간 뷰

struct SharedScheduleWeekView: View {
    let snapshot: SharedScheduleSnapshot

    private var segmentsByDay: [Int: [SharedScheduleSnapshot.Seg]] {
        Dictionary(grouping: snapshot.segments, by: { $0.day })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(weekRangeString)
                .font(.subheadline.weight(.medium))

            if !snapshot.routines.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 6)], alignment: .leading, spacing: 4) {
                    ForEach(snapshot.routines) { r in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(sharedTokenColor(r.color).opacity(0.85))
                                .frame(width: 9, height: 9)
                            Text(r.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(r.scheduleDesc)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            SharedHourAxis()

            VStack(spacing: 4) {
                ForEach(DayOfWeek.allCases) { day in
                    SharedDayRow(
                        day: day,
                        date: dayDate(day),
                        segments: (segmentsByDay[day.rawValue] ?? []).sorted { $0.start < $1.start }
                    )
                }
            }
        }
    }

    private func dayDate(_ day: DayOfWeek) -> Date {
        Calendar(identifier: .iso8601).date(byAdding: .day, value: day.rawValue, to: snapshot.weekStart) ?? snapshot.weekStart
    }

    private var weekRangeString: String {
        let start = snapshot.weekStart
        let end = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: start) ?? start
        let f = DateFormatter()
        f.dateFormat = "M월 d일"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}

/// 참가자용 하루 행 — 드래그·편집 없이 세그먼트만 그린다.
private struct SharedDayRow: View {
    let day: DayOfWeek
    let date: Date
    let segments: [SharedScheduleSnapshot.Seg]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(day.shortLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text(dayNumber)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
            }
            .frame(width: 26)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))

                    ForEach(1..<24) { h in
                        let isMajor = (h % 3 == 0)
                        Rectangle()
                            .fill(Color.secondary.opacity(isMajor ? 0.18 : 0.07))
                            .frame(width: isMajor ? 1 : 0.5)
                            .offset(x: CGFloat(h) / 24 * w)
                    }

                    ForEach(segments) { seg in
                        let x = CGFloat(seg.start) / 24 * w
                        let segW = max(1, CGFloat(seg.end - seg.start) / 24 * w)
                        segmentView(seg, width: segW)
                            .offset(x: x)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private func segmentView(_ seg: SharedScheduleSnapshot.Seg, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        let color = sharedTokenColor(seg.color)
        ZStack {
            if seg.isFlexible {
                shape.fill(color.opacity(0.32))
                shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else if seg.isNested {
                shape.fill(color.opacity(0.95))
                shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            } else {
                shape.fill(color.opacity(0.85))
            }
        }
        .padding(.vertical, seg.isNested ? 5 : 0)
        .frame(width: width)
        .overlay(alignment: .leading) {
            if width > 18 {
                Text(seg.title)
                    .font(.system(size: 9, weight: seg.isNested ? .semibold : .medium))
                    .foregroundStyle(seg.isFlexible ? color : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
                    .frame(width: width, alignment: .leading)
            }
        }
        .help("\(seg.title) · \(formatHour(seg.start))–\(formatHour(seg.end))")
    }

    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }
}

/// 참가자용 시간 축 (오른쪽 여유 칸 없이 라벨 폭만 맞춘다).
private struct SharedHourAxis: View {
    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 26)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ForEach([0, 3, 6, 9, 12, 15, 18, 21, 24], id: \.self) { h in
                        Text("\(h)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .offset(x: min(w - 12, CGFloat(h) / 24 * w))
                    }
                }
            }
            .frame(height: 12)
        }
    }
}
