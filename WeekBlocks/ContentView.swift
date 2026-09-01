import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var routines: [Routine]
    @Query private var allBlocks: [PlanBlock]
    @Query(sort: [SortDescriptor(\BacklogItem.sortIndex), SortDescriptor(\BacklogItem.createdAt)])
    private var backlogItems: [BacklogItem]
    @Query private var allOccurrences: [RoutineOccurrence]
    @Query private var allQuotaPlacements: [QuotaPlacement]

    @State private var selectedWeek: Date = .currentWeekStart
    @State private var blockSheet: BlockSheetContext?
    @State private var routineSheet: RoutineSheetContext?
    @State private var routineDetailSheet: Routine?
    @State private var showingReflection = false
    @State private var showingSettings = false
    @State private var showingSampleAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var didSeed = false
    /// 타임라인에서 수면 시간을 잘라내 남은 시간을 넓게 본다.
    @AppStorage("hideSleepInTimeline") private var hideSleepInTimeline = false
    @State private var shareStore = ScheduleShareStore.shared

    /// 한 주 요약(총량·고정 루틴·남은 자유 시간)을 펼쳐 두었는가. 기본은 접힘.
    @AppStorage("showsWeekSummary") private var showsWeekSummary = false

    /// 마지막으로 보던 자리. 앱을 다시 켜도 하던 일을 이어서 한다.
    @AppStorage("weekLens") private var weekLensRaw = WeekLens.plan.rawValue
    private var weekLens: WeekLens { WeekLens(rawValue: weekLensRaw) ?? .plan }

    /// 툴바 '할 일 추가' 신호 — 목록으로 데려가는 쪽은 여기서 듣는다.
    /// (빈 칸을 여는 쪽은 BacklogSection이 같은 신호를 듣는다.)
    private let composeRequest = TodoComposeRequest.shared

    /// 할 일 목록 자리표. 툴바에서 눌렀을 때 여기로 스크롤한다.
    private static let todosAnchor = "todos-section"

    private var weekBlocks: [PlanBlock] {
        let cal = Calendar(identifier: .iso8601)
        return allBlocks.filter { cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek) }
    }

    private var routineHours: Double {
        routines.reduce(0) { $0 + $1.totalWeeklyHours }
    }

    private var plannedHours: Double {
        // '루틴 안' 일정은 이미 루틴 시간에 포함되므로 계획 시간(자유 소비)에서 제외.
        weekBlocks.filter { !$0.withinRoutine }.reduce(0) { $0 + $1.durationHours }
    }

    private var freeHours: Double {
        max(0, 168 - routineHours)
    }

    /// 빼놓을 수 없는 중요한 고정 루틴이 하나라도 확보돼 있는지.
    /// 이게 true가 되어야 백로그·계획 블록을 추가할 수 있다.
    private var hasFixedRoutines: Bool {
        routines.contains { $0.kind == .fixed }
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 28) {
                    weekHeader
                    // 요약은 접혀 있는 것이 기본이다 (→ weekHeader의 '요약' 버튼).
                    if showsWeekSummary {
                        VStack(alignment: .leading, spacing: 10) {
                            metricsRow
                            WeekBarChart(routineHours: routineHours, plannedHours: plannedHours)
                        }
                        .transition(.asymmetric(insertion: .push(from: .top).combined(with: .opacity),
                                                removal: .opacity))
                    }
                    // 오늘 손을 움직여야 하는 것만 온다 (앞으로 올 시점·계약 미확정은 백로그에 있다).
                    // 늦은 나쁜 소식이 신뢰를 깎는 유일한 요인이라 타임라인 아래에 묻지 않고 위에 둔다.
                    BroadcastPlanSection(allItems: backlogItems, allBlocks: allBlocks)
                    weekLensSection
                    // 할 일 목록은 한 주를 보는 자리 **아래**에 둔다.
                    // 먼저 이번 주가 어떻게 생겼는지 보고, 그다음 무엇을 끌어다 놓을지 고른다.
                    // (따로 선 창으로만 두었더니, 창을 안 열어 둔 사람에게는 요일 칸에
                    //  넣을 카드가 아예 보이지 않았다. 창 ⇧⌘T 는 나란히 놓고 쓰고 싶을 때.)
                    BacklogSection(allItems: backlogItems,
                                   weekStart: selectedWeek,
                                   weekBlocks: weekBlocks,
                                   canPlan: hasFixedRoutines,
                                   showsCategoryFilter: false,
                                   listensForComposeRequest: true)
                        .id(Self.todosAnchor)
                    routinesSection
                    // 공유받은 일정은 실제로 받은 게 있을 때만 노출한다. (내 일정 공유는 설정에서)
                    if !shareStore.received.isEmpty {
                        ReceivedSchedulesSection()
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 툴바에서 '할 일 추가'를 누르면 아래로 내려가 있어도 목록으로 데려간다.
                // 빈 칸이 열렸는데 화면 밖이면 누른 것이 아무 일도 안 한 것처럼 보인다.
                .onChange(of: composeRequest.ticket) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.todosAnchor, anchor: .top)
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 700)
        .navigationTitle("무지개 공방")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // 아이콘만 있던 시절(목록 그림)에는 이게 **적는 자리**라는 걸 아무도
                // 읽어내지 못했다. '＋'와 글자를 함께 세워, 누르기 전에 무엇이 일어나는지
                // 버튼 자체가 말하게 한다. 누르면 아래 할 일 목록으로 데려가고
                // 맨 앞에 빈 칸을 열어 준다 — 누른 뜻이 곧 '적겠다'이기 때문이다.
                Button {
                    TodoComposeRequest.shared.requestNew()
                } label: {
                    Label("할 일 추가", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .help("할 일 목록 맨 앞에 빈 칸을 연다 (⌘N)")

                Button {
                    showingReflection = true
                } label: {
                    Label("회고", systemImage: "checklist")
                }

                Button {
                    showingSettings = true
                } label: {
                    Label("설정", systemImage: "gearshape")
                }

                Menu {
                    // 할 일 창은 두 창을 나란히 놓고 쓰고 싶을 때의 길이다.
                    // 같은 목록이 이 창에도 있으므로 툴바 자리를 차지하지 않는다.
                    Button {
                        openWindow(id: WeekBlocksWindow.todos)
                    } label: {
                        Label("할 일 창 열기 (⇧⌘T)", systemImage: "macwindow.on.rectangle")
                    }
                    Divider()
                    Button {
                        routineSheet = RoutineSheetContext(routine: nil)
                    } label: {
                        Label("루틴 추가", systemImage: "plus")
                    }
                    Button {
                        showingSampleAlert = true
                    } label: {
                        Label("샘플 데이터 추가", systemImage: "tray.and.arrow.down")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        Label("모든 데이터 삭제", systemImage: "trash")
                    }
                } label: {
                    Label("더 보기", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $blockSheet) { ctx in
            BlockEditorView(
                existing: ctx.block,
                day: ctx.day,
                weekStart: selectedWeek,
                suggestedBand: TimelineLayout.suggestedBand(
                    routines: fixedRoutines(on: ctx.day),
                    blocks: weekBlocks.filter { $0.day == ctx.day }
                )
            )
            .frame(minWidth: 520, minHeight: 540)
        }
        .sheet(item: $routineSheet) { ctx in
            RoutineEditorView(existing: ctx.routine)
                .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(isPresented: $showingReflection) {
            ReflectionView(weekStart: selectedWeek)
                .frame(minWidth: 640, minHeight: 600)
        }
        .sheet(item: $routineDetailSheet) { routine in
            RoutineDetailView(routine: routine)
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(scheduleSnapshots: {
                ScheduleSnapshotBuilder.snapshots(routines: routines, allBlocks: allBlocks, currentWeek: selectedWeek)
            })
        }
        .alert("샘플 데이터 추가", isPresented: $showingSampleAlert) {
            Button("추가") { addSampleData() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("기본 루틴과 샘플 할 일·블록을 추가하시겠습니까?")
        }
        .alert("모든 데이터 삭제", isPresented: $showingDeleteAllAlert) {
            Button("삭제", role: .destructive) { deleteAllData() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("루틴·계획 블록·할 일을 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.")
        }
        // 전파 계약이 붙은 할 일을 요일에 떨어뜨릴 때 받던 확인은 걷어냈다 —
        // 배치해도 할 일이 백로그에 그대로 남으므로 알릴 일이 없어졌다.
        .task {
            if !didSeed {
                didSeed = true
                await seedDefaultsIfNeeded()
                dedupeRoutinesByName()
                // 내려받기가 늦게 도착해 겹치는 일이 있어, 자리 잡은 뒤 한 번 더 본다.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    dedupeRoutinesByName()
                }
            }
            reconcileOccurrences(for: selectedWeek)
            await shareStore.refresh()
            await autoPublishSharedSchedule()
        }
        .onChange(of: selectedWeek) { _, newWeek in
            reconcileOccurrences(for: newWeek)
            Task { await autoPublishSharedSchedule() }
        }
        .onChange(of: routineSignature) { _, _ in
            // 루틴 추가·삭제·편집(이름·요일·종류) 시 모든 주의 occurrence를 현재 루틴에 맞게 재동기화.
            let weeks = Set(allOccurrences.map(\.weekStartDate)).union([selectedWeek])
            for w in weeks { reconcileOccurrences(for: w) }
        }
        .onChange(of: shareSignature) { _, _ in
            // 루틴·블록이 바뀌면 공유 중인 일정을 자동 갱신.
            Task { await autoPublishSharedSchedule() }
        }
    }

    /// 공유 중일 때만 현재 일정으로 스냅숏을 갱신한다.
    private func autoPublishSharedSchedule() async {
        guard shareStore.isSharing else { return }
        await shareStore.publish(
            ScheduleSnapshotBuilder.snapshots(routines: routines, allBlocks: allBlocks, currentWeek: selectedWeek)
        )
    }

    /// 공유용 시그니처(루틴·블록) — 바뀌면 자동 재발행.
    private var shareSignature: String {
        ScheduleSnapshotBuilder.signature(routines: routines, allBlocks: allBlocks)
    }

    /// 타임라인에 그릴 시간 범위. 수면 숨김이 꺼져 있으면 하루 전체.
    private var timelineWindow: HourWindow {
        TimelineLayout.visibleWindow(
            fixedRoutines: routines.filter { $0.kind == .fixed },
            blocks: weekBlocks,
            hideSleep: hideSleepInTimeline
        )
    }

    /// 루틴 구성이 바뀌면 onChange가 감지하도록 만드는 시그니처(이름·종류·요일).
    private var routineSignature: String {
        routines.map { "\($0.name)|\($0.kindRaw)|\($0.dayMask)" }.joined(separator: ";")
    }

    // MARK: subviews

    private var weekHeader: some View {
        HStack(spacing: 14) {
            Button { shiftWeek(by: -1) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(weekRangeString)
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                Text(weekSubtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(weekOffset == 0 ? Color.red : .secondary)
            }
            .frame(minWidth: 280, alignment: .leading)

            Button { shiftWeek(by: 1) } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderless)

            if weekOffset != 0 {
                Button("이번 주로") { selectedWeek = .currentWeekStart }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Spacer()

            // 한 주 총량·고정 루틴·남은 자유 시간 요약.
            // 좋은 숫자지만 **매번 볼 숫자는 아니다** — 한 주에 한 번 확인하면 되는 값이
            // 화면 맨 위 제일 좋은 자리를 늘 차지하고 있었다. 버튼 뒤로 접고, 접힘 상태를 기억한다.
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showsWeekSummary.toggle() }
            } label: {
                Label(showsWeekSummary ? "요약 접기" : "요약",
                      systemImage: "chart.bar.xaxis")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .help("한 주 총량 · 고정 루틴 · 남은 자유 시간")
        }
    }

    private var weekRangeString: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: selectedWeek) ?? selectedWeek
        let f = DateFormatter()
        f.dateFormat = "M월 d일"
        return "\(f.string(from: selectedWeek)) – \(f.string(from: end))"
    }

    /// 현재 주 기준 선택된 주의 상대 위치 (0 = 이번 주, +1 = 다음 주 …)
    private var weekOffset: Int {
        let cal = Calendar(identifier: .iso8601)
        let days = cal.dateComponents([.day], from: .currentWeekStart, to: selectedWeek).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    private var weekSubtitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy년"
        let year = f.string(from: selectedWeek)
        let rel: String
        switch weekOffset {
        case 0: rel = "이번 주"
        case 1: rel = "다음 주"
        case -1: rel = "지난 주"
        case let n where n > 0: rel = "\(n)주 후"
        default: rel = "\(-weekOffset)주 전"
        }
        return "\(year) · \(rel)"
    }

    private func dayDate(_ day: DayOfWeek) -> Date {
        Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: day.rawValue, to: selectedWeek) ?? selectedWeek
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            MetricCard(label: "한 주", value: "168", unit: "h", subtitle: "하루 24h")
            MetricCard(
                label: "고정 루틴",
                value: String(format: "%.1f", routineHours),
                unit: "h",
                subtitle: "하루 약 \(String(format: "%.1f", routineHours / 7))h"
            )
            // 자유 시간은 '아직 계획이 없는 시간' — 계획(파랑)과 같은 색을 쓰면 뜻이 겹친다.
            // 아래 막대에서도 남은 자유는 빈 구간으로 그리므로 여기서도 색을 주지 않는다.
            MetricCard(
                label: "남은 자유 시간",
                value: String(format: "%.1f", freeHours),
                unit: "h",
                subtitle: "하루 약 \(String(format: "%.1f", freeHours / 7))h"
            )
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("고정 루틴 · 중요한 일", systemImage: "lock")
                    .font(.headline)
                Spacer()
                Button {
                    routineSheet = RoutineSheetContext(routine: nil)
                } label: {
                    Label("루틴 추가", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if routines.isEmpty {
                ContentUnavailableView(
                    "루틴이 없습니다",
                    systemImage: "lock.open",
                    description: Text("수면 · 식사 · 운동처럼 빼놓을 수 없는 중요한 시간을 먼저 확보하세요.")
                )
                .frame(minHeight: 120)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(routines) { routine in
                        RoutineBlock(
                            routine: routine,
                            onEdit: { routineSheet = RoutineSheetContext(routine: routine) },
                            onDelete: {
                                context.delete(routine)
                                try? context.save()
                            }
                        )
                    }
                }
            }
        }
    }

    /// 해당 요일에 이번 주 배치된 고정 루틴들.
    private func fixedRoutines(on day: DayOfWeek) -> [Routine] {
        let cal = Calendar(identifier: .iso8601)
        let names = Set(allOccurrences
            .filter { $0.day == day && !$0.hidden && cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek) }
            .map(\.routineName))
        return routines
            .filter { $0.kind == .fixed && names.contains($0.name) }
            .sorted { $0.startHour < $1.startHour }
    }

    /// 해당 요일에 숨긴(삭제한) 고정 루틴들 — 타임라인에 유령 블록으로 표시·되살리기용.
    private func hiddenFixedRoutines(on day: DayOfWeek) -> [Routine] {
        let cal = Calendar(identifier: .iso8601)
        let names = Set(allOccurrences
            .filter { $0.day == day && $0.hidden && cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek) }
            .map(\.routineName))
        return routines
            .filter { $0.kind == .fixed && names.contains($0.name) }
            .sorted { $0.startHour < $1.startHour }
    }

    /// '요일별 하루' 타임라인이 실제로 배치한 시작 시각 순서대로,
    /// 고정 루틴·유연 쿼터·계획 블록을 한 줄로 섞어 정렬한 '이번 주 계획' 컬럼 항목.
    /// (타임라인의 왼→오른쪽 = 컬럼의 위→아래가 일치하도록.)
    private func dayPlanItems(on day: DayOfWeek) -> [DayPlanItem] {
        let cal = Calendar(identifier: .iso8601)
        let dayBlocks = weekBlocks.filter { $0.day == day }
        let fixed = fixedRoutines(on: day)
        let quota = routines.filter { $0.kind == .quota }.sorted { $0.weeklyHours > $1.weeklyHours }
        let occs = allOccurrences.filter { $0.day == day && cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek) }
        let placements = allQuotaPlacements.filter { $0.day == day && cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek) }

        var startOverride: [String: Double] = [:]
        for o in occs where o.startHourOverride >= 0 { startOverride[o.routineName] = o.startHourOverride }
        var quotaPlace: [String: [Int: Double]] = [:]
        for p in placements { quotaPlace[p.routineName, default: [:]][p.sessionIndex] = p.startHour }
        var quotaHiddenMap: [String: Set<Int>] = [:]
        for p in placements where p.hidden { quotaHiddenMap[p.routineName, default: []].insert(p.sessionIndex) }

        let segs = TimelineLayout.segments(
            routines: fixed,
            blocks: dayBlocks,
            quota: quota,
            routineStartOverride: startOverride,
            quotaPlacement: quotaPlace,
            quotaHidden: quotaHiddenMap,
            hiddenRoutines: hiddenFixedRoutines(on: day)
        )

        // 끼니 겹침 판정용: 쿼터를 제외한, 실제로 차지된 구간(고정 루틴·블록 등).
        let occupiers = segs.filter { !$0.isGhost && !$0.source.isQuota }.map { ($0.start, $0.end) }
        func overlapsOccupier(_ s: Double, _ e: Double) -> Bool {
            occupiers.contains { s < $0.1 - 1e-6 && $0.0 < e - 1e-6 }
        }

        // 타임라인에 '보이는' 조각을 그대로 컬럼 항목으로. 정렬 키 = 그려진 시작 시각(seg.start).
        // 자정을 넘긴 고정 루틴은 조각마다 따로 → 위·아래 두 번. 겹치는 끼니는 접는다.
        // 블록은 자정 분할로 중복되지 않게 가장 이른 조각만.
        var entries: [(start: Double, rank: Int, item: DayPlanItem)] = []
        var blockStart: [String: Double] = [:]
        for seg in segs where !seg.isGhost {
            switch seg.source {
            case .fixedRoutine(let name):
                guard let r = fixed.first(where: { $0.name == name }) else { break }
                entries.append((seg.start, 0, .fixedRoutine(r, occurrenceID: seg.id,
                                                             atHour: seg.start, hours: seg.end - seg.start)))
            case .quotaSession(let name, let index):
                guard let r = quota.first(where: { $0.name == name }) else { break }
                if overlapsOccupier(seg.start, seg.end) { break }   // 다른 일정 안의 끼니는 접음
                entries.append((seg.start, 2, .quotaSession(r, sessionIndex: index, atHour: seg.start)))
            case .planBlock(let blk):
                let id = String(describing: blk.persistentModelID)
                blockStart[id] = min(blockStart[id] ?? .greatestFiniteMagnitude, seg.start)
            case .none:
                break
            }
        }
        for b in dayBlocks {
            let id = String(describing: b.persistentModelID)
            let at = blockStart[id] ?? b.sortHour
            entries.append((at, 1, .block(b, atHour: at)))
        }

        // 시각 같으면 고정 → 블록 → 쿼터 순으로 안정 정렬.
        return entries
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.rank < $1.rank }
            .map(\.item)
    }

    /// 한 주를 보는 두 자리. 목적이 다르므로 **한 번에 하나만** 세운다.
    ///
    /// 예전에는 '요일별 하루 24시간'과 '이번 주 계획'을 위아래로 함께 깔았다.
    /// 둘 다 같은 주의 같은 일을 그리지만 묻는 것이 달라서(무엇을 언제 / 하루 어디에),
    /// 스크롤로 왔다 갔다 하면 지금 무엇을 정하고 있었는지를 놓친다.
    /// 세그먼트로 가르고, 그 옆에 이 자리가 무엇을 하는 자리인지 한 줄로 적는다.
    private var weekLensSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Picker("", selection: lensBinding) {
                    ForEach(WeekLens.allCases) { lens in
                        Label(lens.rawValue, systemImage: lens.symbol).tag(lens.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)

                Text(weekLens.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)

                Spacer(minLength: 12)

                // 오른쪽 끝에는 그 자리에서만 필요한 범례를 둔다.
                // 겹쳐 세워야 바뀌는 동안 옆 글이 밀리지 않는다.
                ZStack(alignment: .trailing) {
                    switch weekLens {
                    case .plan:
                        Legend()
                            .transition(.opacity)
                    case .day:
                        Text(timelineLegend)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }

            // 두 자리는 **겹쳐 세우고 옆으로 밀어** 바꾼다.
            // 위아래로 갈아 끼우면 새 자리가 어디서 왔는지 알 수 없어
            // 매번 화면을 처음부터 다시 읽게 된다.
            ZStack(alignment: .topLeading) {
                switch weekLens {
                case .plan:
                    weekGridSection
                        .transition(lensTransition)
                case .day:
                    dayTimelineSection
                        .transition(lensTransition)
                }
            }
        }
    }

    /// 세그먼트를 누르면 값이 애니메이션과 함께 바뀐다.
    private var lensBinding: Binding<String> {
        Binding(
            get: { weekLensRaw },
            set: { newValue in
                guard newValue != weekLensRaw else { return }
                withAnimation(.snappy(duration: 0.3)) { weekLensRaw = newValue }
            }
        )
    }

    /// 나가는 쪽과 들어오는 쪽이 같은 방향으로 흐른다 — 한 장을 옆으로 넘기는 결.
    /// 방향은 따로 기억하지 않는다. 두 칸짜리 세그먼트에서는 **지금 선 자리**가 곧 방향이다
    /// (오른쪽 칸으로 갔으면 오른쪽에서 들어온다).
    /// 밀리는 거리는 짧게(28pt) 둔다. 화면이 통째로 날아다니면 산만하다.
    private var lensTransition: AnyTransition {
        let forward = (weekLens == .day)
        return .asymmetric(
            insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
            removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)
        )
    }

    /// 타임라인 오른쪽 끝의 범례. 잘라 보는 중이면 그 사실도 여기서 말한다
    /// (제목을 세그먼트에 내주었으므로 "6–24시"가 갈 자리가 여기밖에 없다).
    private var timelineLegend: String {
        let window = timelineWindow.isFullDay
            ? "하루 24시간"
            : "\(Int(timelineWindow.start))–\(Int(timelineWindow.end))시 · 수면 숨김"
        return "\(window) · 실선=고정 · 점선=유연 쿼터 · 계획은 빈 구간에"
    }

    private var dayTimelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HourAxis(window: timelineWindow)

            VStack(spacing: 4) {
                ForEach(DayOfWeek.allCases) { day in
                    DayTimelineRow(
                        day: day,
                        date: dayDate(day),
                        routines: fixedRoutines(on: day),
                        blocks: weekBlocks.filter { $0.day == day },
                        quotaRoutines: routines.filter { $0.kind == .quota },
                        hiddenRoutines: hiddenFixedRoutines(on: day),
                        occurrences: allOccurrences.filter {
                            $0.day == day && Calendar(identifier: .iso8601).isDate($0.weekStartDate, inSameDayAs: selectedWeek)
                        },
                        quotaPlacements: allQuotaPlacements.filter {
                            $0.day == day && Calendar(identifier: .iso8601).isDate($0.weekStartDate, inSameDayAs: selectedWeek)
                        },
                        weekStart: selectedWeek,
                        window: timelineWindow,
                        onDropBacklog: { token, hour in
                            dropBacklogItem(token: token, day: day, atHour: hour)
                        }
                    )
                }
            }
        }
    }

    private var weekGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(DayOfWeek.allCases) { day in
                    DayColumn(
                        day: day,
                        date: dayDate(day),
                        canPlan: hasFixedRoutines,
                        items: dayPlanItems(on: day),
                        onAdd: {
                            blockSheet = BlockSheetContext(day: day, block: nil)
                        },
                        onEdit: { block in
                            blockSheet = BlockSheetContext(day: day, block: block)
                        },
                        onEditRoutine: { routine in
                            routineDetailSheet = routine
                        },
                        onEditRoutineSchedule: { routine in
                            routineSheet = RoutineSheetContext(routine: routine)
                        },
                        onDropBacklog: { token in
                            dropBacklogItem(token: token, day: day)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    // MARK: helpers

    /// 해당 주의 occurrence를 현재 고정 루틴 구성(이름·요일)과 정확히 일치시킨다.
    /// 루틴을 편집(이름/요일 변경)하거나 추가/삭제해도 그리드·타임라인이 즉시 반영되도록.
    private func reconcileOccurrences(for week: Date) {
        let cal = Calendar(identifier: .iso8601)
        let weekOccs = allOccurrences.filter { cal.isDate($0.weekStartDate, inSameDayAs: week) }
        let fixedRoutinesList = routines.filter { $0.kind == .fixed }
        let fixedNames = Set(fixedRoutinesList.map(\.name))

        var changed = false

        // 1) 고아 occurrence 제거 (현재 고정 루틴 이름과 매칭되지 않는 것 — 이름 변경/삭제/종류 변경)
        for occ in weekOccs where !fixedNames.contains(occ.routineName) {
            context.delete(occ)
            changed = true
        }

        // 2) 각 고정 루틴의 이번 주 배치를 selectedDays와 정확히 일치시킨다
        for routine in fixedRoutinesList {
            let existing = weekOccs.filter { $0.routineName == routine.name }
            let existingDays = Set(existing.map(\.day))
            let wantDays = routine.selectedDays

            for day in wantDays.subtracting(existingDays) {
                context.insert(RoutineOccurrence(routineName: routine.name, day: day, weekStartDate: week))
                changed = true
            }
            for occ in existing where !wantDays.contains(occ.day) {
                context.delete(occ)
                changed = true
            }
        }

        if changed { try? context.save() }
    }

    /// 요일 칸(블록으로 보기)과 시간 자(시간축으로 보기)가 함께 쓰는 받는 자리.
    /// - Parameter atHour: 자 위에 떨어뜨렸을 때의 시작 시각. 요일 칸에서는 nil(시간대만 정한다).
    private func dropBacklogItem(token: String, day: DayOfWeek, atHour: Double? = nil) {
        if token.hasPrefix("block:") {
            // 이미 계획에 올린 블록을 옮긴다 — 요일 칸에서는 요일만, 자 위에서는 시각까지.
            let idStr = String(token.dropFirst("block:".count))
            guard let blk = allBlocks.first(where: { String(describing: $0.persistentModelID) == idStr }) else { return }
            var changed = false
            if blk.day != day { blk.day = day; changed = true }
            if let hour = atHour {
                let start = clampStart(hour, duration: blk.durationHours)
                if blk.startHour != start {
                    blk.startHour = start
                    blk.timeBand = timeBand(for: start)
                    changed = true
                }
            }
            if changed { try? context.save() }
            return
        }
        if token.hasPrefix("routine:") {
            let name = String(token.dropFirst("routine:".count))
            guard let routine = routines.first(where: { $0.name == name }) else { return }
            let duration = routine.kind == .fixed ? routine.durationHours : 1
            let start = atHour.map { clampStart($0, duration: duration) }
            let block = PlanBlock(
                day: day,
                timeBand: timeBand(for: start ?? (routine.kind == .fixed ? routine.startHour : 12)),
                durationHours: duration,
                title: routine.name,
                successCriteria: "",
                deliverable: "",
                weekStartDate: selectedWeek,
                concreteVerified: false,
                startHour: start ?? -1
            )
            context.insert(block)
        } else {
            guard let item = backlogItems.first(where: { $0.dragToken == token }) else { return }
            convertBacklogItem(item, to: day, atHour: atHour)
        }
        try? context.save()
    }

    /// 떨어뜨린 시각을 하루 안에 가둔다 — 끝자락에 놓아도 자정을 넘겨 사라지지 않게.
    private func clampStart(_ hour: Double, duration: Double) -> Double {
        min(max(0, hour), max(0, 24 - duration))
    }

    /// 백로그 항목 → 계획 블록. **항목은 지우지 않는다. 목록에서 내릴 뿐이다.**
    ///
    /// 요일에 올린 일은 할 일 목록에서 빠진다 — 언제 할지 정한 것과 아직 안 정한 것이
    /// 섞이면 "무엇을 정해야 하는가"가 흐려지기 때문이다(→ BacklogSection.filteredItems).
    /// 하지만 **레코드는 그대로 남는다.** 블록을 지우면 다시 목록에 서고,
    /// 끝냈는지는 '요일에 올린 일'에서 체크한다.
    ///
    /// ⚠️ 예전에는 단계가 없는 할 일을 배치하면서 `context.delete(item)`으로 지웠다.
    ///    그 삭제가 CloudKit을 타고 iOS '욕망의 무지개'까지 건너가, 맥에서 요일에
    ///    올린 할 일이 아이폰 할 일 목록에서 통째로 사라졌다. iOS는 반대로 배정해도
    ///    항목을 남긴다(→ ScheduleDensityApp/Services/WeekBlocksStore.swift). 두 앱이
    ///    같은 스토어를 쓰는 이상 어느 한쪽만 지우면 안 된다. **다시 지우지 말 것.**
    ///
    /// 단계로 쪼갠 할 일은 지금 할 단계 하나만 올린다. 남은 단계가 여전히 할 일이기 때문이다.
    private func convertBacklogItem(_ item: BacklogItem, to day: DayOfWeek, atHour: Double? = nil) {
        let tree = TodoTree(backlogItems)
        let step = tree.hasChildren(item) ? tree.currentStep(of: item) : nil
        let title = step.map { "\(item.title) · \($0.title)" } ?? item.title

        // 항목이 백로그에 남으므로 같은 것을 두 번 떨어뜨릴 수 있다.
        // 같은 주·같은 요일에 이미 올라가 있으면 블록을 새로 만들지 않는다.
        // 다만 자 위에서 시각까지 정해 다시 떨어뜨린 것이라면, 그건 "옮기겠다"는 뜻이다.
        if let existing = weekBlocks.first(where: { $0.day == day && $0.title == title }) {
            if let hour = atHour {
                let start = clampStart(hour, duration: existing.durationHours)
                existing.startHour = start
                existing.timeBand = timeBand(for: start)
                try? context.save()
            }
            return
        }

        let duration = step?.durationHours ?? item.durationHours
        // 자 위에 놓았으면 그 시각이 곧 시작이다. 요일 칸에 놓았으면 빈 시간대를 골라 준다.
        let start = atHour.map { clampStart($0, duration: duration) }
        let block = PlanBlock(
            day: day,
            timeBand: start.map { timeBand(for: $0) } ?? TimelineLayout.suggestedBand(
                routines: fixedRoutines(on: day),
                blocks: weekBlocks.filter { $0.day == day }
            ),
            durationHours: duration,
            title: title,
            successCriteria: "",
            deliverable: "",
            weekStartDate: selectedWeek,
            concreteVerified: false,
            startHour: start ?? -1
        )
        // 전파 계약은 넘기지 않는다 — 항목이 백로그에 남아 계약의 주인으로 계속 서 있다.
        // 양쪽에 복사하면 '전파 필요' 섹션에 같은 전파가 두 줄로 선다.
        context.insert(block)
        try? context.save()
    }

    private func timeBand(for startHour: Double) -> TimeBand {
        switch startHour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<23: return .evening
        default: return .night
        }
    }

    private func shiftWeek(by weeks: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: weeks * 7, to: selectedWeek) {
            selectedWeek = next.weekStart()
        }
    }

    /// 처음 켠 사람에게만 기본 루틴을 깔아 준다.
    ///
    /// ⚠️ "루틴이 비어 있다"를 곧바로 믿으면 안 된다. CloudKit이 아직 내려주기 전이면
    ///    이미 쓰던 사람의 화면도 잠깐 비어 있고, 거기서 심으면 수면·식사·운동이
    ///    **하나씩 더** 생겨 클라우드로 퍼진다. (실제로 그렇게 만들어 봤다.)
    ///    그래서 ① 내려받을 시간을 주고 ② 한 번 심었으면 다시는 심지 않는다.
    ///    (→ BacklogSection.reconcileCategories 와 같은 규칙)
    @MainActor
    private func seedDefaultsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.seededKey) else { return }
        guard routines.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.seededKey)   // 이미 쓰던 사람
            return
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        // 기다린 뒤에는 @Query가 아니라 스토어에 직접 묻는다 —
        // 기다리는 동안 뷰가 새로 만들어져 손에 든 값이 옛것일 수 있다.
        guard PlanStore.shared.fetch(Routine.self).isEmpty else { return }
        seedDefaults()
    }

    /// 기본 루틴을 실제로 깐다. 기다림 없이 부르는 자리(샘플 데이터)도 이것을 쓴다 —
    /// "심었다"는 표시와 심는 내용이 두 곳에 흩어지면 한쪽만 고치게 된다.
    private func seedDefaults() {
        UserDefaults.standard.set(true, forKey: Self.seededKey)
        for r in Self.defaultRoutines { context.insert(r) }
        try? context.save()
    }

    private static let seededKey = "didSeedDefaultRoutines"

    /// 처음 켠 사람에게 깔아 주는 세 가지. 샘플 데이터도 같은 것을 쓴다.
    private static var defaultRoutines: [Routine] {
        [
            Routine(name: "수면", iconName: "moon.fill", kind: .fixed, colorName: "indigo",
                    dayMask: 0b1111111, startHour: 23, durationHours: 8, sortIndex: 0),
            Routine(name: "식사", iconName: "fork.knife", kind: .quota, colorName: "green",
                    weeklyHours: 17.5, sessionsPerDay: 3, sortIndex: 1),
            Routine(name: "운동", iconName: "figure.run", kind: .fixed, colorName: "orange",
                    dayMask: 0b0110101, startHour: 7.5, durationHours: 1, sortIndex: 2),
        ]
    }

    /// 같은 이름의 루틴이 둘 이상이면 **먼저 만들어진 것만** 남긴다.
    ///
    /// 동기화가 늦어 빈 화면에서 기본 루틴이 다시 심겼거나, 두 기기가 같은 이름을
    /// 각자 만든 경우에 생긴다. 요일별 배치(RoutineOccurrence)는 이름으로 붙으므로
    /// 이름만 하나로 모으면 배치도 제자리를 찾는다.
    private func dedupeRoutinesByName() {
        var keep: [String: Routine] = [:]
        var victims: [Routine] = []
        for r in PlanStore.shared.fetch(Routine.self) {
            guard let kept = keep[r.name] else { keep[r.name] = r; continue }
            if r.createdAt < kept.createdAt {
                keep[r.name] = r
                victims.append(kept)
            } else {
                victims.append(r)
            }
        }
        guard !victims.isEmpty else { return }
        for v in victims { context.delete(v) }
        try? context.save()
        reconcileOccurrences(for: selectedWeek)
    }

    private func addSampleData() {
        // 샘플을 부른 것은 사람의 뜻이므로 여기서는 기다리지 않고 바로 깐다.
        if routines.isEmpty { seedDefaults() }

        let base = backlogItems.map(\.sortIndex).max() ?? -1
        let samples: [(String, Double)] = [
            ("기획서 초안 작성", 2),
            ("논문 1편 정독", 1.5),
            ("주간 회고 정리", 0.5),
        ]
        for (i, s) in samples.enumerated() {
            context.insert(BacklogItem(title: s.0, durationHours: s.1,
                                       sortIndex: base + 1 + i, weekStartDate: selectedWeek))
        }

        context.insert(PlanBlock(
            day: .mon,
            timeBand: .evening,
            durationHours: 2,
            title: "Swift Combine 학습",
            successCriteria: "sink·assign 차이를 노트에 정리하고 예제 실행에 성공한다",
            deliverable: "정리 노트 1장 + 동작하는 예제 1개",
            weekStartDate: selectedWeek,
            concreteVerified: true
        ))
        try? context.save()
    }

    private func deleteAllData() {
        for b in allBlocks { context.delete(b) }
        for r in routines { context.delete(r) }
        for o in allOccurrences { context.delete(o) }
        for i in backlogItems { context.delete(i) }
        try? context.save()
    }
}

