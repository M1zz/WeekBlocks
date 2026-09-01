import SwiftUI
import SwiftData
import TipKit

/// 주간 화면 툴바의 '할 일 추가'가 다른 창(할 일 창)에 보내는 신호.
/// 창을 여는 것과 빈 칸을 여는 것은 서로 다른 창에서 일어나므로 한 곳을 거쳐 간다.
/// 숫자를 하나 올리는 것으로 신호를 삼는다 — 창이 이미 떠 있으면 바뀐 값이 바로 닿고,
/// 이제 뜨는 중이면 나타나는 쪽이 "내가 본 적 없는 번호"를 보고 빈 칸을 연다.
@Observable
final class TodoComposeRequest {
    static let shared = TodoComposeRequest()
    private init() { }

    private(set) var ticket = 0

    func requestNew() { ticket += 1 }
}

struct BacklogSection: View {
    @Environment(\.modelContext) private var context

    let allItems: [BacklogItem]
    let weekStart: Date
    /// 보고 있는 주의 계획 블록. 요일에 올려 둔 할 일에 표시를 붙이는 데만 쓴다.
    var weekBlocks: [PlanBlock] = []
    /// 고정 루틴이 확보돼 있을 때만 할 일을 작성할 수 있다.
    var canPlan: Bool = true
    /// 툴바 '할 일 추가'의 신호를 받는 자리인가. 같은 목록이 두 창에 서 있으므로
    /// 신호를 받는 쪽은 하나여야 한다 — 버튼이 있는 주간 화면 쪽만 true.
    var listensForComposeRequest: Bool = false

    @Query(sort: [SortDescriptor(\BacklogCategory.sortIndex), SortDescriptor(\BacklogCategory.createdAt)])
    private var categories: [BacklogCategory]

    @AppStorage("didSeedBacklogCategories") private var didSeedCategories = false
    /// 전파 카테고리는 기본값 시딩보다 나중에 생겼으므로 별도 플래그로 한 번 보강한다.
    @AppStorage("didSeedBroadcastCategory") private var didSeedBroadcastCategory = false

    /// 툴바 '할 일 추가'가 보내는 신호. 마지막으로 받은 번호와 다르면 빈 칸을 연다.
    private let composeRequest = TodoComposeRequest.shared
    @State private var seenComposeTicket = 0

    @State private var filterCategoryID: String? = nil   // nil = 전체
    @State private var showingComposer = false
    @State private var showingAllBacklog = false

