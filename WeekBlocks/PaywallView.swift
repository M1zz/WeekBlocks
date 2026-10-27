//
//  PaywallView.swift
//  WeekBlocks
//
//  **무료 · Plus · Pro 세 칸을 나란히 보이는 자리** (2026-10 개편).
//
//  화면이 먼저 하는 말은 **무엇이 그대로인가**다. 잠긴 것부터 늘어놓으면 앱이 인질처럼
//  보이는데, 실제로 이 앱의 본체는 잠겨 있지 않다. 계획도, 루틴도, 적는 것도, 이번 주
//  회고와 그 복사도, 아이폰과 오가는 것도 값을 안 받는다. 그래서 무료 칸이 맨 앞에 선다.
//
//  값을 받는 것은 **지난 주들이 쌓여야 보이는 것(Plus)** 과 **남에게 내보내고 아이폰까지 여는 것(Pro)** 이다
//  (→ WeekBlocksSpec.monetization). 유료 칸마다 연 구독과 평생을 고른다(`LeeoTermPicker`).
//
//  ⚠️ 구독을 파는 화면이라 심사가 보는 것이 있다: 가격과 기간, 첫 해 할인 뒤 얼마가 나가는지,
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

    @State private var plusTerm: LeeoPlanTerm = .yearly
    @State private var proTerm: LeeoPlanTerm = .yearly
    /// 첫 해 할인을 받을 수 있는 연 구독. 이미 한 번 받은 사람에게 할인가를 말하면 거짓말이다.
    @State private var introEligible: Set<String> = []
    /// 프로모션 코드 넣는 시트 (→ OfferCode.swift).
    @State private var showingOfferCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("무지개 공방 Plus · Pro")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .padding(.bottom, 6)

            Text("지난 주들이 쌓이면 보이는 것을 엽니다.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)

            if purchases.products.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("요금제를 불러오는 중…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)
            }

            HStack(alignment: .top, spacing: 12) {
                freeCard
                plusCard
                proCard
            }
            .padding(.bottom, 10)

            // 세 칸 아래 한 줄: 이 개발자의 모든 앱을 평생으로 (→ LeeoForeverPass).
            LeeoForeverPassLine(pass: purchases.pass, ownsLifetimePro: purchases.ownsLifetimePro)
            LeeoLifetimePriceNotice()
                .padding(.bottom, 10)

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
                Spacer(minLength: 12)
                secondaryButtons
            }

            legal
                .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 780)
        .offerCodeSheet(isPresented: $showingOfferCode)
        .animation(Motion.disclose, value: purchases.isWorking)
        .animation(Motion.disclose, value: purchases.failureMessage)
        .animation(Motion.squish, value: purchases.tier)
        .task {
            // 자체 화면이라 페이월 노출은 여기서 손으로 남긴다. 이게 없으면
            // "안 샀다"와 "볼 기회도 없었다"가 같아진다 (→ Telemetry.swift).
            LeeoAnalyticsCenter.track(.paywallShown(reason: reason))
            if purchases.products.isEmpty { await purchases.loadProducts() }
            await loadIntroEligibility()
        }
        .onChange(of: purchases.products.map(\.id)) { _, _ in
            Task { await loadIntroEligibility() }
        }
        // 사거나 코드를 써서 칸이 올라갔으면 이 창은 할 일을 다 했다.
        .onChange(of: purchases.tier) { old, new in
            if new > old { dismiss() }
        }
    }

    // MARK: 칸

    private var freeCard: some View {
        card(title: "무료", tier: .free) {
            row("calendar", "주간·일간 계획과 루틴, 할 일", "개수 제한 없이 적고 배치합니다.")
            row("checklist", "회고와 타이머, 다음 첫 동작", "매일 돌아보는 데 값을 받지 않습니다.")
            row("doc.on.doc", "이번 주 회고를 글로 복사합니다", "한 주의 회고를 글로 복사해 노트나 보고서에 붙입니다.")
            row("sunrise", "내일 미리 정하기", "저녁에 내일을 닫고, 아침에 첫 걸음 하나를 봅니다.")
            row("calendar.badge.plus", "캘린더에서 가져오기")
            row("iphone", "아이폰과 오가기", "같은 Apple 계정이면 양쪽에서 보입니다.")
        } footer: {
            EmptyView()
        }
    }

    private var plusCard: some View {
        card(title: "Plus", tier: .plus) {
            row("chart.bar.xaxis", "회고 추세 8주",
                "잘 되는 요일과 시간대, 번번이 미루는 일까지. 무료로는 지난 2주가 보입니다.")
            row("stopwatch", "계획 대비 실제",
                "계획한 시간 중 해낸 시간, 일마다 계획보다 얼마나 더 걸리는지 봅니다.")
            row("square.on.square", "다른 주 계획 가져오기",
                "잘 굴러간 주의 계획을 이번 주에 한 번에 깝니다.")
        } footer: {
            purchaseArea(term: $plusTerm,
                         yearly: purchases.product(WeekBlocksSpec.plusYearlyID),
                         lifetime: purchases.product(WeekBlocksSpec.plusLifetimeID),
                         prominent: false)
        }
    }

    private var proCard: some View {
        card(title: "Pro", tier: .pro, recommended: true) {
            row("checkmark.circle", "Plus의 모든 것")
            row("person.crop.circle.badge.plus", "내 일정 공유", "내 주간 일정을 보기 전용 링크로 보냅니다.")
            // 두 앱은 서로 다른 앱이지만, 한쪽에서 산 Pro 가 다른 쪽도 연다 (→ ProMark.swift).
            row("iphone", "한 번 사면 아이폰 앱도 함께 Pro로 열립니다.")
        } footer: {
            // Plus 평생을 이미 산 사람에게 평생 Pro 는 차액(올리기 상품)이다.
            purchaseArea(term: $proTerm,
                         yearly: purchases.product(WeekBlocksSpec.proYearlyID),
                         lifetime: purchases.product(purchases.ownsPlusLifetime
                                                     ? WeekBlocksSpec.proUpgradeID
                                                     : WeekBlocksSpec.proLifetimeID),
                         prominent: true)
        }
    }

    /// 칸 카드 하나. 지금 쓰는 칸이면 테두리를 세우고, 아래 단추 자리에 그 사실을 적는다.
    private func card<Rows: View, Footer: View>(
        title: LocalizedStringKey, tier: MacTier, recommended: Bool = false,
        @ViewBuilder rows: () -> Rows, @ViewBuilder footer: () -> Footer
    ) -> some View {
        let current = purchases.isKnown && purchases.tier == tier
        let included = purchases.tier > tier && tier != .free
        let shape = RoundedRectangle.soft(Corner.card)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                if recommended, !current {
                    Text("추천")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 8) { rows() }
            Spacer(minLength: 0)
            if current {
                Label("지금 쓰는 중", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
            } else if included {
                Label("Pro에 포함", systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                footer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape.fill(recommended ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03))
            shape.strokeBorder(current || recommended ? Color.accentColor : Color.primary.opacity(0.08),
                               lineWidth: current || recommended ? 1.5 : 1)
        }
    }

    /// 유료 칸의 아래: 연 구독 / 평생 고르기와 고른 길의 결제 단추.
    @ViewBuilder
    private func purchaseArea(term: Binding<LeeoPlanTerm>, yearly: Product?, lifetime: Product?,
                              prominent: Bool) -> some View {
        let chosen = term.wrappedValue == .yearly ? yearly : lifetime
        VStack(alignment: .leading, spacing: 10) {
            LeeoTermPicker(term: term, yearly: yearly, lifetime: lifetime)
            Button {
                guard let chosen else { return }
                Task { await purchases.purchase(chosen) }
            } label: {
                Group {
                    if purchases.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(buyTitle(chosen))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .modifier(Prominence(prominent: prominent))
            .disabled(purchases.isWorking || chosen == nil)
        }
    }

    private struct Prominence: ViewModifier {
        let prominent: Bool
        func body(content: Content) -> some View {
            if prominent {
                content.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }

    /// "₩2,200 결제". 첫 해 할인을 받을 수 있으면 실제로 나갈 할인가를 적는다.
    private func buyTitle(_ product: Product?) -> String {
        guard let product else { return String(localized: "계속") }
        var price = product.displayPrice
        if introEligible.contains(product.id), let offer = product.subscription?.introductoryOffer,
           offer.paymentMode == .payUpFront || offer.paymentMode == .payAsYouGo {
            price = offer.displayPrice
        }
        return String(localized: "\(price) 결제")
    }

    private func loadIntroEligibility() async {
        var eligible: Set<String> = []
        for product in purchases.products {
            if let sub = product.subscription, sub.introductoryOffer != nil,
               await sub.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        introEligible = eligible
    }

    // MARK: 단추

    @ViewBuilder
    private var secondaryButtons: some View {
        Button("구매 복원") {
            Task { await purchases.restore() }
        }
        .disabled(purchases.isWorking)

        // 받은 프로모션 코드를 여기서 바로 쓴다 (→ OfferCode.swift).
        if OfferCode.isAvailable {
            Button("코드 사용") { showingOfferCode = true }
                .disabled(purchases.isWorking)
        }
    }

    // MARK: 약관

    private var legal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("연 구독은 기간이 끝나기 24시간 전까지 해지하지 않으면 정가로 자동 갱신되며, Apple 계정으로 결제됩니다. 첫 해 할인은 처음 구독하는 분께 한 번만 적용됩니다. 해지와 관리는 App Store의 계정 설정에서 합니다. 평생은 한 번만 결제하고 갱신되지 않습니다.")
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

    private func row(_ icon: String, _ title: LocalizedStringKey, _ note: LocalizedStringKey? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
