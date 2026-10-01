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

    /// 보고 있는 주 — 그 주 월요일 (→ WeekStartSetting). 일요일 시작이면 맨 앞 일요일은 앞 ISO 주에서 온다.
    let weekStart: Date
    @AppStorage(WeekStartSetting.key) private var weekStartsOnSunday = false

    /// 이 요일의 기록이 적힌 ISO 주.
    private func storedWeek(for day: DayOfWeek) -> Date {
        DayOfWeek.storedWeek(of: day, shownWeek: weekStart, sundayFirst: weekStartsOnSunday)
    }

    /// 화면에 세우는 요일 차례.
    private var shownDays: [DayOfWeek] { DayOfWeek.displayOrder(sundayFirst: weekStartsOnSunday) }

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

    /// 루틴 이름. 이 이름으로 선 블록은 점검하지 않는다 (→ PlanBlock.isRoutineKind).
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var routinesRaw: [Routine]
    private var routineNames: Set<String> {
        Set(routinesRaw.filter(TodoSharing.isVisible).map(\.name))
    }
    private var weekBlocks: [PlanBlock] {
        allBlocks
            .filter { Calendar.current.isDate($0.weekStartDate, inSameDayAs: storedWeek(for: $0.day)) }
            .sorted { day1, day2 in
                let order = shownDays
                let i = order.firstIndex(of: day1.day) ?? 0, j = order.firstIndex(of: day2.day) ?? 0
                return (i, day1.sortHour) < (j, day2.sortHour)
            }
    }

    private func blocks(on day: DayOfWeek) -> [PlanBlock] {
        weekBlocks.filter { $0.day == day }
    }

    /// 점검해야 하는 줄들. 숫자 넷은 이것만 센다.
    private var reviewableBlocks: [PlanBlock] {
        weekBlocks.filter { $0.isTodo(routineNames) }
    }

    /// **아직 안 찍은 것.** 지나간 날과, 오늘 끝 시각이 지난 것 (→ PlanBlock.isUnreviewedPast).
    private var unreviewed: [PlanBlock] {
        _ = stillGoingRaw
        return weekBlocks.filter { $0.isUnreviewedPast(weekStart: storedWeek(for: $0.day), routineNames: routineNames) }
    }

    /// 계획이 하나라도 있는 요일만. 빈 요일까지 머리를 세우면 돌아볼 것이 없는 줄이 끼어든다.
    private var daysWithBlocks: [DayOfWeek] {
        shownDays.filter { day in weekBlocks.contains { $0.day == day } }
    }

    /// 루틴·배경 줄을 펼쳐 둔 요일. 기본은 접힘 — 했는지 묻지 않는 줄이 찍을 줄 사이에 끼면
    /// 무엇을 돌아봐야 하는지가 묻힌다.
    @State private var expandedRoutineDays: Set<DayOfWeek> = []
    /// '아직 하는 중'이라고 답한 것 (→ StillGoing). 바뀌면 밀린 것을 다시 센다.
    @AppStorage(StillGoing.storageKey) private var stillGoingRaw = ""

    /// 열자마자 내려가 비추는 요일 — 오늘. 오늘 계획이 없으면 오늘 전의 가장 가까운 날.
    /// 이번 주가 아니면(지난 주를 돌아볼 때) 옮기지 않는다.
    private var focusDay: DayOfWeek? {
        guard let today = shownDays.first(where: { Calendar.current.isDateInToday(date(of: $0)) }),
              let i = shownDays.firstIndex(of: today) else { return nil }
        return shownDays[...i].reversed().first { daysWithBlocks.contains($0) }
    }
    /// 방금 내려가 비추는 중인 요일. 테두리가 잠깐 굵어진다.
    @State private var pulsingDay: DayOfWeek?

    /// 그 요일의 날짜.
    private func date(of day: DayOfWeek) -> Date {
        Calendar(identifier: .iso8601).date(byAdding: .day, value: day.rawValue, to: storedWeek(for: day)) ?? weekStart
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let first = shownDays.first ?? .mon, last = shownDays.last ?? .sun
        return "\(f.string(from: date(of: first))) – \(f.string(from: date(of: last)))"
    }

    var body: some View {
        let stats = ReflectionStats(reviewableBlocks)

        VStack(spacing: 0) {
            header(stats)

            Divider()

            if tab == .trends, purchases.offersPro {
                ReflectionTrendsView(weekStart: weekStart, allBlocks: allBlocks,
                                     routineNames: routineNames)
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
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        // **한 주를 한눈에.** 요일마다 몇 개를 해냈는지 막대로 — 누르면 그 요일로 내려간다.
                        weekStrip { day in
                            withAnimation(Motion.screen) { proxy.scrollTo(day, anchor: .top) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                        Divider()

                        ScrollView {
                            // 주간 회고는 **일간 회고들을 모은 것**이다 — 요일마다 끊어 그날의 몫을 따로 센다.
                            // 일간 화면에서 찍은 표시가 여기 그 요일 아래에 그대로 서 있다 (→ DayReflectionPanel).
                            VStack(alignment: .leading, spacing: 14) {
                                // **밀린 것부터.** 주간 회고를 여는 까닭은 대개 안 찍은 것을 찍기
                                // 위해서다. 요일 일곱 개를 훑어 빈 동그라미를 찾게 두지 않는다.
                                if !unreviewed.isEmpty { unreviewedCard }

                                ForEach(daysWithBlocks, id: \.self) { day in
                                    dayCard(day).id(day)
                                }
                            }
                            .padding(20)
                            .animation(Motion.row, value: weekBlocks.map(\.dragToken))
                        }
                    }
                    // **열면 오늘부터.** 월요일부터 훑어 내려가게 두지 않는다 — 대개 돌아보려는 것은 오늘이다.
                    // 한 박자 뒤에 옮긴다. 시트가 뜨는 중에 옮기면 자리를 못 잡는다.
                    .task {
                        guard let day = focusDay else { return }
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation(Motion.screen) { proxy.scrollTo(day, anchor: .top) }
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(Motion.squish) { pulsingDay = day }
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation(Motion.screen) { pulsingDay = nil }
                    }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("주간 회고")
                    .font(.title2.weight(.bold))
                Text(rangeLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                            .font(.body)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.bordered)
                    .disabled(weekBlocks.isEmpty)
                    .help(purchases.isPro ? "이번 주 회고를 글로 복사합니다" : "Pro 기능입니다")
                }
            }

            if tab == .week || !purchases.offersPro {
                summary(stats)
                    .transition(.disclose)
            }
        }
        .padding(20)
    }

    /// 이번 주가 어땠는지 한 줄로 — 큰 달성률, 넷으로 나뉜 막대, 그 아래 네 칸.
    private func summary(_ stats: ReflectionStats) -> some View {
        let rate = stats.total == 0 ? 0 : Int((Double(stats.done) / Double(stats.total) * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(rate)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("달성 · 할 일 \(stats.total)개 중 \(stats.done)개")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            ReviewBar(stats: stats, height: 10)
            HStack(spacing: 10) {
                ReflectionStatTile(label: "달성", value: stats.done, color: .green)
                ReflectionStatTile(label: "부분", value: stats.partial, color: .yellow)
                ReflectionStatTile(label: "건너뜀", value: stats.skipped, color: .red)
                ReflectionStatTile(label: "미회고", value: stats.pending, color: .secondary)
            }
        }
        // 한 줄에 표시를 찍으면 위쪽 숫자가 함께 움직인다.
        // 굴러가야 방금 누른 것이 어느 칸에 닿았는지가 보인다.
        .animation(Motion.number, value: stats.key)
    }

    /// 일곱 요일을 한 줄에. 요일마다 해낸 몫이 막대로 서고, 밀린 것이 있으면 주황 점이 붙는다.
    private func weekStrip(onSelect: @escaping (DayOfWeek) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(shownDays, id: \.self) { day in
                let todos = blocks(on: day).filter { $0.isTodo(routineNames) }
                let st = ReflectionStats(todos)
                let hasBlocks = daysWithBlocks.contains(day)
                let late = unreviewed.contains { $0.day == day }
                let isToday = Calendar.current.isDateInToday(date(of: day))
                Button { onSelect(day) } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(day.shortLabel)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(isToday ? Color.accentColor : .primary)
                            if late {
                                Circle().fill(Color.orange).frame(width: 7, height: 7)
                            }
                        }
                        Text(verbatim: st.total == 0 ? "–" : "\(st.done)/\(st.total)")
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(st.total > 0 && st.done == st.total ? Color.green : .secondary)
                            .contentTransition(.numericText())
                        ReviewBar(stats: st, height: 5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle.soft(Corner.chip)
                        .fill(isToday ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasBlocks)
                .opacity(hasBlocks ? 1 : 0.4)
                .help(late ? String(localized: "아직 안 찍은 것이 있습니다") : "")
            }
        }
        .animation(Motion.number, value: reviewableBlocks.map { $0.reviewStatus?.rawValue ?? "" })
    }

    /// 밀린 것들 — 주황 카드. 같은 줄이 아래 제 요일에도 서 있다. 여기는 처리하는 자리, 아래는 기록이다.
    private var unreviewedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                Text("먼저 찍을 것 \(unreviewed.count)개")
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    Haptic.tick()
                    withAnimation(Motion.row) { for b in unreviewed { b.reviewStatus = .done } }
                    try? context.save()
                } label: {
                    Label("모두 완료", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("시간이 지난 일정을 모두 끝낸 것으로 찍습니다")
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(unreviewed) { block in
                Divider().padding(.leading, 16)
                ReflectionRow(block: block, showsDay: true, isOverdue: true) {
                    try? context.save()
                }
            }
        }
        .background(RoundedRectangle.soft(Corner.card).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle.soft(Corner.card).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        .animation(Motion.number, value: unreviewed.count)
    }

    /// 한 요일 카드. 찍을 줄이 먼저, 루틴·배경 줄은 접어 둔다.
    private func dayCard(_ day: DayOfWeek) -> some View {
        let all = blocks(on: day)
        let todos = all.filter { $0.isTodo(routineNames) }
        let others = all.filter { !$0.isTodo(routineNames) }
        // 루틴은 세지 않는다 — '3/8'의 8에 수면·끼니가 들어가면 달성률이 흐려진다.
        let st = ReflectionStats(todos)
        let expanded = expandedRoutineDays.contains(day)
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let isToday = Calendar.current.isDateInToday(date(of: day))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(day.longLabel)
                    .font(.headline)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Text(f.string(from: date(of: day)))
                    .font(.body)
                    .foregroundStyle(.secondary)
                if isToday {
                    Text("오늘")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Spacer()
                if st.total > 0 {
                    ReviewBar(stats: st, height: 6)
                        .frame(width: 90)
                    Text(verbatim: "\(st.done)/\(st.total)")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(st.done == st.total ? Color.green : .secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if todos.isEmpty {
                Divider().padding(.leading, 16)
                Text("이 날은 찍을 할 일이 없습니다")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            ForEach(todos) { block in
                Divider().padding(.leading, 16)
                ReflectionRow(block: block, showsDay: false,
                              runningUntil: block.inProgressEnd(on: date(of: day)),
                              isOverdue: unreviewed.contains { $0.persistentModelID == block.persistentModelID }) {
                    try? context.save()
                }
            }

            if !others.isEmpty {
                Divider().padding(.leading, 16)
                Button {
                    withAnimation(Motion.disclose) {
                        if expanded { expandedRoutineDays.remove(day) } else { expandedRoutineDays.insert(day) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("루틴·배경 일정 \(others.count)개")
                        Spacer()
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(others) { block in
                        ReflectionRow(block: block, showsDay: false, reviewable: false) {
                            try? context.save()
                        }
                        .opacity(0.75)
                    }
                    .transition(.disclose)
                }
            }
        }
        .background(RoundedRectangle.soft(Corner.card).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle.soft(Corner.card)
            .strokeBorder(isToday || pulsingDay == day ? Color.accentColor.opacity(pulsingDay == day ? 0.9 : 0.45)
                                                       : Color.primary.opacity(0.08),
                          lineWidth: pulsingDay == day ? 3 : (isToday ? 1.5 : 1)))
        .scaleEffect(pulsingDay == day ? 1.01 : 1)
        .animation(Motion.number, value: st.key)
    }

    /// **이번 주 회고를 글로 복사한다** (Pro). 붙여넣을 곳은 사람마다 다르다 — 노션, 메모,
    /// 주간 보고. 그래서 앱이 고른 서식이 아니라 어디에나 붙는 평범한 글로 낸다.
    private func copyWeek() {
        var lines: [String] = []
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let cal = Calendar(identifier: .iso8601)
        let first = shownDays.first ?? .mon, last = shownDays.last ?? .sun
        let start = cal.date(byAdding: .day, value: first.rawValue, to: storedWeek(for: first)) ?? weekStart
        let end = cal.date(byAdding: .day, value: last.rawValue, to: storedWeek(for: last)) ?? weekStart
        lines.append("# \(f.string(from: start)) – \(f.string(from: end))")
        let stats = ReflectionStats(reviewableBlocks)
        lines.append(String(localized: "달성 \(stats.done) · 부분 \(stats.partial) · 건너뜀 \(stats.skipped) · 미회고 \(stats.pending)"))
        for day in daysWithBlocks {
            lines.append("")
            lines.append("## \(day.longLabel)")
            for block in blocks(on: day) {
                let mark: String
                // 루틴은 안 찍는 줄이다. `[ ]`로 내보내면 붙여넣은 글에서 '안 한 일'로 읽힌다.
                if block.isBackground {
                    mark = "[·]"
                } else if block.isRoutineKind(routineNames) {
                    mark = "[↻]"
                } else {
                    switch block.reviewStatus {
                    case .done: mark = "[x]"
                    case .partial: mark = "[~]"
                    case .skipped: mark = "[-]"
                    case nil: mark = "[ ]"
                    }
                }
                lines.append(block.isAllDay
                             ? "- \(mark) \(block.whenLabel) \(block.title)"
                             : "- \(mark) \(block.whenLabel) \(block.title) (\(shortHours(block.durationHours)))")
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
    /// 그 주에 서 있는 루틴들의 이름. 이 이름으로 선 블록은 루틴에서 온 것으로 본다.
    var routineNames: Set<String> = []
    var onOpenWeekly: () -> Void = {}
    /// 할 일을 받을 수 있는가. 고정 루틴이 없으면 계획할 수 없다 (→ 하루 시간표와 같은 조건).
    var canPlan: Bool = true
    /// 할 일 카드를 떨어뜨렸다. 그날에 올린다 — 시각은 정하지 않는다(드래그 토큰).
    var onDropBacklog: (String) -> Void = { _ in }

    @State private var dropTargeted = false
    /// 진행 중을 가르는 시계. 분이 바뀔 때마다 다시 본다 — 시각이 되면 저절로 진행 중으로 넘어간다.
    @State private var now = Date()
    /// '아직 하는 중'이라고 답한 것 (→ StillGoing). 바뀌면 줄을 다시 가른다.
    @AppStorage(StillGoing.storageKey) private var stillGoingRaw = ""
    /// 일간 시간표에서 알약을 끌어 이 위에 올려 둔 중인가 (→ DayDragZones).
    var externallyTargeted: Bool = false
    private var targeted: Bool { dropTargeted || externallyTargeted }

    /// 하루가 흐른 차례대로 — 옆의 하루 시간표를 위에서 아래로 읽는 순서와 같다.
    private var sorted: [PlanBlock] { blocks.sorted { $0.sortHour < $1.sortHour } }

    /// **점검해야 하는 줄들.** 뱃지의 셈도 이것만 본다 —
    /// 루틴이 섞이면 '미회고 5개'가 사실은 아무것도 안 밀린 날일 수 있다.
    private var reviewable: [PlanBlock] { sorted.filter { $0.isTodo(routineNames) } }

    private var isPast: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: date) < cal.startOfDay(for: Date())
    }

    /// 시간이 지났는데 아직 안 찍은 것 — 지난 날 전부와, 오늘 끝 시각이 지난 것 (→ PlanBlock.isUnreviewedPast).
    /// '아직 하는 중'이라고 답한 것은 빠진다.
    private var unreviewed: [PlanBlock] {
        _ = stillGoingRaw
        return reviewable.filter {
            $0.isUnreviewedPast(weekStart: $0.weekStartDate, routineNames: routineNames, now: now)
        }
    }

    /// 지나간 것을 모두 끝낸 것으로.
    private func completeAllPast() {
        Haptic.tick()
        withAnimation(Motion.row) {
            for b in unreviewed { b.reviewStatus = .done }
        }
        try? context.save()
    }

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
        let stats = ReflectionStats(reviewable)
        let running = reviewable.filter { $0.inProgressEnd(on: date, now: now) != nil }.count

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
                    // 진행 중은 미회고에서 떼어 따로 센다 — 아직 끝나지 않은 일을 '안 찍은 것'이라 부르지 않는다.
                    if running > 0 {
                        StatBadge(symbol: "play.circle.fill", value: running, color: .blue, label: "진행 중")
                            .transition(.pop)
                    }
                    StatBadge(symbol: "circle.dashed", value: stats.pending - running, color: .secondary, label: "미회고")
                }
                .animation(Motion.number, value: running)
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

            // **시간이 지났는데 안 찍은 것은 판 위에 세운다.** 뱃지의 숫자 하나로는 밀린 줄 모른다.
            // 한 번에 끝낼 수 있게 '모두 완료'를 붙인다 — 하나씩 누르기엔 지나간 하루가 길다.
            if !unreviewed.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("시간이 지난 것 \(unreviewed.count)개 · 끝냈나요?")
                        .font(.body.weight(.semibold))
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Button {
                        completeAllPast()
                    } label: {
                        Label("모두 완료", systemImage: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .help("시간이 지난 일정을 모두 끝낸 것으로 찍습니다")
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12), in: .soft(Corner.chip))
                .transition(.disclose)
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
                        ReflectionRow(block: block, showsDay: false, compact: true,
                                      reviewable: block.isTodo(routineNames),
                                      runningUntil: block.isTodo(routineNames)
                                          ? block.inProgressEnd(on: date, now: now) : nil,
                                      isOverdue: unreviewed.contains { $0.persistentModelID == block.persistentModelID },
                                      now: now) {
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
        // 분이 바뀌는 그 순간에 맞춰 다시 본다. 시작 시각이 되면 줄이 진행 중으로 넘어간다.
        .task(id: date) {
            while !Task.isCancelled {
                let second = Calendar.current.component(.second, from: Date())
                try? await Task.sleep(for: .seconds(60 - second))
                withAnimation(Motion.row) { now = Date() }
            }
        }
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

/// 달성·부분·건너뜀·미회고를 한 막대에 나눠 그린다. 비어 있으면 회색 바탕만.
struct ReviewBar: View {
    let stats: ReflectionStats
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(1, stats.total)
            let parts: [(Int, Color)] = [(stats.done, .green), (stats.partial, .yellow),
                                         (stats.skipped, .red), (stats.pending, Color.secondary.opacity(0.35))]
            HStack(spacing: stats.total > 0 ? 2 : 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.0 > 0 {
                        Capsule()
                            .fill(part.1)
                            .frame(width: max(height, geo.size.width * CGFloat(part.0) / CGFloat(total)))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .clipShape(Capsule())
        }
        .frame(height: height)
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
                .font(.body)
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
    /// 점검하는 줄인가. 루틴에서 온 것은 '했는지'를 묻지 않는다 (→ PlanBlock.isRoutineKind).
    var reviewable = true
    /// 지금 진행 중이면 그 끝 시각 (→ PlanBlock.inProgressEnd). 줄이 파랗게 서고 남은 시간이 붙는다.
    var runningUntil: Date? = nil
    /// 시간이 지났는데 안 찍었다. 주황으로 서고 '다 했어요 / 아직 하는 중'을 바로 묻는다.
    var isOverdue = false
    var now: Date = Date()
    let onChange: () -> Void

    @State private var hovering = false
    /// 한 줄 회고를 적는 중인가. **찍는다고 저절로 열지 않는다** — 찍을 때마다 칸이 열려 줄이 길어지고
    /// 목록이 들썩였다. '회고하기'를 눌러야 열린다.
    @State private var writing = false
    @FocusState private var noteFocused: Bool

    private var note: String { block.reviewNote ?? "" }

    /// 다 한 것으로 보는가. 줄을 흐리고 제목에 줄을 긋는 기준이다.
    private var isDone: Bool { block.reviewStatus == .done }

    /// 기준·회고 칸이 제목 글줄에 맞춰 들어가는 폭 (동그라미 + 요일).
    private var detailIndent: CGFloat { (showsDay ? 32 : 0) + (compact ? 30 : 32) }

    /// 시각이 정해진 블록은 시각을, 아니면 시간대를. 하루 시간표 옆에서는 몇 시였는지가 먼저 읽혀야 한다.
    private var whenLabel: String {
        block.whenLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .center, spacing: 10) {
                // **할 일 목록과 같은 자리, 같은 손짓** — 왼쪽 동그라미를 눌러 끝낸다
                // (→ BacklogView의 '요일에 올린 일'). 세 갈래 상태는 이 동그라미의
                // 모양으로 드러나므로, 눈으로 읽는 것과 손으로 누르는 것이 한 자리에 있다.
                if reviewable { checkButton } else { routineMark }

                if showsDay {
                    Text(block.day.shortLabel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(block.title)
                            .font(.body.weight(.semibold))
                            .strikethrough(isDone)
                            .foregroundStyle(isDone ? .secondary : .primary)
                        if let end = runningUntil {
                            runningBadge(end)
                                .transition(.pop)
                        } else if isOverdue {
                            overdueBadge
                                .transition(.pop)
                        }
                    }
                    Text(block.isAllDay ? whenLabel : "\(whenLabel) · \(String(format: "%.1fh", block.durationHours))")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 찍었고 아직 안 적었으면 버튼 하나만 선다 — 줄 높이는 그대로.
                if reviewable, block.reviewStatus != nil, note.isEmpty, !writing {
                    Button {
                        withAnimation(Motion.row) { writing = true }
                    } label: {
                        Label("회고하기", systemImage: "square.and.pencil")
                            .font(.body)
                    }
                    // 글자만 있는 단추는 눌러도 되는지 안 읽힌다 — 도드라진 단추로 세운다.
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .help("무엇이 잘 됐고 무엇이 안 됐는지 한 줄로 남깁니다")
                    .transition(.pop)
                }

                // 부분·건너뜀은 자주 쓰는 손짓이 아니다. 늘 세워 두면 '끝냄' 하나를
                // 누르러 온 사람이 셋 중에 고르는 일이 되므로, 가리키기 전에는 숨긴다.
                // (마우스를 안 쓰는 사람을 위해 줄 전체에 같은 메뉴를 우클릭으로도 단다.)
                if reviewable {
                    stateMenu
                        .opacity(hovering ? 1 : 0)
                        .scaleEffect(hovering ? 1 : 0.8)
                }
            }

            if isOverdue && reviewable {
                overdueActions
                    .padding(.leading, detailIndent)
                    .transition(.disclose)
            }

            // 멈출 때 남겨 둔 한 줄 — 돌아왔을 때 여기서부터 (→ PlanBlock.nextAction).
            if let next = block.nextAction, !next.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(next)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.leading, detailIndent)
                .transition(.disclose)
            }

            if !block.successCriteria.isEmpty {
                Text("기준: \(block.successCriteria)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, detailIndent)
            }

            if writing {
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
                .focused($noteFocused)
                .onSubmit { finishWriting() }
                .onExitCommand { finishWriting() }
                .onChange(of: noteFocused) { _, focused in if !focused { finishWriting() } }
                .onAppear { noteFocused = true }
                .padding(.leading, detailIndent)
                .transition(.disclose)
            } else if !note.isEmpty {
                // 적어 둔 회고는 글로만 선다. 누르면 다시 고친다.
                Button {
                    withAnimation(Motion.row) { writing = true }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "text.quote")
                        Text(note)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("눌러서 고치기")
                .padding(.leading, detailIndent)
                .transition(.disclose)
            }
        }
        .padding(.horizontal, compact ? 4 : 16)
        .padding(.vertical, compact ? 9 : 12)
        // 진행 중인 줄은 옅게 파랗다 — 목록에서 '지금'이 먼저 읽힌다.
        .background {
            if runningUntil != nil || isOverdue {
                RoundedRectangle.soft(Corner.chip)
                    .fill((runningUntil != nil ? Color.blue : Color.orange).opacity(0.09))
                    .overlay(RoundedRectangle.soft(Corner.chip)
                        .strokeBorder(isOverdue ? Color.orange.opacity(0.45) : .clear, lineWidth: 1))
                    .padding(.horizontal, compact ? -4 : 6)
                    .padding(.vertical, 3)
            }
        }
        .animation(Motion.row, value: runningUntil)
        .animation(Motion.row, value: isOverdue)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // 표시를 찍으면 제목에 줄이 그어지고 옆에 '회고하기'가 선다. 한 결로 묶는다.
        .animation(Motion.row, value: block.reviewStatus)
        .animation(Motion.row, value: writing)
        .animation(Motion.hover, value: hovering)
        .contextMenu { if reviewable { stateButtons } }
    }

    /// '진행 중 · 32분 남음'. 끝냈는지는 묻지 않는다 — 끝나면 사람이 찍는다.
    /// '아직 하는 중'이라 답해 끝 시각을 넘긴 것은 '12분 넘김'.
    private func runningBadge(_ end: Date) -> some View {
        let over = now >= end
        let minutes = max(1, Int((abs(end.timeIntervalSince(now)) / 60).rounded(.up)))
        let left: String
        if over {
            left = minutes >= 60
                ? String(localized: "\(minutes / 60)시간 \(minutes % 60)분 넘김")
                : String(localized: "\(minutes)분 넘김")
        } else {
            left = minutes >= 60
                ? String(localized: "\(minutes / 60)시간 \(minutes % 60)분 남음")
                : String(localized: "\(minutes)분 남음")
        }
        return HStack(spacing: 4) {
            Image(systemName: "play.circle.fill")
            Text("진행 중")
            Text(verbatim: "· \(left)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.12), in: Capsule())
        .lineLimit(1)
        .fixedSize()
    }

    /// '시간 지남'. 진행 중이던 줄이 끝 시각을 넘기면 이것으로 바뀐다.
    private var overdueBadge: some View {
        Label("시간 지남", systemImage: "clock.badge.exclamationmark.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    /// 끝났는지, 아직 하는 중인지. 부분·건너뜀은 동그라미 옆 메뉴에 그대로 있다.
    private var overdueActions: some View {
        HStack(spacing: 8) {
            Button {
                Haptic.tick()
                withAnimation(Motion.squish) { block.reviewStatus = .done }
                StillGoing.clear(block)
                onChange()
            } label: {
                Label("다 했어요", systemImage: "checkmark")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                withAnimation(Motion.row) { StillGoing.mark(block) }
            } label: {
                Label("아직 하는 중", systemImage: "play.fill")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .help("끝날 때까지 진행 중으로 둡니다. 끝나면 동그라미를 눌러 주세요")
        }
    }

    private func finishWriting() {
        guard writing else { return }
        withAnimation(Motion.row) { writing = false }
    }

    /// 루틴 줄의 표시. 체크 동그라미 자리를 비워 두면 줄이 어긋나므로 같은 크기로 세운다.
    private var routineMark: some View {
        Image(systemName: block.isBackground ? "calendar" : "repeat")
            .font(.system(size: compact ? 10 : 11, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
            .help(block.isBackground ? "그날의 배경 일정입니다 — 했는지 묻지 않습니다"
                                     : "루틴입니다 — 했는지 묻지 않습니다")
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


// MARK: - 끝났나요?

/// **지나간 일정 중 아직 안 찍은 것을 묻는다.** 맨 위 줄, 타이머 알약 옆에 선다.
///
/// 끝나자마자 찍으라고 창을 띄우지 않는다 — 인터뷰가 끝난 그 순간에는 다음 일로 넘어가는 중이다.
/// 대신 주황 뱃지로 남아 있다가, 누르면 일정마다 달성 · 부분 달성 · 건너뜀을 바로 고른다.
/// 하나도 없으면 아무것도 서지 않는다.
struct OverdueAskBadge: View {
    /// 지나갔는데 안 찍은 블록 (시각 순).
    let blocks: [PlanBlock]

    @Environment(\.modelContext) private var context

    var body: some View {
        if !blocks.isEmpty {
            Menu {
                Section("끝냈나요?") {
                    ForEach(blocks, id: \.dragToken) { block in
                        Menu {
                            Button {
                                StillGoing.mark(block)
                            } label: {
                                Label("아직 하는 중", systemImage: "play.fill")
                            }
                            Divider()
                            ForEach(ReviewStatus.allCases) { status in
                                Button {
                                    Haptic.tick()
                                    withAnimation(Motion.squish) {
                                        block.reviewStatus = status
                                        try? context.save()
                                    }
                                } label: {
                                    Label(status.label, systemImage: status.systemImage)
                                }
                            }
                        } label: {
                            Text(verbatim: "\(block.title) · \(block.whenLabel)")
                        }
                    }
                }
                Divider()
                Button {
                    Haptic.tick()
                    withAnimation(Motion.squish) {
                        for b in blocks { b.reviewStatus = .done }
                        try? context.save()
                    }
                } label: {
                    Label("모두 완료", systemImage: "checkmark.circle.fill")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "questionmark.circle.fill")
                    Text("끝냈나요?")
                    Text(verbatim: "\(blocks.count)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "시간이 지났는데 아직 안 찍은 일정 \(blocks.count)개"))
            .transition(.pop)
        }
    }
}
