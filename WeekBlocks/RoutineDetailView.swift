import SwiftUI
import SwiftData

struct RoutineDetailView: View {
    @Bindable var routine: Routine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                infoTab
                    .tabItem { Label("정보", systemImage: "info.circle") }
                executionTab
                    .tabItem { Label("실행 전략", systemImage: "list.bullet.clipboard") }
                premortemTab
                    .tabItem { Label("프리모템", systemImage: "exclamationmark.triangle") }
            }
        }
        .onDisappear { try? context.save() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(routine.displayColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: routine.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(routine.displayColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.title3.weight(.semibold))
                Text(routine.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("닫기") { dismiss() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(routine.displayColor.opacity(0.06))
    }

    // MARK: Tab 1 — 정보

    private var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard(
                    icon: "clock",
                    title: "시간",
                    value: routine.kind == .fixed
                        ? String(format: "%.1fh/일  ·  %.1fh/주", routine.durationHours, routine.totalWeeklyHours)
                        : routine.scheduleDescription,
                    color: routine.displayColor
                )
                if routine.kind == .fixed {
                    infoCard(icon: "calendar", title: "요일",
                             value: routine.scheduleDescription, color: routine.displayColor)
                }

                Divider()

                Text("색상")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                ColorPicker(selected: $routine.colorName)
            }
            .padding(24)
        }
    }

    private func infoCard(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Tab 2 — 실행 전략

    private var executionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    icon: "lightbulb.fill",
                    color: .yellow,
                    title: "어떻게 잘 할 것인가",
                    subtitle: "이 루틴을 더 잘 수행하기 위한 나만의 전략, 팁, 준비사항을 적어두세요."
                )
                TextEditor(text: $routine.executionNotes)
                    .font(.body)
                    .frame(minHeight: 260)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            }
            .padding(24)
        }
    }

    // MARK: Tab 3 — 프리모템

    private var premortemTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader(
                    icon: "brain.head.profile",
                    color: .orange,
                    title: "프리모템 (Pre-mortem)",
                    subtitle: "이 루틴이 이미 실패했다고 가정하세요. 원인을 미리 생각하면 실제 실패를 막을 수 있습니다."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("실패 시나리오", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("이 루틴을 못 지키게 되는 이유는 무엇인가?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $routine.premortemFailScenario)
                        .font(.body)
                        .frame(minHeight: 110)
                        .padding(10)
                        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("대응 전략", systemImage: "shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("그 실패를 어떻게 막거나 빠르게 회복할 수 있는가?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $routine.premortemPrevention)
                        .font(.body)
                        .frame(minHeight: 110)
                        .padding(10)
                        .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(24)
        }
    }

    // MARK: Helpers

    private func sectionHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Color Picker

private struct ColorPicker: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(routineColorOptions, id: \.name) { option in
                Button {
                    selected = option.name
                } label: {
                    ZStack {
                        Circle()
                            .fill(option.color)
                            .frame(width: 26, height: 26)
                        if selected == option.name {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(option.name)
            }
        }
    }
}
