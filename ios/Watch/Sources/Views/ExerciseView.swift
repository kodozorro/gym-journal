import SwiftUI
import GymJournalCore

// Экран упражнения: записать подход одним касанием.
//
// Повторы уже подставлены: записанное число, прошлое или верх диапазона из плана. Колёсико
// меняет их, кнопка внизу записывает. Вес стоит с прошлого раза и меняется кнопками на шаг,
// который задан в настройках на телефоне. Экран не прокручивается: колёсико занято повторами.

struct ExerciseScreen: View {
    @EnvironmentObject private var model: WatchModel
    let key: String

    /// Повторы, выбранные колёсиком.
    @State private var reps = 10.0
    /// Подход, выбранный касанием; nil — первый незаписанный.
    @State private var picked: Int?
    @FocusState private var crown: Bool

    var body: some View {
        if let row = model.row(key), !row.isWalk {
            content(row)
        } else {
            ScrollView {
                MessageView(icon: "questionmark.circle", title: "Упражнения нет", text: "В сегодняшнем дне его больше нет.")
            }
        }
    }

    /// Подход, с которым работают: выбранный касанием или первый незаписанный.
    private func activeIndex(_ row: JournalRow) -> Int? {
        if let picked, picked < row.slotCount { return picked }
        let next = row.nextSetIndex
        return next >= 0 ? next : nil
    }

    /// С какого числа повторов начать для подхода.
    private func anchor(_ row: JournalRow, _ index: Int) -> Double {
        let last = model.state.last[key]
        let before: Double? = last.flatMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil }
        return Double(Present.reps(plan: row.strengthPlan, current: row.sets[index], last: before).anchor)
    }

    /// Меняется, когда повторы нужно подставить заново: другое упражнение, другой подход или
    /// другое записанное число.
    private func stamp(_ row: JournalRow, _ index: Int?) -> String {
        guard let index else { return row.key + "|none" }
        var value = ""
        if let done = row.sets[index] { value = Numbers.plain(done) }
        return row.key + "|\(index)|" + value
    }

    private func sync(_ row: JournalRow) {
        guard let index = activeIndex(row) else { return }
        reps = anchor(row, index)
    }

    private func content(_ row: JournalRow) -> some View {
        let index = activeIndex(row)
        let busy = model.activeRest != nil
        return VStack(spacing: 5) {
            Text(row.exercise)
                .font(.watch(15, .semibold))
                .foregroundStyle(WatchPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            WeightRow(row: row)
            SetCells(row: row, active: index, reps: reps) { tapped in
                picked = tapped == row.nextSetIndex ? nil : tapped
                crown = true
            }
            // главная кнопка всегда у нижнего края: палец находит её не глядя
            Spacer(minLength: 0)
            action(row, index)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable(index != nil && !busy)
        .focused($crown)
        .digitalCrownRotation(
            detent: $reps, from: 1, through: 500, by: 1, sensitivity: .low,
            isContinuous: false, isHapticFeedbackEnabled: true
        )
        .focusEffectDisabled()
        .navigationTitle(Present.planChip(row))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sync(row)
            crown = true
        }
        .onChange(of: stamp(row, index)) { _, _ in
            if let current = model.row(key) { sync(current) }
        }
        .onChange(of: busy) { _, now in
            // отсчёт отдыха ушёл с экрана: колёсико снова меняет повторы
            if !now { crown = true }
        }
    }

    @ViewBuilder
    private func action(_ row: JournalRow, _ index: Int?) -> some View {
        if let index {
            Button(row.sets[index] == nil ? "Записать" : "Исправить") {
                let value = max(1, reps.rounded())
                picked = nil
                model.recordSet(key, index, value)
            }
            .buttonStyle(.watch(.primary))
        } else {
            let next = model.nextExercise(after: key)
            Button(next == nil ? "К списку" : "Дальше") {
                model.open(next)
            }
            .buttonStyle(.watch(.soft))
        }
    }
}

