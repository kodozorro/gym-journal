import SwiftUI
import WatchKit

// Оформление приложения на часах. Экран часов всегда тёмный, поэтому цвета взяты из тёмной темы
// веб-приложения (css/app.css). Фон страницы на часах чёрный: так экран сливается с корпусом.

/// Цвета по ролям: те же названия, что в приложении для iPhone.
enum WatchPalette {
    static let surface = Color(hex: 0x1A1A19)
    static let surface2 = Color(hex: 0x262624)
    static let ink = Color(hex: 0xF0EFEC)
    static let ink2 = Color(hex: 0xC3C2B7)
    static let ink3 = Color(hex: 0xA3A198)
    static let line = Color(hex: 0x2C2C2A)
    static let lineStrong = Color(hex: 0x77756E)
    static let accent = Color(hex: 0x2672CF)
    static let accentInk = Color(hex: 0xFFFFFF)
    static let accentText = Color(hex: 0x86B6EF)
    static let accentSoft = Color(hex: 0x163A6B)
    static let accentSoftInk = Color(hex: 0xCDE2FB)
    static let mark = Color(hex: 0x3987E5)
    static let markTrack = Color(hex: 0x184F95)
    static let ok = Color(hex: 0x4CC24C)
    static let okSoft = Color(hex: 0x10301A)
    static let okSoftInk = Color(hex: 0x7FD67F)
    static let warnSoft = Color(hex: 0x3A2C05)
    static let warnSoftInk = Color(hex: 0xFAD78A)
    static let danger = Color(hex: 0xF08A8A)
    static let dangerFill = Color(hex: 0xC23030)
}

extension Color {
    /// Цвет из записи 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Шрифт системы заданного размера. Числа набраны округлым начертанием, как на циферблатах.
    static func watch(_ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false) -> Font {
        .system(size: size, weight: weight, design: rounded ? .rounded : .default)
    }
}

/// Размеры, общие для экранов часов.
enum WatchMetrics {
    static let radius: CGFloat = 14
    /// Высота главной кнопки: под палец, но не больше, чем нужно маленькому экрану.
    static let button: CGFloat = 42
    /// Маленький экран: часы 40 и 41 мм. На нём числа и подписи чуть мельче.
    static let compact = WKInterfaceDevice.current().screenBounds.height < 220
}

// MARK: Кнопки

/// Кнопка во всю ширину: главная, спокойная, серая или красная.
struct WatchButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case soft
        case plain
        case danger
    }

    var kind: Kind = .plain
    var height: CGFloat = WatchMetrics.button
    /// Размер шрифта подписи.
    var size: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        WatchButtonBody(configuration: configuration, kind: kind, height: height, size: size)
    }
}

private struct WatchButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: WatchButtonStyle.Kind
    let height: CGFloat
    let size: CGFloat
    @Environment(\.isEnabled) private var enabled

    private var fill: Color {
        switch kind {
        case .primary: return WatchPalette.accent
        case .soft: return WatchPalette.accentSoft
        case .plain: return WatchPalette.surface2
        case .danger: return WatchPalette.dangerFill
        }
    }

    private var ink: Color {
        switch kind {
        case .primary: return WatchPalette.accentInk
        case .soft: return WatchPalette.accentSoftInk
        case .plain: return WatchPalette.ink
        case .danger: return Color.white
        }
    }

    var body: some View {
        configuration.label
            .font(.watch(size, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: RoundedRectangle(cornerRadius: height / 2))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == WatchButtonStyle {
    static func watch(
        _ kind: WatchButtonStyle.Kind = .plain, height: CGFloat = WatchMetrics.button, size: CGFloat = 16
    ) -> WatchButtonStyle {
        WatchButtonStyle(kind: kind, height: height, size: size)
    }
}

/// Строка списка: плашка с содержимым, при нажатии слегка темнеет.
struct WatchRowStyle: ButtonStyle {
    var fill: Color = WatchPalette.surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: WatchMetrics.radius))
            .brightness(configuration.isPressed ? 0.08 : 0)
            .contentShape(Rectangle())
    }
}

/// Круглая кнопка со значком: «меньше» и «больше».
struct WatchRoundStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.watch(17, .bold))
            .foregroundStyle(WatchPalette.ink)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? WatchPalette.accentSoft : WatchPalette.surface2, in: Circle())
            .contentShape(Circle())
    }
}
