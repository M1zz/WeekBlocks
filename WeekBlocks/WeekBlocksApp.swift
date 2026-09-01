import SwiftUI
import SwiftData
import CloudKit
import LeeoKit

/// CloudKit 일정 공유 초대 링크를 눌렀을 때 수락 콜백을 받는다.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await ScheduleShareStore.shared.accept(metadata) }
    }
}

/// 창 id는 여는 쪽(ContentView)과 세우는 쪽(WeekBlocksApp)이 함께 쓰므로 한 곳에 둔다.
enum WeekBlocksWindow {
    static let main = "main"
    static let todos = "todos"
}

@main
struct WeekBlocksApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// 이 앱이 쓰는 단 하나의 컨테이너 (→ Stores.swift).
    ///
    /// ⚠️ **저장 프로퍼티로 두지 말 것.** 기본값 초기화는 `init()` 본문보다 먼저 돌기 때문에,
    ///    저장 프로퍼티로 두면 "스토어를 열기 전에" 해야 하는 일(다시 받기 요청 처리 등)이
    ///    정작 열린 **뒤에** 돌아 아무 효과가 없다.
    private let container: ModelContainer

    init() {
        // 저장소를 세우는 일이 가장 먼저다. 순서가 곧 안전이다 (→ Stores.swift).
        StoreBootstrap.run()
        container = PlanStore.shared.container
        // LeeoKit 사용량 트래커 — 리뷰 요청·만족도 프롬프트 게이팅에 쓰인다.
        _ = LeeoEngagement.shared.registerLaunch()
        // 할 일 화면의 조언은 전부 TipKit으로 낸다 (→ TodoTips.swift).
        TodoTips.configure()
    }

    var body: some Scene {
        // 단일 창 앱: Window 씬을 쓰면 창을 닫아도
        // "윈도우" 메뉴(및 Dock 아이콘 클릭)로 다시 열 수 있다. (App Store 심사 Guideline 4 대응)
        Window("무지개 공방", id: WeekBlocksWindow.main) {
            ContentView()
                .leeoSatisfactionCheck(WeekBlocksSpec.self)
                // 다른 앱에서 공유한 할 일 받기. 공유 익스텐션은 SwiftData에 직접 못 쓰고
                // App Group에 쌓아만 두므로, 앱이 켜지고 앞으로 나올 때 그 상자를 비운다.
                // 받은 할 일은 할 일 스토어로 들어간다.
                .task { TodoShareIntake.drain(into: TodoStore.shared.context) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { TodoShareIntake.drain(into: TodoStore.shared.context) }
                }
        }
        .modelContainer(container)
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // 할 일은 따로 선 창이다 (→ TodoWindowView).
        // 적는 일과 한 주를 짜는 일은 손이 오가는 방향이 달라서, 나란히 놓고 쓸 수 있어야 한다.
        Window("할 일", id: WeekBlocksWindow.todos) {
            TodoWindowView()
        }
        .modelContainer(container)
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
