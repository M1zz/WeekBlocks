import SwiftUI
import SwiftData
import TipKit

struct BacklogSection: View {
    @Environment(\.modelContext) private var context

    let allItems: [BacklogItem]
    let weekStart: Date
    /// 고정 루틴이 확보돼 있을 때만 할 일을 작성할 수 있다.
    var canPlan: Bool = true

    @Query(sort: [SortDescriptor(\BacklogCategory.sortIndex), SortDescriptor(\BacklogCategory.createdAt)])
    private var categories: [BacklogCategory]

    @AppStorage("didSeedBacklogCategories") private var didSeedCategories = false
    /// 전파 카테고리는 기본값 시딩보다 나중에 생겼으므로 별도 플래그로 한 번 보강한다.
    @AppStorage("didSeedBroadcastCategory") private var didSeedBroadcastCategory = false

    @State private var filterCategoryID: String? = nil   // nil = 전체
    @State private var showingComposer = false
    @State private var showingAllBacklog = false
    /// 전파 필요 항목만 보기.
    @State private var broadcastOnly = false
    @State private var contractSheetItem: BacklogItem?
    /// 단계(뎁스)를 들여다보는 시트.
    @State private var stepsSheetItem: BacklogItem?

    private let cal = Calendar(identifier: .iso8601)

    /// 할 일의 단계(뎁스) 계산기. iOS와 같은 로직(TodoTree.swift)을 쓴다.
    private var tree: TodoTree { TodoTree(allItems) }

    /// 아직 안 한 할 일 **전부**. 주를 옮겨도 목록에서 사라지지 않는다.
    /// (해야 할 일이 보이는 주에 따라 나타났다 사라지면 빠뜨리게 된다)
    /// iOS Todo에서 완료 처리한 항목만 제외.
    /// 단계는 자기 카드를 갖지 않으므로 최상위 할 일만 세운다.
    private var weekItems: [BacklogItem] {
        let tree = self.tree
        return tree.roots.filter { !$0.isCompleted }.sorted { a, b in
            // 성질이 첫 번째 키다 — iOS 목록의 띠 순서를 카드 순서로 옮긴 것.
            //   바로 하면 되는 일 → 그냥 하면 되는 것 → 시간을 잡은 일
            let (la, lb) = (tree.lane(of: a), tree.lane(of: b))
            if la != lb { return la < lb }
            let (ba, bb) = (weekBucket(a), weekBucket(b))
            if ba != bb { return ba < bb }
            // 같은 묶음 안에서는 주차순 → 원래 정렬(sortIndex, createdAt) 유지.
            if !cal.isDate(a.weekStartDate, inSameDayAs: b.weekStartDate) {
                return a.weekStartDate < b.weekStartDate
            }
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt < b.createdAt
        }
    }

    /// 표시 순서 묶음: 보고 있는 주 → 지난 주(이월) → 앞으로.
    /// 이월을 두 번째에 두는 이유는 이미 밀린 일이라 눈에서 사라지면 안 되기 때문이다.
    private func weekBucket(_ item: BacklogItem) -> Int {
        if cal.isDate(item.weekStartDate, inSameDayAs: weekStart) { return 0 }
        return item.weekStartDate < weekStart ? 1 : 2
    }

    private var filteredItems: [BacklogItem] {
        var items = weekItems
        if let f = filterCategoryID { items = items.filter { $0.categoryID == f } }
        if broadcastOnly { items = items.filter { $0.needsBroadcast } }
        return items
    }

    /// 전파 필요 항목 수 (필터 칩 배지).
    private var broadcastCount: Int {
        weekItems.filter { $0.needsBroadcast }.count
    }


    /// 이번 주보다 과거 주에 남아 있는(못 한) 백로그 수.
    private var carryoverCount: Int {
        allItems.filter { !$0.isCompleted && $0.weekStartDate < weekStart && !cal.isDate($0.weekStartDate, inSameDayAs: weekStart) }.count
    }

