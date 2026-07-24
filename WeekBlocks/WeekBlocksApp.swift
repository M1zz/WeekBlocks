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

    init() {
        // LeeoKit 사용량 트래커 — 리뷰 요청·만족도 프롬프트 게이팅에 쓰인다.
        _ = LeeoEngagement.shared.registerLaunch()
    }

    let container: ModelContainer = {
        let schema = Schema([Routine.self, PlanBlock.self, BacklogItem.self, RoutineOccurrence.self, BacklogCategory.self, QuotaPlacement.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
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
        }
        .modelContainer(container)
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
