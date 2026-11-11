import SwiftUI
import UIKit

// Оформление: цвета по ролям, размеры и вид кнопок. Значения те же, что в css/app.css
// веб-приложения: два приложения должны выглядеть одинаково в светлой и тёмной теме.

/// Цвета по ролям. Каждый цвет сам меняется вместе с темой.
enum Palette {
    static let page = dynamic(0xF4F3EF, 0x0D0D0D)
    static let surface = dynamic(0xFCFCFB, 0x1A1A19)
    static let surface2 = dynamic(0xEEEDE9, 0x262624)
    static let ink = dynamic(0x0B0B0B, 0xF0EFEC)
    static let ink2 = dynamic(0x52514E, 0xC3C2B7)
    static let ink3 = dynamic(0x65635E, 0xA3A198)
    static let line = dynamic(0xE1E0D9, 0x2C2C2A)
    static let lineStrong = dynamic(0x8A8880, 0x77756E)
    static let accent = dynamic(0x256ABF, 0x2672CF)
    static let accentInk = dynamic(0xFFFFFF, 0xFFFFFF)
    static let accentText = dynamic(0x1C5CAB, 0x86B6EF)
    static let accentSoft = dynamic(0xE3EEFC, 0x163A6B)
    static let accentSoftInk = dynamic(0x104281, 0xCDE2FB)
    static let mark = dynamic(0x2A78D6, 0x3987E5)
    static let markTrack = dynamic(0xB7D3F6, 0x184F95)
    static let ok = dynamic(0x006300, 0x4CC24C)
    static let okSoft = dynamic(0xE1F2E1, 0x10301A)
    static let okSoftInk = dynamic(0x005200, 0x7FD67F)
    static let warnSoft = dynamic(0xFDF0CF, 0x3A2C05)
    static let warnSoftInk = dynamic(0x5C3D00, 0xFAD78A)
    static let danger = dynamic(0xB42B2B, 0xF08A8A)
    static let dangerFill = dynamic(0xC23030, 0xC23030)
    static let dangerSoft = dynamic(0xFBE5E5, 0x3B1616)
    static let dangerSoftInk = dynamic(0x9B1F1F, 0xF5A3A3)
    static let artMove = dynamic(0xC8372D, 0xEB6156)
    /// Затемнение под листом.
    static let scrim = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.6)
            : UIColor(red: 11 / 255, green: 11 / 255, blue: 11 / 255, alpha: 0.45)
    })
    static let shadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.5)
            : UIColor(red: 11 / 255, green: 11 / 255, blue: 11 / 255, alpha: 0.18)
    })

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            Palette.solid(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func solid(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Размеры из css/app.css.
enum Metrics {
    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 12
    static let gap: CGFloat = 12
    static let pad: CGFloat = 16
    static let cardPad: CGFloat = 14
    /// Шире приложение не растягивается: на большом экране оно стоит посередине.
    static let maxWidth: CGFloat = 560
}

extension Font {
    /// Шрифт системы заданного размера. Размеры в пунктах равны размерам веб-приложения в px.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Выбранная в настройках тема: окну приложения задаётся светлый или тёмный вид, либо как в системе.
enum ThemeApplier {
    static func apply(_ style: UIUserInterfaceStyle) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

// MARK: Кнопки

/// Вид кнопки: как классы .btn, .btn--primary, .btn--soft и другие.
struct AppButtonStyle: ButtonStyle {
    enum Kind {
        /// Серая кнопка на карточке.
        case plain
        case primary
        case soft
        /// Без фона, цветом ссылки.
        case ghost
        case danger
        /// Кнопка на цветной плашке: фон карточки.
        case surface
    }

    var kind: Kind = .plain
    var small = false
    var block = false

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(configuration: configuration, kind: kind, small: small, block: block)
    }
}

private struct AppButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AppButtonStyle.Kind
    let small: Bool
    let block: Bool
    @Environment(\.isEnabled) private var enabled

    private var fill: Color {
        switch kind {
        case .plain: return Palette.surface2
        case .primary: return Palette.accent
        case .soft: return Palette.accentSoft
        case .ghost: return Color.clear
        case .danger: return Palette.dangerFill
        case .surface: return Palette.surface
        }
    }

    private var ink: Color {
        switch kind {
        case .plain, .surface: return Palette.ink
        case .primary: return Palette.accentInk
        case .soft: return Palette.accentSoftInk
        case .ghost: return Palette.accentText
        case .danger: return Color.white
        }
    }

    var body: some View {
        configuration.label
            .font(.app(small ? 15 : 17, .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .foregroundStyle(ink)
            .padding(.horizontal, small ? 14 : 18)
            .frame(maxWidth: block ? .infinity : nil, minHeight: small ? 44 : 52)
            .background(fill, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ kind: AppButtonStyle.Kind = .plain, small: Bool = false, block: Bool = false) -> AppButtonStyle {
        AppButtonStyle(kind: kind, small: small, block: block)
    }
}

/// Кнопка без собственного оформления: нажатие слегка затемняет её, выключенная бледнеет.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }
}

private struct PressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
}

/// Клавиша цифровой клавиатуры: при нажатии подсвечивается.
struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration)
    }
}

private struct KeyBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.app(26, .semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                configuration.isPressed ? Palette.accentSoft : Palette.surface2,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

// MARK: Карточка

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var vertical: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .padding(.vertical, vertical ?? padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.line, lineWidth: 1))
    }
}

extension View {
    /// Карточка: фон, тонкая рамка, скруглённые углы.
    func card(padding: CGFloat = Metrics.cardPad, vertical: CGFloat? = nil) -> some View {
        modifier(CardModifier(padding: padding, vertical: vertical))
    }
}
