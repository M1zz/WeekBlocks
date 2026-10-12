//
//  RainbowLane.swift
//  무지개 공방
//
//  **아이폰 '욕망의 무지개'의 일정을 맥에서도 본다 · 고친다 · 더한다.** (→ RainbowEvent.swift)
//
//  무지개 일정은 '이 기간 동안 하루 몇 시간씩'이다. 시각이 없으니 시간 칸에는 안 서고, 종일 줄처럼
//  요일 칸 위를 가로지르는 막대로 선다. 아이폰 무지개와 같은 뜻으로 칠한다 —
//  기간 안이면 옅게, 실제로 하는 날이면 진하게.
//

import SwiftUI
import SwiftData

// MARK: - 주간: 요일 칸 위 막대

struct RainbowLane: View {
    let events: [RainbowEvent]
    /// 보이는 요일들의 0시 (왼쪽부터).
    let dates: [Date]
    let spacing: CGFloat
    let onOpen: (RainbowEvent) -> Void

    private static let rowHeight: CGFloat = 26

    /// 이 주에서 기간 안인 칸들의 처음과 끝 (보이는 칸 번호). 하나도 없으면 nil.
    private func range(_ e: RainbowEvent) -> ClosedRange<Int>? {
        let hits = dates.indices.filter { e.spans(dates[$0]) }
        guard let a = hits.first, let b = hits.last else { return nil }
        return a...b
    }

    var body: some View {
        let placed = events.compactMap { e in range(e).map { (event: e, range: $0) } }
            .sorted { ($0.range.lowerBound, $0.event.startDate) < ($1.range.lowerBound, $1.event.startDate) }
        // 겹치지 않게 줄을 나눈다 — 먼저 시작한 것부터 비어 있는 첫 줄에.
        var rowEnds: [Int] = []
        var rows: [String: Int] = [:]
        for p in placed {
            if let r = rowEnds.firstIndex(where: { $0 < p.range.lowerBound }) {
                rowEnds[r] = p.range.upperBound
                rows[p.event.uuid] = r
            } else {
                rowEnds.append(p.range.upperBound)
                rows[p.event.uuid] = rowEnds.count - 1
            }
        }

        return GeometryReader { geo in
            let n = CGFloat(max(1, dates.count))
            let col = (geo.size.width - spacing * (n - 1)) / n
            ZStack(alignment: .topLeading) {
                ForEach(placed, id: \.event.uuid) { p in
                    let count = p.range.count
                    let width = CGFloat(count) * col + CGFloat(count - 1) * spacing
                    RainbowBar(event: p.event,
                               days: Array(dates[p.range]),
                               columnWidth: col,
                               spacing: spacing) { onOpen(p.event) }
                        .frame(width: width, height: Self.rowHeight - 4)
                        .offset(x: CGFloat(p.range.lowerBound) * (col + spacing),
                                y: CGFloat(rows[p.event.uuid] ?? 0) * Self.rowHeight)
                }
            }
        }
        .frame(height: CGFloat(rowEnds.count) * Self.rowHeight)
        .animation(Motion.squish, value: placed.map(\.event.uuid))
    }
}

/// 막대 하나. 칸마다 옅게(기간 안) · 진하게(하는 날) 칠하고, 그 위에 이름과 하루 시간.
struct RainbowBar: View {
    let event: RainbowEvent
    let days: [Date]
    let columnWidth: CGFloat
    let spacing: CGFloat
    let onOpen: () -> Void

    @State private var hovering = false

    private var color: Color { Color(hex: event.colorHex) ?? .accentColor }

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(days, id: \.self) { day in
                        Capsule(style: .continuous)
                            .fill(color.opacity(event.occurs(on: day) ? (hovering ? 0.5 : 0.4) : 0.12))
                            .frame(width: columnWidth)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "rainbow")
                        .font(.system(size: 12, weight: .semibold))
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(RainbowEventFormat.hours(event.hoursPerDay))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .opacity(0.75)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "무지개 일정 — 진한 칸이 하는 날입니다. 눌러서 고칩니다"))
    }
}

// MARK: - 시간 자 보기: 이 주의 무지개 일정 한 줄

/// 시간 자 보기에는 요일 칸이 세로로 선다 — 가로지르는 막대를 둘 자리가 없다.
/// 이 주에 걸친 무지개 일정을 칩 한 줄로 세우고, 칩마다 이 주에 하는 요일을 적는다.
struct RainbowDayList: View {
    let events: [RainbowEvent]
    let days: [(day: DayOfWeek, date: Date)]
    let onOpen: (RainbowEvent) -> Void

