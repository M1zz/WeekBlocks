//
//  MacEntitlement.swift
//  WeekBlocks
//
//  **어느 칸을 쓰고 있는가.** 무료 · Plus · Pro (2026-10 개편, → WeekBlocksSpec.monetization).
//
//  칸을 여는 것은 넷이다: 이 맥의 영수증, 아이폰 '욕망의 무지개'가 남긴 표(→ ProMark.swift),
//  언제나 평생 패스(→ LeeoForeverPass, 열리면 Pro), 그리고 판매를 멈춘 예전 상품(월 구독 · 'sync').
//
//  ⚠️ 권한의 근거는 언제나 `Transaction.currentEntitlements`다. 아래 UserDefaults 값은
//     화면이 빨리 그려지라고 둔 거울이지 근거가 아니다. 켤 때마다 다시 확인해 덮어쓴다.
//
//  ⚠️ **영수증을 읽는 일은 LeeoKit(`LeeoStore`)이 한다.** 이 파일에 남은 것은 **정책**뿐이다.
//

import Foundation
import Combine
import StoreKit
import LeeoKit

/// 무지개 공방의 세 칸. Pro 는 Plus 를 전부 포함한다.
enum MacTier: Int, Comparable, CaseIterable {
    case free = 0
    case plus = 1
    case pro = 2

    static func < (lhs: MacTier, rhs: MacTier) -> Bool { lhs.rawValue < rhs.rawValue }

    init(_ mark: ProMarkTier?) {
        switch mark {
        case .plus: self = .plus
        case .pro: self = .pro
        case nil: self = .free
        }
    }

    /// 아이폰에 남길 표의 등급. 무료면 표를 지운다.
    var markTier: ProMarkTier? {
        switch self {
        case .free: nil
        case .plus: .plus
        case .pro: .pro
        }
    }

    /// **영수증 · 아이폰 표 · 패스를 합친 칸.** 셋 중 가장 높은 것.
    static func resolve(owned: Set<String>, crossPlatform: ProMarkTier?, foreverPass: Bool) -> MacTier {
        if foreverPass { return .pro }   // 패스는 그 앱의 가장 높은 칸을 연다
        return max(WeekBlocksSpec.tier(owned: owned), MacTier(crossPlatform))
    }
}

enum MacEntitlement {

    /// **Pro를 팔기 시작했는가.**
    ///
    /// 개발 빌드에서는 켠다 — `WeekBlocks.storekit`의 가짜 스토어로 페이월과 구매 흐름을
    /// 끝까지 굴려 볼 수 있어야 한다. 출시 빌드는 App Store Connect에 상품
    /// (연간·월간 구독, 평생 이용권)을 만들고 **심사에 함께 올리는 판에서** 켠다.
    ///
    /// ⚠️ 상품이 콘솔에 없는데 출시 빌드에서 켜면 Pro 기능이 잠긴 채로 서고 아무도 못 산다.
    ///
    /// ✅ 1.1.12부터 판다 (2026-10-13). 평생 이용권(`.sync`)·연간·월간을 콘솔에 세웠다.
    ///    ⚠️ 처음 파는 인앱결제는 **이 빌드와 함께 심사에 내야** 한다 — 상품만 승인 안 된 채로 나가면
    ///    페이월이 '불러오는 중'에 멈춘다.
    static var sellsPro: Bool { true }

    /// 1.1.14까지 Pro 하나를 비추던 거울(Bool). 지금은 칸(`tierKey`)을 적는다.
    /// 옛 값이 true 면 Pro 로 읽는다. 그때 산 것은 모두 Pro 였다.
    private static let purchasedKey = "mac.pro.purchased"
    private static let tierKey = "mac.tier"

    /// 캐시에 적혀 있는 칸. **nil은 '무료'가 아니라 '아직 애플에게 안 물어봤다'** 이다.
    ///
    /// 그 차이를 잃으면 처음 켠 사람에게, 산 사람이라도, 잠깐 "무료"라고 **단정해서** 말하게 된다.
    static var cachedTier: MacTier? {
        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: tierKey) as? Int { return MacTier(rawValue: raw) ?? .free }
        if let old = defaults.object(forKey: purchasedKey) as? Bool { return old ? .pro : .free }
        return nil
    }

    /// 무엇이든 유료 칸을 가졌는가. nil 은 모름 (→ Telemetry).
    static var cachedPurchase: Bool? { cachedTier.map { $0 != .free } }

    /// **지금 칸.** 모를 때는 무료 쪽으로 기운다. 문을 여는 판단이라 모르는 채로 열면 안 된다.
    /// 대신 *화면에 뭐라고 쓸지*는 `PurchaseManager.isKnown`을 함께 보고, 아직 모르면 '확인 중'이라고 말한다.
    static var currentTier: MacTier { cachedTier ?? .free }

    /// 영수증 확인 결과를 적는다. `PurchaseManager`만 부른다.
    static func setTier(_ tier: MacTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: tierKey)
    }
}

