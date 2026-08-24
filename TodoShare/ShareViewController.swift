//
//  ShareViewController.swift
//  TodoShareExtension (macOS)
//
//  사파리 등에서 공유 → '무지개 공방'을 고르면 뜨는 작은 창.
//  받은 것(링크·텍스트)을 제목으로 채워 두고, 시간만 고르면 한 줄이 된다.
//
//  ⚠️ iOS '욕망의 무지개'의 같은 이름 파일과 짝이다. 화면 구성과 규칙을 같이 유지할 것.
//     맥은 NSViewController이고, 창 크기를 직접 잡아줘야 한다는 점만 다르다.
//
//  확정한 할 일은 SwiftData에 바로 못 넣는다 — 그 store는 앱 샌드박스 안이라
//  익스텐션이 열 수 없다. App Group의 '받은 상자'에 적어두면 앱이 켜질 때
//  가져간다 (→ TodoShareInbox.swift).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private let model = ShareTodoModel()

    override func loadView() {
        // 익스텐션 창은 스스로 크기를 정해야 한다. 제목 한 줄 + 칩 줄이 들어갈 만큼.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        model.onDone = { [weak self] in self?.finish() }
        model.onCancel = { [weak self] in self?.cancel() }

        let host = NSHostingController(rootView: ShareTodoView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.load(from: items) }
    }

    /// 상자에 넣었으니 창을 닫는다. 공유한 쪽 앱은 그대로 남는다.
    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "TodoShare", code: NSUserCancelledError))
    }
}

// MARK: - 받은 것을 읽어 한 줄로 만드는 모델

@MainActor
@Observable
final class ShareTodoModel {
    /// 할 일이 될 제목. 받은 것에서 채워 두고, 사용자가 고쳐 쓸 수 있다.
    var title = ""
    /// 어디서 온 것인지 보여주기 위한 링크. 제목을 만드는 데만 쓰고 따로 저장하지는 않는다.
    var link: String?
    /// 고른 시간. 지난번에 고른 값이 따라온다 (앱의 빈 줄과 같은 규칙).
    var label: TodoLabel = .ready
    /// 받은 내용을 아직 읽는 중인가.
    var isLoading = true
    /// App Group을 못 열었을 때만 채워진다.
    var errorMessage: String?

    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    /// 앱의 빈 줄과 같은 키를 쓴다 — 공유로 넣든 직접 적든 지난번 시간이 따라온다.
    /// (App Group의 UserDefaults라야 앱과 익스텐션이 같은 값을 본다.)
    private static let labelKey = "todo.newLabel"
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: TodoShareInbox.appGroupID)
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: 받은 내용 읽기

    func load(from items: [NSExtensionItem]) async {
        if let raw = sharedDefaults?.string(forKey: Self.labelKey),
           let saved = TodoLabel.resolve(raw) {
            label = saved
        }

        for item in items {
            // 사파리에서 문장을 끌어 공유하면 여기에 그 문장이 온다.
            if let text = item.attributedContentText?.string.trimmed, !text.isEmpty, title.isEmpty {
                title = text
            }
            // 웹페이지는 제목이 따로 온다 — 링크보다 제목이 훨씬 읽기 좋다.
            if let pageTitle = item.attributedTitle?.string.trimmed, !pageTitle.isEmpty {
                title = pageTitle
            }

            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await provider.loadURL() {
                    link = url.absoluteString
                    // 제목을 못 얻었으면 링크라도 세워 둔다 (사용자가 고쳐 쓰면 된다).
                    if title.isEmpty { title = url.readableTitle }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await provider.loadText()?.trimmed,
                          !text.isEmpty, title.isEmpty {
                    title = text
                }
            }
        }

        // 공유한 문장이 통째로 오면 한 줄에 안 들어간다. 첫 줄만 제목으로 쓴다.
        title = title.firstLine
        isLoading = false
    }

    // MARK: 확정

    func save() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines).firstLine
        guard !text.isEmpty else { return }

        let ok = TodoShareInbox.add(SharedTodoDraft(title: text, labelRaw: label.rawValue))
        guard ok else {
            errorMessage = "할 일을 저장하지 못했습니다. 앱을 한 번 열고 다시 시도해 주세요."
            return
        }
        sharedDefaults?.set(label.rawValue, forKey: Self.labelKey)
        onDone?()
    }

    func cancel() { onCancel?() }
}

// MARK: - 거들기

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 여러 줄이 통째로 넘어와도 목록에는 한 줄만 선다.
    var firstLine: String {
        // 너무 길면 목록에서 어차피 잘린다. 한 줄 분량에서 끊어 둔다.
        let line = split(whereSeparator: \.isNewline).first.map(String.init)?.trimmed ?? trimmed
        return line.count > 120 ? String(line.prefix(120)) + "…" : line
    }
}

private extension URL {
    /// 링크만 왔을 때 세울 이름. 전체 URL은 목록에서 읽히지 않으므로
    /// 도메인과 마지막 경로 조각 정도만 남긴다.
    var readableTitle: String {
        let host = self.host()?.replacingOccurrences(of: "www.", with: "") ?? absoluteString
        let last = pathComponents.last(where: { $0 != "/" && !$0.isEmpty })
        guard let last, last.count > 1 else { return host }
        let cleaned = last
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .removingPercentEncoding ?? last
        return "\(cleaned) — \(host)"
    }
}

private extension NSItemProvider {
    func loadURL() async -> URL? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.url.identifier) { value, _ in
                continuation.resume(returning: value as? URL)
            }
        }
    }

    func loadText() async -> String? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.plainText.identifier) { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }
}
