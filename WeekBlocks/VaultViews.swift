//
//  VaultViews.swift
//  무지개 공방
//
//  금고(→ DataVault.swift)가 사람에게 말하는 자리 둘.
//   · 되살리기 창 — 없어진 것을 보여 주고 되살릴지 묻는다.
//   · 설정의 '백업과 되살리기' — 백업이 어디 몇 벌 있는지, 고른 벌에서 되살리기.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - 되살리기 창

struct VaultRecoverySheet: View {
    let finding: VaultMonitor.Finding
    var onClose: () -> Void

    @State private var restoredCount: Int?

    private var m: DataVault.Missing { finding.missing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(restoredCount == nil ? "없어진 기록이 있습니다" : "되살렸습니다")
                    .font(.title2.bold())
            } icon: {
                Image(systemName: restoredCount == nil ? "exclamationmark.arrow.triangle.2.circlepath"
                                                       : "checkmark.circle.fill")
                    .foregroundStyle(restoredCount == nil ? .orange : .green)
            }

            if let restoredCount {
                Text("\(restoredCount)개를 되살렸습니다. 되살리기 전 모습도 백업으로 남겨 두었습니다.")
                    .font(.body)
                HStack {
                    Spacer()
                    Button("닫기") { onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(explanation)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        group("프로젝트", m.projects.map(\.name))
                        group("할 일", m.items.map(\.title))
                        group("계획 블록", m.blocks.map(\.title))
                        group("루틴", m.routines.map(\.name))
                        group("분류", m.categories.map(\.name))
                        group("무지개 일정", m.rainbowEvents.map(\.title))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 320)

                Text("되살리기는 없는 것만 더합니다. 지금 있는 것은 바꾸지 않습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("그대로 두기") { onClose() }
                    Spacer()
                    Button("모두 되살리기") {
                        restoredCount = VaultMonitor.shared.restore(m)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 520)
        #endif
    }

    private var explanation: String {
        let when = m.baseTakenAt.formatted(date: .abbreviated, time: .shortened)
        switch finding.cause {
        case .launch:
            return String(localized: "\(when)에 있던 것 중 \(m.total)개가 지금 없습니다. 이 기기에서 지운 것이 아닙니다. 다른 기기에서 직접 지운 것이라면 그대로 두셔도 됩니다.")
        case .remote:
            return String(localized: "iCloud에서 내려온 변경 뒤에 \(m.total)개가 없어졌습니다. 다른 기기에서 직접 지운 것이라면 그대로 두셔도 됩니다.")
        case .manual:
            return String(localized: "\(when) 백업에 있던 것 중 \(m.total)개가 지금 없습니다.")
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                ForEach(Array(names.prefix(40).enumerated()), id: \.offset) { _, name in
                    Text(name.isEmpty ? String(localized: "(제목 없음)") : name)
                        .font(.body)
                        .lineLimit(1)
                }
                if names.count > 40 {
                    Text("외 \(names.count - 40)개").font(.body).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 켤 때·iCloud 변경 뒤에 찾은 것을 창으로 띄운다. 창의 맨 바깥에 한 번만 건다.
struct VaultPrompt: ViewModifier {
    @State private var monitor = VaultMonitor.shared

    func body(content: Content) -> some View {
        content.sheet(item: $monitor.finding) { finding in
            VaultRecoverySheet(finding: finding) { monitor.finding = nil }
        }
    }
}

extension View {
    func vaultRecoveryPrompt() -> some View { modifier(VaultPrompt()) }
}

// MARK: - 설정 · 백업과 되살리기

struct VaultSettingsSection: View {
    @State private var files: [URL] = []
    @State private var chosen: URL?
    @State private var manualFinding: VaultMonitor.Finding?
    @State private var nothingMissing = false
    @State private var iCloudLast: Date?
    @State private var iCloudError: String?

    var body: some View {
        Section {
            if let latest = files.first {
                let c = DataVault.counts(of: latest)
                LabeledContent("마지막 백업") {
                    Text(dateText(latest)).font(.body)
                }
                Text("할 일 \(c.items)개 · 프로젝트 \(c.projects)개 · 계획 블록 \(c.blocks)개 · 모두 \(files.count)벌")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("아직 백업이 없습니다.").font(.body)
            }

            LabeledContent("iCloud Drive") {
                if let iCloudError {
                    Text(iCloudError).font(.body).foregroundStyle(.orange)
                } else if let iCloudLast {
                    Text(iCloudLast.formatted(date: .abbreviated, time: .shortened)).font(.body)
                } else {
                    Text("아직 올리지 않음").font(.body).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    VaultMonitor.shared.snapshotNow(reason: "manual", force: true)
                    reload()
                } label: {
                    Label("지금 백업", systemImage: "externaldrive.badge.plus")
                }
                #if os(macOS)
                Button {
                    try? FileManager.default.createDirectory(at: DataVault.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([DataVault.root])
                } label: {
                    Label("백업 폴더 열기", systemImage: "folder")
                }
                #else
                // 아이폰에는 폴더를 열어 줄 곳이 없다. 마지막 벌을 파일로 내보낸다 (파일 앱·메일·에어드롭).
                if let latest = files.first {
                    ShareLink(item: latest) {
                        Label("백업 파일 내보내기", systemImage: "square.and.arrow.up")
                    }
                }
                #endif
            }

            if !files.isEmpty {
                Picker("되살릴 백업", selection: $chosen) {
                    Text("고르세요").tag(URL?.none)
                    ForEach(files.prefix(120), id: \.self) { url in
                        let c = DataVault.counts(of: url)
                        Text("\(dateText(url)) · 할 일 \(c.items) · 블록 \(c.blocks)").tag(URL?.some(url))
                    }
                }
                Button {
                    guard let chosen else { return }
                    if let m = VaultMonitor.shared.compare(with: chosen) {
                        manualFinding = VaultMonitor.Finding(missing: m, cause: .manual)
                    } else {
                        nothingMissing = true
                    }
                } label: {
                    Label("이 백업에서 없는 것 찾기", systemImage: "arrow.counterclockwise")
                }
                .disabled(chosen == nil)
                if nothingMissing {
                    Text("이 백업에 있던 것은 모두 지금도 있습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("백업과 되살리기")
        } footer: {
            Text("적은 것은 세 군데에 따로 남습니다. 이 맥의 백업 폴더(업데이트 직전 저장 파일 통째 사본 포함), iCloud Drive, 그리고 iCloud 동기화. 한 곳이 비어도 나머지에서 되살릴 수 있습니다. 되살리기는 없는 것만 더하고 지금 있는 것은 바꾸지 않습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: reload)
        .onChange(of: chosen) { _, _ in nothingMissing = false }
        .sheet(item: $manualFinding) { finding in
            VaultRecoverySheet(finding: finding) {
                manualFinding = nil
                reload()
            }
        }
    }

    private func reload() {
        files = DataVault.snapshotFiles()
        iCloudLast = UserDefaults.standard.object(forKey: DataVault.iCloudLastKey) as? Date
        iCloudError = UserDefaults.standard.string(forKey: DataVault.iCloudErrorKey)
    }

    private func dateText(_ url: URL) -> String {
        DataVault.date(of: url)?.formatted(date: .abbreviated, time: .shortened) ?? url.lastPathComponent
    }
}
