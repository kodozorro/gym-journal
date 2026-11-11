import Foundation

/// Что показать по кнопке «i»: фото тренажёра, рисунок и подсказки.
/// Пустые строки и nil там, где показать нечего.
public struct ExerciseGuide: Equatable, Sendable {
    /// Название тренажёра из таблицы.
    public var machine: String
    /// Имя фотографии тренажёра без расширения или nil.
    public var photo: String?
    /// По чему тренажёр узнать в зале.
    public var look: String
    /// Имя рисунка упражнения или пустая строка.
    public var art: String
    /// Откуда смотрим, если не сбоку.
    public var view: String
    public var legend: String
    public var muscles: String
    public var steps: [String]
    public var rule: String
    /// Адрес поиска фото, если своего фото нет.
    public var search: String
    /// Тип тренажёра: общие слова без марки, например «treadmill».
    public var machineType: String
    /// Ходьба: к ней не относится правило о запасе повторов.
    public var cardio: Bool
}

/// Справочник упражнений: по названиям из таблицы подбирает фото тренажёра, рисунок и подсказки.
///
/// Тренажёр узнаётся по типу: «… Seated Leg Press» любой фирмы — жим ногами сидя. Марок здесь
/// нет, только общие слова. От типа тренажёра зависят фото и рисунок, от названия упражнения —
/// то, что на этом тренажёре делают: на одном тренажёре бывает два упражнения.
///
/// Подсказки — общепринятые правила работы на тренажёрах. Программу они не меняют: число
/// подходов, повторы и вес по-прежнему берутся из таблицы.
public enum Guide {
    /// Размер фотографий: все файлы одинаковые, 4:3.
    public static let photoWidth = 800
    public static let photoHeight = 600

    private static let quads = "Передняя поверхность бедра и ягодицы, помогает задняя поверхность бедра."
    private static let sitToRow = "Сядьте на скамью, стопы поставьте в упоры, колени слегка согните."
    private static let rowBack = "Плавно выпрямите руки. Корпус держите почти вертикально, без раскачки."

    struct Machine {
        var id: String
        var test: Rx
        var photo: String?
        var look: String
    }

    struct Move {
        var art: String
        var view: String = ""
        var legend: String = ""
        var cardio: Bool = false
        var muscles: String
        var steps: [String]
    }

