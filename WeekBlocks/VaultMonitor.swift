//
//  VaultMonitor.swift
//  무지개 공방
//
//  **사람이 지우지 않았는데 없어진 것을 알아챈다.** (→ DataVault.swift)
//
//  사람이 이 기기에서 지우면 그 저장 뒤에 금고가 한 벌을 새로 뜬다. 그래서 '마지막 벌'은
//  늘 "사람이 마지막으로 본 모습"이다. 그 벌에 있던 것이 지금 없다면 범인은 사람의 손이 아니다 —
//  업데이트 뒤 스토어가 다르게 열렸거나, iCloud가 무언가를 지워서 내려보냈거나.
//
//  두 때에 본다.
//   · 켤 때 — 지난번 마지막 벌과 지금 스토어.
//   · iCloud에서 변경이 내려왔을 때 — 내려오기 직전 벌과 지금 스토어.
//
//  ⚠️ 다른 기기에서 사람이 직접 지운 것도 여기 걸린다. 그건 막을 수 없고 막아서도 안 된다 —
//     그래서 묻는다. 한두 개는 묻지 않고 금고에만 남긴다(설정에서 언제든 되살린다).
//

import Foundation
import SwiftData
import CoreData
#if os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class VaultMonitor {
    static let shared = VaultMonitor()

    enum Cause {
        /// 켤 때 지난번과 견주어 찾았다.
        case launch
        /// iCloud에서 내려온 변경 뒤에 찾았다.
        case remote
        /// 사람이 설정에서 고른 백업과 견주었다.
        case manual
    }

    struct Finding: Identifiable {
        let id = UUID()
        let missing: DataVault.Missing
        let cause: Cause
    }

    /// 사람에게 물어볼 것. 값이 있으면 되살리기 창이 뜬다.
    var finding: Finding?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    /// iCloud 변경이 내려왔고 아직 견주지 않았다. 그동안은 자동 벌을 뜨지 않는다 —
    /// 뜨면 지워진 상태가 '마지막 벌'이 되어 견줄 기준이 사라진다.
    @ObservationIgnored private var remoteDirty = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() { }

    private var context: ModelContext? { container?.mainContext }

    /// 스토어를 연 **직후**, 다른 정리(겹친 것 정리·주차 끌어오기)보다 먼저 부른다.
    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        checkAtLaunch()
        observe()
    }

    // MARK: 켤 때

    private func checkAtLaunch() {
        guard let context else { return }
        if let base = latestBase() {
            let missing = DataVault.missing(in: context, comparedTo: base.snapshot, at: base.url)
            report(missing, cause: .launch)
        }
        DataVault.writeSnapshot(context,
                                reason: DataVault.launchedAfterUpdate ? "launch-after-update" : "launch",
                                force: true)
    }

    private func latestBase() -> (url: URL, snapshot: DataVault.Snapshot)? {
        // 맨 위 벌이 깨져 있으면 그 아래 것을 본다.
        for url in DataVault.snapshotFiles().prefix(5) {
            if let snap = DataVault.load(url) { return (url, snap) }
        }
        return nil
    }

    // MARK: 지켜보기

    private func observe() {
        let center = NotificationCenter.default

        // 이 기기에서 저장했다 = 사람이 한 일. 5초 모아서 한 벌 뜬다.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let ctx = note.object as? ModelContext,
                      ctx.container === self.container else { return }
                self.scheduleAutoSnapshot()
            }
        })

        // iCloud에서 내려왔다 = 사람이 이 기기에서 한 일이 아니다. 자리 잡을 때를 기다렸다가 견준다.
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remoteDirty = true
                self.remoteTask?.cancel()
                self.remoteTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled else { return }
                    self.checkAfterRemoteChange()
                }
            }
        })

        #if os(macOS)
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.snapshotNow(reason: "quit") }
        })
        #endif
    }

    private func scheduleAutoSnapshot() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            // 내려온 변경을 아직 안 견주었으면 그쪽이 먼저다 (그 끝에 한 벌을 뜬다).
            if remoteDirty { checkAfterRemoteChange() } else { snapshotNow(reason: "auto") }
        }
    }

    private func checkAfterRemoteChange() {
        remoteTask?.cancel()
        remoteDirty = false
        guard let context else { return }
        if let base = latestBase() {
            let missing = DataVault.missing(in: context, comparedTo: base.snapshot, at: base.url)
            report(missing, cause: .remote)
        }
        DataVault.writeSnapshot(context, reason: "remote")
    }

    /// 지금 한 벌. 앱이 뒤로 갈 때·끝날 때·사람이 눌렀을 때.
    @discardableResult
    func snapshotNow(reason: String, force: Bool = false) -> URL? {
        guard let context else { return nil }
        if remoteDirty { checkAfterRemoteChange() }
        return DataVault.writeSnapshot(context, reason: reason, force: force)
    }

    // MARK: 묻기

    /// 한두 개는 묻지 않는다 — 다른 기기에서 하나 지울 때마다 창이 뜨면 안 된다.
    /// 그래도 금고에는 남아 있으니 설정에서 언제든 되살린다.
    /// 프로젝트나 루틴이 통째로 없어진 것은 하나라도 묻는다 — 그 아래 것들이 같이 흔들린다.
    private func report(_ missing: DataVault.Missing, cause: Cause) {
        guard finding == nil else { return }
        let worth = missing.total >= 3 || !missing.projects.isEmpty || !missing.routines.isEmpty
        guard worth else {
            if missing.total > 0 { print("ℹ️ [Vault] \(missing.total)개가 없어졌다(묻지 않음) — 기준 \(missing.base.lastPathComponent)") }
            return
        }
        print("🚨 [Vault] 지난 벌에 있던 \(missing.total)개가 지금 없다 — 기준 \(missing.base.lastPathComponent)")
        finding = Finding(missing: missing, cause: cause)
    }

    /// 설정에서 고른 백업과 견준다. 없는 것이 없으면 nil.
    func compare(with url: URL) -> DataVault.Missing? {
        guard let context, let snap = DataVault.load(url) else { return nil }
        let m = DataVault.missing(in: context, comparedTo: snap, at: url)
        return m.isEmpty ? nil : m
    }

    @discardableResult
    func restore(_ missing: DataVault.Missing) -> Int {
        guard let context else { return 0 }
        return DataVault.restore(missing, into: context)
    }
}
