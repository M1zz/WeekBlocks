import SwiftUI
import CloudKit

/// 가족 공유 할 일 섹션 (macOS).
/// iOS '욕망의 무지개'와 CKShare 존을 공유한다 — 자세한 구조는 [[FamilyShareStore]] 참고.
struct FamilyTodoSection: View {
    @State private var store = FamilyShareStore.shared
    @State private var newTitle = ""
    @State private var showingShareNotice = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("가족 할 일", systemImage: "person.2")
                    .font(.headline)
                if !store.items.isEmpty {
                    Text("\(store.items.filter { !$0.isCompleted }.count)개 남음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isBusy)

                shareControls
            }

            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.mode == .owner && store.shareURL != nil {
                Text("초대 링크를 받은 사람은 누구나 참여할 수 있습니다. 링크는 가족에게만 보내주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.iCloudAvailable {
                emptyNotice("iCloud에 로그인하면 가족과 할 일을 공유할 수 있습니다.")
            } else if store.items.isEmpty && !store.isSharing {
                emptyNotice("가족 공유를 시작하거나, 초대 링크를 받아 참여하세요. iOS 앱과 같은 목록을 씁니다.")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(store.items) { todo in
                        FamilyTodoBlock(
                            todo: todo,
                            onToggle: { Task { await store.toggle(todo) } },
                            onDelete: { Task { await store.delete(todo) } }
                        )
                    }
                }

                // 인라인 추가 줄
                HStack(spacing: 8) {
                    TextField("가족 할 일 입력 후 Enter", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(add)
                        .frame(maxWidth: 340)
                    Button("추가", action: add)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .task { await store.refresh() }
    }

    @ViewBuilder
    private var shareControls: some View {
        switch store.mode {
        case .participant:
            Button {
                Task { await store.leave() }
            } label: {
                Label("공유 나가기", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderless)
        default:
            if let url = store.shareURL {
                ShareLink(item: url) {
                    Label("초대 링크", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                Button {
                    Task { await store.stopSharing() }
                } label: {
                    Label("공유 중지", systemImage: "person.2.slash")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    showingShareNotice = true
                } label: {
                    Label("가족 공유 시작", systemImage: "person.2.badge.plus")
                }
                .buttonStyle(.borderless)
                .disabled(!store.iCloudAvailable || store.isBusy)
                .alert("가족 공유 시작", isPresented: $showingShareNotice) {
                    Button("공유 시작") {
                        Task { await store.startSharing() }
                    }
                    Button("취소", role: .cancel) { }
                } message: {
                    Text("초대 링크를 받은 사람은 누구나 이 목록에 참여해 함께 읽고 쓸 수 있습니다.\n링크는 가족에게만 보내주세요.")
                }
            }
        }
    }

    private func emptyNotice(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        newTitle = ""
        focused = true
        Task { await store.add(title: t) }
    }
}

private struct FamilyTodoBlock: View {
    let todo: FamilyTodo
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(todo.isCompleted ? .green : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 12, weight: .medium))
                .strikethrough(todo.isCompleted)
                .foregroundStyle(todo.isCompleted ? Color.secondary : Color.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.25), lineWidth: 0.6))
        .onHover { hovering = $0 }
    }
}