    /// Типы тренажёров в порядке проверки: более точное название стоит раньше общего.
    static let machines: [Machine] = [
        Machine(
            id: "seated-leg-press", test: Rx(#"seated\s+leg\s+press"#), photo: "seated-leg-press",
            look: "Сиденье со спинкой едет по наклонным направляющим, платформа для ног неподвижна. Груз — стек плиток."
        ),
        Machine(
            id: "leg-press", test: Rx(#"leg\s+press"#), photo: "leg-press",
            look: "Низкая наклонная спинка и большая платформа на направляющих под 45°. Груз — диски."
        ),
        Machine(
            id: "hack-press", test: Rx(#"hack"#), photo: "hack-press",
            look: "Наклонная каретка со спинкой и подушками для плеч, внизу платформа для стоп. Груз — диски."
        ),
        Machine(
            id: "leg-curl", test: Rx(#"kneeling\s+leg\s+curl"#), photo: "leg-curl",
            look: "Сверху подушка для предплечий с рукоятями, под ней наклонные подушки для бёдер, внизу валики на красных рычагах. Груз — диски."
        ),
        Machine(
            id: "chest-press", test: Rx(#"chest\s+press"#), photo: "chest-press",
            look: "Сиденье с высокой спинкой, по бокам красные рычаги с рукоятями на уровне груди. Груз — стек плиток."
        ),
        Machine(
            id: "low-pulley", test: Rx(#"low\s+pulley|cable\s+row|seated\s+row"#), photo: "low-pulley",
            look: "Длинная скамья, упоры для стоп и блок с тросом на стойке. Груз — стек плиток."
        ),
        Machine(
            id: "shoulder-press", test: Rx(#"shoulder\s+press"#), photo: "shoulder-press",
            look: "Сиденье с высокой спинкой, на уровне плеч длинный красный рычаг с рукоятями. Груз — стек плиток."
        ),
        // сведение и обратные разведения на одном тренажёре; для тренажёра только под сведение фото нет
        Machine(
            id: "pec-deck",
            test: Rx(#"pec[\s-]*deck?\b.*(?:reverse|rear)|(?:reverse|rear).*pec[\s-]*deck?\b"#),
            photo: "pec-deck",
            look: "Сиденье с узкой подушкой, сверху красные рычаги, которые опускаются к рукоятям."
        ),
        Machine(id: "pec-deck", test: Rx(#"pec[\s-]*deck?\b"#), photo: nil, look: ""),
        Machine(
            id: "lateral-raise", test: Rx(#"lateral\s+raise"#), photo: "lateral-raise",
            look: "Высокая стойка с красными рычагами на уровне плеч, внизу платформа, которая ставится по росту. Груз — стек плиток."
        ),
        Machine(id: "treadmill", test: Rx(#"дорожк|treadmill"#), photo: nil, look: ""),
    ]

    /// Упражнения: рисунок, мышцы и порядок выполнения.
    static let moves: [String: Move] = [
        "seated-leg-press": Move(
            art: "seated-leg-press",
            muscles: quads,
            steps: [
                "Сядьте, спину и таз прижмите к спинке. Стопы поставьте на платформу на ширине плеч.",
                "Выжимайте платформу ногами: сиденье отъедет назад. Колени в конце не выпрямляйте до упора.",
                "Плавно возвращайтесь, пока колени не согнутся примерно под прямым углом. Таз от сиденья не отрывайте.",
            ]
        ),
        "leg-press": Move(
            art: "leg-press",
            muscles: quads,
            steps: [
                "Лягте на спинку, стопы поставьте на платформу на ширине плеч.",
                "Выжмите платформу и уберите упоры рукоятями у сиденья.",
                "Плавно опускайте платформу, пока колени не согнутся примерно под прямым углом. Поясницу от спинки не отрывайте.",
                "Выжимайте вверх, колени до упора не выпрямляйте. После подхода верните упоры на место.",
            ]
        ),
        "hack-press": Move(
            art: "hack-press",
            muscles: "Передняя поверхность бедра и ягодицы.",
            steps: [
                "Встаньте на платформу, спину прижмите к спинке, плечи подведите под подушки. Стопы на ширине плеч.",
                "Выпрямите ноги и уберите упоры рукоятями у плеч.",
                "Плавно приседайте, спину от спинки не отрывайте. Глубину подбирайте без боли в коленях, начинайте с небольшой.",
                "Выжимайте каретку вверх, колени до упора не выпрямляйте. После подхода верните упоры на место.",
            ]
        ),
        "leg-curl": Move(
            art: "leg-curl",
            muscles: "Задняя поверхность бедра.",
            steps: [
                "Обопритесь предплечьями на верхнюю подушку. Бедро рабочей ноги прижмите к наклонной подушке, колено второй ноги поставьте на свою подушку. Валик должен лечь чуть выше пятки.",
                "Согните ногу: пятка идёт к ягодице. Таз не поднимайте, поясницу не прогибайте.",
                "Плавно опустите валик, вес не бросайте. Сделайте все повторы одной ногой, потом другой.",
            ]
        ),
        "chest-press": Move(
            art: "chest-press",
            muscles: "Грудные мышцы, передняя часть плеч и трицепс.",
            steps: [
                "Выставьте сиденье так, чтобы рукояти были на уровне середины груди. Спину и лопатки прижмите к спинке.",
                "Выжмите рукояти вперёд, локти до упора не выпрямляйте.",
                "Плавно верните рукояти к груди. Плечи к ушам не поднимайте.",
            ]
        ),
        "shoulder-press": Move(
            art: "shoulder-press",
            muscles: "Дельтовидные мышцы и трицепс.",
            steps: [
                "Выставьте сиденье так, чтобы рукояти были на уровне плеч. Спину прижмите к спинке.",
                "Выжмите рукояти вверх, локти до упора не выпрямляйте.",
                "Плавно опустите рукояти до уровня плеч. Поясницу не прогибайте.",
            ]
        ),
        "row-narrow": Move(
            art: "row-narrow",
            muscles: "Широчайшие мышцы спины, мышцы между лопатками и бицепс.",
            steps: [
                "\(sitToRow) Возьмите узкую рукоять.",
                "Тяните рукоять к животу. Локти идут назад вдоль корпуса, лопатки сводятся.",
                rowBack,
            ]
        ),
        "row-wide": Move(
            art: "row-wide",
            muscles: "Мышцы между лопатками и задняя часть плеч, помогают широчайшие мышцы и бицепс.",
            steps: [
                "\(sitToRow) Возьмите длинную рукоять хватом шире плеч.",
                "Тяните рукоять к низу груди. Локти идут в стороны и назад, лопатки сводятся.",
                rowBack,
            ]
        ),
        "pec-fly": Move(
            art: "pec-fly",
            view: "Вид сверху.",
            muscles: "Грудные мышцы и передняя часть плеч.",
            steps: [
                "Рычаги разведите в стороны. Сядьте спиной к подушке и возьмитесь за рукояти, локти слегка согните.",
                "Сведите руки перед грудью по дуге. Локти остаются слегка согнутыми.",
                "Плавно разведите руки, но не дальше линии плеч.",
            ]
        ),
        "reverse-fly": Move(
            art: "reverse-fly",
            view: "Вид сверху.",
            muscles: "Задняя часть плеч и мышцы между лопатками.",
            steps: [
                "Рычаги переставьте вперёд. Сядьте лицом к подушке, прижмитесь к ней грудью и возьмитесь за рукояти на уровне плеч.",
                "Разведите руки в стороны и назад по дуге, локти слегка согнуты. Плечи к ушам не поднимайте.",
                "Плавно верните руки вперёд, вес не бросайте.",
            ]
        ),
        "lateral-raise": Move(
            art: "lateral-raise",
            view: "Вид спереди.",
            muscles: "Средняя часть дельтовидных мышц.",
            steps: [
                "Встаньте на платформу между рычагами. Высоту платформы подберите так, чтобы оси рычагов были на уровне плеч.",
                "Подушки рычагов должны лечь на руки снаружи, у локтей. Поднимайте локти в стороны до уровня плеч.",
                "Плавно опустите руки. Плечи к ушам не поднимайте, корпус не раскачивайте.",
            ]
        ),
        "treadmill": Move(
            art: "treadmill",
            legend: "Наклон на рисунке больше настоящего: так его видно.",
            cardio: true,
            muscles: "Сердце и дыхание, мышцы ног и ягодиц.",
            steps: [
                "Наклон и расстояние возьмите из плана. Идите шагом, без бега.",
                "Темп такой, чтобы можно было говорить, но не петь.",
                "Не висите на поручнях. Если болят колени или стопы, убавьте скорость и прибавьте наклон.",
            ]
        ),
    ]

    private static let wideRx = Rx("широк")
    private static let reverseRx = Rx("обратн")
    private static let flyRx = Rx("сведени")

    /// Какое упражнение делают на тренажёре: единственное или выбранное по названию.
    static func moveOn(machine id: String, exercise: String) -> String {
        switch id {
        case "low-pulley":
            return wideRx.test(exercise) ? "row-wide" : "row-narrow"
        case "pec-deck":
            return reverseRx.test(exercise) ? "reverse-fly" : flyRx.test(exercise) ? "pec-fly" : ""
        default:
            return id
        }
    }

    /// Если тренажёр в таблице не указан, упражнение узнаётся по своему названию.
    static let byName: [(test: Rx, move: String)] = [
        (Rx("^жим ногами сидя"), "seated-leg-press"),
        (Rx("^жим ногами"), "leg-press"),
        (Rx("гакк"), "hack-press"),
        (Rx("сгибание ног"), "leg-curl"),
        (Rx("жим от груди"), "chest-press"),
        (Rx("жим вверх"), "shoulder-press"),
        (Rx("тяга сидя.*широк"), "row-wide"),
        (Rx("тяга сидя"), "row-narrow"),
        (Rx("обратн.*разведени"), "reverse-fly"),
        (Rx("сведение рук"), "pec-fly"),
        (Rx("разведение рук в стороны"), "lateral-raise"),
        (Rx("^ходьба"), "treadmill"),
    ]

    public static let strengthRule =
        "Вес берите такой, чтобы в конце подхода оставалось 2–3 повтора в запасе. Амплитуда полная, но без боли."
    // «яркая», а не «тёмная»: в тёмной теме фигура светлая
    public static let legend = "Яркая и бледная фигуры — крайние положения, стрелка — рабочее усилие."

    private static let spacesRx = Rx(#"\s+"#)
    /// Знаки, которые в адресе не кодируются: латинские буквы, цифры и - _ . ! ~ * ' ( )
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    static func clean(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        return spacesRx.replace(lowered, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Тип тренажёра по названию из таблицы или nil.
    static func machine(named name: String) -> Machine? {
        let text = clean(name)
        if text.isEmpty { return nil }
        return machines.first { $0.test.test(text) }
    }

    /// Тип тренажёра общими словами («treadmill», «leg-press») или пустая строка.
    public static func machineType(_ name: String) -> String {
        machine(named: name)?.id ?? ""
    }

    /// Что показать по кнопке «i» для строки журнала.
    public static func guide(exercise: String, machine name: String) -> ExerciseGuide {
        let machineName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let exerciseName = clean(exercise)
        let kind = Guide.machine(named: machineName)

        var id = ""
        if let kind {
            id = moveOn(machine: kind.id, exercise: exerciseName)
        } else if machineName.isEmpty {
            id = byName.first { $0.test.test(exerciseName) }?.move ?? ""
        }
        let move = moves[id]
        let photo = kind?.photo
        let cardio = move?.cardio ?? false

        var search = ""
        // фото тренажёра в приложении нет: его можно поискать по названию. Дорожку искать незачем.
        if !machineName.isEmpty, photo == nil, !cardio {
            let query = machineName.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
            search = "https://www.google.com/search?tbm=isch&q=\(query)"
        }

        var legendText = ""
        if let move { legendText = move.legend.isEmpty ? Guide.legend : move.legend }

        return ExerciseGuide(
            machine: machineName,
            photo: photo,
            look: kind?.look ?? "",
            art: move?.art ?? "",
            view: move?.view ?? "",
            legend: legendText,
            muscles: move?.muscles ?? "",
            steps: move?.steps ?? [],
            rule: (move != nil && !cardio) ? strengthRule : "",
            search: search,
            machineType: kind?.id ?? "",
            cardio: cardio
        )
    }

    /// Все фотографии справочника: для проверки, что файлы на месте.
    public static var photoNames: [String] {
        var seen = Set<String>()
        return machines.compactMap { $0.photo }.filter { seen.insert($0).inserted }
    }

    /// Все рисунки, на которые ссылается справочник.
    public static var artNames: [String] {
        var seen = Set<String>()
        return moves.values.map { $0.art }.filter { seen.insert($0).inserted }.sorted()
    }
}