    /// 항목별 색상: 카테고리가 있으면 카테고리 색(같은 카테고리=같은 색),
    /// 없으면 카테고리가 안 쓰는 팔레트에서 겹치지 않게 고유 색을 배정.
    private var itemColorMap: [String: Color] {
        let usedCategoryColors = Set(categories.map(\.colorName))
        let freePool = Rainbow.spectrum.filter { !usedCategoryColors.contains($0.name) }
        let palette = (freePool.isEmpty ? Rainbow.spectrum : freePool).map { Color(hex: $0.hex) ?? .accentColor }

        var map: [String: Color] = [:]
        var i = 0
        for item in weekItems {
            if let cid = item.categoryID, let cat = categories.first(where: { $0.uuid == cid }) {
                map[item.dragToken] = cat.displayColor
            } else if !palette.isEmpty {
                map[item.dragToken] = palette[i % palette.count]
                i += 1
            } else {
                map[item.dragToken] = .secondary
            }
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("백로그")
                    .font(.headline)
                if !weekItems.isEmpty {
                    Text("\(filteredItems.count)개 · \(formatDuration(filteredItems.reduce(0) { $0 + $1.durationHours }))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    showingAllBacklog = true
                } label: {
                    Text(carryoverCount > 0 ? "전체 백로그 (이월 \(carryoverCount))" : "전체 백로그")
                }
                .buttonStyle(.borderless)

                Button("할 일 작성") { showingComposer = true }
                    .buttonStyle(.borderless)
                    .disabled(!canPlan)
            }

            // 카테고리 필터 칩
            if !categories.isEmpty && canPlan {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(label: "전체", color: .secondary,
                                   selected: filterCategoryID == nil) { filterCategoryID = nil }
                        ForEach(categories) { c in
                            FilterChip(label: c.name, color: c.displayColor,
                                       selected: filterCategoryID == c.uuid) {
                                filterCategoryID = (filterCategoryID == c.uuid) ? nil : c.uuid
                            }
                        }
                        if broadcastCount > 0 {
                            // 카테고리 칩의 점은 카테고리 색(사용자가 고른 정체성)이지만
                            // 이건 상태 필터라 색으로 의미를 만들지 않는다.
                            FilterChip(label: "전파 \(broadcastCount)", color: .secondary,
                                       selected: broadcastOnly) { broadcastOnly.toggle() }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if !canPlan {
                lockedNotice
            } else if filteredItems.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(filteredItems) { item in
                        BacklogBlock(
                            item: item,
                            categories: categories,
                            tint: itemColorMap[item.dragToken] ?? .secondary,
                            lane: tree.lane(of: item),
                            weekNote: weekNote(for: item),
                            steps: stepsInfo(for: item),
                            onAdvance: { advance(item) },
                            onRewind: { rewind(item) },
                            onEditSteps: { stepsSheetItem = item },
                            // 단계까지 통째로 지운다.
                            onDelete: {
                                for node in tree.subtree(of: item) { context.delete(node) }
                                try? context.save()
                            },
                            onSetCategory: { id in
                                item.categoryID = id
                                // 전파 카테고리로 옮기면 전파 필요를 켜고 계약을 받으러 간다.
                                if let bc = categories.broadcastCategory, id == bc.uuid, !item.needsBroadcast {
                                    item.needsBroadcast = true
                                    try? context.save()
                                    contractSheetItem = item
                                    return
                                }
                                try? context.save()
                            },
                            onOpenBroadcastContract: {
                                if !item.needsBroadcast {
                                    item.needsBroadcast = true
                                    try? context.save()
                                }
                                contractSheetItem = item
                            },
                            onClearBroadcast: {
                                item.needsBroadcast = false
                                item.broadcastContractVerified = false
                                try? context.save()
                            },
                            onToggleNow: { toggleNow(item) }
                        )
                    }
                }
            }
        }
        .task { await reconcileCategories() }
        .sheet(isPresented: $showingComposer) {
            BacklogComposerView(weekStart: weekStart)
                .frame(minWidth: 540, minHeight: 560)
        }
        .sheet(isPresented: $showingAllBacklog) {
            AllBacklogView(currentWeek: weekStart)
                .frame(minWidth: 560, minHeight: 600)
        }
        .sheet(item: $contractSheetItem) { item in
            BroadcastContractView(item: item)
                .frame(minWidth: 560, minHeight: 640)
        }
        .sheet(item: $stepsSheetItem) { item in
            TodoStepsView(root: item)
        }
    }

    /// 카드에 그릴 단계 요약. 단계가 없으면 nil.
    private func stepsInfo(for item: BacklogItem) -> BacklogBlock.StepsInfo? {
        let tree = self.tree
        guard tree.hasChildren(item) else { return nil }
        // 표시해 둔 단계가 있으면 그것을 세운다. 차례를 기다리지 않는 것이
        // '바로 하면 되는 일'로 표시해 둔 뜻이다 (iOS 목록·위젯과 같은 규칙).
        let marked = tree.markedStep(of: item)
        return BacklogBlock.StepsInfo(
            currentTitle: (marked ?? tree.currentStep(of: item))?.title,
            isMarked: marked != nil,
            progress: tree.progress(of: item),
            count: tree.leafCount(of: item),
            number: tree.currentStepNumber(of: item),
            totalHours: tree.totalHours(of: item),
            canRewind: tree.lastDoneStep(of: item) != nil
        )
    }

    /// 지금 할 단계를 끝내고 다음 단계로 넘긴다.
    private func advance(_ item: BacklogItem) {
        let tree = self.tree
        withAnimation {
            // 표시해 둔 단계를 세워 뒀으면 끝나는 것도 그 단계여야 한다.
            if let marked = tree.markedStep(of: item), tree.hasChildren(item) {
                tree.setCompleted(marked, true)
            } else {
                tree.advance(item)
            }
            try? context.save()
        }
    }

