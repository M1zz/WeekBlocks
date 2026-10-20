import Foundation
import SwiftData
import SwiftUI

//  Stores.swift
//
//  저장소는 **한 채**다. 루틴·계획·할 일이 모두 default.store 하나에 들어간다.
//
//  ⚠️ 한때 아이폰을 따라 할 일을 별도 CloudKit 스토어로 갈랐다가 되돌렸다.
//     Core Data가 한 컨테이너에 여러 스토어를 미러링하는 것은 **데이터베이스 범위가
//     서로 다를 때만**(private/public/shared) 지원한다. private 하나에 스토어 둘을 붙이면
//     한쪽이 조용히 진다 — 실제로 아이폰이 그 구성이었고, 이긴 미러(루틴·계획)는 오가는데
//     진 쪽(할 일)은 양방향으로 한 톨도 안 건너왔다. 로그가 그것을 그대로 보여줬다:
//       ✅ 미러 조회: routines=4, blocks=8   (맥이 올린 그 숫자가 아이폰까지 내려옴)
//       ❌ 같은 시각 할 일은 맥 1개 / 아이폰 4개로 서로 안 보임
//     **다시는 이 앱에서 private DB에 스토어를 둘 이상 열지 말 것.**
//
//  PlanStore와 TodoStore는 이제 **같은 컨테이너를 보는 두 창구**다.
//  이름을 남겨 둔 것은 부르는 쪽이 무엇을 물어보는지 드러내기 위해서다.

/// 이 할 일을 마지막으로 손댄 시각. 모델에 수정 시각이 없어 만든 때·끝낸 때로 본다.
/// **떠 둔 벌과 클라우드가 준 벌을 견주는 기준**이라, 양쪽이 반드시 같은 규칙을 써야 한다.
func touchedAt(createdAt: Date, completedAt: Date?) -> Date {
    max(createdAt, completedAt ?? .distantPast)
}

// MARK: - 켤 때 한 번

@MainActor
enum StoreBootstrap {
    /// 앱이 켜질 때 **가장 먼저** 부른다. 순서가 곧 안전이다.
    ///  1) 옛 스토어에 남아 있는 할 일을 파일로 떠 둔다 (되돌릴 길).
    ///  2) 계획 스토어를 연다 — 이때 옛 할 일 테이블이 정리된다.
    ///  3) 할 일 스토어를 연다 — CloudKit이 존에 있는 할 일을 도로 채워 준다.
    ///
    /// - Parameter safeMode: 직전 실행들이 첫 화면 전에 끝났다 (→ WeekBlocksApp.launchGuard).
    ///   스토어를 열고 금고와 견주는 데까지만 하고, 그 뒤의 정리는 이번 한 번 건너뛴다.
    static func run(safeMode: Bool = false) {
        // 시험이 띄운 실행: 메모리 안 스토어만 연다. 금고·옛 스토어·다시 받기는 디스크의 진짜 파일을 만진다.
        guard !LaunchEnvironment.isUnderTest else {
            _ = PlanStore.shared
            return
        }
        // 스토어를 열기 전에 해야 하는 일이 둘 있다.
        //  ① '다시 받아오기' 요청이 걸려 있으면 로컬 사본을 먼저 버린다.
        //  ② 한때 갈라 두었던 할 일 스토어가 남아 있으면, 그 안의 할 일을 떠 온다.
        // ⓪ 무엇보다 먼저, 스토어 파일을 통째로 떠 둔다 (→ DataVault.swift).
        //    업데이트 뒤 첫 실행이면 반드시. 아래 무엇이 잘못되든 이 순간의 바이트로 돌아갈 수 있다.
        DataVault.copyStoreFilesBeforeOpen(PlanStore.storeFileURLs)
        TodoStore.consumeRefetchRequestIfNeeded()
        LegacyTodoArchive.captureFromSplitStoreIfNeeded()

        _ = PlanStore.shared
        // 연 **직후**, 무엇을 정리하기도 전에 지난번 마지막 벌과 견준다 (→ VaultMonitor.swift).
        // 아래 정리들이 지우는 것까지 '사라짐'으로 보지 않게, 견준 뒤에 이번 벌을 뜬다.
        VaultMonitor.shared.start(container: PlanStore.shared.container)
        guard !safeMode else {
            AppLog.launch.notice("세이프 모드 — 켤 때 정리를 건너뛴다")
            return
        }
        TodoStore.shared.pullForwardOverdueWeeks()
        // 동기화가 막혀 있던 동안 두 기기가 각자 만든 같은 것이 한꺼번에 내려온다.
        // 켤 때 한 번 정리하고, 늦게 도착하는 것은 아래 판정이 한 번 더 본다.
        StoreBootstrap.dedupeAll()
        TodoStore.shared.scheduleArchiveReconcile()
    }