    // MARK: 적는 자리
    //
    // 적으려고 모달을 열고, 적고, 닫고, 다시 카드에서 찾는 왕복이 가장 큰 부담이었다.
    // 이제 **목록 맨 앞에 빈 칸이 하나 생긴다** — 거기 적으면 그게 곧 할 일이다.
    /// 빈 칸이 열려 있는가.
    @State private var isAdding = false
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
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
            // 주차로는 가르지 않는다. 요일에 올리기 전의 할 일에는 시간이 없고,
            // 시간이 없는 것을 주 단위로 나누면 "지난 주 것"이라는 딱지만 늘어난다.
            // (아이폰도 같은 규칙 — 밀린 줄은 이번 주로 끌어오고 목록은 하나다.)
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt < b.createdAt
        }
    }

    /// 표시 순서 묶음: 보고 있는 주 → 지난 주(이월) → 앞으로.
    /// 이월을 두 번째에 두는 이유는 이미 밀린 일이라 눈에서 사라지면 안 되기 때문이다.
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
                Text("할 일")
                    .font(.headline)

                // '전체 보기'는 제목 바로 옆에 붙인다 — 지금 목록이 **전부가 아니라는 것**을
                // 제목과 한 호흡에 말해야, 이월된 할 일을 못 보고 지나치지 않는다.
                //
                // 테두리 없는 글씨로 두었더니 제목 옆에 붙은 설명처럼 읽혀서
                // 누를 수 있는 줄 몰랐다. 테두리를 두르고 아이콘을 붙여 버튼으로 세운다.
                // 이월 개수는 괄호가 아니라 알약 하나로 — 숫자가 글에 섞이지 않게.
                Button {
                    showingAllBacklog = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 11))
                        Text("전체 보기")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("끝낸 것까지 포함한 전체 할 일")

                if !weekItems.isEmpty {
                    Text("\(filteredItems.count)개 · \(formatDuration(filteredItems.reduce(0) { $0 + $1.durationHours }))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 시간·분류를 표처럼 한꺼번에 고치는 옛 화면. 적는 통로가 아니라
                // 이따금 쓰는 정리 도구라 메뉴 안으로 넣는다.
                Menu {
                    Button("여러 개 한꺼번에 고치기") { showingComposer = true }
                        .disabled(!canPlan)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // 분류 버튼 줄. 오른쪽 끝이 '새 할 일'을 여는 자리다 —
            // 분류를 고르고 바로 그 분류로 적는 흐름이 한 줄 안에서 끝난다.
            //
            // 이 줄은 **어떤 경우에도 사라지지 않는다.** 고정 루틴이 없어 아직 계획할 수
            // 없을 때 버튼까지 통째로 없애 봤더니, 화면에 남은 '추가'가 루틴 쪽뿐이라
            // 할 일을 어디서 적는지 길이 끊겼다. 못 누르는 것과 없는 것은 다르다 —
            // 흐릿하게 남겨 두고, 왜 못 누르는지는 아래 안내가 말한다.
            HStack(spacing: 8) {
                if canPlan {
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
                                // 분류 버튼의 점은 분류 색(사용자가 고른 정체성)이지만
                                // 이건 상태 필터라 색으로 의미를 만들지 않는다.
                                FilterChip(label: "전파 \(broadcastCount)", color: .secondary,
                                           selected: broadcastOnly) { broadcastOnly.toggle() }
                            }
                        }
                        .padding(.vertical, 1)
                    }
                } else {
                    Spacer(minLength: 0)
                }

                // 창이 좁아도, 분류가 많아도 이 버튼은 밀려나지 않는다
                // (가로 스크롤이 남는 폭을 다 가져가지 못하게 자리를 먼저 잡는다).
                Button(action: beginAdding) {
                    Label("새 할 일", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canPlan)
                .fixedSize()
                .layoutPriority(1)
                .help(canPlan ? "목록 맨 위에 빈 칸을 만든다 (⌘N)"
                              : "고정 루틴을 하나 세우면 할 일을 적을 수 있습니다")
                .keyboardShortcut("n", modifiers: .command)
            }

            if !canPlan {
                lockedNotice
            } else if filteredItems.isEmpty && !isAdding {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    // 새 할 일은 목록 **맨 앞 빈 칸**으로 열린다.
                    // 적을 자리가 목록 안에 이미 생겨 있으니 따로 '추가' 절차가 없다 —
                    // 그 칸에 적으면 그게 곧 할 일이 된다.
                    if isAdding { newTodoCard }

                    ForEach(filteredItems) { item in
                        BacklogBlock(
                            item: item,
                            categories: categories,
                            tint: itemColorMap[item.dragToken] ?? .secondary,
                            lane: tree.lane(of: item),
                            isFragment: isFragmentCard(item),
                            planNote: planNote(for: item),
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
        // 안 끝난 일의 주차는 켤 때마다 이번 주로 끌어온다 (아이폰과 같은 규칙).
        // 요일에 올리기 전의 할 일에는 시간이 없어서, 지난 주에 서 있을 이유가 없다.
        .onAppear { pullForwardOverdueWeeks() }
        // 툴바의 '할 일 추가'가 부른 것이면 빈 칸까지 열어 준다.
        // 창이 이제 뜨는 중이면 onChange가 오지 않으므로 나타날 때도 한 번 본다.
        .onAppear { consumeComposeRequest() }
        .onChange(of: composeRequest.ticket) { _, _ in consumeComposeRequest() }
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

    /// 이 카드가 지금 세우고 있는 것이 조각인가 — 앱 판정까지 포함해서 본다.
    /// 표시해 둔 것(lane == .now)과 같은 연두로 칠한다. 둘 다 "그냥 집으면 된다"는 뜻이다.
    private func isFragmentCard(_ item: BacklogItem) -> Bool {
        let tree = self.tree
        guard let step = tree.markedStep(of: item) ?? tree.currentStep(of: item) ?? Optional(item)
        else { return false }
        return TodoSplitAdvisor.advice(title: step.title,
                                       durationHours: step.durationHours,
                                       pick: step.fragmentPick).isFragment
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

    /// 이 할 일을 이 주의 어느 요일에 올려 뒀는지. 안 올렸으면 nil.
    ///
    /// 요일에 올려도 할 일은 백로그에 남는다(→ ContentView의 `convertBacklogItem`).
    /// 그래서 카드만 보면 올렸는지 아닌지를 알 수 없다 — 이 표시가 그 자리를 메운다.
    /// 블록과 항목을 잇는 식별자가 스키마에 없어 **제목으로 맞춘다**(iOS도 같은 방식).
    /// 단계를 올린 블록은 "할 일 · 단계" 꼴이라 접두어까지 함께 본다.
    private func planNote(for item: BacklogItem) -> String? {
        let prefix = item.title + " · "
        let days = weekBlocks
            .filter { $0.title == item.title || $0.title.hasPrefix(prefix) }
            .map(\.day)
        guard let first = days.min(by: { $0.rawValue < $1.rawValue }) else { return nil }
        let others = Set(days).count - 1
        return others > 0 ? "\(first.shortLabel) +\(others)" : first.longLabel
    }

    /// 보고 있는 주가 아닌 항목에만 붙는 주차 표시 ("2주 전" 같은 상대 표기).
    /// 전부 보여주면서도 어느 주에 계획한 일인지는 잃지 않게 한다.
    /// 목록 맨 앞의 빈 칸. **적으면 그게 곧 할 일이 된다.**
    ///
    /// 예전에는 목록 위에 입력 줄이 따로 열리고 Enter로 '추가'해야 했다.
    /// 적는 것과 목록이 다른 물건처럼 보여서, 한 줄 적을 때마다 절차를 밟는 느낌이었다.
    /// 지금은 목록 안에 빈 칸이 하나 생길 뿐이다 — 카드 모양도 크기도 옆의 할 일과 같다.
    ///
    /// 받는 것은 이름 하나뿐이다. 분류는 위에서 고른 버튼을 따라가고,
    /// 시간·단계는 나중에 카드에서 고친다. 적는 순간에 정할 것을 늘리면 적기를 그만두게 된다.
    private var newTodoCard: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(draftTint)
                .frame(width: 3)

            TextField("할 일", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .focused($addFocused)
                // Enter를 쳐도 되지만 안 쳐도 된다 — 다른 곳을 누르면 그대로 담긴다.
                .onSubmit { commitDraft(keepOpen: true) }
                .onExitCommand { endAdding() }

            Button(action: endAdding) {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("닫기 (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(draftTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(draftTint.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        // 다른 데를 누르면 적던 것이 그대로 담긴다. 빈 칸이면 조용히 사라진다.
        .onChange(of: addFocused) { _, focused in
            if !focused { commitDraft(keepOpen: false) }
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .opacity))
    }

    /// 빈 칸을 연다. 분류는 지금 보고 있는 필터를 그대로 따른다 —
    /// '업무'만 보고 있었다면 지금 적는 것도 업무다.
    private func beginAdding() {
        withAnimation(.easeOut(duration: 0.18)) { isAdding = true }
        addFocused = true
    }

    /// 안 끝난 일의 주차(`weekStartDate`)를 이번 주로 끌어온다.
    ///
    /// 예전에는 '이번 주로' 버튼을 사람이 줄마다 눌렀다. 그런데 안 끝난 일이 지난 주에
    /// 남아 있다는 사실은 딱지로 말할 것이 아니라 그냥 목록에 서 있으면 되는 것이었다.
    /// 주차는 이제 결산이 "이번 주에 무엇을 했나"를 세는 자리로만 쓴다.
    /// **완료한 일은 건드리지 않는다** — 지난 주에 끝낸 것은 지난 주의 셈이다.
    /// (→ iOS TodoView.pullForwardOverdueWeeks 와 같은 규칙)
    private func pullForwardOverdueWeeks() {
        let tree = self.tree
        let stale = tree.roots.filter {
            !$0.isCompleted && $0.weekStartDate < weekStart
                && !cal.isDate($0.weekStartDate, inSameDayAs: weekStart)
        }
        guard !stale.isEmpty else { return }
        for root in stale {
            // 단계도 부모와 한 덩어리로 같이 옮긴다.
            for node in tree.subtree(of: root) { node.weekStartDate = weekStart }
        }
        try? context.save()
    }

    /// 다른 창에서 온 '할 일 추가' 신호를 한 번만 받아 빈 칸을 연다.
    private func consumeComposeRequest() {
        guard listensForComposeRequest else { return }
        guard composeRequest.ticket != seenComposeTicket else { return }
        seenComposeTicket = composeRequest.ticket
        guard canPlan, !isAdding else { return }
        beginAdding()
    }

    private func endAdding() {
        newTitle = ""
        addFocused = false
        withAnimation(.easeOut(duration: 0.18)) { isAdding = false }
    }

    /// 적은 것을 할 일로 담는다.
    /// - Parameter keepOpen: 담고 나서 빈 칸을 하나 더 열어 둘지. Enter로 이어 적을 때만 true.
    private func commitDraft(keepOpen: Bool) {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            if !keepOpen { endAdding() }
            return
        }

        // 새로 적은 것이 맨 앞에 서도록 지금 가장 작은 순서보다 하나 앞에 둔다.
        let minIndex = allItems.map(\.sortIndex).min() ?? 0
        let item = BacklogItem(title: title,
                               durationHours: TodoTree.defaultStepHours,
                               sortIndex: minIndex - 1,
                               categoryID: filterCategoryID,
                               weekStartDate: weekStart)
        // 전파 분류로 적은 것은 곧바로 전파 필요가 된다 (계약은 미확정으로 남아 눈에 띈다).
        if let broadcast = categories.broadcastCategory, filterCategoryID == broadcast.uuid {
            item.needsBroadcast = true
        }
        withAnimation(.easeOut(duration: 0.18)) {
            context.insert(item)
            try? context.save()
        }
        newTitle = ""
        if keepOpen {
            addFocused = true          // 손이 키보드를 떠나지 않게 둔다
        } else {
            withAnimation(.easeOut(duration: 0.18)) { isAdding = false }
        }
    }

    /// 빈 칸의 색. 어느 분류로 적는 중인지 테두리 색이 말한다.
    private var draftTint: Color {
        categories.first { $0.uuid == filterCategoryID }?.displayColor
            ?? Color(red: 0.55, green: 0.80, blue: 0.45)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Text(weekItems.isEmpty
                 ? "할 일이 아직 없습니다."
                 : "이 분류엔 할 일이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if weekItems.isEmpty && !isAdding {
                Button("새 할 일") { beginAdding() }
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

/// '할 일'을 담는 **따로 선 창**.
///
/// 예전에는 주간 화면 맨 아래에 얹힌 한 조각이었다. 그런데 할 일을 적는 일과
/// 한 주를 짜는 일은 손이 오가는 방향이 다르다 — 적을 때는 목록만 보면 되고,
/// 배치할 때는 목록과 요일 칸을 **동시에** 봐야 한다. 한 창에 세로로 쌓아 두면
/// 둘 중 하나는 늘 스크롤 밖에 있다. 창을 따로 세우면 나란히 놓고 끌어다 놓을 수 있다.
///
/// 주는 언제나 '이번 주'다. 지난 주를 들추는 일은 '전체 보기'가 맡는다.
struct TodoWindowView: View {
    @Query(sort: [SortDescriptor(\BacklogItem.sortIndex), SortDescriptor(\BacklogItem.createdAt)])
    private var allItems: [BacklogItem]

    private let weekStart: Date = .currentWeekStart

    // 이 창은 **할 일 스토어** 위에 서 있다. 루틴·계획 블록은 다른 스토어에 살아서
    // @Query로 못 읽는다 — 카드에 붙일 표시에만 쓰는 값이라 그때그때 물어본다.
    // (→ Stores.swift)

    /// 이번 주의 계획 블록 — 카드에 '어느 요일에 올렸는지'를 붙이는 데 쓴다.
    private var weekBlocks: [PlanBlock] { PlanStore.shared.blocks(inWeek: weekStart) }

    /// 고정 루틴이 하나라도 있어야 할 일을 계획할 수 있다 (주간 화면과 같은 규칙).
    private var canPlan: Bool { PlanStore.shared.hasFixedRoutines }

    var body: some View {
        ScrollView {
            BacklogSection(allItems: allItems, weekStart: weekStart,
                           weekBlocks: weekBlocks, canPlan: canPlan)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let selected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    // 안 고른 것도 **눌리는 것처럼** 보여야 한다. 예전에는 배경이 아예 없어서
    // 고르기 전에는 그냥 적어 둔 글씨로 읽혔다 — 누를 수 있는 줄 모르고 지나쳤다.
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                selected ? color.opacity(0.20)
                         : Color.primary.opacity(hovering ? 0.10 : 0.06),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(selected ? color.opacity(0.65) : Color.primary.opacity(0.12),
                                 lineWidth: selected ? 1.2 : 1)
            )
            .foregroundStyle(selected ? color : .primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
    /// 이 카드가 어느 자리에 서는가. 순서가 여기서 나온다 (iOS 목록의 띠와 같은 규칙).
    var lane: TodoTree.Lane = .planned
    /// 지금 세우고 있는 것이 조각인가. 표시해 둔 것과 같은 연두로 칠한다.
    var isFragment: Bool = false
    /// 이 주에 이미 요일로 올려 둔 경우의 표시 ("화요일"). 안 올렸으면 nil.
    var planNote: String? = nil
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
        if isFragment { return Self.nowGreen.opacity(0.18) }
        switch lane {
        case .now:     return Self.nowGreen.opacity(0.18)
        case .errand:  return Color.secondary.opacity(0.09)
        case .planned: return tint.opacity(0.10)
        }
    }

    private var laneBorder: Color {
        if isFragment { return Self.nowGreen.opacity(0.45) }
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
                                  : ((steps.isMarked || isFragment) ? "bolt.circle" : "arrowtriangle.right.circle.fill"))
                                .font(.system(size: 13))
                                .foregroundStyle(steps.currentTitle == nil
                                                 ? Color.green
                                                 : ((steps.isMarked || isFragment) ? Self.nowGreen : Color.orange))
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
                //
                // 분류 이름은 여기 적지 않는다. 카드 색이 이미 분류를 말하고 있고,
                // 한 줄에 글씨가 넷씩 붙으면 정작 읽어야 할 시간·요일이 묻힌다.
                // 무슨 분류인지 확인하고 바꾸는 자리는 카드 오른쪽 클릭 메뉴다.
                HStack(spacing: 6) {
                    if (lane == .now || isFragment), steps == nil {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Self.nowGreen)
                    }
                    Text(formatDuration(steps?.totalHours ?? item.durationHours))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    // 요일에 올려 둔 할 일. 카드가 백로그에 그대로 남으므로,
                    // "이건 이미 언제 할지 정했다"를 이 칩 하나로 말한다.
                    if let planNote {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(planNote)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.16), in: Capsule())
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
                    Text("전체 할 일").font(.title2.weight(.semibold))
                    Text("끝낸 것까지, 주별로 모아 봅니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("완료") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            if rootItems.isEmpty {
                Spacer()
                Text("할 일이 비어 있습니다.").foregroundStyle(.secondary)
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
