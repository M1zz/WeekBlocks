import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
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
    /// 전파 계약이 붙은 백로그 항목을 요일에 떨어뜨렸을 때 확인을 받기 위한 보류 상태.
    @State private var pendingBroadcastDrop: BroadcastDropContext?

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

    /// 협상 불가능한 고정 루틴이 하나라도 확보돼 있는지.
    /// 이게 true가 되어야 백로그·계획 블록을 추가할 수 있다.
    private var hasFixedRoutines: Bool {
        routines.contains { $0.kind == .fixed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                weekHeader
                VStack(alignment: .leading, spacing: 10) {
                    metricsRow
                    WeekBarChart(routineHours: routineHours, plannedHours: plannedHours)
                }
                // 오늘 손을 움직여야 하는 것만 온다 (앞으로 올 시점·계약 미확정은 백로그에 있다).
                // 늦은 나쁜 소식이 신뢰를 깎는 유일한 요인이라 타임라인 아래에 묻지 않고 위에 둔다.
                BroadcastPlanSection(allItems: backlogItems, allBlocks: allBlocks)
                dayTimelineSection
                weekGridSection
                BacklogSection(allItems: backlogItems, weekStart: selectedWeek, canPlan: hasFixedRoutines)
                routinesSection
                // 공유받은 일정은 실제로 받은 게 있을 때만 노출한다. (내 일정 공유는 설정에서)
                if !shareStore.received.isEmpty {
                    ReceivedSchedulesSection()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 980, minHeight: 700)
        .navigationTitle("무지개 공방")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
            Text("기본 루틴과 샘플 백로그·블록을 추가하시겠습니까?")
        }
        .alert("모든 데이터 삭제", isPresented: $showingDeleteAllAlert) {
            Button("삭제", role: .destructive) { deleteAllData() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("루틴·계획 블록·백로그를 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.")
        }
        .alert("전파 계약이 있는 할 일입니다",
               isPresented: Binding(get: { pendingBroadcastDrop != nil },
                                    set: { if !$0 { pendingBroadcastDrop = nil } })) {
            Button("배치하고 계약 유지") {
                if let ctx = pendingBroadcastDrop {
                    convertBacklogItem(ctx.item, to: ctx.day)
                }
                pendingBroadcastDrop = nil
            }
            Button("취소", role: .cancel) { pendingBroadcastDrop = nil }
        } message: {
            if let ctx = pendingBroadcastDrop {
                Text("""
                \(ctx.item.title)
                \(ctx.item.broadcastCarryOverSummary)

                \(ctx.day.longLabel)에 배치하면 이 할 일은 백로그에서 사라지고 계획 블록이 됩니다. \
                전파 계약은 블록으로 그대로 넘어가고, '전파 필요' 섹션에도 계속 남습니다.
                """)
            }
        }
        .task {
            if !didSeed {
                didSeed = true
                seedDefaultsIfNeeded()
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
                Label("고정 루틴 · 협상 불가", systemImage: "lock")
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
                    description: Text("수면 · 식사 · 운동처럼 협상 불가능한 시간을 먼저 확보하세요.")
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
            entries.append((blockStart[id] ?? b.sortHour, 1, .block(b)))
        }

        // 시각 같으면 고정 → 블록 → 쿼터 순으로 안정 정렬.
        return entries
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.rank < $1.rank }
            .map(\.item)
    }

    private var dayTimelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timelineWindow.isFullDay
                     ? "요일별 하루 24시간"
                     : "요일별 하루 \(Int(timelineWindow.start))–\(Int(timelineWindow.end))시")
                    .font(.headline)
                if !timelineWindow.isFullDay {
                    Text("수면 시간 숨김")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("실선=고정 · 점선=유연 쿼터 · 계획은 빈 구간에")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                        window: timelineWindow
                    )
                }
            }
        }
    }

    private var weekGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("이번 주 계획", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Legend()
            }

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

    private func dropBacklogItem(token: String, day: DayOfWeek) {
        if token.hasPrefix("block:") {
            // 이미 계획에 올린 블록을 다른 요일로 이동 (같은 주 안에서 요일만 변경).
            let idStr = String(token.dropFirst("block:".count))
            guard let blk = allBlocks.first(where: { String(describing: $0.persistentModelID) == idStr }) else { return }
            if blk.day != day {
                blk.day = day
                try? context.save()
            }
            return
        }
        if token.hasPrefix("routine:") {
            let name = String(token.dropFirst("routine:".count))
            guard let routine = routines.first(where: { $0.name == name }) else { return }
            let block = PlanBlock(
                day: day,
                timeBand: timeBand(for: routine.kind == .fixed ? routine.startHour : 12),
                durationHours: routine.kind == .fixed ? routine.durationHours : 1,
                title: routine.name,
                successCriteria: "",
                deliverable: "",
                weekStartDate: selectedWeek,
                concreteVerified: false
            )
            context.insert(block)
        } else {
            guard let item = backlogItems.first(where: { $0.dragToken == token }) else { return }
            // 전파 계약이 붙은 항목은 배치하면 백로그에서 사라지므로 먼저 확인을 받는다.
            // (계약은 블록으로 승계되지만, 백로그에서 찾을 수 없게 되는 건 알려야 한다)
            if item.needsBroadcast {
                pendingBroadcastDrop = BroadcastDropContext(item: item, day: day)
                return
            }
            convertBacklogItem(item, to: day)
        }
        try? context.save()
    }

    /// 백로그 항목 → 계획 블록. 전파 계약을 그대로 승계한다.
    ///
    /// 단계로 쪼갠 할 일은 **지금 할 단계 하나만** 요일에 올리고 항목은 백로그에 남긴다.
    /// 남은 단계가 여전히 할 일이기 때문이다. 단계가 없는 할 일은 종전대로
    /// 통째로 옮겨지고(백로그에서 사라지고) 블록이 그 자리를 대신한다.
    private func convertBacklogItem(_ item: BacklogItem, to day: DayOfWeek) {
        let tree = TodoTree(backlogItems)
        let step = tree.hasChildren(item) ? tree.currentStep(of: item) : nil

        let block = PlanBlock(
            day: day,
            timeBand: TimelineLayout.suggestedBand(
                routines: fixedRoutines(on: day),
                blocks: weekBlocks.filter { $0.day == day }
            ),
            durationHours: step?.durationHours ?? item.durationHours,
            title: step.map { "\(item.title) · \($0.title)" } ?? item.title,
            successCriteria: "",
            deliverable: "",
            weekStartDate: selectedWeek,
            concreteVerified: false
        )
        // 대상·두 날짜·넘길 형태·이미 보낸 시점까지 통째로 넘긴다.
        // 보낸 기록을 빼먹으면 이미 보낸 전파를 다시 보내라고 뜬다.
        item.copyBroadcastContract(to: block)
        context.insert(block)
        if step == nil { context.delete(item) }
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

    private func seedDefaultsIfNeeded() {
        guard routines.isEmpty else { return }
        let defaults: [Routine] = [
            Routine(name: "수면", iconName: "moon.fill", kind: .fixed, colorName: "indigo",
                    dayMask: 0b1111111, startHour: 23, durationHours: 8, sortIndex: 0),
            Routine(name: "식사", iconName: "fork.knife", kind: .quota, colorName: "green",
                    weeklyHours: 17.5, sessionsPerDay: 3, sortIndex: 1),
            Routine(name: "운동", iconName: "figure.run", kind: .fixed, colorName: "orange",
                    dayMask: 0b0110101, startHour: 7.5, durationHours: 1, sortIndex: 2),
        ]
        for r in defaults { context.insert(r) }
        try? context.save()
    }

    private func addSampleData() {
        seedDefaultsIfNeeded()  // 루틴이 비어 있으면 기본 루틴 먼저

        let base = backlogItems.map(\.sortIndex).max() ?? -1
        let samples: [(String, Double)] = [
            ("기획서 초안 작성", 2),
            ("논문 1편 정독", 1.5),
            ("주간 회고 정리", 0.5),
        ]
        for (i, s) in samples.enumerated() {
            context.insert(BacklogItem(title: s.0, durationHours: s.1, sortIndex: base + 1 + i, weekStartDate: selectedWeek))
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
        for i in backlogItems { context.delete(i) }
        for o in allOccurrences { context.delete(o) }
        try? context.save()
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

/// 전파 계약이 붙은 백로그 항목을 요일에 떨어뜨렸을 때, 확인을 받는 동안 붙잡아 두는 값.
struct BroadcastDropContext: Identifiable {
    let id = UUID()
    let item: BacklogItem
    let day: DayOfWeek
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
