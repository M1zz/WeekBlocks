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

@main
struct WeekBlocksApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // LeeoKit 사용량 트래커 — 리뷰 요청·만족도 프롬프트 게이팅에 쓰인다.
        _ = LeeoEngagement.shared.registerLaunch()
        // 할 일 화면의 조언은 전부 TipKit으로 낸다 (→ TodoTips.swift).
        TodoTips.configure()
    }

    let container: ModelContainer = {
        let schema = Schema([Routine.self, PlanBlock.self, BacklogItem.self, RoutineOccurrence.self, BacklogCategory.self, QuotaPlacement.self])
        // ⚠️ groupContainer: .none 을 반드시 명시한다.
        //    공유 익스텐션용 App Group entitlement가 붙으면 SwiftData의 기본 저장 위치가
        //    앱 샌드박스 → App Group 컨테이너로 바뀐다. 그러면 이미 배포된 사용자의
        //    기존 store를 못 찾고 빈 스토어를 새로 만들어, 루틴·계획·백로그가 전부
        //    사라진 것처럼 보인다. (iOS '욕망의 무지개'도 같은 이유로 못박아 두었다.)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none,
            cloudKitDatabase: .private("iCloud.com.devkoan.ScheduleDensity")
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer failed: \(error)")
        }
    }()

    var body: some Scene {
        // 단일 창 앱: Window 씬을 쓰면 창을 닫아도
        // "윈도우" 메뉴(및 Dock 아이콘 클릭)로 다시 열 수 있다. (App Store 심사 Guideline 4 대응)
        Window("무지개 공방", id: "main") {
            ContentView()
                .leeoSatisfactionCheck(WeekBlocksSpec.self)
                // 다른 앱에서 공유한 할 일 받기. 공유 익스텐션은 SwiftData에 직접 못 쓰고
                // App Group에 쌓아만 두므로, 앱이 켜지고 앞으로 나올 때 그 상자를 비운다.
                .task { TodoShareIntake.drain(into: container.mainContext) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { TodoShareIntake.drain(into: container.mainContext) }
                }
        }
        .modelContainer(container)
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
