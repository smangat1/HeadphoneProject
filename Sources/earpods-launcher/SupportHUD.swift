import AppKit
import Foundation

@MainActor
final class SupportCardController {
    private static let rowWidth: CGFloat = 360

    private let window: SupportWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let metadataField: NSTextField
    private let footerField: NSTextField
    private let actionStack: NSStackView
    private var actionRowViews: [SupportActionRowView] = []
    private var currentModel: SupportCardModel?
    private var selectedIndex = 0

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemYellow,
            tintOpacity: 0.10
        )

        titleField = NSTextField(labelWithString: "")
        subtitleField = NSTextField(wrappingLabelWithString: "")
        metadataField = NSTextField(wrappingLabelWithString: "")
        footerField = NSTextField(wrappingLabelWithString: "")
        actionStack = NSStackView()

        stylePortalTitle(titleField)

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        metadataField.translatesAutoresizingMaskIntoConstraints = false
        metadataField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        metadataField.textColor = NSColor.white.withAlphaComponent(0.72)
        metadataField.alignment = .center
        metadataField.maximumNumberOfLines = 8
        metadataField.lineBreakMode = .byWordWrapping

        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        actionStack.orientation = .vertical
        actionStack.alignment = .leading
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [titleField, subtitleField, metadataField, actionStack, footerField])
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

        window = SupportWindow(
            contentRect: NSRect(x: 0, y: 0, width: 476, height: 704),
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

    func currentSelection() -> (action: SupportAction, index: Int)? {
        guard let currentModel, !currentModel.actions.isEmpty else {
            return nil
        }
        return (currentModel.actions[selectedIndex], selectedIndex)
    }

    func show(model: SupportCardModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        update(model: model, selectedIndex: explicitSelectedIndex)
        return revealWindow()
    }

    func update(model: SupportCardModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        currentModel = model
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        metadataField.stringValue = model.metadataText
        footerField.stringValue = model.footer
        rebuildActions(model.actions)
        applySelectionIndex(from: model.actions, explicitSelectedIndex: explicitSelectedIndex)
        applySelection()
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> (action: SupportAction, index: Int)? {
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

    func confirmSelection() -> (action: SupportAction, index: Int)? {
        guard let selection = currentSelection(), selection.action.isEnabled else {
            return nil
        }
        return selection
    }

    private func rebuildActions(_ actions: [SupportAction]) {
        for rowView in actionRowViews {
            actionStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        actionRowViews = actions.map { action in
            let rowView = SupportActionRowView(action: action)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            actionStack.addArrangedSubview(rowView)
            return rowView
        }
    }

    private func applySelectionIndex(from actions: [SupportAction], explicitSelectedIndex: Int?) {
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
private final class SupportWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class SupportActionRowView: NSView {
    private let action: SupportAction
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let detailField: NSTextField

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(action: SupportAction) {
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
        detailField.lineBreakMode = .byWordWrapping
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
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        applyPortalRowSurface(self, state: isSelected ? .selected : .idle)
        iconView.contentTintColor = colorForState(isSelected: isSelected, enabled: action.isEnabled, emphasis: .icon)
        titleField.textColor = colorForState(isSelected: isSelected, enabled: action.isEnabled, emphasis: .primary)
        detailField.textColor = colorForState(isSelected: isSelected, enabled: action.isEnabled, emphasis: .secondary)
    }
}
