//
//  DeletionMark.swift
//  욕망의 무지개 · 무지개 공방 (두 앱이 같은 파일을 쓴다)
//
//  **사람이 지운 것의 표.** 지운 기기에서 남기고, iCloud로 다른 기기에 함께 간다.
//
//  금고(VaultMonitor)는 지난 벌에 있던 것이 지금 없으면 '사라짐'으로 보고 되살릴지 묻는다.
//  그런데 기기가 넷이면, 아이폰에서 사람이 지운 할 일도 나머지 셋에는 '사라짐'으로 보였다.
//  거기서 되살리기를 누르면 지운 것이 네 기기 모두에 돌아오고, 여럿이 누르면 여러 벌이 된다.
//  이 표가 있으면 '사람이 지웠다'와 '어디선가 없어졌다'를 가른다 — 표가 있는 것은 묻지 않는다.
//
//  · 표는 **이 기기의 main context에서 지운 것**에만 자동으로 찍힌다 (→ DeletionLog.watch).
//    지우는 자리마다 손으로 부르지 않는다 — 하나 빠뜨리면 그 자리만 조용히 되살아난다.
//  · 겹친 것 정리처럼 **같은 것이 남아 있는 지우기**에는 찍지 않는다. 표가 남은 쪽까지
//    가려서, 그것이 나중에 정말 없어졌을 때 금고가 못 보게 된다.
//  · 무지개 일정은 행에 직접 `deletedAt`을 찍으므로 여기서 다루지 않는다.
//  · 같은 타입에 **기기 명부**도 싣는다 — "device:설치id" 행 하나가 "이 기기는 표를 찍는 버전"이라는 뜻이다
//    (→ DeviceRoll). 스키마를 또 늘리지 않으려고 같은 칸을 빌려 쓴다.
//
//  ⚠️ 칸 이름 · 타입 · 기본값은 두 앱에서 **글자 하나까지 같아야 한다.** CloudKit 레코드 타입
//     `CD_DeletionMark`를 두 앱이 함께 쓴다. 출시 전에 Production 스키마 배포가 필요하다.
//

import Foundation
import SwiftData

@Model
final class DeletionMark {
    /// 무엇을 지웠나. "item:토큰" · "project:uuid" · "block:만든 시각" 처럼 종류와 열쇠 (→ DeletionLog.key).
    var key: String = ""
    var deletedAt: Date = Date()
    /// 지운 기기의 설치 id (→ TodoSharing.installID).
    var originInstallID: String = ""

    init(key: String, originInstallID: String) {
        self.key = key
        self.originInstallID = originInstallID
    }
}

@MainActor
enum DeletionLog {

    // MARK: 열쇠 — 금고가 '같은 것'으로 보는 기준과 같다 (→ DataVault.missing)

    static func key(_ r: DataVault.ItemRow) -> String { "item:\(r.dragToken)" }
    static func key(_ r: DataVault.CategoryRow) -> String { "category:\(r.uuid)" }
    static func key(_ r: DataVault.ProjectRow) -> String { "project:\(r.uuid)" }
    static func key(_ r: DataVault.BlockRow) -> String { "block:\(r.identityKey)" }
    static func key(_ r: DataVault.RoutineRow) -> String { "routine:\(r.identityKey)" }
    static func key(_ r: DataVault.OccurrenceRow) -> String { "occurrence:\(r.key)" }
    static func key(_ r: DataVault.PlacementRow) -> String { "placement:\(r.key)" }

    static func keys(of m: DataVault.Missing) -> [String] {
        m.items.map(key) + m.categories.map(key) + m.projects.map(key) + m.blocks.map(key)
            + m.routines.map(key) + m.occurrences.map(key) + m.placements.map(key)
    }

    // MARK: 읽기

