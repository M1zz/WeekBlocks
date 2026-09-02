import SwiftUI
import SwiftData

/// 처음 켠 사람에게 **세 걸음으로 앱을 건네는 자리.**
///
/// 예전에는 고정 루틴 한 걸음만 물었다. 그런데 루틴을 세우고 나면 화면에는
/// 빈 요일 칸 일곱 개가 남고, 아무도 "그다음 무엇을 하면 되는지" 말해 주지 않았다.
/// 이 앱의 중심 동작인 **끌어다 놓기**도 어디에도 적혀 있지 않아, 알아서 해 보다
/// 발견하는 수밖에 없었다.
///
/// 그래서 세 걸음이다.
///   1. 왜 — 한 주는 168시간이고, 고정을 먼저 깔아야 남는 자리가 보인다.
///   2. 무엇 — 빼놓을 수 없는 시간을 고른다(예시일 뿐, 아무것도 미리 고르지 않는다).
///   3. 어떻게 — 적고, 끌어다 놓고, 자를 보고, 남은 시간을 본다.
///
/// 여전히 **아무것도 미리 깔지 않는다.** 회사를 안 다니는 사람도, 운동을 안 하는
/// 사람도 있다. 내가 만들지 않은 일정이 이미 놓여 있으면 그것부터 지우는 일로
/// 앱을 시작하게 된다.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// '직접 적기'를 골랐다 — 부르는 쪽이 루틴 편집 시트를 연다.
    var onWriteMyOwn: () -> Void = { }
    /// 어느 걸음에서 열 것인가. 루틴이 비어 있어 다시 부른 자리에서는 바로 2로 온다.
    var startPage: Int = 0

    @State private var page = 0
    @State private var picked: Set<UUID> = []

    private static let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: whyPage
                case 1: routinePage
                default: howPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 540)
        .onAppear { page = startPage }
    }

    // MARK: 1. 왜 — 한 주는 168시간

    private var whyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("한 주는 168시간입니다")
                    .font(.title.weight(.semibold))
                Text("시간이 없는 게 아니라, 어디에 갔는지 모르는 것에 가깝습니다.\n빼놓을 수 없는 시간을 먼저 깔아 두면, 남는 자리가 실제로 쓸 수 있는 시간이 됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 말로만 하면 와닿지 않는다. 168칸을 한 번 보여 준다.
            weekBar

            VStack(alignment: .leading, spacing: 10) {
                bullet("lock", "고정 루틴", "잠·끼니·일처럼 뺄 수 없는 시간. 여기부터 세웁니다.")
                bullet("square.stack.3d.up", "계획 블록", "남는 자리에 무엇을 넣을지 요일마다 정합니다.")
                bullet("chart.bar", "남은 시간", "고정을 뺀 나머지가 이번 주에 쓸 수 있는 전부입니다.")
            }
        }
        .padding(28)
    }

    /// 168시간을 한 줄로. 색이 아니라 **비율**을 보여 주는 그림이다.
    private var weekBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    band(width: geo.size.width * (56.0 / 168), color: .indigo, label: "잠 56h")
                    band(width: geo.size.width * (45.0 / 168), color: .blue, label: "일 45h")
                    band(width: geo.size.width * (67.0 / 168), color: .secondary.opacity(0.25),
                         label: "남는 자리 67h", dark: false)
                }
            }
            .frame(height: 34)

            Text("예시입니다. 사람마다 다르고, 그 차이를 보는 것이 이 앱이 하는 일입니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func band(width: CGFloat, color: Color, label: String, dark: Bool = true) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color.opacity(dark ? 0.85 : 1))
            .frame(width: max(0, width))
            .overlay(
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(dark ? .white : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            )
    }

    private func bullet(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 2. 무엇 — 고정 루틴 고르기

    /// 고를 수 있는 예시. 값은 흔한 모양일 뿐이고, 만든 뒤 언제든 고친다.
    private struct Suggestion: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let color: String
        let detail: String
        let make: () -> Routine
    }

    private let suggestions: [Suggestion] = [
        Suggestion(name: "잠", icon: "moon.fill", color: "indigo",
                   detail: "매일 23:00부터 8시간") {
            Routine(name: "잠", iconName: "moon.fill", kind: .fixed, colorName: "indigo",
                    dayMask: 0b1111111, startHour: 23, durationHours: 8, sortIndex: 0)
        },
        Suggestion(name: "끼니", icon: "fork.knife", color: "green",
                   detail: "주 17.5시간 · 하루 세 번 (시각은 유연하게)") {
            Routine(name: "끼니", iconName: "fork.knife", kind: .quota, colorName: "green",
                    weeklyHours: 17.5, sessionsPerDay: 3, sortIndex: 1)
        },
        Suggestion(name: "일 · 학교", icon: "calendar", color: "blue",
                   detail: "평일 09:00부터 9시간") {
            Routine(name: "일", iconName: "calendar", kind: .fixed, colorName: "blue",
                    dayMask: 0b0011111, startHour: 9, durationHours: 9, sortIndex: 2)
        },
        Suggestion(name: "운동", icon: "figure.run", color: "orange",
                   detail: "월·수·금 07:30부터 1시간") {
            Routine(name: "운동", iconName: "figure.run", kind: .fixed, colorName: "orange",
                    dayMask: 0b0010101, startHour: 7.5, durationHours: 1, sortIndex: 3)
        },
    ]

    private var routinePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("빼놓을 수 없는 시간부터 세웁니다")
                    .font(.title2.weight(.semibold))
                Text("해당하는 것만 고르세요. 예시일 뿐이고, 안 골라도 됩니다.\n만든 뒤에 시각·요일·이름을 모두 고칠 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                ForEach(suggestions) { s in
                    suggestionRow(s)
                }
            }

            Button {
                createPicked()
                onWriteMyOwn()
            } label: {
                Label("여기 없는 것을 직접 적기", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(28)
    }

    private func suggestionRow(_ s: Suggestion) -> some View {
        let isOn = picked.contains(s.id)
        return Button {
            if isOn { picked.remove(s.id) } else { picked.insert(s.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)

                Image(systemName: s.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(paletteColor(s.color))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name)
                        .font(.system(size: 14, weight: .medium))
                    Text(s.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isOn ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: 3. 어떻게 — 한 주를 짜는 순서

    private var howPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("한 주는 이렇게 짭니다")
                    .font(.title2.weight(.semibold))
                Text("네 걸음입니다. 지금 다 외우지 않아도 됩니다 — 화면이 그때그때 다음 걸음을 알려줍니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                step(1, "square.and.pencil", "할 일을 적습니다",
                     "화면 아래 '할 일'에 한 줄씩. 아직 언제 할지는 정하지 않아도 됩니다.")
                step(2, "hand.draw", "요일 칸으로 끌어다 놓습니다",
                     "할 일 카드를 잡아 요일 칸에 떨어뜨리면 그 요일의 계획이 됩니다. 올려 둔 것도 다른 요일로 다시 끌 수 있습니다.")
                step(3, "chart.bar.doc.horizontal", "'시간축으로 보기'에서 자리를 봅니다",
                     "하루 24시간 자 위에서 좌우로 끌면 시각이, 위아래로 끌면 요일이 바뀝니다.")
                step(4, "timer", "지금 하는 일에 남은 시간을 봅니다",
                     "일정에 적힌 시각대로 저절로 셉니다. 날짜 줄 오른쪽과 타이머 창(⇧⌘R)에서 보입니다.")
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("주말에는 '회고'에서 세운 대로 살았는지 되돌아봅니다. 다음 주를 짜는 재료가 됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(28)
    }

    private func step(_ number: Int, _ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: 아래 줄

    private var footer: some View {
        HStack(spacing: 10) {
            Button("건너뛰기") { finish() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

            Spacer()

            // 지금 몇 걸음째인지. 세 개짜리라 점으로 충분하다.
            HStack(spacing: 5) {
                ForEach(0...Self.lastPage, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if page > 0 {
                Button("이전") { withAnimation(.snappy(duration: 0.2)) { page -= 1 } }
                    .buttonStyle(.bordered)
            }

            Button(nextTitle) {
                if page == 1 { createPicked() }        // 고른 것은 넘어갈 때 만든다
                if page == Self.lastPage { finish(); return }
                withAnimation(.snappy(duration: 0.2)) { page += 1 }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var nextTitle: String {
        switch page {
        case 0: "시작하기"
        case 1: picked.isEmpty ? "건너뛰고 다음" : "\(picked.count)개 만들고 다음"
        default: "다 봤습니다"
        }
    }

    // MARK: 만들기·끝내기

    private func createPicked() {
        guard !picked.isEmpty else { return }
        for s in suggestions where picked.contains(s.id) {
            context.insert(s.make())
        }
        try? context.save()
        picked.removeAll()   // 뒤로 갔다 다시 와도 두 번 만들지 않는다
    }

    /// 다시 묻지 않는다. 안 고르고 닫았어도 마찬가지다 —
    /// 루틴이 없으면 '고정 루틴' 자리와 '다음 한 걸음'이 계속 도와주겠다고 말하고 있다.
    private func finish() {
        UserDefaults.standard.set(true, forKey: RoutineOnboarding.shownKey)
        dismiss()
    }
}

enum RoutineOnboarding {
    static let shownKey = "didShowRoutineOnboarding"

    static var wasShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    /// 설정에서 '처음 안내 다시 보기'를 눌렀을 때. 다음에 열 때 처음부터 다시 흐른다.
    static func reset() {
        UserDefaults.standard.set(false, forKey: shownKey)
    }
}
