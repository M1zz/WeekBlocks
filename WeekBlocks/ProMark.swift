//
//  ProMark.swift
//
//  **한쪽에서 사면 양쪽이 열린다.**
//
//  아이폰 '욕망의 무지개'와 맥 '무지개 공방'은 App Store에서 서로 다른 앱이다(번들 ID가
//  다르다). 그래서 유니버설 구매가 안 되고, 한쪽에서 산 것이 다른 쪽 영수증에는 없다.
//  두 앱을 다 쓰는 사람 — 가장 오래 쓸 사람 — 에게 두 번 받는 모양이 되는 자리다.
//
//  두 앱은 **같은 iCloud 계정의 같은 컨테이너**를 쓰므로, 산 쪽이 "샀다"는 표를 하나 적어
//  두면 다른 쪽이 그것을 보고 열 수 있다. 이 파일이 그 표다.
//
//  ⚠️ **표는 영수증이 아니다.** 권한의 근거는 언제나 각 앱의 `Transaction.currentEntitlements`이고,
//     이 표는 그것을 **옮겨 적은 쪽지**일 뿐이다. 그래서 규칙이 셋이다.
//      1. 앱은 **자기 표만** 쓰고 지운다. 남의 표는 읽기만 한다 — 안 그러면 두 앱이 서로의
//         만료일을 덮어써서, 아무도 진실을 모르게 된다.
//      2. 구독은 **끝나는 날**을 함께 적는다. 그 날이 지나면 남의 표는 안 쳐준다.
//         평생 이용권은 끝이 없으므로 비워 둔다.
//      3. 자기 영수증에서 권한이 사라지면 자기 표를 지운다. 해지가 다른 기기에도 닿아야 한다.
//
//  ⚠️ 이 파일은 두 레포에 **같은 내용으로** 복제돼 있다. CloudKit 스키마를 함께 쓰므로
//     한쪽만 고치면 다른 쪽에서 안 보이거나, 안 지워진다. 한쪽을 고치면 반드시 같이 고칠 것.
//

import Foundation
import SwiftData

@Model
final class ProMark {
    /// 어느 앱이 적은 표인가. "ios" · "mac".
    var platformRaw: String = ProMarkPlatform.ios.rawValue
    /// 무엇을 샀는가. 사람이 나중에 들여다볼 때를 위한 것이지, 판단에는 쓰지 않는다.
    var productID: String = ""
    /// 구독이 끝나는 날. **nil이면 끝이 없다**(평생 이용권·옛 1회 구매).
    var validUntil: Date? = nil
    /// 마지막으로 확인한 때.
    var updatedAt: Date = Date()

    init(platform: ProMarkPlatform, productID: String, validUntil: Date?) {
        self.platformRaw = platform.rawValue
        self.productID = productID
        self.validUntil = validUntil
        self.updatedAt = Date()
    }

    var platform: ProMarkPlatform { ProMarkPlatform(rawValue: platformRaw) ?? .ios }

    /// 지금도 유효한 표인가.
    func isValid(at now: Date = Date()) -> Bool {
        guard let validUntil else { return true }
        return validUntil > now
    }
}

enum ProMarkPlatform: String {
    case ios
    case mac

    /// 지금 이 앱.
    static var current: ProMarkPlatform {
#if os(macOS)
        .mac
#else
        .ios
#endif
    }
}

enum ProMarkStore {

    /// **다른 쪽 앱이 남긴 표가 살아 있는가.** 이것 하나면 열어 준다.
    static func otherPlatformHasPro(in context: ModelContext, now: Date = Date()) -> Bool {
        let mine = ProMarkPlatform.current.rawValue
        let marks = (try? context.fetch(FetchDescriptor<ProMark>())) ?? []
        return marks.contains { $0.platformRaw != mine && $0.isValid(at: now) }
    }

    /// 내 표를 적거나 고친다. 같은 앱의 표는 늘 하나만 둔다.
    static func stamp(productID: String, validUntil: Date?, in context: ModelContext) {
        let mine = ProMarkPlatform.current
        let marks = ((try? context.fetch(FetchDescriptor<ProMark>())) ?? [])
            .filter { $0.platform == mine }

        if let existing = marks.first {
            existing.productID = productID
            existing.validUntil = validUntil
            existing.updatedAt = Date()
            // 어쩌다 둘 이상 생겼으면 하나만 남긴다 (두 기기가 같은 순간에 적은 경우).
            for extra in marks.dropFirst() { context.delete(extra) }
        } else {
            context.insert(ProMark(platform: mine, productID: productID, validUntil: validUntil))
        }
        try? context.save()
    }

    /// 내 표를 지운다. 해지했거나 환불받았을 때.
    static func clearMine(in context: ModelContext) {
        let mine = ProMarkPlatform.current
        let marks = ((try? context.fetch(FetchDescriptor<ProMark>())) ?? [])
            .filter { $0.platform == mine }
        guard !marks.isEmpty else { return }
        for mark in marks { context.delete(mark) }
        try? context.save()
    }
}
