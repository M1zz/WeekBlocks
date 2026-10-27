import SwiftUI
import SwiftData
import CloudKit
import LeeoKit

/// CloudKit 일정 공유 초대 링크를 눌렀을 때 수락 콜백을 받고,
/// **조용한 푸시를 받을 자리를 연다.**
final class MacAppDelegate: NSObject, NSApplicationDelegate {

    /// **아이폰이 적은 것을 기다리지 않고 받는다.**
    ///
    /// 미러링은 상대가 뭔가 올리면 조용한 푸시로 알려 주는데, 그 푸시는 앱이 APNs에
    /// 등록해야 온다. 등록을 안 하면 코어데이터는 켤 때와 이따금 도는 예약 작업에서만
    /// 내려받아서, 아이폰에서 적은 줄이 **몇 분 뒤에** 나타난다 (재어 보니 8분 21초였다.
    /// 반대 방향은 3초 — 아이폰에는 푸시 권한이 붙어 있었기 때문이다).
    ///
    /// ⚠️ 권한(`com.apple.developer.aps-environment`)이 없으면 등록이 실패한다.
    ///    실패해도 앱은 그대로 돌아간다 — 늦게 받을 뿐이다. 그래서 실패를 로그로만
    ///    남기고 사용자에게는 말하지 않는다. 대신 로그를 보면 원인이 바로 드러난다.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppLog.push.info("등록됨 — 아이폰이 올린 것을 바로 받는다")
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLog.push.error("등록 실패 — 아이폰이 적은 것이 몇 분 늦게 온다: \(String(describing: error), privacy: .public)")
    }

    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await ScheduleShareStore.shared.accept(metadata) }
    }
}

/// 창 id는 여는 쪽(ContentView)과 세우는 쪽(WeekBlocksApp)이 함께 쓰므로 한 곳에 둔다.
enum WeekBlocksWindow {
    static let main = "main"
    static let todos = "todos"
    static let timer = "timer"
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

    /// **켤 때마다 같은 자리에서 죽으면 다음 실행은 세이프 모드로** (LeeoKit `LeeoCrashLoopGuard`).
    ///
    /// 두 번 잇달아 첫 화면까지 못 가고 끝났으면, 켤 때 돌던 정리(겹친 것 합치기·지난 주 끌어오기·
    /// 떠 둔 벌과 맞추기)와 공유 메뉴로 받은 상자 비우기를 이번 한 번 건너뛴다. 받은 상자 파일 하나가
    /// 깨져 있으면 켤 때마다 같은 자리에서 죽는데, 그러면 사람은 앱을 지우는 것 말고 할 수 있는 게 없다.
    /// 스토어를 열고 금고에 떠 두는 일은 **세이프 모드에서도 한다** — 그게 데이터를 지키는 쪽이다.
    /// 세이프 모드로 무사히 뜨면 횟수가 0으로 돌아가고, 그다음 실행은 평소대로 연다.
    static let launchGuard = LeeoCrashLoopGuard(name: "app", defaults: .standard)
    /// 이번 실행이 세이프 모드인가. `init()` 이 한 번 정한다.
    static private(set) var isSafeMode = false

