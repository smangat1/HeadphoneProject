import AppKit

@MainActor
final class PortalActionFeedbackController {
    private let window: PortalActionFeedbackWindow
    private let symbolContainer: NSView
    private let symbolView: NSImageView
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private var dismissTask: Task<Void, Never>?

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemGreen,
            tintOpacity: 0.16,
            cornerRadius: 34
        )

        self.symbolContainer = NSView()
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false
        symbolContainer.wantsLayer = true
        symbolContainer.layer?.cornerRadius = 34
        symbolContainer.layer?.cornerCurve = .continuous
        symbolContainer.layer?.borderWidth = 1

        self.symbolView = NSImageView()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        symbolContainer.addSubview(symbolView)

        self.titleField = NSTextField(labelWithString: "")
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleField.textColor = .white
        titleField.alignment = .center

        self.subtitleField = NSTextField(labelWithString: "")
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        subtitleField.textColor = NSColor.white.withAlphaComponent(0.68)
        subtitleField.alignment = .center

        let stackView = NSStackView(views: [symbolContainer, titleField, subtitleField])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        chrome.chromeView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: chrome.chromeView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: chrome.chromeView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: chrome.chromeView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: chrome.chromeView.trailingAnchor, constant: -20),

            symbolContainer.widthAnchor.constraint(equalToConstant: 68),
            symbolContainer.heightAnchor.constraint(equalToConstant: 68),
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
        ])

        self.window = PortalActionFeedbackWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 188),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(self.window)
        self.window.alphaValue = 0
        self.window.contentView = chrome.rootView
    }

    @discardableResult
    func pulse(
        title: String,
        subtitle: String,
        symbolName: String = "checkmark",
        accessibilityDescription: String = "Action confirmed",
        accentColor: NSColor = .systemGreen
    ) -> Bool {
        configure(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accessibilityDescription: accessibilityDescription,
            accentColor: accentColor
        )

        dismissTask?.cancel()
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        showPortalWindow(window)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        dismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }

            self.window.alphaValue = 0
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else { return }
            self.window.orderOut(nil)
        }

        return window.isVisible
    }

    func close() {
        dismissTask?.cancel()
        dismissTask = nil
        window.orderOut(nil)
    }

    private func configure(
        title: String,
        subtitle: String,
        symbolName: String,
        accessibilityDescription: String,
        accentColor: NSColor
    ) {
        titleField.stringValue = title
        subtitleField.stringValue = subtitle
        symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        symbolView.contentTintColor = accentColor.withAlphaComponent(0.98)
        symbolContainer.layer?.backgroundColor = accentColor.withAlphaComponent(0.14).cgColor
        symbolContainer.layer?.borderColor = accentColor.withAlphaComponent(0.30).cgColor
    }
}

@MainActor
private final class PortalActionFeedbackWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
