//
//  DayPanelExpansion.swift
//  무지개 공방
//
//  일간의 판 하나를 크게 편다.
//
//  오늘의 계획은 오른쪽 위 반쪽에 있어 줄이 길어지면 답답했다. 판을 누르면 그 판이 화면을 다 차지하도록
//  좍 늘어나고, 나머지 판은 비켜선다. 접는 길은 다섯 — 펴진 판 바탕을 다시 누르기, 오른쪽 위 접기 단추,
//  위쪽 손잡이를 아래로 끌기, 판 밖(요일 줄·안내)을 누르기, Esc.
//
//  판 안의 단추·체크·알약은 그대로 먼저 눌린다. 판을 펴는 탭은 그 아래 빈 바탕이 받는다.
//

import SwiftUI

/// 일간에서 크게 펼 수 있는 판.
enum DayPanel: Hashable {
    case schedule, plan, backlog
}

extension AnyTransition {
    /// 비켜서는 판 — 작아지며 옅어진다. 크게 펴는 판이 그 자리를 채우며 늘어난다.
    static let panelAside = AnyTransition.scale(scale: 0.9, anchor: .center).combined(with: .opacity)
}

extension Animation {
    /// 판을 펴고 접는 결. 목표를 조금 지나쳤다가 돌아온다 — 툭 멈추면 딱딱하다.
    static let panelSpring = Animation.spring(response: 0.48, dampingFraction: 0.66)
}

/// 판이 출렁이는 정도. 가로와 세로가 엇갈려 움직여야 '쫀득'하게 읽힌다 —
/// 가로로 늘어나는 동안 세로는 살짝 눌렸다가, 자리를 잡으며 반대로 한 번 튕긴다.
private struct Jelly {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

private struct ExpandablePanel: ViewModifier {
    let panel: DayPanel
    @Binding var expanded: DayPanel?

    /// 손잡이를 끌어 내린 만큼. 넘으면 접는다.
    @State private var pull: CGFloat = 0
    /// 움직임 줄이기를 켠 사람에게는 출렁이지 않는다.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expanded == panel }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // 판 바탕을 누르면 편다. 펴진 판의 바탕을 다시 누르면 접는다 — 같은 자리, 같은 손짓으로 오간다.
            // 판 안의 단추·체크·알약은 그대로 먼저 눌린다.
            .onTapGesture {
                if isExpanded {
                    collapse()
                } else if expanded == nil {
                    Haptic.tick()
                    withAnimation(.panelSpring) { expanded = panel }
                }
            }
            .overlay(alignment: .top) {
                if isExpanded {
                    handle
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isExpanded {
                    Button {
                        collapse()
                    } label: {
                        Label("접기", systemImage: "arrow.down.right.and.arrow.up.left")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.squish)
                    .help("접기 (Esc)")
                    .padding(10)
                    .transition(.pop)
                }
            }
            // 펴고 접힐 때 한 번 출렁인다 — 커졌다(약 108%) 살짝 줄었다 제자리로.
            .keyframeAnimator(initialValue: Jelly(), trigger: reduceMotion ? false : isExpanded) { view, j in
                view.scaleEffect(x: j.x, y: j.y, anchor: .top)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(1.08, duration: 0.16)
                    SpringKeyframe(0.97, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(0.96, duration: 0.12)
                    SpringKeyframe(1.05, duration: 0.2, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.34, spring: .bouncy)
                }
            }
            // 끌어 내리는 동안 판이 손을 따라 조금 내려가고 작아진다 — 놓으면 접힌다는 것이 미리 보인다.
            .offset(y: pull * 0.5)
            .scaleEffect(1 - min(pull, 160) / 1600, anchor: .top)
    }

    /// 위쪽 가운데 손잡이. 아래로 끌면 접는다.
    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 44, height: 5)
            .padding(.vertical, 6)
            .padding(.horizontal, 30)
            .contentShape(Rectangle())
            .hoverCursor(.resizeUpDown)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { v in pull = max(0, v.translation.height) }
                    .onEnded { v in
                        if v.translation.height > 60 || v.predictedEndTranslation.height > 140 {
                            collapse()
                        } else {
                            withAnimation(Motion.squish) { pull = 0 }
                        }
                    }
            )
            .help("아래로 끌어 접기")
    }

    private func collapse() {
        Haptic.tick()
        withAnimation(.panelSpring) {
            expanded = nil
            pull = 0
        }
    }
}

extension View {
    /// 누르면 크게 펴지는 일간의 판 (→ ExpandablePanel).
    func expandable(_ panel: DayPanel, expanded: Binding<DayPanel?>) -> some View {
        modifier(ExpandablePanel(panel: panel, expanded: expanded))
    }
}
