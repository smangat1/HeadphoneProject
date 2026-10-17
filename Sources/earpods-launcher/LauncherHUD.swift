import AppKit

@MainActor var portalHUDDebugSink: ((String) -> Void)?

@MainActor
final class LauncherHUDController {
    private let items: [LauncherItem]
    private let idleTimeout: TimeInterval
    private let panel: LauncherWindow
    private let stackView: NSStackView
    private let rowViews: [LauncherRowView]
    private var idleTimer: Timer?
    private var selectedIndex = 0
    private static let rowWidth: CGFloat = 300

    init(items: [LauncherItem], idleTimeout: TimeInterval) {
        self.items = items
        self.idleTimeout = idleTimeout

        debugHUD("init begin")

        self.stackView = NSStackView()
        self.stackView.orientation = .vertical
        self.stackView.alignment = .leading
        self.stackView.spacing = 8
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        debugHUD("stack view ready")

        var builtRowViews: [LauncherRowView] = []
        builtRowViews.reserveCapacity(items.count)
        for item in items {
            debugHUD("row init begin \(item.id): \(item.title)")
            let rowView = LauncherRowView(item: item)
            debugHUD("row init complete \(item.id): \(item.title)")
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            stackView.addArrangedSubview(rowView)
            debugHUD("row attached \(item.id): \(item.title)")
            builtRowViews.append(rowView)
        }
        self.rowViews = builtRowViews
        debugHUD("rows ready")

        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.12,
            cornerRadius: PortalHUDStyle.compactCornerRadius
        )
        debugHUD("container ready")

        chrome.chromeView.addSubview(stackView)
        debugHUD("content wrapper ready")

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalToConstant: Self.rowWidth),
        ])

        let rowHeight = CGFloat(42)
        for rowView in rowViews {
            rowView.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }

        let panelHeight = (CGFloat(items.count) * rowHeight) + (CGFloat(max(items.count - 1, 0)) * stackView.spacing) + 32
        let panelFrame = NSRect(x: 0, y: 0, width: Self.rowWidth + 32, height: panelHeight)
        debugHUD("window init begin")
        self.panel = LauncherWindow(
            contentRect: panelFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        debugHUD("window init complete")
        debugHUD("window configure begin")
        applyPortalFloatingWindowStyle(self.panel)
        debugHUD("window background clear")
        debugHUD("window opaque disabled")
        debugHUD("window shadow enabled")
        debugHUD("window release-on-close disabled")
        self.panel.contentView = chrome.rootView
        debugHUD("window content attached")
        debugHUD("window configure complete")

        updateSelection()
        debugHUD("init complete")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func currentSelection() -> (item: LauncherItem, index: Int)? {
        guard !items.isEmpty else {
            return nil
        }
        return (items[selectedIndex], selectedIndex)
    }

    @discardableResult
    func show(selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        guard !items.isEmpty else {
            return false
        }

        debugHUD("show begin")
        if let explicitSelectedIndex {
            selectedIndex = min(max(explicitSelectedIndex, 0), items.count - 1)
        }
        updateSelection()
        debugHUD("show selection reset")
        centerPortalWindow(panel)
        debugHUD("show positioned")
        panel.level = .statusBar
        debugHUD("show level statusBar")
        panel.ignoresMouseEvents = true
        debugHUD("show ignoresMouseEvents enabled")
        resetIdleTimer()
        debugHUD("show idle timer reset")
        showPortalWindow(panel)
        debugHUD("show ordered front")
        debugHUD("show displayIfNeeded visible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)")
        return panel.isVisible
    }

    @discardableResult
    func close() -> Bool {
        idleTimer?.invalidate()
        idleTimer = nil
        panel.orderOut(nil)
        return !panel.isVisible
    }

    @discardableResult
    func moveSelection(by delta: Int) -> (item: LauncherItem, index: Int)? {
        guard !items.isEmpty else {
            return nil
        }

        selectedIndex = (selectedIndex + delta + items.count) % items.count
        updateSelection()
        resetIdleTimer()
        return currentSelection()
    }

    func confirmSelection() -> (item: LauncherItem, index: Int)? {
        guard !items.isEmpty else {
            return nil
        }

        let item = items[selectedIndex]
        let index = selectedIndex
        close()
        return (item, index)
    }

    private func updateSelection() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

}

@MainActor
private final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum SetupStep: CaseIterable, Hashable {
    case volumeUp
    case volumeDown
    case centerTap

    var symbol: String {
        switch self {
        case .volumeUp:
            return "plus.circle"
        case .volumeDown:
            return "minus.circle"
        case .centerTap:
            return "button.horizontal.top.press"
        }
    }

    var text: String {
        switch self {
        case .volumeUp:
            return "Press + once to move upward."
        case .volumeDown:
            return "Press - once to move downward."
        case .centerTap:
            return "Tap center once for a quick confirm click."
        }
    }
}

@MainActor
final class SetupOverlayController {
    private let panel: LauncherWindow
    private let footerField: NSTextField
    private let stepViews: [SetupStep: SetupInstructionRowView]
    private var completedSteps: Set<SetupStep> = []

