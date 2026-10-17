import AppKit
import EarPodsCore
import Foundation

enum OnboardingPageID: String, Codable, Sendable {
    case launcher
    case timer
    case nowPlaying
}

enum OnboardingStepID: String, Codable, Hashable, Sendable {
    case volumeUp
    case volumeDown
    case centerTap
    case centerDouble
    case centerHold
}

struct OnboardingStep: Hashable, Sendable {
    let id: OnboardingStepID
    let symbol: String
    let text: String
}

struct OnboardingPageModel: Sendable {
    let id: OnboardingPageID
    let title: String
    let subtitle: String
    let highlightsTitle: String?
    let highlights: [String]
    let steps: [OnboardingStep]
    let dismissalGesture: GestureKind
    let dismissalStepID: OnboardingStepID?
    let blockedDismissalHint: String
    let defaultFooter: String
    let readyFooter: String
    let persistCompletion: Bool

    var stepIDs: Set<OnboardingStepID> {
        Set(steps.map(\.id))
    }

    func containsStep(_ stepID: OnboardingStepID) -> Bool {
        stepIDs.contains(stepID)
    }

    var stepsRequiredBeforeDismiss: Set<OnboardingStepID> {
        if let dismissalStepID {
            return stepIDs.subtracting([dismissalStepID])
        }
        return stepIDs
    }

    static let launcher = OnboardingPageModel(
        id: .launcher,
        title: "Welcome to Inlay",
        subtitle: "Inlay is a hidden layer for resuming context, capturing threads, and controlling a few focused parts of your Mac from the EarPods buttons. Prove the core launcher controls once, then it stays quiet in the background.",
        highlightsTitle: "What It’s Best At",
        highlights: [
            "Companion handles short commands like timers, searches, apps, capture, and undo.",
            "Current Thread names what you are doing right now.",
            "Work Queue stages threads you want to return to later.",
            "Support handles permissions, recovery, and current limits."
        ],
        steps: [
            OnboardingStep(id: .volumeUp, symbol: "plus.circle", text: "Press + once to move upward."),
            OnboardingStep(id: .volumeDown, symbol: "minus.circle", text: "Press - once to move downward."),
            OnboardingStep(id: .centerTap, symbol: "button.horizontal.top.press", text: "Tap center once for a quick confirm click."),
        ],
        dismissalGesture: .centerHold,
        dismissalStepID: nil,
        blockedDismissalHint: "Finish +, -, and tap center before you hold center to leave setup.",
        defaultFooter: "Finish the checklist, then hold center to finish setup. After that Inlay stays silent until you call it.",
        readyFooter: "Nice. Hold center now to finish setup, then choose your Cipher.",
        persistCompletion: false
    )

    static let timer = OnboardingPageModel(
        id: .timer,
        title: "Timer Controls",
        subtitle: "Timer uses a richer control map. Do each move once so the page feels natural before you use it.",
        highlightsTitle: nil,
        highlights: [],
        steps: [
            OnboardingStep(id: .volumeUp, symbol: "plus.circle", text: "Press + once to adjust the current timer row upward."),
            OnboardingStep(id: .volumeDown, symbol: "minus.circle", text: "Press - once to adjust the current timer row downward."),
            OnboardingStep(id: .centerTap, symbol: "arrow.down.circle", text: "Tap center once to move forward to the next timer row."),
            OnboardingStep(id: .centerDouble, symbol: "arrow.uturn.backward.circle", text: "Double-tap center once to move back to the previous timer row."),
            OnboardingStep(id: .centerHold, symbol: "hand.tap.fill", text: "Hold center once to leave Timer and go back to the launcher."),
        ],
        dismissalGesture: .centerHold,
        dismissalStepID: .centerHold,
        blockedDismissalHint: "Do +, -, tap center, and double-tap center before you hold center to finish Timer training.",
        defaultFooter: "Finish the checklist. Center hold will only complete training after the other steps are done.",
        readyFooter: "Perfect. Hold center now to finish Timer training and continue.",
        persistCompletion: true
    )
}

final class OnboardingStateStore {
    private struct StoredState: Codable {
        var completedPages: Set<OnboardingPageID>
    }

    private let path: String
    private var completedPages: Set<OnboardingPageID> = []

    init(path: String) throws {
        self.path = normalizePath(path)
        try load()
    }

    func isCompleted(_ pageID: OnboardingPageID) -> Bool {
        completedPages.contains(pageID)
    }

    func markCompleted(_ pageID: OnboardingPageID) throws {
        guard !completedPages.contains(pageID) else {
            return
        }

        completedPages.insert(pageID)
        try persist()
    }

