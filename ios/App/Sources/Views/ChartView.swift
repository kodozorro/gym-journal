import SwiftUI
import GymJournalCore

// Графики: линия «лучший вес по неделям» и столбцы «километры по неделям».
//
// Один ряд — один цвет, поэтому легенды нет: что нарисовано, сказано в заголовке карточки.
// Подписано только последнее значение, остальные показывает подсказка по касанию,
// а полные данные — таблица под графиком. Размеры те же, что в веб-приложении (js/ui/chart.js).

struct ChartPoint: Equatable {
    /// Номер недели.
    var x: Int
    var y: Double
    /// Значение словами: «42,5 кг».
    var value: String
    /// Подпись в подсказке: «неделя 3 · 9 ноя – 15 ноя».
    var title: String
}

/// Линия цели (для столбцов).
struct ChartGoal: Equatable {
    var value: Double
    var label: String
}

enum ChartKind {
    case line, bars
}

/// Геометрия графика: где какая неделя и какое значение.
private struct ChartFrame {
    static let height: CGFloat = 210
    static let top: CGFloat = 24
    static let right: CGFloat = 12
    static let bottom: CGFloat = 26
    static let left: CGFloat = 38
    static let minWidth: CGFloat = 240

    let width: CGFloat
    let bars: Bool
    let xMin: Int
    let xMax: Int
    let band: CGFloat
    let scale: AxisScale

    init(kind: ChartKind, points: [ChartPoint], xMin: Int, xMax: Int, goal: ChartGoal?, width: CGFloat) {
        self.width = max(ChartFrame.minWidth, width.rounded())
        bars = kind == .bars
        self.xMin = xMin
        self.xMax = max(xMin, xMax)
        let count = max(1, xMax - xMin + 1)
        band = (self.width - ChartFrame.left - ChartFrame.right) / CGFloat(count)
        let values = points.map { $0.y }
        let highest = max(values.max() ?? 0, goal?.value ?? -Double.infinity)
        scale = kind == .bars
            ? Scales.nice(0, highest, fromZero: true)
            : Scales.nice(values.min() ?? 0, highest)
    }

    var base: CGFloat { ChartFrame.height - ChartFrame.bottom }

    func x(_ week: Int) -> CGFloat {
        ChartFrame.left + band * (CGFloat(week - xMin) + 0.5)
    }

    func y(_ value: Double) -> CGFloat {
        CGFloat(scale.position(value, from: Double(base), to: Double(ChartFrame.top)))
    }

    /// Ближайшая к касанию точка.
    func nearest(_ points: [ChartPoint], to position: CGFloat) -> Int {
        var best = 0
        for (index, point) in points.enumerated() where abs(x(point.x) - position) < abs(x(points[best].x) - position) {
            best = index
        }
        return best
    }

    /// Недели, которые подписаны на оси: все, через одну или через три, смотря сколько места.
    var weekTicks: [Int] {
        let every = band >= 22 ? 1 : (band >= 11 ? 2 : 4)
        return (xMin...xMax).filter { ($0 - xMin) % every == 0 }
    }
}

struct ChartView: View {
    let kind: ChartKind
    /// Меняется вместе с набором данных: выделение точки сбрасывается.
    let id: String
    let points: [ChartPoint]
    let xMin: Int
    let xMax: Int
    var goal: ChartGoal?
    /// Описание для экранного диктора.
    let label: String
    /// Текст, когда данных нет.
    let empty: String

    @State private var selected: Int?