    init() {
        // 단위 시험의 숙주: 메모리 안 스토어만 세우고 끝낸다. 진단·통계·원격 스위치는 iCloud 권한을
        // 요구해서, 서명 없이 도는 CI 에서는 켜는 순간 멈춘다 (→ LaunchEnvironment).
        if LaunchEnvironment.isUnitTestHost {
            StoreBootstrap.run()
            container = PlanStore.shared.container
            return
        }
        Self.isSafeMode = Self.launchGuard.beginLaunch()
        if Self.isSafeMode {
            AppLog.launch.fault("직전 실행 \(Self.launchGuard.consecutiveIncompleteLaunches, privacy: .public)번이 첫 화면 전에 끝났다 — 세이프 모드로 연다")
        }
        // 저장소를 세우는 일이 가장 먼저다. 순서가 곧 안전이다 (→ Stores.swift).
        AppLog.measure("StoreBootstrap") { StoreBootstrap.run(safeMode: Self.isSafeMode) }
        container = PlanStore.shared.container
        // **계약을 켜는 한 줄** (→ WeekBlocksSpec.swift). 이걸 안 부르면 계약을 아무리
        // 잘 채워도 아무 일도 안 일어난다 — 실행 횟수가 안 세지니 만족도·리뷰 프롬프트가
        // 영영 안 뜨고, 분석 싱크가 안 꽂히니 페이월을 봤는지조차 알 수 없다.
        //
        // ⚠️ 사용현황 스냅샷만 여기서 끈다(`usageReporting: false`). LeeoKit 기본 스냅샷은
        //    실행 횟수·설치 후 경과일까지만 담는데, 이 앱은 할 일·계획·루틴 개수까지 실어
        //    보낸다. 그러려면 스토어가 선 뒤라야 해서 창이 열릴 때 따로 부른다
        //    (→ Telemetry.reportSnapshot). 여기서 끄지 않으면 같은 스냅샷이 숫자 없이
        //    먼저 올라가고, 12시간 간격에 걸려 **숫자 있는 쪽이 하루 종일 안 올라간다.**
        //
        // 원격 스위치(→ WeekBlocksFlag.swift)도 여기서 켠다 — 마지막으로 받아 둔 값을 백그라운드로 새로 받는다.
        LeeoKit.bootstrap(WeekBlocksSpec.self, flags: WeekBlocksFlag.self, usageReporting: false)
        // 할 일 화면의 조언은 전부 TipKit으로 낸다 (→ TodoTips.swift).
        TodoTips.configure()
    }

    var body: some Scene {
        // 단일 창 앱: Window 씬을 쓰면 창을 닫아도
        // "윈도우" 메뉴(및 Dock 아이콘 클릭)로 다시 열 수 있다. (App Store 심사 Guideline 4 대응)
        Window("무지개 공방", id: WeekBlocksWindow.main) {
            // 단위 시험의 숙주로 떴으면 창을 그리지 않는다 — 시험은 순수 로직만 본다 (→ LaunchEnvironment).
            if LaunchEnvironment.isUnitTestHost {
                Color.clear.frame(width: 1, height: 1)
            } else {
                mainWindow
            }
        }
        .modelContainer(container)
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            // 앱 이름 메뉴의 '설정' 자리 옆. 설정 단추를 못 읽어도 여기는 모든 맥 앱에 있다 (→ AppLanguage.swift).
            CommandGroup(after: .appSettings) {
                AppLanguageMenu()
            }
            // 처음 쓰는 사람이 길을 잃었을 때 찾아가는 곳은 메뉴 막대의 '도움말'이다.
            // 설정 안에만 두면 거기까지 가지 못한다.
            CommandGroup(replacing: .help) {
                Button("무지개 공방 사용법") {
                    OnboardingPresenter.shared.present()
                }
            }
        }

        // 할 일은 따로 선 창이다 (→ TodoWindowView).
        // 적는 일과 한 주를 짜는 일은 손이 오가는 방향이 달라서, 나란히 놓고 쓸 수 있어야 한다.
        Window("할 일", id: WeekBlocksWindow.todos) {
            TodoWindowView()
                .fontDesign(.rounded)
        }
        .modelContainer(container)
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
        .keyboardShortcut("t", modifiers: [.command, .shift])