/// 한 주를 보는 두 자리. 이름이 아니라 **목적**으로 가른다.
enum WeekLens: String, CaseIterable, Identifiable {
    /// 무엇을 어느 요일에 할지 정하는 자리 (할 일을 끌어다 놓는 곳).
    /// 요일 칸에 덩어리가 쌓인 모양이라 '블록'이다.
    case plan = "블록으로 보기"
    /// 그 일이 하루의 어디에 들어가는지 보는 자리.
    /// 24시간 자 위에 깔린 모양이라 '시간축'이다.
    case day = "시간축으로 보기"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .plan: "calendar"
        case .day:  "clock"
        }
    }

    /// 세그먼트 옆 한 줄. 지금 무엇을 하는 중인지를 잊지 않게 한다.
    var purpose: String {
        switch self {
        case .plan: "무엇을 어느 요일에 할지 정한다 — 할 일을 끌어다 놓는 자리"
        case .day:  "그 일이 하루 어디에 들어가는지 본다 — 시간이 실제로 있는지"
        }
    }
}

// MARK: Sheet contexts

struct BlockSheetContext: Identifiable {
    let id = UUID()
    let day: DayOfWeek
    let block: PlanBlock?
}

struct RoutineSheetContext: Identifiable {
    let id = UUID()
    let routine: Routine?
}

