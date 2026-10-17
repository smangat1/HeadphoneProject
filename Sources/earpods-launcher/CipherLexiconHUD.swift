import AppKit

enum CipherLexiconRowKind: Equatable {
    case ritual(CompanionRitualTarget)
    case intentMeaning
    case savedIntentMeaning(String)
    case macro
    case savedMacro(String)
    case appMeaning
    case savedAppMeaning(String)
    case correction
    case savedCorrection(String)
    case semanticOpenBias
    case semanticPreferredBrowser
    case resetRituals
    case resetIntentMeanings
    case resetMacros
    case resetMeanings
    case resetCorrections
    case back
}

struct CipherLexiconRow {
    let kind: CipherLexiconRowKind
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
    let style: Style
    let sectionTitle: String?

    enum Style {
        case primary
        case utility
    }
}

struct CipherLexiconCardModel {
    let title: String
    let subtitle: String
    let metadataText: String
    let footer: String
    let rows: [CipherLexiconRow]
}

enum CipherLexiconEntryPhase {
    case ritual(CompanionRitualTarget)
    case intentMeaningPhrase
    case intentMeaningTarget(phrase: String)
    case macroPhrase
    case macroSteps(phrase: String)
    case appMeaningPhrase
    case appMeaningTarget(phrase: String)
    case correctionPhrase
    case correctionReplacement(phrase: String)
}

struct CipherLexiconEntryModel {
    let title: String
    let subtitle: String
    let helperText: String
    let placeholder: String
    let footer: String
    let symbol: String
}

enum CipherLexiconSelection {
    case row(CipherLexiconRow, Int)
}

@MainActor
final class CipherLexiconCardController {
    private static let rowWidth: CGFloat = 360
    private static let rowsViewportHeight: CGFloat = 308
    private static let rowContentWidth: CGFloat = 332

