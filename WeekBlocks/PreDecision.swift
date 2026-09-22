//
//  PreDecision.swift
//  WeekBlocks
//
//  **아침의 첫 걸음은 어젯밤에 정한다.**
//
//  하루를 망치는 것은 대개 일의 양이 아니라 **아침에 무엇부터 할지 정하는 일**이다.
//  일어나서 고르기 시작하면 고르는 데 기운을 다 쓰고, 정작 첫 걸음은 늦게 뗀다.
//  그런데 어젯밤의 나는 그걸 이미 알고 있었다 — 계획이 거기 적혀 있으니까.
//
//  그래서 하루에 딱 두 번만 말을 건다.
//    - **저녁(18시 이후):** 내일이 닫혀 있는가. 비어 있으면 지금 채우자고 부른다.
//    - **아침(12시 이전):** 오늘의 첫 걸음 하나만 크게. 목록이 아니라 한 걸음이다.
//
//  ⚠️ **하루에 한 번 닫으면 그날은 다시 안 뜬다.** 매번 뜨는 안내는 사흘이면 벽지가 된다.
//

import SwiftUI

struct PreDecisionBanner: View {
    /// 지금. 바깥의 `TimelineView`가 분마다 새 값을 준다.
    let now: Date
    /// 오늘의 계획 블록 (시각 순).
    let todayBlocks: [PlanBlock]
    /// 내일의 계획 블록 (시각 순).
    let tomorrowBlocks: [PlanBlock]
    /// 지금 보고 있는 날이 오늘인가. 다른 날을 들여다보는 중에는 말을 걸지 않는다.
    let isViewingToday: Bool
    /// 이 블록을 지금 센다 (타이머).
    var onStart: (PlanBlock) -> Void = { _ in }
    /// 내일로 건너간다.
    var onOpenTomorrow: () -> Void = {}

    /// 마지막으로 닫은 안내. "2026-09-18-morning" 꼴이다.
    @AppStorage("preDecision.dismissed") private var dismissed = ""
    /// **지금 화면에 서 있는 안내**(key). 보일지 말지를 여기 따로 들고, 바뀔 때마다 `withAnimation`으로 옮긴다.
    ///
    /// ⚠️ 한때 `withAnimation { dismissed = key }`로 닫았는데 **사라질 때 결이 없었다.**
    ///    `@AppStorage`의 변경은 UserDefaults 를 한 번 돌아 나중에 화면에 닿아서 그 애니메이션에 안 실린다.
    ///    12시가 지나거나 첫 걸음을 끝내서 저절로 내려갈 때는 애초에 애니메이션이 없었다.
    @State private var shownKey: String?

    enum Kind: Equatable {
        /// 아침 — 오늘의 첫 걸음 하나.
        case morning(PlanBlock)
        /// 저녁 — 내일이 닫혀 있다. 첫 걸음을 보여 준다.
        case tomorrowReady(PlanBlock)
        /// 저녁 — 내일이 비어 있다.
        case tomorrowEmpty
    }

    private var hour: Int { Calendar.current.component(.hour, from: now) }

    /// 오늘 아직 안 끝낸 것 중 가장 이른 것 = 지금의 첫 걸음.
    private var firstOpenToday: PlanBlock? {
        todayBlocks.first { $0.reviewStatus == nil }
    }

    private var kind: Kind? {
        guard isViewingToday else { return nil }
        if hour >= 18 {
            return tomorrowBlocks.first.map(Kind.tomorrowReady) ?? .tomorrowEmpty
        }
        if hour < 12, let first = firstOpenToday {
            return .morning(first)
        }
        return nil
    }

    /// 오늘 이 안내를 이미 닫았는가. 아침·저녁은 따로 센다.
    private var key: String? {
        guard let kind else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let phase: String = {
            switch kind {
            case .morning: return "morning"
            case .tomorrowReady, .tomorrowEmpty: return "evening"
            }
        }()
        return "\(f.string(from: now))-\(phase)"
    }

    /// 지금 서야 할 안내. 없거나 오늘 닫았으면 nil.
    private var visibleKey: String? {
        guard let key, dismissed != key else { return nil }
        return key
    }

    var body: some View {
        VStack(spacing: 0) {
            if let kind, let key, shownKey == key {
                card(kind, key: key)
                    .transition(.disclose)
            }
        }
        .onAppear { shownKey = visibleKey }
        // 서야 할 것이 바뀌면(닫음·시각·첫 걸음을 끝냄) 결을 실어 옮긴다 — 아래 요일 줄도 함께 올라온다.
        .onChange(of: visibleKey) { _, new in
            withAnimation(Motion.disclose) { shownKey = new }
        }
    }

    private func card(_ kind: Kind, key: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            GlyphBadge(symbol: symbol(kind), color: tint(kind), size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint(kind))
                Text(headline(kind))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let note = note(kind) {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            switch kind {
            case .morning(let block):
                Button {
                    onStart(block)
                } label: {
                    Label("지금 시작", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)
            case .tomorrowReady:
                Button("내일 보기") { onOpenTomorrow() }
                    .buttonStyle(.bordered)
            case .tomorrowEmpty:
                Button("내일 계획하기") { onOpenTomorrow() }
                    .buttonStyle(.borderedProminent)
            }

            Button {
                Haptic.tick()
                // 먼저 화면에서 결을 실어 내리고, 오늘 닫았다는 것은 그다음에 적는다.
                withAnimation(Motion.disclose) { shownKey = nil }
                dismissed = key
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.squish)
            .help("오늘은 그만 보기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint(kind).opacity(0.1), in: .soft(Corner.panel))
        .overlay(RoundedRectangle.soft(Corner.panel)
            .strokeBorder(tint(kind).opacity(0.25), lineWidth: 1))
    }

    // MARK: 말

    private func symbol(_ kind: Kind) -> String {
        switch kind {
        case .morning: "sunrise.fill"
        case .tomorrowReady: "moon.stars.fill"
        case .tomorrowEmpty: "moon.zzz.fill"
        }
    }

    private func tint(_ kind: Kind) -> Color {
        switch kind {
        case .morning: .orange
        case .tomorrowReady: .accentColor
        case .tomorrowEmpty: .indigo
        }
    }

    private func title(_ kind: Kind) -> LocalizedStringKey {
        switch kind {
        case .morning: "오늘의 첫 걸음"
        case .tomorrowReady: "내일은 정해져 있습니다"
        case .tomorrowEmpty: "내일이 아직 비어 있습니다"
        }
    }

    private func headline(_ kind: Kind) -> String {
        switch kind {
        case .morning(let block), .tomorrowReady(let block):
            return block.title
        case .tomorrowEmpty:
            return String(localized: "지금 정해 두면 아침에 고를 일이 없습니다")
        }
    }

    private func note(_ kind: Kind) -> String? {
        switch kind {
        case .morning(let block):
            let when = block.startHour >= 0 ? formatHour(block.startHour) : block.timeBand.shortLabel
            return "\(when) · \(formatDuration(block.durationHours))"
        case .tomorrowReady(let block):
            let when = block.startHour >= 0 ? formatHour(block.startHour) : block.timeBand.shortLabel
            let rest = tomorrowBlocks.count - 1
            let first = String(localized: "첫 걸음 \(when)")
            return rest > 0 ? "\(first) · \(String(localized: "그 밖에 \(rest)개"))" : first
        case .tomorrowEmpty:
            return nil
        }
    }
}
