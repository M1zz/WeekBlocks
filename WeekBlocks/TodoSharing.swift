//
//  TodoSharing.swift
//  WeekBlocks
//
//  **올라가는 것은 못 막는다. 그리면 안 되는 것은 안 그리면 된다.**
//
//  잠긴 기기에서 적은 할 일은 상대 기기에 보이면 안 된다. 그런데 동기화 엔진은
//  "이건 올리고 저건 올리지 마"를 못 한다 — 미러링을 켜면 로컬에 있는 것을 전부 올린다.
//  스토어를 둘로 나누면 막을 수야 있지만, 데이터가 사는 집을 쪼개는 일이라 값이 안 맞는다.
//
//  그래서 **막는 자리를 옮겼다.** 데이터는 올라가게 두고, 줄마다 '나눠 쓰는 줄인가'를
//  적어 둔 뒤 **받는 쪽에서 안 그린다.**
//
//  ⚠️ 이건 담장이 아니라 **커튼**이다. 값은 사용자 자신의 iCloud를 거쳐 자신의 다른 기기
//     디스크에 실제로 놓인다. 남의 데이터가 아니므로 보안 문제는 아니지만, "물리적으로
//     막았다"고 말하면 안 된다.
//
//  ⚠️ iOS '욕망의 무지개'의 같은 이름 파일과 **규칙이 똑같아야 한다.** 한쪽만 고치면
//     한쪽에서는 보이고 한쪽에서는 안 보이는 줄이 생긴다.
//
//  거르는 자리는 **`TodoTree`를 세울 때 한 번**이다 (→ TodoTree.swift). 목록·주간
//  화면·결산이 전부 그 트리에서 나오므로 거기서 한 번 거르면 어디에도 안 샌다.
//

import Foundation
import SwiftData

/// **함께 쓰는지를 스스로 말할 수 있는 것.**
///
/// 할 일에만 걸려 있던 규칙을 계획 블록·루틴까지 넓히면서, 세 모델이 같은 두 칸을
/// 갖게 됐다. 규칙을 세 번 쓰면 언젠가 한 벌만 고쳐져 어긋나므로 하나로 묶는다.
protocol SharedRecord: AnyObject {
    var isShared: Bool { get set }
    var originInstallID: String { get set }
}

extension BacklogItem: SharedRecord {}
extension PlanBlock: SharedRecord {}
extension Routine: SharedRecord {}

enum TodoSharing {

