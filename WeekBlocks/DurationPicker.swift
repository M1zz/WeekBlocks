//
//  DurationPicker.swift
//  WeekBlocks
//
//  **얼마나 걸릴지 — 한 번 눌러 열고, 한 번 눌러 정한다.**
//
//  시간을 정하는 자리가 다섯 군데였고 모양이 셋이었다. 블록 편집기는 "길이 (h)" 칸에
//  `2.5`를 치거나 ▲▼를 여러 번, 단계 줄은 `0.5`를 치고 옆에 "h", 할 일 상세와 프로젝트
//  창은 메뉴. 사람은 시간을 "30분", "1시간 반"으로 생각하는데 소수 시간을 치게 했고,
//  같은 것을 정하는데 자리마다 손이 달랐다.
//
//  이제 어디서든 같은 알약 하나다. 누르면 자주 쓰는 시간이 버튼으로 서고, 누르면 닫힌다.
//  목록에 없는 시간은 아래 −/+ 로 15분씩 맞춘다.
//

import SwiftUI

struct DurationPicker: View {
    @Binding var hours: Double
    var range: ClosedRange<Double> = 0.25...12
    var tint: Color = .accentColor
    /// 알약 앞에 붙는 말 ("다 하면"). 없으면 시간만.
    var prefix: LocalizedStringKey? = nil
    var style: Style = .pill

    enum Style {
        /// 옅은 캡슐 — 창 안에서 따로 서는 자리 (블록 편집기, 할 일 상세 머리).
        case pill
        /// 글자만 — 목록 줄 끝처럼 여러 개가 늘어서는 자리.
        case plain
    }

    @State private var open = false

    /// 자주 쓰는 시간. 사람은 여기서 대부분을 고른다.
    static let presets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]
    private static let step = 0.25

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix)
                }
                Text(formatDuration(hours))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .opacity(style == .pill ? 1 : 0.6)
            }
            .font(style == .pill ? .body.weight(.semibold) : .body)
            .foregroundStyle(style == .pill ? tint : Color.secondary)
            .padding(.horizontal, style == .pill ? 10 : 4)
            .padding(.vertical, style == .pill ? 4 : 2)
            .background(style == .pill ? tint.opacity(0.1) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .help(String(localized: "얼마나 걸릴지"))
        .animation(Motion.number, value: hours)
        .popover(isPresented: $open, arrowEdge: .bottom) { panel }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("얼마나 걸릴까요")
                .font(.body.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.presets.filter { range.contains($0) }, id: \.self) { h in
                    let selected = abs(h - hours) < 0.001
                    Button {
                        hours = h
                        open = false
                    } label: {
                        Text(formatDuration(h))
                            .font(.body.weight(selected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selected ? tint.opacity(0.18) : Color.primary.opacity(0.06),
                                        in: .soft(Corner.chip))
                            .overlay(RoundedRectangle.soft(Corner.chip)
                                .strokeBorder(selected ? tint.opacity(0.6) : .clear, lineWidth: 1.2))
                            .foregroundStyle(selected ? tint : .primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // 목록에 없는 시간은 15분씩. 누르는 동안 창은 안 닫힌다.
            HStack {
                Button { nudge(-Self.step) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(hours <= range.lowerBound ? Color.secondary.opacity(0.4) : tint)
                .disabled(hours <= range.lowerBound)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Spacer()
                Text(formatDuration(hours))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()

                Button { nudge(Self.step) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(hours >= range.upperBound ? Color.secondary.opacity(0.4) : tint)
                .disabled(hours >= range.upperBound)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .animation(Motion.number, value: hours)

            Text("15분씩 · ← → 키로도")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 340)
    }

    /// 15분 격자에 붙여서 옮긴다 — 1시간 10분처럼 격자 밖에 있던 값도 한 번 누르면 격자로 온다.
    private func nudge(_ delta: Double) {
        let snapped = ((hours + delta) / Self.step).rounded() * Self.step
        hours = min(max(snapped, range.lowerBound), range.upperBound)
    }
}
