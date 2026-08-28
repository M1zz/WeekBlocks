//
//  TodoLabelChip.swift
//  WeekBlocks
//
//  라벨(= 예상 시간) 하나를 그리는 칩. 앱과 공유 익스텐션이 함께 컴파일한다 —
//  공유 창에서도 백로그와 똑같은 칩으로 시간을 고르게 하기 위해서다.
//  (그래서 SwiftData·TipKit에 기대지 않는다. import는 SwiftUI 하나뿐.)
//

import SwiftUI

extension TodoLabel {
    /// 속성의 색. iOS·맥이 같은 색을 쓰도록 하나씩 못 박아 둔다.
    /// '기다림'만 회색이다 — 내 시간을 쓰지 않는 유일한 속성이라 한눈에 갈라 보여야 한다.
    var tint: Color {
        switch self {
        case .ready:   return .green
        case .setup:   return .teal
        case .deep:    return .indigo
        case .decide:  return .orange
        case .waiting: return .gray
        }
    }
}

/// 목록·상세·입력창 어디서나 같은 모양으로 쓰는 라벨 칩.
///
/// ⚠️ iOS '욕망의 무지개'의 TodoLabelChip.swift와 같은 규칙을 쓴다 (점 크기만 맥에 맞게
///    한 단계 작다). 한쪽을 고치면 다른 쪽도 같이 고칠 것.
///
/// 속성이 '지금 시작할 수 있나'를 말하므로 이름이 곧 알맹이다 — 시간은 딸려 오는
/// 값이라 뒤에 붙인다. '기다림'은 내 시간을 안 쓰므로 시간 자리를 비운다.
/// `.full`은 가로로 늘어놓고 고르는 자리에서 조금 더 넉넉하게 쓴다.
struct TodoLabelChip: View {
    enum Style { case time, full }

    let label: TodoLabel
    var hours: Double? = nil
    var isSelected: Bool = false
    var style: Style = .time

    /// 시간이 따로 안 넘어오면 속성의 기본 시간을 쓴다.
    private var shownHours: Double { hours ?? label.defaultHours }
    /// '기다림'은 내 시간을 안 쓰므로 시간을 적지 않는다.
    private var showsHours: Bool { label.costsMyTime && shownHours > 0 }

    var body: some View {
        // ⚠️ 시간은 **칩 밖**에 둔다. 알약 안에 같이 넣으면 "바로 15분"처럼 한 덩어리로
        //    읽혀서, 조건인지 길이인지 구분이 안 된다. 조건은 알약, 시간은 그 옆의 글자다.
        //    (iOS '욕망의 무지개'와 같은 규칙.)
        HStack(spacing: 6) {
            capsuleBody
            if showsHours {
                Text(formatDuration(shownHours))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsHours ? "\(label.name), \(formatDuration(shownHours))" : label.name)
    }

    private var capsuleBody: some View {
        HStack(spacing: 5) {
            Image(systemName: label.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(label.name)
                .font(.system(size: 13, weight: .semibold))
        }
        .lineLimit(1)
        // ⚠️ 칩은 어떤 자리에서도 쪼그라들지 않는다.
        //    폭이 모자란 자리에 놓이면 SwiftUI가 글자를 세로로 접어 버린다
        //    ("1시간" → "1 / 시 / 간"). 자리를 양보하는 건 옆의 제목이어야 한다.
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(isSelected ? Color.white : label.tint)
        .padding(.horizontal, style == .full ? 10 : 8)
        .padding(.vertical, style == .full ? 6 : 4)
        .background(Capsule().fill(isSelected ? label.tint : label.tint.opacity(0.14)))
    }
}