    /// 겹쳐 들어온 것들을 한 번에 정리한다. 켤 때, 그리고 내려받기가 자리 잡은 뒤 한 번 더.
    static func dedupeAll() {
        PlanStore.shared.dedupeBlocks()
        TodoStore.shared.dedupeCategoriesByName()
        TodoStore.shared.dedupeByDragToken()
        TodoStore.shared.dedupeProjectsByUUID()
        PlanStore.shared.dedupeRainbowEvents()
    }
}

// MARK: - 계획 스토어

@MainActor
final class PlanStore {
    static let shared = PlanStore()

    static let containerID = "iCloud.com.devkoan.ScheduleDensity"
    /// 이 앱이 iCloud로 오가는 전부. **한 스토어에 여섯 타입**이 함께 산다.
    /// ⚠️ `ProMark`는 일곱 번째 타입이다 — "한쪽에서 샀다"는 표 (→ ProMark.swift).
    /// ⚠️ `Project`는 여덟 번째 — 할 일을 끝이 있는 일로 묶는다 (→ BacklogCategory.swift).
    /// ⚠️ `RainbowEvent`는 아홉 번째 — 아이폰 무지개 일정을 맥과 함께 쓰는 사본 (→ RainbowEvent.swift).
    /// ⚠️ `DeletionMark`는 열 번째 — 사람이 지운 것의 표 (→ DeletionMark.swift).
    ///    아이폰 스토어의 같은 목록과 **글자 하나까지 같아야 한다.**
    static let schema = Schema([Routine.self, PlanBlock.self, BacklogItem.self,
                                RoutineOccurrence.self, BacklogCategory.self, QuotaPlacement.self,
                                ProMark.self, Project.self, RainbowEvent.self, DeletionMark.self])

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private init() {
        container = PlanStore.makeContainer()
    }

    /// 이 앱의 스토어 파일들. 이름을 한 곳에서만 말한다 —
    /// 설정을 바꿔 파일 이름이 달라지면 '다시 받아오기'가 조용한 무동작이 된다.
    static var storeFileURLs: [URL] {
        let base = URL.applicationSupportDirectory.appending(path: "default.store")
        return ["", "-wal", "-shm"].map { URL(fileURLWithPath: base.path + $0) }
    }