    static func marks(in context: ModelContext) -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<DeletionMark>())) ?? []).map(\.key))
    }

    /// 표가 찍힌 것(사람이 지운 것)을 뺀다. 남은 것이 '어디선가 없어진 것'이다.
    static func excludingMarked(_ m: DataVault.Missing, in context: ModelContext) -> DataVault.Missing {
        let marked = marks(in: context)
        guard !marked.isEmpty else { return m }
        var out = m
        out.items.removeAll { marked.contains(key($0)) }
        out.categories.removeAll { marked.contains(key($0)) }
        out.projects.removeAll { marked.contains(key($0)) }
        out.blocks.removeAll { marked.contains(key($0)) }
        out.routines.removeAll { marked.contains(key($0)) }
        out.occurrences.removeAll { marked.contains(key($0)) }
        out.placements.removeAll { marked.contains(key($0)) }
        return out
    }

    /// 되살린 것의 표는 걷는다 — 다시 있는 것이니, 다음에 없어지면 그때는 물어야 한다.
    static func unmark(_ keys: [String], in context: ModelContext) {
        guard !keys.isEmpty else { return }
        let set = Set(keys)
        let all = (try? context.fetch(FetchDescriptor<DeletionMark>())) ?? []
        for mark in all where set.contains(mark.key) { context.delete(mark) }
    }

    // MARK: 찍기 — 이 기기의 저장을 지켜본다

    private static var observers: [NSObjectProtocol] = []
    /// 저장 직전에 떠 둔, 지워질 것들의 값. 저장이 끝나면 정말 없어졌는지 보고 표를 찍는다.
    private static var pending: [ObjectIdentifier: DataVault.Snapshot] = [:]

    /// 스토어를 연 뒤 한 번 부른다. 이 컨테이너의 **main context** 저장만 본다.
    static func watch(_ container: ModelContainer) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.willSave, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let ctx = note.object as? ModelContext, ctx === container.mainContext else { return }
                let doomed = ctx.deletedModelsArray
                guard !doomed.isEmpty else { return }
                pending[ObjectIdentifier(ctx)] = rows(of: doomed)
            }
        })
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let ctx = note.object as? ModelContext, ctx === container.mainContext,
                      let doomed = pending.removeValue(forKey: ObjectIdentifier(ctx)) else { return }
                stamp(doomed, in: ctx)
            }
        })
        prune(container.mainContext)
    }

    /// 지운 것 중 **같은 것이 남아 있지 않은 것**에만 표를 찍는다.
    /// '같은 것'의 기준은 금고와 같다 — 겹친 것 정리로 지운 쪽은 남은 쪽이 있으니 빠진다.
    private static func stamp(_ doomed: DataVault.Snapshot, in ctx: ModelContext) {
        let gone = DataVault.missing(in: ctx, comparedTo: doomed, at: URL(fileURLWithPath: "/"))
        let already = marks(in: ctx)
        // 캘린더에서 가져온 블록이면 그 일정의 이름에도 표를 찍는다 — 다른 맥이 같은 일정을
        // 처음 가져올 때 사람이 지운 것을 다시 세우지 않게 (→ CalendarImport, 맥 전용).
        let calendarKeys = gone.blocks.compactMap { $0.calendarEventID.map { "calendar:\($0)" } }
        let fresh = Set(keys(of: gone) + calendarKeys).subtracting(already)
        guard !fresh.isEmpty else { return }
        let me = TodoSharing.installID
        for k in fresh { ctx.insert(DeletionMark(key: k, originInstallID: me)) }
        do {
            try ctx.save()
            AppLog.vault.info("지운 것 \(fresh.count, privacy: .public)개에 표를 찍었다")
        } catch {
            AppLog.vault.error("표 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 지워질 모델을 값으로 옮긴다. 모르는 타입(표 자체 · 무지개 일정 · 표시)은 넘긴다.
    private static func rows(of models: [any PersistentModel]) -> DataVault.Snapshot {
        var s = DataVault.Snapshot(takenAt: Date(), appVersion: "", platform: DataVault.platform, reason: "deleting",
                                   items: [], categories: [], projects: [], blocks: [], routines: [],
                                   occurrences: [], placements: [])
        for model in models {
            #if DEBUG
            // 스키마 표본을 치우는 지우기는 사람이 한 일이 아니다 (→ CloudSchemaPrimer).
            if let m = model as? BacklogItem, m.title == CloudSchemaPrimer.marker { continue }
            if let m = model as? BacklogCategory, m.name == CloudSchemaPrimer.marker { continue }
            if let m = model as? Project, m.name == CloudSchemaPrimer.marker { continue }
            if let m = model as? PlanBlock, m.title == CloudSchemaPrimer.marker { continue }
            if let m = model as? Routine, m.name == CloudSchemaPrimer.marker { continue }
            #endif
            switch model {
            case let m as BacklogItem: s.items.append(.init(m))
            case let m as BacklogCategory: s.categories.append(.init(m))
            case let m as Project: s.projects.append(.init(m))
            case let m as PlanBlock: s.blocks.append(.init(m))
            case let m as Routine: s.routines.append(.init(m))
            case let m as RoutineOccurrence: s.occurrences.append(.init(m))
            case let m as QuotaPlacement: s.placements.append(.init(m))
            default: break
            }
        }
        return s
    }

    /// 한 해 넘은 표는 걷는다. 끝없이 쌓이지 않게 — 한 해 넘게 안 켠 기기는 드물고, 그때는 물어보는 쪽이 낫다.
    private static func prune(_ ctx: ModelContext) {
        let cutoff = Date().addingTimeInterval(-365 * 86_400)
        let old = ((try? ctx.fetch(FetchDescriptor<DeletionMark>(predicate: #Predicate { $0.deletedAt < cutoff }))) ?? [])
            .filter { !$0.key.hasPrefix(DeviceRoll.prefix) }   // 기기 명부는 걷지 않는다 (→ DeviceRoll)
        guard !old.isEmpty else { return }
        for m in old { ctx.delete(m) }
        try? ctx.save()
    }
}

// MARK: - 기기 명부 — 표를 찍지 못하는 옛 버전 기기를 알아본다

/// 옛 버전 앱은 지운 것에 표를 찍지 않는다. 그 기기에서 지운 것은 다른 기기의 금고에 '사라짐'으로 보여
/// 되살리기 창이 뜬다. 미리 알면 사람이 그 기기를 업데이트해서 막을 수 있다.
///
/// · 새 버전은 켤 때 명부에 자기 설치 id를 한 번 적는다 (`deletedAt` = 처음 적은 때).
/// · 할 일 · 계획 블록 · 루틴은 만든 기기의 설치 id를 싣고 다닌다 (→ TodoSharing).
///   최근에 무엇을 만든 기기인데 명부에 없으면, 그 기기는 아직 옛 버전이다.
@MainActor
enum DeviceRoll {
    static let prefix = "device:"
    /// 스키마 표본이 싣는 가짜 id (→ CloudSchemaPrimer).
    private static let sampleID = "schema-sample-install"

    /// 이 기기를 명부에 올린다. 이미 있으면 아무것도 안 한다.
    static func register(_ ctx: ModelContext) {
        let me = TodoSharing.installID
        let key = prefix + me
        let existing = (try? ctx.fetch(FetchDescriptor<DeletionMark>(predicate: #Predicate { $0.key == key }))) ?? []
        guard existing.isEmpty else { return }
        ctx.insert(DeletionMark(key: key, originInstallID: me))
        try? ctx.save()
    }

    /// 최근 7일 안에(그리고 이 기기가 새 버전이 된 뒤에) 무엇을 만들었는데 명부에 없는 기기들.
    static func outdatedDevices(_ ctx: ModelContext) -> Set<String> {
        let me = TodoSharing.installID
        let roll = ((try? ctx.fetch(FetchDescriptor<DeletionMark>())) ?? []).filter { $0.key.hasPrefix(prefix) }
        let registered = Set(roll.map { String($0.key.dropFirst(prefix.count)) })
        // 이 기기가 새 버전이 되기 전의 것은 보지 않는다 — 그때는 모두가 옛 버전이었다.
        let mySince = roll.first { $0.key == prefix + me }?.deletedAt ?? Date()
        let since = max(mySince, Date().addingTimeInterval(-7 * 86_400))

        var authors: [String] = []
        authors += ((try? ctx.fetch(FetchDescriptor<BacklogItem>(predicate: #Predicate { $0.createdAt >= since }))) ?? [])
            .map(\.originInstallID)
        authors += ((try? ctx.fetch(FetchDescriptor<PlanBlock>(predicate: #Predicate { $0.createdAt >= since }))) ?? [])
            .map(\.originInstallID)
        authors += ((try? ctx.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.createdAt >= since }))) ?? [])
            .map(\.originInstallID)
        return Set(authors.filter { !$0.isEmpty && $0 != me && $0 != sampleID && !registered.contains($0) })
    }
}
