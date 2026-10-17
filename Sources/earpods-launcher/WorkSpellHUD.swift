import AppKit
import Foundation

enum WorkSpellSelection {
    case row(WorkSpellRow, Int)
}

@MainActor
final class WorkSpellCardController {
    private static let rowWidth: CGFloat = 360

    private let window: WorkSpellWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let metadataField: NSTextField
    private let footerField: NSTextField
    private let rowsSurface: NSView
    private let rowsScrollView: NSScrollView
    private let rowsContainerView: NSView
    private let rowsStack: NSStackView
    private let inputSurface: NSView
    private let inputField: WorkSpellInputField
    private let rowsHeightConstraint: NSLayoutConstraint
    private var rowViews: [WorkSpellRowView] = []
    private var currentModel: WorkSpellCardModel?
    private var selectedIndex = 0
    private var isComposingTask = false

    var onSubmit: ((String) -> Void)?
    var onSelectionActivated: ((WorkSpellRow, Int) -> Void)?

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemGreen,
            tintOpacity: 0.10
        )

        titleField = NSTextField(labelWithString: "")
        subtitleField = NSTextField(wrappingLabelWithString: "")
        metadataField = NSTextField(wrappingLabelWithString: "")
        footerField = NSTextField(wrappingLabelWithString: "")
        rowsSurface = NSView()
        rowsScrollView = NSScrollView()
        rowsContainerView = NSView()
        rowsStack = NSStackView()
        inputSurface = NSView()
        inputField = WorkSpellInputField()

        stylePortalTitle(titleField)

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        metadataField.translatesAutoresizingMaskIntoConstraints = false
        metadataField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        metadataField.textColor = NSColor.systemGreen.withAlphaComponent(0.9)
        metadataField.alignment = .center
        metadataField.maximumNumberOfLines = 3
        metadataField.lineBreakMode = .byWordWrapping

        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 3

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        rowsSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(rowsSurface, cornerRadius: 18)
        applyPortalRowSurface(rowsSurface, state: .idle)
        rowsScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.drawsBackground = false
        rowsScrollView.borderType = .noBorder
        rowsScrollView.hasVerticalScroller = true
        rowsScrollView.hasHorizontalScroller = false
        rowsScrollView.autohidesScrollers = true
        rowsScrollView.scrollerStyle = .overlay

        rowsContainerView.translatesAutoresizingMaskIntoConstraints = false
        rowsContainerView.addSubview(rowsStack)
        rowsScrollView.documentView = rowsContainerView
        rowsSurface.addSubview(rowsScrollView)

        inputSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(inputSurface, cornerRadius: 16)
        applyPortalRowSurface(inputSurface, state: .muted)
        inputSurface.addSubview(inputField)

        let contentStack = NSStackView(views: [titleField, subtitleField, metadataField, rowsSurface, inputSurface, footerField])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        chrome.chromeView.addSubview(contentStack)

        rowsHeightConstraint = rowsSurface.heightAnchor.constraint(equalToConstant: 158)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),

            subtitleField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            metadataField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            rowsSurface.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            rowsHeightConstraint,
            rowsScrollView.leadingAnchor.constraint(equalTo: rowsSurface.leadingAnchor, constant: 8),
            rowsScrollView.trailingAnchor.constraint(equalTo: rowsSurface.trailingAnchor, constant: -8),
            rowsScrollView.topAnchor.constraint(equalTo: rowsSurface.topAnchor, constant: 8),
            rowsScrollView.bottomAnchor.constraint(equalTo: rowsSurface.bottomAnchor, constant: -8),
            rowsContainerView.leadingAnchor.constraint(equalTo: rowsScrollView.contentView.leadingAnchor),
            rowsContainerView.trailingAnchor.constraint(equalTo: rowsScrollView.contentView.trailingAnchor),
            rowsContainerView.topAnchor.constraint(equalTo: rowsScrollView.contentView.topAnchor),
            rowsContainerView.bottomAnchor.constraint(equalTo: rowsScrollView.contentView.bottomAnchor),
            rowsContainerView.widthAnchor.constraint(equalTo: rowsScrollView.contentView.widthAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: rowsContainerView.leadingAnchor, constant: 2),
            rowsStack.trailingAnchor.constraint(equalTo: rowsContainerView.trailingAnchor, constant: -2),
            rowsStack.topAnchor.constraint(equalTo: rowsContainerView.topAnchor, constant: 2),
            rowsStack.bottomAnchor.constraint(equalTo: rowsContainerView.bottomAnchor, constant: -2),

            inputSurface.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            inputField.leadingAnchor.constraint(equalTo: inputSurface.leadingAnchor, constant: 14),
            inputField.trailingAnchor.constraint(equalTo: inputSurface.trailingAnchor, constant: -14),
            inputField.topAnchor.constraint(equalTo: inputSurface.topAnchor, constant: 10),
            inputField.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -10),

            footerField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        window = WorkSpellWindow(
            contentRect: NSRect(x: 0, y: 0, width: 478, height: 612),
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

    func currentSelection() -> WorkSpellSelection? {
        guard let currentModel, currentModel.rows.indices.contains(selectedIndex) else {
            return nil
        }
        return .row(currentModel.rows[selectedIndex], selectedIndex)
    }

    func show(model: WorkSpellCardModel, selectedIndex explicitSelectedIndex: Int? = nil, focusInput: Bool = false) -> Bool {
        update(model: model, selectedIndex: explicitSelectedIndex)
        if focusInput {
            enterComposerMode()
        } else {
            exitComposerMode()
        }
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = false
        showPortalWindow(window, makeKey: true)
        if focusInput {
            window.makeFirstResponder(inputField)
        }
        return window.isVisible
    }

    func update(model: WorkSpellCardModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        currentModel = model
        rebuildRows(model.rows)
        updateRowsSurfaceHeight(for: model.rows)
        applySelectionIndex(from: model.rows, explicitSelectedIndex: explicitSelectedIndex)
        applySelection()
        applyDisplayedState()
        ensureSelectionIsVisible()
    }

    func reshowCurrentState() -> Bool {
        guard currentModel != nil else {
            return false
        }
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = false
        showPortalWindow(window, makeKey: true)
        return window.isVisible
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func clearInput() {
        inputField.stringValue = ""
    }

    func focusInput() {
        enterComposerMode()
        showPortalWindow(window, makeKey: true)
        window.makeFirstResponder(inputField)
    }

    func enterComposerMode() {
        guard currentModel != nil else {
            return
        }
        isComposingTask = true
        inputField.stringValue = ""
        applyDisplayedState()
    }

    func exitComposerMode() {
        guard isComposingTask else {
            return
        }
        isComposingTask = false
        applyDisplayedState()
    }

    func moveSelection(by delta: Int) -> WorkSpellSelection? {
        guard let currentModel, !currentModel.rows.isEmpty else {
            return nil
        }

        let enabledStates = currentModel.rows.map(\.isEnabled)
        guard enabledStates.contains(true) else {
            return nil
        }

        var nextIndex = selectedIndex
        for _ in 0..<enabledStates.count {
            nextIndex = (nextIndex + delta + enabledStates.count) % enabledStates.count
            if enabledStates[nextIndex] {
                selectedIndex = nextIndex
                applySelection()
                return currentSelection()
            }
        }
        return nil
    }

    func confirmSelection() -> WorkSpellSelection? {
        guard let selection = currentSelection() else {
            return nil
        }
        switch selection {
        case .row(let row, _):
            return row.isEnabled ? selection : nil
        }
    }

    private func rebuildRows(_ rows: [WorkSpellRow]) {
        for rowView in rowViews {
            rowsStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        rowViews = rows.enumerated().map { index, row in
            let rowView = WorkSpellRowView(row: row)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: row.minimumHeight).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            rowView.onActivate = { [weak self] in
                guard let self else {
                    return
                }
                self.selectedIndex = index
                self.applySelection()
                self.onSelectionActivated?(row, index)
            }
            rowsStack.addArrangedSubview(rowView)
            return rowView
        }
    }

    private func updateRowsSurfaceHeight(for rows: [WorkSpellRow]) {
        let contentHeight = rows.reduce(CGFloat(0)) { partialResult, row in
            partialResult + row.minimumHeight
        } + (CGFloat(max(rows.count - 1, 0)) * rowsStack.spacing) + 16

        rowsHeightConstraint.constant = min(max(contentHeight, 118), 294)
        rowsSurface.layoutSubtreeIfNeeded()
    }

    private func resizeWindowIfNeeded(forRowCount rowCount: Int) {
        let targetHeight: CGFloat
        if isComposingTask {
            targetHeight = 348
        } else {
            targetHeight = min(max(356 + rowsHeightConstraint.constant, 424), 648)
        }
        let currentFrame = window.frame
        guard abs(currentFrame.height - targetHeight) > 1 else {
            return
        }

        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - (targetHeight - currentFrame.height) / 2,
            width: currentFrame.width,
            height: targetHeight
        )
        window.setFrame(newFrame, display: true)
    }

    private func applySelectionIndex(from rows: [WorkSpellRow], explicitSelectedIndex: Int?) {
        let enabledStates = rows.map(\.isEnabled)
        guard !enabledStates.isEmpty else {
            selectedIndex = 0
            return
        }

        if let explicitSelectedIndex,
           enabledStates.indices.contains(explicitSelectedIndex),
           enabledStates[explicitSelectedIndex] {
            selectedIndex = explicitSelectedIndex
            return
        }

        if !enabledStates.indices.contains(selectedIndex) || !enabledStates[selectedIndex] {
            selectedIndex = enabledStates.firstIndex(of: true) ?? 0
        }
    }

    private func applySelection() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }
    }

    private func ensureSelectionIsVisible() {
        guard !isComposingTask,
              rowViews.indices.contains(selectedIndex) else {
            return
        }

        rowsContainerView.layoutSubtreeIfNeeded()
        rowsStack.layoutSubtreeIfNeeded()
        rowViews[selectedIndex].scrollToVisible(rowViews[selectedIndex].bounds.insetBy(dx: 0, dy: -12))
        rowsScrollView.reflectScrolledClipView(rowsScrollView.contentView)
    }

    private func applyDisplayedState() {
        guard let currentModel else {
            return
        }

        if isComposingTask {
            titleField.stringValue = "Add Task"
            subtitleField.stringValue = "Type one task or a comma-separated dump."
            metadataField.stringValue = "Return adds it instantly. You can paste a whole list here."
            footerField.stringValue = "Examples: research, design, export. Hold center closes."
            inputField.placeholderString = "Type a task and press Return"
            rowsSurface.isHidden = true
            applyPortalRowSurface(inputSurface, state: .selected)
        } else {
            titleField.stringValue = currentModel.title
            subtitleField.stringValue = currentModel.subtitle
            metadataField.stringValue = currentModel.metadataText
            footerField.stringValue = currentModel.footer
            inputField.placeholderString = currentModel.inputPlaceholder
            rowsSurface.isHidden = false
            applyPortalRowSurface(inputSurface, state: .muted)
        }

        resizeWindowIfNeeded(forRowCount: currentModel.rows.count)
    }
}