    private static func makeContainer() -> ModelContainer {
        // ⚠️ groupContainer: .none 을 반드시 명시한다.
        //    공유 익스텐션용 App Group entitlement가 붙으면 SwiftData의 기본 저장 위치가
        //    앱 샌드박스 → App Group 컨테이너로 바뀐다. 그러면 이미 배포된 사용자의
        //    기존 store를 못 찾고 빈 스토어를 새로 만들어, 루틴·계획이 전부
        //    사라진 것처럼 보인다. (iOS '욕망의 무지개'도 같은 이유로 못박아 두었다.)
        // 시험이 띄운 실행은 메모리 안에서만 — 사람의 스토어와 iCloud 는 건드리지 않는다 (→ LaunchEnvironment).
        let config = LaunchEnvironment.isUnderTest
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                 groupContainer: .none, cloudKitDatabase: .none)
            : ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .none,
                cloudKitDatabase: .private(containerID)
            )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer failed: \(error)")
        }
    }

    // MARK: 다른 스토어에서 물어보는 것들

    func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    func save() { try? context.save() }

    /// **같은 주·같은 요일·같은 제목·같은 시각**의 블록이 둘 이상이면 먼저 만든 것만 남긴다.
    ///
    /// 동기화가 멈춰 있는 동안 두 기기가 같은 할 일을 각자 요일에 올리면, 다시 이어졌을 때
    /// 서로 다른 레코드로 둘 다 내려온다. 사람이 보기엔 같은 일이 두 번 잡힌 것이라
    /// 남은 시간 계산까지 어긋난다.
    /// 회고(reviewStatus)가 적힌 쪽이 있으면 그쪽을 남긴다 — 사람이 손댄 흔적이 우선이다.
    ///
    /// ⚠️ **시각까지 열쇠에 넣는다.** 예전에는 제목만 보아서, 같은 날 10시·15시 "회의"처럼
    ///    일부러 둘 세운 것 중 하나를 켤 때마다 지웠고, 그 지우기가 모든 기기로 퍼졌다.
    ///    (분 단위로 본다 — 두 기기가 같은 일을 올리면 시각도 같다. 금고의 placeKey와 같은 기준)
    func dedupeBlocks() {
        struct Key: Hashable { let title: String; let day: Int; let week: Date; let minute: Int }
        var keep: [Key: PlanBlock] = [:]
        var victims: [PlanBlock] = []
        for block in fetch(PlanBlock.self) {
            let key = Key(title: block.title, day: block.dayRaw, week: block.weekStartDate,
                          minute: Int((block.startHour * 60).rounded()))
            guard let kept = keep[key] else { keep[key] = block; continue }
            let keptHasReview = kept.reviewStatusRaw != nil
            let thisHasReview = block.reviewStatusRaw != nil
            let thisWins = (thisHasReview && !keptHasReview)
                || (thisHasReview == keptHasReview
                    && (block.createdAt, Self.tieBreak(block)) < (kept.createdAt, Self.tieBreak(kept)))
            if thisWins {
                keep[key] = block
                victims.append(kept)
            } else {
                victims.append(block)
            }
        }
        guard !victims.isEmpty else { return }
        for v in victims { context.delete(v) }
        save()
        AppLog.store.info("겹쳐 있던 계획 블록 \(victims.count, privacy: .public)개를 정리했다")
    }

    /// 만든 때까지 같을 때 고르는 기준. 기기마다 다른 가져온 순서가 아니라 내용으로 가른다.
    static func tieBreak(_ b: PlanBlock) -> String {
        "\(b.durationHours)|\(b.successCriteria)|\(b.deliverable)|\(b.nextAction ?? "")|\(b.calendarEventID ?? "")"
    }

    /// **같은 uuid의 무지개 일정**이 둘 이상이면 하나만 남긴다.
    ///
    /// 금고 되살리기나 공용 스토어 다시 받기가 겹치면 같은 일정이 행 둘로 선다. 화면은 uuid로
    /// 그려서 둘이 부딪히고, 아이폰은 그중 아무 하나를 집어 기기마다 다른 행을 볼 수 있다.
    /// '지움' 표가 있는 행이 이긴다 — 사람이 지운 것이 겹친 행 때문에 되살아나면 안 된다.
    /// 그다음은 나중에 고친 것, 그래도 같으면 내용으로 가른다 — 어느 기기가 정리해도 같은 행이 남는다.
    func dedupeRainbowEvents() {
        func rank(_ e: RainbowEvent) -> (Int, Date, String) {
            (e.deletedAt != nil ? 1 : 0, e.updatedAt, "\(e.title)|\(e.startDate.timeIntervalSince1970)|\(e.endDate.timeIntervalSince1970)|\(e.colorHex)")
        }
        var keep: [String: RainbowEvent] = [:]
        var victims: [RainbowEvent] = []
        for e in fetch(RainbowEvent.self) {
            guard let kept = keep[e.uuid] else { keep[e.uuid] = e; continue }
            if rank(e) > rank(kept) {
                // 지움 표는 진 쪽에 있었어도 이긴 쪽으로 옮긴다.
                if e.deletedAt == nil, let d = kept.deletedAt { e.deletedAt = d }
                keep[e.uuid] = e
                victims.append(kept)
            } else {
                if kept.deletedAt == nil, let d = e.deletedAt { kept.deletedAt = d }
                victims.append(e)
            }
        }
        guard !victims.isEmpty else { return }
        for v in victims { context.delete(v) }
        save()
        AppLog.store.info("겹쳐 있던 무지개 일정 \(victims.count, privacy: .public)개를 정리했다")
    }
}

// MARK: - 할 일 스토어

@MainActor
final class TodoStore {
    static let shared = TodoStore()

    /// ⚠️ 별도 스토어를 열지 않는다. 계획과 **같은 컨테이너**를 본다.
    ///    private DB에 스토어를 둘 붙이면 한쪽이 조용히 동기화를 멈춘다(→ 파일 머리말).
    var container: ModelContainer { PlanStore.shared.container }
    var context: ModelContext { container.mainContext }

    private init() { }

