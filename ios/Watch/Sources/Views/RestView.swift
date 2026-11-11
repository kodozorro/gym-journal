import SwiftUI
import GymJournalCore

/// Отсчёт отдыха во весь экран: кольцо, оставшееся время и две кнопки.
///
/// Появляется сам, когда отдых запустили на часах или на телефоне, и сам уходит, когда отдых
/// кончился: в этот момент часы вибрируют, а под отсчётом уже открыто следующее упражнение.
struct RestOverlay: View {
    @EnvironmentObject private var model: WatchModel
    let rest: RestTimer

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: rest.startedAt, by: 0.25)) { context in
                let left = rest.left(now: context.date)
                ZStack {
                    Circle()
                        .stroke(WatchPalette.markTrack, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - rest.progress(now: context.date)))
                        .stroke(WatchPalette.mark, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(RestTimer.clock(left))
                            .font(.watch(34, .bold, rounded: true))
                            .monospacedDigit()
                            .foregroundStyle(WatchPalette.ink)
                        Text("отдых")
                            .font(.watch(13))
                            .foregroundStyle(WatchPalette.ink3)
                    }
                }
                .padding(5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Отдых, осталось \(RestTimer.clock(left))")
            }
            HStack(spacing: 6) {
                Button("+30 с") {
                    model.extendRest()
                }
                .buttonStyle(.watch(.plain, height: 38))
                Button("Стоп") {
                    model.stopRest()
                }
                .buttonStyle(.watch(.soft, height: 38))
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
