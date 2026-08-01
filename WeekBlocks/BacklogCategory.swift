import Foundation
import SwiftUI
import SwiftData

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