    /// '바로 하면 되는 일' 표시를 켜고 끈다. 표시는 **그 줄 자체**에 붙는다 —
    /// 쪼갠 일이면 지금 세워져 있는 단계에. (iOS와 같은 규칙)
    private func toggleNow(_ item: BacklogItem) {
        let tree = self.tree
        let target = tree.markedStep(of: item)
            ?? (tree.hasChildren(item) ? tree.currentStep(of: item) : item)
        guard let target else { return }
        let on = !target.isMarkedNow
        withAnimation {
            target.setFragmentAnswer(on ? true : nil, for: .start)
            target.setFragmentAnswer(on ? true : nil, for: .closing)
            try? context.save()
        }
    }

    /// 마지막으로 끝낸 단계를 되돌린다.
    private func rewind(_ item: BacklogItem) {
        withAnimation {
            tree.rewind(item)
            try? context.save()
        }
    }

    /// 보고 있는 주가 아닌 항목에만 붙는 주차 표시 ("2주 전" 같은 상대 표기).
    /// 전부 보여주면서도 어느 주에 계획한 일인지는 잃지 않게 한다.
    private func weekNote(for item: BacklogItem) -> String? {
        guard !cal.isDate(item.weekStartDate, inSameDayAs: weekStart) else { return nil }
        let days = cal.dateComponents([.day], from: weekStart, to: item.weekStartDate).day ?? 0
        let offset = Int((Double(days) / 7).rounded())
        switch offset {
        case -1: return "지난 주"
        case 1: return "다음 주"
        case let n where n < -1: return "\(-n)주 전"
        default: return "\(offset)주 후"
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Text(weekItems.isEmpty
                 ? "할 일이 아직 없습니다."
                 : "이 카테고리엔 할 일이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if weekItems.isEmpty {
                Button("할 일 작성") { showingComposer = true }
                    .buttonStyle(.borderless)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var lockedNotice: some View {
        HStack(spacing: 8) {
            Text("고정 루틴을 먼저 추가하면 할 일을 계획할 수 있습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func reconcileCategories() async {
        // CloudKit 동기화가 아직 기존 카테고리를 내려받기 전이면 categories가
        // 비어 보여서 기본값이 중복 시딩된다. 초기 임포트가 정착할 시간을 잠깐 준다.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // (A) 같은 이름의 중복 카테고리를 하나로 합친다.
        //     (과거 동기화 경쟁으로 생긴 "업무 업무 / 개인 개인" 정리)
        dedupeCategoriesByName()

        // (B) 정말로 카테고리가 하나도 없을 때만, 그리고 한 번만 기본값을 넣는다.
        seedDefaultCategoriesIfNeeded()

        // (C) 전파 카테고리 보강 — 기본값 시딩을 이미 끝낸 기존 설치에도 한 번은 들어가야 한다.
        //     (B) 다음에 둬서 목록 맨 뒤에 붙는다. 이름이 아니라 플래그로 판별하므로
        //     사용자가 이름을 바꿔도 다시 만들어지지 않는다.
        seedBroadcastCategoryIfNeeded()
    }

    private func seedDefaultCategoriesIfNeeded() {
        guard !didSeedCategories, categories.isEmpty else { return }
        didSeedCategories = true
        let defaults: [(String, String, String)] = [
            ("업무", "blue", "briefcase"),
            ("개인", "green", "person"),
            ("건강", "orange", "heart"),
            ("학습", "purple", "book"),
        ]
        var existingNames = Set(categories.map { $0.name.trimmingCharacters(in: .whitespaces) })
        for (i, d) in defaults.enumerated() where !existingNames.contains(d.0) {
            context.insert(BacklogCategory(name: d.0, colorName: d.1, iconName: d.2, sortIndex: i))
            existingNames.insert(d.0)
        }
        try? context.save()
    }

    /// 전파 카테고리를 기본으로 하나 만들어 둔다.
    /// 이 카테고리로 지정하면 전파 필요가 자동으로 켜지므로, 안테나 토글을 몰라도 전파 흐름에 들어온다.
    ///
    /// `categories`(@Query)는 방금 insert한 기본값을 아직 반영하지 않으므로 직접 fetch한다.
    /// 안 그러면 sortIndex가 업무와 겹쳐 목록 순서가 뒤섞인다.
    private func seedBroadcastCategoryIfNeeded() {
        guard !didSeedBroadcastCategory else { return }
        let existing = (try? context.fetch(FetchDescriptor<BacklogCategory>())) ?? []
        didSeedBroadcastCategory = true
        // 이미 플래그가 붙은 게 있으면(동기화로 내려왔거나 직접 지정한 경우) 다시 만들지 않는다.
        guard existing.broadcastCategory == nil else { return }
        let sortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        context.insert(BacklogCategory(name: "전파",
                                       colorName: "indigo",
                                       iconName: "antenna.radiowaves.left.and.right",
                                       sortIndex: sortIndex,
                                       isBroadcast: true))
        try? context.save()
    }

    /// 이름이 같은 카테고리를 가장 먼저 만들어진 하나로 합치고,
    /// 나머지를 쓰던 항목은 살아남은 카테고리로 재연결한 뒤 중복을 삭제한다.
    private func dedupeCategoriesByName() {
        var survivors: [String: BacklogCategory] = [:]   // 이름(정규화) → 살아남을 카테고리
        var duplicates: [BacklogCategory] = []
        // createdAt 오름차순으로 훑으며 각 이름의 첫 번째를 살린다.
        for c in categories.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = c.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            if survivors[key] == nil {
                survivors[key] = c
            } else {
                duplicates.append(c)
            }
        }
        guard !duplicates.isEmpty else { return }

        for dup in duplicates {
            let key = dup.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let keep = survivors[key] else { continue }
            // 중복 카테고리를 참조하던 항목을 살아남은 카테고리로 옮긴다.
            for item in allItems where item.categoryID == dup.uuid {
                item.categoryID = keep.uuid
            }
            // 전파 플래그는 합칠 때 잃지 않는다 (사라지면 자동 전파 연결이 끊긴다).
            if dup.isBroadcast { keep.isBroadcast = true }
            context.delete(dup)
        }
        try? context.save()
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                color.opacity(selected ? 0.22 : 0.0),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(color.opacity(selected ? 0.55 : 0.25), lineWidth: selected ? 1 : 0.5)
            )
            .foregroundStyle(selected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

/// 드래그해서 요일에 떨어뜨리기 좋은 백로그 블록(카드).
struct BacklogBlock: View {
    /// 할 일 안의 단계(뎁스) 요약. 단계가 없는 할 일이면 nil.
    struct StepsInfo {
        /// 지금 해야 할 단계. 전부 끝났으면 nil.
        /// 사용자가 '바로 하면 되는 일'로 표시해 둔 단계가 있으면 차례를 건너뛰고 그것이 온다.
        let currentTitle: String?
        /// 위 단계가 표시해 둔 것인가 (차례를 건너뛰고 세운 단계).
        var isMarked: Bool = false
        let progress: Double
        let count: Int
        /// 몇 번째 단계인지 (1부터). 전부 끝났으면 nil.
        let number: Int?
        let totalHours: Double
        let canRewind: Bool
    }

    let item: BacklogItem
    let categories: [BacklogCategory]
    let tint: Color
    /// 이 카드가 어느 자리에 서는가. 배경색이 여기서 나온다 (iOS 목록의 띠와 같은 규칙).
    var lane: TodoTree.Lane = .planned
    /// 보고 있는 주가 아닐 때 붙는 표시 ("지난 주", "2주 전"). 같은 주면 nil.
    var weekNote: String? = nil
    var steps: StepsInfo? = nil
    /// 지금 할 단계를 끝내고 다음으로 넘기기.
    var onAdvance: () -> Void = { }
    /// 마지막으로 끝낸 단계 되돌리기.
    var onRewind: () -> Void = { }
    /// 단계 시트 열기.
    var onEditSteps: () -> Void = { }
    let onDelete: () -> Void
    let onSetCategory: (String?) -> Void
    /// 전파 계약 시트를 열어달라는 요청.
    var onOpenBroadcastContract: () -> Void = { }
    /// 전파 필요 체크 해제.
    var onClearBroadcast: () -> Void = { }
    /// '바로 하면 되는 일' 표시를 켜고 끈다.
    var onToggleNow: () -> Void = { }

    @State private var hovering = false

    private var category: BacklogCategory? { categories.first { $0.uuid == item.categoryID } }

    /// 카드에는 전파 항목이라는 사실과 급한지 여부만. 어느 시점을 언제 보내는지는
    /// '전파 필요' 섹션이 온전히 보여주므로 여기서 반복하지 않는다.
    /// 색을 쓰지 않으므로 급한 정도는 문구 자체가 말한다.
    private var broadcastMark: String? {
        guard item.needsBroadcast else { return nil }
        if !item.broadcastContractVerified { return "전파 · 계약 미확정" }
        guard let next = item.nextBroadcastCheckpoint else { return "전파 완료" }
        let d = BroadcastPlanner.dayCount(from: Date(), to: next.date)
        if d < 0 { return "전파 지남" }
        if d == 0 { return "전파 오늘" }
        return "전파 D-\(d)"
    }

    private var broadcastHelp: String {
        guard item.needsBroadcast, item.broadcastContractVerified, let next = item.nextBroadcastCheckpoint else {
            return "드래그해서 요일에 배치"
        }
        let who = item.broadcastRecipient.isEmpty ? item.broadcastAudience.shortLabel : item.broadcastRecipient
        return "\(BroadcastPlanner.dateLabel(next.date)) — \(who)에게 \(next.kind.label)"
    }

    /// '바로 하면 되는 일'의 색. iOS와 같은 연두다.
    static let nowGreen = Color(hue: 0.26, saturation: 0.72, brightness: 0.66)

    /// 카드 배경. 성질이 곧 색이다.
    ///   바로 하면 되는 일 → 연두, 그냥 하면 되는 것 → 회색, 나머지 → 카테고리 색.
    private var laneBackground: Color {
        switch lane {
        case .now:     return Self.nowGreen.opacity(0.18)
        case .errand:  return Color.secondary.opacity(0.09)
        case .planned: return tint.opacity(0.10)
        }
    }

    private var laneBorder: Color {
        switch lane {
        case .now:     return Self.nowGreen.opacity(0.45)
        case .errand:  return Color.secondary.opacity(0.25)
        case .planned: return tint.opacity(0.30)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let steps {
                    // 단계가 있는 할 일은 '지금 할 단계'가 곧 지금 해야 하는 일이다.
                    Button(action: onAdvance) {
                        HStack(spacing: 4) {
                            // 표시해 둔 단계는 원 안의 번개로 — 색만으로는 흑백에서 사라진다.
                            Image(systemName: steps.currentTitle == nil
                                  ? "checkmark.circle.fill"
                                  : (steps.isMarked ? "bolt.circle" : "arrowtriangle.right.circle.fill"))
                                .font(.system(size: 13))
                                .foregroundStyle(steps.currentTitle == nil
                                                 ? Color.green
                                                 : (steps.isMarked ? Self.nowGreen : Color.orange))
                            Text(steps.currentTitle ?? "모든 단계 완료")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(steps.currentTitle == nil ? "모든 단계를 마쳤습니다" : "이 단계를 끝내고 다음으로 넘기기")

                    // 진행바만 남긴다. 퍼센트와 "3단계 중 2"는 같은 말을 글씨로 되풀이했다.
                    ProgressView(value: steps.progress)
                        .tint(steps.progress >= 1 ? .green : tint)
                        .frame(maxWidth: 110)
                }

                // 카드 아래 줄은 '얼마짜리인가'와 곁다리 표시만. 시간은 칩 하나로 말한다 —
                // 단계가 있으면 이 카드를 끌어다 놓을 때 잡히는 건 전체 시간이라 그걸 쓴다.
                HStack(spacing: 6) {
                    if lane == .now, steps == nil {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Self.nowGreen)
                    }
                    Text(formatDuration(steps?.totalHours ?? item.durationHours))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if let category {
                        Text(category.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                    if let weekNote {
                        Text(weekNote)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let broadcastMark {
                        Text(broadcastMark)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }

            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(laneBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(laneBorder, lineWidth: 0.6))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(item.dragToken)
        .onHover { hovering = $0 }
        .help(broadcastHelp)
        .contextMenu {
            Button(steps == nil ? "단계로 쪼개기…" : "단계 보기·편집…", action: onEditSteps)
            Button(lane == .now ? "'바로' 표시 거두기" : "바로 하면 되는 일로 표시",
                   action: onToggleNow)
            if let steps {
                if steps.currentTitle != nil {
                    Button("지금 단계 끝내기", action: onAdvance)
                }
                if steps.canRewind {
                    Button("이전 단계로 되돌리기", action: onRewind)
                }
            }
            Divider()
            if item.needsBroadcast {
                Button(item.broadcastContractVerified ? "전파 계약 열기" : "전파 계약 마치기",
                       action: onOpenBroadcastContract)
                Button("전파 필요 해제", action: onClearBroadcast)
            } else {
                Button("전파 필요로 체크", action: onOpenBroadcastContract)
            }
            Divider()
            Menu("카테고리 지정") {
                Button {
                    onSetCategory(nil)
                } label: {
                    Label("미분류", systemImage: item.categoryID == nil ? "checkmark" : "circle")
                }
                Divider()
                ForEach(categories) { c in
                    Button {
                        onSetCategory(c.uuid)
                    } label: {
                        Label(c.name, systemImage: item.categoryID == c.uuid ? "checkmark" : "")
                    }
                }
            }
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - 할 일 작성 (TODO 리스트 방식)
//
// 새 항목은 보고 있는 주에 들어가지만, 목록은 백로그와 같이 **전부** 보여준다.
// 백로그에 보이는데 여기서 편집할 수 없으면 손댈 방법이 없어진다.

struct BacklogComposerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let weekStart: Date

    @Query(sort: [SortDescriptor(\BacklogItem.sortIndex), SortDescriptor(\BacklogItem.createdAt)])
    private var allItems: [BacklogItem]
    @Query(sort: [SortDescriptor(\BacklogCategory.sortIndex), SortDescriptor(\BacklogCategory.createdAt)])
    private var categories: [BacklogCategory]

    @State private var newTitle = ""
    @State private var defaultCategoryID: String? = nil
    /// 적으면서 고르는 라벨 = 예상 시간. 고르기 전에는 추가할 수 없다.
    @State private var showingCategoryManager = false
    @FocusState private var focused: Bool

    private let cal = Calendar(identifier: .iso8601)

    /// 아직 안 한 할 일 전부 (백로그와 같은 범위). 보고 있는 주가 위로 온다.
    /// 단계는 부모 안에서만 보이므로 최상위만 세운다.
    private var weekItems: [BacklogItem] {
        TodoTree(allItems).roots.filter { !$0.isCompleted }.sorted { a, b in
            let (ba, bb) = (bucket(a), bucket(b))
            if ba != bb { return ba < bb }
            if !cal.isDate(a.weekStartDate, inSameDayAs: b.weekStartDate) {
                return a.weekStartDate < b.weekStartDate
            }
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt < b.createdAt
        }
    }

    private func bucket(_ item: BacklogItem) -> Int {
        if cal.isDate(item.weekStartDate, inSameDayAs: weekStart) { return 0 }
        return item.weekStartDate < weekStart ? 1 : 2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("할 일").font(.title3.weight(.medium))
                    Text("입력하고 Enter ↵ 로 계속 추가")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("카테고리") { showingCategoryManager = true }
                    .buttonStyle(.borderless)
            }
            .padding(20)

            Divider()

            // TODO 방식 입력 줄 — 제목 입력 후 Enter 로 즉시 추가, 포커스 유지
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    categoryDefaultMenu
                    TextField("할 일 입력 후 Enter", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit(addAndContinue)
                    Button("추가", action: addAndContinue)
                        .buttonStyle(.borderless)
                        .disabled(!canAdd)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if weekItems.isEmpty {
                Spacer()
                Text("아직 할 일이 없습니다. 위에 입력해 추가하세요.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(weekItems) { item in
                            ComposerItemRow(item: item, categories: categories) {
                                context.delete(item); try? context.save()
                            }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Text("\(weekItems.count)개 · 합계 \(formatDuration(weekItems.reduce(0) { $0 + $1.durationHours }))")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()
                Button("완료") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .onAppear { focused = true }
        .sheet(isPresented: $showingCategoryManager) {
            CategoryManagerView().frame(minWidth: 440, minHeight: 460)
        }
    }

    private var categoryDefaultMenu: some View {
        let current = categories.first { $0.uuid == defaultCategoryID }
        return Menu {
            Button { defaultCategoryID = nil } label: {
                Label("미분류", systemImage: defaultCategoryID == nil ? "checkmark" : "circle")
            }
            Divider()
            ForEach(categories) { c in
                Button { defaultCategoryID = c.uuid } label: {
                    Label(c.name, systemImage: defaultCategoryID == c.uuid ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(current?.displayColor ?? Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                Text(current?.name ?? "미분류").font(.callout)
                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("새 항목의 기본 카테고리")
    }

    /// 이름만 있으면 추가된다. 시간은 나중에 줄에서 고친다.
    private var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addAndContinue() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let maxIndex = allItems.map(\.sortIndex).max() ?? -1
        let item = BacklogItem(title: t, durationHours: TodoTree.defaultStepHours,
                               sortIndex: maxIndex + 1,
                               categoryID: defaultCategoryID, weekStartDate: weekStart)
        // 전파 카테고리로 넣은 항목은 곧바로 전파 필요가 된다.
        // 계약은 아직 미확정 상태로 남아 '전파 예정' 섹션에서 계속 눈에 띈다.
        if let broadcast = categories.broadcastCategory, defaultCategoryID == broadcast.uuid {
            item.needsBroadcast = true
        }
        context.insert(item)
        try? context.save()
        newTitle = ""
        focused = true
    }
}

struct ComposerItemRow: View {
    @Bindable var item: BacklogItem
    let categories: [BacklogCategory]
    @Environment(\.modelContext) private var context
    @Query private var allItems: [BacklogItem]
    let onDelete: () -> Void

    @State private var showingContract = false

    private var category: BacklogCategory? { categories.first { $0.uuid == item.categoryID } }

    var body: some View {
        HStack(spacing: 10) {
            categoryMenu

            TextField("할 일", text: $item.title)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

            broadcastToggle


            HStack(spacing: 2) {
                TextField("", value: hoursBinding, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 38)
                    .multilineTextAlignment(.trailing)
                Text("h").font(.callout).foregroundStyle(.secondary)
            }
            Stepper("", value: hoursBinding, in: 0.25...12, step: 0.25)
                .labelsHidden()

            Button("삭제", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: item.title) { _, _ in try? context.save() }
        .sheet(isPresented: $showingContract) {
            BroadcastContractView(item: item)
                .frame(minWidth: 560, minHeight: 640)
        }
    }

    /// 이 할 일에 걸리는 시간. 단계가 있으면 그 합이라 여기서는 손대지 않는다.
    private var hoursBinding: Binding<Double> {
        Binding(get: { item.durationHours },
                set: { value in
                    guard !TodoTree(allItems).hasChildren(item) else { return }
                    item.durationHours = max(0, value)
                    try? context.save()
                })
    }

    /// 카테고리 지정. 전파 카테고리면 전파 필요를 켜고 계약 시트로 바로 넘긴다.
    /// 전파 카테고리에서 빼는 건 전파 필요 해제와 다른 동작이므로 계약을 지우지 않는다.
    private func assign(_ category: BacklogCategory) {
        item.categoryID = category.uuid
        if category.isBroadcast && !item.needsBroadcast {
            item.needsBroadcast = true
            try? context.save()
            showingContract = true
            return
        }
        try? context.save()
    }

    /// 전파 필요 체크. 켜는 순간 일반 항목과 다른 전처리(전파 계약)로 들어간다.
    private var broadcastToggle: some View {
        Button {
            if !item.needsBroadcast {
                item.needsBroadcast = true
                try? context.save()
            }
            showingContract = true
        } label: {
            Text(item.needsBroadcast
                 ? (item.broadcastContractVerified ? "전파" : "전파 · 미확정")
                 : "전파 안 함")
                .font(.system(size: 13))
                .foregroundStyle(item.needsBroadcast ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .help(item.needsBroadcast
              ? (item.broadcastContractVerified ? "전파 계약 확정됨 — 열어서 확인" : "전파 계약 미확정")
              : "전파 필요로 체크")
    }

    private var categoryMenu: some View {
        Menu {
            Button { item.categoryID = nil; try? context.save() } label: {
                Label("미분류", systemImage: item.categoryID == nil ? "checkmark" : "circle")
            }
            Divider()
            ForEach(categories) { c in
                Button { assign(c) } label: {
                    Label(c.name, systemImage: item.categoryID == c.uuid ? "checkmark" : "")
                }
            }
        } label: {
            Circle()
                .fill(category?.displayColor ?? Color.secondary.opacity(0.4))
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(category?.name ?? "미분류")
    }
}

// MARK: - 전체 백로그 (지난 주 포함)

struct AllBacklogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let currentWeek: Date

    @Query(sort: [SortDescriptor(\BacklogItem.weekStartDate, order: .reverse), SortDescriptor(\BacklogItem.sortIndex)])
    private var allItems: [BacklogItem]
    @Query(sort: [SortDescriptor(\BacklogCategory.sortIndex), SortDescriptor(\BacklogCategory.createdAt)])
    private var categories: [BacklogCategory]

    private let cal = Calendar(identifier: .iso8601)

    private var tree: TodoTree { TodoTree(allItems) }

    /// 최상위 할 일만 (단계는 부모 안에서 본다). 정렬은 @Query 순서를 그대로 쓴다.
    private var rootItems: [BacklogItem] {
        let roots = Set(tree.roots.map(\.dragToken))
        return allItems.filter { roots.contains($0.dragToken) }
    }

    /// 항목이 존재하는 주들 (최신 주 우선).
    private var weeks: [Date] {
        var seen = Set<Date>(); var result: [Date] = []
        for it in rootItems where !seen.contains(it.weekStartDate) {
            seen.insert(it.weekStartDate); result.append(it.weekStartDate)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("전체 백로그").font(.title2.weight(.semibold))
                    Text("지난 주에 못 한 항목을 이번 주로 가져올 수 있습니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("완료") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            if rootItems.isEmpty {
                Spacer()
                Text("백로그가 비어 있습니다.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(weeks, id: \.self) { week in
                            let items = rootItems.filter { cal.isDate($0.weekStartDate, inSameDayAs: week) }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(weekLabel(week))
                                        .font(.headline)
                                        .foregroundStyle(isCurrent(week) ? Color.red : .primary)
                                    Text("\(items.count)개").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("합계 \(formatDuration(items.reduce(0) { $0 + tree.totalHours(of: $1) }))")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                                ForEach(items) { item in
                                    AllBacklogRow(
                                        item: item,
                                        categories: categories,
                                        isCurrentWeek: isCurrent(week),
                                        onCarry: {
                                            for node in tree.subtree(of: item) { node.weekStartDate = currentWeek }
                                            try? context.save()
                                        },
                                        onDelete: {
                                            for node in tree.subtree(of: item) { context.delete(node) }
                                            try? context.save()
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func isCurrent(_ w: Date) -> Bool { cal.isDate(w, inSameDayAs: currentWeek) }

    private func weekLabel(_ week: Date) -> String {
        let days = cal.dateComponents([.day], from: currentWeek, to: week).day ?? 0
        let offset = Int((Double(days) / 7).rounded())
        let f = DateFormatter(); f.dateFormat = "M월 d일"
        let end = cal.date(byAdding: .day, value: 6, to: week) ?? week
        let range = "\(f.string(from: week))–\(f.string(from: end))"
        let rel: String
        switch offset {
        case 0: rel = "이번 주"
        case -1: rel = "지난 주"
        case 1: rel = "다음 주"
        case let n where n < 0: rel = "\(-n)주 전"
        default: rel = "\(offset)주 후"
        }
        return "\(rel) · \(range)"
    }
}

struct AllBacklogRow: View {
    let item: BacklogItem
    let categories: [BacklogCategory]
    let isCurrentWeek: Bool
    let onCarry: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    private var category: BacklogCategory? { categories.first { $0.uuid == item.categoryID } }

    var body: some View {
        HStack(spacing: 8) {
            if let c = category {
                Circle().fill(c.displayColor).frame(width: 7, height: 7)
            }
            Text(item.title)
                .font(.system(size: 15))
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1fh", item.durationHours))
                .font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()

            if !isCurrentWeek && !item.isCompleted {
                Button("이번 주로", action: onCarry)
                    .buttonStyle(.borderless)
                .font(.caption)
                .help("이 항목을 이번 주 백로그로 가져옵니다")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .onHover { hovering = $0 }
    }
}

// MARK: - Category Manager

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BacklogCategory.sortIndex), SortDescriptor(\BacklogCategory.createdAt)])
    private var categories: [BacklogCategory]
    @Query private var allItems: [BacklogItem]

    @State private var newName = ""
    @State private var newColor = "blue"
    @State private var newIcon = "tag"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("카테고리 관리")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if categories.isEmpty {
                Spacer()
                Text("아직 카테고리가 없습니다. 아래에서 추가하세요.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(categories) { c in
                            CategoryEditRow(
                                category: c,
                                onDelete: { deleteCategory(c) },
                                onToggleBroadcast: { toggleBroadcast(c) }
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // 새 카테고리 추가
            HStack(spacing: 8) {
                ColorPickerMenu(colorName: $newColor)
                IconPickerMenu(iconName: $newIcon, colorName: $newColor)
                TextField("새 카테고리 이름", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCategory)
                Button("추가", action: addCategory)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    private func addCategory() {
        let t = newName.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let maxIndex = categories.map(\.sortIndex).max() ?? -1
        context.insert(BacklogCategory(name: t, colorName: newColor, iconName: newIcon, sortIndex: maxIndex + 1))
        try? context.save()
        newName = ""
        newColor = "blue"
        newIcon = "tag"
    }

    private func deleteCategory(_ c: BacklogCategory) {
        // 이 카테고리를 쓰던 항목은 미분류로 되돌림
        for item in allItems where item.categoryID == c.uuid {
            item.categoryID = nil
        }
        context.delete(c)
        try? context.save()
    }

    /// 전파 연결은 한 카테고리만 가진다 (여러 개면 어느 쪽이 자동 전파인지 알 수 없다).
    private func toggleBroadcast(_ c: BacklogCategory) {
        let turningOn = !c.isBroadcast
        for other in categories { other.isBroadcast = false }
        c.isBroadcast = turningOn
        try? context.save()
    }
}

struct CategoryEditRow: View {
    @Bindable var category: BacklogCategory
    @Environment(\.modelContext) private var context
    let onDelete: () -> Void
    var onToggleBroadcast: () -> Void = { }

    var body: some View {
        HStack(spacing: 10) {
            ColorPickerMenu(colorName: $category.colorName)
                .onChange(of: category.colorName) { _, _ in try? context.save() }
            IconPickerMenu(iconName: $category.iconName, colorName: $category.colorName)
                .onChange(of: category.iconName) { _, _ in try? context.save() }

            TextField("이름", text: $category.name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: category.name) { _, _ in try? context.save() }

            Button(category.isBroadcast ? "전파 카테고리" : "전파로 지정", action: onToggleBroadcast)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(category.isBroadcast ? .primary : .secondary)
            .help(category.isBroadcast
                  ? "이 카테고리로 지정하면 전파 필요가 자동으로 켜집니다 — 눌러서 해제"
                  : "이 카테고리를 전파 카테고리로 지정")

            Button("삭제", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ColorPickerMenu: View {
    @Binding var colorName: String

    var body: some View {
        Menu {
            ForEach(routineColorOptions, id: \.name) { opt in
                Button {
                    colorName = opt.name
                } label: {
                    Label(opt.name, systemImage: colorName == opt.name ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle()
                .fill(paletteColor(colorName))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("색상 선택")
    }
}

struct IconPickerMenu: View {
    @Binding var iconName: String
    @Binding var colorName: String

    var body: some View {
        Menu {
            ForEach(categoryIconOptions, id: \.self) { icon in
                Button {
                    iconName = icon
                } label: {
                    Label(icon, systemImage: icon)
                }
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 15))
                .foregroundStyle(paletteColor(colorName))
                .frame(width: 20, height: 16)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("아이콘 선택")
    }
}