    private let window: CipherLexiconWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let metadataField: NSTextField
    private let footerField: NSTextField
    private let rowsSurface: NSView
    private let rowsScrollView: NSScrollView
    private let rowsStack: NSStackView
    private var rowViews: [CipherLexiconRowView] = []
    private var currentModel: CipherLexiconCardModel?
    private var selectedIndex = 0

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.12
        )

        titleField = NSTextField(labelWithString: "")
        stylePortalTitle(titleField)

        subtitleField = NSTextField(wrappingLabelWithString: "")
        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        metadataField = NSTextField(wrappingLabelWithString: "")
        metadataField.translatesAutoresizingMaskIntoConstraints = false
        metadataField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        metadataField.textColor = NSColor.systemIndigo.withAlphaComponent(0.92)
        metadataField.alignment = .center
        metadataField.maximumNumberOfLines = 2

        footerField = NSTextField(wrappingLabelWithString: "")
        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        rowsSurface = NSView()
        rowsSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(rowsSurface, cornerRadius: 18)
        applyPortalRowSurface(rowsSurface, state: .idle)

        rowsScrollView = NSScrollView()
        rowsScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.drawsBackground = false
        rowsScrollView.borderType = .noBorder
        rowsScrollView.hasVerticalScroller = true
        rowsScrollView.hasHorizontalScroller = false
        rowsScrollView.autohidesScrollers = true
        rowsScrollView.scrollerStyle = .overlay

        rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = true
        rowsScrollView.documentView = rowsStack
        rowsSurface.addSubview(rowsScrollView)

        let contentStack = NSStackView(views: [titleField, subtitleField, metadataField, rowsSurface, footerField])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        chrome.chromeView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),

            subtitleField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            metadataField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            rowsSurface.widthAnchor.constraint(equalToConstant: Self.rowWidth),
            rowsSurface.heightAnchor.constraint(equalToConstant: Self.rowsViewportHeight),
            rowsScrollView.leadingAnchor.constraint(equalTo: rowsSurface.leadingAnchor, constant: 12),
            rowsScrollView.trailingAnchor.constraint(equalTo: rowsSurface.trailingAnchor, constant: -8),
            rowsScrollView.topAnchor.constraint(equalTo: rowsSurface.topAnchor, constant: 10),
            rowsScrollView.bottomAnchor.constraint(equalTo: rowsSurface.bottomAnchor, constant: -10),
            footerField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        window = CipherLexiconWindow(
            contentRect: NSRect(x: 0, y: 0, width: 472, height: 572),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(window)
        window.contentView = chrome.rootView
    }

    var isVisible: Bool {
        window.isVisible
    }

    func currentSelection() -> CipherLexiconSelection? {
        guard let currentModel,
              currentModel.rows.indices.contains(selectedIndex) else {
            return nil
        }
        let row = currentModel.rows[selectedIndex]
        guard row.isEnabled else {
            return nil
        }
        return .row(row, selectedIndex)
    }

    func show(model: CipherLexiconCardModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        update(model: model, selectedIndex: explicitSelectedIndex)
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        showPortalWindow(window)
        return window.isVisible
    }

    func update(model: CipherLexiconCardModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        currentModel = model
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        metadataField.stringValue = model.metadataText
        footerField.stringValue = model.footer
        rebuildRows(model.rows)
        applySelectionIndex(explicitSelectedIndex)
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> CipherLexiconSelection? {
        guard let currentModel, !currentModel.rows.isEmpty else {
            return nil
        }

        var nextIndex = selectedIndex
        for _ in 0..<currentModel.rows.count {
            nextIndex = (nextIndex + delta + currentModel.rows.count) % currentModel.rows.count
            if currentModel.rows[nextIndex].isEnabled {
                selectedIndex = nextIndex
                applySelection()
                return currentSelection()
            }
        }

        return nil
    }

    func confirmSelection() -> CipherLexiconSelection? {
        currentSelection()
    }

    private func rebuildRows(_ rows: [CipherLexiconRow]) {
        for rowView in rowViews {
            rowsStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        rowViews = rows.enumerated().map { index, row in
            let rowView = CipherLexiconRowView(row: row)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowContentWidth).isActive = true
            rowsStack.addArrangedSubview(rowView)
            if index + 1 < rows.count, rows[index + 1].sectionTitle != nil {
                rowsStack.setCustomSpacing(18, after: rowView)
            } else {
                rowsStack.setCustomSpacing(8, after: rowView)
            }
            return rowView
        }

        rowsStack.layoutSubtreeIfNeeded()
        let contentHeight = max(rowsStack.fittingSize.height, Self.rowsViewportHeight - 20)
        rowsStack.frame = NSRect(x: 0, y: 0, width: Self.rowContentWidth, height: contentHeight)
    }

    private func applySelectionIndex(_ explicitSelectedIndex: Int?) {
        guard let currentModel, !currentModel.rows.isEmpty else {
            selectedIndex = 0
            applySelection()
            return
        }

        if let explicitSelectedIndex,
           currentModel.rows.indices.contains(explicitSelectedIndex),
           currentModel.rows[explicitSelectedIndex].isEnabled {
            selectedIndex = explicitSelectedIndex
        } else if !currentModel.rows.indices.contains(selectedIndex) || !currentModel.rows[selectedIndex].isEnabled {
            selectedIndex = currentModel.rows.firstIndex(where: \.isEnabled) ?? 0
        }

        applySelection()
    }

    private func applySelection() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }

        guard rowViews.indices.contains(selectedIndex) else {
            return
        }

        rowsStack.layoutSubtreeIfNeeded()
        let rowFrame = rowViews[selectedIndex].frame.insetBy(dx: 0, dy: -8)
        rowsStack.scrollToVisible(rowFrame)
        rowsScrollView.reflectScrolledClipView(rowsScrollView.contentView)
    }
}

@MainActor
final class CipherLexiconEntryController {
    private let window: CipherLexiconEntryWindow
    private let symbolView: NSImageView
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let helperField: NSTextField
    private let inputField: CipherLexiconInputField
    private let footerField: NSTextField