        // 하고 있는 하나와 거기 남은 시간 (→ TimerView.swift).
        // 한 주를 짜는 창과 따로 세운다 — 계획을 보는 동안에도 옆에 띄워 둘 수 있어야 한다.
        Window("타이머", id: WeekBlocksWindow.timer) {
            TimerWindowView()
                .fontDesign(.rounded)
        }
        .modelContainer(container)
        .defaultSize(width: 400, height: 500)
        .windowResizability(.contentMinSize)
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    /// 한 주를 짜는 창.
    private var mainWindow: some View {
            ContentView()
                // **둥근 서체.** 알약·동그라미와 글씨가 같은 결이어야 말랑하게 읽힌다.
                // 서체를 따로 고른 글씨(`design:` 지정)는 그대로 둔다.
                .fontDesign(.rounded)
                .leeoSatisfactionCheck(WeekBlocksSpec.self)
                // 업데이트 뒤 처음 열 때 한 번 "새로 생긴 것" (→ WhatsNewView.swift).
                .whatsNewOnUpdate()
                // 사람이 지우지 않았는데 없어진 것이 있으면 되살릴지 묻는다 (→ VaultMonitor.swift).
                .vaultRecoveryPrompt()
                // 구독 중이면 6개월째 · 갱신 7일 전에 한 번 평생가를 보인다 (→ GraduationOffer.swift).
                .graduationOfferOnLaunch()
                // 다른 앱에서 공유한 할 일 받기. 공유 익스텐션은 SwiftData에 직접 못 쓰고
                // App Group에 쌓아만 두므로, 앱이 켜지고 앞으로 나올 때 그 상자를 비운다.
                // 받은 할 일은 할 일 스토어로 들어간다.
                .task {
                    // 세이프 모드에서는 받은 상자를 건드리지 않는다 — 깨진 파일 하나가 원인일 수 있다.
                    guard !Self.isSafeMode else { return }
                    TodoShareIntake.drain(into: TodoStore.shared.context)
                }
                // 첫 화면이 서고 몇 초 버티면 이번 실행은 무사히 뜬 것이다 (→ launchGuard).
                .task {
                    Self.launchGuard.markLaunchSucceededAfterSurvivalDelay()
                    // 못 뜬 횟수를 허브로 — 끈 사람에게는 보내지 않는다 (→ Telemetry.isEnabled).
                    if Telemetry.isEnabled {
                        await Self.launchGuard.reportIncompleteLaunches(to: Telemetry.reporter)
                    }
                }
                // 켤 때 영수증을 다시 읽는다 (→ MacEntitlement.swift).
                // UserDefaults에 적힌 값은 화면이 빨리 그려지라고 둔 거울일 뿐이라,
                // 다른 맥에서 산 것·환불된 것은 여기서 읽지 않으면 영영 안 잡힌다.
                // 페이월을 열 때만 읽던 시절에는 산 사람이 잠긴 화면을 먼저 봐야 했다.
                .task {
                    await PurchaseManager.shared.refresh()
                    // 영수증을 읽은 **뒤에** 맞춘다. 순서가 뒤집히면 헌 거울을 보고
                    // 산 사람의 줄을 닫는다 (→ TodoSharing.swift).
                    TodoSharing.reconcileMySharing(in: TodoStore.shared.context)
                    // 이 설치가 지금 어떤 모습인지 한 줄로 올린다 (→ Telemetry.swift).
                    // 스토어가 선 뒤라야 개수를 셀 수 있어서 init이 아니라 여기다.
                    // 끈 사람에게는 아무것도 나가지 않는다.
                    Telemetry.reportSnapshot()
                    Telemetry.recordOpen()
                }
                .onChange(of: scenePhase) { _, phase in
                    // 뒤로 갈 때 한 벌 떠 둔다 — 같은 내용이면 금고가 알아서 건너뛴다.
                    if phase == .background { VaultMonitor.shared.snapshotNow(reason: "background") }
                    guard phase == .active else { return }
                    // 켜 둔 채 날이 바뀌고 다시 앞으로 온 날도 '연 날'이다 (→ Telemetry.recordOpen).
                    Telemetry.recordOpen()
                    if !Self.isSafeMode { TodoShareIntake.drain(into: TodoStore.shared.context) }
                    // 앱을 켜 둔 채 다른 기기에서 사고 돌아오는 길.
                    Task { await PurchaseManager.shared.refresh() }
                }
    }
}
