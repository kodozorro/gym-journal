import SwiftUI

// Рисунки упражнений из линий: два крайних положения и стрелка усилия. Фигуры лежат в
// Resources/art.json, файл делает ios/tools/generate.mjs из js/ui/art.js. В данных нет цветов,
// только роли фигур («frame», «body»): цвет роли задаётся здесь, тот же, что у класса
// art__… в css/app.css, поэтому рисунок перекрашивается вместе с темой.

/// Фигура рисунка или группа фигур.
private struct ArtNode: Decodable {
    /// Роли: чем фигура закрашена и обведена.
    let c: [String]
    let o: String?
    let n: [Double]?
    /// Толщина линии.
    let w: Double?
    let dash: [Double]?
    /// Вложенные фигуры: узел — группа.
    let ch: [ArtNode]?
}

private struct ArtFile: Decodable {
    let width: Double
    let height: Double
    let items: [String: [ArtNode]]
}

private enum ArtStore {
    static let file: ArtFile? = {
        guard let url = Bundle.main.url(forResource: "art", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ArtFile.self, from: data)
    }()
}

/// Чем рисуется фигура.
private struct ArtPaint {
    var fill: Color?
    var stroke: Color?
    /// Скруглённые концы и стыки линий.
    var round = false
    /// Порядок правила в css/app.css: при нескольких ролях побеждает более позднее.
    var rank = 0
}

private enum ArtRoles {
    /// Прозрачность группы или 1.
    static func opacity(_ role: String) -> Double {
        switch role {
        case "ghost":
            // второе крайнее положение
            return 0.3
        case "below":
            // то, что на виде сверху лежит ниже рук
            return 0.5
        default:
            return 1
        }
    }

    static func paint(_ role: String) -> ArtPaint? {
        switch role {
        case "floor":
            return ArtPaint(stroke: Palette.lineStrong, round: true)
        case "frame":
            return ArtPaint(stroke: Palette.lineStrong, round: true)
        case "pad":
            return ArtPaint(stroke: Palette.ink3, round: true)
        case "cable":
            return ArtPaint(stroke: Palette.ink3, round: true)
        case "move":
            return ArtPaint(stroke: Palette.artMove, round: true)
        case "body":
            return ArtPaint(stroke: Palette.ink, round: true)
        case "halo":
            // просвет вокруг руки, чтобы она не сливалась с корпусом
            return ArtPaint(stroke: Palette.page, round: true)
        case "arrow":
            return ArtPaint(stroke: Palette.mark, round: true)
        case "fill-body":
            return ArtPaint(fill: Palette.ink, rank: 1)
        case "fill-pad":
            return ArtPaint(fill: Palette.ink3, rank: 1)
        case "fill-move":
            return ArtPaint(fill: Palette.artMove, rank: 1)
        case "fill-arrow":
            return ArtPaint(fill: Palette.mark, rank: 1)
        case "fill-panel":
            return ArtPaint(fill: Palette.page, rank: 1)
        case "head":
            return ArtPaint(fill: Palette.ink, stroke: Palette.page, rank: 2)
        case "tower":
            return ArtPaint(fill: Palette.surface, stroke: Palette.lineStrong, rank: 2)
        case "seat":
            return ArtPaint(fill: Palette.surface, stroke: Palette.lineStrong, rank: 2)
        case "hub":
            return ArtPaint(fill: Palette.page, stroke: Palette.ink3, rank: 2)
        default:
            return nil
        }
    }

    /// Итог для фигуры с несколькими ролями: правила применяются в порядке стилей веб-приложения.
    static func combined(_ roles: [String]) -> ArtPaint {
        var out = ArtPaint()
        let paints = roles.compactMap { paint($0) }.sorted { $0.rank < $1.rank }
        for item in paints {
            if item.rank == 0 {
                // правило линии убирает заливку
                out.fill = nil
                out.round = true
            }
            if let fill = item.fill { out.fill = fill }
            if let stroke = item.stroke { out.stroke = stroke }
        }
        return out
    }
}

/// Рисунок упражнения по имени из справочника.
struct ArtView: View {
    let name: String

    static func exists(_ name: String) -> Bool {
        ArtStore.file?.items[name] != nil
    }

    var body: some View {
        let width = ArtStore.file?.width ?? 320
        let height = ArtStore.file?.height ?? 240
        Canvas { context, size in
            guard let nodes = ArtStore.file?.items[name], width > 0 else { return }
            var scaled = context
            let scale = size.width / CGFloat(width)
            scaled.scaleBy(x: scale, y: scale)
            ArtView.draw(nodes, in: &scaled)
        }
        .aspectRatio(CGFloat(width / height), contentMode: .fit)
    }

    private static func draw(_ nodes: [ArtNode], in context: inout GraphicsContext) {
        for node in nodes {
            if let children = node.ch {
                let opacity = node.c.map { ArtRoles.opacity($0) }.min() ?? 1
                // группа бледнеет целиком: её фигуры сначала рисуются на отдельном слое
                var group = context
                group.opacity = opacity
                group.drawLayer { layer in
                    draw(children, in: &layer)
                }
                continue
            }
            guard let ops = node.o, let numbers = node.n else { continue }
            let path = Outline(o: ops, n: numbers).path()
            let paint = ArtRoles.combined(node.c)
            if let fill = paint.fill {
                context.fill(path, with: .color(fill))
            }
            if let stroke = paint.stroke {
                let style = StrokeStyle(
                    lineWidth: CGFloat(node.w ?? 1),
                    lineCap: paint.round ? .round : .butt,
                    lineJoin: paint.round ? .round : .miter,
                    dash: (node.dash ?? []).map { CGFloat($0) }
                )
                context.stroke(path, with: .color(stroke), style: style)
            }
        }
    }
}