/// Вес: кнопки на шаг меньше и больше, касание числа открывает выбор колёсиком.
private struct WeightRow: View {
    @EnvironmentObject private var model: WatchModel
    let row: JournalRow

    var body: some View {
        let weight = model.weight(of: row)
        let text = weight.map { Numbers.format($0) } ?? "—"
        let spoken = weight == nil ? "не записан" : text + " кг"
        HStack(spacing: 4) {
            Button {
                model.stepWeight(row.key, -1)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(WatchRoundStyle())
            .accessibilityLabel("Убавить вес")

            Button {
                model.weightPrompt = WeightPrompt(key: row.key)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text)
                        .font(.watch(22, .bold, rounded: true))
                        .monospacedDigit()
                        // вес с прошлого раза ещё не записан: он бледнее
                        .foregroundStyle(row.weight == nil ? WatchPalette.ink2 : WatchPalette.ink)
                    Text("кг")
                        .font(.watch(13))
                        .foregroundStyle(WatchPalette.ink3)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Вес \(spoken). Изменить")

            Button {
                model.stepWeight(row.key, 1)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(WatchRoundStyle())
            .accessibilityLabel("Прибавить вес")
        }
    }
}

/// Ячейки подходов. В выбранной стоит число, которое меняет колёсико.
private struct SetCells: View {
    let row: JournalRow
    let active: Int?
    let reps: Double
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<row.slotCount, id: \.self) { index in
                Button {
                    onPick(index)
                } label: {
                    cell(index)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(index))
            }
        }
    }

    private func label(_ index: Int) -> String {
        if index == active { return "Подход \(index + 1): \(Numbers.plain(reps.rounded())) повторов, колёсико меняет число" }
        if let done = row.sets[index] { return "Подход \(index + 1): записано \(Numbers.plain(done))" }
        return "Подход \(index + 1): не записан"
    }

    private func cell(_ index: Int) -> some View {
        let isActive = index == active
        let done = row.sets[index]
        let text = isActive ? Numbers.plain(reps.rounded()) : (done.map { Numbers.plain($0) } ?? "–")
        var ink = WatchPalette.ink3
        if isActive {
            ink = WatchPalette.ink
        } else if done != nil {
            ink = WatchPalette.okSoftInk
        }
        return Text(text)
            .font(.watch(isActive ? 28 : 20, .bold, rounded: true))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(ink)
            // на маленьких часах ячейки ниже: так на экран помещается название в две строки
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 50)
            .background(
                isActive ? WatchPalette.accentSoft : (done != nil ? WatchPalette.okSoft : WatchPalette.surface),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? WatchPalette.mark : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
    }
}

/// Выбор веса колёсиком: один щелчок — один шаг.
struct WeightSheet: View {
    @EnvironmentObject private var model: WatchModel
    @Environment(\.dismiss) private var dismiss
    let key: String

    @State private var weight = 0.0
    @FocusState private var crown: Bool

    var body: some View {
        let step = model.step(for: key)
        VStack(spacing: 6) {
            Text(model.row(key)?.exercise ?? "Вес")
                .font(.watch(13))
                .foregroundStyle(WatchPalette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Numbers.format(weight))
                    .font(.watch(38, .bold, rounded: true))
                    .monospacedDigit()
                    .foregroundStyle(WatchPalette.ink)
                Text("кг")
                    .font(.watch(15))
                    .foregroundStyle(WatchPalette.ink3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 52)
            .focusable()
            .focused($crown)
            .digitalCrownRotation(
                detent: $weight, from: 0, through: 1000, by: step, sensitivity: .medium,
                isContinuous: false, isHapticFeedbackEnabled: true
            )
            Text("Колёсико меняет вес по \(Numbers.format(step)) кг")
                .font(.watch(12))
                .foregroundStyle(WatchPalette.ink3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Готово") {
                model.setWeight(key, weight)
                dismiss()
            }
            .buttonStyle(.watch(.primary))
        }
        .padding(.horizontal, 6)
        .onAppear {
            weight = model.row(key).flatMap { model.weight(of: $0) } ?? 0
            crown = true
        }
    }
}
