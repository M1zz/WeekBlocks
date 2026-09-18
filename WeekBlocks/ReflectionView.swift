import SwiftUI
import SwiftData
import AppKit

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

    /// 이번 주를 돌아보는가, 지난 주들을 겹쳐 보는가 (→ ReflectionTrendsView, Pro).
    enum Tab: Hashable { case week, trends }
    @State private var tab: Tab = .week
    @State private var purchases = PurchaseManager.shared
    @State private var showingPaywall = false
    /// 방금 복사했다. 단추 글씨가 잠깐 바뀐다 — 조용히 끝나면 눌린 줄도 모른다.
    @State private var copied = false

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

            if tab == .trends, purchases.offersPro {
                ReflectionTrendsView(weekStart: weekStart, allBlocks: allBlocks)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
            } else if weekBlocks.isEmpty {
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
        .sheet(isPresented: $showingPaywall) {
            PaywallView(reason: WeekBlocksSpec.Gate.export)
        }
    }

    private func header(_ stats: ReflectionStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("주간 회고")
                    .font(.title3.weight(.medium))
                Spacer()
                // 추세는 Pro지만 탭은 누구에게나 선다 — 안 산 사람은 들어가서 흐린 제 기록 위의 문을 본다.
                // 팔기 전(출시 빌드)에는 탭 자체가 없다 (→ PurchaseManager.offersPro).
                if purchases.offersPro {
                    Picker("", selection: $tab.animation(Motion.screen)) {
                        Text("이번 주").tag(Tab.week)
                        Text("추세").tag(Tab.trends)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    // 밖으로 내보내는 일은 Pro. 적어 둔 것을 보는 데는 값을 받지 않는다.
                    Button {
                        if purchases.isPro { copyWeek() } else { showingPaywall = true }
                    } label: {
                        Label(copied ? "복사했습니다" : "내보내기",
                              systemImage: copied ? "checkmark" : (purchases.isPro ? "doc.on.doc" : "sparkles"))
                            .font(.system(size: 12, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .disabled(weekBlocks.isEmpty)
                    .help(purchases.isPro ? "이번 주 회고를 글로 복사합니다" : "Pro 기능입니다")
                }
            }

            if tab == .week || !purchases.offersPro {
                HStack(spacing: 10) {
                    ReflectionStatTile(label: "달성", value: stats.done, color: .green)
                    ReflectionStatTile(label: "부분", value: stats.partial, color: .yellow)
                    ReflectionStatTile(label: "건너뜀", value: stats.skipped, color: .red)
                    ReflectionStatTile(label: "미회고", value: stats.pending, color: .secondary)
                }
                // 한 줄에 표시를 찍으면 위쪽 숫자 넷이 함께 움직인다.
                // 굴러가야 방금 누른 것이 어느 칸에 닿았는지가 보인다.
                .animation(Motion.number, value: stats.key)
                .transition(.disclose)
            }
        }
        .padding(20)
    }

    /// **이번 주 회고를 글로 복사한다** (Pro). 붙여넣을 곳은 사람마다 다르다 — 노션, 메모,
    /// 주간 보고. 그래서 앱이 고른 서식이 아니라 어디에나 붙는 평범한 글로 낸다.
    private func copyWeek() {
        var lines: [String] = []
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let end = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        lines.append("# \(f.string(from: weekStart)) – \(f.string(from: end))")
        let stats = ReflectionStats(weekBlocks)
        lines.append(String(localized: "달성 \(stats.done) · 부분 \(stats.partial) · 건너뜀 \(stats.skipped) · 미회고 \(stats.pending)"))
        for day in daysWithBlocks {
            lines.append("")
            lines.append("## \(day.longLabel)")
            for block in blocks(on: day) {
                let mark: String
                switch block.reviewStatus {
                case .done: mark = "[x]"
                case .partial: mark = "[~]"
                case .skipped: mark = "[-]"
                case nil: mark = "[ ]"
                }
                let when = block.startHour >= 0 ? formatHour(block.startHour) : block.timeBand.shortLabel
                lines.append("- \(mark) \(when) \(block.title) (\(shortHours(block.durationHours)))")
                if let note = block.reviewNote, !note.isEmpty { lines.append("      \(note)") }
                if let next = block.nextAction, !next.isEmpty {
                    lines.append("      → \(next)")
                }
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        Haptic.tick()
        withAnimation(Motion.squish) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.squish) { copied = false }
        }
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
/// 하루를 크게 펴 보는 까닭 하나는 **그 하루를 돌아보기 위해서**다 — 계획해 둔 블록마다 했는지를
/// 찍고 한 줄을 남긴다. 같은 표시(`PlanBlock.reviewStatus`·`reviewNote`)가 주간 회고의
/// 그 요일 아래에 그대로 모인다. 저장하는 자리를 새로 만들지 않았다.
struct DayReflectionPanel: View {
    @Environment(\.modelContext) private var context

    let day: DayOfWeek
    let date: Date
    /// 그날의 계획 블록.
    let blocks: [PlanBlock]
    var onOpenWeekly: () -> Void = {}
    /// 할 일을 받을 수 있는가. 고정 루틴이 없으면 계획할 수 없다 (→ 하루 시간표와 같은 조건).
    var canPlan: Bool = true
    /// 할 일 카드를 떨어뜨렸다. 그날에 올린다 — 시각은 정하지 않는다(드래그 토큰).
    var onDropBacklog: (String) -> Void = { _ in }

    @State private var dropTargeted = false
    /// 일간 시간표에서 알약을 끌어 이 위에 올려 둔 중인가 (→ DayDragZones).
    var externallyTargeted: Bool = false
    private var targeted: Bool { dropTargeted || externallyTargeted }

    /// 하루가 흐른 차례대로 — 옆의 하루 시간표를 위에서 아래로 읽는 순서와 같다.
    private var sorted: [PlanBlock] { blocks.sorted { $0.sortHour < $1.sortHour } }

    private var isFuture: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: date) > cal.startOfDay(for: Date())
    }

    /// 판의 이름. '일간 회고'는 무엇을 하는 칸인지 한 번에 안 읽혔다 — 여기 서는 것은
    /// 그날 **하기로 한 계획**이고, 한 것을 체크하는 자리다. 아래의 '할 일'(아직 날을 안 정한 것)과
    /// 헷갈리지 않게 '계획'이라 부른다.
    private var panelTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "오늘의 계획") }
        if cal.isDateInTomorrow(date) { return String(localized: "내일의 계획") }
        if cal.isDateInYesterday(date) { return String(localized: "어제의 계획") }
        return String(localized: "\(day.longLabel)의 계획")
    }

    var body: some View {
        let stats = ReflectionStats(blocks)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(panelTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                // 달성·부분·건너뜀·남은 것을 **제목 옆 작은 뱃지**로. 네 칸짜리 숫자판은
                // 오늘 할 일보다 먼저 눈에 들어올 만큼 컸다. 셀 것이 없는 뱃지는 흐리게 둔다.
                HStack(spacing: 4) {
                    StatBadge(symbol: "checkmark.circle.fill", value: stats.done, color: .green, label: "달성")
                    StatBadge(symbol: "circle.lefthalf.filled", value: stats.partial, color: .yellow, label: "부분")
                    StatBadge(symbol: "xmark.circle.fill", value: stats.skipped, color: .red, label: "건너뜀")
                    StatBadge(symbol: "circle.dashed", value: stats.pending, color: .secondary, label: "미회고")
                }
                .animation(Motion.number, value: stats.key)
                Spacer(minLength: 4)
                Button(action: onOpenWeekly) {
                    Label("주간 회고 열기", systemImage: "checklist")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

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
                    if canPlan {
                        Text("아래 할 일을 여기로 끌어다 놓으면 이 날에 올라갑니다.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
        .contentShape(Rectangle())
        // 받을 준비가 되면 판이 살짝 부푼다 — 여기 놓으면 된다는 것이 모양으로 읽힌다.
        .scaleEffect(targeted ? 1.008 : 1)
        .animation(Motion.squish, value: targeted)
        // **아래 할 일을 여기 떨어뜨리면 그날의 일이 된다.** 회고할 줄이 하나 늘어나는 것이다.
        // 몇 시에 할지까지 정하려면 왼쪽 하루 위에 떨어뜨린다.
        .dropDestination(for: String.self) { items, _ in
            dropTargeted = false
            guard canPlan, let token = items.first else { return false }
            onDropBacklog(token)
            return true
        } isTargeted: { targeted in
            withAnimation(Motion.target) { dropTargeted = targeted && canPlan }
        }
        .overlay {
            RoundedRectangle.soft(Corner.card)
                .strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0)
                .padding(-6)
                .allowsHitTesting(false)
        }
    }
}

/// 제목 옆에 붙는 작은 수 뱃지 — 기호 하나와 숫자 하나.
struct StatBadge: View {
    let symbol: String
    let value: Int
    let color: Color
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .symbolEffect(.bounce, value: value)
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .opacity(value == 0 ? 0.45 : 1)
        .help(Text(label))
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
        // 칸마다 제 색으로 옅게 물든다 — 네 칸이 회색 표가 아니라 색 알약으로 읽힌다.
        .background(color.opacity(0.1), in: .soft(Corner.panel))
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
    private var detailIndent: CGFloat { (showsDay ? 28 : 0) + (compact ? 30 : 32) }

    /// 시각이 정해진 블록은 시각을, 아니면 시간대를. 하루 시간표 옆에서는 몇 시였는지가 먼저 읽혀야 한다.
    private var whenLabel: String {
        block.startHour >= 0 ? formatHour(block.startHour) : block.timeBand.shortLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .center, spacing: 10) {
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
                        .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
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

            // 멈출 때 남겨 둔 한 줄 — 돌아왔을 때 여기서부터 (→ PlanBlock.nextAction).
            if let next = block.nextAction, !next.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(next)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, detailIndent)
                .transition(.disclose)
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
    /// 일간 알약 옆의 동그라미와 같은 모양·같은 손맛이다 (→ SoftCheck).
    private var checkButton: some View {
        SoftCheck(status: block.reviewStatus, color: .green, size: compact ? 20 : 22) {
            block.reviewStatus = block.reviewStatus == nil ? .done : nil
            onChange()
        }
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
                Haptic.tick()
                withAnimation(Motion.squish) {
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
}
