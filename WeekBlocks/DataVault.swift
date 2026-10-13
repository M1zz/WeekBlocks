//
//  DataVault.swift
//  무지개 공방
//
//  **사람이 적은 것은 어떤 업데이트·동기화·버튼을 거쳐도 잃지 않는다.**
//
//  2026-10 — 지난주에 만든 프로젝트 안의 할 일이 흔적도 없이 사라졌다. 데이터가 사는 곳이
//  스토어 한 채뿐이었고, 유일한 안전망(legacy-todos.json)은 켤 때마다 **줄어든 상태로 다시
//  떠져서** 스스로 비워졌다. 그날 무엇이 지웠는지는 지금도 모른다. 모르는 원인까지 막으려면
//  "지우지 않는다"가 아니라 "**지워져도 되돌릴 수 있다**"여야 한다.
//
//  그래서 세 겹으로 둔다. 어느 한 겹이 비어도 나머지가 남는다.
//
//   1층 · 스토어 파일 통째 사본 — 스토어를 **열기 전에** 뜬다. 업데이트로 빌드가 바뀐 첫 실행에는
//         반드시, 그 밖에는 하루에 한 번. 마이그레이션·미러 초기화가 무엇을 하든 그 직전 바이트가 남는다.
//   2층 · 모든 모델을 값으로 뜬 JSON — 켤 때 · 저장 뒤 · 끝낼 때. 날짜마다 **새 파일**로 쌓는다.
//         덮어쓰지 않으므로 줄어든 벌이 늘어난 벌을 지울 수 없다.
//   3층 · 같은 JSON을 iCloud Drive에 — CloudKit 미러링과 **다른 길**이다. 미러가 지운 것도 여기는 남는다.
//
//  그리고 감시한다. 켤 때 지난번 마지막 벌에 있던 것이 지금 없으면, 사람이 지운 게 아니므로
//  목록을 보여 주고 되살리기를 권한다 (→ VaultMonitor).
//
//  ⚠️ 되살리기는 **없는 것만 더한다.** 지금 있는 것을 덮거나 지우지 않는다. 같은 것이 둘이
//     되는 것은 고칠 수 있지만, 덮어서 잃은 것은 못 고친다.
//  ⚠️ 아이폰 '욕망의 무지개'의 같은 이름 파일과 **값의 모양(Row)이 같아야 한다.**
//     한쪽에서 뜬 백업을 다른 쪽에서 읽을 수 있어야 하기 때문이다.
//

import Foundation
import SwiftData

enum DataVault {

    // MARK: - 자리

    static var root: URL {
        rootOverride ?? URL.applicationSupportDirectory.appending(path: "DataVault", directoryHint: .isDirectory)
    }
    /// 시험할 때만 바꾼다. 앱은 늘 nil.
    nonisolated(unsafe) static var rootOverride: URL?
    static var storeCopiesDirectory: URL { root.appending(path: "StoreFiles", directoryHint: .isDirectory) }
    static var snapshotsDirectory: URL { root.appending(path: "Snapshots", directoryHint: .isDirectory) }