/// 영수증을 확인하고 사는 일을 맡는다. 화면은 `isPro`·`offersPro`만 본다.
///
/// **속은 전부 `LeeoStore`다.** 이 클래스가 하는 일은 두 가지뿐이다 —
///  ① LeeoKit의 값(`ObservableObject`)을 SwiftUI의 `@Observable` 세계로 옮겨 적는 것,
///  ② 그 값을 **앱의 정책**(`MacEntitlement`)에 통과시키는 것.
@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    @ObservationIgnored let store: LeeoStore
    /// 언제나 평생 패스. 열려 있으면 Pro 다.
    @ObservationIgnored let pass = LeeoForeverPass(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub")

    /// 지금 칸 (→ `MacTier.resolve`).
    private(set) var tier: MacTier = MacEntitlement.currentTier
    /// **애플에게 물어봐서 답을 받았는가.** false면 화면은 '무료'라고 단정하면 안 된다.
    private(set) var isKnown: Bool = MacEntitlement.cachedTier != nil
    /// 페이월에 설 상품들 (→ WeekBlocksSpec.saleProductIDs).
    private(set) var products: [Product] = []
    /// 이 맥의 영수증에 있는 상품들. 올리기 · 졸업 · 패스 값을 고를 때 본다.
    private(set) var ownedIDs: Set<String> = []
    /// 지금 살아 있는 구독. 있으면 설정에 '평생으로 바꾸기'가 선다.
    private(set) var subscription: LeeoGraduation.Subscription?
    private(set) var isWorking = false
    /// 사다가 막혔을 때 화면에 그대로 보여줄 말. 조용히 실패하면 사용자는 단추가 고장 난 줄 안다.
    private(set) var failureMessage: String?

    /// Plus 가 여는 것(추세 8주 · 요일별 · 시간대별 · 계획 대비 실제 · 다른 주 계획 가져오기).
    var isPlus: Bool { tier >= .plus }
    /// Pro 가 여는 것(일정 공유, 아이폰 Pro).
    var isPro: Bool { tier == .pro }

    /// **유료 기능을 화면에 세우는가.** 팔고 있거나, 이미 산 사람이면.
    var offersPro: Bool { MacEntitlement.sellsPro || tier > .free }

    /// Plus 평생을 이 맥에서 샀는가. 그러면 Pro 평생 단추가 올리기 상품을 산다.
    var ownsPlusLifetime: Bool { ownedIDs.contains(WeekBlocksSpec.plusLifetimeID) }
    /// 끝이 없는 Pro 를 이 맥에서 샀는가. 패스는 올리기 값으로 팔고, 졸업은 권하지 않는다.
    var ownsLifetimePro: Bool { !ownedIDs.isDisjoint(with: WeekBlocksSpec.proLifetimeIDs) }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    /// 설정에 가격 한 줄을 적을 대표 상품 (가장 싼 길, Plus 연).
    var featuredProduct: Product? {
        product(WeekBlocksSpec.plusYearlyID) ?? products.first
    }

    /// **이번 실행에서 영수증을 실제로 읽었는가.**
    ///
    /// ⚠️ 이 플래그가 서기 전에는 캐시에 아무것도 쓰지 않는다. LeeoStore는 상품을
    ///    불러오는 중에도 값이 바뀌었다고 알려 오는데, 그 알림에 대고 빈 영수증을
    ///    캐시에 적어 버리면 **처음 켠 구매자가 '무료'로 못박힌다.**
    @ObservationIgnored private var entitlementsChecked = false
    @ObservationIgnored private var observations: Set<AnyCancellable> = []

    private init() {
        guard let config = WeekBlocksSpec.paywall else {
            preconditionFailure("계약에 페이월이 없다. WeekBlocksSpec.monetization을 확인할 것")
        }
        store = LeeoStore(config: config)

        // ⚠️ objectWillChange는 값이 바뀌기 **직전**에 온다. 그 자리에서 읽으면 옛 값이므로
        //    다음 차례로 미뤄서 읽는다.
        store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.pull() }
        }.store(in: &observations)
        pass.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.pull() }
        }.store(in: &observations)
    }

    /// 영수증을 다시 읽어 권한을 맞춘다. 켤 때마다 부른다.
    func refresh() async {
        await store.refreshEntitlements()
        if MacEntitlement.sellsPro { await store.loadProducts() }
        await pass.refresh()
        entitlementsChecked = true
        await syncCrossPlatformMark()
        subscription = await LeeoGraduation.currentSubscription(among: WeekBlocksSpec.subscriptionIDs)
        pull()
    }

    // MARK: - 한쪽에서 사면 양쪽이 (→ ProMark.swift)

    /// 이 맥의 영수증만 본 칸. 아이폰에 남기는 표는 이것이다(남의 표 · 패스를 옮겨 적지 않는다).
    private var receiptTier: MacTier { WeekBlocksSpec.tier(owned: store.purchasedProductIDs) }

    /// **내 영수증을 아이폰이 읽을 수 있는 표로 옮겨 적고, 아이폰이 적어 둔 표를 읽는다.**
    ///
    /// ⚠️ 아이폰의 `PurchaseManager.syncCrossPlatformMark`와 **같은 규칙**이다. 자기 표만
    ///    쓰고 지우며, 구독은 끝나는 날을, 칸은 등급(plus · pro)을 함께 적는다. 한쪽을 고치면 같이 고칠 것.
    private func syncCrossPlatformMark() async {
        let mine = receiptTier
        markedTier = mine
        let ids = mine == .pro ? WeekBlocksSpec.proEntitlementIDs : WeekBlocksSpec.plusEntitlementIDs
        let defaultID = mine == .pro ? WeekBlocksSpec.proYearlyID : WeekBlocksSpec.plusYearlyID
        crossPlatformTier = await ProMarkStore.sync(tier: mine.markTier,
                                                    entitlementIDs: ids,
                                                    defaultProductID: defaultID,
                                                    in: PlanStore.shared.context)
    }

    /// 아이폰에서 산 것 중 살아 있는 가장 높은 등급.
    @ObservationIgnored private var crossPlatformTier: ProMarkTier?

    /// 내 표에 마지막으로 옮겨 적은 칸. 영수증이 이것과 달라지면 표를 다시 적는다.
    @ObservationIgnored private var markedTier: MacTier?

    /// 고른 상품을 산다. 성공·취소·승인 대기·실패의 갈래와 퍼널 이벤트는 LeeoStore 안에 있다.
    func purchase(_ product: Product) async {
        _ = await store.purchase(product)
        entitlementsChecked = true
        subscription = await LeeoGraduation.currentSubscription(among: WeekBlocksSpec.subscriptionIDs)
        pull()
    }

    /// 상품을 아직 못 불러왔을 때 페이월이 다시 청한다.
    func loadProducts() async {
        await store.loadProducts()
        pull()
    }

    /// 기기를 바꿨거나 다시 깔았을 때.
    func restore() async {
        await store.restore()
        await pass.refresh()
        entitlementsChecked = true
        subscription = await LeeoGraduation.currentSubscription(among: WeekBlocksSpec.subscriptionIDs)
        pull()
    }

    // MARK: - 구독 졸업

    /// 졸업 상품. 상품을 아직 못 불러왔으면 nil.
    var graduateProduct: Product? { product(WeekBlocksSpec.proGraduateID) }

    /// **지금 졸업가를 한 번 보일 때인가.** 구독 중이고, 끝이 없는 Pro 가 아직 없고,
    /// 창(6개월째 · 갱신 7일 전)에 처음 들어섰을 때. 보이기로 했으면 그 자리에서 표시를 남긴다.
    func takeGraduationOffer(now: Date = Date()) -> Bool {
        guard MacEntitlement.sellsPro, let subscription, !ownsLifetimePro, !pass.isActive,
              LeeoGraduation.isDue(subscription, now: now, lastOffered: LeeoGraduation.lastOffered())
        else { return false }
        LeeoGraduation.markOffered(now)
        return true
    }

    private func pull() {
        // 사기·복원·리스너(다른 기기, 가족 공유, 환불, 만료)로 영수증이 바뀌었으면 표도 바로 고친다.
        if entitlementsChecked, let marked = markedTier, marked != receiptTier {
            markedTier = receiptTier
            Task { await syncCrossPlatformMark(); pull() }
        }
        if entitlementsChecked {
            MacEntitlement.setTier(MacTier.resolve(owned: store.purchasedProductIDs,
                                                   crossPlatform: crossPlatformTier,
                                                   foreverPass: pass.isActive))
        }
        tier = MacEntitlement.currentTier
        isKnown = entitlementsChecked || MacEntitlement.cachedTier != nil
        ownedIDs = store.purchasedProductIDs
        products = store.products
        isWorking = store.purchasingProductID != nil || store.isRestoring
        failureMessage = store.lastError
    }
}
