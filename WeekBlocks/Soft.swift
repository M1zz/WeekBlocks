//
//  Soft.swift
//  WeekBlocks
//
//  **말랑한 조각들.** 일간의 알약 타임라인에서 나온 모양을 앱 전체가 함께 쓴다.
//
//  색 동그라미 안의 흰 그림(루틴 아이콘·할 일 첫 글자)과, 눌러서 채우는 둥근 체크.
//  화면마다 따로 그리면 어딘가는 네모나고 어딘가는 둥글어 한 앱으로 안 읽힌다 —
//  무엇인지를 말하는 자리는 `GlyphBadge`, 끝냈는지를 찍는 자리는 `SoftCheck` 하나로 간다.
//

import SwiftUI

/// 무엇인지를 색과 그림 하나로 — 색 동그라미(또는 알약) 안에 흰 아이콘이나 첫 글자.
struct GlyphBadge: View {
    enum Style {
        /// 꽉 찬 색. 정해진 것(고정 루틴·계획 블록).
        case filled
        /// 옅은 색에 점선 — 시간이 유연한 것(끼니 같은 쿼터).
        case dashed
        /// 옅은 색 바탕에 색 그림 — 목록 안의 조용한 표시.
        case soft
    }

    /// SF Symbol 이름. 없으면 `title`의 첫 글자를 쓴다.
    var symbol: String?
    var title: String = ""
    let color: Color
    var size: CGFloat = 24
    var style: Style = .filled
    /// 흐리게(끝낸 것).
    var dimmed = false

    private var letter: String {
        title.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "•"
    }

    var body: some View {
        ZStack {
            switch style {
            case .filled:
                Circle().fill(color.gradient)
            case .dashed:
                Circle().fill(Color.surface)
                Circle().fill(color.opacity(0.22))
                Circle().strokeBorder(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
            case .soft:
                Circle().fill(color.opacity(0.16))
            }
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.46, weight: .semibold))
                } else {
                    Text(letter)
                        .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(style == .filled ? Color.white : color)
        }
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.55 : 1)
        .shadow(color: style == .filled ? color.opacity(0.28) : .clear, radius: size * 0.1, y: size * 0.06)
    }
}

/// **눌러서 채우는 둥근 체크.** 비어 있으면 색 테두리, 찍으면 그 색으로 톡 차오르며 흰 표시.
///
/// 표시는 셋이다(달성·부분·건너뜀) — 누르면 달성과 비움만 오가고, 나머지는 메뉴에서 고른다
/// (→ ReflectionRow). 누르는 손맛(딸깍·출렁임)은 여기서 한 번에 준다.
struct SoftCheck: View {
    let status: ReviewStatus?
    var color: Color = .green
    var size: CGFloat = 22
    let onToggle: () -> Void

    var body: some View {
        Button {
            Haptic.tick()
            withAnimation(Motion.squish) { onToggle() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(color.opacity(status == nil ? 0.55 : 0), lineWidth: 1.8)
                Circle()
                    .fill(tint)
                    .scaleEffect(status == nil ? 0.2 : 1)
                    .opacity(status == nil ? 0 : 1)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .black))
                    .foregroundStyle(.white)
                    .scaleEffect(status == nil ? 0.3 : 1)
                    .opacity(status == nil ? 0 : 1)
            }
            .frame(width: size, height: size)
            .shadow(color: status == nil ? .clear : tint.opacity(0.35), radius: 3, y: 1.5)
            .contentShape(Circle())
        }
        .buttonStyle(.squish)
        .animation(Motion.squish, value: status)
    }

    private var symbol: String {
        switch status {
        case .partial: "circle.lefthalf.filled"
        case .skipped: "xmark"
        default: "checkmark"
        }
    }

    private var tint: Color {
        switch status {
        case .partial: .yellow
        case .skipped: .red.opacity(0.85)
        default: color
        }
    }
}

