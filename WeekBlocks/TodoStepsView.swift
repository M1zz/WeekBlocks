//
//  TodoStepsView.swift
//  무지개 공방
//
//  할 일 하나를 '들여다보는' 시트 — 그 안의 단계(뎁스)를 순서대로 보여주고 편집한다.
//
//  할 일 전체가 몇 시간인지를 먼저 정하고(그게 100%), 단계들이 그 시간을 나눠 갖는다.
//  기본은 N분의 1이고, 한 단계를 직접 조정하면 나머지가 남은 몫을 다시 나눠
//  합계는 언제나 100%가 된다. 계산은 TodoTree.swift(iOS와 공유하는 순수 로직)에 있다.
//
//  **조언을 띄우지 않는다.** 한때 "쪼개기 전에 한 가지"·구성 조언·지금 단계 경고를 TipKit으로
//  냈는데, 단계를 적으러 온 창에 읽을 글이 먼저 서서 창이 복잡해 보였다. 판단 자체는
//  TodoSplitAdvisor 에 그대로 있고(아이폰과 같이 쓰는 파일이라 지우지 않는다), 이 창에서만 안 그린다.
//  쪼개기 도우미도 **사람이 부를 때만** 펼친다.
//

import SwiftUI
import SwiftData

struct TodoStepsView: View {
    /// 100%에 해당하는 최상위 할 일.
    let root: BacklogItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BacklogItem.sortIndex), SortDescriptor(\BacklogItem.createdAt)])
    private var allItems: [BacklogItem]

    /// 새 단계를 붙일 자리. nil이면 최상위 할 일 바로 아래.
    @State private var addTarget: BacklogItem?
    @State private var newTitle = ""
    /// 새 단계의 라벨. nil이면 '자동' — 형제들과 N분의 1로 나눠 갖는다.
    /// 새 단계의 속성. 백로그의 빈 줄과 같은 키를 써서, 어디서 적든 지난번 값이 따라온다.
    @FocusState private var focused: Bool
    /// 쪼개기 도우미(기본 뼈대)를 펼쳤는가. 기본은 접힘 — 부를 때만 선다.
    @State private var showsHelper = false
    /// 끝낸 단계를 펼쳐 보는가. 기본은 접힘 — 줄기 바로 아래가 **지금 할 단계**가 되게.
    @State private var showsFinished = false

    private var tree: TodoTree { TodoTree(allItems) }

    private var rows: [(item: BacklogItem, depth: Int)] {
        Array(tree.flattened(from: root).dropFirst())
    }

    /// 다 끝난 줄 — 제가 끝났고, 아래 단계가 있으면 그것까지 다 끝났다.
    private func isFinished(_ item: BacklogItem) -> Bool {
        tree.hasChildren(item) ? tree.progress(of: item) >= 1 : item.isCompleted
    }

    /// 목록에 세울 줄. **끝낸 단계는 접는다.**
    ///
    /// 단계는 순서대로 서고 끝낸 것도 제자리에 남아서, 앞을 끝낼수록 '지금' 줄이 아래로 밀려났다.
    /// 다섯 중 셋을 끝내면 줄기 밑으로 넉 줄을 지나야 할 차례가 나왔다 — 할 것을 찾으러 매번
    /// 끝난 것을 다시 읽게 된다. 접어 두면 줄기 바로 밑이 늘 지금 할 단계다.
    /// 부모가 다 끝났을 때만 그 부모를 접으므로, 보이는 자식의 부모는 언제나 보인다(가지가 안 끊긴다).
    private var visibleRows: [(item: BacklogItem, depth: Int)] {
        showsFinished ? rows : rows.filter { !isFinished($0.item) }
    }

    private var finishedCount: Int { rows.filter { !tree.hasChildren($0.item) && $0.item.isCompleted }.count }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Text("아직 단계가 없습니다. 아래에 적어 보세요.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                            // 부를 때만 펼친다. 처음부터 뼈대 네 줄과 설명이 깔려 있으면
                            // 한 줄 적으러 온 창이 설문지처럼 보인다.
                            Button {
                                withAnimation(Motion.disclose) { showsHelper.toggle() }
                            } label: {
                                Label(showsHelper ? "도우미 접기" : "쪼개기 도우미…",
                                      systemImage: "wand.and.stars")
                                    .font(.body)
                            }
                            .buttonStyle(.borderless)
                        }

                        if showsHelper {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(TodoSplitAdvisor.template(for: root.title).enumerated()), id: \.offset) { _, step in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(step.title)
                                            .font(.body)
                                        Text(step.note)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Button("이 뼈대로 4단계 만들기", action: applyTemplate)
                                    .buttonStyle(.borderedProminent)
                                    .padding(.top, 4)
                            }
                            .padding(14)
                            .background(Color.primary.opacity(0.04), in: .soft(Corner.chip))
                            .transition(.disclose)
                        }
                    }
                    .padding(20)
                }
                .transition(.opacity)
            } else {
                ScrollView {
                    // **쪼갠다는 것이 모양으로 보이게.** 맨 위에 할 일(줄기)이 서고, 단계들이
                    // 그 아래로 가지를 친다(├ └). 들여쓰기만 있을 때는 단계가 할 일과 나란한
                    // 다른 줄들로 읽혀서 '하나를 나눈 것'이라는 느낌이 안 났다.
                    // 줄 사이 간격은 0 — 가지 선이 줄과 줄 사이에서 끊기지 않게.
                    let shown = visibleRows
                    let branches = Self.branches(for: shown.map(\.depth))
                    LazyVStack(alignment: .leading, spacing: 0) {
                        trunkRow

                        if finishedCount > 0 { finishedToggle }

                        ForEach(Array(shown.enumerated()), id: \.element.item.id) { index, row in
                            StepRow(
                                item: row.item,
                                depth: row.depth,
                                branch: branches[index],
                                isCurrent: row.item.dragToken == tree.currentStep(of: root)?.dragToken,
                                hasChildren: tree.hasChildren(row.item),
                                progress: tree.progress(of: row.item),
                                share: share(of: row.item),
                                onHours: { setHours(row.item, $0) },
                                onToggle: { toggle(row.item) },
                                onAddChild: { addTarget = row.item; focused = true },
                                onMoveUp: { move(row.item, by: -1) },
                                onMoveDown: { move(row.item, by: 1) },
                                onDelete: { remove(row.item) }
                            )
                            .transition(.row)
                        }

                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    // 단계는 붙고 떨어지고 위아래로 자리를 옮긴다. 그 셋이 한 결이다.
                    .animation(Motion.row, value: shown.map(\.item.dragToken))
                }
                .transition(.opacity)
            }

            Divider()

            inputBar
        }
        .frame(minWidth: 560, minHeight: 480)
        .animation(Motion.screen, value: rows.isEmpty)
    }

    // MARK: - 끝낸 단계 (접힘)

    /// "✓ 끝낸 단계 3개" — 줄기 바로 밑. 누르면 끝낸 것까지 제 순서대로 펼친다.
    private var finishedToggle: some View {
        Button {
            withAnimation(Motion.disclose) { showsFinished.toggle() }
        } label: {
            HStack(spacing: 0) {
                // 줄기에서 내려온 선이 이 줄을 지나 아래 단계로 이어진다 — 여기서 끊기면
                // 아래 단계들이 줄기와 떨어진 것처럼 보인다.
                BranchGuide()
                    .stroke(Color.secondary.opacity(visibleRows.isEmpty ? 0 : 0.35),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: StepBranch.column)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(showsFinished ? "끝낸 단계 접기" : "끝낸 단계 \(finishedCount)개")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(showsFinished ? 90 : 0))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 줄기 (쪼개진 할 일 자신)

    /// 목록 맨 위의 할 일 — 가지들이 여기서 뻗어 나간다.
    private var trunkRow: some View {
        let count = tree.leafCount(of: root)
        return HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: StepBranch.column)
            Text(root.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            Spacer()
            Text("하위 \(count)개 · \(formatDuration(tree.totalHours(of: root)))")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.07), in: .soft(Corner.chip))
    }

    /// 줄마다 어떤 가지를 그릴지. 깊이 목록(1부터)만 보고 정한다.
    /// - 제 가지: 형제가 아래에 더 있으면 ├, 마지막이면 └.
    /// - 위 칸들: 그 깊이의 조상 아래에 형제가 더 남아 있으면 세로줄(│)을 이어 긋는다.
    static func branches(for depths: [Int]) -> [StepBranch] {
        func continues(at level: Int, after index: Int) -> Bool {
            for j in (index + 1)..<depths.count {
                if depths[j] < level { return false }
                if depths[j] == level { return true }
            }
            return false
        }
        return depths.indices.map { i in
            let d = depths[i]
            let guides = (1..<max(1, d)).map { continues(at: $0, after: i) }
            return StepBranch(guides: guides, isLast: !continues(at: d, after: i))
        }
    }

    // MARK: - 헤더

    private var header: some View {
        let progress = tree.progress(of: root)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(root.title)
                        .font(.title3.weight(.semibold))
                    // ⚠️ `currentStep`은 자식이 없으면 **자기 자신**을 돌려준다. 안 쪼갠 일에서
                    //    그것만 보고 세우면 헤더가 제 이름을 두 번 적는다 —
                    //    "제목 / 지금 단계 / 같은 제목". 쪼갠 일에만 이 줄이 있다.
                    if tree.hasChildren(root), let step = tree.currentStep(of: root) {
                        HStack(spacing: 6) {
                            // 기호 하나로는 이게 '지금 할 것'이라는 뜻이 안 읽힌다. 말로 적는다.
                            Text("지금 단계")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                            Text(step.title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                        }
                    } else if tree.hasChildren(root) {
                        Label("모든 단계를 마쳤습니다", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(progress >= 1 ? Color.green : Color.accentColor)
                    .contentTransition(.numericText())
                Button("완료") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : .accentColor)
                .animation(Motion.number, value: progress)

            // 이 일 전체가 몇 시간인가. 안 쪼갠 일은 여기서 고른다.
            HStack(spacing: 8) {
                totalHoursMenu
                Spacer()
            }
        }
        .padding(20)
        // '지금 단계'가 다음으로 넘어가고, 퍼센트가 굴러가고, 다 마쳤다는 줄이 대신 선다.
        .animation(Motion.row, value: progress)
    }

    /// 이 일 전체에 걸리는 시간.
    ///
    /// - **안 쪼갠 일**: 이 시간이 곧 그 일의 시간이다 — 눌러서 고른다. 새 할 일은 30분으로
    ///   태어나는데(`TodoTree.defaultStepHours`), 예전엔 여기 글자로만 서 있어서 바꿀 길이 없었다.
    /// - **쪼갠 일**: 단계들의 합이다(→ TodoTree.totalHours). 여기서 바꾸면 무엇을 얼마나 줄일지
    ///   모르므로, 글자로 두고 단계마다 고치라고 말한다.
    @ViewBuilder
    private var totalHoursMenu: some View {
        let total = tree.totalHours(of: root)
        if tree.hasChildren(root) {
            HStack(spacing: 5) {
                Image(systemName: "sum").font(.body)
                Text("다 하면 \(formatDuration(total))")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(String(localized: "단계 시간의 합 — 단계마다 시간을 고치면 따라 바뀝니다"))
        } else {
            DurationPicker(hours: Binding(get: { root.durationHours },
                                          set: { setHours(root, $0) }),
                           prefix: "다 하면")
        }
    }



    // MARK: - 추가 입력 줄

    private var inputBar: some View {
        return VStack(alignment: .leading, spacing: 6) {
            if let target = addTarget {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2)
                    Text("‘\(target.title)’ 아래에 추가")
                        .font(.caption)
                        .lineLimit(1)
                    Button {
                        addTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.squish)
                }
                .foregroundStyle(.secondary)
                .transition(.row)
            }

            HStack(spacing: 10) {
                TextField("다음에 할 단계", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(addStep)

                Button("추가", action: addStep)
                    .buttonStyle(.borderless)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .animation(Motion.row, value: addTarget?.dragToken)
    }

    /// 지금 빈 줄에 적히면 붙을 속성.

    // MARK: - 동작

    /// 이 단계가 전체에서 차지하는 몫. 분모는 잎(실제로 하는 단계)들의 합이다 —
    /// 중간 묶음까지 더하면 두 번 센다.
    private func share(of item: BacklogItem) -> Double? {
        let total = tree.leaves(of: root).reduce(0) { $0 + $1.durationHours }
        guard total > 0 else { return nil }
        let hours = tree.hasChildren(item) ? tree.totalHours(of: item) : item.durationHours
        return hours / total
    }

    /// 단계 시간을 직접 적는다. 상위 할 일의 시간은 아래에서 위로 저절로 따라온다.
    private func setHours(_ item: BacklogItem, _ hours: Double) {
        item.durationHours = hours
        try? context.save()
    }

    private func addStep() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let parent = addTarget ?? root

        let step = TodoTree.makeStep(under: parent,
                                     title: title,
                                     sortIndex: tree.nextSortIndex(under: parent))
        context.insert(step)

        // 새로 만든 단계까지 넣어 트리를 다시 세운다 (@Query 갱신 전에도 계산이 맞도록).
        // 시간은 손댈 게 없다 — 위쪽 숫자는 이 단계가 더해지면서 저절로 커진다.
        let updated = TodoTree(allItems + [step])
        if updated.children(of: parent).count >= 2 { ShareSplitTip.hasSplit = true }
        updated.rollUp(from: step)
        withAnimation(Motion.row) { try? context.save() }

        newTitle = ""
        focused = true
    }

    /// 쪼개기 도우미의 기본 뼈대를 그대로 단계로 만든다.
    /// 뼈대의 시간은 '비율의 씨앗'이다 — 전체 예상 시간을 그 비율대로 나눠 갖는다.
    private func applyTemplate() {
        let tree = self.tree
        var index = tree.nextSortIndex(under: root)
        var made: [BacklogItem] = []
        for step in TodoSplitAdvisor.template(for: root.title) {
            let node = TodoTree.makeStep(under: root,
                                         title: step.title,
                                         sortIndex: index)
            context.insert(node)
            made.append(node)
            index += 1
        }
        let updated = TodoTree(allItems + made)
        updated.rollUp(from: root)
        withAnimation(Motion.row) { try? context.save() }
    }

    private func toggle(_ item: BacklogItem) {
        withAnimation(Motion.row) {
            tree.setCompleted(item, !item.isCompleted)
            try? context.save()
        }
    }

    /// 속성을 바꾸면 시간도 그 속성의 것으로 따라간다 — 고르는 건 하나뿐이라는 약속을 지킨다.
    private func remove(_ item: BacklogItem) {
        let tree = self.tree
        let parent = tree.parent(of: item)
        let victims = Set(tree.subtree(of: item).map(\.dragToken))
        withAnimation(Motion.row) {
            for node in tree.subtree(of: item) { context.delete(node) }
            if let parent {
                // 시간은 남은 단계들의 합이라 저절로 줄어든다. 완료 상태만 다시 굴려 준다.
                let updated = TodoTree(allItems.filter { !victims.contains($0.dragToken) })
                updated.rollUp(from: parent)
            }
            try? context.save()
        }
    }

    private func move(_ item: BacklogItem, by offset: Int) {
        let tree = self.tree
        guard let parent = tree.parent(of: item) else { return }
        var siblings = tree.children(of: parent)
        guard let index = siblings.firstIndex(where: { $0.dragToken == item.dragToken }) else { return }
        let target = index + offset
        guard siblings.indices.contains(target) else { return }
        siblings.swapAt(index, target)
        for (i, sibling) in siblings.enumerated() { sibling.sortIndex = i }
        withAnimation(Motion.row) { try? context.save() }
    }
}

// MARK: - 단계 한 줄

/// 한 줄의 가지 모양. `guides[k]` = k+1 번째 깊이의 세로줄을 이어 그을지.
struct StepBranch {
    var guides: [Bool]
    var isLast: Bool
    /// 깊이 한 칸의 폭. 줄기의 아이콘 칸과 같아서 첫 가지가 줄기 아이콘 바로 아래서 뻗는다.
    static let column: CGFloat = 22
}

/// ├ 또는 └ — 위에서 내려온 줄이 가운데서 오른쪽으로 꺾인다. 마지막이 아니면 아래로도 잇는다.
private struct BranchElbow: Shape {
    let isLast: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: isLast ? r.midY : r.maxY))
        p.move(to: CGPoint(x: r.midX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

private struct BranchGuide: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

private struct StepRow: View {
    let item: BacklogItem
    let depth: Int
    let branch: StepBranch
    let isCurrent: Bool
    let hasChildren: Bool
    let progress: Double
    /// 이 단계가 이 할 일 전체에서 차지하는 몫(0...1).
    let share: Double?
    let onHours: (Double) -> Void
    let onToggle: () -> Void
    let onAddChild: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    /// 두 질문 판정. 잎(실제로 하는 단계)일 때만 본다.
    private var advice: StepAdvice {
        TodoSplitAdvisor.advice(title: item.title,
                                durationHours: item.durationHours,
                                pick: item.fragmentPick)
    }

    private var hoursBinding: Binding<Double> {
        Binding(get: { item.durationHours },
                set: { onHours(max(0.25, min(12, $0))) })
    }

    private static let line = StrokeStyle(lineWidth: 1.5, lineCap: .round)

    var body: some View {
        HStack(spacing: 0) {
            // 가지 — 위 칸들의 세로줄, 그리고 제 칸의 ├/└.
            ForEach(Array(branch.guides.enumerated()), id: \.offset) { _, on in
                BranchGuide()
                    .stroke(Color.secondary.opacity(on ? 0.35 : 0), style: Self.line)
                    .frame(width: StepBranch.column)
            }
            BranchElbow(isLast: branch.isLast)
                .stroke(Color.secondary.opacity(0.35), style: Self.line)
                .frame(width: StepBranch.column)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isCurrent ? Color.orange.opacity(0.08) : Color.clear,
                            in: .soft(Corner.chip))
                .padding(.vertical, 1)
        }
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        // 차례가 이 줄로 넘어오면 바탕색이 켜진다. 툭 갈리면 어느 줄로 넘어왔는지 놓친다.
        .animation(Motion.row, value: isCurrent)
        .contextMenu {
            Button("하위 단계 추가", action: onAddChild)
            Button("위로", action: onMoveUp)
            Button("아래로", action: onMoveDown)
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted
                      ? "checkmark.circle.fill"
                      : (isCurrent ? "arrowtriangle.right.circle.fill" : "circle"))
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? .green : (isCurrent ? .orange : Color.secondary))
            }
            .buttonStyle(.squish)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // 지금 할 차례 — 기호만으로는 안 읽혀서 말로 붙인다.
                    if isCurrent {
                        Text("지금")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasChildren {
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? .green : .accentColor)
                        .frame(maxWidth: 160)
                        .animation(Motion.number, value: progress)
                } else if advice.isFragment {
                    // 표식은 조각에만. iOS('욕망의 무지개')와 같은 말·같은 기준이다.
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("5분에 집기")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.teal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.teal.opacity(0.15)))
                }

            }

            Spacer()

            // 시간은 여기서 직접 적는다. 그리고 그게 전체에서 몇 %인지 바로 옆에 —
            // 시간을 손으로 적게 된 뒤로는 이 숫자가 "어디를 더 쪼개야 하나"를 말해준다.
            if !hasChildren {
                DurationPicker(hours: hoursBinding, style: .plain)
            }

            if let share {
                Text("\(Int((share * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .frame(width: 40, alignment: .trailing)
            }

            if hovering {
                Button(action: onAddChild) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11))
                }
                .buttonStyle(.squish)
                .help("하위 단계 추가")
                .transition(.control)
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 11))
                }
                .buttonStyle(.squish)
                .help("삭제")
                .transition(.control)
            }
        }
    }
}
