import AppKit
import EarPodsCore

enum CipherSetupMode {
    case initialSetup
    case rekey

    var title: String {
        switch self {
        case .initialSetup:
            return "Set Your Cipher"
        case .rekey:
            return "Rekey Cipher"
        }
    }

    var subtitle: String {
        switch self {
        case .initialSetup:
            return "Choose a 4-step private unlock code using +, -, center tap, or center double. This is how you reach Cipher later. Repeat it once to confirm. Hold - to clear and try again."
        case .rekey:
            return "Choose a new 4-step unlock code using +, -, center tap, or center double. Repeat it once to confirm. Hold - to clear. Hold center before saving to cancel and keep your current Cipher."
        }
    }

    var recordingFooter: String {
        switch self {
        case .initialSetup:
            return "Enter your 4-step code. Hold - anytime to clear and start over."
        case .rekey:
            return "Enter a new 4-step code. Hold center now to cancel and keep your current Cipher."
        }
    }

    var resetFooter: String {
        switch self {
        case .initialSetup:
            return "Cleared. Enter a new 4-step Cipher now."
        case .rekey:
            return "Cleared. Enter a new 4-step Cipher or hold center to cancel."
        }
    }

    var confirmingFooter: String {
        switch self {
        case .initialSetup:
            return "Repeat the same code once more. Hold - to clear and choose a different one."
        case .rekey:
            return "Repeat the same code once more. Hold - to clear, or hold center to cancel and keep your current Cipher."
        }
    }

    var mismatchFooter: String {
        switch self {
        case .initialSetup:
            return "That didn’t match. Repeat the same 4-step code again."
        case .rekey:
            return "That didn’t match. Repeat the same 4-step code again, or hold center to cancel."
        }
    }

    var readyFooter: String {
        switch self {
        case .initialSetup:
            return "Perfect. Hold center now to save your Cipher and finish first-run setup."
        case .rekey:
            return "Perfect. Hold center now to save your new Cipher."
        }
    }

    var blockedSaveHint: String {
        switch self {
        case .initialSetup:
            return "Record 4 steps, repeat them exactly, then hold center to save your Cipher."
        case .rekey:
            return "Repeat your new code exactly, then hold center to save it. Hold center before that to cancel and keep your current Cipher."
        }
    }

    var allowsCancellationBeforeSave: Bool {
        self == .rekey
    }
}

@MainActor
enum CipherSetupAppendResult {
    case ignored
    case recorded(step: Int, total: Int)
    case movedToConfirmation
    case confirmationProgress(step: Int, total: Int)
    case mismatch
    case ready
}

@MainActor
final class CipherSetupController {
    private enum Phase {
        case recording
        case confirming
        case ready
    }

    let mode: CipherSetupMode
    private let window: CipherSetupWindow
    private let stageField: NSTextField
    private let footerField: NSTextField
    private let entrySlots: [CipherStepSlotView]
    private let confirmSlots: [CipherStepSlotView]

    private var phase: Phase = .recording
    private var recordedSequence: [GestureKind] = []
    private var confirmationSequence: [GestureKind] = []

