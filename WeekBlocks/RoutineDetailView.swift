import SwiftUI
import SwiftData

/// 자 위의 **한 칸**(그날 그 끼니·그날 그 루틴)을 눌러 열었을 때만 생기는 손짓.
///
/// 이 창은 루틴 **정의**를 다룬다 — 모든 날의 식사다. 그런데 사람은 월요일 13시 식사 한 칸을
/// 눌러 들어왔고, 그 한 칸을 지우려는 참이다. 계획 블록은 눌러 연 창에 삭제 단추가 있는데
/// 끼니는 우클릭까지 가야 했다. 어느 칸에서 왔는지는 부른 쪽만 알기에 그쪽이 쥐여 준다.
struct RoutineDayAction {
    /// "이 끼니 삭제 (오늘만)" 처럼 — 우클릭 메뉴와 같은 글자 (→ TimeSegment.deleteLabel).
    let label: String
    let perform: () -> Void
}

struct RoutineDetailView: View {
    @Bindable var routine: Routine
    /// 자 위의 한 칸에서 열었으면 그 칸을 지우는 손짓. 루틴 목록에서 열었으면 nil.
    var dayAction: RoutineDayAction? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditor = false
    @State private var tab: Tab = .info

    private enum Tab: Hashable, CaseIterable {
        case info, execution, premortem
        var title: LocalizedStringKey {
            switch self {
            case .info: "정보"
            case .execution: "실행 전략"
            case .premortem: "프리모템"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // ⚠️ `TabView`를 쓰지 않는다. 시트 안의 TabView 는 탭 머리를 가운데 작은 칸 하나에
            //    몰아 그려서 "정보·실행 전략·프리모템" 세 글자가 한 자리에 겹쳐 보였다.
            //    고르는 줄(세그먼트)과 몸통을 직접 나눠 그리면 폭을 제대로 받는다.
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 10)

            Group {
                switch tab {
                case .info: infoTab
                case .execution: executionTab
                case .premortem: premortemTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 색을 고르면 머리의 동그라미·바탕까지 함께 물든다. 한 번에 갈리지 않게.
        .animation(Motion.disclose, value: routine.colorName)
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
                    .font(.system(size: 20))
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
            // 이 화면은 정보·실행 전략만 다룬다. 이름·요일·시각을 바꾸려면 편집기가 필요한데
            // 여기서 갈 길이 없으면 막다른 길이 된다.
            // 그날 그 칸만 지운다 — 루틴 정의와 다른 날은 그대로. 지우면 창도 닫는다
            // (지운 것의 상세를 계속 보고 있을 까닭이 없다).
            if let dayAction {
                Button(role: .destructive) {
                    dayAction.perform()
                    dismiss()
                } label: {
                    Label(dayAction.label, systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
            Button("수정") { showingEditor = true }
                .buttonStyle(.borderless)
            Button("닫기") { dismiss() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(routine.displayColor.opacity(0.06))
        .sheet(isPresented: $showingEditor) {
            RoutineEditorView(existing: routine)
                .frame(minWidth: 520, minHeight: 480)
        }
    }

    // MARK: Tab 1 — 정보

    private var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard(
                    icon: "clock",
                    title: "시간",
                    value: routine.kind == .fixed
                        ? String(localized: "\(String(format: "%.1f", routine.durationHours))h/일  ·  \(String(format: "%.1f", routine.totalWeeklyHours))h/주")
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

    private func infoCard(icon: String, title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
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
        .background(color.opacity(0.08), in: .soft(Corner.panel))
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
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle.soft(Corner.card))
                    .overlay(RoundedRectangle.soft(Corner.card).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
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
                        .background(Color.red.opacity(0.07), in: .soft(Corner.card))
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
                        .background(Color.green.opacity(0.07), in: .soft(Corner.card))
                }
            }
            .padding(24)
        }
    }

    // MARK: Helpers

    private func sectionHeader(icon: String, color: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
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
        .background(color.opacity(0.08), in: .soft(Corner.panel))
    }
}

// MARK: Color Picker

private struct ColorPicker: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(routineColorOptions, id: \.name) { option in
                Button {
                    withAnimation(Motion.hover) { selected = option.name }
                } label: {
                    ZStack {
                        Circle()
                            .fill(option.color)
                            .frame(width: 26, height: 26)
                            .scaleEffect(selected == option.name ? 1.12 : 1)
                        if selected == option.name {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 20, height: 20)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.squish)
                .help(option.name)
            }
        }
    }
}
