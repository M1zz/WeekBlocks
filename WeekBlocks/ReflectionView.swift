import SwiftUI
import SwiftData

/// 달성·부분·건너뜀·미회고의 수. 주간 회고와 일간 회고가 같은 셈을 쓴다.
struct ReflectionStats {
    var done = 0
    var partial = 0
    var skipped = 0
    var pending = 0

    init(_ blocks: [PlanBlock]) {
        for b in blocks {
            switch b.reviewStatus {
            case .done: done += 1
            case .partial: partial += 1
            case .skipped: skipped += 1
            case nil: pending += 1
            }
        }
    }

    var total: Int { done + partial + skipped + pending }

    /// 넷 중 하나라도 바뀌면 달라지는 값 — 숫자가 굴러가는 결을 거는 데 쓴다.
    var key: Int { done + partial * 100 + skipped * 10_000 + pending * 1_000_000 }
}

struct ReflectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let weekStart: Date

    @Query private var allBlocksRaw: [PlanBlock]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var allBlocks: [PlanBlock] { allBlocksRaw.filter(TodoSharing.isVisible) }
    private var weekBlocks: [PlanBlock] {
        allBlocks
            .filter { Calendar.current.isDate($0.weekStartDate, inSameDayAs: weekStart) }
            .sorted { ($0.day.rawValue, $0.sortHour) < ($1.day.rawValue, $1.sortHour) }
    }

    private func blocks(on day: DayOfWeek) -> [PlanBlock] {
        weekBlocks.filter { $0.day == day }
    }

    /// 계획이 하나라도 있는 요일만. 빈 요일까지 머리를 세우면 돌아볼 것이 없는 줄이 끼어든다.
    private var daysWithBlocks: [DayOfWeek] {
        DayOfWeek.allCases.filter { day in weekBlocks.contains { $0.day == day } }
    }

    var body: some View {
        let stats = ReflectionStats(weekBlocks)

        VStack(spacing: 0) {
            header(stats)

            Divider()

            if weekBlocks.isEmpty {
                ContentUnavailableView(
                    "이번 주에는 계획된 블록이 없습니다",
                    systemImage: "tray",
                    description: Text("주간 계획을 먼저 채운 뒤 다시 확인하세요.")
                )
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            } else {
                ScrollView {
                    // 주간 회고는 **일간 회고들을 모은 것**이다 — 요일마다 끊어 그날의 몫을 따로 센다.
                    // 일간 화면에서 찍은 표시가 여기 그 요일 아래에 그대로 서 있다 (→ DayReflectionPanel).
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(daysWithBlocks, id: \.self) { day in
                            Section {
                                ForEach(blocks(on: day)) { block in
                                    ReflectionRow(block: block, showsDay: false) {
                                        try? context.save()
                                    }
                                    Divider()
                                }
                            } header: {
                                dayHeader(day)
                            }
                        }
                    }
                    .animation(Motion.row, value: weekBlocks.map(\.dragToken))
                }
                .transition(.opacity)
            }

            Divider()

            HStack {
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private func header(_ stats: ReflectionStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("주간 회고")
                .font(.title3.weight(.medium))

            HStack(spacing: 10) {
                ReflectionStatTile(label: "달성", value: stats.done, color: .green)
                ReflectionStatTile(label: "부분", value: stats.partial, color: .yellow)
                ReflectionStatTile(label: "건너뜀", value: stats.skipped, color: .red)
                ReflectionStatTile(label: "미회고", value: stats.pending, color: .secondary)
            }
            // 한 줄에 표시를 찍으면 위쪽 숫자 넷이 함께 움직인다.
            // 굴러가야 방금 누른 것이 어느 칸에 닿았는지가 보인다.
            .animation(Motion.number, value: stats.key)
        }
        .padding(20)
    }

    /// 요일 머리. 그날 계획 중 몇 개를 해냈는지를 옆에 적는다.
    private func dayHeader(_ day: DayOfWeek) -> some View {
        let stats = ReflectionStats(blocks(on: day))
        return HStack(spacing: 8) {
            Text(day.longLabel)
                .font(.subheadline.weight(.semibold))
            Text(verbatim: "\(stats.done)/\(stats.total)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(stats.done == stats.total ? Color.green : .secondary)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.bar)
        .animation(Motion.number, value: stats.key)
    }
}

/// **그날의 회고** — 주간 회고를 하루치로 떼어 일간 옆에 둔다.
///
/// 일간에 할 일 목록을 붙여 끌어다 놓게 했더니 주간이 하는 일(요일에 배치하기)과 겹쳤다.
/// 하루를 크게 펴 보는 까닭은 **그 하루를 돌아보기 위해서**다 — 계획해 둔 블록마다 했는지를
/// 찍고 한 줄을 남긴다. 같은 표시(`PlanBlock.reviewStatus`·`reviewNote`)가 주간 회고의
/// 그 요일 아래에 그대로 모인다. 저장하는 자리를 새로 만들지 않았다.
struct DayReflectionPanel: View {
    @Environment(\.modelContext) private var context

    let day: DayOfWeek
    let date: Date
    /// 그날의 계획 블록.
    let blocks: [PlanBlock]
    var onOpenWeekly: () -> Void = {}

    /// 하루가 흐른 차례대로 — 옆의 하루 시간표를 위에서 아래로 읽는 순서와 같다.
    private var sorted: [PlanBlock] { blocks.sorted { $0.sortHour < $1.sortHour } }

    private var isFuture: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: date) > cal.startOfDay(for: Date())
    }

    var body: some View {
        let stats = ReflectionStats(blocks)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("일간 회고")
                    .font(.headline)
                Spacer()
                Button(action: onOpenWeekly) {
                    Label("주간 회고 열기", systemImage: "checklist")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 6) {
                ReflectionStatTile(label: "달성", value: stats.done, color: .green, compact: true)
                ReflectionStatTile(label: "부분", value: stats.partial, color: .yellow, compact: true)
                ReflectionStatTile(label: "건너뜀", value: stats.skipped, color: .red, compact: true)
                ReflectionStatTile(label: "미회고", value: stats.pending, color: .secondary, compact: true)
            }
            .animation(Motion.number, value: stats.key)

            // 오지 않은 날도 막지는 않는다(미리 건너뛸 줄 아는 날도 있다). 다만 지금 찍는 게
            // 회고가 아니라는 것은 말해 둔다.
            if isFuture {
                Text("아직 오지 않은 날입니다. 끝낸 뒤에 돌아봅니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sorted.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("이 날은 계획한 블록이 없습니다")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    ForEach(sorted) { block in
                        ReflectionRow(block: block, showsDay: false, compact: true) {
                            try? context.save()
                        }
                        if block.persistentModelID != sorted.last?.persistentModelID {
                            Divider()
                        }
                    }
                }
                .animation(Motion.row, value: sorted.map(\.dragToken))
            }
        }
    }
}

