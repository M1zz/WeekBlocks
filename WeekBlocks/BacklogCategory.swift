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
    "antenna.radiowaves.left.and.right",
]

// MARK: - 프로젝트

/// **할 일을 끝이 있는 일 단위로 묶는다.** (테크맵, 1.2 출시 …)
///
/// 분류(BacklogCategory)와는 **다른 축**이다. 분류는 삶의 칸(업무·개인·건강)이라 끝나지
/// 않고, 프로젝트는 끝난다. 할 일 하나가 '업무'이면서 '테크맵'일 수 있어야 해서 분류에
/// 종류를 더하지 않고 따로 세웠다.
///
/// ⚠️ 아이폰 '욕망의 무지개'(ScheduleDensity)의 같은 파일에 **글자 하나까지 같은 정의**가 있다.
///    같은 CloudKit 스키마를 쓰므로 칸을 더하거나 빼면 양쪽을 함께 고친다 (→ README).
///    CloudKit 미러링 규칙대로 모든 칸에 기본값이 있고, 관계 대신 uuid 문자열로 잇는다
///    (할 일 쪽 `BacklogItem.projectID`).
@Model
final class Project {
    /// 이름이 바뀌어도 연결이 유지되도록 쓰는 안정적인 식별자.
    var uuid: String = UUID().uuidString
    var name: String = ""
    var colorName: String = "blue"
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    /// 끝낸 프로젝트. 고르는 자리(칩·메뉴)에서 빠진다. 할 일은 그대로 남는다.
    var isCompleted: Bool = false
    var completedAt: Date? = nil

    init(name: String, colorName: String = "blue", sortIndex: Int = 0) {
        self.uuid = UUID().uuidString
        self.name = name
        self.colorName = colorName
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    var displayColor: Color { paletteColor(colorName) }
}
