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
//  화면은 '라벨 먼저'다 — 적을 때 고른 라벨을 크게 보여준다. 조언은 화면에 깔지 않고
//  전부 TipKit으로 낸다 (→ TodoTips.swift). 필요한 때 한 번 뜨고, 닫으면 다시 안 뜬다.
//

import SwiftUI
import SwiftData
import TipKit

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
    @State private var newLabel: TodoLabel?
    @FocusState private var focused: Bool

    private var tree: TodoTree { TodoTree(allItems) }

    private var rows: [(item: BacklogItem, depth: Int)] {
        Array(tree.flattened(from: root).dropFirst())
    }

    /// 구성 전체에 대한 조언 (조각 시간 연구 기반).
    private var hints: [SplitHint] {
        let tree = self.tree
        let leaves = tree.hasChildren(root) ? tree.leaves(of: root) : []
        return TodoSplitAdvisor.hints(rootTitle: root.title,
                                      steps: leaves.map { ($0.title, $0.durationHours) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("아직 단계가 없습니다.")
                                .font(.callout.weight(.medium))
                            Text("이 할 일을 이루는 단계를 '되어야 하는 순서대로' 적어보세요.\n단계들은 전체 \(formatDuration(tree.totalHours(of: root)))를 N분의 1로 나눠 갖습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("쪼개기 도우미", systemImage: "wand.and.stars")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button("이 뼈대로 4단계 만들기", action: applyTemplate)
                                .buttonStyle(.borderedProminent)
                        }

                        ForEach(Array(TodoSplitAdvisor.template(for: root.title).enumerated()), id: \.offset) { _, step in
                            HStack(alignment: .top, spacing: 10) {
                                TodoLabelChip(label: TodoLabel.nearest(toHours: step.hours))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title).font(.system(size: 13, weight: .medium))
                                    Text(step.note).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }

                        if let hint = topHint, SplitHintTip(hint: hint).shouldDisplay {
                            Divider()
                            TipView(SplitHintTip(hint: hint))
                        }
                    }
                    .padding(20)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("단계 · 합쳐서 100%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                withAnimation {
                                    tree.splitEvenly(under: root)
                                    try? context.save()
                                }
                            } label: {
                                Label("N분의 1로 다시", systemImage: "equal.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)

                        // 비중이 어떻게 굴러가는지는 여기서 한 번만 설명한다.
                        if ShareSplitTip().shouldDisplay {
                            TipView(ShareSplitTip()).padding(.bottom, 6)
                        }
                        // 자물쇠 설명은 실제로 하나 잠근 뒤에만.
                        if LockedShareTip().shouldDisplay {
                            TipView(LockedShareTip()).padding(.bottom, 6)
                        }

                        ForEach(rows, id: \.item.id) { row in
                            StepRow(
                                item: row.item,
                                depth: row.depth,
                                percent: tree.weightInRoot(of: row.item),
                                weightInParent: tree.weight(of: row.item),
                                isCurrent: row.item.dragToken == tree.currentStep(of: root)?.dragToken,
                                hasChildren: tree.hasChildren(row.item),
                                progress: tree.progress(of: row.item),
                                onToggle: { toggle(row.item) },
                                onWeight: { setWeight(row.item, $0) },
                                onRelease: { release(row.item) },
                                onLabel: { setLabel(row.item, $0) },
                                onAddChild: { addTarget = row.item; focused = true },
                                onMoveUp: { move(row.item, by: -1) },
                                onMoveDown: { move(row.item, by: 1) },
                                onDelete: { remove(row.item) }
                            )
                        }

                        if let hint = topHint, SplitHintTip(hint: hint).shouldDisplay {
                            Divider().padding(.vertical, 8)
                            TipView(SplitHintTip(hint: hint))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            inputBar
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - 헤더

    private var header: some View {
        let progress = tree.progress(of: root)
        let stepCount = tree.hasChildren(root) ? tree.leafCount(of: root) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(root.title)
                        .font(.title3.weight(.semibold))
                    if let step = tree.currentStep(of: root) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                            Text(step.title)
                                .font(.callout)
                            if let number = tree.currentStepNumber(of: root), stepCount > 0 {
                                Text("· \(stepCount)단계 중 \(number)번째")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    } else if stepCount > 0 {
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
                Button("완료") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : .accentColor)

            // 지금 할 단계에 경고가 있으면 그것만 팁으로. (다른 줄에는 안 깐다)
            if let step = tree.currentStep(of: root),
               !tree.hasChildren(step),
               let warning = TodoSplitAdvisor.advice(title: step.title,
                                                     durationHours: step.durationHours).warning {
                TipView(StepWarningTip(warning: warning))
            }

            // 이 일 전체가 몇 시간인가 = 100%. 단계들은 이 시간을 나눠 갖는다.
            HStack(spacing: 8) {
                totalHoursMenu
                Text(stepCount > 0 ? "= 100%, 단계 \(stepCount)개가 나눠 가짐" : "= 100%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if stepCount > 0 {
                    Text("\(formatDuration(tree.doneHours(of: root))) 완료")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(20)
    }

    /// 전체 예상 시간을 고치는 메뉴. 바꾸면 단계들이 비율을 지킨 채 같이 늘고 준다.
    private var totalHoursMenu: some View {
        Menu {
            ForEach(TodoLabel.allCases) { label in
                Button("\(label.name) · \(formatDuration(label.defaultHours))") {
                    setRootHours(label.defaultHours, label: label)
                }
            }
            Divider()
            ForEach([6.0, 8.0, 12.0], id: \.self) { h in
                Button(formatDuration(h)) { setRootHours(h, label: nil) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: root.label.symbol).font(.system(size: 10))
                Text("이 일 전체 \(formatDuration(tree.totalHours(of: root)))")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(root.label.tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - 조언 (전부 TipKit)

    /// 구성 전체에 대한 조언 중 지금 가장 중요한 하나만 팁으로 낸다.
    /// 경고가 있으면 경고를, 없으면 잘 쪼갰다는 확인을. 닫으면 그 종류는 다시 안 뜬다.
    private var topHint: SplitHint? {
        let all = hints
        return all.first { $0.tone == .caution } ?? all.first
    }

    // MARK: - 추가 입력 줄

    private var inputBar: some View {
        let parent = addTarget ?? root
        let evenShare = tree.totalHours(of: parent) / Double(tree.children(of: parent).count + 1)
        let isFirstStep = !tree.hasChildren(parent)

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
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
            }

            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
                    Button {
                        newLabel = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "equal.square").font(.system(size: 10))
                            Text("자동 N분의 1").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(newLabel == nil ? Color.white : Color.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(newLabel == nil ? Color.accentColor : Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)

                    ForEach(TodoLabel.allCases) { label in
                        Button {
                            newLabel = label
                        } label: {
                            TodoLabelChip(label: label,
                                          hours: label.defaultHours,
                                          isSelected: newLabel == label)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                Text(isFirstStep
                     ? "첫 단계라 전체 \(formatDuration(tree.totalHours(of: parent)))를 그대로 물려받습니다. 단계를 더하면 나눠 갖습니다."
                     : (newLabel.map { "이 단계에 \(formatDuration(min($0.defaultHours, tree.totalHours(of: parent))))를 떼어 주고, 나머지 단계가 남은 몫을 나눠 가집니다." }
                        ?? "자동으로 N분의 1 — 이 단계는 \(formatDuration(evenShare))쯤이 됩니다."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
    }

    // MARK: - 동작

    private func addStep() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let parent = addTarget ?? root

        let step = TodoTree.makeStep(under: parent,
                                     title: title,
                                     sortIndex: tree.nextSortIndex(under: parent),
                                     label: newLabel)
        context.insert(step)

        // 새로 만든 단계까지 넣어 트리를 다시 세운다 (@Query 갱신 전에도 계산이 맞도록).
        let updated = TodoTree(allItems + [step])
        updated.giveInitialShare(step, hours: newLabel?.defaultHours)
        if updated.children(of: parent).count >= 2 { ShareSplitTip.hasSplit = true }
        updated.rollUp(from: step)
        try? context.save()

        newTitle = ""
        newLabel = nil
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
                                         sortIndex: index,
                                         seedHours: step.hours,
                                         label: TodoLabel.nearest(toHours: step.hours))
            node.isManualWeight = true   // 일부러 정해둔 비율이라 자동 재분배에서 빠진다
            context.insert(node)
            made.append(node)
            index += 1
        }
        let updated = TodoTree(allItems + made)
        updated.rollUp(from: root)
        updated.fit(under: root)
        try? context.save()
    }

    private func toggle(_ item: BacklogItem) {
        withAnimation {
            tree.setCompleted(item, !item.isCompleted)
            try? context.save()
        }
    }

    /// 이 일 전체의 예상 시간을 바꾼다. 아래 단계들은 비율을 지킨 채 함께 조정된다.
    private func setRootHours(_ hours: Double, label: TodoLabel?) {
        withAnimation {
            if let label { root.labelRaw = label.rawValue }
            tree.setTotalHours(root, to: hours)
            try? context.save()
        }
    }

    /// 한 단계의 비중을 직접 정한다. 나머지 단계들이 남은 몫을 다시 나눈다.
    private func setWeight(_ item: BacklogItem, _ fraction: Double) {
        LockedShareTip.hasLocked = true
        withAnimation {
            tree.setWeight(item, to: fraction)
            try? context.save()
        }
    }

    /// 직접 정한 비중을 풀고 자동(N분의 1)으로 되돌린다.
    private func release(_ item: BacklogItem) {
        withAnimation {
            tree.releaseManual(item)
            try? context.save()
        }
    }

    private func setLabel(_ item: BacklogItem, _ label: TodoLabel) {
        item.labelRaw = label.rawValue
        try? context.save()
    }

    private func remove(_ item: BacklogItem) {
        let tree = self.tree
        let parent = tree.parent(of: item)
        let victims = Set(tree.subtree(of: item).map(\.dragToken))
        withAnimation {
            for node in tree.subtree(of: item) { context.delete(node) }
            if let parent {
                // 남은 단계들이 빈 몫을 비율대로 나눠 갖는다.
                let updated = TodoTree(allItems.filter { !victims.contains($0.dragToken) })
                updated.rollUp(from: parent)
                updated.fit(under: parent)
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
        withAnimation { try? context.save() }
    }
}

// MARK: - 단계 한 줄

private struct StepRow: View {
    let item: BacklogItem
    let depth: Int
    /// 최상위 할 일 전체에서 차지하는 비중.
    let percent: Double
    /// 바로 위 부모 안에서 차지하는 비중 (조정은 이 값으로 한다).
    let weightInParent: Double
    let isCurrent: Bool
    let hasChildren: Bool
    let progress: Double
    let onToggle: () -> Void
    let onWeight: (Double) -> Void
    let onRelease: () -> Void
    let onLabel: (TodoLabel) -> Void
    let onAddChild: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if depth > 1 {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .padding(.leading, CGFloat(depth - 2) * 16)
                    .padding(.vertical, 3)
            }

            Button(action: onToggle) {
                Image(systemName: item.isCompleted
                      ? "checkmark.circle.fill"
                      : (isCurrent ? "arrowtriangle.right.circle.fill" : "circle"))
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? .green : (isCurrent ? .orange : Color.secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)

                HStack(spacing: 5) {
                    Menu {
                        ForEach(TodoLabel.allCases) { label in
                            Button("\(label.name) · \(formatDuration(label.defaultHours))") { onLabel(label) }
                        }
                    } label: {
                        TodoLabelChip(label: item.label, hours: item.durationHours)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    if item.isManualWeight {
                        Button(action: onRelease) {
                            Image(systemName: "lock.fill").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("직접 정한 비중입니다. 누르면 자동 N분의 1로 돌아갑니다.")
                    }
                }

                if hasChildren {
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? .green : .accentColor)
                        .frame(maxWidth: 160)
                }

            }

            Spacer()

            // 비중 조정 — 올리면 나머지 단계가 남은 몫을 다시 나눈다.
            Stepper(value: Binding(get: { (weightInParent * 100).rounded() },
                                   set: { onWeight($0 / 100) }),
                    in: 0...100, step: 5) {
                Text("\(percentText)%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.isCompleted ? .green : item.label.tint)
                    .frame(width: 44, alignment: .trailing)
            }
            .fixedSize()
            .opacity(hovering ? 1 : 0.6)

            if hovering {
                Button(action: onAddChild) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("하위 단계 추가")
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("삭제")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isCurrent ? Color.orange.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("하위 단계 추가", action: onAddChild)
            if item.isManualWeight {
                Button("자동 분배로 되돌리기", action: onRelease)
            }
            Button("위로", action: onMoveUp)
            Button("아래로", action: onMoveDown)
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        }
    }

    /// 0.5% 미만이라도 0%로 보이지 않게 소수 한 자리까지 쓴다.
    private var percentText: String {
        let value = percent * 100
        if value > 0 && value < 1 { return String(format: "%.1f", value) }
        return String(Int(value.rounded()))
    }
}

// MARK: - 라벨 칩

extension TodoLabel {
    /// 라벨의 색. iOS·맥이 같은 색을 쓰도록 라벨마다 하나씩 못 박아 둔다.
    var tint: Color {
        switch self {
        case .now:     return .green
        case .sit:     return .teal
        case .focus:   return .indigo
        case .block:   return .purple
        case .halfDay: return .orange
        }
    }
}

/// 목록·상세·입력창 어디서나 같은 모양으로 쓰는 라벨 칩.
struct TodoLabelChip: View {
    let label: TodoLabel
    var hours: Double? = nil
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: label.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(label.name)
                .font(.system(size: 11, weight: .medium))
            if let hours {
                Text(formatDuration(hours))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .opacity(0.75)
            }
        }
        .foregroundStyle(isSelected ? Color.white : label.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(isSelected ? label.tint : label.tint.opacity(0.14)))
    }
}

// MARK: - 조각/덩어리 태그

/// 이 단계를 언제 하는 게 맞는지 한 낱말로. 규칙은 TodoSplitAdvisor(공유)에 있다.
struct ChunkTag: View {
    let kind: ChunkKind

    var body: some View {
        Text(kind.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var color: Color {
        switch kind {
        case .fragment: return .green
        case .short:    return .blue
        case .block:    return .indigo
        }
    }
}
