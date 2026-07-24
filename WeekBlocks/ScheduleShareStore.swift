//
//  ScheduleShareStore.swift
//  무지개 공방
//
//  일정 공유(보기 전용) — 가족 공유 할 일 목록을 대체한다.
//  SwiftData는 CloudKit 공유 DB를 지원하지 않으므로, 주간 일정을 주마다 하나의 JSON
//  스냅숏 레코드로 만들어 커스텀 존("SharedSchedule")에 저장하고 존 전체를 CKShare로 공유한다.
//  - 소유자: 개인 DB의 존에 '주별 스냅숏'을 저장 → 존을 readOnly로 공유 → 초대 링크 배포
//  - 참가자: 초대 링크를 여럿 수락 가능 (사람마다 별도 존) → 각 존의 주별 스냅숏을 읽어
//    '보기 전용'으로 렌더링하고, 주를 넘겨가며 볼 수 있다. (publicPermission = .readOnly)
//
//  '내 일정 공유'와 '남의 일정 공유받기'는 독립적이다 — 한 사람이 동시에 둘 다 할 수 있다.
//

import Foundation
import CloudKit
import Observation

// MARK: - 공유되는 일정 스냅숏 (JSON 직렬화, 주 1건)

struct SharedScheduleSnapshot: Codable {
    var ownerName: String
    /// 스냅숏이 나타내는 주의 시작(월요일) — 초 단위 epoch.
    var weekStartEpoch: Double
    var generatedAtEpoch: Double
    /// 요일별 타임라인 조각 (소유자 쪽 TimelineLayout 결과를 그대로 담는다).
    var segments: [Seg]
    /// 루틴 요약(범례·목록용).
    var routines: [RoutineInfo]

    struct Seg: Codable, Identifiable {
        var day: Int          // DayOfWeek.rawValue
        var start: Double     // 0...24
        var end: Double
        var title: String
        var color: String     // 색 토큰: "accent" / "orange" / 팔레트 이름
        var isRoutine: Bool
        var isFlexible: Bool
        var isNested: Bool

        var id: String { "\(day)-\(start)-\(end)-\(title)" }
    }

    struct RoutineInfo: Codable, Identifiable {
        var name: String
        var color: String
        var kind: String      // RoutineKind.rawValue
        var scheduleDesc: String

        var id: String { name }
    }

    var weekStart: Date { Date(timeIntervalSince1970: weekStartEpoch) }
    var generatedAt: Date { Date(timeIntervalSince1970: generatedAtEpoch) }
}

// MARK: - 공유받은 한 사람의 일정 (여러 주)

struct ReceivedSchedule: Identifiable {
    let zoneID: CKRecordZone.ID
    var ownerName: String
    /// 주 시작 오름차순으로 정렬된 주별 스냅숏.
    var weeks: [SharedScheduleSnapshot]

    var id: String { "\(zoneID.zoneName)|\(zoneID.ownerName)" }
}

// MARK: - CloudKit 스토어

@MainActor
@Observable
final class ScheduleShareStore {
    static let shared = ScheduleShareStore()

    static let containerID = "iCloud.com.devkoan.ScheduleDensity"
    static let zoneName = "SharedSchedule"
    static let recordType = "ScheduleSnapshot"

    // 내 공유 상태 (소유자)
    private(set) var isSharing = false
    private(set) var shareURL: URL? = nil
    private(set) var sharedWeekCount = 0
    private(set) var lastPublishedAt: Date? = nil

    // 공유받은 사람들 (참가자)
    private(set) var received: [ReceivedSchedule] = []

    private(set) var isBusy = false
    private(set) var iCloudAvailable = true
    var errorMessage: String? = nil

    private let container = CKContainer(identifier: ScheduleShareStore.containerID)
    /// 내 개인 DB의 공유용 존.
    private let ownerZoneID = CKRecordZone.ID(zoneName: ScheduleShareStore.zoneName)
    private var ownerZoneExists = false
    /// weekKey → 서버 레코드(시스템 필드 보존용).
    private var ownerRecords: [String: CKRecord] = [:]
    /// weekKey → 마지막으로 발행한 payload (같으면 재발행 스킵).
    private var lastPublishedPayload: [String: String] = [:]

    // MARK: 새로고침

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let status = try await container.accountStatus()
            iCloudAvailable = (status == .available)
            guard iCloudAvailable else { return }

            try await fetchOwnerState()
            try await fetchReceived()
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// 내 개인 DB 존의 주별 스냅숏·공유 상태를 읽는다.
    private func fetchOwnerState() async throws {
        do {
            let (items, share) = try await fetchZone(db: container.privateCloudDatabase, zoneID: ownerZoneID)
            ownerZoneExists = true
            ownerRecords.removeAll()
            lastPublishedPayload.removeAll()
            for (snap, rec) in items {
                let k = weekKey(snap.weekStart)
                ownerRecords[k] = rec
                if let p = rec["payload"] as? String { lastPublishedPayload[k] = p }
            }
            sharedWeekCount = items.count
            isSharing = (share != nil)
            shareURL = share?.url
            lastPublishedAt = items.map { $0.0.generatedAt }.max()
        } catch let ck as CKError where ck.code == .zoneNotFound || ck.code == .userDeletedZone {
            ownerZoneExists = false
            isSharing = false
            shareURL = nil
            sharedWeekCount = 0
            lastPublishedAt = nil
            ownerRecords.removeAll()
            lastPublishedPayload.removeAll()
        }
    }

