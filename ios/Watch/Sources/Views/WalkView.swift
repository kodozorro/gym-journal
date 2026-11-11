import SwiftUI
import GymJournalCore

// Ходьба на часах: что записано, сколько по плану и запись отрезка.
//
// Ходьбу обычно делят на части, до и после силовой, поэтому на часах записывают отрезок: он
// прибавляется к уже записанному. После тренировки «Ходьба» минуты и километры подставлены сами.

struct WalkScreen: View {
    @EnvironmentObject private var model: WatchModel
    let key: String

    var body: some View {
        ScrollView {
            if let row = model.row(key), row.isWalk {
                content(row)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            } else {
                MessageView(icon: "questionmark.circle", title: "Ходьбы нет", text: "В сегодняшнем дне её больше нет.")
            }
        }
        .navigationTitle("Ходьба")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ row: JournalRow) -> some View {
        let walking = model.workout?.kind == .walk
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.exercise)
                    .font(.watch(16, .semibold))
                    .foregroundStyle(WatchPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.plan.isEmpty {
                    Text("План: \(row.plan)")
                        .font(.watch(13))
                        .foregroundStyle(WatchPalette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.hasData ? "Записано" : "Пока не записано")
                    .font(.watch(12))
                    .foregroundStyle(WatchPalette.ink3)
                if row.hasData {
                    Text(row.summary)
                        .font(.watch(20, .bold, rounded: true))
                        .monospacedDigit()
                        .foregroundStyle(WatchPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let pace = Journal.pace(km: row.km, min: row.min) {
                        Text("\(pace.pace) мин/км · \(Numbers.format(pace.speed, digits: 1)) км/ч")
                            .font(.watch(12))
                            .monospacedDigit()
                            .foregroundStyle(WatchPalette.ink2)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: WatchMetrics.radius))

            if walking {
                // идёт тренировка «Ходьба»: её конец сам предложит записать отрезок
                Button(model.workoutEnding ? "Завершаю…" : "Закончить ходьбу") {
                    model.endWorkout()
                }
                .buttonStyle(.watch(.primary))
                .disabled(model.workoutEnding)
            } else if model.workoutOffer.contains(.walk) {
                Button {
                    model.startWorkout(.walk)
                } label: {
                    Label(
                        model.workoutStarting == .walk ? "Запускаю…" : WorkoutLook.startTitle(.walk),
                        systemImage: WorkoutLook.icon(.walk)
                    )
                }
                .buttonStyle(.watch(.soft))
                .disabled(model.workoutStarting != nil)
            }
            Button("Записать отрезок") {
                model.askWalk(key)
            }
            .buttonStyle(.watch(walking ? .plain : .primary))
        }
    }
}

/// Окно «Отрезок ходьбы»: километры и минуты выбирают колёсиком.
struct WalkSegmentSheet: View {
    private enum Field: Hashable {
        case km, minutes
    }

    @EnvironmentObject private var model: WatchModel
    @Environment(\.dismiss) private var dismiss
    let prompt: WalkPrompt

    @State private var km = 0.0
    @State private var minutes = 0.0
    @FocusState private var field: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(prompt.note)
                    .font(.watch(12))
                    .foregroundStyle(WatchPalette.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    value(Numbers.format(km), unit: "км", active: field == .km)
                        .focusable()
                        .focused($field, equals: .km)
                        .digitalCrownRotation(
                            detent: $km, from: 0, through: 200, by: 0.05, sensitivity: .medium,
                            isContinuous: false, isHapticFeedbackEnabled: true
                        )
                        .accessibilityLabel("Километры: \(Numbers.format(km))")
                    value(Numbers.format(minutes, digits: 0), unit: "мин", active: field == .minutes)
                        .focusable()
                        .focused($field, equals: .minutes)
                        .digitalCrownRotation(
                            detent: $minutes, from: 0, through: 1440, by: 1, sensitivity: .medium,
                            isContinuous: false, isHapticFeedbackEnabled: true
                        )
                        .accessibilityLabel("Минуты: \(Numbers.format(minutes, digits: 0))")
                }
                Text("Коснитесь числа и поверните колёсико")
                    .font(.watch(11))
                    .foregroundStyle(WatchPalette.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Записать") {
                    model.addWalk(prompt.key, km: km, minutes: minutes)
                    dismiss()
                }
                .buttonStyle(.watch(.primary))
                .disabled(km <= 0 && minutes <= 0)
            }
            .padding(.horizontal, 6)
        }
        .onAppear {
            km = prompt.km
            minutes = prompt.minutes
            field = .km
        }
    }

    private func value(_ text: String, unit: String, active: Bool) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.watch(24, .bold, rounded: true))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.watch(12))
                .foregroundStyle(WatchPalette.ink3)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
            active ? WatchPalette.accentSoft : WatchPalette.surface,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