    /// 사용자가 설정에서 '다시 받아오기'를 눌렀는가. 스토어를 **열기 전에** 봐야 해서
    /// 파일이 아니라 UserDefaults에 둔다.
    private static let refetchKey = "todoStore.refetchFromCloud"

    /// 설정에서 부른다. 지금 있는 할 일을 먼저 떠 두고, 다음 실행 때 로컬 사본을 버리게 표시한다.
    /// 앱이 스토어를 열고 있는 동안에는 파일을 지울 수 없어서 **다음 실행**으로 미룬다.
    func requestRefetchFromCloud() {
        LegacyTodoArchive.write(items: allItems(), categories: categories(), projects: projects())
        LegacyTodoArchive.reconcilePending = true
        VaultMonitor.shared.snapshotNow(reason: "before-refetch", force: true)
        UserDefaults.standard.set(true, forKey: TodoStore.refetchKey)
    }

    /// 요청이 걸려 있으면 로컬 스토어를 지운다. 변경 토큰이 사라져 CloudKit이
    /// **존에 있는 것을 처음부터 전부** 내려준다. 지우기 직전에 할 일을 떠 두므로
    /// 클라우드가 못 준 것은 뒤이어 되살아난다.
    ///
    /// ⚠️ 스토어가 한 채이므로 루틴·계획도 함께 다시 받는다. 아직 안 올라간 변경이 있으면
    ///    그것은 잃는다 — 그래서 사람이 눌렀을 때만 한다.
    static func consumeRefetchRequestIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: refetchKey) else { return }
        defaults.set(false, forKey: refetchKey)

        // ⚠️ **지우지 않고 금고로 옮긴다.** 아직 iCloud에 못 올라간 것이 이 파일에만 있을 수 있다.
        //    옮기지 못하면 아무것도 버리지 않고 그대로 연다 — 다시 받기를 못 하는 편이 잃는 것보다 낫다.
        guard DataVault.moveStoreFilesAside(PlanStore.storeFileURLs, reason: "refetch") else {
            AppLog.store.error("로컬 사본을 금고로 옮기지 못해 다시 받기를 그만둔다")
            return
        }
        AppLog.store.info("로컬 사본을 금고로 옮겼다 — iCloud에서 처음부터 받는다")
    }

    // MARK: 계획 화면이 물어보는 것들
    //
    // 주간 화면은 계획 스토어 위에 서 있어서 할 일을 @Query 할 수 없다.
    // 요일에 떨어뜨린 카드 하나를 집어 오는 일만 여기로 물어본다.

    func allItems() -> [BacklogItem] {
        let d = FetchDescriptor<BacklogItem>(sortBy: [SortDescriptor(\.sortIndex),
                                                      SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    func item(dragToken: String) -> BacklogItem? {
        allItems().first { $0.dragToken == dragToken }
    }

    func categories() -> [BacklogCategory] {
        let d = FetchDescriptor<BacklogCategory>(sortBy: [SortDescriptor(\.sortIndex),
                                                          SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    func projects() -> [Project] {
        let d = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortIndex),
                                                  SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    func save() { try? context.save() }

    /// 안 끝난 일의 주차(`weekStartDate`)를 이번 주로 끌어온다. **켤 때 한 번.**
    ///
    /// 예전에는 '이번 주로' 버튼을 사람이 줄마다 눌렀다. 그런데 안 끝난 일이 지난 주에
    /// 남아 있다는 사실은 딱지로 말할 것이 아니라 그냥 목록에 서 있으면 되는 것이었다.
    /// 주차는 이제 결산이 "이번 주에 무엇을 했나"를 세는 자리로만 쓴다.
    /// **완료한 일은 건드리지 않는다** — 지난 주에 끝낸 것은 지난 주의 셈이다.
    /// (→ iOS TodoView.pullForwardOverdueWeeks 와 같은 규칙)
    ///
    /// ⚠️ 화면의 onAppear에 두지 않는다. 목록을 세우는 뷰가 두 창에 동시에 떠 있어서
    ///    같은 데이터 정리가 두 번 돌고, 스크롤로 다시 나타날 때마다 또 돈다.
    func pullForwardOverdueWeeks() {
        let weekStart = Date.currentWeekStart
        let cal = Calendar(identifier: .iso8601)
        let tree = TodoTree(allItems())
        let stale = tree.roots.filter {
            !$0.isCompleted && $0.weekStartDate < weekStart
                && !cal.isDate($0.weekStartDate, inSameDayAs: weekStart)
        }
        guard !stale.isEmpty else { return }
        for root in stale {
            // 단계도 부모와 한 덩어리로 같이 옮긴다.
            for node in tree.subtree(of: root) { node.weekStartDate = weekStart }
        }
        save()
    }

    // MARK: 비상구 — 더 최신인 쪽을 세운다

    /// 스토어를 나눈 뒤, **두 벌 중 어느 쪽이 더 최신인지 보고 최신 쪽을 세운다.**
    ///
    ///  · 클라우드가 내려준 것 = 지금 스토어에 들어 있는 할 일
    ///  · 떠 둔 것 = 나누기 직전 옛 스토어에서 뜬 JSON (→ LegacyTodoArchive)
    ///
    /// 둘의 '마지막으로 손댄 시각'(만든 때·끝낸 때 중 가장 늦은 것)을 비교해서,
    /// 떠 둔 쪽이 더 최신일 때만 모자란 것을 채운다. 클라우드가 더 최신이면 손대지 않는다 —
    /// 오래된 벌을 위에 덮으면 아이폰에서 지운 할 일이 되살아난다.
    ///
    /// 채울 때는 dragToken이 없는 것만 넣고, 마지막에 같은 토큰이 둘이면 정리한다.
    /// 같은 할 일이 둘로 보이는 것이 데이터가 안 보이는 것만큼 나쁘기 때문이다.
    ///
    /// ⚠️ **떠 둔 직후 한 번만 돈다** (다시 받아오기 · 갈라 둔 스토어 흡수 → `reconcilePending`).
    ///    예전에는 파일이 있는 맥에서 켤 때마다 돌아서, 아이폰에서 가장 최근 할 일을 지우면
    ///    '떠 둔 쪽이 더 최신'이 되어 그사이 다른 기기에서 지운 것까지 모두 되살렸다.
    ///    평소의 안전망은 이제 금고(→ DataVault)가 맡는다.
    func scheduleArchiveReconcile() {
        guard LegacyTodoArchive.exists, LegacyTodoArchive.reconcilePending else { return }
        Task { @MainActor in
            // 처음 내려받기가 자리 잡을 시간을 준다. 내려오는 중에 판단하면 항상 '떠 둔 쪽이 최신'이 된다.
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            reconcileWithArchive()
            LegacyTodoArchive.reconcilePending = false
            StoreBootstrap.dedupeAll()
        }
    }

    /// 위 판단을 실제로 한 번 수행한다.
    func reconcileWithArchive() {
        guard let archive = LegacyTodoArchive.load() else { return }
        // 어느 갈래로 빠지든 겹친 것을 정리하고 안전망을 최신으로 둔다.
        defer {
            dedupeByDragToken()
            refreshArchive()
        }

        let items = allItems()
        let cloudStamp = TodoStore.lastTouched(items)
        let archiveStamp = archive.lastTouched

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        AppLog.store.info("""
            최신 비교 — 클라우드 \(items.count, privacy: .public)개(\(f.string(from: cloudStamp), privacy: .public)) \
            vs 떠 둔 것 \(archive.items.count, privacy: .public)개(\(f.string(from: archiveStamp), privacy: .public))
            """)

        guard !archive.items.isEmpty else {
            AppLog.store.info("떠 둔 것이 비어 있다 — 지금 있는 것으로 안전망을 세운다")
            return
        }
        guard archiveStamp > cloudStamp else {
            AppLog.store.info("클라우드 쪽이 더 최신이라 그대로 둔다")
            return
        }

        let known = Set(items.map(\.dragToken))
        let knownCategories = Set(categories().map(\.uuid))
        let knownProjects = Set(projects().map(\.uuid))
        // 어느 기기에서든 사람이 지운 것은 세우지 않는다 (→ DeletionMark.swift).
        let marked = DeletionLog.marks(in: context)
        var added = 0
        for row in archive.categories where !knownCategories.contains(row.uuid)
            && !marked.contains("category:\(row.uuid)") {
            context.insert(row.model())
        }
        // 프로젝트도 uuid 그대로 — 할 일이 projectID로 붙잡고 있다. 옛 스냅샷에는 없다(nil).
        for row in archive.projects ?? [] where !knownProjects.contains(row.uuid)
            && !marked.contains("project:\(row.uuid)") {
            context.insert(row.model())
        }
        for row in archive.items where !known.contains(row.dragToken) && !marked.contains("item:\(row.dragToken)") {
            context.insert(row.model())
            added += 1
        }
        save()
        AppLog.store.info("떠 둔 쪽이 더 최신 — 모자란 할 일 \(added, privacy: .public)개를 세웠다")
    }

    /// 판정이 끝난 **지금의 한 벌**을 안전망으로 다시 떠 둔다.
    /// 스냅샷이 스토어를 나누던 시점에 얼어붙어 있으면, 다음 비교가 늘 옛 벌을 보고 판단한다.
    func refreshArchive() {
        let items = allItems()
        let categories = self.categories()
        let projects = self.projects()
        // 켤 때마다 같은 내용을 다시 직렬화해 디스크에 쓸 이유가 없다.
        // (프로젝트를 새로 만들기만 해도 다시 떠야 하므로 그 수도 본다.)
        if let current = LegacyTodoArchive.load(),
           current.items.count == items.count,
           current.categories.count == categories.count,
           (current.projects?.count ?? 0) == projects.count,
           current.lastTouched == TodoStore.lastTouched(items) {
            return
        }
        LegacyTodoArchive.write(items: items, categories: categories, projects: projects)
    }

    /// 이름이 같은 분류를 **가장 먼저 만들어진 하나로** 합친다.
    ///
    /// 두 기기가 각자 기본 분류(업무·개인·건강·학습)를 심으면 이름은 같고 uuid는 다른
    /// 짝이 생긴다. 항목은 uuid로 분류를 붙잡고 있으므로, 합치기 전에 참조부터 옮긴다.
    func dedupeCategoriesByName() {
        var survivors: [String: BacklogCategory] = [:]
        var duplicates: [BacklogCategory] = []
        for c in categories().sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = c.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            if survivors[key] == nil { survivors[key] = c } else { duplicates.append(c) }
        }
        guard !duplicates.isEmpty else { return }

        let items = allItems()
        for dup in duplicates {
            let key = dup.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let keep = survivors[key] else { continue }
            for item in items where item.categoryID == dup.uuid {
                item.categoryID = keep.uuid
            }
            context.delete(dup)
        }
        save()
        AppLog.store.info("이름이 겹치던 분류 \(duplicates.count, privacy: .public)개를 합쳤다")
    }

    /// 같은 dragToken이 둘 이상이면 **가장 최근에 손댄 것 하나만** 남긴다.
    /// (단계가 부모의 토큰으로 매달려 있어서, 토큰이 겹치면 트리도 갈라진다)
    func dedupeByDragToken() {
        var seen: [String: BacklogItem] = [:]
        var victims: [BacklogItem] = []
        for item in allItems() {
            guard let kept = seen[item.dragToken] else { seen[item.dragToken] = item; continue }
            // 손댄 때가 같으면 내용으로 가른다. 가져온 순서는 기기마다 달라서, 그것으로 고르면
            // 두 맥이 서로 다른 쪽을 지워 결국 둘 다 사라질 수 있다.
            let a = (TodoStore.touched(item), TodoStore.tieBreak(item))
            let b = (TodoStore.touched(kept), TodoStore.tieBreak(kept))
            if a > b {
                seen[item.dragToken] = item
                victims.append(kept)
            } else {
                victims.append(item)
            }
        }
        guard !victims.isEmpty else { return }
        for v in victims { context.delete(v) }
        save()
        AppLog.store.info("같은 할 일이 겹쳐 있던 \(victims.count, privacy: .public)개를 정리했다")
    }

    /// **같은 uuid의 프로젝트**가 둘 이상이면 하나만 남긴다.
    /// 할 일은 projectID(uuid)로 붙잡고 있어서 어느 쪽을 지워도 할 일은 떨어지지 않는다.
    /// 끝낸 표가 있는 쪽 → 먼저 만든 쪽 → 이름 순으로 고른다 — 어느 기기가 정리해도 같은 쪽이 남는다.
    func dedupeProjectsByUUID() {
        func rank(_ p: Project) -> (Int, Double, String) {
            (p.isCompleted ? 1 : 0, -p.createdAt.timeIntervalSince1970, "\(p.name)|\(p.colorName)|\(p.sortIndex)")
        }
        var keep: [String: Project] = [:]
        var victims: [Project] = []
        for p in projects() {
            guard let kept = keep[p.uuid] else { keep[p.uuid] = p; continue }
            if rank(p) > rank(kept) {
                keep[p.uuid] = p
                victims.append(kept)
            } else {
                victims.append(p)
            }
        }
        guard !victims.isEmpty else { return }
        for v in victims { context.delete(v) }
        save()
        AppLog.store.info("겹쳐 있던 프로젝트 \(victims.count, privacy: .public)개를 정리했다")
    }

    static func tieBreak(_ item: BacklogItem) -> String {
        "\(item.title)|\(item.durationHours)|\(item.isCompleted)|\(item.weekStartDate.timeIntervalSince1970)"
    }

    static func touched(_ item: BacklogItem) -> Date {
        touchedAt(createdAt: item.createdAt, completedAt: item.completedAt)
    }

    static func lastTouched(_ items: [BacklogItem]) -> Date {
        items.map(touched).max() ?? .distantPast
    }
}

// MARK: - 옛 스토어에 남은 할 일을 떠 두는 곳
//
// 할 일을 JSON 한 벌로 떠 둔다. 스키마와 무관하게 사람이 열어 읽고 되살릴 수 있는 형태다.
// 클라우드가 내려준 벌과 견줄 기준이 되고, 클라우드가 못 준 것을 되살리는 마지막 그물이다.
// **지우지 않는다.** 몇백 KB가 아까울 자리가 아니다.

enum LegacyTodoArchive {
    private static var supportDirectory: URL {
        URL.applicationSupportDirectory
    }
    private static var archiveURL: URL {
        supportDirectory.appending(path: "legacy-todos.json")
    }
    static var exists: Bool {
        FileManager.default.fileExists(atPath: archiveURL.path)
    }

    /// 떠 둔 것을 아직 견주지 않았다. 다시 받아오기·스토어 흡수 때만 켜지고, 한 번 견주면 꺼진다.
    static var reconcilePending: Bool {
        get { UserDefaults.standard.bool(forKey: "legacyArchive.reconcilePending") }
        set { UserDefaults.standard.set(newValue, forKey: "legacyArchive.reconcilePending") }
    }

    /// 갈라 두었던 `WeekBlocksTodos.store`가 아직 남아 있으면, 그 안의 할 일을 떠 온다.
    ///
    /// 스토어를 도로 한 채로 합치면서 그 파일은 더 이상 열지 않는다. 대부분은 클라우드에도
    /// 같은 것이 있어 저절로 돌아오지만, 갈라져 있는 동안 이 기기에서만 적은 것이 있을 수 있다.
    /// 그것을 잃지 않으려고 한 번 떠서 안전망에 합쳐 둔다 (되살리기는 dragToken으로 겹치지 않게).
    static func captureFromSplitStoreIfNeeded() {
        let key = "didAbsorbSplitTodoStore.v1"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }

        let splitURL = supportDirectory.appending(path: "WeekBlocksTodos.store")
        guard FileManager.default.fileExists(atPath: splitURL.path) else {
            defaults.set(true, forKey: key)
            return
        }
        do {
            let schema = Schema([BacklogItem.self, BacklogCategory.self])
            // 오프라인으로 연다 — 이 파일이 다시 미러링에 끼어들면 안 된다.
            let config = ModelConfiguration("WeekBlocksTodos", schema: schema,
                                            groupContainer: .none, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let items = try context.fetch(FetchDescriptor<BacklogItem>())
            let categories = try context.fetch(FetchDescriptor<BacklogCategory>())
            write(items: items, categories: categories)
            reconcilePending = true
            defaults.set(true, forKey: key)
            AppLog.store.info("갈라 두었던 스토어에서 할 일 \(items.count, privacy: .public)개를 떠 왔다")
        } catch {
            AppLog.store.error("갈라 두었던 스토어를 못 읽었다: \(String(describing: error), privacy: .public)")
        }
    }

    /// 지금 스토어에 있는 것을 그대로 떠서 덮어쓴다.
    /// '다시 받아오기' 직전에 부른다 — 클라우드가 못 돌려주는 것이 있어도 이 파일이 남는다.
    static func write(items: [BacklogItem], categories: [BacklogCategory], projects: [Project] = []) {
        let snapshot = Snapshot(capturedAt: Date(),
                                items: items.map(ItemRow.init),
                                categories: categories.map(CategoryRow.init),
                                projects: projects.map(ProjectRow.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(snapshot).write(to: archiveURL, options: .atomic)
            AppLog.store.info("지금 할 일 \(items.count, privacy: .public)개를 떠 두었다")
        } catch {
            AppLog.store.error("스냅샷 쓰기 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 떠 둔 것을 읽어 온다. 판단은 부르는 쪽(→ TodoStore.reconcileWithArchive)이 한다.
    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: archiveURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            AppLog.store.error("스냅샷을 읽지 못했다")
            return nil
        }
        return snapshot
    }

    // MARK: 값으로 떠 두는 모양
    //
    // @Model 객체는 스토어가 닫히면 못 읽는다. 필드를 전부 값으로 옮겨 적는다.
    // 하나라도 빠뜨리면 되살릴 때 그 필드가 사라지므로, 모델이 늘면 여기도 늘려야 한다.

    struct Snapshot: Codable {
        let capturedAt: Date
        let items: [ItemRow]
        let categories: [CategoryRow]
        /// 프로젝트가 생기기 전에 뜬 스냅샷에는 이 칸이 없다 — 옵셔널이라 그대로 읽힌다.
        var projects: [ProjectRow]? = nil

        /// 이 벌을 마지막으로 손댄 시각. 항목이 없으면 뜬 시각으로 본다.
        var lastTouched: Date {
            items.map { touchedAt(createdAt: $0.createdAt, completedAt: $0.completedAt) }
                .max() ?? capturedAt
        }
    }

    struct ItemRow: Codable {
        var title: String
        var durationHours: Double
        var sortIndex: Int
        var createdAt: Date
        var dragToken: String
        var categoryID: String?
        /// 옛 스냅샷에는 없다 — 옵셔널이라 nil 로 읽힌다.
        var projectID: String?
        var weekStartDate: Date
        var isCompleted: Bool
        var completedAt: Date?
        var parentToken: String?
        var labelRaw: String?

        init(_ m: BacklogItem) {
            title = m.title
            durationHours = m.durationHours
            sortIndex = m.sortIndex
            createdAt = m.createdAt
            dragToken = m.dragToken
            categoryID = m.categoryID
            projectID = m.projectID
            weekStartDate = m.weekStartDate
            isCompleted = m.isCompleted
            completedAt = m.completedAt
            parentToken = m.parentToken
            labelRaw = m.labelRaw
        }

        /// 되살릴 때는 dragToken까지 그대로 돌려놓는다 —
        /// 단계(뎁스)가 부모의 dragToken으로 매달려 있어서, 토큰이 바뀌면 쪼갠 것이 흩어진다.
        func model() -> BacklogItem {
            let m = BacklogItem(title: title,
                                durationHours: durationHours,
                                sortIndex: sortIndex,
                                categoryID: categoryID,
                                weekStartDate: weekStartDate)
            m.dragToken = dragToken
            m.createdAt = createdAt
            m.isCompleted = isCompleted
            m.completedAt = completedAt
            m.parentToken = parentToken
            m.labelRaw = labelRaw
            m.projectID = projectID
            return m
        }
    }

    struct CategoryRow: Codable {
        var uuid: String
        var name: String
        var colorName: String
        var iconName: String
        var sortIndex: Int
        var createdAt: Date

        init(_ m: BacklogCategory) {
            uuid = m.uuid
            name = m.name
            colorName = m.colorName
            iconName = m.iconName
            sortIndex = m.sortIndex
            createdAt = m.createdAt
        }

        /// uuid도 그대로 돌려놓는다 — 할 일이 categoryID로 이 값을 붙잡고 있다.
        func model() -> BacklogCategory {
            let m = BacklogCategory(name: name, colorName: colorName,
                                    iconName: iconName, sortIndex: sortIndex)
            m.uuid = uuid
            m.createdAt = createdAt
            return m
        }
    }

    struct ProjectRow: Codable {
        var uuid: String
        var name: String
        var colorName: String
        var sortIndex: Int
        var createdAt: Date
        var isCompleted: Bool
        var completedAt: Date?

        init(_ m: Project) {
            uuid = m.uuid
            name = m.name
            colorName = m.colorName
            sortIndex = m.sortIndex
            createdAt = m.createdAt
            isCompleted = m.isCompleted
            completedAt = m.completedAt
        }

        /// uuid도 그대로 — 할 일이 projectID로 이 값을 붙잡고 있다.
        func model() -> Project {
            let m = Project(name: name, colorName: colorName, sortIndex: sortIndex)
            m.uuid = uuid
            m.createdAt = createdAt
            m.isCompleted = isCompleted
            m.completedAt = completedAt
            return m
        }
    }
}

// MARK: - 두 스토어가 만나는 자리
