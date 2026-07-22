import SwiftUI
import SwiftData

struct BacklogSection: View {
    @Environment(\.modelContext) private var context

    let allItems: [BacklogItem]
    let weekStart: Date
    /// 고정 루틴이 확보돼 있을 때만 할 일을 작성할 수 있다.
    var canPlan: Bool = true

    @Query(sort: [SortDescriptor(\BacklogCategory.sortIndex), SortDescriptor(\BacklogCategory.createdAt)])
    private var categories: [BacklogCategory]

    @AppStorage("didSeedBacklogCategories") private var didSeedCategories = false

    @State private var filterCategoryID: String? = nil   // nil = 전체
    @State private var showingComposer = false
    @State private var showingAllBacklog = false

    private let cal = Calendar(identifier: .iso8601)

    /// 이번 주 백로그. (iOS Todo에서 완료 처리한 항목은 제외)
    private var weekItems: [BacklogItem] {
        allItems.filter { !$0.isCompleted && cal.isDate($0.weekStartDate, inSameDayAs: weekStart) }
    }

    private var filteredItems: [BacklogItem] {
        guard let f = filterCategoryID else { return weekItems }
        return weekItems.filter { $0.categoryID == f }
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
                Label("백로그 — 이번 주", systemImage: "tray.full")
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
                    HStack(spacing: 4) {
                        Label("전체 백로그", systemImage: "archivebox")
                        if carryoverCount > 0 {
                            Text("\(carryoverCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.borderless)

                Button {
                    showingComposer = true
                } label: {
                    Label("할 일 작성", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .disabled(!canPlan)
            }

            // 카테고리 필터 칩
            if !categories.isEmpty && canPlan {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(label: "전체", color: .secondary, icon: "square.grid.2x2",
                                   selected: filterCategoryID == nil) { filterCategoryID = nil }
                        ForEach(categories) { c in
                            FilterChip(label: c.name, color: c.displayColor, icon: c.iconName,
                                       selected: filterCategoryID == c.uuid) {
                                filterCategoryID = (filterCategoryID == c.uuid) ? nil : c.uuid
                            }
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
                            onDelete: { context.delete(item); try? context.save() },
                            onSetCategory: { id in item.categoryID = id; try? context.save() }
                        )
                    }
                }
            }
        }
        .task { seedCategoriesIfNeeded() }
        .sheet(isPresented: $showingComposer) {
            BacklogComposerView(weekStart: weekStart)
                .frame(minWidth: 540, minHeight: 560)
        }
        .sheet(isPresented: $showingAllBacklog) {
            AllBacklogView(currentWeek: weekStart)
                .frame(minWidth: 560, minHeight: 600)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Text(weekItems.isEmpty
                 ? "이번 주 할 일이 아직 없습니다."
                 : "이 카테고리엔 할 일이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if weekItems.isEmpty {
                Button {
                    showingComposer = true
                } label: {
                    Label("할 일 작성", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var lockedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("고정 루틴을 먼저 추가하면 할 일을 계획할 수 있습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func seedCategoriesIfNeeded() {
        guard !didSeedCategories, categories.isEmpty else { return }
        didSeedCategories = true
        let defaults: [(String, String, String)] = [
            ("업무", "blue", "briefcase"),
            ("개인", "green", "person"),
            ("건강", "orange", "heart"),
            ("학습", "purple", "book"),
        ]
        for (i, d) in defaults.enumerated() {
            context.insert(BacklogCategory(name: d.0, colorName: d.1, iconName: d.2, sortIndex: i))
        }
        try? context.save()
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let icon: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
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
    let item: BacklogItem
    let categories: [BacklogCategory]
    let tint: Color
    let onDelete: () -> Void
    let onSetCategory: (String?) -> Void

    @State private var hovering = false

    private var category: BacklogCategory? { categories.first { $0.uuid == item.categoryID } }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if let category {
                        Text(category.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(tint)
                    }
                    Text(String(format: "%.1fh", item.durationHours))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.30), lineWidth: 0.6))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(item.dragToken)
        .onHover { hovering = $0 }
        .help("드래그해서 요일에 배치")
        .contextMenu {
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
                        Label(c.name, systemImage: item.categoryID == c.uuid ? "checkmark" : c.iconName)
                    }
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

// MARK: - 할 일 작성 (이번 주, TODO 리스트 방식)

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
    @State private var showingCategoryManager = false
    @FocusState private var focused: Bool

    private let cal = Calendar(identifier: .iso8601)
    private var weekItems: [BacklogItem] {
        allItems.filter { !$0.isCompleted && cal.isDate($0.weekStartDate, inSameDayAs: weekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("이번 주 할 일").font(.title3.weight(.medium))
                    Text("입력하고 Enter ↵ 로 계속 추가하세요").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingCategoryManager = true } label: {
                    Label("카테고리", systemImage: "tag")
                }
                .buttonStyle(.borderless)
            }
            .padding(20)

            Divider()

            // TODO 방식 입력 줄 — 제목 입력 후 Enter 로 즉시 추가, 포커스 유지
            HStack(spacing: 10) {
                categoryDefaultMenu
                TextField("할 일 입력 후 Enter", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(addAndContinue)
                Button("추가", action: addAndContinue)
                    .buttonStyle(.borderless)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
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

            HStack {
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
                    Label(c.name, systemImage: defaultCategoryID == c.uuid ? "checkmark" : c.iconName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(current?.displayColor ?? Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                Text(current?.name ?? "미분류").font(.callout)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("새 항목의 기본 카테고리")
    }

    private func addAndContinue() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let maxIndex = allItems.map(\.sortIndex).max() ?? -1
        context.insert(BacklogItem(title: t, durationHours: 1, sortIndex: maxIndex + 1,
                                   categoryID: defaultCategoryID, weekStartDate: weekStart))
        try? context.save()
        newTitle = ""
        focused = true
    }
}

struct ComposerItemRow: View {
    @Bindable var item: BacklogItem
    let categories: [BacklogCategory]
    @Environment(\.modelContext) private var context
    let onDelete: () -> Void

    private var category: BacklogCategory? { categories.first { $0.uuid == item.categoryID } }

    var body: some View {
        HStack(spacing: 10) {
            categoryMenu

            TextField("할 일", text: $item.title)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                TextField("", value: $item.durationHours, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 38)
                    .multilineTextAlignment(.trailing)
                Text("h").font(.callout).foregroundStyle(.secondary)
            }
            Stepper("", value: $item.durationHours, in: 0.25...12, step: 0.25)
                .labelsHidden()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: item.title) { _, _ in try? context.save() }
        .onChange(of: item.durationHours) { _, _ in try? context.save() }
    }

    private var categoryMenu: some View {
        Menu {
            Button { item.categoryID = nil; try? context.save() } label: {
                Label("미분류", systemImage: item.categoryID == nil ? "checkmark" : "circle")
            }
            Divider()
            ForEach(categories) { c in
                Button { item.categoryID = c.uuid; try? context.save() } label: {
                    Label(c.name, systemImage: item.categoryID == c.uuid ? "checkmark" : c.iconName)
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

    /// 항목이 존재하는 주들 (최신 주 우선).
    private var weeks: [Date] {
        var seen = Set<Date>(); var result: [Date] = []
        for it in allItems where !seen.contains(it.weekStartDate) {
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

            if allItems.isEmpty {
                Spacer()
                Text("백로그가 비어 있습니다.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(weeks, id: \.self) { week in
                            let items = allItems.filter { cal.isDate($0.weekStartDate, inSameDayAs: week) }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(weekLabel(week))
                                        .font(.headline)
                                        .foregroundStyle(isCurrent(week) ? Color.accentColor : .primary)
                                    Text("\(items.count)개").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("합계 \(formatDuration(items.reduce(0) { $0 + $1.durationHours }))")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                                ForEach(items) { item in
                                    AllBacklogRow(
                                        item: item,
                                        categories: categories,
                                        isCurrentWeek: isCurrent(week),
                                        onCarry: { item.weekStartDate = currentWeek; try? context.save() },
                                        onDelete: { context.delete(item); try? context.save() }
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
            if item.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1fh", item.durationHours))
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()

            if !isCurrentWeek && !item.isCompleted {
                Button(action: onCarry) {
                    Label("이번 주로", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("이 항목을 이번 주 백로그로 가져옵니다")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 10))
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
                            CategoryEditRow(category: c) {
                                deleteCategory(c)
                            }
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
}

struct CategoryEditRow: View {
    @Bindable var category: BacklogCategory
    @Environment(\.modelContext) private var context
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ColorPickerMenu(colorName: $category.colorName)
                .onChange(of: category.colorName) { _, _ in try? context.save() }
            IconPickerMenu(iconName: $category.iconName, colorName: $category.colorName)
                .onChange(of: category.iconName) { _, _ in try? context.save() }

            TextField("이름", text: $category.name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: category.name) { _, _ in try? context.save() }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
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
                .font(.system(size: 13))
                .foregroundStyle(paletteColor(colorName))
                .frame(width: 20, height: 16)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("아이콘 선택")
    }
}
