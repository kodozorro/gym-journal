import SwiftUI

// Значки те же, что в веб-приложении: контурные, на поле 24 × 24, рисуются цветом текста.
// Их пути лежат в Resources/icons.json, файл делает ios/tools/generate.mjs из js/ui/icons.js.

/// Путь из простых команд: M, L, C, Q и Z; числа идут подряд.
struct Outline: Decodable {
    let o: String
    let n: [Double]

    func path(scale: Double = 1) -> Path {
        var path = Path()
        var index = 0
        func point() -> CGPoint {
            guard index + 1 < n.count else { return .zero }
            let value = CGPoint(x: n[index] * scale, y: n[index + 1] * scale)
            index += 2
            return value
        }
        for op in o {
            switch op {
            case "M":
                path.move(to: point())
            case "L":
                path.addLine(to: point())
            case "C":
                let first = point()
                let second = point()
                path.addCurve(to: point(), control1: first, control2: second)
            case "Q":
                let control = point()
                path.addQuadCurve(to: point(), control: control)
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}

private struct IconFile: Decodable {
    let size: Double
    let stroke: Double
    let items: [String: [Outline]]
}

enum IconStore {
    private static let file: IconFile? = {
        guard let url = Bundle.main.url(forResource: "icons", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IconFile.self, from: data)
    }()

    static let size: Double = file?.size ?? 24
    static let stroke: Double = file?.stroke ?? 2

    static func outlines(_ name: String) -> [Outline] {
        file?.items[name] ?? []
    }
}

private struct IconShape: Shape {
    let name: String

    func path(in rect: CGRect) -> Path {
        let scale = Double(min(rect.width, rect.height)) / IconStore.size
        var path = Path()
        for outline in IconStore.outlines(name) {
            path.addPath(outline.path(scale: scale))
        }
        return path
    }
}

/// Значок по имени из веб-приложения: `Icon("check")`.
struct Icon: View {
    private let name: String
    private let size: CGFloat

    init(_ name: String, size: CGFloat = 24) {
        self.name = name
        self.size = size
    }

    var body: some View {
        IconShape(name: name)
            .stroke(style: StrokeStyle(
                lineWidth: CGFloat(IconStore.stroke) * size / CGFloat(IconStore.size), lineCap: .round, lineJoin: .round
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
