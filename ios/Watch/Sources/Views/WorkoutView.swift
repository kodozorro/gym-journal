import SwiftUI
import WatchKit
import GymJournalCore

/// Размеры экрана тренировки. На часах поменьше время и числа мельче: кнопка «Завершить» видна
/// сразу и не заходит в скруглённый угол экрана.
private struct WorkoutLayout {
    var timer: CGFloat
    var value: CGFloat
    var spacing: CGFloat
    /// Отступ над кнопкой и под ней.
    var above: CGFloat
    var below: CGFloat

    static let current: WorkoutLayout = {
        let height = WKInterfaceDevice.current().screenBounds.height
        if height < 220 { return WorkoutLayout(timer: 30, value: 20, spacing: 3, above: 2, below: 2) }
        if height < 230 { return WorkoutLayout(timer: 32, value: 22, spacing: 4, above: 2, below: 8) }
        return WorkoutLayout(timer: 36, value: 24, spacing: 6, above: 4, below: 8)
    }()
}

/// Идущая тренировка: время, пульс, калории, у ходьбы — расстояние, и кнопка «Завершить».
struct WorkoutScreen: View {
    @EnvironmentObject private var model: WatchModel
    @State private var confirming = false

    var body: some View {
        ScrollView {
            if let workout = model.workout {
                content(workout)
                    .padding(.horizontal, 4)
                    .padding(.bottom, WorkoutLayout.current.below)
            } else {
                MessageView(icon: "checkmark.circle", title: "Тренировка завершена", text: "")
            }
        }
        .navigationTitle(model.workout?.kind.title ?? "Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Завершить тренировку?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Завершить", role: .destructive) {
                model.endWorkout()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Она сохранится в «Здоровье».")
        }
    }

    private func content(_ workout: LiveWorkout) -> some View {
        let metrics = model.metrics
        let layout = WorkoutLayout.current
        return VStack(alignment: .leading, spacing: layout.spacing) {
            Text(workout.startedAt, style: .timer)
                .font(.watch(layout.timer, .bold, rounded: true))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
            metric(
                icon: "heart.fill", tint: WatchPalette.danger,
                value: metrics.heartRate.map { Numbers.format($0, digits: 0) }, unit: "уд/мин", name: "Пульс"
            )
            metric(
                icon: "flame.fill", tint: WatchPalette.warnSoftInk,
                value: metrics.kcal.map { Numbers.format($0, digits: 0) }, unit: "ккал", name: "Калории"
            )
            if workout.kind == .walk {
                metric(
                    icon: "figure.walk", tint: WatchPalette.accentText,
                    value: metrics.km.map { Numbers.format($0, digits: 2) }, unit: "км", name: "Расстояние"
                )
            }
            Button(model.workoutEnding ? "Завершаю…" : "Завершить") {
                confirming = true
            }
            .buttonStyle(.watch(.danger))
            .disabled(model.workoutEnding)
            .padding(.top, layout.above)
        }
    }

    private func metric(icon: String, tint: Color, value: String?, unit: String, name: String) -> some View {
        var spoken = "нет данных"
        if let value { spoken = value + " " + unit }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(value ?? "—")
                .font(.watch(WorkoutLayout.current.value, .bold, rounded: true))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.ink)
            Text(unit)
                .font(.watch(13))
                .foregroundStyle(WatchPalette.ink3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(spoken)")
    }
}