    init() {
        let titleField = NSTextField(labelWithString: "Inlay Setup")
        stylePortalTitle(titleField, alignment: .left)

        let subtitleField = NSTextField(wrappingLabelWithString: "Do each action once. This setup stays on screen until you prove the controls, then you hold center to finish.")
        stylePortalSubtitle(subtitleField, alignment: .left)
        subtitleField.maximumNumberOfLines = 0

        let instructionsStack = NSStackView()
        instructionsStack.orientation = .vertical
        instructionsStack.alignment = .leading
        instructionsStack.spacing = 10
        instructionsStack.translatesAutoresizingMaskIntoConstraints = false

        var stepViews: [SetupStep: SetupInstructionRowView] = [:]
        for step in SetupStep.allCases {
            let rowView = SetupInstructionRowView(step: step)
            stepViews[step] = rowView
            rowView.widthAnchor.constraint(equalTo: instructionsStack.widthAnchor).isActive = true
            instructionsStack.addArrangedSubview(rowView)
        }
        self.stepViews = stepViews

        self.footerField = NSTextField(labelWithString: "Finish the checklist, then hold center to close setup.")
        stylePortalFooter(self.footerField, alignment: .left)

        let stackView = NSStackView(views: [titleField, subtitleField, instructionsStack, self.footerField])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.14,
            cornerRadius: PortalHUDStyle.compactCornerRadius
        )
        chrome.chromeView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            stackView.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            stackView.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            stackView.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalToConstant: 360),
        ])

        self.panel = LauncherWindow(
            contentRect: NSRect(x: 0, y: 0, width: 404, height: 244),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(self.panel)
        self.panel.contentView = chrome.rootView
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var canDismiss: Bool {
        completedSteps.count == SetupStep.allCases.count
    }

    @discardableResult
    func show() -> Bool {
        centerPortalWindow(panel)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        showPortalWindow(panel)
        return panel.isVisible
    }

    @discardableResult
    func close() -> Bool {
        panel.orderOut(nil)
        return !panel.isVisible
    }

    func markCompleted(_ step: SetupStep) {
        guard !completedSteps.contains(step) else {
            return
        }

        completedSteps.insert(step)
        stepViews[step]?.isComplete = true
        updateFooter()
    }

    func showBlockedDismissalHint() {
        footerField.stringValue = "Finish +, -, and tap center before you hold center to leave setup."
        footerField.textColor = NSColor.systemOrange.withAlphaComponent(0.95)
    }

    private func updateFooter() {
        if canDismiss {
            footerField.stringValue = "Nice. Hold center now to finish setup and go silent."
            footerField.textColor = NSColor.systemGreen.withAlphaComponent(0.95)
        } else {
            footerField.stringValue = "Finish the checklist, then hold center to close setup."
            footerField.textColor = NSColor.white.withAlphaComponent(0.60)
        }
    }
}

@MainActor
private final class LauncherRowView: NSView {
    private let iconView: NSImageView
    private let titleField: NSTextField

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(item: LauncherItem) {
        self.iconView = NSImageView()
        self.titleField = NSTextField(labelWithString: item.title)
        super.init(frame: .zero)

        configurePortalRowSurface(self)
        debugHUD("row view configure surface \(item.id)")

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        debugHUD("row view symbol lookup begin \(item.id) symbol=\(item.symbol)")
        iconView.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title) ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: item.title)
        debugHUD("row view symbol lookup complete \(item.id) symbol=\(item.symbol)")

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail

        addSubview(iconView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
        debugHUD("row view appearance ready \(item.id)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        if isSelected {
            applyPortalRowSurface(self, state: .selected)
            titleField.textColor = PortalHUDStyle.primaryTextColor
            iconView.contentTintColor = PortalHUDStyle.primaryTextColor
        } else {
            applyPortalRowSurface(self, state: .idle)
            titleField.textColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.86)
            iconView.contentTintColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.72)
        }
    }
}

@MainActor
private final class SetupInstructionRowView: NSView {
    private let statusIconView: NSImageView
    private let textField: NSTextField

    var isComplete: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(step: SetupStep) {
        self.textField = NSTextField(wrappingLabelWithString: step.text)
        self.statusIconView = NSImageView()
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: step.symbol, accessibilityDescription: step.text)
            ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: step.text)
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.88)

        self.textField.translatesAutoresizingMaskIntoConstraints = false
        self.textField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.textField.maximumNumberOfLines = 0

        self.statusIconView.translatesAutoresizingMaskIntoConstraints = false
        self.statusIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)

        addSubview(iconView)
        addSubview(self.textField)
        addSubview(self.statusIconView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            self.textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            self.textField.topAnchor.constraint(equalTo: topAnchor),
            self.textField.bottomAnchor.constraint(equalTo: bottomAnchor),

            self.statusIconView.leadingAnchor.constraint(equalTo: self.textField.trailingAnchor, constant: 10),
            self.statusIconView.trailingAnchor.constraint(equalTo: trailingAnchor),
            self.statusIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.statusIconView.widthAnchor.constraint(equalToConstant: 18),
            self.statusIconView.heightAnchor.constraint(equalToConstant: 18),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        if isComplete {
            textField.textColor = NSColor.systemGreen.withAlphaComponent(0.95)
            statusIconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "completed")
            statusIconView.contentTintColor = NSColor.systemGreen.withAlphaComponent(0.95)
        } else {
            textField.textColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.90)
            statusIconView.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "incomplete")
            statusIconView.contentTintColor = PortalHUDStyle.quaternaryTextColor
        }
    }
}

@MainActor
private func debugHUD(_ message: String) {
    portalHUDDebugSink?(message)
    print("[HUD INIT] \(message)")
    fflush(stdout)
}