    private func load() throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else {
            completedPages = []
            return
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            completedPages = []
            return
        }

        let decoded = try JSONDecoder().decode(StoredState.self, from: data)
        completedPages = decoded.completedPages
    }

    private func persist() throws {
        let url = URL(fileURLWithPath: path)
        let data = try JSONEncoder().encode(StoredState(completedPages: completedPages))
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
final class PageOnboardingController {
    private let model: OnboardingPageModel
    private let panel: OnboardingWindow
    private let footerField: NSTextField
    private let stepViews: [OnboardingStepID: OnboardingInstructionRowView]
    private var completedSteps: Set<OnboardingStepID> = []

    init(model: OnboardingPageModel) {
        self.model = model

        let titleField = NSTextField(labelWithString: model.title)
        stylePortalTitle(titleField, alignment: .left)

        let subtitleField = NSTextField(wrappingLabelWithString: model.subtitle)
        stylePortalSubtitle(subtitleField, alignment: .left)
        subtitleField.maximumNumberOfLines = 0

        let highlightsViews: [NSView]
        if !model.highlights.isEmpty {
            let highlightsTitleField = NSTextField(labelWithString: model.highlightsTitle ?? "What Inlay Does")
            highlightsTitleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            highlightsTitleField.textColor = NSColor.systemMint.withAlphaComponent(0.94)

            let highlightStack = NSStackView()
            highlightStack.orientation = .vertical
            highlightStack.alignment = .leading
            highlightStack.spacing = 6
            highlightStack.translatesAutoresizingMaskIntoConstraints = false

            for highlight in model.highlights {
                let row = NSTextField(wrappingLabelWithString: "• \(highlight)")
                row.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                row.textColor = NSColor.white.withAlphaComponent(0.74)
                row.maximumNumberOfLines = 2
                row.lineBreakMode = .byWordWrapping
                row.translatesAutoresizingMaskIntoConstraints = false
                row.widthAnchor.constraint(equalTo: highlightStack.widthAnchor).isActive = true
                highlightStack.addArrangedSubview(row)
            }

            highlightsViews = [highlightsTitleField, highlightStack]
        } else {
            highlightsViews = []
        }

        let instructionsStack = NSStackView()
        instructionsStack.orientation = .vertical
        instructionsStack.alignment = .leading
        instructionsStack.spacing = 10
        instructionsStack.translatesAutoresizingMaskIntoConstraints = false

        var stepViews: [OnboardingStepID: OnboardingInstructionRowView] = [:]
        for step in model.steps {
            let rowView = OnboardingInstructionRowView(step: step)
            stepViews[step.id] = rowView
            rowView.widthAnchor.constraint(equalTo: instructionsStack.widthAnchor).isActive = true
            instructionsStack.addArrangedSubview(rowView)
        }
        self.stepViews = stepViews

        self.footerField = NSTextField(labelWithString: model.defaultFooter)
        stylePortalFooter(self.footerField, alignment: .left)

        let stackView = NSStackView(views: [titleField, subtitleField] + highlightsViews + [instructionsStack, self.footerField])
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

        let panelHeight = 176 + (CGFloat(model.steps.count) * 32) + (CGFloat(model.highlights.count) * 26) + (model.highlights.isEmpty ? 0 : 40)
        self.panel = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 404, height: panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(self.panel)
        self.panel.contentView = chrome.rootView
    }

    var pageID: OnboardingPageID {
        model.id
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var canDismissNow: Bool {
        model.stepsRequiredBeforeDismiss.isSubset(of: completedSteps)
    }

    func containsStep(_ stepID: OnboardingStepID) -> Bool {
        model.containsStep(stepID)
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

    @discardableResult
    func markCompleted(_ stepID: OnboardingStepID) -> Bool {
        guard containsStep(stepID), !completedSteps.contains(stepID) else {
            return false
        }

        completedSteps.insert(stepID)
        stepViews[stepID]?.isComplete = true
        updateFooter()
        return true
    }

    func showBlockedDismissalHint() {
        footerField.stringValue = model.blockedDismissalHint
        footerField.textColor = NSColor.systemOrange.withAlphaComponent(0.95)
    }

    private func updateFooter() {
        if canDismissNow {
            footerField.stringValue = model.readyFooter
            footerField.textColor = NSColor.systemGreen.withAlphaComponent(0.95)
        } else {
            footerField.stringValue = model.defaultFooter
            footerField.textColor = NSColor.white.withAlphaComponent(0.60)
        }
    }
}

@MainActor
private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class OnboardingInstructionRowView: NSView {
    private let statusIconView: NSImageView
    private let textField: NSTextField

    var isComplete: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(step: OnboardingStep) {
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
