import Foundation

/// Ось графика: границы, шаг и деления.
public struct AxisScale: Equatable, Sendable {
    public var lo: Double
    public var hi: Double
    public var step: Double
    public var ticks: [Double]

    /// Линейный перевод значения из отрезка [lo, hi] в отрезок [from, to].
    public func position(_ value: Double, from: Double, to: Double) -> Double {
        Scales.linear(value, lo, hi, from, to)
    }
}

/// Шкалы для графиков: «круглые» деления оси и перевод значения в точки экрана.
public enum Scales {
    /// Шаг деления из ряда 1, 2, 2.5, 5, 10 × 10ⁿ.
    public static func niceStep(_ span: Double, count: Double = 4) -> Double {
        guard span > 0, count > 0 else { return 1 }
        let raw = span / count
        let power = pow(10, log10(raw).rounded(.down))
        let n = raw / power
        let nice: Double = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10
        return nice * power
    }

    private static func clean(_ value: Double) -> Double {
        Numbers.roundHalfUp(value * 1e6) / 1e6
    }

    /// Ось, которая охватывает значения от min до max.
    /// fromZero — ось начинается с нуля (столбцы).
    public static func nice(_ minimum: Double, _ maximum: Double, count: Double = 4, fromZero: Bool = false) -> AxisScale {
        var lo = fromZero ? 0 : Swift.min(minimum, maximum)
        var hi = Swift.max(minimum, maximum)
        if !lo.isFinite || !hi.isFinite {
            lo = 0
            hi = 1
        }
        if hi == lo {
            // одна точка: ось вокруг неё, но не ниже нуля
            let pad = hi == 0 ? 1 : abs(hi) * 0.1
            lo = fromZero ? 0 : Swift.max(0, lo - pad)
            hi += pad
        }
        let step = niceStep(hi - lo, count: count)
        let first = (lo / step + 1e-9).rounded(.down) * step
        var last = (hi / step - 1e-9).rounded(.up) * step
        if last == first { last = first + step }
        var ticks: [Double] = []
        var value = first
        while value <= last + step * 1e-6 {
            ticks.append(clean(value))
            value += step
        }
        return AxisScale(lo: clean(first), hi: clean(last), step: clean(step), ticks: ticks)
    }

    /// Линейный перевод значения из отрезка [d0, d1] в отрезок [r0, r1].
    public static func linear(_ value: Double, _ d0: Double, _ d1: Double, _ r0: Double, _ r1: Double) -> Double {
        let span = d1 - d0
        return span == 0 ? (r0 + r1) / 2 : r0 + ((value - d0) / span) * (r1 - r0)
    }
}
