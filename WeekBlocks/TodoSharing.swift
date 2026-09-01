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
    static func isMine(_ item: BacklogItem) -> Bool {
        item.originInstallID.isEmpty || item.originInstallID == installID
    }

    /// **화면에 그릴 줄인가.** 감추는 것은 *남이 잠긴 채로 적어 둔 줄* 하나뿐이다.
    /// 내 줄은 잠겨 있어도 내 화면에서는 그대로 보인다.
    static func isVisible(_ item: BacklogItem) -> Bool {
        item.isShared || isMine(item)
    }

    /// 새로 적는 줄에 지금 상태를 새긴다.
    static func stamp(_ item: BacklogItem) {
        item.originInstallID = installID
        item.isShared = TodoAccess.canEdit
    }

    /// **값을 치렀다.** 이 기기에서 난 줄들을 상대에게도 보이게 한다.
    /// 그때부터 올라가는 것이 아니라 **이미 올라가 있던 것이 그제서야 보이는** 것이라
    /// 기다림이 없다.
    ///
    /// ⚠️ `isShared`는 false → true 로만 간다. 양쪽에서 반대로 뒤집으면 풀 방법이 없고,
    ///    이미 상대에게 내려간 줄을 뒤늦게 감추면 데이터가 사라진 것으로 보인다.
    static func openMyItems(in context: ModelContext) {
        let mine = ((try? context.fetch(FetchDescriptor<BacklogItem>())) ?? [])
            .filter { !$0.isShared && isMine($0) }
        guard !mine.isEmpty else { return }
        for item in mine { item.isShared = true }
        try? context.save()
        print("🔓 [Sharing] 이 기기의 할 일 \(mine.count)개를 함께 쓰기로 열었다")
    }

    /// 이 기기에서 난 줄 중 상대에게 **아직 안 보이는** 것의 수.
    /// "동기화가 고장났나"와 "안 열어서 그렇다"를 가르는 숫자다.
    static func hiddenFromOthersCount(_ items: [BacklogItem]) -> Int {
        items.filter { !$0.isShared && isMine($0) && !$0.isCompleted }.count
    }
}
