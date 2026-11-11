import SwiftUI
import GymJournalCore

// Общие кусочки экранов: плашка с сообщением, полоса выполнения, строка дня, переключатели.
// Размеры и цвета — из css/app.css веб-приложения.

/// Текст с жирным началом: «Заголовок. Пояснение».
func leadText(_ lead: String, _ text: String, size: CGFloat = 15) -> AttributedString {
    var head = AttributedString(lead)
    head.font = Font.app(size, .bold)
    var tail = AttributedString(text)
    tail.font = Font.app(size)
    return head + tail
}

/// Заголовок раздела маленькими прописными буквами.
struct CapsTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.app(13, .bold))
            .tracking(0.78)
            .foregroundStyle(Palette.ink2)
    }
}

// MARK: Плашка

enum BannerTone {
    case info, warn, bad
}

/// Плашка с сообщением и, если нужно, кнопкой под ним.
struct BannerView<Actions: View>: View {
    var tone: BannerTone
    var lead: String
    var text: String
    private let actions: Actions

    init(tone: BannerTone = .info, lead: String = "", text: String, @ViewBuilder actions: () -> Actions) {
        self.tone = tone
        self.lead = lead
        self.text = text
        self.actions = actions()
    }

    private var fill: Color {
        switch tone {
        case .info: return Palette.accentSoft
        case .warn: return Palette.warnSoft
        case .bad: return Palette.dangerSoft
        }
    }

    private var ink: Color {
        switch tone {
        case .info: return Palette.accentSoftInk
        case .warn: return Palette.warnSoftInk
        case .bad: return Palette.dangerSoftInk
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(leadText(lead, text))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
    }
}

extension BannerView where Actions == EmptyView {
    init(tone: BannerTone = .info, lead: String = "", text: String) {
        self.init(tone: tone, lead: lead, text: text) { EmptyView() }
    }
}

// MARK: Полоса выполнения

/// Полоса «сколько сделано». Доля — от 0 до 1.
struct MeterView: View {
    var share: Double
    var label: String

    var body: some View {
        let value = (min(1, max(0, share)) * 100).rounded() / 100
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.markTrack)
                Capsule().fill(Palette.mark).frame(width: geometry.size.width * value)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) %")
    }
}

// MARK: Строка дня

/// Метка состояния дня. Пропущенный день ничем не выделяется: пропуски — обычное дело,
/// запись можно сделать позже.
struct StatusChip: View {
    let status: DayStatus

