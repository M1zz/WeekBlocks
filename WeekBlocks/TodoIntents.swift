//
//  TodoIntents.swift
//  WeekBlocks
//
//  "무지개 공방에 할 일 추가" — 떠오른 일을 말로 이번 주 백로그에 넣는다. 창을 띄우지 않는다.
//
//  공유 익스텐션과 같은 길(받은 상자 → TodoShareIntake)로 넣는다. 넣는 규칙(이번 주, 맨 아래,
//  기본 시간)이 한 곳에만 있게 하려는 것이다. 앱이 떠 있으면 바로 비워 백로그에 보인다.
//

import AppIntents
import Foundation

struct AddTodoIntent: AppIntent {
    static let title = LocalizedStringResource("할 일 추가", comment: "Siri: add a to-do to this week's backlog")
    static let description = IntentDescription(
        LocalizedStringResource("이번 주 백로그 맨 아래에 할 일을 넣습니다.", comment: "Siri: add to-do description")
    )
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("할 일", comment: "Siri: to-do text parameter"),
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
