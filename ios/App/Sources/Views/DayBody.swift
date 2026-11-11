import SwiftUI
import GymJournalCore

// День тренировки. Упражнения идут парами в порядке строк таблицы. Открыта пара, с которой
// сейчас работают; записанные упражнения сворачиваются сами. Повторы записываются одним
// касанием числа.

struct DayBody: View {
    @EnvironmentObject private var model: AppModel
    let day: JournalDay

    var body: some View {
        let rows = day.rows
        let split = Journal.splitDay(rows)
        let pairs = split.pairs
        let walks = split.walks
        let progress = Journal.dayProgress(rows)
        let active = model.activePair(date: day.date, pairs: pairs)
        let offer = model.workoutOffer(for: day)
        // Силовой день начинается с ходьбы, а её строка в таблице последняя: кнопка сверху, пока ничего не записано.
        let untouched = rows.allSatisfy { !$0.hasData }
        VStack(alignment: .leading, spacing: Metrics.gap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(pairs.isEmpty ? "Ходьба" : Journal.workoutTitle(rows))
                        .font(.app(20, .bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(progress.done) из \(progress.total)")
                        .font(.app(15))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
                MeterView(
                    share: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0,
                    label: "Записано упражнений"
                )
            }

            if !offer.isEmpty {
                WorkoutOfferView(kinds: offer, date: day.date)
            }

            if !pairs.isEmpty, !model.settings.weightNoteSeen {
                BannerView(
                    lead: "Как записывать вес. ",
                    text: "Так, как он выставлен на тренажёре: число на плитке стека или сумма дисков. Тогда график покажет настоящий прогресс."
                ) {
                    Button("Понятно") {
                        model.dismissWeightNote()
                    }
                    .buttonStyle(.app(.surface, small: true))
                }
            }

            if !pairs.isEmpty, let warmup = walks.first, untouched {
                Button {
                    model.openWalk(warmup.key, .add)
                } label: {
                    HStack(spacing: 8) {
                        Icon("plus", size: 20)
                        Text("Записать ходьбу до силовой")
                    }
                }
                .buttonStyle(.app(.soft, block: true))
            }

            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CapsTitle(pairs.count > 1 ? "Пара \(index + 1)" : "Упражнения")
                        Spacer(minLength: 0)
                        if index == active {
                            Button {
                                model.startRest()
                            } label: {
                                HStack(spacing: 6) {
                                    Icon("timer", size: 18)
                                    Text("Отдых \(RestTimer.clock(model.settings.restSec))")
                                }
                                .font(.app(15, .semibold))
                                .foregroundStyle(Palette.accentText)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.press)
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 2)
                    ForEach(pair) { row in
                        ExerciseCard(row: row, pairIndex: index, inActivePair: index == active)
                            .id(row.key)
                    }
                }
            }

            if !walks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !pairs.isEmpty {
                        CapsTitle("Ходьба")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 2)
                    }
                    ForEach(walks) { row in
                        WalkCard(row: row)
                            .id(row.key)
                    }
                }
            }
        }
    }
}

// MARK: Тренировка в «Здоровье»

/// Кнопки «начать тренировку»: силовую, если в дне есть тренажёры, и ходьбу, если есть ходьба.
private struct WorkoutOfferView: View {
    @EnvironmentObject private var model: AppModel
    let kinds: [WorkoutKind]
    let date: String

    var body: some View {
        let onWatch = model.watchInstalled
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: onWatch ? "applewatch" : "iphone")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Тренировка в «Здоровье»")
                        .font(.app(16, .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(onWatch
                        ? "Часы начнут её сами и посчитают пульс и калории."
                        : "Телефон запишет вид тренировки и её время.")
                        .font(.app(13))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                ForEach(kinds, id: \.self) { kind in
                    Button {
                        model.startWorkout(kind, date: date)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(model.workoutPending == kind ? "Запускаю…" : kind.title)
                        }
                    }
                    .buttonStyle(.app(.soft, small: true, block: true))
                    .disabled(model.workoutPending != nil)
                }
            }
        }
        .card(padding: Metrics.cardPad, vertical: 12)
    }
}

// MARK: Общее для карточек

/// «Прошлый раз: 60 кг · 15, 14, пн 23.11».
private struct LastLine: View {
    let last: JournalRow?