@MainActor
final class WorkSpellSettingsCardController {
    private static let rowWidth: CGFloat = 360

    private let window: WorkSpellWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let metadataField: NSTextField
    private let footerField: NSTextField
    private let rowsStack: NSStackView
    private var rowViews: [WorkSpellRowView] = []
    private var currentModel: WorkSpellSettingsModel?
    private var selectedIndex = 0
    var onSelectionActivated: ((WorkSpellSettingsRow, Int) -> Void)?

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemOrange,
            tintOpacity: 0.10
        )

        titleField = NSTextField(labelWithString: "")
        subtitleField = NSTextField(wrappingLabelWithString: "")
        metadataField = NSTextField(wrappingLabelWithString: "")
        footerField = NSTextField(wrappingLabelWithString: "")
        rowsStack = NSStackView()

        stylePortalTitle(titleField)

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        metadataField.translatesAutoresizingMaskIntoConstraints = false
        metadataField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        metadataField.textColor = NSColor.systemOrange.withAlphaComponent(0.9)
        metadataField.alignment = .center
        metadataField.maximumNumberOfLines = 3
        metadataField.lineBreakMode = .byWordWrapping

        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [titleField, subtitleField, metadataField, rowsStack, footerField])
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
            rowsStack.widthAnchor.constraint(equalToConstant: Self.rowWidth),
            footerField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        window = WorkSpellWindow(
            contentRect: NSRect(x: 0, y: 0, width: 476, height: 548),
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

    func currentSelection() -> (row: WorkSpellSettingsRow, index: Int)? {
        guard let currentModel, currentModel.rows.indices.contains(selectedIndex) else {
            return nil
        }
        return (currentModel.rows[selectedIndex], selectedIndex)
    }

    func show(model: WorkSpellSettingsModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        update(model: model, selectedIndex: explicitSelectedIndex)
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = false
        showPortalWindow(window, makeKey: true)
        return window.isVisible
    }

    func update(model: WorkSpellSettingsModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        currentModel = model
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        metadataField.stringValue = model.metadataText
        footerField.stringValue = model.footer
        rebuildRows(model.rows)
        applySelectionIndex(from: model.rows, explicitSelectedIndex: explicitSelectedIndex)
        applySelection()
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> (row: WorkSpellSettingsRow, index: Int)? {
        guard let currentModel, !currentModel.rows.isEmpty else {
            return nil
        }

        let enabledStates = currentModel.rows.map(\.isEnabled)
        guard enabledStates.contains(true) else {
            return nil
        }

        var nextIndex = selectedIndex
        for _ in 0..<enabledStates.count {
            nextIndex = (nextIndex + delta + enabledStates.count) % enabledStates.count
            if enabledStates[nextIndex] {
                selectedIndex = nextIndex
                applySelection()
                return currentSelection()
            }
        }
        return nil
    }

    func confirmSelection() -> (row: WorkSpellSettingsRow, index: Int)? {
        guard let selection = currentSelection() else {
            return nil
        }
        return selection.row.isEnabled ? selection : nil
    }

    private func rebuildRows(_ rows: [WorkSpellSettingsRow]) {
        for rowView in rowViews {
            rowsStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        rowViews = rows.enumerated().map { index, row in
            let displayRow = WorkSpellRow(
                kind: .newTask,
                eyebrow: nil,
                title: row.title,
                detail: row.detail,
                symbol: row.symbol,
                isEnabled: row.isEnabled,
                style: .utility,
                indentLevel: 0
            )
            let rowView = WorkSpellRowView(row: displayRow)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            rowView.onActivate = { [weak self] in
                guard let self else {
                    return
                }
                self.selectedIndex = index
                self.applySelection()
                self.onSelectionActivated?(row, index)
            }
            rowsStack.addArrangedSubview(rowView)
            return rowView
        }
    }

    private func applySelectionIndex(from rows: [WorkSpellSettingsRow], explicitSelectedIndex: Int?) {
        let enabledStates = rows.map(\.isEnabled)
        guard !enabledStates.isEmpty else {
            selectedIndex = 0
            return
        }

        if let explicitSelectedIndex,
           enabledStates.indices.contains(explicitSelectedIndex),
           enabledStates[explicitSelectedIndex] {
            selectedIndex = explicitSelectedIndex
            return
        }

        if !enabledStates.indices.contains(selectedIndex) || !enabledStates[selectedIndex] {
            selectedIndex = enabledStates.firstIndex(of: true) ?? 0
        }
    }

    private func applySelection() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }
    }
}

