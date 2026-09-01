import Foundation
import SwiftUI
import SwiftData

    // 전파 계약. 아직 출시 전인 맥 전용 기능이다.
    //
    // ⚠️ CloudKit **Development** 환경이라 이 필드들은 서버에 자동으로 만들어진다
    //    (→ WeekBlocks.entitlements). Production이었다면 콘솔에서 배포하기 전까지
    //    서버가 모르는 필드라, 그 하나 때문에 미러링 초기화가 실패해 받기·보내기가
    //    통째로 멈춘다. 실제로 그렇게 한 번 멈췄었다.
    //
    // ⚠️ iOS '욕망의 무지개'에도 **같은 필드가 있어야 한다.** 같은 스토어를 쓰는데
    //    한쪽에만 칸이 없으면 그쪽이 저장할 때 남의 값을 지운다.

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
    var isBroadcast: Bool = false

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
