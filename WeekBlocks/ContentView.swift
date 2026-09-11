import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var routinesRaw: [Routine]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var routines: [Routine] { routinesRaw.filter(TodoSharing.isVisible) }
    @Query private var allBlocksRaw: [PlanBlock]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var allBlocks: [PlanBlock] { allBlocksRaw.filter(TodoSharing.isVisible) }
    @Query(sort: [SortDescriptor(\BacklogItem.sortIndex), SortDescriptor(\BacklogItem.createdAt)])
    private var backlogItems: [BacklogItem]
    @Query private var allOccurrences: [RoutineOccurrence]
    @Query private var allQuotaPlacements: [QuotaPlacement]

    @State private var selectedWeek: Date = .currentWeekStart
    /// 캘린더에서 가져온 결과를 사람에게 알리는 자리. 조용히 끝나면 눌린 줄도 모른다.
    @State private var calendarNotice: String?
    /// 끼워 넣은 것이 틈보다 커서 겹쳤을 때 뜨는 붉은 줄.
    @State private var conflictNotice: String?
    /// 캘린더에서 사라져 지울 참인 블록들. **묻기 전에는 안 지운다.**
    @State private var pendingRemovals: [PlanBlock] = []
    @State private var blockSheet: BlockSheetContext?
    @State private var routineSheet: RoutineSheetContext?
    @State private var routineDetailSheet: Routine?
    @State private var showingReflection = false
    @State private var showingSettings = false
    @State private var showingSampleAlert = false
    /// 처음 켠 사람에게 앱을 건네는 자리 (→ OnboardingView.swift).
    /// 메뉴 막대(도움말)에서도 같은 자리를 열기에 스토어를 가운데에 둔다.
    @State private var onboarding = OnboardingPresenter.shared
    /// '다음 한 걸음' 줄을 아주 닫았는가. 다 아는 사람에게 계속 말을 걸지 않는다.
    @AppStorage("didDismissNextStep") private var didDismissNextStep = false
    @State private var showingDeleteAllAlert = false
    @State private var didSeed = false
    /// 타임라인에서 수면 시간을 잘라내 남은 시간을 넓게 본다.
    @AppStorage("hideSleepInTimeline") private var hideSleepInTimeline = false
    @State private var shareStore = ScheduleShareStore.shared
    /// 지금 하고 있는 하나와 남은 시간 (→ TaskTimer.swift). 기기에만 남는다.
    @State private var taskTimer = TaskTimer.shared

    /// 시간 자에서 요일 줄들이 각각 화면 어디에 서 있는가(요일 rawValue → 화면 좌표).
    /// 계획 블록을 세로로 끌 때 "지금 어느 요일 위인가"를 여기서 답한다.
    @State private var timelineRowFrames: [Int: CGRect] = [:]
    /// 지금 끌고 가는 계획 블록이 놓이려는 요일. 그 줄에 테두리가 선다.
    @State private var timelineDayTarget: DayOfWeek?

    /// 마지막으로 주를 어느 쪽으로 넘겼는가. 새 주는 넘긴 쪽에서 들어온다 —
    /// 방향이 없으면 다음 주로 가나 지난 주로 가나 같은 그림이라 어디로 갔는지 모른다.
    @State private var weekForward = true

    /// 한 주 요약(총량·고정 루틴·남은 자유 시간)을 펼쳐 두었는가. 기본은 접힘.
    @AppStorage("showsWeekSummary") private var showsWeekSummary = false

    /// 마지막으로 보던 자리. 앱을 다시 켜도 하던 일을 이어서 한다.
    @AppStorage("weekLens") private var weekLensRaw = WeekLens.plan.rawValue
    private var weekLens: WeekLens { WeekLens(rawValue: weekLensRaw) ?? .plan }

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
            VStack(alignment: .leading, spacing: 22) {
                weekHeader
                // 지금 화면에서 다음에 할 일 하나. 흐름을 다 지나면 사라진다.
                if let step = nextStep {
                    NextStepBanner(step: step,
                                   onAction: { perform(step) },
                                   onDismiss: {
                                       withAnimation(Motion.banner) {
                                           didDismissNextStep = true
                                       }
                                   })
                    .transition(.banner)
                }
                // 요약은 접혀 있는 것이 기본이다 (→ weekHeader의 '요약' 버튼).
                if showsWeekSummary {
                    VStack(alignment: .leading, spacing: 10) {
                        metricsRow
                        WeekBarChart(routineHours: routineHours, plannedHours: plannedHours)
                    }
                    // 접히고 펴지는 결이 양쪽으로 같아야 한 덩어리가 여닫히는 것으로 읽힌다.
                    // 예전에는 펼 때만 밀려 내려오고 접을 때는 그 자리에서 사라져서,
                    // 접는 순간 아래 화면이 툭 끊기며 올라왔다.
                    .transition(.disclose)
                    // 미끄러져 들어오는 동안 위의 날짜 줄을 덮지 않게 자른다. 다만 요약 카드의
                    // 그림자까지 잘리지 않게, 자르는 테두리를 둘레만큼 넓혀 둔다 (→ Surface.swift).
                    .padding(20)
                    .clipped()
                    .padding(-20)
                }
                weekLensSection
                // 할 일 목록은 한 주를 보는 자리 **아래**에 둔다.
                // 먼저 이번 주가 어떻게 생겼는지 보고, 그다음 무엇을 끌어다 놓을지 고른다.
                // (따로 선 창으로만 두었더니, 창을 안 열어 둔 사람에게는 요일 칸에
                //  넣을 카드가 아예 보이지 않았다. 창 ⇧⌘T 는 나란히 놓고 쓰고 싶을 때.)
                BacklogSection(allItems: backlogItems,
                               weekStart: selectedWeek,
                               weekBlocks: weekBlocks,
                               canPlan: hasFixedRoutines,
                               showsCategoryFilter: false)
                .dashboardPanel()
                routinesSection
                    .dashboardPanel()
                // 공유받은 일정은 실제로 받은 게 있을 때만 노출한다. (내 일정 공유는 설정에서)
                if !shareStore.received.isEmpty {
                    ReceivedSchedulesSection()
                        .dashboardPanel()
                        .transition(.disclose)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // @Query가 스스로 새 값을 물어오는 자리에는 `withAnimation`을 걸 손이 없다.
            // "무엇이 서 있는가"가 바뀌었을 때만 결이 붙도록 값으로 건다.
            .animation(Motion.screen, value: nextStep)
            .animation(Motion.disclose, value: shareStore.received.count)
            // ⚠️ **@AppStorage 값은 `withAnimation`만으로는 안 움직인다.** 값이 UserDefaults를 한 바퀴
            //    돌아 돌아오는 사이에 애니메이션이 떨어져 나가서, 요약이 늘고 줄 때 아래 화면이 툭
            //    끊겨 올라왔다. 값 자체에 결을 건다 — 어디서 바꾸든(단추·다른 창·다음 실행) 같은 결로 움직인다.
            .animation(Motion.disclose, value: showsWeekSummary)
            .animation(Motion.screen, value: weekLensRaw)
        }
        // 대시보드의 바닥. 요일 칸·할 일·루틴이 이 위에 올라간 카드로 읽힌다 (→ Surface.swift).
        .background(Color.canvas)
        .frame(minWidth: 980, minHeight: 700)
        .navigationTitle("무지개 공방")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openWindow(id: WeekBlocksWindow.timer)
                } label: {
                    Label("타이머", systemImage: "timer")
                }
                .help("지금 하는 일에 남은 시간 (⇧⌘R)")

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
                    // 이미 캘린더에 적혀 있는 것을 손으로 또 적게 하지 않는다
                    // (→ CalendarImport.swift). 고를 캘린더는 설정에서 정한다.
                    Button {
                        importFromCalendar()
                    } label: {
                        Label("캘린더에서 가져오기", systemImage: "calendar.badge.plus")
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
        .alert("캘린더에서 사라진 일정 \(pendingRemovals.count)개를 지울까요?",
               isPresented: Binding(get: { !pendingRemovals.isEmpty },
                                    set: { if !$0 { pendingRemovals = [] } })) {
            Button("남겨두기", role: .cancel) { pendingRemovals = [] }
            Button("지우기", role: .destructive) {
                let removed = CalendarBridge.shared.removeOrphans(pendingRemovals, in: context)
                pendingRemovals = []
                calendarNotice = String(localized: "\(removed)개를 지웠습니다.")
            }
        } message: {
            Text("""
            아래 블록은 캘린더에서 일정이 없어졌습니다.             지우면 **같은 iCloud 계정의 아이폰에서도 함께 사라지고, 되돌릴 수 없습니다.**
            (성공 기준·산출물·회고를 적어 둔 것은 이 목록에 없습니다 — 그건 남깁니다.)

            \(removalPrompt)
            """)
        }
        .alert("캘린더에서 가져오기",
               isPresented: Binding(get: { calendarNotice != nil },
                                    set: { if !$0 { calendarNotice = nil } })) {
            Button("확인", role: .cancel) { calendarNotice = nil }
        } message: {
            Text(calendarNotice ?? "")
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
        .sheet(isPresented: $onboarding.isPresented) {
            OnboardingView(onWriteMyOwn: {
                routineSheet = RoutineSheetContext(routine: nil)
            }, startPage: onboarding.startPage)
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
            }, onReplayOnboarding: {
                RoutineOnboarding.reset()
                didDismissNextStep = false
                showingSettings = false
                onboarding.present()
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
        .task {
            if !didSeed {
                didSeed = true
                await offerRoutineOnboardingIfNeeded()
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

    /// 지금 화면에서 **다음에 할 일 하나** (→ OnboardingView.swift).
    ///
    /// 순서는 앱이 실제로 흐르는 순서다: 고정 루틴 → 할 일 → 요일에 올리기.
    /// 세 개를 다 지나면 nil이 되어 줄이 사라진다. 처음 온 사람만 보게 된다.
    private var nextStep: NextStep? {
        guard !didDismissNextStep else { return nil }
        if routines.isEmpty { return .setRoutines }
        guard weekBlocks.isEmpty else { return nil }
        let hasOpenTodo = backlogItems.contains { $0.parentToken == nil && !$0.isCompleted }
        return hasOpenTodo ? .placeTodos : .writeTodos
    }

    private func perform(_ step: NextStep) {
        switch step {
        case .setRoutines:
            onboarding.present(from: 1)
        case .writeTodos:
            openWindow(id: WeekBlocksWindow.todos)
        case .placeTodos:
            break
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
        // 날짜는 **한 줄**로 선다. 두 줄에 32pt로 세워 두었더니 화면 맨 위의 제일 좋은
        // 자리를 늘 날짜가 차지했다 — 정작 봐야 할 것은 그 아래 한 주의 모양이다.
        HStack(spacing: 8) {
            Button { shiftWeek(by: -1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)

            Text(weekRangeString)
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
                .fixedSize()
                // 주를 넘기면 날짜도 함께 굴러간다. 화면만 밀리고 날짜가 툭 바뀌면
                // 두 개가 따로 노는 것으로 읽힌다.
                .contentTransition(.numericText())

            Button { shiftWeek(by: 1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)

            Text(weekSubtitle)
                .contentTransition(.opacity)
                .font(.callout.weight(.medium))
                .foregroundStyle(weekOffset == 0 ? Color.red : .secondary)
                .fixedSize()
                .padding(.leading, 2)

            if weekOffset != 0 {
                Button("이번 주로") { shiftWeek(to: .currentWeekStart) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.control)
            }

            // 한 줄의 무게를 양 끝으로 나눈다. 왼쪽은 '언제'(날짜), 오른쪽은 '어떻게 볼까'.
            // 가운데에 몰아 두면 오른쪽이 통째로 비어 한쪽으로 쏠려 보인다.
            Spacer()

            // 지금 세고 있는 일이 있으면 남은 시간이 여기 늘 서 있다.
            // 타이머 창을 닫아 두어도 "무엇을 하는 중이고 얼마 남았는지"는 사라지지 않는다.
            TimelineView(.everyMinute) { ctx in
                TimerPill(slot: currentSlot(at: ctx.date)) {
                    openWindow(id: WeekBlocksWindow.timer)
                }
            }

            // 한 주를 보는 두 자리. 날짜 줄에 함께 세운다 —
            // 세그먼트 하나가 아래에서 한 줄을 통째로 차지하고 있었다.
            Picker("", selection: lensBinding) {
                ForEach(WeekLens.allCases) { lens in
                    Label(lens.label, systemImage: lens.symbol).tag(lens.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .padding(.leading, 6)

            // 한 주 총량·고정 루틴·남은 자유 시간 요약.
            // 좋은 숫자지만 **매번 볼 숫자는 아니다** — 한 주에 한 번 확인하면 되는 값이
            // 화면 맨 위 제일 좋은 자리를 늘 차지하고 있었다. 버튼 뒤로 접고, 접힘 상태를 기억한다.
            Button {
                withAnimation(Motion.disclose) { showsWeekSummary.toggle() }
            } label: {
                Label(showsWeekSummary ? "요약 접기" : "요약",
                      systemImage: showsWeekSummary ? "chevron.up" : "chart.bar.xaxis")
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.borderless)
            .help("한 주 총량 · 고정 루틴 · 남은 자유 시간")
        }
    }

    private var weekRangeString: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: selectedWeek) ?? selectedWeek
        let f = DateFormatter()
        // ⚠️ "M월 d일"로 못 박지 않는다. 언어마다 월·일 차례와 사이에 오는 것이 다르므로,
        //    무엇을 보일지(월과 일)만 말하고 어떻게 쓸지는 로케일에 맡긴다.
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(f.string(from: selectedWeek)) – \(f.string(from: end))"
    }

    /// 현재 주 기준 선택된 주의 상대 위치 (0 = 이번 주, +1 = 다음 주 …)
    private var weekOffset: Int {
        let cal = Calendar(identifier: .iso8601)
        let days = cal.dateComponents([.day], from: .currentWeekStart, to: selectedWeek).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    private var weekSubtitle: String {
        let rel: String
        switch weekOffset {
        case 0: rel = String(localized: "이번 주")
        case 1: rel = String(localized: "다음 주")
        case -1: rel = String(localized: "지난 주")
        case let n where n > 0: rel = String(localized: "\(n)주 후")
        default: rel = String(localized: "\(-weekOffset)주 전")
        }
        // 연도는 올해가 아닐 때만 말한다. 늘 붙여 두면 매번 읽히지만 매번 필요하지는 않다.
        let cal = Calendar.current
        guard cal.component(.year, from: selectedWeek) != cal.component(.year, from: Date())
        else { return rel }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yyyy")
        return "\(f.string(from: selectedWeek)) · \(rel)"
    }

    private func dayDate(_ day: DayOfWeek) -> Date {
        Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: day.rawValue, to: selectedWeek) ?? selectedWeek
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            MetricCard(label: String(localized: "한 주"), value: "168", unit: "h",
                       subtitle: String(localized: "하루 24h"))
            MetricCard(
                label: String(localized: "고정 루틴"),
                value: String(format: "%.1f", routineHours),
                unit: "h",
                subtitle: String(localized: "하루 약 \(String(format: "%.1f", routineHours / 7))h")
            )
            // 자유 시간은 '아직 계획이 없는 시간' — 계획(파랑)과 같은 색을 쓰면 뜻이 겹친다.
            // 아래 막대에서도 남은 자유는 빈 구간으로 그리므로 여기서도 색을 주지 않는다.
            MetricCard(
                label: String(localized: "남은 자유 시간"),
                value: String(format: "%.1f", freeHours),
                unit: "h",
                subtitle: String(localized: "하루 약 \(String(format: "%.1f", freeHours / 7))h")
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
                // 비어 있다고만 말하지 않는다. 무엇을 해야 하는지와, 도와줄 길을 함께 준다.
                VStack(alignment: .leading, spacing: 10) {
                    Text("고정으로 시간을 쓰는 일이 아직 없습니다")
                        .font(.callout.weight(.medium))
                    Text("잠, 끼니처럼 빼놓을 수 없는 시간을 먼저 세우면 남는 자리가 실제로 쓸 수 있는 시간이 됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("만드는 걸 도와드릴게요") { onboarding.present(from: 1) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("직접 적기") { routineSheet = RoutineSheetContext(routine: nil) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: .soft(Corner.panel))
                .transition(.disclose)
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
                                withAnimation(Motion.card) {
                                    context.delete(routine)
                                    try? context.save()
                                }
                            }
                        )
                        .transition(.card)
                    }
                }
            }
        }
        // 비어 있는 안내와 카드 무리가 서로 갈아 끼워지는 것까지 한 결로 묶는다.
        .animation(Motion.card, value: routines.map(\.name))
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
            // 자리를 고르는 세그먼트는 날짜 줄에 있다 (→ weekHeader).
            // 두 자리는 **겹쳐 세우고 옆으로 밀어** 바꾼다.
            // 위아래로 갈아 끼우면 새 자리가 어디서 왔는지 알 수 없어
            // 매번 화면을 처음부터 다시 읽게 된다.
            if let notice = conflictNotice {
                conflictBanner(notice)
            }

            // 바깥 껍질은 **보는 자리**가 바뀌는 결(옆으로 넘김), 안쪽 껍질은 **주**가
            // 바뀌는 결이다. 한 뷰에 `.transition`을 두 번 붙이면 바깥 것만 살아남으므로
            // 껍질을 두 겹으로 나눈다.
            //
            // ⚠️ 안쪽도 **ZStack**이어야 한다. VStack으로 감싸면 넘기는 동안 나가는 주와
            //    들어오는 주가 위아래로 나란히 서서 화면 높이가 잠깐 두 배가 되고,
            //    아래에 있는 할 일 목록이 통째로 밀려 내려갔다 올라온다.
            ZStack(alignment: .topLeading) {
                switch weekLens {
                case .plan:
                    ZStack(alignment: .topLeading) {
                        weekGridSection
                            .id(selectedWeek)
                            .transition(.pageSlide(forward: weekForward, distance: 40))
                    }
                    .transition(lensTransition)
                case .day:
                    ZStack(alignment: .topLeading) {
                        dayTimelineSection
                            .dashboardPanel()
                            .id(selectedWeek)
                            .transition(.pageSlide(forward: weekForward, distance: 40))
                    }
                    .transition(lensTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// **겹쳤다고 알리는 붉은 줄.**
    ///
    /// 알림창(alert)으로 안 낸 이유: 끼워 넣기는 여러 번 이어서 하는 손짓이라, 매번 창이
    /// 뜨면 흐름이 끊긴다. 그리고 겹침은 *지금 이 화면에서는 볼 수 없는* 일이므로,
    /// 말만 하는 것으로 끝내지 않고 **볼 수 있는 자리로 가는 길**을 같은 줄에 둔다.
    private func conflictBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text(notice)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("시간축으로 보기") {
                withAnimation(Motion.screen) {
                    weekLensRaw = WeekLens.day.rawValue
                    conflictNotice = nil
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .underline()
            Button {
                withAnimation(Motion.banner) { conflictNotice = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.92), in: .soft(Corner.card))
        .transition(.banner)
    }

    /// 세그먼트를 누르면 값이 애니메이션과 함께 바뀐다.
    private var lensBinding: Binding<String> {
        Binding(
            get: { weekLensRaw },
            set: { newValue in
                guard newValue != weekLensRaw else { return }
                withAnimation(Motion.screen) { weekLensRaw = newValue }
            }
        )
    }

    /// 나가는 쪽과 들어오는 쪽이 같은 방향으로 흐른다 — 한 장을 옆으로 넘기는 결.
    /// 방향은 따로 기억하지 않는다. 두 칸짜리 세그먼트에서는 **지금 선 자리**가 곧 방향이다
    /// (오른쪽 칸으로 갔으면 오른쪽에서 들어온다).
    /// 밀리는 거리는 짧게(28pt) 둔다. 화면이 통째로 날아다니면 산만하다.
    private var lensTransition: AnyTransition {
        .pageSlide(forward: weekLens == .day)
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
                        },
                        isDayDropTarget: timelineDayTarget == day,
                        dayAtGlobalPoint: dayRow(atGlobalPoint:),
                        onDayTargetChange: { target in
                            guard timelineDayTarget != target else { return }
                            withAnimation(Motion.target) { timelineDayTarget = target }
                        },
                        onEditBlock: { block in
                            blockSheet = BlockSheetContext(day: day, block: block)
                        },
                        onEditRoutine: { routine in
                            routineDetailSheet = routine
                        },
                        onEditRoutineSchedule: { routine in
                            routineSheet = RoutineSheetContext(routine: routine)
                        }
                    )
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: DayRowFramesKey.self,
                                                   value: [day.rawValue: geo.frame(in: .global)])
                        }
                    }
                }
            }
            .onPreferenceChange(DayRowFramesKey.self) { timelineRowFrames = $0 }
        }
    }

    /// 화면 좌표 한 점이 어느 요일 줄 위인가.
    /// 줄 사이 틈에서 답이 끊기지 않게 세로로 가장 가까운 줄을 고르고,
    /// 자에서 한 줄 넘게 벗어나면 "요일을 바꾸려는 게 아니다"로 본다.
    private func dayRow(atGlobalPoint point: CGPoint) -> DayOfWeek? {
        guard let nearest = timelineRowFrames.min(by: {
            abs(point.y - $0.value.midY) < abs(point.y - $1.value.midY)
        }) else { return nil }
        guard abs(point.y - nearest.value.midY) <= nearest.value.height else { return nil }
        return DayOfWeek(rawValue: nearest.key)
    }

    private var weekGridSection: some View {
        // 분이 바뀌면 '지금 하고 있는 것'이 달라질 수 있다. 그때 칩의 남은 시간도 자리를 옮긴다.
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(DayOfWeek.allCases) { day in
                        DayColumn(
                            day: day,
                            date: dayDate(day),
                            canPlan: hasFixedRoutines,
                            currentSlot: currentSlot(at: ctx.date),
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
                            },
                            onDropIntoGap: { token, start, gap in
                                dropIntoGap(token: token, day: day, startHour: start, gap: gap)
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                // 일곱 칸의 키를 가장 긴 칸에 맞춘다 (칸 쪽은 `maxHeight: .infinity`로 늘어난다).
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// **캘린더의 이번 주 일정을 계획 블록으로 옮긴다** (→ CalendarImport.swift).
    ///
    /// 권한이 없거나 고른 캘린더가 없으면 설정으로 보낸다 — 아무 일도 안 일어나면
    /// 사람은 기능이 고장 났다고 읽는다.
    private func importFromCalendar() {
        let bridge = CalendarBridge.shared
        guard bridge.hasAccess, !bridge.selectedIDs.isEmpty else {
            showingSettings = true
            return
        }
        let result = bridge.importWeek(selectedWeek, into: context)

        // 캘린더에서 사라진 일정이 있으면 **지우기 전에 묻는다.**
        // 이 삭제는 CloudKit을 타고 아이폰까지 건너가 거기서도 사라진다 — 되돌릴 수 없다.
        if !result.pendingRemovals.isEmpty {
            pendingRemovals = result.pendingRemovals
            return
        }
        calendarNotice = bridge.failureMessage ?? result.summary
    }

    /// 지울 참인 블록들을 사람이 읽을 수 있게 늘어놓는다. 숫자만 보여주고 지우면
    /// "뭐가 지워졌지"가 남는다. 다섯 줄까지만 적고 나머지는 세어서 말한다.
    private var removalPrompt: String {
        let names = pendingRemovals.prefix(5).map { "· \($0.title) (\($0.day.shortLabel))" }
        var text = names.joined(separator: "\n")
        if pendingRemovals.count > names.count {
            text += "\n" + String(localized: "… 외 \(pendingRemovals.count - names.count)개")
        }
        return text
    }

    /// 일정 기준으로 지금 하고 있는 조각 (→ ScheduleClock.swift).
    /// 타이머를 켜고 끄는 것과 무관하게, 계획에 적힌 시각만으로 정해진다.
    private func currentSlot(at date: Date) -> ScheduleSlot? {
        ScheduleClock.current(
            ScheduleClock.slots(routines: routines, blocks: allBlocks,
                                occurrences: allOccurrences, placements: allQuotaPlacements,
                                around: date),
            at: date
        )
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
        if let move = RoutineDragToken(token) {
            moveRoutine(move, to: day, startHour: atHour, gap: nil)
            return
        }
        if token.hasPrefix("block:") {
            // 이미 계획에 올린 블록을 옮긴다 — 요일 칸에서는 요일만, 자 위에서는 시각까지.
            guard let blk = PlanBlock.matching(dragToken: token, in: allBlocks) else { return }
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

    /// **칩 사이에 끼워 넣는다 — 순서를 바꾼다는 건 시각을 정한다는 뜻이다.**
    ///
    /// 요일 칸에는 수동 순서가 없다. 자리는 곧 시각이라(`PlanBlock.sortHour`), 앞 항목이
    /// 끝나는 시각에 놓아 원하는 자리에 서게 한다.
    ///
    /// ⚠️ 틈보다 큰 것이 들어오면 **그래도 옮긴다.** 안 옮기고 튕기면 사람은 드래그가
    ///    고장 났다고 읽는다. 대신 겹쳤다는 사실을 붉게 알리고, 겹침이 실제로 보이는
    ///    자리(시간축)로 갈 길을 함께 준다. 요일 칸은 겹침을 그리지 못한다.
    private func dropIntoGap(token: String, day: DayOfWeek, startHour: Double, gap: Double) {
        if let move = RoutineDragToken(token) {
            moveRoutine(move, to: day, startHour: startHour, gap: gap)
            return
        }
        guard token.hasPrefix("block:") else {
            // 백로그 항목·루틴은 원래 길로. 시각까지 정해서 넘긴다.
            dropBacklogItem(token: token, day: day, atHour: startHour)
            return
        }
        guard let blk = PlanBlock.matching(dragToken: token, in: allBlocks) else { return }
        blk.day = day
        blk.startHour = clampStart(startHour, duration: blk.durationHours)
        blk.timeBand = timeBand(for: blk.startHour)
        try? context.save()

        // 0.01은 반올림 앙금을 무시하려는 여유다. 1.5h가 1.4999h 틈에 안 들어간다고
        // 경고하면 사람은 앱이 트집 잡는다고 느낀다.
        if blk.durationHours > gap + 0.01 {
            withAnimation(Motion.banner) {
                conflictNotice = String(localized: "‘\(blk.title)’(\(shortHours(blk.durationHours)))이 \(shortHours(gap)) 틈보다 커서 다음 일정과 겹칩니다.")
            }
        }
    }

    /// **요일 칸에서 루틴·끼니 칩을 끌어 옮긴다 — 이번 주 그 요일의 시각만.**
    ///
    /// 시간축에서 띠를 좌우로 끄는 것과 같은 자리에 적는다(고정 루틴 → `RoutineOccurrence.startHourOverride`,
    /// 끼니 → `QuotaPlacement`, → DayTimelineRow.commitDrag). 루틴 정의(모든 주의 기본 시각)는 안 건드린다.
    ///
    /// ⚠️ **요일은 못 옮긴다.** 고정 루틴의 요일은 루틴 자체의 약속이라 칩 하나 끌어서 바꾸면
    ///    다음 주부터 어긋난다. 그렇다고 놓아도 튕기기만 하면 고장으로 읽히므로 이유를 붉게 알린다.
    private func moveRoutine(_ move: RoutineDragToken, to day: DayOfWeek, startHour: Double?, gap: Double?) {
        guard move.day == day else {
            withAnimation(Motion.banner) {
                conflictNotice = String(localized: "‘\(move.name)’은(는) 요일을 옮길 수 없습니다. 같은 요일 안에서 시각만 옮기고, 요일은 루틴 수정에서 바꿉니다.")
            }
            return
        }
        guard let startHour else { return }   // 칸 바탕에 놓았다 — 틈을 안 골랐으니 그대로 둔다.
        let cal = Calendar(identifier: .iso8601)

        switch move.kind {
        case .fixed(let pieceStart):
            guard let routine = routines.first(where: { $0.name == move.name }) else { return }
            let occ = allOccurrences.first {
                $0.routineName == move.name && $0.day == day && cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek)
            }
            let logical = (occ?.startHourOverride ?? -1) >= 0 ? occ!.startHourOverride : routine.startHour
            // 자정을 넘겨 둘로 그려진 잠은 어느 조각을 잡았든 **잡은 조각의 머리**가 놓은 자리에 오게,
            // 원래 시작 시각을 같은 만큼 민다.
            var newStart = (logical + (startHour - pieceStart)).truncatingRemainder(dividingBy: 24)
            if newStart < 0 { newStart += 24 }
            newStart = min(max(newStart, 0), 23.75)
            if let occ {
                occ.startHourOverride = newStart
            } else {
                let created = RoutineOccurrence(routineName: move.name, day: day, weekStartDate: selectedWeek)
                created.startHourOverride = newStart
                context.insert(created)
            }

        case .quota(let index):
            guard let routine = routines.first(where: { $0.name == move.name && $0.kind == .quota }) else { return }
            let each = routine.dailyQuotaHours / Double(max(1, routine.sessionsPerDay))
            let newStart = clampStart(startHour, duration: each)
            if let placement = allQuotaPlacements.first(where: {
                $0.routineName == move.name && $0.day == day && $0.sessionIndex == index
                    && cal.isDate($0.weekStartDate, inSameDayAs: selectedWeek)
            }) {
                placement.startHour = newStart
            } else {
                context.insert(QuotaPlacement(routineName: move.name, day: day, weekStartDate: selectedWeek,
                                              sessionIndex: index, startHour: newStart))
            }
            // 틈보다 크면 다음 일정과 겹친다 — 겹친 끼니는 요일 칸에서 접히므로(→ dayPlanItems) 말없이
            // 사라진 것처럼 보인다. 계획 블록과 같은 말로 알린다.
            if let gap, each > gap + 0.01 {
                withAnimation(Motion.banner) {
                    conflictNotice = String(localized: "‘\(routine.name)’(\(shortHours(each)))이 \(shortHours(gap)) 틈보다 커서 다음 일정과 겹칩니다.")
                }
            }
        }
        withAnimation(Motion.card) { try? context.save() }
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
        context.insert(block)
        try? context.save()
    }

    private func timeBand(for startHour: Double) -> TimeBand { .containing(startHour) }

    private func shiftWeek(by weeks: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: weeks * 7, to: selectedWeek)
        else { return }
        shiftWeek(to: next.weekStart())
    }

    /// 주를 옮긴다. **방향을 먼저 정하고 옮긴다** — 화면이 어느 쪽에서 들어올지가
    /// 여기서 정해지기 때문이다. 같은 주를 다시 부르면 아무 일도 일어나지 않는다.
    private func shiftWeek(to week: Date) {
        guard !Calendar(identifier: .iso8601).isDate(week, inSameDayAs: selectedWeek) else { return }
        weekForward = week > selectedWeek
        withAnimation(Motion.screen) { selectedWeek = week }
    }

    /// 처음 켠 사람에게 **고정 루틴을 함께 세우자고 묻는다.** 대신 깔아 주지 않는다.
    ///
    /// 회사를 안 다니는 사람도, 운동을 안 하는 사람도 있다. 내가 만들지 않은 일정이
    /// 이미 놓여 있으면 그것부터 지우는 일로 앱을 시작하게 된다. (→ RoutineOnboardingView)
    ///
    /// ⚠️ "루틴이 비어 있다"를 곧바로 믿으면 안 된다. CloudKit이 아직 내려주기 전이면
    ///    이미 쓰던 사람의 화면도 잠깐 비어 있어서, 쓰던 사람에게 첫 인사를 다시 건네게 된다.
    ///    그래서 내려받을 시간을 준 뒤에 묻는다.
    @MainActor
    private func offerRoutineOnboardingIfNeeded() async {
        guard !RoutineOnboarding.wasShown else { return }
        guard routines.isEmpty else {
            UserDefaults.standard.set(true, forKey: RoutineOnboarding.shownKey)  // 이미 쓰던 사람
            return
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        // 기다린 뒤에는 @Query가 아니라 스토어에 직접 묻는다 —
        // 기다리는 동안 뷰가 새로 만들어져 손에 든 값이 옛것일 수 있다.
        guard PlanStore.shared.fetch(Routine.self).isEmpty else { return }
        onboarding.present()
    }

    /// 처음 켠 사람에게 깔아 주는 세 가지. 샘플 데이터도 같은 것을 쓴다.
    private static var defaultRoutines: [Routine] {
        [
            Routine(name: String(localized: "수면", comment: "기본 루틴 이름"), iconName: "moon.fill", kind: .fixed, colorName: "indigo",
                    dayMask: 0b1111111, startHour: 23, durationHours: 8, sortIndex: 0),
            Routine(name: String(localized: "식사", comment: "기본 루틴 이름"), iconName: "fork.knife", kind: .quota, colorName: "green",
                    weeklyHours: 17.5, sessionsPerDay: 3, sortIndex: 1),
            Routine(name: String(localized: "운동", comment: "기본 루틴 이름"), iconName: "figure.run", kind: .fixed, colorName: "orange",
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
        // 샘플을 부른 것은 사람의 뜻이므로 여기서는 묻지 않고 바로 깐다.
        if routines.isEmpty {
            UserDefaults.standard.set(true, forKey: RoutineOnboarding.shownKey)
            for r in Self.defaultRoutines { context.insert(r) }
        }

        let base = backlogItems.map(\.sortIndex).max() ?? -1
        let samples: [(String, Double)] = [
            (String(localized: "기획서 초안 작성", comment: "샘플 할 일"), 2),
            (String(localized: "논문 1편 정독", comment: "샘플 할 일"), 1.5),
            (String(localized: "주간 회고 정리", comment: "샘플 할 일"), 0.5),
        ]
        for (i, s) in samples.enumerated() {
            context.insert(BacklogItem(title: s.0, durationHours: s.1,
                                       sortIndex: base + 1 + i, weekStartDate: selectedWeek))
        }

        context.insert(PlanBlock(
            day: .mon,
            timeBand: .evening,
            durationHours: 2,
            title: String(localized: "Swift Combine 학습", comment: "샘플 계획 블록"),
            successCriteria: String(localized: "sink·assign 차이를 노트에 정리하고 예제 실행에 성공한다", comment: "샘플 계획 블록"),
            deliverable: String(localized: "정리 노트 1장 + 동작하는 예제 1개", comment: "샘플 계획 블록"),
            weekStartDate: selectedWeek,
            concreteVerified: true
        ))
        try? context.save()
    }

    /// ⚠️ **거르지 않은 목록(Raw)을 쓴다.** '모든 데이터 삭제'가 화면에 보이는 것만
    ///    지우면, 안 그려진 것이 스토어에 남아 다음 실행에 되살아난 것처럼 보인다.
    ///    '보이는 것'과 '있는 것'을 가르는 자리라 여기서만 예외를 둔다.
    private func deleteAllData() {
        for b in allBlocksRaw { context.delete(b) }
        for r in routinesRaw { context.delete(r) }
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

    /// ⚠️ rawValue를 화면에 그대로 쓰지 않는다. 그 값은 @AppStorage("weekLens")에
    ///    저장되는 것이라, 번역하면 예전에 고른 자리를 못 알아본다.
    var label: String {
        switch self {
        case .plan: String(localized: "블록으로 보기")
        case .day:  String(localized: "시간축으로 보기")
        }
    }

    var symbol: String {
        switch self {
        case .plan: "calendar"
        case .day:  "clock"
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
                    // 계획을 올리고 내리면 숫자가 굴러간다.
                    .contentTransition(.numericText())
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
        .background { DashboardSurface() }
        .animation(Motion.number, value: value)
    }
}

struct WeekBarChart: View {
    let routineHours: Double
    let plannedHours: Double

    /// 막대가 다 차올랐는가. 요약을 펴면 왼쪽에서부터 자란다.
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                            .frame(width: barWidth(geo.size.width, drawn ? routineHours : 0))
                    }
                    if clampedPlanned > 0 {
                        Rectangle()
                            .fill(isOverPlanned ? Color.red.opacity(0.7) : Color.accentColor.opacity(0.8))
                            .frame(width: barWidth(geo.size.width, drawn ? clampedPlanned : 0))
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
            // 계획을 올리고 내리면 그만큼 자라고 준다. 툭 바뀌면 무엇이 얼마나 늘었는지
            // 앞뒤를 견줄 수가 없다.
            .animation(Motion.chart, value: routineHours)
            .animation(Motion.chart, value: plannedHours)
            .onAppear {
                if reduceMotion { drawn = true; return }
                withAnimation(Motion.chart.delay(0.08)) { drawn = true }
            }

            HStack(spacing: 20) {
                barLegend(color: .secondary.opacity(0.6), label: String(localized: "루틴"), hours: routineHours)
                barLegend(color: isOverPlanned ? .red : .accentColor, label: String(localized: "계획"), hours: plannedHours)
                barLegend(color: .secondary.opacity(0.15), label: String(localized: "남은 자유 (계획 없음)"), hours: freeRemaining)
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
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(label) \(String(format: "%.0f", hours))h")
                .contentTransition(.numericText())
                .animation(Motion.number, value: hours)
        }
    }
}