    var body: some View {
        if points.isEmpty {
            Text(empty)
                .font(.app(15))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 28)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusSmall)
                        .strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        } else {
            GeometryReader { geometry in
                let frame = ChartFrame(
                    kind: kind, points: points, xMin: xMin, xMax: xMax, goal: goal, width: geometry.size.width
                )
                let focus: Int? = selected.flatMap { points.indices.contains($0) ? $0 : nil }
                Canvas { context, _ in
                    draw(context, frame: frame, focus: focus)
                }
                .frame(width: frame.width, height: ChartFrame.height)
                .overlay(alignment: .topLeading) {
                    if let focus {
                        tip(points[focus], frame: frame)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let index = frame.nearest(points, to: value.location.x)
                        selected = selected == index ? nil : index
                    }
                )
            }
            .frame(height: ChartFrame.height)
            .onChange(of: id) { _, _ in
                selected = nil
            }
            .accessibilityElement()
            .accessibilityLabel(label)
        }
    }

    /// Подсказка над выбранной точкой: значение и неделя.
    private func tip(_ point: ChartPoint, frame: ChartFrame) -> some View {
        let x = min(frame.width - 80, max(80, frame.x(point.x)))
        let y = max(0, frame.y(point.y) - 12)
        return VStack(alignment: .leading, spacing: 0) {
            Text(point.value)
                .font(.app(16, .bold))
            Text(point.title)
                .font(.app(13))
        }
        .foregroundStyle(Palette.surface)
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 10))
        // подсказка стоит над точкой и по её центру
        .frame(width: 0, height: 0, alignment: .bottom)
        .offset(x: x, y: y)
        .allowsHitTesting(false)
    }

    // MARK: Рисование

    private func label(_ text: String, size: CGFloat, weight: Font.Weight, color: Color) -> Text {
        Text(text)
            .font(.app(size, weight))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    /// Подпись поверх линий и столбцов: обводка цветом карточки не даёт ей слиться с ними.
    private func haloText(
        _ context: GraphicsContext, _ text: String, size: CGFloat, weight: Font.Weight, color: Color,
        at point: CGPoint, anchor: UnitPoint
    ) {
        let halo = label(text, size: size, weight: weight, color: Palette.surface)
        for dx in [-2.0, 0.0, 2.0] {
            for dy in [-2.0, 0.0, 2.0] where dx != 0 || dy != 0 {
                context.draw(halo, at: CGPoint(x: point.x + dx, y: point.y + dy), anchor: anchor)
            }
        }
        context.draw(label(text, size: size, weight: weight, color: color), at: point, anchor: anchor)
    }

    private func segment(_ context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat = 1, dash: [CGFloat] = []) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    private func dot(_ context: GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color) {
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: box), with: .color(color))
    }

    private func draw(_ context: GraphicsContext, frame: ChartFrame, focus: Int?) {
        let left = ChartFrame.left
        let right = frame.width - ChartFrame.right
        let base = frame.base

        // деления по вертикали
        for tick in frame.scale.ticks {
            let y = frame.y(tick)
            if !(frame.bars && tick == frame.scale.lo) {
                segment(context, from: CGPoint(x: left, y: y), to: CGPoint(x: right, y: y), color: Palette.line)
            }
            context.draw(
                label(Numbers.format(tick), size: 12, weight: .regular, color: Palette.ink3),
                at: CGPoint(x: left - 8, y: y), anchor: .trailing
            )
        }
        segment(context, from: CGPoint(x: left, y: base), to: CGPoint(x: right, y: base), color: Palette.lineStrong)

        // недели
        for week in frame.weekTicks {
            context.draw(
                label(String(week), size: 12, weight: .regular, color: Palette.ink3),
                at: CGPoint(x: frame.x(week), y: ChartFrame.height - 3), anchor: .bottom
            )
        }

        if let goal {
            let y = frame.y(goal.value)
            segment(
                context, from: CGPoint(x: left, y: y), to: CGPoint(x: right, y: y),
                color: Palette.ink2, width: 1.5, dash: [5, 4]
            )
            haloText(
                context, goal.label, size: 12, weight: .semibold, color: Palette.ink2,
                at: CGPoint(x: right, y: y - 3), anchor: .bottomTrailing
            )
        }

        if frame.bars {
            let barWidth = min(24, max(6, frame.band * 0.62))
            for (index, point) in points.enumerated() where point.y > 0 {
                let x0 = frame.x(point.x) - barWidth / 2
                let y0 = frame.y(point.y)
                let radius = max(0, min(4, barWidth / 2, base - y0))
                var bar = Path()
                bar.move(to: CGPoint(x: x0, y: base))
                bar.addLine(to: CGPoint(x: x0, y: y0 + radius))
                bar.addQuadCurve(to: CGPoint(x: x0 + radius, y: y0), control: CGPoint(x: x0, y: y0))
                bar.addLine(to: CGPoint(x: x0 + barWidth - radius, y: y0))
                bar.addQuadCurve(to: CGPoint(x: x0 + barWidth, y: y0 + radius), control: CGPoint(x: x0 + barWidth, y: y0))
                bar.addLine(to: CGPoint(x: x0 + barWidth, y: base))
                bar.closeSubpath()
                context.fill(bar, with: .color(Palette.mark))
                if index == focus {
                    // выбранный столбец светлее
                    context.fill(bar, with: .color(Color.white.opacity(0.18)))
                }
            }
        } else {
            if let focus {
                let x = frame.x(points[focus].x)
                segment(context, from: CGPoint(x: x, y: ChartFrame.top), to: CGPoint(x: x, y: base), color: Palette.lineStrong)
            }
            if points.count > 1 {
                var line = Path()
                for (index, point) in points.enumerated() {
                    let place = CGPoint(x: frame.x(point.x), y: frame.y(point.y))
                    if index == 0 {
                        line.move(to: place)
                    } else {
                        line.addLine(to: place)
                    }
                }
                context.stroke(
                    line, with: .color(Palette.mark),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
            for point in points {
                let center = CGPoint(x: frame.x(point.x), y: frame.y(point.y))
                dot(context, at: center, radius: 5, color: Palette.surface)
                dot(context, at: center, radius: 3, color: Palette.mark)
            }
            if let focus {
                let center = CGPoint(x: frame.x(points[focus].x), y: frame.y(points[focus].y))
                dot(context, at: center, radius: 7.5, color: Palette.surface)
                dot(context, at: center, radius: 4.5, color: Palette.mark)
            }
        }

        // подписано только последнее значение; под подсказкой оно не нужно
        if let last = points.last, focus != points.count - 1 {
            let x = frame.x(last.x)
            let y = frame.y(last.y) - 7
            if x > frame.width - 40 {
                haloText(
                    context, last.value, size: 13, weight: .bold, color: Palette.ink,
                    at: CGPoint(x: min(frame.width - 2, x + 10), y: y), anchor: .bottomTrailing
                )
            } else if x < left + 24 {
                haloText(
                    context, last.value, size: 13, weight: .bold, color: Palette.ink,
                    at: CGPoint(x: x - 6, y: y), anchor: .bottomLeading
                )
            } else {
                haloText(
                    context, last.value, size: 13, weight: .bold, color: Palette.ink,
                    at: CGPoint(x: x, y: y), anchor: .bottom
                )
            }
        }
    }
}