@MainActor
private final class WorkSpellWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class WorkSpellRowView: NSView {
    private let eyebrowField: NSTextField
    private let row: WorkSpellRow
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let detailField: NSTextField
    var onActivate: (() -> Void)?

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(row: WorkSpellRow) {
        eyebrowField = NSTextField(labelWithString: row.eyebrow ?? "")
        self.row = row
        iconView = NSImageView()
        titleField = NSTextField(labelWithString: row.title)
        detailField = NSTextField(wrappingLabelWithString: row.detail)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(self, cornerRadius: 14)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.title)
            ?? NSImage(systemSymbolName: "checklist", accessibilityDescription: row.title)

        eyebrowField.translatesAutoresizingMaskIntoConstraints = false
        eyebrowField.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        eyebrowField.textColor = NSColor.systemGreen.withAlphaComponent(0.92)
        eyebrowField.alignment = .left
        eyebrowField.isHidden = (row.eyebrow ?? "").isEmpty

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(
            ofSize: row.style == .focus ? 15 : 13,
            weight: .semibold
        )
        titleField.lineBreakMode = .byTruncatingTail

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        detailField.maximumNumberOfLines = row.style == .focus ? 3 : 2
        detailField.lineBreakMode = .byWordWrapping

        addSubview(eyebrowField)
        addSubview(iconView)
        addSubview(titleField)
        addSubview(detailField)