    private var text: AttributedString {
        guard let last else { return AttributedString("Раньше не записывалось") }
        var summary = AttributedString(last.summary)
        summary.font = Font.app(15, .semibold)
        summary.foregroundColor = Palette.ink
        return AttributedString("Прошлый раз: ") + summary + AttributedString(", \(Days.formatSheetDay(last.date))")
    }

    var body: some View {
        Text(text)
            .font(.app(15))
            .foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Кнопка «i»: фото тренажёра, рисунок и техника упражнения. Стоит рядом с заголовком карточки,
/// значок на уровне названия, а место под палец — 44 пункта: лишнее уходит в отрицательные поля.
private struct InfoButton: View {
    @EnvironmentObject private var model: AppModel
    let row: JournalRow
    /// В свёрнутой карточке кнопка стоит по центру строки.
    var centered = false

    var body: some View {
        Button {
            model.openInfo(row)
        } label: {
            Icon("info")
                .foregroundStyle(Palette.accentText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.press)
        .padding(EdgeInsets(top: centered ? 0 : -10, leading: -6, bottom: centered ? 0 : -10, trailing: -10))
        .accessibilityLabel("Фото и техника: \(row.exercise)")
    }
}

/// Низ карточки: заметка и отметка о том, что запись ещё не ушла в таблицу.
private struct RowFooter: View {
    @EnvironmentObject private var model: AppModel
    let row: JournalRow

    var body: some View {
        let empty = row.note.isEmpty
        HStack(spacing: 8) {
            Button {
                model.openNote(row.key)
            } label: {
                HStack(spacing: 6) {
                    Icon("note", size: 18)
                    Text(empty ? "Заметка" : row.note)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.app(15, empty ? .semibold : .regular))
                .foregroundStyle(empty ? Palette.accentText : Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.press)
            .accessibilityLabel(empty ? "Заметка" : "Заметка: \(row.note)")
            if row.pending {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Palette.ink3)
                        .frame(width: 6, height: 6)
                    Text("не отправлено")
                        .font(.app(12))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
                .fixedSize()
            }
        }
        .padding(.top, -4)
        .padding(.bottom, -6)
    }
}

// MARK: Силовое упражнение

struct ExerciseCard: View {
    @EnvironmentObject private var model: AppModel
    let row: JournalRow
    let pairIndex: Int
    let inActivePair: Bool

    var body: some View {
        let plan = row.strengthPlan
        let done = row.isDone
        let isOpen = model.open[row.key] ?? (inActivePair && !done)
        let last = Journal.lastTime(model.sync.journal, for: row)
        VStack(alignment: .leading, spacing: 12) {
            head(plan: plan, done: done, isOpen: isOpen, last: last)
            if isOpen {
                opened(plan: plan, last: last)
            }
        }
        .card(padding: Metrics.cardPad, vertical: isOpen ? 14 : 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.exercise)
    }

    // тренажёр идёт отдельной строкой под названием, во всю ширину заголовка
    private func head(plan: StrengthPlan, done: Bool, isOpen: Bool, last: JournalRow?) -> some View {
        let meta = Present.meta(row)
        return HStack(alignment: isOpen ? .top : .center, spacing: 0) {
            Button {
                model.toggleCard(row, pair: pairIndex, open: !isOpen)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: isOpen ? .top : .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.exercise)
                                .font(.app(19, .bold))
                                .foregroundStyle(Palette.ink)
                            if !isOpen {
                                Text(Present.closedText(row, last: last))
                                    .font(.app(15))
                                    .foregroundStyle(Palette.ink2)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if done {
                            DoneBadge()
                        }
                        if isOpen, !plan.unknown {
                            Text(Present.planChip(row))
                                .font(.app(15, .bold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 10))
                        }
                        Icon(isOpen ? "chevronUp" : "chevronDown", size: 20)
                            .foregroundStyle(Palette.ink3)
                    }
                    if isOpen, !meta.isEmpty {
                        Text(meta)
                            .font(.app(14))
                            .foregroundStyle(Palette.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: isOpen ? .topLeading : .leading)
            }
            .buttonStyle(.press)
            .accessibilityValue(isOpen ? "раскрыто" : "свёрнуто")
            InfoButton(row: row, centered: !isOpen)
        }
    }

    @ViewBuilder
    private func opened(plan: StrengthPlan, last: JournalRow?) -> some View {
        let slots = model.slotsOf(row)
        let selected = model.selectedSet(row)
        let step = model.settings.step(for: row.exercise)
        // вес, который подставлен, но ещё не записан: с прошлого раза
        let draft: Double? = row.weight == nil ? last?.weight : nil
        let shown: Double? = row.weight ?? draft
        let stepText = Numbers.format(step)

        LastLine(last: last)

        if model.settings.hints, row.weight == nil, let hint = Journal.progression(last: last, step: step) {
            HStack(spacing: 10) {
                Text("В прошлый раз все подходы дошли до \(hint.reps). По правилу программы пора прибавить.")
                    .font(.app(15))
                    .foregroundStyle(Palette.okSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Взять \(Numbers.format(hint.weight)) кг") {
                    model.setWeight(row.key, hint.weight)
                }
                .buttonStyle(.app(.surface, small: true))
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8))
            .background(Palette.okSoft, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
        }

        HStack(spacing: 8) {
            stepButton(Icon("minus", size: 26), label: "Убавить вес на \(stepText) кг") {
                model.stepWeight(row.key, -1)
            }
            .disabled((shown ?? 0) <= 0)
            Button {
                model.openWeight(row.key)
            } label: {
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(shown.map { Numbers.format($0) } ?? "—")
                            .font(.app(26, .bold))
                            .foregroundStyle(row.weight == nil ? Palette.ink2 : Palette.ink)
                        Text("кг")
                            .font(.app(15, .semibold))
                            .foregroundStyle(Palette.ink2)
                    }
                    .lineLimit(1)
                    Text(row.weight != nil ? "шаг \(stepText) кг" : (draft != nil ? "как в прошлый раз" : "укажите вес"))
                        .font(.app(12))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(row.weight == nil ? Color.clear : Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            row.weight == nil ? Palette.lineStrong : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                )
            }
            .buttonStyle(.press)
            .accessibilityLabel(shown.map { "Вес \(Numbers.format($0)) кг. Изменить" } ?? "Указать вес")
            stepButton(Icon("plus", size: 26), label: "Прибавить вес на \(stepText) кг") {
                model.stepWeight(row.key, 1)
            }
        }

        HStack(spacing: 8) {
            ForEach(0..<slots, id: \.self) { index in
                setCell(index, selected: index == selected)
            }
            if slots < Plans.maxSets {
                Button {
                    model.addSet(row)
                } label: {
                    VStack(spacing: 2) {
                        Text("ещё")
                            .font(.app(12))
                        Icon("plus", size: 22)
                    }
                    .foregroundStyle(Palette.ink3)
                    .frame(width: 52)
                    .frame(minHeight: 60)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.press)
                .accessibilityLabel("Добавить подход")
            }
        }

        if selected >= 0 {
            RepsStrip(row: row, plan: plan, selected: selected, last: last)
        }

        RowFooter(row: row)
    }

    private func stepButton(_ icon: Icon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .foregroundStyle(Palette.ink)
                .frame(width: 56)
                .frame(minHeight: 56)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.press)
        .accessibilityLabel(label)
    }

    private func setCell(_ index: Int, selected: Bool) -> some View {
        let value: Double? = row.sets.indices.contains(index) ? row.sets[index] : nil
        return Button {
            model.selectSet(row, index)
        } label: {
            VStack(spacing: 2) {
                Text("Подход \(index + 1)")
                    .font(.app(12))
                    .foregroundStyle(selected ? Palette.accentSoftInk : Palette.ink3)
                    .lineLimit(1)
                Text(value.map { Numbers.plain($0) } ?? "—")
                    .font(.app(24, value == nil ? .medium : .bold))
                    .foregroundStyle(value == nil ? Palette.ink3 : Palette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(selected ? Palette.accentSoft : Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Palette.accentText : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.press)
        .accessibilityLabel("Подход \(index + 1): \(value.map { Numbers.plain($0) } ?? "не записан")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Лента повторов: число записывается одним касанием. Лента прокручена так, чтобы нужное число
/// было посередине; повторно — только когда сменился подход или значение.
private struct RepsStrip: View {
    @EnvironmentObject private var model: AppModel
    let row: JournalRow
    let plan: StrengthPlan
    let selected: Int
    let last: JournalRow?

    private func value(_ source: JournalRow?) -> Double? {
        guard let source, source.sets.indices.contains(selected) else { return nil }
        return source.sets[selected]
    }

    private func inPlan(_ count: Int) -> Bool {
        guard !plan.unknown, let low = plan.low, let high = plan.high else { return false }
        return count >= low && count <= high
    }

    var body: some View {
        let current = value(row)
        let lastReps = value(last)
        let choice = Present.reps(plan: plan, current: current, last: lastReps)
        let anchor = "\(selected):\(choice.anchor)"
        VStack(alignment: .leading, spacing: 6) {
            Text("Повторы в подходе \(selected + 1)")
                .font(.app(13))
                .foregroundStyle(Palette.ink3)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(choice.low...max(choice.low, choice.high), id: \.self) { count in
                            repButton(count, current: current, lastReps: lastReps)
                                .id(count)
                        }
                        Button {
                            model.openReps(row.key, selected)
                        } label: {
                            Text("Другое")
                                .font(.app(15, .semibold))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 52)
                                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.press)
                    }
                    .padding(.horizontal, Metrics.cardPad)
                    .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo(choice.anchor, anchor: .center)
                }
                .onChange(of: anchor) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(choice.anchor, anchor: .center)
                    }
                }
            }
            // лента идёт от края до края карточки
            .padding(.horizontal, -Metrics.cardPad)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Повторы в подходе \(selected + 1)")
    }

    private func repButton(_ count: Int, current: Double?, lastReps: Double?) -> some View {
        let chosen = current == Double(count)
        let asLast = lastReps == Double(count)
        let planned = inPlan(count)
        let ink = chosen ? Palette.accentInk : (planned ? Palette.accentSoftInk : Palette.ink)
        let fill = chosen ? Palette.accent : (planned ? Palette.accentSoft : Palette.surface2)
        return Button {
            model.recordSet(row.key, selected, Double(count))
        } label: {
            Text(String(count))
                .font(.app(19, .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 6)
                .frame(minWidth: 48)
                .frame(height: 52)
                .background(fill, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .bottom) {
                    // точка под числом: столько было в прошлый раз
                    if asLast {
                        Circle()
                            .fill(ink)
                            .frame(width: 6, height: 6)
                            .padding(.bottom, 6)
                    }
                }
        }
        .buttonStyle(.press)
        .accessibilityLabel(asLast ? "\(count), как в прошлый раз" : String(count))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// MARK: Ходьба

struct WalkCard: View {
    @EnvironmentObject private var model: AppModel
    let row: JournalRow

    var body: some View {
        let last = Journal.lastTime(model.sync.journal, for: row)
        let pace = Journal.pace(km: row.km, min: row.min)
        let meta = [row.machine, row.plan].filter { !$0.isEmpty }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.exercise)
                            .font(.app(19, .bold))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        if row.isDone {
                            DoneBadge()
                        }
                    }
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.app(14))
                            .foregroundStyle(Palette.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                InfoButton(row: row)
            }
            LastLine(last: last)
            HStack(spacing: 8) {
                tile("Километры", row.km, .km)
                tile("Минуты", row.min, .min)
            }
            if let pace {
                Text("Темп \(pace.pace) мин/км · \(Numbers.format(pace.speed, digits: 1)) км/ч")
                    .font(.app(15))
                    .foregroundStyle(Palette.ink2)
            }
            Button {
                model.openWalk(row.key, .add)
            } label: {
                HStack(spacing: 8) {
                    Icon("plus", size: 20)
                    Text("Добавить отрезок")
                }
            }
            .buttonStyle(.app(.soft, block: true))
            RowFooter(row: row)
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.exercise)
    }

    private func tile(_ label: String, _ value: Double?, _ focus: WalkFocus) -> some View {
        Button {
            model.openWalk(row.key, focus)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.app(12))
                    .foregroundStyle(Palette.ink3)
                Text(value.map { Numbers.format($0) } ?? "—")
                    .font(.app(26, value == nil ? .medium : .bold))
                    .foregroundStyle(value == nil ? Palette.ink3 : Palette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.press)
        .accessibilityLabel("\(label): \(value.map { Numbers.format($0) } ?? "не записано"). Изменить")
    }
}
