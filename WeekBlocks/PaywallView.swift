//
//  PaywallView.swift
//  WeekBlocks
//
//  **「무지개 공방 Pro」를 사는 자리.**
//
//  화면이 먼저 하는 말은 **무엇이 그대로인가**다. 잠긴 것부터 늘어놓으면 앱이 인질처럼
//  보이는데, 실제로 이 앱의 본체는 잠겨 있지 않다 — 계획도, 루틴도, 적는 것도, 이번 주
//  회고도, 아이폰과 오가는 것도 값을 안 받는다. 그 사실을 감추면 안 사는 사람이 앱을
//  못 쓴다고 오해하고 지운다.
//
//  값을 받는 것은 **지난 주들이 쌓여야 보이는 것**이다 (→ WeekBlocksSpec.monetization).
//
//  ⚠️ 구독을 파는 화면이라 심사가 보는 것이 있다: 가격과 기간, 체험 뒤 얼마가 나가는지,
//     자동 갱신과 해지 방법, 이용약관·개인정보 처리방침 링크, 구매 복원. 하나라도 빠지면 돌아온다.
//

import SwiftUI
import StoreKit
import LeeoKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var purchases = PurchaseManager.shared

    /// 어느 문 앞에서 열렸는가 (→ WeekBlocksSpec.Gate). 통계에서 "어디서 사고 싶어졌나"를 가른다.
    var reason: String = "settings"

    /// 고른 상품. 처음엔 연간.
    @State private var selectedID: String = WeekBlocksSpec.proYearlyID
    /// 체험을 받을 수 있는 구독 상품들. 이미 한 번 받은 사람에게 '무료 체험'이라고 말하면 거짓말이다.
    @State private var trialEligible: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("무지개 공방 Pro")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .padding(.bottom, 6)

            Text("지난 주들이 쌓이면 보이는 것을 엽니다.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 10) {
                Text("사면 열리는 것")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                row("chart.bar.xaxis", "회고 추세 8주",
                    "잘 되는 요일과 시간대, 번번이 미루는 일까지. 무료로는 지난 2주가 보입니다.")
                row("square.on.square", "다른 주 계획 가져오기",
                    "잘 굴러간 주의 계획을 이번 주에 한 번에 깝니다.")
                row("doc.on.doc", "회고 내보내기",
                    "한 주의 회고를 글로 복사해 노트나 보고서에 붙입니다.")
                row("person.crop.circle.badge.plus", "내 일정 공유",
                    "내 주간 일정을 보기 전용 링크로 보냅니다.")
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text("그대로 무료인 것")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                row("calendar", "주간·일간 계획과 루틴, 할 일", "개수 제한 없이 적고 배치합니다.")
                row("checklist", "회고와 타이머, 다음 첫 동작", "매일 돌아보는 데 값을 받지 않습니다.")
                row("sunrise", "내일 미리 정하기", "저녁에 내일을 닫고, 아침에 첫 걸음 하나를 봅니다.")
                row("iphone", "아이폰과 오가기", "같은 Apple 계정이면 양쪽에서 보입니다.")
            }
            .padding(.bottom, 20)

            plans
                .padding(.bottom, 12)

            if let message = purchases.failureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 12)
                    .transition(.disclose)
            }

            HStack(spacing: 10) {
                Button("나중에") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("구매 복원") {
                    Task {
                        await purchases.restore()
                        if purchases.isPro { dismiss() }
                    }
                }
                .disabled(purchases.isWorking)

                Button {
                    guard let product = selectedProduct else { return }
                    Task {
                        await purchases.purchase(product)
                        if purchases.isPro { dismiss() }
                    }
                } label: {
                    if purchases.isWorking {
                        ProgressView().controlSize(.small)
                            .transition(.opacity)
                    } else {
                        Text(buyTitle)
                            .transition(.opacity)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(purchases.isWorking || selectedProduct == nil)
            }

            legal
                .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 500)
        .animation(Motion.disclose, value: purchases.isWorking)
        .animation(Motion.disclose, value: purchases.failureMessage)
        .animation(Motion.squish, value: selectedID)
        .task {
            // 자체 화면이라 페이월 노출은 여기서 손으로 남긴다. 이게 없으면
            // "안 샀다"와 "볼 기회도 없었다"가 같아진다 (→ Telemetry.swift).
            LeeoAnalyticsCenter.track(.paywallShown(reason: reason))
            if purchases.products.isEmpty { await purchases.loadProducts() }
            var eligible: Set<String> = []
            for product in purchases.products {
                if let sub = product.subscription, sub.introductoryOffer != nil,
                   await sub.isEligibleForIntroOffer {
                    eligible.insert(product.id)
                }
            }
            trialEligible = eligible
        }
    }

    // MARK: 요금제

    private var selectedProduct: Product? {
        purchases.products.first { $0.id == selectedID }
    }

    @ViewBuilder
    private var plans: some View {
        if purchases.products.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("요금제를 불러오는 중…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        } else {
            VStack(spacing: 8) {
                ForEach(purchases.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        let shape = RoundedRectangle.soft(Corner.card)
        return Button {
            guard !selected else { return }
            Haptic.tick()
            withAnimation(Motion.squish) { selectedID = product.id }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: selected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(planName(product))
                            .font(.system(size: 14, weight: .semibold))
                        if product.id == WeekBlocksSpec.proYearlyID {
                            Text("추천")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(planNote(product))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(product.displayPrice)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                    if let unit = periodUnit(product) {
                        Text(unit)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                shape.fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                                   lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.squish)
    }

    private func planName(_ product: Product) -> String {
        switch product.id {
        case WeekBlocksSpec.proYearlyID: String(localized: "연간")
        case WeekBlocksSpec.proLifetimeID: String(localized: "평생")
        case WeekBlocksSpec.proMonthlyID: String(localized: "월간")
        default: product.displayName
        }
    }

    private func planNote(_ product: Product) -> String {
        if trialEligible.contains(product.id), let days = trialDays(product) {
            return String(localized: "\(days)일 무료로 써 보고, 그 뒤에 결제됩니다.")
        }
        switch product.id {
        case WeekBlocksSpec.proLifetimeID: return String(localized: "한 번 결제로 계속 씁니다. 구독이 아닙니다.")
        case WeekBlocksSpec.proMonthlyID: return String(localized: "달마다 결제되고 언제든 해지합니다.")
        default: return String(localized: "해마다 결제되고 언제든 해지합니다.")
        }
    }

    /// "/ 년" · "/ 월". 평생 이용권에는 없다.
    private func periodUnit(_ product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .year: return String(localized: "/ 년")
        case .month: return String(localized: "/ 월")
        case .week: return String(localized: "/ 주")
        case .day: return String(localized: "/ 일")
        @unknown default: return nil
        }
    }

    /// 체험 기간을 날수로. 체험이 아닌 할인 제안이면 nil.
    private func trialDays(_ product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let per = offer.period
        let unitDays: Int
        switch per.unit {
        case .day: unitDays = 1
        case .week: unitDays = 7
        case .month: unitDays = 30
        case .year: unitDays = 365
        @unknown default: return nil
        }
        return per.value * unitDays * max(1, offer.periodCount)
    }

    private var buyTitle: String {
        guard let product = selectedProduct else { return String(localized: "계속") }
        if trialEligible.contains(product.id) { return String(localized: "무료 체험 시작") }
        return String(localized: "\(product.displayPrice) 결제")
    }

    // MARK: 약관

    private var legal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("구독은 기간이 끝나기 24시간 전까지 해지하지 않으면 같은 요금으로 자동 갱신되며, Apple 계정으로 결제됩니다. 무료 체험 중에 해지하면 요금이 나가지 않습니다. 해지와 관리는 App Store의 계정 설정에서 합니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                if let terms = WeekBlocksSpec.monetization.subscriptionTermsURL {
                    Button("이용약관") { openURL(terms) }
                }
                Button("개인정보 처리방침") { openURL(WeekBlocksSpec.legal.privacyURL) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ note: LocalizedStringKey) -> some View {
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
