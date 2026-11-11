import SwiftUI
import UIKit
import GymJournalCore

// Листы поверх экрана: цифровая клавиатура, заметка, состояние синхронизации, справка об
// упражнении, подтверждение. Системный лист не используется: этот — своей высоты, с затемнением,
// а лист заметки прижат к верху экрана, как в веб-приложении.

struct SheetHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let sheet = model.sheet {
                    Palette.scrim
                        .ignoresSafeArea()
                        .onTapGesture {
                            model.closeSheet()
                        }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                        .zIndex(1)
                    SheetPanel(sheet: sheet, limit: geometry.size.height * 0.92)
                        .frame(maxWidth: Metrics.maxWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sheet.top ? .top : .bottom)
                        .transition(.move(edge: sheet.top ? .top : .bottom))
                        .id(sheet.id)
                        .zIndex(2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.easeOut(duration: 0.22), value: model.sheet?.id)
    }
}

private struct SheetPanel: View {
    @EnvironmentObject private var model: AppModel
    let sheet: SheetState
    /// Наибольшая высота листа.
    let limit: CGFloat

    private var shape: UnevenRoundedRectangle {
        sheet.top
            ? UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20)
            : UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
    }

    /// Лист с текстовым полем невысок и помещается всегда. Остальные прокручиваются, если не поместились.
    private var scrolls: Bool {
        if case .note = sheet.content { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            if scrolls {
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView {
                        content
                    }
                }
            } else {
                content
            }
        }
        .background {
            shape
                .fill(Palette.surface)
                .shadow(color: Palette.shadow, radius: 16, y: sheet.top ? 8 : -8)
                .ignoresSafeArea(edges: sheet.top ? .top : .bottom)
        }
        // касание самого листа его не закрывает: под ним лежит затемнение
        .contentShape(Rectangle())
        .onTapGesture {}
        .frame(maxHeight: limit, alignment: sheet.top ? .top : .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            model.closeSheet()
        }
    }

    private var head: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.title)
                    .font(.app(19, .bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if !sheet.sub.isEmpty {
                    Text(sheet.sub)
                        .font(.app(14))
                        .foregroundStyle(Palette.ink2)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.closeSheet()
            } label: {
                Icon("close")
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Закрыть")
        }
        .padding(EdgeInsets(top: 10, leading: Metrics.pad, bottom: 4, trailing: 8))
    }

    private var content: some View {
        Group {
            switch sheet.content {
            case .keypad(let keypad):
                KeypadBody(keypad: keypad)
            case .note(let note):
                NoteBody(note: note)
            case .sync:
                SyncBody()
            case .info(let exercise, let machine):
                InfoBody(exercise: exercise, machine: machine)
            case .confirm(let confirm):
                ConfirmBody(confirm: confirm)
            }
        }
        .padding(EdgeInsets(top: 8, leading: Metrics.pad, bottom: 16, trailing: Metrics.pad))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Цифровая клавиатура

private struct KeypadBody: View {
    @EnvironmentObject private var model: AppModel
    let keypad: KeypadState

    private static let rows: [[KeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.comma, .digit(0), .back],
    ]

    /// «Далее», пока следующее поле ещё не заполняли.
    private var wantsNext: Bool {
        let following = keypad.active + 1
        guard keypad.fields.count > 1, keypad.fields.indices.contains(following) else { return false }
        return keypad.fields[following].text.isEmpty
    }

    private var integerOnly: Bool {
        keypad.fields.indices.contains(keypad.active) ? keypad.fields[keypad.active].integer : false
    }

    var body: some View {
        let many = keypad.fields.count > 1
        let next = wantsNext
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(keypad.fields.enumerated()), id: \.element.id) { index, field in
                    DisplayField(field: field, chosen: !many || index == keypad.active, tappable: many) {
                        model.keypadField(index)
                    }
                }
            }
            Text(keypad.error)
                .font(.app(14, .semibold))
                .foregroundStyle(Palette.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 20)
            VStack(spacing: 8) {
                ForEach(Array(KeypadBody.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            keyButton(key)
                        }
                    }
                }
            }
            if let exercise = keypad.stepsFor {
                VStack(alignment: .leading, spacing: 6) {
                    CapsTitle("Шаг кнопок «+» и «−», кг")
                    FlowLayout(spacing: 8) {
                        ForEach(AppSettings.stepChoices, id: \.self) { value in
                            ChipButton(title: Numbers.format(value), chosen: value == model.settings.step(for: exercise)) {
                                model.setStep(exercise, value)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                if keypad.canClear {
                    Button("Стереть") {
                        model.keypadClear()
                    }
                    .buttonStyle(.app(.plain, block: true))
                }
                Button(next ? "Далее" : "Готово") {
                    if next {
                        model.keypadNext()
                    } else {
                        model.keypadDone()
                    }
                }
                .buttonStyle(.app(.primary, block: true))
            }
        }
    }

    private func keyName(_ key: KeypadKey) -> String {
        switch key {
        case .digit(let digit): return String(digit)
        case .comma: return "Запятая"
        case .back: return "Стереть цифру"
        }
    }

    private func keyButton(_ key: KeypadKey) -> some View {
        Button {
            model.keypadKey(key)
        } label: {
            switch key {
            case .digit(let digit):
                Text(String(digit))
            case .comma:
                Text(",")
            case .back:
                Icon("backspace", size: 28)
            }
        }
        .buttonStyle(KeyStyle())
        .disabled(key == .comma && integerOnly)
        .accessibilityLabel(keyName(key))
    }
}

/// Поле над клавиатурой: подпись, набранное число и единица измерения.
private struct DisplayField: View {
    let field: KeypadField
    /// В это поле попадают цифры.
    let chosen: Bool
    /// Полей несколько: касание выбирает поле.
    let tappable: Bool
    let action: () -> Void

    private var face: some View {
        let blank = field.text.isEmpty
        // значение будет заменено первым нажатием
        let fresh = field.fresh && !blank
        return VStack(spacing: 4) {
            Text(field.label)
                .font(.app(13))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(blank ? "—" : field.text)
                    .font(.app(32, blank ? .medium : .bold))
                    .foregroundStyle(blank ? Palette.ink3 : (fresh ? Palette.accentInk : Palette.ink))
                    .padding(.horizontal, fresh ? 4 : 0)
                    .background(fresh ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                if !field.unit.isEmpty {
                    Text(" \(field.unit)")
                        .font(.app(17, .semibold))
                        .foregroundStyle(Palette.ink2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minHeight: 36)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(chosen ? Palette.accentSoft : Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(chosen ? Palette.accentText : Color.clear, lineWidth: 2)
        )
    }

    var body: some View {
        if tappable {
            Button(action: action) {
                face
            }
            .buttonStyle(.press)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        } else {
            face
                .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Заметка

private struct NoteBody: View {
    @EnvironmentObject private var model: AppModel
    let note: NoteState
    @FocusState private var focused: Bool

    var body: some View {
        let text = Binding<String>(
            get: { note.text },
            set: { model.noteInput($0) }
        )
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "Заметка", text: text, prompt: Text("Например: сиденье на 4, было легко"), axis: .vertical
            )
            .lineLimit(3, reservesSpace: true)
            .font(.app(17))
            .foregroundStyle(Palette.ink)
            .focused($focused)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusSmall)
                    .strokeBorder(Palette.lineStrong, lineWidth: 1)
            )
            if !note.chips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(note.chips, id: \.self) { chip in
                        ChipButton(title: chip) {
                            model.noteAppend(chip)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if note.hadNote {
                    Button("Стереть") {
                        model.noteSave("")
                    }
                    .buttonStyle(.app(.plain, block: true))
                }
                Button("Сохранить") {
                    model.noteSave(note.text)
                }
                .buttonStyle(.app(.primary, block: true))
            }
        }
        .task {
            // клавиатура выезжает, когда лист уже на месте
            try? await Task.sleep(nanoseconds: 300_000_000)
            focused = true
        }
    }
}

// MARK: Синхронизация

private struct SyncBody: View {
    @EnvironmentObject private var model: AppModel

    private func rows(_ state: SyncState) -> [(name: String, value: String)] {
        var out: [(name: String, value: String)] = [
            (name: "Журнал прочитан", value: Days.formatMoment(state.snapshot?.fetchedAt, now: model.now())),
            (name: "В очереди", value: String(state.pending)),
        ]
        if !state.failed.isEmpty {
            out.append((name: "Не принято таблицей", value: String(state.failed.count)))
        }
        return out
    }

    var body: some View {
        let state = model.sync
        let busy = state.phase == .syncing
        VStack(alignment: .leading, spacing: 12) {
            // пока ждём следующей попытки, в тексте идёт обратный отсчёт
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Present.syncText(state, now: context.date))
                    .font(.app(15))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.configured {
                KeyValues(rows: rows(state))
            }
            if !state.failed.isEmpty {
                FailedList()
            }
            HStack(spacing: 8) {
                Button("Настройки") {
                    model.closeSheet()
                    model.go(.settings)
                }
                .buttonStyle(.app(.plain, block: true))
                if state.configured {
                    Button(busy ? "Обмен…" : "Обновить") {
                        model.syncNow()
                    }
                    .buttonStyle(.app(.primary, block: true))
                    .disabled(busy)
                }
            }
        }
    }
}

// MARK: Справка об упражнении

/// Фотографии тренажёров из набора приложения. Декодированные снимки остаются в памяти.
enum MachinePhotos {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        if let found = cache.object(forKey: name as NSString) { return found }
        guard let url = Bundle.main.url(forResource: name, withExtension: "webp", subdirectory: "machines"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

/// Кнопка «i»: как выглядит тренажёр и как на нём делать упражнение. Чего в справочнике нет, то не показывается.
private struct InfoBody: View {
    @EnvironmentObject private var model: AppModel
    let exercise: String
    let machine: String

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsTitle(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.app(14))
            .foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(.app(16))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        let guide = Guide.guide(exercise: exercise, machine: machine)
        let hasArt = !guide.art.isEmpty && ArtView.exists(guide.art)
        let photo = guide.photo.flatMap { MachinePhotos.image($0) }
        let artCaption = [guide.view, guide.legend].filter { !$0.isEmpty }.joined(separator: " ")
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                if guide.photo != nil || !guide.search.isEmpty {
                    section("Тренажёр") {
                        if let photo {
                            // у фотографий белый фон: панель белая в обеих темах
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(
                                    CGFloat(Guide.photoWidth) / CGFloat(Guide.photoHeight), contentMode: .fit
                                )
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Metrics.radiusSmall)
                                        .strokeBorder(Palette.line, lineWidth: 1)
                                )
                                .accessibilityLabel("Фото тренажёра: \(guide.machine)")
                        } else {
                            plain("Фото этого тренажёра в приложении нет.")
                        }
                        if !guide.look.isEmpty {
                            caption(guide.look)
                        }
                        if !guide.search.isEmpty {
                            LinkButton(title: "Найти фото в интернете", address: guide.search, kind: .soft)
                        }
                    }
                }
                if hasArt {
                    section("Упражнение") {
                        ArtView(name: guide.art)
                            .frame(maxWidth: .infinity)
                            .background(Palette.page)
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall))
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.radiusSmall)
                                    .strokeBorder(Palette.line, lineWidth: 1)
                            )
                            .accessibilityElement()
                            .accessibilityLabel("Рисунок упражнения: \(exercise)")
                        if !artCaption.isEmpty {
                            caption(artCaption)
                        }
                    }
                }
                if !guide.muscles.isEmpty {
                    section("Что работает") {
                        plain(guide.muscles)
                    }
                }
                if !guide.steps.isEmpty {
                    section("Как делать") {
                        StepsList(steps: guide.steps, size: 16)
                    }
                }
            }
            if !guide.rule.isEmpty {
                BannerView(text: guide.rule)
            }
            if !hasArt && guide.steps.isEmpty {
                Text("Рисунка и описания для этого упражнения в приложении пока нет.")
                    .font(.app(15))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Понятно") {
                model.closeSheet()
            }
            .buttonStyle(.app(.primary, block: true))
        }
    }
}

// MARK: Подтверждение

private struct ConfirmBody: View {
    @EnvironmentObject private var model: AppModel
    let confirm: ConfirmState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(confirm.text)
                .font(.app(15))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Отмена") {
                    model.closeSheet()
                }
                .buttonStyle(.app(.plain, block: true))
                Button(confirm.confirmLabel) {
                    model.confirmSheet()
                }
                .buttonStyle(.app(confirm.danger ? .danger : .primary, block: true))
            }
        }
    }
}