    /// 이 설치본의 이름. 기기가 아니라 **이 앱이 깔린 자리**를 가리킨다.
    static var installID: String {
        let key = "todo.installID"
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: key), !saved.isEmpty { return saved }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }

    /// 이 줄을 이 기기에서 만들었는가.
    /// 이름이 비어 있으면(이 기능이 생기기 전에 적은 줄) 내 것으로 본다 —
    /// 쓰던 사람의 줄이 갑자기 남의 것이 되어 사라지면 안 된다.
    static func isMine(_ item: some SharedRecord) -> Bool {
        item.originInstallID.isEmpty || item.originInstallID == installID
    }

    /// **화면에 그릴 줄인가.** 감추는 것은 *남이 잠긴 채로 적어 둔 줄* 하나뿐이다.
    /// 내 줄은 잠겨 있어도 내 화면에서는 그대로 보인다.
    static func isVisible(_ item: some SharedRecord) -> Bool {
        item.isShared || isMine(item)
    }

    /// 새로 적는 줄에 지금 상태를 새긴다.
    static func stamp(_ item: some SharedRecord) {
        item.originInstallID = installID
        item.isShared = TodoAccess.canSync
    }

    /// **값을 치렀다.** 이 기기에서 난 줄들을 상대에게도 보이게 한다.
    /// 그때부터 올라가는 것이 아니라 **이미 올라가 있던 것이 그제서야 보이는** 것이라
    /// 기다림이 없다.
    static func openMyItems(in context: ModelContext) {
        let n = flipMine(to: true, in: context)
        guard n > 0 else { return }
        try? context.save()
        print("🔓 [Sharing] 이 기기의 것 \(n)개를 함께 쓰기로 열었다")
    }

    /// 세 모델을 한 번에 뒤집는다. **내 것만** 건드린다.
    ///
    /// 할 일·계획 블록·루틴이 모두 같은 규칙을 따르므로 한 자리에서 돈다.
    /// 여기 빠진 모델이 있으면 그것만 조용히 새어 보인다 — 모델을 늘릴 때 같이 늘릴 것.
    private static func flipMine(to value: Bool, in context: ModelContext) -> Int {
        flip(BacklogItem.self, to: value, in: context)
            + flip(PlanBlock.self, to: value, in: context)
            + flip(Routine.self, to: value, in: context)
    }

    private static func flip<T: PersistentModel & SharedRecord>(
        _ type: T.Type, to value: Bool, in context: ModelContext
    ) -> Int {
        let mine = ((try? context.fetch(FetchDescriptor<T>())) ?? [])
            .filter { $0.isShared != value && isMine($0) }
        for item in mine { item.isShared = value }
        return mine.count
    }

    /// **무료로 열려 있던 것을 도로 닫는다.** 팔기 시작했는데 안 산 기기에서.
    ///
    /// 팔기 전에는 `stamp`가 모두를 열린 채로 찍는다 — 그때는 살 수도 없으므로 그게 맞다.
    /// 그런데 그대로 두면 **팔기 시작한 뒤에도 무료 기간에 적은 줄은 영영 열려 있다.**
    /// 무료 기간에 깔아 둔 사람만 값을 안 치르고 함께 쓰기를 계속 갖는 셈이라, 그 구멍을
    /// 여기서 막는다.
    ///
    /// ⚠️ **내 줄만 닫는다** (`isMine`). 이 방향이 안전한 이유가 여기 있다 — 줄을 만든
    ///    기기 하나만 자기 줄을 뒤집으므로 양쪽이 서로 반대로 뒤집으며 싸울 일이 없다.
    ///    남이 연 줄에는 손대지 않는다.
    ///
    /// ⚠️ 닫아도 **지우지 않는다.** 내 화면에서는 `isVisible`이 `isMine`으로 계속 그리고,
    ///    상대 기기의 디스크에도 그대로 남아 있다가 값을 치르면 `openMyItems`가 도로 연다.
    ///    되돌릴 수 있는 커튼이지 태우는 일이 아니다.
    static func closeMyItems(in context: ModelContext) {
        let n = flipMine(to: false, in: context)
        guard n > 0 else { return }
        try? context.save()
        print("🔒 [Sharing] 이 기기의 것 \(n)개를 함께 쓰기에서 닫았다")
    }

    /// **영수증과 화면을 맞춘다.** 켤 때 한 번, 그리고 권한이 바뀔 때마다.
    ///
    /// 판정의 근거는 `isUnlocked`가 아니라 **`hasPurchased`**다 (→ MacEntitlement.swift).
    /// 팔기 전에는 아무도 안 샀는데 `isUnlocked`가 참이라, 그 값으로 판정하면 무료 기간에
    /// 적은 것이 산 것과 구별되지 않는다.
    ///
    /// ⚠️ 반드시 `PurchaseManager.refresh()` **뒤에** 부른다. 앞에서 부르면 UserDefaults에
    ///    남은 헌 거울을 보고 산 사람의 줄을 닫는다.
    static func reconcileMySharing(in context: ModelContext) {
        if MacEntitlement.hasPurchased {
            openMyItems(in: context)
        } else if MacEntitlement.sellsAccess {
            // 팔고 있는데 안 샀다 — 무료로 열려 있던 줄을 닫는다.
            closeMyItems(in: context)
        }
        // 아직 팔기 전(`sellsAccess == false`)이면 아무것도 안 한다.
        // 살 길이 없는 사람에게서 뺏으면 그건 값을 받는 게 아니라 고장이다.
    }

    /// 이 기기에서 난 줄 중 상대에게 **아직 안 보이는** 것의 수.
    /// "동기화가 고장났나"와 "안 열어서 그렇다"를 가르는 숫자다.
    static func hiddenFromOthersCount(_ items: [BacklogItem]) -> Int {
        items.filter { !$0.isShared && isMine($0) && !$0.isCompleted }.count
    }
}
