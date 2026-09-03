//
//  PaywallView.swift
//  WeekBlocks
//
//  **'함께 쓰기'를 사는 자리.**
//
//  화면이 먼저 하는 말은 **무엇이 그대로인가**다. 잠긴 것부터 늘어놓으면 앱이 인질처럼
//  보이는데, 실제로 이 앱의 본체는 잠겨 있지 않다 — 주간 계획도, 루틴도, **적는 것도**,
//  아이폰에서 내려온 할 일을 보는 것도 값을 안 받는다.
//  값을 받는 것은 **여기서 적은 것이 아이폰으로 건너가기** 하나다 (→ TodoAccess.swift).
//  그 사실을 감추면 안 사는 사람이 앱을 못 쓴다고 오해하고 지운다.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var purchases = PurchaseManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("함께 쓰기")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .padding(.bottom, 6)

            Text("여기서 적은 할 일이 아이폰에도 보입니다.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            // 무엇이 그대로인지부터.
            VStack(alignment: .leading, spacing: 10) {
                Text("지금도 되는 것")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                row("calendar", "주간 계획과 루틴", "값을 받지 않습니다.")
                row("square.and.pencil", "이 맥에서 적기", "무엇이든, 얼마든지 적습니다.")
                row("iphone", "아이폰에서 온 할 일 보기", "계속 내려옵니다.")
                row("eye", "예전에 적어 둔 것", "그대로 보입니다.")
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 10) {
                Text("사면 열리는 것")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                row("arrow.left.arrow.right", "아이폰으로 건너가기",
                    "여기서 적은 것이 아이폰에도 보입니다. 예전에 적어 둔 것도 함께 열립니다.")
            }
            .padding(.bottom, 24)

            if let message = purchases.failureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                Button("나중에") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("구매 복원") { Task { await purchases.restore() } }
                    .disabled(purchases.isWorking)

                Button {
                    Task {
                        await purchases.purchase()
                        if purchases.isUnlocked { dismiss() }
                    }
                } label: {
                    if purchases.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(purchases.product.map { "\($0.displayPrice)에 열기" } ?? "열기")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(purchases.isWorking || purchases.product == nil)
            }

            Text("한 번 사면 끝입니다. 구독이 아니고, 같은 Apple 계정의 다른 맥에서도 열립니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .padding(24)
        .frame(width: 460)
        .task { await purchases.refresh() }
    }

    private func row(_ icon: String, _ title: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
