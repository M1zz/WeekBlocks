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

    init(name: String,
         colorName: String = "blue",
         iconName: String = "tag",
         sortIndex: Int = 0)
    {
        self.uuid = UUID().uuidString
        self.name = name
        self.colorName = colorName
        self.iconName = iconName
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    var displayColor: Color { paletteColor(colorName) }
}

// 카테고리 아이콘으로 고를 수 있는 SF Symbols
let categoryIconOptions: [String] = [
    "tag", "briefcase", "person", "heart", "book", "house",
    "cart", "dumbbell", "laptopcomputer", "phone", "star", "flag",
    "leaf", "paintbrush", "music.note", "gamecontroller",
]
