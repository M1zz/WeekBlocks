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

    // MARK: - 전파 계약
    //
    // '전파 필요'로 체크한 항목은 일반 항목과 다른 전처리를 밟는다.
    // 아래 필드가 그 전처리(전파 계약)의 내용이고, 전파 시점은 여기서 역산된다.
    // CloudKit 라이트웨이트 마이그레이션을 위해 전부 기본값 또는 옵셔널이다.

    // ⚠️ **아래 필드들은 일부러 저장하지 않는다 (@Transient).**
    //
    //    전파 계약은 아직 출시 전이라 이 필드들이 **Production CloudKit 스키마에 없다.**
    //    그런데 CloudKit은 모르는 필드를 만나면 그 레코드만 거절하는 게 아니라
    //    미러링 델리게이트 초기화 자체를 실패시킨다 — 받기도 보내기도 통째로 멈춘다
    //    ("Never successfully initialized"). 필드 하나가 맥과 아이폰의 동기화 전부를
    //    죽이고 있었다.
    //
    //    스키마는 CloudKit 콘솔에서만 배포할 수 있어 코드로는 못 고친다. 그래서
    //    동기화를 살리는 쪽을 택했다 — 화면과 계산은 그대로 두고(전부 컴파일된다)
    //    **저장만 안 한다.** 앱을 껐다 켜면 계약 내용은 사라진다.
    //
    //    🔧 되살리는 법: 콘솔에서 Development → Production 스키마를 배포한 뒤
    //       이 @Transient 들을 지우고, iOS 쪽 모델에도 같은 필드를 다시 넣는다
    //       (→ 욕망의 무지개/ScheduleDensityApp/Shared/). 한쪽에만 칸이 있으면
    //       저장할 때 남의 값을 지운다.

    /// 이 할 일을 누군가에게 알려야 하는가.
    @Transient var needsBroadcast: Bool = false
    /// 진짜 마감. 전파 시점 역산의 출발점.
    @Transient var deadline: Date? = nil
    /// BroadcastAudience.rawValue
    @Transient var broadcastAudienceRaw: String = "decisionMaker"
    /// 누구에게 알리는가 (이름·역할).
    @Transient var broadcastRecipient: String = ""
    /// 어떤 모양으로 넘어가는가. 상대가 이걸 전제로 자기 일을 짠다.
    @Transient var handoffForm: String = ""
    /// 빠르면 이 날.
    @Transient var earliestDate: Date? = nil
    /// 늦어도 이 날 보장. 상대가 계획을 세우는 기준이고, 역산의 실제 기준일.
    @Transient var latestDate: Date? = nil
    /// BroadcastConfidence.rawValue
    @Transient var broadcastConfidenceRaw: String = "medium"
    /// 지금 미확정인 것 하나. "없음"이면 없는 것으로 본다.
    @Transient var openVariable: String = ""
    /// 그 변수가 판명되는 날.
    @Transient var variableResolveDate: Date? = nil
    /// "연락 없음 = 정상 진행" 규칙을 상대와 합의했는가.
    @Transient var noSignalRuleAgreed: Bool = false
    /// 전파 계약 전처리를 통과했는가. (일반 항목의 concreteVerified에 대응)
    @Transient var broadcastContractVerified: Bool = false
    /// 이미 보낸 전파 시점의 token 목록 (콤마 구분).
    @Transient var sentCheckpointsRaw: String = ""

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

// 전파 계약 접근자는 BroadcastContract.swift의 프로토콜 익스텐션이 제공한다
// (PlanBlock과 같은 구현을 쓴다).
extension BacklogItem: BroadcastContractHolder { }