    var body: some View {
        switch status {
        case .done:
            Icon("check", size: 16)
                .foregroundStyle(Palette.okSoftInk)
                .padding(5)
                .background(Palette.okSoft, in: Circle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("записано")
        case .partial:
            label("частично", fill: Palette.warnSoft, ink: Palette.warnSoftInk)
        case .today:
            label("сегодня", fill: Palette.accent, ink: Palette.accentInk)
        case .missed, .planned:
            Icon("chevronRight", size: 20)
                .foregroundStyle(Palette.ink3)
        }
    }

    private func label(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text)
            .font(.app(13, .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Строка дня в списках: дата, тренировка, состояние. Ведёт на экран дня.
struct DayRowView: View {
    @EnvironmentObject private var model: AppModel
    let day: JournalDay

    var body: some View {
        let isToday = day.date == model.today
        let status = Journal.dayStatus(day.rows, date: day.date, today: model.today)
        Button {
            model.go(isToday ? .today : .day(day.date))
        } label: {
            HStack(spacing: 10) {
                Text(Days.formatSheetDay(day.date))
                    .font(.app(15))
                    .foregroundStyle(isToday ? Palette.accentSoftInk : Palette.ink2)
                    .lineLimit(1)
                    .frame(width: 70, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Journal.workoutTitle(day.rows))
                        .font(.app(16, .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text(Present.daySummary(day.rows))
                        .font(.app(13))
                        .foregroundStyle(isToday ? Palette.accentSoftInk : Palette.ink2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(status: status)
            }
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 12))
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isToday ? Palette.accentSoft : Color.clear)
        }
        .buttonStyle(.press)
    }
}

/// Список дней одной карточкой: строки разделены тонкой линией.
struct DaysList: View {
    let days: [JournalDay]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                DayRowView(day: day)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// Список дней с заголовком: «Следующая тренировка», «Не записано раньше».
struct DaysSection: View {
    let title: String
    let days: [JournalDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CapsTitle(title)
                .padding(EdgeInsets(top: 0, leading: 2, bottom: 6, trailing: 2))
            DaysList(days: days)
        }
    }
}

// MARK: Пустой экран

/// Сообщение посреди экрана: заголовок, пояснение и, если нужно, кнопки.
struct EmptyState<Extra: View>: View {
    var title: String
    var text: String
    private let extra: Extra

    init(title: String = "", text: String, @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.text = text
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.app(20, .bold))
                    .foregroundStyle(Palette.ink)
            }
            Text(text)
                .font(.app(17))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            extra
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyState where Extra == EmptyView {
    init(title: String = "", text: String) {
        self.init(title: title, text: text) { EmptyView() }
    }
}

/// Шаги с номерами в кружках.
struct StepsList: View {
    let steps: [String]
    var size: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.app(15, .bold))
                        .foregroundStyle(Palette.accentSoftInk)
                        .frame(width: 28, height: 28)
                        .background(Palette.accentSoft, in: Circle())
                    Text(step)
                        .font(.app(size))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Кнопка, которая открывает страницу в браузере: инструкция, поиск фото.
struct LinkButton: View {
    @Environment(\.openURL) private var openURL
    let title: String
    let address: String
    var kind: AppButtonStyle.Kind = .ghost
    var small = false
    var block = false
    /// Значок «ссылка» после текста.
    var marked = true

    var body: some View {
        Button {
            if let url = URL(string: address) { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                if marked {
                    Icon("link", size: 20)
                }
            }
        }
        .buttonStyle(.app(kind, small: small, block: block))
        .accessibilityAddTraits(.isLink)
    }
}

/// Отметка «записано»: галочка в зелёном кружке.
struct DoneBadge: View {
    var body: some View {
        Icon("check", size: 18)
            .foregroundStyle(Palette.okSoftInk)
            .frame(width: 26, height: 26)
            .background(Palette.okSoft, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("записано")
    }
}

// MARK: Переключатели

/// Переключатель «включено — выключено». Кнопка выше нарисованного переключателя: попасть пальцем должно быть легко.
struct SwitchView: View {
    let label: String
    let isOn: Bool
    let action: (Bool) -> Void

    var body: some View {
        Button {
            action(!isOn)
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Palette.accent : Palette.lineStrong)
                    .frame(width: 56, height: 34)
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .offset(x: isOn ? 25 : 3)
            }
            .frame(width: 56, height: 44)
            .animation(.easeInOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.press)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "включено" : "выключено")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Вариант для выбора из нескольких.
struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// Выбор одного из нескольких вариантов в одну строку.
struct SegmentedView<Value: Hashable>: View {
    let label: String
    let options: [SegmentOption<Value>]
    let selection: Value
    let action: (Value) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let chosen = option.value == selection
                Button {
                    action(option.value)
                } label: {
                    Text(option.title)
                        .font(.app(15, .semibold))
                        .foregroundStyle(chosen ? Palette.ink : Palette.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(chosen ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(chosen ? Palette.line : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Кнопка-таблетка: шаг веса, готовое слово для заметки.
struct ChipButton: View {
    let title: String
    var chosen = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(15, .semibold))
                .foregroundStyle(chosen ? Palette.accentInk : Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 44)
                .background(chosen ? Palette.accent : Palette.surface2, in: Capsule())
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Раскладка «в строку с переносом»: таблетки переходят на следующую строку, когда не помещаются.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX + 0.5 {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Пары «название — значение» в два столбца.
struct KeyValues: View {
    let rows: [(name: String, value: String)]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(row.name)
                        .foregroundStyle(Palette.ink2)
                    Spacer(minLength: 0)
                    Text(row.value)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.trailing)
                }
                .font(.app(15))
            }
        }
    }
}

// MARK: Экран

/// Прокручиваемый экран: поля и промежутки как у .screen, прокрутка к началу и к нужной карточке.
struct ScreenScroll<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    /// Что показать у верхнего края, когда экран открылся: текущая неделя в плане.
    private let initialTarget: String?
    private let content: Content

    init(initialTarget: String? = nil, @ViewBuilder content: () -> Content) {
        self.initialTarget = initialTarget
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.gap) {
                    content
                }
                .padding(EdgeInsets(top: 6, leading: Metrics.pad, bottom: 28, trailing: Metrics.pad))
                .frame(maxWidth: Metrics.maxWidth)
                .frame(maxWidth: .infinity)
                .id("top")
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard let initialTarget else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(initialTarget, anchor: .top)
                }
            }
            .onChange(of: model.scrollTop) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: model.scrollTarget) { _, key in
                guard let key else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(key)
                }
                model.scrollTarget = nil
            }
        }
    }
}
