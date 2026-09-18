//
//  MacEntitlement.swift
//  WeekBlocks
//
//  **「무지개 공방 Pro」를 샀는가.** 연간·월간 구독이나 평생 이용권, 무엇이든 하나.
//
//  Pro가 여는 것은 **쌓여야 보이는 것**뿐이다 — 지난 주들의 회고 추세, 다른 주 계획 가져오기.
//  계획하고 적고 돌아보고 아이폰과 오가는 것은 전부 무료다 (→ WeekBlocksSpec.monetization).
//
//  ⚠️ **팔기 전에는 Pro 기능을 아예 세우지 않는다** (`offersPro`).
//     무료로 열어 두었다가 나중에 잠그면 그건 새로 파는 게 아니라 뺏는 것이다.
//     예전에 '아이폰으로 건너가기'를 팔려다 그 자리에서 데었다. 그래서 거꾸로 간다 —
//     상품이 스토어에 서기 전에는 보이지 않고, 서는 날 잠긴 채로 처음 나타난다.
//
//  ⚠️ 권한의 근거는 언제나 `Transaction.currentEntitlements`다. 아래 UserDefaults 값은
//     화면이 빨리 그려지라고 둔 거울이지 근거가 아니다. 켤 때마다 다시 확인해 덮어쓴다.
//
//  ⚠️ **영수증을 읽는 일은 LeeoKit(`LeeoStore`)이 한다.** 상품 로드·구매·복원·
//     거래 리스너(다른 기기에서 산 것, 가족 공유, '구입 요청' 승인분, 환불, 구독 만료)가
//     거기 다 들어 있다. 이 파일에 남은 것은 **정책**뿐이다 —
//     "지금 팔고 있는가(`sellsPro`)"와 "모를 때 뭐라고 말할 것인가(`cachedPurchase`)".
//

import Foundation
import Combine
import StoreKit
import LeeoKit

enum MacEntitlement {

    /// **Pro를 팔기 시작했는가.**
    ///
    /// 개발 빌드에서는 켠다 — `WeekBlocks.storekit`의 가짜 스토어로 페이월과 구매 흐름을
    /// 끝까지 굴려 볼 수 있어야 한다. 출시 빌드는 App Store Connect에 상품
    /// (연간·월간 구독, 평생 이용권)을 만들고 **심사에 함께 올리는 판에서** 켠다.
    ///
    /// ⚠️ 상품이 콘솔에 없는데 출시 빌드에서 켜면 Pro 기능이 잠긴 채로 서고 아무도 못 산다.
    static var sellsPro: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// v1.1.3까지 '함께 쓰기'를 비추던 거울. 그때는 아무도 살 수 없었으므로 옮겨 올 값이 없다.
    /// 새 이름을 쓰는 까닭은 옛 값이 '안 샀다'로 남아 있으면 Pro 구매자에게도 한 번은 틀린 말을 하기 때문이다.
    private static let purchasedKey = "mac.pro.purchased"

    /// 캐시에 적혀 있는 답. **nil은 '안 샀다'가 아니라 '아직 애플에게 안 물어봤다'** 이다.
    ///
    /// `UserDefaults.bool(forKey:)`는 이 둘을 똑같이 false로 돌려준다. 그 차이를 잃으면
    /// 처음 켠 사람에게 — 산 사람이라도 — 잠깐 "무료"라고 **단정해서** 말하게 된다.
    static var cachedPurchase: Bool? {
        UserDefaults.standard.object(forKey: purchasedKey) as? Bool
    }

    /// **Pro인가.** 모를 때는 안 산 쪽으로 기운다 — 문을 여는 판단이라 모르는 채로 열면 안 된다.
    /// 대신 *화면에 뭐라고 쓸지*는 `PurchaseManager.isKnown`을 함께 보고, 아직 모르면 '확인 중'이라고 말한다.
    static var hasPurchased: Bool { cachedPurchase ?? false }

    /// 영수증 확인 결과를 적는다. `PurchaseManager`만 부른다.
    static func setPurchased(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: purchasedKey)
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

    /// Pro를 샀는가 (→ `MacEntitlement.hasPurchased`).
    private(set) var isPro: Bool = MacEntitlement.hasPurchased
    /// **애플에게 물어봐서 답을 받았는가.** false면 화면은 '무료'라고 단정하면 안 된다.
    private(set) var isKnown: Bool = MacEntitlement.cachedPurchase != nil
    /// 페이월에 설 상품들. 계약의 차례(연간 → 평생 → 월간)를 따른다.
    private(set) var products: [Product] = []
    private(set) var isWorking = false
    /// 사다가 막혔을 때 화면에 그대로 보여줄 말. 조용히 실패하면 사용자는 단추가 고장 난 줄 안다.
    private(set) var failureMessage: String?

