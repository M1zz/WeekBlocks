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

    /// 적을 수 있는가.
    static var isUnlocked: Bool {
        guard sellsAccess else { return true }
        return UserDefaults.standard.bool(forKey: purchasedKey)
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
    private(set) var product: Product?
    private(set) var isWorking = false

    private var updates: Task<Void, Never>?

    private init() {
        // 다른 기기에서 사거나 환불한 것이 뒤늦게 도착한다. 계속 듣는다.
        updates = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refresh() }
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
        product = try? await Product.products(for: [MacEntitlement.productID]).first
    }

    func purchase() async {
        guard let product else { return }
        isWorking = true
        defer { isWorking = false }
        guard let result = try? await product.purchase() else { return }
        if case .success(let verification) = result,
           case .verified(let transaction) = verification {
            await transaction.finish()
            await refresh()
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
