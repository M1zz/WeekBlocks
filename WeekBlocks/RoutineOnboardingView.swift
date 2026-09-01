import SwiftUI
import SwiftData

/// 처음 켠 사람에게 **고정 루틴을 함께 세우자고 묻는 자리.**
///
/// 예전에는 수면·식사·운동을 묻지도 않고 깔아 두었다. 그런데 회사를 안 다니는 사람도,
/// 운동을 안 하는 사람도 있다. 내가 만들지 않은 일정이 이미 놓여 있으면
/// 그것부터 지우는 일로 앱을 시작하게 된다.
///
/// 그래서 **아무것도 미리 고르지 않는다.** 아래 것들은 예시일 뿐이고,
/// 해당하는 것만 고르거나 직접 적으면 된다.
struct RoutineOnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// '직접 적기'를 골랐다 — 부르는 쪽이 루틴 편집 시트를 연다.
    var onWriteMyOwn: () -> Void = { }

    /// 고를 수 있는 예시. 값은 흔한 모양일 뿐이고, 만든 뒤 언제든 고친다.
    private struct Suggestion: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let color: String
        let detail: String
        let make: () -> Routine
    }

    @State private var picked: Set<UUID> = []

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("고정으로 시간을 쓰는 일부터 세웁니다")
                    .font(.title2.weight(.semibold))
                Text("한 주는 168시간입니다. 빼놓을 수 없는 시간을 먼저 깔면, 남는 자리가 실제로 쓸 수 있는 시간이 됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("해당하는 것만 고르세요")
                    .font(.subheadline.weight(.medium))
                Text("예시일 뿐입니다. 안 골라도 되고, 만든 뒤에 시각·요일을 고칠 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(suggestions) { s in
                        suggestionRow(s)
                    }
                }
                .padding(.top, 2)
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button("나중에") { finish() }
                    .buttonStyle(.borderless)

                Spacer()

                Button("직접 적기") {
                    finish()
                    onWriteMyOwn()
                }
                .buttonStyle(.bordered)

                Button("고른 것으로 시작하기") { createPicked() }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 480)
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

    private func createPicked() {
        for s in suggestions where picked.contains(s.id) {
            context.insert(s.make())
        }
        try? context.save()
        finish()
    }

    /// 다시 묻지 않는다. 안 고르고 닫았어도 마찬가지다 —
    /// 루틴이 없으면 '고정 루틴' 자리가 계속 도와주겠다고 말하고 있다.
    private func finish() {
        UserDefaults.standard.set(true, forKey: RoutineOnboarding.shownKey)
        dismiss()
    }
}

enum RoutineOnboarding {
    static let shownKey = "didShowRoutineOnboarding"

    static var wasShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }
}