/// **누르면 진행이 한 칸 차는 동그라미.** 할 일 카드 맨 앞, 무엇인지를 말하던 자리에 선다.
///
/// 테두리 고리가 곧 진행도다. 단계로 쪼갠 일은 누를 때마다 지금 단계를 끝내고 고리가 그만큼
/// 차고, 안 쪼갠 일은 한 번에 꽉 차며 체크가 선다. 평소에는 안에 분류 아이콘(없으면 비어 있다)이
/// 있다가, 가리키면 누르면 무엇이 되는지(→ 다음 단계 / ✓ 끝)로 바뀐다.
struct ProgressCheck: View {
    /// 0…1.
    let progress: Double
    let color: Color
    var symbol: String?
    var title: String = ""
    /// 단계로 쪼갠 일인가. 가리켰을 때 보일 표시가 달라진다.
    var stepped = false
    var size: CGFloat = 30
    let action: () -> Void

    @State private var hovering = false

    private var done: Bool { progress >= 0.999 }

    var body: some View {
        Button {
            Haptic.tick()
            action()
        } label: {
            ZStack {
                Circle().fill(color.opacity(done ? 0 : 0.12))
                Circle().stroke(color.opacity(0.22), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(color.gradient)
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)

                Group {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.42, weight: .black))
                            .foregroundStyle(.white)
                            .transition(.pop)
                    } else if hovering {
                        Image(systemName: stepped ? "arrow.right" : "checkmark")
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(color)
                            .transition(.pop)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(color)
                            .transition(.pop)
                    }
                    // 분류가 없으면 빈 고리 그대로 둔다 — 첫 글자는 제목을 한 번 더 읽을 뿐이었다.
                }
            }
            .frame(width: size, height: size)
            .shadow(color: done ? color.opacity(0.35) : .clear, radius: 4, y: 2)
            .scaleEffect(hovering && !done ? 1.04 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.squish)
        .onHover { hovering = $0 }
        .animation(Motion.squish, value: progress)
        .animation(Motion.squish, value: hovering)
    }
}


/// **손에 들려 가는 카드.** 끌기 시작하면 이 모양이 손끝을 따라간다.
///
/// 기본값은 뷰를 그대로 찍은 사진이라, 두 줄짜리 할 일 카드가 통째로 따라다녀 무엇을 들었는지
/// 보다 덩어리가 먼저 보였다. 들고 다니는 동안 필요한 것은 **무엇을 들었는가** 하나뿐이다.
struct DragPreviewCard: View {
    let title: String
    let hours: Double
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            GlyphBadge(symbol: symbol, title: title, color: color, size: 24)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(formatDuration(hours))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
    }
}


/// **내려놓는 결.** 막 놓인 것이 한 번 부풀었다 제자리로 내려앉는다.
///
/// 새로 생긴 것은 이미 톡 튀어나오지만(`AnyTransition.pop`), 그것만으로는 "생겼다"까지다.
/// 놓은 자리에서 한 번 더 출렁여야 **내가 거기 놓았다**는 것이 손과 눈에 함께 남는다.
struct LandingTracker {
    /// 이미 본 것들. 처음 그릴 때의 전부는 '방금 놓인 것'이 아니다.
    private(set) var seen: Set<String> = []
    private(set) var landed: String?

    /// 목록이 바뀌었다. 하나만 새로 생겼으면 그것이 방금 놓인 것이다.
    mutating func update(_ ids: [String]) -> Bool {
        let now = Set(ids)
        defer { seen = now }
        guard !seen.isEmpty else { return false }
        let fresh = now.subtracting(seen)
        guard fresh.count == 1, let one = fresh.first else { return false }
        landed = one
        return true
    }

    mutating func clear() { landed = nil }
}

extension View {
    /// 방금 놓인 것이면 한 번 부푼다.
    func landingBounce(_ landed: Bool) -> some View {
        scaleEffect(landed ? 1.07 : 1)
            .animation(Motion.squish, value: landed)
    }
}