    /// iCloud Drive 쪽 사본이 들어가는 컨테이너. 엔타이틀먼트의 ubiquity 컨테이너와 같아야 한다.
    static let ubiquityContainerID = "iCloud.com.devkoan.ScheduleDensity"

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short)(\(build))"
    }

    private static let lastBuildKey = "vault.lastBuild"
    private static let lastStoreCopyKey = "vault.lastStoreCopyAt"
    private static let lastDigestKey = "vault.lastDigest"
    static let iCloudLastKey = "vault.iCloudLastAt"
    static let iCloudErrorKey = "vault.iCloudError"

    private static let fm = FileManager.default

    /// 이번 실행이 업데이트 뒤 첫 실행인가. 스토어를 열기 전에 정해진다.
    nonisolated(unsafe) private(set) static var launchedAfterUpdate = false

    private static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    private static func ensure(_ dir: URL) {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - 1층 · 스토어 파일 통째 사본

    /// 스토어를 **열기 전에** 부른다. 이미 열린 스토어를 복사하면 -wal 과 본 파일이 어긋날 수 있다.
    ///
    /// 빌드가 바뀌었으면(= 업데이트 뒤 첫 실행) 언제나 뜬다. 아니면 마지막 사본이 20시간 넘었을 때만.
    ///
    /// - Parameter label: 스토어가 여럿이면 저마다 이름을 준다. 언제 떴는지를 따로 센다.
    ///   `main`(함께 쓰는 스토어)만 '업데이트 뒤 첫 실행'을 정한다.
    static func copyStoreFilesBeforeOpen(_ urls: [URL], label: String = "main") {
        guard let main = urls.first, fm.fileExists(atPath: main.path) else { return }  // 새로 깐 사람
        let defaults = UserDefaults.standard
        let buildKey = "\(lastBuildKey).\(label)", copyKey = "\(lastStoreCopyKey).\(label)"
        let updated = defaults.string(forKey: buildKey) != appVersion
        if label == "main", updated { launchedAfterUpdate = true }
        let last = defaults.object(forKey: copyKey) as? Date ?? .distantPast
        guard updated || Date().timeIntervalSince(last) > 20 * 3600 else { return }

        let reason = (updated ? "update" : "daily") + (label == "main" ? "" : "-\(label)")
        if copyStoreFiles(urls, reason: reason) != nil {
            defaults.set(appVersion, forKey: buildKey)
            defaults.set(Date(), forKey: copyKey)
        }
        pruneStoreCopies()
    }

    /// 파일을 그대로 베낀다. 크기까지 같은지 확인한 뒤에만 성공으로 친다.
    @discardableResult
    static func copyStoreFiles(_ urls: [URL], reason: String) -> URL? {
        let dir = storeCopiesDirectory.appending(path: "\(stamp())_\(reason)_\(appVersion)", directoryHint: .isDirectory)
        ensure(dir)
        var ok = true
        for url in urls where fm.fileExists(atPath: url.path) {
            let dest = dir.appending(path: url.lastPathComponent)
            do {
                try fm.copyItem(at: url, to: dest)
                let a = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
                let b = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -2
                if a != b { ok = false }
            } catch {
                ok = false
                print("⚠️ [Vault] 스토어 파일 사본 실패(\(url.lastPathComponent)): \(error)")
            }
        }
        print(ok ? "🧱 [Vault] 스토어 파일 사본(\(reason)) → \(dir.lastPathComponent)"
                 : "⚠️ [Vault] 스토어 파일 사본이 온전하지 않다(\(reason)) — 폴더는 남겨 둔다")
        return ok ? dir : nil
    }

    /// 스토어 파일을 **지우는 대신 금고로 옮긴다.** '다시 받아오기'처럼 로컬 사본을 버려야 할 때 쓴다.
    /// 하나라도 못 옮기면 false — 부르는 쪽은 그때 아무것도 하지 말아야 한다.
    static func moveStoreFilesAside(_ urls: [URL], reason: String) -> Bool {
        let existing = urls.filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return true }
        let dir = storeCopiesDirectory.appending(path: "\(stamp())_\(reason)_\(appVersion)", directoryHint: .isDirectory)
        ensure(dir)
        // 옮기기 전에 먼저 베낀다. 옮기다 반쯤 실패해도 원래 자리에 남은 것과 사본이 함께 있다.
        for url in existing {
            do { try fm.copyItem(at: url, to: dir.appending(path: url.lastPathComponent)) } catch {
                print("⚠️ [Vault] 옮기기 전 사본 실패 — 버리지 않는다: \(error)")
                return false
            }
        }
        for url in existing { try? fm.removeItem(at: url) }
        print("📦 [Vault] 스토어 파일을 금고로 옮겼다(\(reason)) → \(dir.lastPathComponent)")
        return true
    }

    /// 사본 정리. **업데이트 직전 사본과 옮겨 둔 원본(refetch 등)은 자동으로 지우지 않는다** —
    /// 그것이 그 시점의 유일한 원본일 수 있다. 하루치 사본만 최근 10개로 줄인다.
    private static func pruneStoreCopies() {
        guard let dirs = try? fm.contentsOfDirectory(at: storeCopiesDirectory, includingPropertiesForKeys: nil) else { return }
        let daily = dirs.filter { $0.lastPathComponent.contains("_daily") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in daily.dropFirst(10) { try? fm.removeItem(at: old) }
        let updates = dirs.filter { $0.lastPathComponent.contains("_update") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in updates.dropFirst(30) { try? fm.removeItem(at: old) }
    }

    // MARK: - 2층 · 값으로 뜬 한 벌

    struct Snapshot: Codable {
        var format: Int = 1
        var takenAt: Date
        var appVersion: String
        var platform: String
        var reason: String
        var items: [ItemRow]
        var categories: [CategoryRow]
        var projects: [ProjectRow]
        var blocks: [BlockRow]
        var routines: [RoutineRow]
        var occurrences: [OccurrenceRow]
        var placements: [PlacementRow]
        /// 함께 쓰는 무지개 일정 (→ RainbowEvent.swift). 옛 백업에는 없어서 옵셔널이다.
        var rainbowEvents: [RainbowRow]? = nil

        var isEmpty: Bool {
            items.isEmpty && projects.isEmpty && blocks.isEmpty && routines.isEmpty && categories.isEmpty
        }
    }

    static var platform: String {
        #if os(macOS)
        "mac"
        #else
        "ios"
        #endif
    }

    @MainActor
    static func capture(_ context: ModelContext, reason: String) -> Snapshot {
        func all<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        return Snapshot(takenAt: Date(), appVersion: appVersion, platform: platform, reason: reason,
                        items: all(BacklogItem.self).map(ItemRow.init),
                        categories: all(BacklogCategory.self).map(CategoryRow.init),
                        projects: all(Project.self).map(ProjectRow.init),
                        blocks: all(PlanBlock.self).map(BlockRow.init),
                        routines: all(Routine.self).map(RoutineRow.init),
                        occurrences: all(RoutineOccurrence.self).map(OccurrenceRow.init),
                        placements: all(QuotaPlacement.self).map(PlacementRow.init),
                        rainbowEvents: all(RainbowEvent.self).map(RainbowRow.init))
    }

    /// 지금 스토어를 한 벌 떠서 **새 파일**로 남긴다. 지난번과 내용이 같으면(자동 저장일 때) 건너뛴다.
    @MainActor
    @discardableResult
    static func writeSnapshot(_ context: ModelContext, reason: String, force: Bool = false) -> URL? {
        let snap = capture(context, reason: reason)

        // 같은 내용을 또 쓰지 않는다 — 내용만 견준다(뜬 시각·까닭은 빼고).
        let digest = contentDigest(snap)
        if !force, UserDefaults.standard.string(forKey: lastDigestKey) == digest { return nil }

        ensure(snapshotsDirectory)
        let name = "\(stamp(snap.takenAt))_\(reason)_i\(snap.items.count)_p\(snap.projects.count)_b\(snap.blocks.count).json"
        let url = snapshotsDirectory.appending(path: name)
        do {
            try encoder.encode(snap).write(to: url, options: .atomic)
        } catch {
            print("⚠️ [Vault] 스냅숏 쓰기 실패: \(error)")
            return nil
        }
        UserDefaults.standard.set(digest, forKey: lastDigestKey)
        print("🗄 [Vault] 스냅숏(\(reason)) — 할 일 \(snap.items.count) · 프로젝트 \(snap.projects.count) · 블록 \(snap.blocks.count)")
        pruneSnapshots()
        mirrorToICloudDrive(url)
        return url
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // 날짜는 숫자 그대로 — ISO 문자열은 초 아래를 버려 createdAt 으로 찾는 열쇠가 어긋난다.
        e.dateEncodingStrategy = .deferredToDate
        return e
    }

    static func load(_ url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func contentDigest(_ s: Snapshot) -> String {
        var copy = s
        copy.takenAt = .distantPast
        copy.reason = ""
        guard let data = try? encoder.encode(copy) else { return UUID().uuidString }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data { h ^= UInt64(b); h &*= 0x0000_0100_0000_01b3 }
        return String(h, radix: 16) + "-\(data.count)"
    }

    /// 떠 둔 벌들, 새것부터.
    static func snapshotFiles() -> [URL] {
        ((try? fm.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 파일 이름에서 개수를 읽는다(열지 않고). `..._i12_p3_b40.json`
    static func counts(of url: URL) -> (items: Int, projects: Int, blocks: Int) {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        func n(_ p: Character) -> Int {
            parts.last { $0.first == p && Int($0.dropFirst()) != nil }.flatMap { Int($0.dropFirst()) } ?? 0
        }
        return (n("i"), n("p"), n("b"))
    }

    static func date(of url: URL) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.date(from: String(url.lastPathComponent.prefix(15)))
    }

    /// 정리 규칙 — 남기는 것만 말한다. 나머지를 지운다.
    ///  · 최근 80벌
    ///  · 120일 안의 날마다 마지막 한 벌
    ///  · 업데이트·되살리기·지우기 직전에 뜬 벌 최근 40벌
    ///  · 할 일이 가장 많았던 3벌, 블록이 가장 많았던 3벌 (줄어든 벌이 늘어난 벌을 밀어내지 못하게)
    private static func pruneSnapshots() {
        let files = snapshotFiles()
        guard files.count > 80 else { return }
        var keep = Set(files.prefix(80))
        var seenDays = Set<String>()
        let horizon = Date().addingTimeInterval(-120 * 86400)
        for f in files {
            let day = String(f.lastPathComponent.prefix(8))
            if let d = date(of: f), d > horizon, !seenDays.contains(day) {
                seenDays.insert(day)
                keep.insert(f)
            }
        }
        let special = files.filter {
            let n = $0.lastPathComponent
            return n.contains("_launch-after-update_") || n.contains("_before-") || n.contains("_after-restore_")
        }
        keep.formUnion(special.prefix(40))
        keep.formUnion(files.sorted { counts(of: $0).items > counts(of: $1).items }.prefix(3))
        keep.formUnion(files.sorted { counts(of: $0).blocks > counts(of: $1).blocks }.prefix(3))
        for f in files where !keep.contains(f) { try? fm.removeItem(at: f) }
    }

    // MARK: - 3층 · iCloud Drive

    /// 같은 JSON을 iCloud Drive(앱의 ubiquity 컨테이너)에도 둔다. CloudKit 미러링과 별개의 길이다.
    /// iCloud Drive를 꺼 두었으면 조용히 건너뛰고, 설정에 그 사실을 보인다.
    static func mirrorToICloudDrive(_ file: URL) {
        Task.detached(priority: .utility) {
            let defaults = UserDefaults.standard
            guard let ubiq = FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerID) else {
                defaults.set(String(localized: "iCloud Drive가 꺼져 있습니다"), forKey: iCloudErrorKey)
                return
            }
            let dir = ubiq.appending(path: "Documents/Backups/\(platform)-\(TodoSharing.installID.prefix(8))",
                                     directoryHint: .isDirectory)
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appending(path: file.lastPathComponent)
            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordError) { url in
                do {
                    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                    try fm.copyItem(at: file, to: url)
                } catch { writeError = error }
            }
            if let e = coordError ?? writeError {
                defaults.set(e.localizedDescription, forKey: iCloudErrorKey)
                return
            }
            defaults.set(Date(), forKey: iCloudLastKey)
            defaults.removeObject(forKey: iCloudErrorKey)
            // iCloud 쪽은 최근 60벌 + 업데이트·지우기 직전 벌만 남긴다.
            let all = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in all.dropFirst(60) {
                let n = old.lastPathComponent
                if n.contains("_launch-after-update_") || n.contains("_before-") { continue }
                try? fm.removeItem(at: old)
            }
        }
    }

    // MARK: - 사라진 것 찾기

    /// 기준 벌에는 있는데 지금 스토어에는 없는 것들.
    struct Missing {
        var base: URL
        var baseTakenAt: Date
        var items: [ItemRow] = []
        var categories: [CategoryRow] = []
        var projects: [ProjectRow] = []
        var blocks: [BlockRow] = []
        var routines: [RoutineRow] = []
        var occurrences: [OccurrenceRow] = []
        var placements: [PlacementRow] = []
        var rainbowEvents: [RainbowRow] = []

        /// 사람에게 말할 만한 것의 수. 요일 배치(occurrence·placement)는 루틴이 있으면 저절로 다시 선다.
        var total: Int {
            items.count + projects.count + blocks.count + routines.count + categories.count + rainbowEvents.count
        }
        var isEmpty: Bool { total == 0 && occurrences.isEmpty && placements.isEmpty }
    }

    /// 무엇이 없어졌는가. **같은 것으로 볼 수 있는 것이 남아 있으면 없어진 것으로 치지 않는다** —
    /// 겹친 것을 정리한 결과(같은 토큰·같은 이름·같은 날 같은 제목)를 사라짐으로 오해하지 않게.
    @MainActor
    static func missing(in context: ModelContext, comparedTo base: Snapshot, at url: URL) -> Missing {
        let now = capture(context, reason: "compare")
        var m = Missing(base: url, baseTakenAt: base.takenAt)

        let tokens = Set(now.items.map(\.dragToken))
        m.items = base.items.filter { !tokens.contains($0.dragToken) }

        let catIDs = Set(now.categories.map(\.uuid))
        let catNames = Set(now.categories.map { $0.name.lowercased() })
        m.categories = base.categories.filter { !catIDs.contains($0.uuid) && !catNames.contains($0.name.lowercased()) }

        let projectIDs = Set(now.projects.map(\.uuid))
        m.projects = base.projects.filter { !projectIDs.contains($0.uuid) }

        let blockKeys = Set(now.blocks.map(\.identityKey))
        let blockPlaces = Set(now.blocks.map(\.placeKey))
        m.blocks = base.blocks.filter { !blockKeys.contains($0.identityKey) && !blockPlaces.contains($0.placeKey) }

        let routineKeys = Set(now.routines.map(\.identityKey))
        let routineNames = Set(now.routines.map(\.name))
        m.routines = base.routines.filter { !routineKeys.contains($0.identityKey) && !routineNames.contains($0.name) }

        let occKeys = Set(now.occurrences.map(\.key))
        m.occurrences = base.occurrences.filter { !occKeys.contains($0.key) }
        let placeKeys = Set(now.placements.map(\.key))
        m.placements = base.placements.filter { !placeKeys.contains($0.key) }

        // 무지개 일정은 uuid로 본다. 지금 '지움' 표가 찍혀 있으면 사람이 지운 것이라 없어진 것으로 치지 않는다
        // (행이 남아 있으니 uuid가 있다). 기준 벌에서 이미 지운 것도 셈에서 뺀다.
        let rainbowIDs = Set((now.rainbowEvents ?? []).map(\.uuid))
        m.rainbowEvents = (base.rainbowEvents ?? []).filter { $0.deletedAt == nil && !rainbowIDs.contains($0.uuid) }
        return m
    }

    // MARK: - 되살리기

    /// 없는 것만 더한다. 지금 있는 것은 하나도 건드리지 않는다.
    /// 되살리기 직전에 지금 상태를 한 벌 떠 둔다 — 되살리기가 마음에 안 들어도 돌아갈 자리가 있다.
    @MainActor
    @discardableResult
    static func restore(_ m: Missing, into context: ModelContext) -> Int {
        writeSnapshot(context, reason: "before-restore", force: true)
        for r in m.categories { context.insert(r.model()) }
        for r in m.projects { context.insert(r.model()) }
        for r in m.items { context.insert(r.model()) }
        for r in m.routines { context.insert(r.model()) }
        for r in m.blocks { context.insert(r.model()) }
        for r in m.occurrences { context.insert(r.model()) }
        for r in m.placements { context.insert(r.model()) }
        for r in m.rainbowEvents { context.insert(r.model()) }
        do {
            try context.save()
        } catch {
            print("⚠️ [Vault] 되살리기 저장 실패: \(error)")
            return 0
        }
        writeSnapshot(context, reason: "after-restore", force: true)
        print("🚑 [Vault] \(m.total)개를 되살렸다 (기준: \(m.base.lastPathComponent))")
        return m.total
    }

    // MARK: - 값으로 떠 두는 모양
    //
    // @Model 객체는 스토어가 닫히면 못 읽는다. 필드를 **전부** 값으로 옮겨 적는다.
    // ⚠️ 모델에 필드를 더하면 여기에도 더한다. 빠뜨리면 되살릴 때 그 필드만 사라진다.
    //    새 필드는 옵셔널로 더한다 — 그래야 옛 백업 파일도 그대로 읽힌다.

    struct ItemRow: Codable {
        var title: String
        var durationHours: Double
        var sortIndex: Int
        var createdAt: Date
        var dragToken: String
        var categoryID: String?
        var projectID: String?
        var weekStartDate: Date
        var isCompleted: Bool
        var completedAt: Date?
        var parentToken: String?
        var labelRaw: String?
        var isShared: Bool?
        var originInstallID: String?

        init(_ m: BacklogItem) {
            title = m.title; durationHours = m.durationHours; sortIndex = m.sortIndex
            createdAt = m.createdAt; dragToken = m.dragToken; categoryID = m.categoryID
            projectID = m.projectID; weekStartDate = m.weekStartDate; isCompleted = m.isCompleted
            completedAt = m.completedAt; parentToken = m.parentToken; labelRaw = m.labelRaw
            isShared = m.isShared; originInstallID = m.originInstallID
        }

        func model() -> BacklogItem {
            let m = BacklogItem(title: title, durationHours: durationHours, sortIndex: sortIndex,
                                categoryID: categoryID, weekStartDate: weekStartDate)
            m.createdAt = createdAt; m.dragToken = dragToken; m.projectID = projectID
            m.isCompleted = isCompleted; m.completedAt = completedAt
            m.parentToken = parentToken; m.labelRaw = labelRaw
            if let isShared { m.isShared = isShared }
            if let originInstallID { m.originInstallID = originInstallID }
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
            uuid = m.uuid; name = m.name; colorName = m.colorName
            iconName = m.iconName; sortIndex = m.sortIndex; createdAt = m.createdAt
        }

        func model() -> BacklogCategory {
            let m = BacklogCategory(name: name, colorName: colorName, iconName: iconName, sortIndex: sortIndex)
            m.uuid = uuid; m.createdAt = createdAt
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
            uuid = m.uuid; name = m.name; colorName = m.colorName; sortIndex = m.sortIndex
            createdAt = m.createdAt; isCompleted = m.isCompleted; completedAt = m.completedAt
        }

        func model() -> Project {
            let m = Project(name: name, colorName: colorName, sortIndex: sortIndex)
            m.uuid = uuid; m.createdAt = createdAt; m.isCompleted = isCompleted; m.completedAt = completedAt
            return m
        }
    }

    struct BlockRow: Codable {
        var dayRaw: Int
        var timeBandRaw: String
        var durationHours: Double
        var title: String
        var successCriteria: String
        var deliverable: String
        var weekStartDate: Date
        var concreteVerified: Bool
        var withinRoutine: Bool
        var startHour: Double
        var createdAt: Date
        var calendarEventID: String?
        var isShared: Bool?
        var originInstallID: String?
        var nextAction: String?
        var iconName: String?
        var actualMinutes: Double?
        var reviewStatusRaw: String?
        var reviewNote: String?
        var reviewedAt: Date?

        init(_ m: PlanBlock) {
            dayRaw = m.dayRaw; timeBandRaw = m.timeBandRaw; durationHours = m.durationHours
            title = m.title; successCriteria = m.successCriteria; deliverable = m.deliverable
            weekStartDate = m.weekStartDate; concreteVerified = m.concreteVerified
            withinRoutine = m.withinRoutine; startHour = m.startHour; createdAt = m.createdAt
            calendarEventID = m.calendarEventID; isShared = m.isShared; originInstallID = m.originInstallID
            nextAction = m.nextAction; iconName = m.iconName; actualMinutes = m.actualMinutes
            reviewStatusRaw = m.reviewStatusRaw; reviewNote = m.reviewNote; reviewedAt = m.reviewedAt
        }

        /// 블록에는 따로 붙은 이름표가 없다. 만든 시각(밀리초)이 사실상 이름표다.
        var identityKey: String { String(Int64((createdAt.timeIntervalSinceReferenceDate * 1000).rounded())) }
        /// 같은 주 · 같은 요일 · 같은 제목 · **같은 시각** — 겹친 것 정리(dedupeBlocks)와 같은 기준.
        /// 시각을 빼면 같은 날 10시·15시 "회의" 중 하나가 정말 없어져도 남은 쪽에 가려 못 본다.
        var placeKey: String {
            "\(title)|\(dayRaw)|\(Int64(weekStartDate.timeIntervalSinceReferenceDate))|\(Int((startHour * 60).rounded()))"
        }

        func model() -> PlanBlock {
            let m = PlanBlock(day: .mon, timeBand: .evening, durationHours: durationHours, title: title,
                              successCriteria: successCriteria, deliverable: deliverable,
                              weekStartDate: weekStartDate, concreteVerified: concreteVerified,
                              withinRoutine: withinRoutine, startHour: startHour)
            m.dayRaw = dayRaw; m.timeBandRaw = timeBandRaw; m.createdAt = createdAt
            m.calendarEventID = calendarEventID; m.nextAction = nextAction; m.iconName = iconName
            m.actualMinutes = actualMinutes
            m.reviewStatusRaw = reviewStatusRaw; m.reviewNote = reviewNote; m.reviewedAt = reviewedAt
            if let isShared { m.isShared = isShared }
            if let originInstallID { m.originInstallID = originInstallID }
            return m
        }
    }

    struct RoutineRow: Codable {
        var name: String
        var iconName: String
        var kindRaw: String
        var colorName: String
        var dayMask: Int
        var startHour: Double
        var durationHours: Double
        var weeklyHours: Double
        var sessionsPerDay: Int
        var sessionStartsRaw: String?
        var sortIndex: Int
        var createdAt: Date
        var isShared: Bool?
        var originInstallID: String?
        var executionNotes: String
        var premortemFailScenario: String
        var premortemPrevention: String

        init(_ m: Routine) {
            name = m.name; iconName = m.iconName; kindRaw = m.kindRaw; colorName = m.colorName
            dayMask = m.dayMask; startHour = m.startHour; durationHours = m.durationHours
            weeklyHours = m.weeklyHours; sessionsPerDay = m.sessionsPerDay; sessionStartsRaw = m.sessionStartsRaw
            sortIndex = m.sortIndex; createdAt = m.createdAt
            isShared = m.isShared; originInstallID = m.originInstallID
            executionNotes = m.executionNotes; premortemFailScenario = m.premortemFailScenario
            premortemPrevention = m.premortemPrevention
        }

        var identityKey: String { String(Int64((createdAt.timeIntervalSinceReferenceDate * 1000).rounded())) }

        func model() -> Routine {
            let m = Routine(name: name, iconName: iconName, kind: .fixed, colorName: colorName,
                            dayMask: dayMask, startHour: startHour, durationHours: durationHours,
                            weeklyHours: weeklyHours, sessionsPerDay: sessionsPerDay, sortIndex: sortIndex)
            m.kindRaw = kindRaw; m.sessionStartsRaw = sessionStartsRaw; m.createdAt = createdAt
            m.executionNotes = executionNotes; m.premortemFailScenario = premortemFailScenario
            m.premortemPrevention = premortemPrevention
            if let isShared { m.isShared = isShared }
            if let originInstallID { m.originInstallID = originInstallID }
            return m
        }
    }

    struct OccurrenceRow: Codable {
        var routineName: String
        var dayRaw: Int
        var weekStartDate: Date
        var startHourOverride: Double
        var hidden: Bool

        init(_ m: RoutineOccurrence) {
            routineName = m.routineName; dayRaw = m.dayRaw; weekStartDate = m.weekStartDate
            startHourOverride = m.startHourOverride; hidden = m.hidden
        }

        var key: String { "\(routineName)|\(dayRaw)|\(Int64(weekStartDate.timeIntervalSinceReferenceDate))" }

        func model() -> RoutineOccurrence {
            let m = RoutineOccurrence(routineName: routineName, day: .mon, weekStartDate: weekStartDate)
            m.dayRaw = dayRaw; m.startHourOverride = startHourOverride; m.hidden = hidden
            return m
        }
    }

    struct PlacementRow: Codable {
        var routineName: String
        var dayRaw: Int
        var weekStartDate: Date
        var sessionIndex: Int
        var startHour: Double
        var hidden: Bool

        init(_ m: QuotaPlacement) {
            routineName = m.routineName; dayRaw = m.dayRaw; weekStartDate = m.weekStartDate
            sessionIndex = m.sessionIndex; startHour = m.startHour; hidden = m.hidden
        }

        var key: String {
            "\(routineName)|\(dayRaw)|\(Int64(weekStartDate.timeIntervalSinceReferenceDate))|\(sessionIndex)"
        }

        func model() -> QuotaPlacement {
            let m = QuotaPlacement(routineName: routineName, day: .mon, weekStartDate: weekStartDate,
                                   sessionIndex: sessionIndex, startHour: startHour)
            m.dayRaw = dayRaw; m.hidden = hidden
            return m
        }
    }

    struct RainbowRow: Codable {
        var uuid: String
        var title: String
        var startDate: Date
        var endDate: Date
        var colorHex: String
        var hoursPerDay: Double
        var selectedWeekdaysData: Data?
        var weeklyPatternData: Data?
        /// 옛 백업에는 없어서 옵셔널이다 (없으면 매주).
        var repeatWeeks: Int?
        var sessionsData: Data?
        var importanceRaw: String
        var isInfinite: Bool
        var excludedDatesData: Data?
        var todoToken: String?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var originInstallID: String

        init(_ m: RainbowEvent) {
            uuid = m.uuid; title = m.title; startDate = m.startDate; endDate = m.endDate
            colorHex = m.colorHex; hoursPerDay = m.hoursPerDay
            selectedWeekdaysData = m.selectedWeekdaysData; weeklyPatternData = m.weeklyPatternData
            repeatWeeks = m.repeatWeeks; sessionsData = m.sessionsData
            importanceRaw = m.importanceRaw; isInfinite = m.isInfinite; excludedDatesData = m.excludedDatesData
            todoToken = m.todoToken; createdAt = m.createdAt; updatedAt = m.updatedAt
            deletedAt = m.deletedAt; originInstallID = m.originInstallID
        }

        func model() -> RainbowEvent {
            let m = RainbowEvent(uuid: uuid, title: title)
            m.startDate = startDate; m.endDate = endDate; m.colorHex = colorHex; m.hoursPerDay = hoursPerDay
            m.selectedWeekdaysData = selectedWeekdaysData; m.weeklyPatternData = weeklyPatternData
            m.repeatWeeks = repeatWeeks ?? 1; m.sessionsData = sessionsData
            m.importanceRaw = importanceRaw; m.isInfinite = isInfinite; m.excludedDatesData = excludedDatesData
            m.todoToken = todoToken; m.createdAt = createdAt; m.updatedAt = Date()
            m.deletedAt = deletedAt; m.originInstallID = originInstallID
            return m
        }
    }
}
