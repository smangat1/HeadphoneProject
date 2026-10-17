import AppKit
import Foundation

@MainActor
final class CurrentThreadCardController {
    private static let rowWidth: CGFloat = 344

    private let window: CurrentThreadWindow
    private let badgeView: CurrentThreadBadgeView
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let metadataField: NSTextField
    private let footerField: NSTextField
    private let actionStack: NSStackView
    private var actionRowViews: [CurrentThreadActionRowView] = []
    private var currentModel: CurrentThreadCardModel?
    private var selectedIndex = 0

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemOrange,
            tintOpacity: 0.10
        )

        badgeView = CurrentThreadBadgeView()
        titleField = NSTextField(labelWithString: "")
        subtitleField = NSTextField(wrappingLabelWithString: "")
        metadataField = NSTextField(wrappingLabelWithString: "")
        footerField = NSTextField(wrappingLabelWithString: "")
        actionStack = NSStackView()

        stylePortalTitle(titleField)
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        metadataField.translatesAutoresizingMaskIntoConstraints = false
        metadataField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        metadataField.textColor = NSColor.white.withAlphaComponent(0.66)
        metadataField.alignment = .center
        metadataField.maximumNumberOfLines = 4
        metadataField.lineBreakMode = .byTruncatingTail

        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        actionStack.orientation = .vertical
        actionStack.alignment = .leading
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [badgeView, titleField, subtitleField, metadataField, actionStack, footerField])
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
            actionStack.widthAnchor.constraint(equalToConstant: Self.rowWidth),
            footerField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        window = CurrentThreadWindow(
            contentRect: NSRect(x: 0, y: 0, width: 472, height: 520),
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

    func currentSelection() -> (action: CurrentThreadAction, index: Int)? {
        guard let currentModel, !currentModel.actions.isEmpty else {
            return nil
        }
        return (currentModel.actions[selectedIndex], selectedIndex)
    }

    func show(model: CurrentThreadCardModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        update(model: model, selectedIndex: explicitSelectedIndex)
        return revealWindow()
    }

    func update(model: CurrentThreadCardModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        currentModel = model
        applySelectionIndex(from: model.actions, explicitSelectedIndex: explicitSelectedIndex)

        badgeView.configure(
            title: model.description.badgeTitle,
            symbolName: model.description.badgeSymbol
        )
        titleField.stringValue = model.description.title
        subtitleField.stringValue = model.description.subtitle
        metadataField.stringValue = model.description.metadataText
        footerField.stringValue = model.footer

        rebuildActions(model.actions)
        applySelection()
    }

    func reshowCurrentState() -> Bool {
        guard currentModel != nil else {
            return false
        }
        return revealWindow()
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> (action: CurrentThreadAction, index: Int)? {
        guard let currentModel, !currentModel.actions.isEmpty else {
            return nil
        }

        let enabledStates = currentModel.actions.map(\.isEnabled)
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

    func confirmSelection() -> (action: CurrentThreadAction, index: Int)? {
        guard let selection = currentSelection(), selection.action.isEnabled else {
            return nil
        }
        return selection
    }

    private func rebuildActions(_ actions: [CurrentThreadAction]) {
        for rowView in actionRowViews {
            actionStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        actionRowViews = actions.map { action in
            let rowView = CurrentThreadActionRowView(action: action)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            actionStack.addArrangedSubview(rowView)
            return rowView
        }
    }

    private func applySelectionIndex(from actions: [CurrentThreadAction], explicitSelectedIndex: Int?) {
        let enabledStates = actions.map(\.isEnabled)
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
        for (index, rowView) in actionRowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }
    }

    private func revealWindow() -> Bool {
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        showPortalWindow(window)
        return window.isVisible
    }
}

@MainActor
private final class CurrentThreadWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CurrentThreadActionRowView: NSView {
    private let action: CurrentThreadAction
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let detailField: NSTextField

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(action: CurrentThreadAction) {
        self.action = action
        self.iconView = NSImageView()
        self.titleField = NSTextField(labelWithString: action.title)
        self.detailField = NSTextField(wrappingLabelWithString: action.detail)
        super.init(frame: .zero)

        configurePortalRowSurface(self)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: action.title)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        detailField.lineBreakMode = .byTruncatingTail
        detailField.maximumNumberOfLines = 2

        addSubview(iconView)
        addSubview(titleField)
        addSubview(detailField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 10),

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
        let surfaceState: PortalRowSurfaceState
        if !action.isEnabled {
            surfaceState = .disabled
        } else if isSelected {
            surfaceState = .selected
        } else {
            surfaceState = .idle
        }

        applyPortalRowSurface(self, state: surfaceState)
        titleField.textColor = colorForState(isSelected: isSelected, enabled: action.isEnabled, emphasis: .primary)
        detailField.textColor = colorForState(isSelected: isSelected, enabled: action.isEnabled, emphasis: .secondary)
        iconView.contentTintColor = colorForState(isSelected: isSelected, enabled: action.isEnabled, emphasis: .icon)
    }
}

@MainActor
private final class CurrentThreadBadgeView: NSView {
    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)

        configurePortalBadgeSurface(self)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        iconView.contentTintColor = NSColor.systemOrange.withAlphaComponent(0.98)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        textField.textColor = NSColor.white.withAlphaComponent(0.90)

        addSubview(iconView)
        addSubview(textField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, symbolName: String) {
        textField.stringValue = title
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
    }
}