    /// 공유 DB의 모든 존(사람마다 하나)에서 주별 스냅숏을 읽는다.
    private func fetchReceived() async throws {
        let zones = try await container.sharedCloudDatabase.allRecordZones()
        var result: [ReceivedSchedule] = []
        for zone in zones where zone.zoneID.zoneName == Self.zoneName {
            let (items, _) = try await fetchZone(db: container.sharedCloudDatabase, zoneID: zone.zoneID)
            let weeks = items.map { $0.0 }.sorted { $0.weekStartEpoch < $1.weekStartEpoch }
            guard !weeks.isEmpty else { continue }
            let owner = weeks.last(where: { !$0.ownerName.isEmpty })?.ownerName ?? "공유받은 일정"
            result.append(ReceivedSchedule(zoneID: zone.zoneID, ownerName: owner, weeks: weeks))
        }
        received = result.sorted { $0.ownerName < $1.ownerName }
    }

    /// 한 존의 스냅숏 레코드들과 공유(CKShare)를 읽어온다.
    private func fetchZone(db: CKDatabase, zoneID: CKRecordZone.ID) async throws
        -> (items: [(snap: SharedScheduleSnapshot, record: CKRecord)], share: CKShare?)
    {
        var token: CKServerChangeToken? = nil
        var items: [(SharedScheduleSnapshot, CKRecord)] = []
        var share: CKShare? = nil
        while true {
            let result = try await db.recordZoneChanges(inZoneWith: zoneID, since: token)
            for mod in result.modificationResultsByID.values {
                guard let record = try? mod.get().record else { continue }
                if let s = record as? CKShare {
                    share = s
                } else if record.recordType == Self.recordType,
                          let payload = record["payload"] as? String,
                          let snap = try? JSONDecoder().decode(SharedScheduleSnapshot.self, from: Data(payload.utf8)) {
                    items.append((snap, record))
                }
            }
            token = result.changeToken
            if !result.moreComing { break }
        }
        return (items, share)
    }

    // MARK: 발행 (소유자)

    /// 존을 만들고 주별 스냅숏을 저장한 뒤, 읽기 전용 존 공유를 만들어 초대 URL을 돌려준다.
    @discardableResult
    func startSharing(publishing snapshots: [SharedScheduleSnapshot]) async -> URL? {
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureOwnerZone()
            for snap in snapshots {
                if let payload = encode(snap) { try await savePayload(payload, weekStart: snap.weekStart) }
            }
            sharedWeekCount = ownerRecords.count

            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownerZoneID)
            if let existing = try? await container.privateCloudDatabase.record(for: shareID) as? CKShare {
                isSharing = true
                shareURL = existing.url
                return existing.url
            }

            let share = CKShare(recordZoneID: ownerZoneID)
            share[CKShare.SystemFieldKey.title] = "내 주간 일정" as CKRecordValue
            // 링크를 받은 사람은 '보기 전용'으로만 참여한다.
            share.publicPermission = .readOnly
            let saved = try await container.privateCloudDatabase.save(share)
            isSharing = true
            shareURL = (saved as? CKShare)?.url
            errorMessage = nil
            return shareURL
        } catch {
            handle(error)
            return nil
        }
    }

    /// 공유 중일 때, 바뀐 주만 골라 스냅숏을 갱신한다.
    func publish(_ snapshots: [SharedScheduleSnapshot]) async {
        guard isSharing else { return }
        let changed = snapshots.filter { snap in
            guard let payload = encode(snap) else { return false }
            return payload != lastPublishedPayload[weekKey(snap.weekStart)]
        }
        guard !changed.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            for snap in changed {
                if let payload = encode(snap) { try await savePayload(payload, weekStart: snap.weekStart) }
            }
            sharedWeekCount = ownerRecords.count
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// 공유 중지 — 참가자 전원의 접근이 해제된다. 내 일정 데이터는 그대로 남는다.
    func stopSharing() async {
        guard isSharing else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownerZoneID)
            _ = try await container.privateCloudDatabase.deleteRecord(withID: shareID)
            isSharing = false
            shareURL = nil
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// (참가자) 특정 사람의 공유에서 나간다.
    func leave(_ schedule: ReceivedSchedule) async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await container.sharedCloudDatabase.deleteRecordZone(withID: schedule.zoneID)
            received.removeAll { $0.id == schedule.id }
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// 초대 링크 수락 (앱 델리게이트에서 호출).
    func accept(_ metadata: CKShare.Metadata) async {
        isBusy = true
        do {
            _ = try await container.accept(metadata)
            isBusy = false
            errorMessage = nil
            await refresh()
        } catch {
            isBusy = false
            handle(error)
        }
    }

    // MARK: 내부 헬퍼

    private func ensureOwnerZone() async throws {
        guard !ownerZoneExists else { return }
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: ownerZoneID))
        ownerZoneExists = true
    }

    private func savePayload(_ payload: String, weekStart: Date) async throws {
        let k = weekKey(weekStart)
        let recordID = CKRecord.ID(recordName: "schedule-\(k)", zoneID: ownerZoneID)
        let record: CKRecord
        if let cached = ownerRecords[k] {
            record = cached
        } else if let existing = try? await container.privateCloudDatabase.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        record["payload"] = payload
        record["updatedOn"] = Date()
        let saved = try await container.privateCloudDatabase.save(record)
        ownerRecords[k] = saved
        lastPublishedPayload[k] = payload
        lastPublishedAt = Date()
    }

    private func weekKey(_ weekStart: Date) -> String {
        String(Int(weekStart.timeIntervalSince1970.rounded()))
    }

    private func encode(_ snapshot: SharedScheduleSnapshot) -> String? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func handle(_ error: Error) {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                iCloudAvailable = false
                errorMessage = "iCloud에 로그인하면 일정을 공유할 수 있습니다."
                return
            case .networkUnavailable, .networkFailure:
                errorMessage = "네트워크 연결을 확인해주세요."
                return
            default:
                break
            }
        }
        errorMessage = "동기화 오류: \(error.localizedDescription)"
    }
}