    /// **Pro 기능을 화면에 세우는가.** 팔고 있거나, 이미 산 사람이면.
    ///
    /// 산 사람에게는 판매를 멈춘 뒤에도 계속 보인다 — 값을 치른 것이 사라지면 안 된다.
    var offersPro: Bool { MacEntitlement.sellsPro || isPro }

    /// 설정 화면에 가격 한 줄을 적을 대표 상품 (연간).
    var featuredProduct: Product? {
        products.first { $0.id == WeekBlocksSpec.proYearlyID } ?? products.first
    }

    /// **이번 실행에서 영수증을 실제로 읽었는가.**
    ///
    /// ⚠️ 이 플래그가 서기 전에는 캐시에 아무것도 쓰지 않는다. LeeoStore는 상품을
    ///    불러오는 중에도 값이 바뀌었다고 알려 오는데, 그 알림에 대고 `hasPro`(아직 false)를
    ///    캐시에 적어 버리면 **처음 켠 구매자가 '무료'로 못박힌다.**
    @ObservationIgnored private var entitlementsChecked = false
    @ObservationIgnored private var observation: AnyCancellable?

    private init() {
        guard let config = WeekBlocksSpec.paywall else {
            preconditionFailure("계약에 페이월이 없다 — WeekBlocksSpec.monetization을 확인할 것")
        }
        store = LeeoStore(config: config)

        // ⚠️ objectWillChange는 값이 바뀌기 **직전**에 온다. 그 자리에서 읽으면 옛 값이므로
        //    다음 차례로 미뤄서 읽는다.
        observation = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.pull() }
        }
    }

    /// 영수증을 다시 읽어 권한을 맞춘다. 켤 때마다 부른다.
    func refresh() async {
        await store.refreshEntitlements()
        if MacEntitlement.sellsPro { await store.loadProducts() }
        entitlementsChecked = true
        await syncCrossPlatformMark()
        pull()
    }

    // MARK: - 한쪽에서 사면 양쪽이 (→ ProMark.swift)

    /// **내 영수증을 아이폰이 읽을 수 있는 표로 옮겨 적고, 아이폰이 적어 둔 표를 읽는다.**
    ///
    /// 두 앱은 App Store에서 서로 다른 앱이라 영수증이 건너가지 않는다. 그런데 두 앱을 다
    /// 쓰는 사람에게 두 번 받는 것은 팔기 전에 이미 잃는 장사다. 같은 iCloud를 쓰므로
    /// 산 쪽이 표를 하나 남기면 다른 쪽이 그것을 보고 연다.
    ///
    /// ⚠️ 아이폰의 `PurchaseManager.syncCrossPlatformMark`와 **같은 규칙**이다. 자기 표만
    ///    쓰고 지우며, 구독은 끝나는 날을 함께 적는다. 한쪽을 고치면 같이 고칠 것.
    private func syncCrossPlatformMark() async {
        crossPlatformPro = await ProMarkStore.sync(hasPro: store.hasPro,
                                                   entitlementIDs: WeekBlocksSpec.proEntitlementIDs,
                                                   defaultProductID: WeekBlocksSpec.proYearlyID,
                                                   in: PlanStore.shared.context)
    }

    /// 아이폰에서 산 것이 살아 있는가.
    @ObservationIgnored private var crossPlatformPro = false

    /// 고른 상품을 산다. 성공·취소·승인 대기·실패의 갈래와 퍼널 이벤트는 LeeoStore 안에 있다.
    func purchase(_ product: Product) async {
        _ = await store.purchase(product)
        entitlementsChecked = true
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
        entitlementsChecked = true
        pull()
    }

    private func pull() {
        if entitlementsChecked {
            // 아이폰에서 산 표가 살아 있으면 그것도 권한이다 (→ syncCrossPlatformMark).
            MacEntitlement.setPurchased(store.hasPro || crossPlatformPro)
        }
        isPro = MacEntitlement.hasPurchased
        isKnown = entitlementsChecked || MacEntitlement.cachedPurchase != nil
        products = store.products
        isWorking = store.purchasingProductID != nil || store.isRestoring
        failureMessage = store.lastError
    }
}