struct ReflectionStatTile: View {
    let label: LocalizedStringKey
    let value: Int
    let color: Color
    /// 일간 옆 반쪽 폭에 들어갈 작은 칸.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(compact ? .headline : .title3.weight(.medium))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 5 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(compact ? Color.primary.opacity(0.04) : Color(nsColor: .controlBackgroundColor),
                    in: .soft(Corner.card))
    }
}

struct ReflectionRow: View {
    @Bindable var block: PlanBlock
    /// 줄 앞에 요일을 적는가. 요일마다 묶어 보여 줄 때(주간 회고의 요일 아래, 일간)는 적지 않는다.
    var showsDay = true
    /// 일간 옆 반쪽 폭에 맞춘 촘촘한 줄.
    var compact = false
    let onChange: () -> Void

    @State private var hovering = false

    /// 다 한 것으로 보는가. 줄을 흐리고 제목에 줄을 긋는 기준이다.
    private var isDone: Bool { block.reviewStatus == .done }

    /// 기준·회고 칸이 제목 글줄에 맞춰 들어가는 폭 (동그라미 + 요일).
    private var detailIndent: CGFloat { showsDay ? 52 : 26 }

    /// 시각이 정해진 블록은 시각을, 아니면 시간대를. 하루 시간표 옆에서는 몇 시였는지가 먼저 읽혀야 한다.
    private var whenLabel: String {
        block.startHour >= 0 ? formatHour(block.startHour) : block.timeBand.shortLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // **할 일 목록과 같은 자리, 같은 손짓** — 왼쪽 동그라미를 눌러 끝낸다
                // (→ BacklogView의 '요일에 올린 일'). 세 갈래 상태는 이 동그라미의
                // 모양으로 드러나므로, 눈으로 읽는 것과 손으로 누르는 것이 한 자리에 있다.
                checkButton

                if showsDay {
                    Text(block.day.shortLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(compact ? .callout.weight(.medium) : .body.weight(.medium))
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    Text("\(whenLabel) · \(String(format: "%.1fh", block.durationHours))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 부분·건너뜀은 자주 쓰는 손짓이 아니다. 늘 세워 두면 '끝냄' 하나를
                // 누르러 온 사람이 셋 중에 고르는 일이 되므로, 가리키기 전에는 숨긴다.
                // (마우스를 안 쓰는 사람을 위해 줄 전체에 같은 메뉴를 우클릭으로도 단다.)
                stateMenu
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.8)
            }

            if !block.successCriteria.isEmpty {
                Text("기준: \(block.successCriteria)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, detailIndent)
            }

            if block.reviewStatus != nil {
                TextField(
                    "한 줄 회고 — 무엇이 잘 됐고 무엇이 안 됐는지",
                    text: Binding(
                        get: { block.reviewNote ?? "" },
                        set: { block.reviewNote = $0.isEmpty ? nil : $0; onChange() }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .padding(.leading, detailIndent)
                .transition(.disclose)
            }
        }
        .padding(.horizontal, compact ? 4 : 20)
        .padding(.vertical, compact ? 9 : 14)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // 표시를 찍으면 회고 칸이 아래로 열리고, 제목에 줄이 그어진다. 한 결로 묶는다.
        .animation(Motion.row, value: block.reviewStatus)
        .animation(Motion.hover, value: hovering)
        .contextMenu { stateButtons }
    }

    /// 누르면 끝낸 것이 되고, 다시 누르면 도로 안 본 것이 된다.
    /// 부분·건너뜀이 찍혀 있을 때 누르면 그것도 풀린다 — 체크박스는 늘 '지금 상태를 끈다'.
    private var checkButton: some View {
        Button {
            withAnimation(Motion.row) {
                block.reviewStatus = block.reviewStatus == nil ? .done : nil
            }
            onChange()
        } label: {
            Image(systemName: block.reviewStatus?.systemImage ?? "circle")
                .font(.system(size: 16))
                .foregroundStyle(tint(for: block.reviewStatus))
        }
        .buttonStyle(.plain)
        .help(block.reviewStatus == nil ? "끝냈다고 표시한다" : "표시를 지운다 (적어 둔 회고는 그대로 남습니다)")
    }

    private var stateMenu: some View {
        Menu {
            stateButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("부분 달성·건너뜀으로 표시")
    }

    @ViewBuilder
    private var stateButtons: some View {
        ForEach(ReviewStatus.allCases) { status in
            Button {
                withAnimation(Motion.row) {
                    block.reviewStatus = block.reviewStatus == status ? nil : status
                }
                onChange()
            } label: {
                Label(status.label, systemImage: block.reviewStatus == status
                      ? "checkmark" : status.systemImage)
            }
        }
        if block.reviewStatus != nil {
            Divider()
            // 지우는 것은 **표시뿐**이다. 적어 둔 한 줄 회고는 그대로 둔다 —
            // 잘못 눌러서 쓴 글이 날아가면 다시는 안 적는다.
            Button("표시 지우기") {
                withAnimation(Motion.row) { block.reviewStatus = nil }
                onChange()
            }
        }
    }

    private func tint(for status: ReviewStatus?) -> Color {
        switch status {
        case .done: return .green
        case .partial: return .yellow
        case .skipped: return .red
        case nil: return .secondary.opacity(0.5)
        }
    }
}
