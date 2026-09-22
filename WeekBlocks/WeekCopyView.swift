//
//  WeekCopyView.swift
//  WeekBlocks
//
//  **잘 굴러간 주를 이번 주에 한 번에 깐다** — Pro.
//
//  한 주를 짜는 일은 대개 지난 주를 다시 짜는 일이다. 같은 수업, 같은 운동, 같은 마감 준비.
//  블록을 하나씩 다시 끌어다 놓는 대신, 고른 주의 계획을 같은 요일·같은 시각으로 옮겨 적는다.
//
//  따로 '템플릿'을 저장하지 않는다. 지나간 주가 곧 템플릿이다 — 새 모델을 만들면
//  CloudKit 스키마가 늘고 아이폰 앱과도 맞춰야 하는데, 이미 있는 주를 고르는 것으로 충분하다.
//
//  ⚠️ **덮어쓰지 않고 더한다.** 이번 주에 이미 세운 블록은 그대로 둔다. 같은 요일·같은 제목·
//     같은 시각의 블록이 이미 있으면 그것만 건너뛴다 — 두 번 눌러도 두 벌이 되지 않는다.
//
//  ⚠️ 옮기는 것은 **계획**뿐이다. 회고 표시·한 줄 회고는 그 주의 기록이라 따라오지 않고,
//     캘린더에서 온 회의는 캘린더 가져오기가 제 주에 맞춰 다시 가져오므로 뺀다.
//

import SwiftUI
import SwiftData

struct WeekCopyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 깔 주 (보고 있는 주).
    let targetWeek: Date

    @Query private var allBlocksRaw: [PlanBlock]
    private var allBlocks: [PlanBlock] { allBlocksRaw.filter(TodoSharing.isVisible) }

    @State private var purchases = PurchaseManager.shared
    @State private var showingPaywall = false
    @State private var selectedWeek: Date?

    private let cal = Calendar(identifier: .iso8601)

    /// 옮길 수 있는 블록 (캘린더에서 온 것 제외).
    private func plan(of week: Date) -> [PlanBlock] {
        allBlocks
            .filter { $0.calendarEventID == nil && cal.isDate($0.weekStartDate, inSameDayAs: week) }
            .sorted { ($0.day.rawValue, $0.sortHour) < ($1.day.rawValue, $1.sortHour) }
    }

    /// 고를 수 있는 주들 — 계획이 있는 주, 깔 주 자신은 빼고, 가까운 주가 위로. 최근 12개.
    private var sourceWeeks: [Date] {
        var seen: [Date] = []
        for b in allBlocks where b.calendarEventID == nil {
            let start = cal.startOfDay(for: b.weekStartDate)
            if cal.isDate(start, inSameDayAs: targetWeek) { continue }
            if !seen.contains(where: { cal.isDate($0, inSameDayAs: start) }) { seen.append(start) }
        }
        return Array(seen.sorted(by: >).prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("다른 주 계획 가져오기")
                    .font(.title3.weight(.medium))
                Text("\(rangeString(targetWeek))에 고른 주의 계획을 같은 요일·같은 시각으로 깝니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            if sourceWeeks.isEmpty {
                ContentUnavailableView(
                    "가져올 주가 없습니다",
                    systemImage: "square.on.square",
                    description: Text("계획을 세운 주가 생기면 여기에서 고를 수 있습니다.")
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    weekList
                        .frame(width: 250)
                    Divider()
                    preview
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            footer
                .padding(20)
        }
        .onAppear {
            if selectedWeek == nil { selectedWeek = sourceWeeks.first }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(reason: WeekBlocksSpec.Gate.weekCopy)
        }
    }

    // MARK: 주 고르기

    private var weekList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(sourceWeeks, id: \.self) { week in
                    let blocks = plan(of: week)
                    let selected = selectedWeek.map { cal.isDate($0, inSameDayAs: week) } ?? false
                    Button {
                        withAnimation(Motion.row) { selectedWeek = week }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rangeString(week))
                                .font(.callout.weight(.semibold))
                            HStack(spacing: 6) {
                                Text("블록 \(blocks.count)개 · \(formatDuration(blocks.reduce(0) { $0 + $1.durationHours }))")
                                if let rate = ReflectionTrends.rate(blocks) {
                                    Text("달성 \(rate.formatted(.percent.precision(.fractionLength(0))))")
                                        .foregroundStyle(.green)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: .soft(Corner.chip))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.squish)
                }
            }
            .padding(10)
        }
    }

    // MARK: 미리보기

    @ViewBuilder
    private var preview: some View {
        if let week = selectedWeek {
            let blocks = plan(of: week)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(DayOfWeek.allCases) { day in
                        let mine = blocks.filter { $0.day == day }
                        if !mine.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.longLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(mine) { block in
                                    HStack(spacing: 8) {
                                        Text(block.startHour >= 0 ? formatHour(block.startHour) : block.timeBand.shortLabel)
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .leading)
                                        Text(block.title)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(formatDuration(block.durationHours))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .id(week)
            .transition(.opacity)
        }
    }

    // MARK: 아래 줄

    private var footer: some View {
        let targetCount = plan(of: targetWeek).count
        return HStack(spacing: 10) {
            if !purchases.isPro {
                Label("Pro 기능입니다", systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if targetCount > 0 {
                Text("이번 주에 이미 있는 블록 \(targetCount)개는 그대로 두고 더합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("취소") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if purchases.isPro {
                Button("이 주에 깔기") { copy() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedWeek == nil)
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    Label("Pro로 가져오기", systemImage: "sparkles")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func copy() {
        guard purchases.isPro, let source = selectedWeek else { return }
        let existing = plan(of: targetWeek)
        for b in plan(of: source) {
            let duplicate = existing.contains {
                $0.day == b.day && $0.title == b.title && $0.startHour == b.startHour
                    && $0.timeBandRaw == b.timeBandRaw
            }
            if duplicate { continue }
            // init이 공유 표시(TodoSharing.stamp)를 찍는다. 회고는 옮기지 않는다.
            let copy = PlanBlock(
                day: b.day,
                timeBand: b.timeBand,
                durationHours: b.durationHours,
                title: b.title,
                successCriteria: b.successCriteria,
                deliverable: b.deliverable,
                weekStartDate: targetWeek,
                concreteVerified: b.concreteVerified,
                withinRoutine: b.withinRoutine,
                startHour: b.startHour
            )
            // 아이콘도 따라간다 — 안 적으면 새로 만든 시각에서 다른 아이콘을 뽑아, 같은 일이 주마다 달라 보인다.
            copy.iconName = b.symbol
            context.insert(copy)
        }
        Haptic.snap()
        withAnimation(Motion.squish) { try? context.save() }
        dismiss()
    }

    private func rangeString(_ start: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}