// MARK: Components

struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title.weight(.medium))
                    .monospacedDigit()
                Text(unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WeekBarChart: View {
    let routineHours: Double
    let plannedHours: Double

    private let total = 168.0
    private var isOverPlanned: Bool { plannedHours > total - routineHours }
    private var clampedPlanned: Double { min(plannedHours, max(0, total - routineHours)) }
    private var freeRemaining: Double { max(0, total - routineHours - clampedPlanned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    if routineHours > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: barWidth(geo.size.width, routineHours))
                    }
                    if clampedPlanned > 0 {
                        Rectangle()
                            .fill(isOverPlanned ? Color.red.opacity(0.7) : Color.accentColor.opacity(0.8))
                            .frame(width: barWidth(geo.size.width, clampedPlanned))
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))

            HStack(spacing: 20) {
                barLegend(color: .secondary.opacity(0.6), label: "루틴", hours: routineHours)
                barLegend(color: isOverPlanned ? .red : .accentColor, label: "계획", hours: plannedHours)
                barLegend(color: .secondary.opacity(0.15), label: "남은 자유 (계획 없음)", hours: freeRemaining)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func barWidth(_ totalWidth: CGFloat, _ hours: Double) -> CGFloat {
        CGFloat(hours / total) * totalWidth
    }

    private func barLegend(color: Color, label: String, hours: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(label) \(String(format: "%.0f", hours))h")
        }
    }
}

struct Legend: View {
    var body: some View {
        HStack(spacing: 14) {
            legendDot(color: .accentColor, label: "구체적인 블록")
            legendDot(color: .orange, label: "추상적인 블록")
            legendDot(color: .secondary, label: "유연 쿼터", dashed: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendDot(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(dashed ? 0.10 : 0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(color.opacity(0.5),
                                style: dashed ? StrokeStyle(lineWidth: 0.8, dash: [2, 1.5]) : StrokeStyle(lineWidth: 0.5))
                )
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}
