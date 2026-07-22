//
//  FamilyShareStore.swift
//  ScheduleDensity 패밀리 (iOS·macOS 공용)
//
//  가족 공유 할 일 — SwiftData는 CloudKit 공유 DB를 지원하지 않으므로,
//  이 목록만 CloudKit을 직접 사용한다:
//  - 소유자: 개인 DB의 커스텀 존("FamilyTodos")에 레코드 저장, 존 전체를 CKShare로 공유
//  - 가족(참가자): 초대 링크 수락 후 공유 DB(sharedCloudDatabase)에서 같은 존을 읽고 쓴다
//

import Foundation
import CloudKit
import Observation

/// 가족 공유 할 일 한 건 (CKRecord 미러).
struct FamilyTodo: Identifiable, Equatable {
    let id: CKRecord.ID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
}

@MainActor
@Observable
final class FamilyShareStore {
    static let shared = FamilyShareStore()

    static let containerID = "iCloud.com.devkoan.ScheduleDensity"
    static let zoneName = "FamilyTodos"
    static let recordType = "FamilyTodo"

    enum Mode: Equatable {
        case unknown
        case owner        // 내 개인 DB의 존을 공유하는 쪽
        case participant  // 가족의 존에 초대받은 쪽
    }

    private(set) var mode: Mode = .unknown
    private(set) var items: [FamilyTodo] = []
    /// 존 전체 공유(CKShare)가 만들어져 있는지 (소유자 기준).
    private(set) var isSharing = false
    private(set) var shareURL: URL? = nil
    private(set) var isBusy = false
    private(set) var iCloudAvailable = true
    var errorMessage: String? = nil

    private let container = CKContainer(identifier: FamilyShareStore.containerID)
    private var zoneID = CKRecordZone.ID(zoneName: FamilyShareStore.zoneName)
    private var zoneExists = false
    /// 서버 시스템 필드 보존용 원본 레코드 캐시.
    private var recordCache: [CKRecord.ID: CKRecord] = [:]

    private var database: CKDatabase {
        mode == .participant ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    // MARK: - 새로고침

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await container.accountStatus()
            iCloudAvailable = (status == .available)
            guard iCloudAvailable else { return }

            try await resolveMode()
            try await fetchAll()
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// 공유 DB에 가족 존이 있으면 참가자, 아니면 소유자로 동작한다.
    private func resolveMode() async throws {
        let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
        if let z = sharedZones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
            mode = .participant
            zoneID = z.zoneID
            zoneExists = true
        } else {
            mode = .owner
            zoneID = CKRecordZone.ID(zoneName: Self.zoneName)
        }
    }

    /// 존의 전체 레코드를 스냅숏으로 다시 읽는다 (목록이 작아 토큰 저장 없이 전체 fetch).
    private func fetchAll() async throws {
        var fetched: [FamilyTodo] = []
        var newCache: [CKRecord.ID: CKRecord] = [:]
        var foundShare: CKShare? = nil
        var token: CKServerChangeToken? = nil

        do {
            while true {
                let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for modification in result.modificationResultsByID.values {
                    guard let record = try? modification.get().record else { continue }
                    if let share = record as? CKShare {
                        foundShare = share
                    } else if record.recordType == Self.recordType {
                        newCache[record.recordID] = record
                        fetched.append(Self.todo(from: record))
                    }
                }
                token = result.changeToken
                if !result.moreComing { break }
            }
            zoneExists = true
        } catch let ck as CKError where ck.code == .zoneNotFound || ck.code == .userDeletedZone {
            // 아직 아무것도 공유·저장하지 않은 상태 — 빈 목록.
            zoneExists = false
        }

        items = fetched.sorted { $0.createdAt < $1.createdAt }
        recordCache = newCache
        isSharing = (foundShare != nil) || mode == .participant
        shareURL = foundShare?.url ?? shareURL
    }

    private static func todo(from record: CKRecord) -> FamilyTodo {
        FamilyTodo(
            id: record.recordID,
            title: record["title"] as? String ?? "",
            isCompleted: (record["done"] as? Int64 ?? 0) != 0,
            createdAt: record["createdOn"] as? Date ?? record.creationDate ?? Date()
        )
    }

    // MARK: - CRUD

    func add(title: String) async {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        do {
            try await ensureZone()
            let record = CKRecord(
                recordType: Self.recordType,
                recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
            )
            record["title"] = t
            record["done"] = Int64(0)
            record["createdOn"] = Date()
            let saved = try await database.save(record)
            recordCache[saved.recordID] = saved
            items.append(Self.todo(from: saved))
            items.sort { $0.createdAt < $1.createdAt }
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    func toggle(_ todo: FamilyTodo) async {
        guard let record = recordCache[todo.id] else { return }
        record["done"] = Int64(todo.isCompleted ? 0 : 1)
        do {
            let saved = try await database.save(record)
            recordCache[saved.recordID] = saved
            if let i = items.firstIndex(where: { $0.id == todo.id }) {
                items[i] = Self.todo(from: saved)
            }
            errorMessage = nil
        } catch {
            handle(error)
            await refresh()  // 충돌 시 서버 상태로 복구
        }
    }

    func delete(_ todo: FamilyTodo) async {
        do {
            _ = try await database.deleteRecord(withID: todo.id)
            items.removeAll { $0.id == todo.id }
            recordCache[todo.id] = nil
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    private func ensureZone() async throws {
        guard mode != .participant, !zoneExists else { return }
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))
        zoneExists = true
    }

    // MARK: - 공유 관리

    /// (소유자) 존 전체 공유를 만들거나 기존 공유를 찾아 초대 URL을 돌려준다.
    @discardableResult
    func startSharing() async -> URL? {
        guard mode != .participant else { return shareURL }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureZone()

            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            if let existing = try? await container.privateCloudDatabase.record(for: shareID),
               let share = existing as? CKShare {
                isSharing = true
                shareURL = share.url
                return share.url
            }

            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = "가족 할 일" as CKRecordValue
            // 링크만 있으면 가족 누구나 참여해 읽고 쓸 수 있게 한다.
            share.publicPermission = .readWrite
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

    /// (소유자) 공유 중지 — 가족 전원의 접근이 해제된다. 데이터는 내 존에 남는다.
    func stopSharing() async {
        guard mode == .owner else { return }
        do {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            _ = try await container.privateCloudDatabase.deleteRecord(withID: shareID)
            isSharing = false
            shareURL = nil
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// (참가자) 공유에서 나간다.
    func leave() async {
        guard mode == .participant else { return }
        do {
            _ = try await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
            mode = .owner
            zoneID = CKRecordZone.ID(zoneName: Self.zoneName)
            zoneExists = false
            items = []
            recordCache = [:]
            isSharing = false
            shareURL = nil
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    /// 초대 링크 수락 (양 플랫폼의 앱/씬 델리게이트에서 호출).
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

    // MARK: -

    private func handle(_ error: Error) {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                iCloudAvailable = false
                errorMessage = "iCloud에 로그인하면 가족 공유를 쓸 수 있습니다."
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