        let titleTopAnchor = eyebrowField.isHidden ? topAnchor : eyebrowField.bottomAnchor
        let titleTopConstant: CGFloat = eyebrowField.isHidden ? (row.style == .focus ? 14 : 11) : 2
        let leadingInset = 14 + (CGFloat(row.indentLevel) * 20)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            eyebrowField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            eyebrowField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            eyebrowField.topAnchor.constraint(equalTo: topAnchor, constant: row.style == .focus ? 12 : 10),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.topAnchor.constraint(equalTo: titleTopAnchor, constant: titleTopConstant),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseUp(with event: NSEvent) {
        guard row.isEnabled else {
            return
        }
        onActivate?()
    }

    private func updateAppearance() {
        let state: PortalRowSurfaceState
        if !row.isEnabled || row.style == .empty {
            state = .muted
        } else if isSelected {
            state = .selected
        } else {
            switch row.style {
            case .focus, .task:
                state = .idle
            case .blocked, .utility:
                state = .muted
            case .empty:
                state = .muted
            }
        }

        applyPortalRowSurface(self, state: state)

        let primaryColor: NSColor
        let secondaryColor: NSColor
        switch row.style {
        case .focus:
            primaryColor = row.isEnabled ? PortalHUDStyle.primaryTextColor : PortalHUDStyle.secondaryTextColor
            secondaryColor = NSColor.systemGreen.withAlphaComponent(0.94)
        case .task:
            primaryColor = row.isEnabled ? PortalHUDStyle.primaryTextColor : PortalHUDStyle.secondaryTextColor
            secondaryColor = PortalHUDStyle.secondaryTextColor
        case .blocked:
            primaryColor = row.isEnabled ? PortalHUDStyle.primaryTextColor.withAlphaComponent(0.92) : PortalHUDStyle.secondaryTextColor
            secondaryColor = NSColor.systemOrange.withAlphaComponent(0.88)
        case .utility:
            primaryColor = row.isEnabled ? PortalHUDStyle.primaryTextColor : PortalHUDStyle.secondaryTextColor
            secondaryColor = PortalHUDStyle.secondaryTextColor
        case .empty:
            primaryColor = PortalHUDStyle.secondaryTextColor
            secondaryColor = PortalHUDStyle.secondaryTextColor.withAlphaComponent(0.72)
        }

        titleField.textColor = primaryColor
        detailField.textColor = secondaryColor
        eyebrowField.textColor = row.style == .blocked
            ? NSColor.systemOrange.withAlphaComponent(row.isEnabled ? 0.9 : 0.45)
            : NSColor.systemGreen.withAlphaComponent(row.isEnabled ? 0.92 : 0.42)
        iconView.contentTintColor = isSelected ? PortalHUDStyle.primaryTextColor : secondaryColor
    }
}

@MainActor
private final class WorkSpellInputField: NSTextField, NSTextFieldDelegate {
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
        placeholderString = "Type a task and press Return"
        delegate = self
        target = self
        action = #selector(commitInput)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitInput()
            return true
        }
        return false
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