    var body: some View {
        let visible = events.filter { e in days.contains { e.spans($0.date) } }
        if !visible.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visible, id: \.uuid) { e in
                        let on = days.filter { e.occurs(on: $0.date) }.map { $0.day.shortLabel }
                        Button { onOpen(e) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "rainbow").font(.system(size: 12, weight: .semibold))
                                Text(e.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(RainbowEventFormat.hours(e.hoursPerDay))
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit().opacity(0.75)
                                if !on.isEmpty {
                                    Text(on.joined(separator: " "))
                                        .font(.system(size: 12, weight: .medium)).opacity(0.75)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background((Color(hex: e.colorHex) ?? .accentColor).opacity(0.18), in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

enum RainbowEventFormat {
    /// "하루 2시간" · "하루 30분" · "하루 1시간 30분".
    static func hours(_ h: Double) -> String {
        let minutes = Int((max(0, h) * 60).rounded())
        let hh = minutes / 60, mm = minutes % 60
        switch (hh, mm) {
        case (0, _): return String(localized: "하루 \(mm)분")
        case (_, 0): return String(localized: "하루 \(hh)시간")
        default: return String(localized: "하루 \(hh)시간 \(mm)분")
        }
    }
}

// MARK: - 고치기 · 더하기

/// 무지개 일정을 고치거나 새로 적는 창. 아이폰 '일정 추가'와 같은 칸들이다.
///
/// 5주 패턴은 아이폰에서만 고친다 — 그 일정이면 요일 고르기 대신 안내가 선다.
/// 저장하면 사본이 iCloud로 올라가고, 아이폰 다리(RainbowBridge)가 원본에 옮긴다.
struct RainbowEventEditor: View {
    /// nil이면 새로 적는다.
    let event: RainbowEvent?
    var defaultStart: Date = Date()
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var isInfinite = false
    @State private var hours: Double = 2
    @State private var weekdays: Set<Int> = []   // 비어 있으면 매일
    @State private var colorHex = Rainbow.spectrum.first?.hex ?? "#FF3B30"
    @State private var importance = "medium"
    @State private var confirmingDelete = false
    /// 같은 일정이 이미 있다 — 어느 기기에서 만든 것인지.
    @State private var twinOrigin: String?

    private var hasPattern: Bool { event?.weeklyPattern != nil }

    /// 월요일부터 (Calendar weekday: 1=일 … 7=토).
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event == nil ? "무지개 일정 추가" : "무지개 일정 고치기")
                .font(.title2.bold())

            Form {
                TextField("제목", text: $title)
                DatePicker("시작", selection: $start, displayedComponents: .date)
                Toggle("끝없이 반복", isOn: $isInfinite)
                if !isInfinite {
                    DatePicker("끝", selection: $end, in: start..., displayedComponents: .date)
                }
                LabeledContent("하루에") {
                    HStack {
                        Text(RainbowEventFormat.hours(hours)).monospacedDigit()
                        Stepper("", value: $hours, in: 0.25...16, step: 0.25).labelsHidden()
                    }
                }
                LabeledContent("요일") {
                    if hasPattern {
                        Text("5주 패턴 — 아이폰에서 고칩니다").foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Self.weekdayOrder, id: \.self) { d in
                                let on = weekdays.isEmpty || weekdays.contains(d)
                                Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                                    toggleWeekday(d)
                                }
                                .buttonStyle(.bordered)
                                .tint(on ? .accentColor : .secondary)
                                .opacity(on ? 1 : 0.5)
                            }
                        }
                    }
                }
                Picker("중요도", selection: $importance) {
                    Text("상").tag("high")
                    Text("중").tag("medium")
                    Text("하").tag("low")
                }
                .pickerStyle(.segmented)
                LabeledContent("색") {
                    HStack(spacing: 6) {
                        ForEach(Rainbow.spectrum, id: \.hex) { swatch in
                            Circle()
                                .fill(Color(hex: swatch.hex) ?? .accentColor)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.primary.opacity(colorHex.uppercased() == swatch.hex.uppercased() ? 0.8 : 0), lineWidth: 2))
                                .onTapGesture { colorHex = swatch.hex }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if event != nil {
                    Button("지우기", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("취소") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear(perform: load)
        // ⚠️ 막는다, 묻지 않는다. 제목·날짜·색이 같은 두 일정은 아이폰 다리(RainbowBridge)가
        //    기기 사이에서 하나로 합친다 — '그래도 만들기'를 두면 만든 것이 곧 사라진다.
        .alert("같은 일정이 이미 있어요", isPresented: Binding(get: { twinOrigin != nil },
                                                          set: { if !$0 { twinOrigin = nil } })) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("\(twinOrigin ?? "") 만든 일정과 모든 내용이 같습니다. 똑같은 일정은 기기 사이에서 하나로 합쳐지니, 제목이나 날짜를 바꿔 주세요.")
        }
        .confirmationDialog("이 무지개 일정을 지울까요?", isPresented: $confirmingDelete) {
            Button("지우기", role: .destructive) { remove() }
        } message: {
            Text("아이폰에서도 사라집니다. 아이폰은 지우기 전에 백업을 남깁니다.")
        }
    }

    private func toggleWeekday(_ d: Int) {
        // 비어 있음 = 매일. 하나를 끄면 나머지 여섯이 켜진 상태에서 시작한다.
        var set = weekdays.isEmpty ? Set(1...7) : weekdays
        if set.contains(d) { set.remove(d) } else { set.insert(d) }
        weekdays = (set.count == 7 || set.isEmpty) ? [] : set
    }

    private func load() {
        guard let event else {
            start = Calendar.current.startOfDay(for: defaultStart)
            end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            return
        }
        title = event.title
        // 다른 시간대 기기가 적은 날짜도 이 기기의 그날로 읽는다 (→ RainbowEvent.day).
        start = RainbowEvent.day(event.startDate)
        end = RainbowEvent.day(event.endDate)
        isInfinite = event.isInfinite
        hours = event.hoursPerDay
        weekdays = Set(event.selectedWeekdays ?? [])
        colorHex = event.colorHex
        importance = event.importanceRaw
    }

    private func save() {
        if let twin = twin() {
            twinOrigin = twin.originInstallID == TodoSharing.installID
                ? String(localized: "이 맥에서") : String(localized: "다른 기기에서")
            return
        }
        let target: RainbowEvent
        if let event {
            target = event
        } else {
            target = RainbowEvent()
            target.originInstallID = TodoSharing.installID
            target.createdAt = Date()
            context.insert(target)
        }
        let cal = Calendar.current
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.startDate = cal.startOfDay(for: start)
        target.endDate = cal.startOfDay(for: max(end, start))
        target.isInfinite = isInfinite
        target.hoursPerDay = hours
        if !hasPattern {
            target.selectedWeekdays = weekdays.isEmpty ? nil : weekdays.sorted()
        }
        target.colorHex = colorHex
        target.importanceRaw = importance
        target.updatedAt = Date()
        try? context.save()
        onClose()
    }

    /// 지우지 않은 다른 일정 중 **모든 칸이 같은 것** — 아이폰 다리가 하나로 합치는 기준과 같다
    /// (→ RainbowBridge.fingerprint). 하루 시간 · 요일 · 중요도 하나라도 다르면 합쳐지지 않으니 막지 않는다.
    private func twin() -> RainbowEvent? {
        let cal = Calendar.current
        let name = title.trimmingCharacters(in: .whitespaces)
        let first = cal.startOfDay(for: start), last = cal.startOfDay(for: max(end, start))
        let days: [Int]? = weekdays.isEmpty ? nil : weekdays.sorted()
        let all = (try? context.fetch(FetchDescriptor<RainbowEvent>())) ?? []
        return all.first { other in
            guard other !== event, other.deletedAt == nil,
                  other.title == name,
                  RainbowEvent.day(other.startDate) == first,
                  other.isInfinite == isInfinite,
                  isInfinite || RainbowEvent.day(other.endDate) == last,
                  other.colorHex.uppercased() == colorHex.uppercased(),
                  abs(other.hoursPerDay - hours) < 0.0001,
                  other.importanceRaw == importance else { return false }
            // 고치는 중이면 그 일정의 패턴 · 뺀 날 · 이어진 할 일을 그대로 가져가고, 새 일정은 셋 다 없다.
            let pattern = event?.weeklyPattern, excluded = event?.excludedDates ?? [], todo = event?.todoToken
            let otherDays = other.selectedWeekdays.map { $0.sorted() }
            // 패턴이 있는 일정은 요일 칸을 고치지 않으므로 원래 값과 견준다 (→ save).
            let mine = hasPattern ? event?.selectedWeekdays.map { $0.sorted() } : days
            return otherDays == mine
                && other.weeklyPattern == pattern
                && other.excludedDates == excluded
                && other.todoToken == todo
        }
    }

    /// 행은 남기고 '지움' 표만 찍는다 (→ RainbowEvent.deletedAt).
    private func remove() {
        guard let event else { return }
        event.deletedAt = Date()
        event.updatedAt = Date()
        try? context.save()
        onClose()
    }
}

/// 시트에 넘기는 값. 새로 적을 때는 event가 nil.
struct RainbowEditContext: Identifiable {
    let id = UUID()
    let event: RainbowEvent?
    var defaultStart: Date = Date()
}
