import Foundation
import SwiftUI
import SwiftData

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

@Model
final class BacklogCategory {
    /// 이름이 바뀌어도 연결이 유지되도록 쓰는 안정적인 식별자.
    var uuid: String = UUID().uuidString
    var name: String = ""
    var colorName: String = "blue"
    var iconName: String = "tag"
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    /// 이 카테고리로 지정하면 '전파 필요'가 자동으로 켜진다.
    /// 이름 대신 플래그로 판별해 사용자가 이름을 바꿔도 동작이 유지된다.
    @Transient var isBroadcast: Bool = false

    init(name: String,
         colorName: String = "blue",
         iconName: String = "tag",
         sortIndex: Int = 0,
         isBroadcast: Bool = false)
    {
        self.uuid = UUID().uuidString
        self.name = name
        self.colorName = colorName
        self.iconName = iconName
        self.sortIndex = sortIndex
        self.createdAt = Date()
        self.isBroadcast = isBroadcast
    }

    var displayColor: Color { paletteColor(colorName) }
}

// 카테고리 아이콘으로 고를 수 있는 SF Symbols
let categoryIconOptions: [String] = [
    "tag", "briefcase", "person", "heart", "book", "house",
    "cart", "dumbbell", "laptopcomputer", "phone", "star", "flag",
    "leaf", "paintbrush", "music.note", "gamecontroller",
    "antenna.radiowaves.left.and.right",
]

extension Array where Element == BacklogCategory {
    /// 전파 카테고리 (기본 시딩으로 하나만 존재한다).
    var broadcastCategory: BacklogCategory? { first { $0.isBroadcast } }
}
