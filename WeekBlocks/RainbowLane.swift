//
//  RainbowLane.swift
//  무지개 공방
//
//  **아이폰 '욕망의 무지개'의 일정을 맥에서도 본다 · 고친다 · 더한다.** (→ RainbowEvent.swift)
//
//  무지개 일정은 '이 기간 동안 하루 몇 시간씩'이다. 시각이 없으니 시간 칸에는 안 서고,
//  요일 아래 무지개 점(→ TodoRainbow)에 한 칸씩 더해진다. 아이폰 무지개의 한 줄이 그날 한 칸인 것과 같다 —
//  기간 안이면 옅게, 실제로 하는 날이면 진하게. 고치기는 ⋯ 메뉴의 '이 주의 무지개 일정'에서.
//

import SwiftUI
import SwiftData

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
    /// 무지개 판에서 끌어 고른 끝날. nil이면 시작부터 한 주.
    var defaultEnd: Date? = nil
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var isInfinite = false
    @State private var hours: Double = 2
    @State private var weekdays: Set<Int> = []   // 비어 있으면 매일
    /// 몇 주마다 (→ RainbowEvent.repeatWeeks). 1 = 매주.
    @State private var repeatWeeks = 1
    @State private var colorHex = Rainbow.spectrum.first?.hex ?? "#FF3B30"
    @State private var importance = "medium"
    @State private var confirmingDelete = false
    /// 같은 일정이 이미 있다 — 어느 기기에서 만든 것인지.
    @State private var twinOrigin: String?
    /// 회차 (→ RainbowEvent.sessions). 있으면 요일 · 반복 대신 이 날들만 하는 날이다.
    @State private var sessions: [RainbowSession] = []
    @State private var showingPaste = false

    private var hasPattern: Bool { event?.weeklyPattern != nil }

    /// 월요일부터 (Calendar weekday: 1=일 … 7=토).
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event == nil ? "장기 플랜 추가" : "장기 플랜 고치기")
                .font(.title2.bold())

            Form {
                TextField("제목", text: $title)
                if !sessions.isEmpty {
                    // 회차가 있으면 기간은 첫 회차부터 마지막 회차까지 — 따로 고르지 않는다.
                    LabeledContent("기간") {
                        Text(sessionPeriodText).monospacedDigit()
                    }
                } else {
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
                if !hasPattern {
                    // 격주 수업처럼 — 기간 내내 옅은 줄이 이어지고, 하는 주의 그 요일만 진하게 선다.
                    Picker("반복", selection: $repeatWeeks) {
                        ForEach(1...4, id: \.self) { n in
                            Text(RainbowEvent.repeatLabel(n)).tag(n)
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
                                // 색 동그라미는 이름이 없다 — 색 이름을 붙이고 누를 수 있게.
                                .accessibilityElement()
                                .accessibilityLabel(paletteDisplayName(swatch.name))
                                .accessibilityAddTraits(colorHex.uppercased() == swatch.hex.uppercased()
                                                        ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction { colorHex = swatch.hex }
                        }
                    }
                }

                sessionsSection
            }
            .formStyle(.grouped)
            .frame(minHeight: 360, idealHeight: sessions.isEmpty ? 420 : 640)

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
        .frame(width: 560)
        .sheet(isPresented: $showingPaste) {
            RainbowSessionPasteSheet { parsed in
                if title.trimmingCharacters(in: .whitespaces).isEmpty, let t = parsed.title { title = t }
                if !parsed.sessions.isEmpty {
                    withAnimation(Motion.row) { sessions = parsed.sessions }
                }
            }
        }
        .onAppear(perform: load)
        // ⚠️ 막는다, 묻지 않는다. 제목·날짜·색이 같은 두 일정은 아이폰 다리(RainbowBridge)가
        //    기기 사이에서 하나로 합친다 — '그래도 만들기'를 두면 만든 것이 곧 사라진다.
        .alert("같은 일정이 이미 있어요", isPresented: Binding(get: { twinOrigin != nil },
                                                          set: { if !$0 { twinOrigin = nil } })) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("\(twinOrigin ?? "") 만든 일정과 모든 내용이 같습니다. 똑같은 일정은 기기 사이에서 하나로 합쳐지니, 제목이나 날짜를 바꿔 주세요.")
        }
        .confirmationDialog("이 장기 플랜을 지울까요?", isPresented: $confirmingDelete) {
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
            end = defaultEnd.map { max(start, Calendar.current.startOfDay(for: $0)) }
                ?? Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            return
        }
        title = event.title
        // 다른 시간대 기기가 적은 날짜도 이 기기의 그날로 읽는다 (→ RainbowEvent.day).
        start = RainbowEvent.day(event.startDate)
        end = RainbowEvent.day(event.endDate)
        isInfinite = event.isInfinite
        hours = event.hoursPerDay
        weekdays = Set(event.selectedWeekdays ?? [])
        repeatWeeks = max(1, event.repeatWeeks)
        colorHex = event.colorHex
        importance = event.importanceRaw
        sessions = event.sessions
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
            target.repeatWeeks = repeatWeeks
        }
        target.colorHex = colorHex
        target.importanceRaw = importance
        // 회차가 있으면 기간 · 하는 날 · 하루 시간을 회차가 정한다.
        var list = sessions.sorted { $0.date < $1.date }
        if let first = list.first, let last = list.last {
            target.startDate = cal.startOfDay(for: first.date)
            target.endDate = cal.startOfDay(for: last.date)
            target.isInfinite = false
            target.selectedWeekdays = nil
            target.weeklyPattern = nil
            target.repeatWeeks = 1
            target.hoursPerDay = list.map(\.hours).reduce(0, +) / Double(list.count)
            moveSessionBlocks(list, planTitle: target.title)
            makeSessionBlocks(&list, planTitle: target.title)
        }
        target.sessions = list
        target.updatedAt = Date()
        try? context.save()
        onClose()
    }

    /// **회차마다 그날의 계획 블록을 하나씩** — 일간에 서고, 시각을 정하고, 회고로 찍을 수 있게.
    /// 이름은 "플랜 이름 + 회차 이름". 무지개는 회차를 장기 플랜 줄로 세므로 이 블록은 두 번 세지 않는다
    /// (→ RainbowEvent.carriesSession). 한 번 만든 회차는 다시 만들지 않는다 — 지웠으면 지운 뜻이다.
    private func makeSessionBlocks(_ list: inout [RainbowSession], planTitle: String) {
        for i in list.indices where !list[i].blockMade {
            let date = Calendar.current.startOfDay(for: list[i].date)
            let startHour = list[i].startHour
            let block = PlanBlock(day: DayOfWeek.of(date),
                                  timeBand: startHour.map(TimeBand.containing) ?? .evening,
                                  durationHours: list[i].hours,
                                  title: "\(planTitle) \(list[i].displayTitle(index: i))",
                                  successCriteria: "",
                                  deliverable: "",
                                  weekStartDate: date.weekStart(),
                                  startHour: startHour ?? -1)
            TodoSharing.stamp(block)
            context.insert(block)
            list[i].blockMade = true
        }
    }

    /// **이미 블록이 선 회차의 시각을 바꿨으면 그 블록도 옮긴다** — 그날, 같은 이름의 블록.
    /// 회차 날짜 · 이름을 바꾼 것은 따라가지 않는다 (어느 블록인지 더는 모른다).
    private func moveSessionBlocks(_ list: [RainbowSession], planTitle: String) {
        let before = Dictionary(uniqueKeysWithValues: (event?.sessions ?? []).map { ($0.id, $0) })
        let blocks = (try? context.fetch(FetchDescriptor<PlanBlock>())) ?? []
        for (i, session) in list.enumerated() where session.blockMade {
            guard let old = before[session.id], old.startHour != session.startHour || old.hours != session.hours,
                  RainbowEvent.day(old.date) == RainbowEvent.day(session.date) else { continue }
            let date = RainbowEvent.day(session.date)
            let name = "\(planTitle) \(session.displayTitle(index: i))"
            for block in blocks where block.title == name && block.day == DayOfWeek.of(date)
                && Calendar.current.isDate(block.weekStartDate, inSameDayAs: date.weekStart()) {
                block.startHour = session.startHour ?? -1
                if let h = session.startHour { block.timeBand = .containing(h) }
                block.durationHours = session.hours
            }
        }
    }

    /// 회차의 시작 시각을 시계 칸에 물린다 (그날 0시 + 시각).
    private func startTime(_ session: Binding<RainbowSession>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval((session.wrappedValue.startHour ?? 19) * 3600)
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            session.wrappedValue.startHour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
    }

    private var sessionPeriodText: String {
        let list = sessions.sorted { $0.date < $1.date }
        guard let first = list.first, let last = list.last else { return "" }
        let f = Date.FormatStyle.dateTime.year().month().day()
        return "\(first.date.formatted(f)) – \(last.date.formatted(f))"
    }

    /// 회차 목록 — 날짜 · 이름 · 시간 · 메모. 붙여 넣어 한꺼번에 채울 수도 있다.
    @ViewBuilder
    private var sessionsSection: some View {
        Section {
            ForEach($sessions) { $session in
                let index = sessions.firstIndex(where: { $0.id == session.id }) ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $session.date, displayedComponents: .date)
                            .labelsHidden()
                        TextField("", text: $session.title,
                                  prompt: Text(RainbowSession(date: session.date).displayTitle(index: index)))
                            .textFieldStyle(.roundedBorder)
                        Text(RainbowEventFormat.hours(session.hours)).monospacedDigit()
                        Stepper("", value: $session.hours, in: 0.25...16, step: 0.25).labelsHidden()
                        Button {
                            withAnimation(Motion.row) { sessions.removeAll { $0.id == session.id } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("이 회차 빼기")
                        .accessibilityLabel("이 회차 빼기")
                    }
                    HStack(spacing: 8) {
                        // 시각은 고르기 — 비워 두면 그날 몇 시간만 (블록은 저녁에 시각 없이 선다).
                        if session.startHour != nil {
                            DatePicker("", selection: startTime($session), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .fixedSize()
                            Button {
                                session.startHour = nil
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("시각 지우기")
                            .accessibilityLabel("시각 지우기")
                        } else {
                            Button {
                                // 앞 회차의 시각을 이어받는다 — 과정은 대개 같은 시각이다.
                                session.startHour = sessions.last(where: { $0.startHour != nil })?.startHour ?? 19
                            } label: {
                                Label("시각", systemImage: "clock")
                            }
                            .help("이 회차를 시작하는 시각 정하기")
                        }
                        TextField("", text: $session.note, prompt: Text("메모"))
                            .textFieldStyle(.roundedBorder)
                    }
                    if session.blockMade {
                        Text("일간에 블록으로 서 있습니다")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Button {
                    let cal = Calendar.current
                    let last = sessions.map(\.date).max()
                    // 다음 회차는 마지막 회차 2주 뒤 — 격주 과정이 흔하다. 처음이면 시작일.
                    let date = last.flatMap { cal.date(byAdding: .day, value: 14, to: $0) } ?? cal.startOfDay(for: start)
                    withAnimation(Motion.row) {
                        sessions.append(RainbowSession(date: date, hours: sessions.last?.hours ?? hours,
                                                       startHour: sessions.last?.startHour))
                    }
                } label: {
                    Label("회차 추가", systemImage: "plus")
                }
                Button {
                    showingPaste = true
                } label: {
                    Label("붙여 넣어 채우기", systemImage: "doc.on.clipboard")
                }
            }
        } header: {
            Text("회차")
        } footer: {
            Text("회차마다 시간과 내용이 다른 과정에 씁니다. 회차가 있으면 그 날들만 진하게 서고, 저장하면 회차마다 일간에 블록이 생깁니다.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
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
            let myRepeat = hasPattern ? (event?.repeatWeeks ?? 1) : repeatWeeks
            return otherDays == mine
                && max(1, other.repeatWeeks) == max(1, myRepeat)
                && other.weeklyPattern == pattern
                && other.excludedDates == excluded
                && other.todoToken == todo
                && other.sessions.map(\.date) == sessions.sorted { $0.date < $1.date }.map(\.date)
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
    /// 무지개 판에서 끌어 고른 끝날 (→ RainbowDensityView.onAddRange).
    var defaultEnd: Date? = nil
}

// MARK: - 할 일의 기간

/// **할 일에 기간을 붙인다** — 그 할 일에 이어진 장기 플랜(RainbowEvent.todoToken) 한 줄로.
///
/// 아이폰이 할 일에 기한을 정할 때(→ TodoEventBridge.drawRainbow)와 같은 꼴이라, 아이폰 할 일에도
/// 같은 기한이 서고 무지개에도 같은 줄이 그어진다. 시작부터 마감까지 옅게 매여 있고, 진하게 손대는 날은
/// 아이폰과 같은 짐작 — 다섯 주 안이면 **마감 하루만**, 그보다 멀면 마감 요일마다.
enum TodoPeriod {
    static func draw(for item: BacklogItem, period: ClosedRange<Date>, context: ModelContext) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: period.lowerBound)
        let end = max(start, cal.startOfDay(for: period.upperBound))
        let event = RainbowEvent(title: item.title)
        event.startDate = start
        event.endDate = end
        event.hoursPerDay = max(0.5, item.durationHours)
        event.todoToken = item.dragToken
        event.originInstallID = TodoSharing.installID
        let days = cal.dateComponents([.day], from: start, to: end).day ?? 0
        if days < 35 {
            var pattern = [Bool](repeating: false, count: 35)
            pattern[days] = true
            event.weeklyPattern = pattern
        } else {
            event.selectedWeekdays = [cal.component(.weekday, from: end)]
        }
        context.insert(event)
    }
}

/// 새 할 일 칸에서 여는 기간 고르기 — 시작과 마감.
struct TodoPeriodPicker: View {
    @Binding var period: ClosedRange<Date>?
    let onClose: () -> Void

    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.date(byAdding: .day, value: 14,
                                                   to: Calendar.current.startOfDay(for: Date())) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기간")
                .font(.headline)
            DatePicker("시작", selection: $start, displayedComponents: .date)
            DatePicker("마감", selection: $end, in: start..., displayedComponents: .date)
            Text("시작부터 마감까지 무지개에 이어진 줄로 섭니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if period != nil {
                    Button("기간 지우기", role: .destructive) {
                        period = nil
                        onClose()
                    }
                }
                Spacer()
                Button("정하기") {
                    period = start...max(start, end)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            if let period {
                start = period.lowerBound
                end = period.upperBound
            }
        }
    }
}

// MARK: - 회차 붙여 넣기

/// **붙여 넣은 글에서 회차를 뽑는다.**
///
/// 날짜 줄과 회차 줄을 따로 모아 **차례대로 짝짓는다.** 두 목록을 이어 붙여도, 섞어 붙여도 된다.
///  · 날짜 줄: 2026-10-06 · 2026.10.06 · 2026/10/06
///  · 회차 시작: "1세션" · "2회차" · "3회" · "Session 4"
///  · 시간: "2H" · "1.5h" · "2시간" — 바로 앞 회차의 시간
///  · 그 밖의 줄: 회차가 시작된 뒤면 그 회차의 메모(여러 줄은 띄어 이어 붙인다),
///    아무 회차도 날짜도 없을 때 처음 나온 줄은 플랜 이름
/// 회차 줄이 없으면 날짜마다 빈 회차를 세운다.
enum RainbowSessionParser {
    struct Result {
        var title: String?
        var sessions: [RainbowSession]
        var dateCount: Int
        var sessionCount: Int
    }

    static func parse(_ text: String) -> Result {
        var title: String?
        var dates: [Date] = []
        /// 날짜 줄에 함께 적힌 시각 (시작, 끝) — "2026-10-06 19:00~21:00".
        var times: [(start: Double?, end: Double?)] = []
        var drafts: [(title: String, hours: Double?, note: [String])] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let date = date(in: line) {
                dates.append(date)
                times.append(clockTimes(in: line))
            } else if line.range(of: #"^(\d+\s*(세션|회차|회|주차)|(session|class)\s*\d+)$"#,
                                 options: [.regularExpression, .caseInsensitive]) != nil {
                drafts.append((line, nil, []))
            } else if let h = hours(in: line), !drafts.isEmpty, drafts[drafts.count - 1].hours == nil {
                drafts[drafts.count - 1].hours = h
            } else if !drafts.isEmpty {
                drafts[drafts.count - 1].note.append(line)
            } else if title == nil, dates.isEmpty {
                title = line
            }
        }
        let count = drafts.isEmpty ? dates.count : min(dates.count, drafts.count)
        let sessions = (0..<count).map { i -> RainbowSession in
            let draft = i < drafts.count ? drafts[i] : nil
            let time = times[i]
            // 회차 줄의 시간(2H)이 먼저, 없으면 날짜 줄의 시작~끝.
            let span = time.start.flatMap { s in time.end.map { $0 > s ? $0 - s : $0 + 24 - s } }
            return RainbowSession(date: dates[i], hours: draft?.hours ?? span ?? 1, startHour: time.start,
                                  title: draft?.title ?? "", note: draft?.note.joined(separator: " ") ?? "")
        }
        return Result(title: title, sessions: sessions, dateCount: dates.count, sessionCount: drafts.count)
    }

    private static func date(in line: String) -> Date? {
        guard let r = line.range(of: #"^(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#, options: .regularExpression) else { return nil }
        let parts = line[r].split(whereSeparator: { "-./".contains($0) }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 줄 안의 "19:00" · "19:00~21:00" — 앞의 둘까지.
    private static func clockTimes(in line: String) -> (start: Double?, end: Double?) {
        let regex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)
        let ns = line as NSString
        let found = (regex?.matches(in: line, range: NSRange(location: 0, length: ns.length)) ?? []).compactMap { m -> Double? in
            guard let h = Int(ns.substring(with: m.range(at: 1))), let mm = Int(ns.substring(with: m.range(at: 2))),
                  h < 24, mm < 60 else { return nil }
            return Double(h) + Double(mm) / 60
        }
        return (found.first, found.count > 1 ? found[1] : nil)
    }

    private static func hours(in line: String) -> Double? {
        guard let r = line.range(of: #"^(\d+(\.\d+)?)\s*(h|시간|hr|hrs)$"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let number = line[r].prefix { $0.isNumber || $0 == "." }
        return Double(number)
    }
}

/// 날짜 목록과 회차 내용을 붙여 넣는 창.
struct RainbowSessionPasteSheet: View {
    let onFill: (RainbowSessionParser.Result) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var parsed: RainbowSessionParser.Result { RainbowSessionParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("회차 붙여 넣기")
                .font(.title2.bold())
            Text("날짜 줄(2026-10-06 19:00~21:00)과 회차 줄(1세션 · 2H · 메모)을 붙여 넣으세요. 차례대로 짝짓습니다. 시각은 없어도 됩니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            let p = parsed
            Group {
                if p.sessionCount > 0 && p.dateCount != p.sessionCount {
                    Text("날짜 \(p.dateCount)개 · 회차 \(p.sessionCount)개 — 적은 쪽에 맞춰 \(p.sessions.count)개를 채웁니다")
                        .foregroundStyle(.orange)
                } else {
                    Text("회차 \(p.sessions.count)개")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("채우기") {
                    onFill(parsed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed.sessions.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
