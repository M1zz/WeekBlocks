//
//  MacEntitlement.swift
//  WeekBlocks
//
//  **'함께 쓰기'를 샀는가.** 한 번 사면 끝인 비소모성 상품 하나.
//
//  이 앱에서 값을 받는 것은 **적기** 하나뿐이다 (→ TodoAccess.swift).
//  잠겨 있어도 아이폰에서 온 할 일은 그대로 내려와 보이고, 예전에 적어 둔 것도
//  그대로 있다. 새로 적는 것만 막힌다.
//
//  ⚠️ **기본값이 '열림'이다.** 상품을 App Store Connect에 만들고 실제로 팔기 전까지는
//     아무도 살 수 없는데, 그동안 앱이 잠겨 있으면 쓰던 사람이 갑자기 못 적게 된다.
//     그건 값을 받는 게 아니라 뺏는 것이다. 팔 준비가 끝나면 `sellsAccess`를 켠다.
//     그 한 줄이 이 정책 전부다.
//
//  ⚠️ 권한의 근거는 언제나 `Transaction.currentEntitlements`다. 아래 UserDefaults 값은
//     화면이 빨리 그려지라고 둔 거울이지 근거가 아니다. 켤 때마다 다시 확인해 덮어쓴다.
//

import Foundation
import StoreKit

enum MacEntitlement {

    /// App Store Connect의 비소모성 상품 ID.
    /// ⚠️ 콘솔에 만든 것과 **글자 하나까지 같아야 한다.**
    static let productID = "com.devkoan.ScheduleDensityApp.sync"

    /// **팔기 시작했는가.** false인 동안에는 모두에게 열려 있다.
    /// 상품 심사가 끝나고 실제로 판매를 시작할 때 true로 바꾼다.
    static let sellsAccess = false

    private static let purchasedKey = "mac.sync.purchased"

    /// 적을 수 있는가. 팔기 전에는 모두에게 열려 있다.
    static var isUnlocked: Bool {
        guard sellsAccess else { return true }
        return hasPurchased
    }

    /// **값을 치렀는가.** `sellsAccess`와 무관한 영수증의 사실이다.
    ///
    /// `isUnlocked`와 갈라 두는 이유: 팔기 전에는 아무도 안 샀는데도 `isUnlocked`가
    /// true다. 그 값으로 '함께 쓰기'를 판정하면 **무료 기간에 적은 것이 산 것과 똑같이**
    /// 다른 기기에 열려 버리고, 팔기 시작한 뒤에도 그대로 남는다 (→ TodoSharing.swift의
    /// `reconcileMySharing`). '적을 수 있는가'와 '나눠 쓸 수 있는가'는 다른 질문이다.
    static var hasPurchased: Bool {
        UserDefaults.standard.bool(forKey: purchasedKey)
    }

    /// 영수증 확인 결과를 적는다. `PurchaseManager`만 부른다.
    static func setPurchased(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: purchasedKey)
    }
}

/// 영수증을 확인하고 사는 일을 맡는다. 화면은 `isUnlocked`만 본다.
@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    private(set) var isUnlocked: Bool = MacEntitlement.isUnlocked
    /// 값을 치렀는가 (→ `MacEntitlement.hasPurchased`).
    /// 근거는 UserDefaults지만 그건 관찰이 안 되므로, 화면이 볼 수 있게 여기 거울을 하나 둔다.
    /// 무료 개방 기간에는 `isUnlocked`가 참이어도 이 값은 거짓이다 — 설정의 '프로/무료'는
    /// 이쪽을 본다.
    private(set) var hasPurchased: Bool = MacEntitlement.hasPurchased
    private(set) var product: Product?
    private(set) var isWorking = false
    /// 사다가 막혔을 때 화면에 그대로 보여줄 말. 조용히 실패하면 사용자는
    /// 버튼이 고장 난 줄 안다.
    private(set) var failureMessage: String?

    private var updates: Task<Void, Never>?

    private init() {
        // 다른 기기에서 사거나 환불한 것이 뒤늦게 도착한다. 계속 듣는다.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                // ⚠️ 여기로 온 거래는 **반드시 끝냈다고 알려야 한다.** 안 그러면 App Store가
                //    켤 때마다 같은 거래를 다시 보낸다 — 다른 맥에서 산 것, 가족 공유로
                //    들어온 것, '구입 요청' 승인분이 특히 그렇다. 끝났다고 말하지 않는 한
                //    App Store는 우리가 물건을 못 받았다고 여긴다.
                //
                //    권한의 근거는 여전히 아래 refresh()가 영수증에서 다시 읽는다.
                //    여기서 하는 일은 '받았다'는 회신 하나뿐이다.
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    /// 영수증을 다시 읽어 권한을 맞춘다. 켤 때마다 부른다.
    func refresh() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == MacEntitlement.productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        MacEntitlement.setPurchased(owned)
        isUnlocked = MacEntitlement.isUnlocked
        hasPurchased = MacEntitlement.hasPurchased
        product = try? await Product.products(for: [MacEntitlement.productID]).first
    }

    func purchase() async {
        guard let product else {
            failureMessage = "상품을 아직 못 불러왔습니다. 잠시 뒤 다시 시도해 주세요."
            return
        }
        isWorking = true
        failureMessage = nil
        defer { isWorking = false }
        let result: Product.PurchaseResult
        do { result = try await product.purchase() }
        catch { failureMessage = "구매하지 못했습니다: \(error.localizedDescription)"; return }
        // 성공만 보고 나머지를 흘리면, 승인 대기(구입 요청)에 걸린 사람은 아무 말도 못 듣고
        // 버튼이 고장 난 줄 안다. 취소만 조용하다 — 스스로 그만둔 것이라 할 말이 없다.
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                failureMessage = "영수증을 확인하지 못했습니다. 잠시 뒤 다시 시도해 주세요."
                return
            }
            await transaction.finish()
            await refresh()
        case .pending:
            failureMessage = "승인을 기다리는 중입니다. 승인되면 앱이 알아서 열립니다."
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    /// 기기를 바꿨거나 다시 깔았을 때.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refresh()
    }
}
