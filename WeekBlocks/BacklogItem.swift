import Foundation
import SwiftData

@Model
final class BacklogItem {
    var title: String = ""
    var durationHours: Double = 1
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    // Stable string token used to identify the item during drag-and-drop.
    var dragToken: String = UUID().uuidString
    /// 연결된 BacklogCategory.uuid (없으면 nil = 미분류).
    var categoryID: String? = nil
    /// 이 할 일이 속한 주 (월요일 00:00). 지난 주에 못 한 항목 구분에 사용.
    var weekStartDate: Date = Date.currentWeekStart
    /// iOS Todo에서 체크한 완료 상태. 완료되면 맥 백로그 그리드에서는 숨긴다.
    var isCompleted: Bool = false
    var completedAt: Date? = nil

    // MARK: - 뎁스(단계)
    //
    // 할 일 하나를 100%로 놓고 그 안을 '일이 되어야 하는 순서대로' 쪼갠 단계들.
    // 단계도 같은 BacklogItem이고, 부모의 dragToken을 parentToken으로 들고 있다.
    // 순서는 sortIndex, 비중은 부모의 예상 시간을 나눠 가진 비율이다 → TodoTree.swift
    // 시간은 위에서 아래로 내려간다: 상위 할 일의 durationHours가 100%이고,
    // 단계들은 그 시간을 나눠 갖는다(기본 N분의 1). 합은 언제나 부모의 시간이다.
    // CloudKit 라이트웨이트 마이그레이션을 위해 옵셔널 + 기본값 nil.

    /// 상위 할 일의 dragToken. nil이면 최상위 할 일(= 그 자체가 100%).
    var parentToken: String? = nil

    /// '착수 조건'(바로/펼치고/몰입해서…)으로 단계를 나누던 시절의 필드.
    ///    이미 배포된 사용자·iOS 앱과 공유하는 CloudKit 스키마에 들어 있어 지우지 못한다.
    ///    (지우면 라이트웨이트 마이그레이션이 깨진다.)
    ///
    ///    ⚠️ 직접 읽거나 쓰지 말 것. 지금은 **두 질문에 사용자가 직접 답한 것**을 담는
    ///    자리로 다시 쓰고 있고, 접두어(`pick:`)로 옛 값과 구분한다.
    ///    → BacklogItem+Fragment.swift 의 `fragmentPick`으로만 드나든다.
    var labelRaw: String? = nil


    // MARK: - 함께 쓰는 줄인가 (→ TodoSharing.swift)
    //
    // 잠긴 기기에서 적은 줄은 상대 기기에 보이면 안 된다. 그런데 동기화 엔진은
    // 골라서 안 올리는 것을 못 한다 — 켜면 로컬에 있는 것을 전부 올린다.
    // 그래서 **올라가게 두고, 받는 쪽에서 안 그린다.** 그러려면 판단에 필요한 것이
    // 줄에 같이 실려 가야 한다. 결제 여부는 나중에 바뀌는데, 받는 쪽은 상대가
    // 그때 샀는지를 알 방법이 없기 때문이다.

    /// 상대 기기에도 보여도 되는 줄인가. **false → true 로만 간다** —
    /// 결제하면 켜지고 다시 꺼지지 않는다. 양쪽에서 반대로 뒤집으면 풀 방법이 없다.
    var isShared: Bool = true

    /// 이 줄이 난 자리(앱 설치본). 잠긴 기기의 스토어에는 자기 것과 상대 것이
    /// 섞여 있어서, 감출 것을 고르려면 누가 만들었는지를 알아야 한다.
    /// 비어 있으면 이 기능이 생기기 전에 적은 줄이고, 그때는 내 것으로 본다.
    var originInstallID: String = ""

    init(title: String,
         durationHours: Double = 1,
         sortIndex: Int = 0,
         categoryID: String? = nil,
         weekStartDate: Date = Date.currentWeekStart)
    {
        self.title = title
        self.durationHours = durationHours
        self.sortIndex = sortIndex
        self.dragToken = UUID().uuidString
        self.categoryID = categoryID
        self.weekStartDate = weekStartDate
    }
}