    init(mode: CipherSetupMode) {
        self.mode = mode

        let titleField = NSTextField(labelWithString: mode.title)
        stylePortalTitle(titleField, alignment: .left)

        let subtitleField = NSTextField(wrappingLabelWithString: mode.subtitle)
        stylePortalSubtitle(subtitleField, alignment: .left)
        subtitleField.maximumNumberOfLines = 0

        self.stageField = NSTextField(labelWithString: "")
        self.stageField.translatesAutoresizingMaskIntoConstraints = false
        self.stageField.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        self.stageField.textColor = NSColor.systemMint.withAlphaComponent(0.96)

        let entryTitle = NSTextField(labelWithString: "Code")
        entryTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        entryTitle.textColor = NSColor.white.withAlphaComponent(0.68)

        let confirmTitle = NSTextField(labelWithString: "Confirm")
        confirmTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        confirmTitle.textColor = NSColor.white.withAlphaComponent(0.68)

        self.entrySlots = (0..<cipherDefaultStepCount).map { _ in CipherStepSlotView() }
        self.confirmSlots = (0..<cipherDefaultStepCount).map { _ in CipherStepSlotView() }

        let entryStack = NSStackView(views: entrySlots)
        entryStack.orientation = .horizontal
        entryStack.alignment = .centerY
        entryStack.spacing = 10

        let confirmStack = NSStackView(views: confirmSlots)
        confirmStack.orientation = .horizontal
        confirmStack.alignment = .centerY
        confirmStack.spacing = 10

        let entryGroup = NSStackView(views: [entryTitle, entryStack])
        entryGroup.orientation = .vertical
        entryGroup.alignment = .leading
        entryGroup.spacing = 8

        let confirmGroup = NSStackView(views: [confirmTitle, confirmStack])
        confirmGroup.orientation = .vertical
        confirmGroup.alignment = .leading
        confirmGroup.spacing = 8

        self.footerField = NSTextField(wrappingLabelWithString: "")
        stylePortalFooter(self.footerField, alignment: .left)
        self.footerField.maximumNumberOfLines = 0

        let contentStack = NSStackView(views: [titleField, subtitleField, stageField, entryGroup, confirmGroup, footerField])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.16,
            cornerRadius: PortalHUDStyle.compactCornerRadius
        )
        chrome.chromeView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),
        ])

        self.window = CipherSetupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 456, height: 342),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(self.window)
        self.window.contentView = chrome.rootView

        updateUI()
    }

    var isVisible: Bool {
        window.isVisible
    }

    var canSave: Bool {
        phase == .ready
    }

    var configuredSequence: [GestureKind]? {
        canSave ? recordedSequence : nil
    }

    func show() -> Bool {
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        showPortalWindow(window)
        return window.isVisible
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func appendStep(_ gesture: GestureKind) -> CipherSetupAppendResult {
        guard GestureKind.cipherAllowedStepSet.contains(gesture) else {
            return .ignored
        }

        switch phase {
        case .recording:
            guard recordedSequence.count < cipherDefaultStepCount else {
                return .ignored
            }
            recordedSequence.append(gesture)
            updateUI()
            if recordedSequence.count == cipherDefaultStepCount {
                phase = .confirming
                updateUI()
                return .movedToConfirmation
            }
            return .recorded(step: recordedSequence.count, total: cipherDefaultStepCount)

        case .confirming:
            let nextIndex = confirmationSequence.count
            guard nextIndex < recordedSequence.count else {
                return .ignored
            }

            if gesture != recordedSequence[nextIndex] {
                confirmationSequence = []
                updateUI(mismatch: true)
                return .mismatch
            }

            confirmationSequence.append(gesture)
            if confirmationSequence.count == recordedSequence.count {
                phase = .ready
                updateUI()
                return .ready
            }

            updateUI()
            return .confirmationProgress(step: confirmationSequence.count, total: cipherDefaultStepCount)

        case .ready:
            return .ignored
        }
    }

    func resetSequence() {
        phase = .recording
        recordedSequence = []
        confirmationSequence = []
        updateUI(reset: true)
    }

    func showBlockedSaveHint() {
        footerField.stringValue = mode.blockedSaveHint
        footerField.textColor = NSColor.systemOrange.withAlphaComponent(0.95)
    }

    private func updateUI(mismatch: Bool = false, reset: Bool = false) {
        for (index, slotView) in entrySlots.enumerated() {
            slotView.configure(gesture: recordedSequence.indices.contains(index) ? recordedSequence[index] : nil)
        }
        for (index, slotView) in confirmSlots.enumerated() {
            slotView.configure(gesture: confirmationSequence.indices.contains(index) ? confirmationSequence[index] : nil)
        }

        switch phase {
        case .recording:
            stageField.stringValue = "Choose 4 steps"
            footerField.stringValue = reset ? mode.resetFooter : mode.recordingFooter
            footerField.textColor = reset
                ? NSColor.systemMint.withAlphaComponent(0.95)
                : NSColor.white.withAlphaComponent(0.60)
        case .confirming:
            stageField.stringValue = "Repeat to confirm"
            footerField.stringValue = mismatch ? mode.mismatchFooter : mode.confirmingFooter
            footerField.textColor = mismatch
                ? NSColor.systemOrange.withAlphaComponent(0.95)
                : NSColor.white.withAlphaComponent(0.60)
        case .ready:
            stageField.stringValue = "Code locked in"
            footerField.stringValue = mode.readyFooter
            footerField.textColor = NSColor.systemGreen.withAlphaComponent(0.95)
        }
    }
}

@MainActor
private final class CipherSetupWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CipherStepSlotView: NSView {
    private let titleField: NSTextField
    private let detailField: NSTextField

    init() {
        self.titleField = NSTextField(labelWithString: "•")
        self.detailField = NSTextField(labelWithString: "Empty")
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleField.alignment = .center

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        detailField.alignment = .center

        addSubview(titleField)
        addSubview(detailField)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 86),
            heightAnchor.constraint(equalToConstant: 66),

            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            detailField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        configure(gesture: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(gesture: GestureKind?) {
        if let gesture {
            titleField.stringValue = gesture.cipherDisplayTitle
            detailField.stringValue = gesture.cipherDisplayDetail
            titleField.textColor = PortalHUDStyle.primaryTextColor
            detailField.textColor = PortalHUDStyle.secondaryTextColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.systemMint.withAlphaComponent(0.18).cgColor
        } else {
            titleField.stringValue = "•"
            detailField.stringValue = "Empty"
            titleField.textColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.30)
            detailField.textColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.26)
            layer?.backgroundColor = PortalHUDStyle.rowIdleFillColor.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = PortalHUDStyle.surfaceBorderColor.cgColor
        }
    }
}
