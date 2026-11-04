//
//  TodoIntents.swift
//  WeekBlocks
//
//  "무지개 공방에 할 일 추가" — 떠오른 일을 말로 이번 주 백로그에 넣는다. 창을 띄우지 않는다.
//
//  공유 익스텐션과 같은 길(받은 상자 → TodoShareIntake)로 넣는다. 넣는 규칙(이번 주, 맨 아래,
//  기본 시간)이 한 곳에만 있게 하려는 것이다. 앱이 떠 있으면 바로 비워 백로그에 보인다.
//
//  아직 안 끝낸 할 일은 Spotlight 에 싣는다(macOS 15+). Siri 도 그걸로 할 일을 찾는다.
//  누르면 그 할 일의 단계 창이 열린다. 다른 기기에서 감춘 줄은 싣지 않는다(→ TodoSharing.swift).
//

import AppIntents
import CoreSpotlight
import Foundation

struct AddTodoIntent: AppIntent {
    static let title = LocalizedStringResource("할 일 추가", comment: "Siri: add a to-do to this week's backlog")
    static let description = IntentDescription(
        LocalizedStringResource("이번 주 백로그 맨 아래에 할 일을 넣습니다.", comment: "Siri: add to-do description")
    )
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("할 일", comment: "Siri: to-do text parameter"),
               description: LocalizedStringResource("이번 주 할 일로 넣을 내용", comment: "Siri: to-do text parameter description"),
               requestValueDialog: IntentDialog(LocalizedStringResource("무엇을 넣을까요?", comment: "Siri: ask for the to-do text")))
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, TodoShareInbox.add(SharedTodoDraft(title: text)) else {
            return .result(dialog: IntentDialog(LocalizedStringResource("할 일을 넣지 못했어요.", comment: "Siri: could not add the to-do")))
        }
        // 세이프 모드에서는 상자를 건드리지 않는다 — 다음에 앱이 정상으로 켜질 때 들어간다.
        if !WeekBlocksApp.isSafeMode { TodoShareIntake.drain(into: TodoStore.shared.context) }
        return .result(dialog: IntentDialog(LocalizedStringResource("‘\(text)’을 이번 주 할 일에 넣었어요.", comment: "Siri: to-do added. Argument is the to-do text")))
    }

    /// 화면에서 할 일을 적었을 때 Siri 에 알린다 — 자주 하는 일을 Siri 가 먼저 떠올린다.
    static func donate(_ text: String) {
        let intent = AddTodoIntent()
        intent.title = text
        Task { _ = try? await IntentDonationManager.shared.donate(intent: intent) }
    }
}

// MARK: - 할 일 (Spotlight · Siri 가 찾는 것)

/// 열어 달라는 할 일. 할 일 판(BacklogSection)이 단계 창으로 열고 비운다.
@MainActor @Observable
final class TodoOpenRequest {
    static let shared = TodoOpenRequest()
    private init() { }
    var dragToken: String?
}

struct TodoEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("할 일", comment: "Siri/Spotlight: one to-do in the backlog")
    )
    static let defaultQuery = TodoEntityQuery()

    /// BacklogItem.dragToken — 기기를 건너도 같은 줄을 가리킨다.
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(_ item: BacklogItem) {
        id = item.dragToken
        title = item.title
    }

    /// 아직 안 끝낸 최상위 할 일, 이 기기에 그리는 것만. 목록과 같은 순서.
    @MainActor
    static func open() -> [TodoEntity] {
        guard !WeekBlocksApp.isSafeMode else { return [] }
        return TodoStore.shared.allItems()
            .filter { $0.parentToken == nil && !$0.isCompleted && !$0.title.isEmpty && TodoSharing.isVisible($0) }
            .map(TodoEntity.init)
    }

    /// Spotlight 에 싣는 할 일을 지금 것에 맞춘다. 앱이 앞으로 올 때와 뒤로 갈 때 부른다.
    @MainActor
    static func reindex() async {
        guard #available(macOS 15.0, *) else { return }
        let entities = open()
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: TodoEntity.self)
        try? await index.indexAppEntities(entities)
    }
}

@available(macOS 15.0, *)
extension TodoEntity: IndexedEntity {}

struct TodoEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TodoEntity] {
        let wanted = Set(identifiers)
        return TodoEntity.open().filter { wanted.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TodoEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return TodoEntity.open().filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [TodoEntity] {
        Array(TodoEntity.open().prefix(20))
    }
}

/// 할 일을 연다. Spotlight · Siri 결과를 누르면 여기로 온다.
struct OpenTodoIntent: OpenIntent {
    static let title = LocalizedStringResource("할 일 열기", comment: "Siri/Spotlight: open a to-do")
    static let description = IntentDescription(
        LocalizedStringResource("할 일을 골라 그 단계 창을 엽니다.", comment: "Siri: open to-do description")
    )

    @Parameter(title: LocalizedStringResource("할 일", comment: "Siri: to-do parameter"),
               description: LocalizedStringResource("열어 볼 할 일", comment: "Siri: to-do parameter description"))
    var target: TodoEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        TodoOpenRequest.shared.dragToken = target.id
        return .result()
    }
}

struct WeekBlocksShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTodoIntent(),
            phrases: ["Add a to-do to \(.applicationName)", "New to-do in \(.applicationName)"],
            shortTitle: "할 일 추가",
            systemImageName: "plus.circle"
        )
    }
}