    var onSubmit: ((String) -> Void)?

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.12
        )

        symbolView = NSImageView()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        symbolView.contentTintColor = NSColor.systemIndigo.withAlphaComponent(0.98)

        titleField = NSTextField(labelWithString: "")
        stylePortalTitle(titleField)

        subtitleField = NSTextField(wrappingLabelWithString: "")
        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 3

        helperField = NSTextField(wrappingLabelWithString: "")
        helperField.translatesAutoresizingMaskIntoConstraints = false
        helperField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        helperField.textColor = NSColor.white.withAlphaComponent(0.70)
        helperField.alignment = .center
        helperField.maximumNumberOfLines = 3

        inputField = CipherLexiconInputField()

        let inputSurface = NSView()
        inputSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(inputSurface, cornerRadius: 16)
        applyPortalRowSurface(inputSurface, state: .idle)
        inputSurface.addSubview(inputField)

        footerField = NSTextField(wrappingLabelWithString: "")
        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        let contentStack = NSStackView(views: [symbolView, titleField, subtitleField, helperField, inputSurface, footerField])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        chrome.chromeView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),

            subtitleField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            helperField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            inputSurface.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            inputField.leadingAnchor.constraint(equalTo: inputSurface.leadingAnchor, constant: 14),
            inputField.trailingAnchor.constraint(equalTo: inputSurface.trailingAnchor, constant: -14),
            inputField.topAnchor.constraint(equalTo: inputSurface.topAnchor, constant: 10),
            inputField.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -10),
            footerField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        window = CipherLexiconEntryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 456, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(window)
        window.contentView = chrome.rootView

        inputField.onSubmit = { [weak self] text in
            self?.onSubmit?(text)
        }
    }

    var isVisible: Bool {
        window.isVisible
    }

    func show(model: CipherLexiconEntryModel) -> Bool {
        update(model: model)
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = false
        showPortalWindow(window, makeKey: true)
        window.makeFirstResponder(inputField)
        return window.isVisible
    }

    func update(model: CipherLexiconEntryModel) {
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        helperField.stringValue = model.helperText
        footerField.stringValue = model.footer
        inputField.placeholderString = model.placeholder
        symbolView.image = NSImage(systemSymbolName: model.symbol, accessibilityDescription: model.title)
    }

    func clearInput() {
        inputField.stringValue = ""
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }
}

@MainActor
private final class CipherLexiconWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CipherLexiconEntryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class CipherLexiconRowView: NSView {
    private let eyebrowField: NSTextField
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let detailField: NSTextField
    private let isEnabled: Bool
    private let style: CipherLexiconRow.Style

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(row: CipherLexiconRow) {
        eyebrowField = NSTextField(labelWithString: row.sectionTitle ?? "")
        iconView = NSImageView()
        titleField = NSTextField(labelWithString: row.title)
        detailField = NSTextField(wrappingLabelWithString: row.detail)
        isEnabled = row.isEnabled
        style = row.style
        super.init(frame: .zero)

        configurePortalRowSurface(self)

        eyebrowField.translatesAutoresizingMaskIntoConstraints = false
        eyebrowField.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        eyebrowField.textColor = NSColor.systemIndigo.withAlphaComponent(0.92)
        eyebrowField.isHidden = row.sectionTitle == nil

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.title)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        detailField.maximumNumberOfLines = 2
        detailField.lineBreakMode = .byTruncatingTail

        addSubview(eyebrowField)
        addSubview(iconView)
        addSubview(titleField)
        addSubview(detailField)

        let topInset: CGFloat = row.sectionTitle == nil ? 10 : 12
        let titleTopAnchor = row.sectionTitle == nil ? topAnchor : eyebrowField.bottomAnchor
        let titleTopConstant: CGFloat = row.sectionTitle == nil ? topInset : 2

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            eyebrowField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            eyebrowField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            eyebrowField.topAnchor.constraint(equalTo: topAnchor, constant: topInset),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.topAnchor.constraint(equalTo: titleTopAnchor, constant: titleTopConstant),

            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        let state: PortalRowSurfaceState
        if !isEnabled {
            state = .disabled
        } else {
            switch style {
            case .primary:
                state = isSelected ? .selected : .idle
            case .utility:
                state = isSelected ? .selected : .muted
            }
        }
        applyPortalRowSurface(self, state: state)
        iconView.contentTintColor = colorForState(isSelected: isSelected, enabled: isEnabled, emphasis: .icon)
        titleField.textColor = colorForState(isSelected: isSelected, enabled: isEnabled, emphasis: .primary)
        detailField.textColor = colorForState(isSelected: isSelected, enabled: isEnabled, emphasis: .secondary)
        eyebrowField.textColor = isSelected
            ? PortalHUDStyle.secondaryTextColor
            : NSColor.systemIndigo.withAlphaComponent(isEnabled ? 0.92 : 0.35)
    }
}

@MainActor
private final class CipherLexiconInputField: NSTextField {
    var onSubmit: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isEditable = true
        isSelectable = true
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = NSFont.systemFont(ofSize: 13, weight: .medium)
        textColor = PortalHUDStyle.primaryTextColor
        placeholderString = "Type a phrase and press Return"
        target = self
        action = #selector(commitInput)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func commitInput() {
        let text = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        stringValue = ""
        onSubmit?(text)
    }
}
