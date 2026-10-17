import AppKit

enum CompanionPhase {
    case listening
    case thinking
    case acting
    case success
    case failure
}

enum CompanionCardPresentationMode {
    case full
    case compact
}

enum CompanionCardAnchorMode {
    case center
    case topTrailing
}

struct CompanionCardModel {
    let title: String
    let subtitle: String
    let transcript: String
    let footer: String
    let symbol: String
    let phase: CompanionPhase
    let domain: CompanionCommandDomain
    let learningNote: String?
    let quickActions: [CompanionQuickAction]
}

@MainActor
final class CompanionCardController {
    private static let quickActionMinHeight: CGFloat = 54

    private let window: CompanionWindow
    private let symbolView: NSImageView
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let domainField: NSTextField
    private let learningField: NSTextField
    private let transcriptScrollView: NSScrollView
    private let transcriptTextView: NSTextView
    private let actionsSurface: NSView
    private let actionsStack: NSStackView
    private let inputField: CompanionInputField
    private let footerField: NSTextField
    private let actionsHeightConstraint: NSLayoutConstraint
    private let transcriptHeightConstraint: NSLayoutConstraint
    private var actionRowViews: [CompanionQuickActionRowView] = []
    private var currentModel: CompanionCardModel?
    private var presentationMode: CompanionCardPresentationMode = .full
    private var anchorMode: CompanionCardAnchorMode = .center
    private var selectedActionIndex = 0
    var onSubmit: ((String) -> Void)?
    var onTextDidBegin: (() -> Void)?

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemTeal,
            tintOpacity: 0.12
        )

        symbolView = NSImageView()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        symbolView.contentTintColor = PortalHUDStyle.primaryTextColor

        titleField = NSTextField(labelWithString: "")
        stylePortalTitle(titleField)

        subtitleField = NSTextField(wrappingLabelWithString: "")
        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        domainField = NSTextField(labelWithString: "")
        domainField.translatesAutoresizingMaskIntoConstraints = false
        domainField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        domainField.textColor = NSColor.systemTeal.withAlphaComponent(0.92)
        domainField.alignment = .center
        domainField.maximumNumberOfLines = 2

        learningField = NSTextField(wrappingLabelWithString: "")
        learningField.translatesAutoresizingMaskIntoConstraints = false
        learningField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        learningField.textColor = NSColor.systemGreen.withAlphaComponent(0.94)
        learningField.alignment = .center
        learningField.maximumNumberOfLines = 2
        learningField.isHidden = true

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        transcriptTextView = NSTextView(frame: .zero, textContainer: textContainer)
        transcriptTextView.translatesAutoresizingMaskIntoConstraints = false
        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = false
        transcriptTextView.drawsBackground = false
        transcriptTextView.isRichText = false
        transcriptTextView.importsGraphics = false
        transcriptTextView.usesFindBar = false
        transcriptTextView.textContainerInset = NSSize(width: 0, height: 2)
        transcriptTextView.textContainer?.lineFragmentPadding = 0
        transcriptTextView.textColor = PortalHUDStyle.primaryTextColor
        transcriptTextView.minSize = NSSize(width: 0, height: 0)
        transcriptTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        transcriptTextView.isVerticallyResizable = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.autoresizingMask = [.width]

        transcriptScrollView = NSScrollView()
        transcriptScrollView.translatesAutoresizingMaskIntoConstraints = false
        transcriptScrollView.drawsBackground = false
        transcriptScrollView.borderType = .noBorder
        transcriptScrollView.hasVerticalScroller = true
        transcriptScrollView.hasHorizontalScroller = false
        transcriptScrollView.autohidesScrollers = true
        transcriptScrollView.scrollerStyle = .overlay
        transcriptScrollView.documentView = transcriptTextView

        actionsSurface = NSView()
        actionsSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(actionsSurface, cornerRadius: 16)
        applyPortalRowSurface(actionsSurface, state: .muted)

        actionsStack = NSStackView()
        actionsStack.orientation = .vertical
        actionsStack.alignment = .centerX
        actionsStack.distribution = .fill
        actionsStack.spacing = 8
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsSurface.addSubview(actionsStack)

        inputField = CompanionInputField()

        footerField = NSTextField(wrappingLabelWithString: "")
        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        let transcriptSurface = NSView()
        transcriptSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(transcriptSurface, cornerRadius: 18)
        applyPortalRowSurface(transcriptSurface, state: .idle)
        transcriptSurface.addSubview(transcriptScrollView)

        let inputSurface = NSView()
        inputSurface.translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(inputSurface, cornerRadius: 16)
        applyPortalRowSurface(inputSurface, state: .muted)
        inputSurface.addSubview(inputField)

        let contentStack = NSStackView(views: [symbolView, titleField, subtitleField, domainField, learningField, transcriptSurface, actionsSurface, inputSurface, footerField])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        chrome.chromeView.addSubview(contentStack)

        actionsHeightConstraint = actionsSurface.heightAnchor.constraint(equalToConstant: 0)
        transcriptHeightConstraint = transcriptSurface.heightAnchor.constraint(equalToConstant: 176)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),

            domainField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            learningField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            transcriptSurface.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            transcriptHeightConstraint,
            transcriptScrollView.leadingAnchor.constraint(equalTo: transcriptSurface.leadingAnchor, constant: 16),
            transcriptScrollView.trailingAnchor.constraint(equalTo: transcriptSurface.trailingAnchor, constant: -12),
            transcriptScrollView.topAnchor.constraint(equalTo: transcriptSurface.topAnchor, constant: 12),
            transcriptScrollView.bottomAnchor.constraint(equalTo: transcriptSurface.bottomAnchor, constant: -12),

            actionsSurface.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            actionsHeightConstraint,
            actionsStack.leadingAnchor.constraint(equalTo: actionsSurface.leadingAnchor, constant: 10),
            actionsStack.trailingAnchor.constraint(equalTo: actionsSurface.trailingAnchor, constant: -10),
            actionsStack.topAnchor.constraint(equalTo: actionsSurface.topAnchor, constant: 10),
            actionsStack.bottomAnchor.constraint(equalTo: actionsSurface.bottomAnchor, constant: -10),

            inputSurface.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            inputField.leadingAnchor.constraint(equalTo: inputSurface.leadingAnchor, constant: 14),
            inputField.trailingAnchor.constraint(equalTo: inputSurface.trailingAnchor, constant: -14),
            inputField.topAnchor.constraint(equalTo: inputSurface.topAnchor, constant: 10),
            inputField.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -10),
        ])

        window = CompanionWindow(
            contentRect: NSRect(x: 0, y: 0, width: 476, height: 548),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(window)
        window.contentView = chrome.rootView

        inputField.onSubmit = { [weak self] text in
            self?.onSubmit?(text)
        }
        inputField.onTextDidBegin = { [weak self] in
            self?.onTextDidBegin?()
        }
    }

    var isVisible: Bool {
        window.isVisible
    }

    var currentPresentationMode: CompanionCardPresentationMode {
        presentationMode
    }

    var currentAnchorMode: CompanionCardAnchorMode {
        anchorMode
    }

    func show(
        model: CompanionCardModel,
        mode: CompanionCardPresentationMode = .full,
        anchor: CompanionCardAnchorMode? = nil
    ) -> Bool {
        presentationMode = mode
        anchorMode = anchor ?? (mode == .compact ? .topTrailing : .center)
        update(model: model)
        positionWindowForCurrentState()
        window.level = .statusBar
        window.ignoresMouseEvents = false
        showPortalWindow(window, makeKey: true)
        window.contentView?.layoutSubtreeIfNeeded()
        layoutTranscriptDocument()
        window.makeFirstResponder(inputField)
        return window.isVisible
    }

    func update(model: CompanionCardModel) {
        let previousMode = presentationMode
        let previousFrameSize = window.frame.size
        if presentationMode == .compact,
           (!model.quickActions.isEmpty || !(model.learningNote ?? "").isEmpty) {
            presentationMode = .full
        }

        currentModel = model
        applyPresentationMode(using: model)
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        let domainLabel = model.quickActions.isEmpty && model.domain == .unknown
            ? ""
            : "\(model.domain.title) Domain"
        domainField.stringValue = model.quickActions.contains(where: \.teachesCompanion)
            ? "\(domainLabel.isEmpty ? "Companion" : domainLabel) • Choosing an option teaches Companion"
            : domainLabel
        domainField.isHidden = domainField.stringValue.isEmpty
        learningField.stringValue = model.learningNote ?? ""
        learningField.isHidden = (model.learningNote ?? "").isEmpty

        transcriptTextView.textStorage?.setAttributedString(
            makeTranscriptAttributedString(from: model.transcript, phase: model.phase)
        )
        rebuildQuickActions(model.quickActions)
        footerField.stringValue = model.footer
        symbolView.image = NSImage(systemSymbolName: model.symbol, accessibilityDescription: model.title)
        symbolView.contentTintColor = tintColor(for: model.phase)
        window.contentView?.layoutSubtreeIfNeeded()
        layoutTranscriptDocument()
        transcriptTextView.needsLayout = true
        transcriptTextView.needsDisplay = true
        transcriptScrollView.contentView.needsLayout = true
        transcriptScrollView.contentView.needsDisplay = true
        scrollTranscriptToBottom()
        let resized = previousFrameSize != window.frame.size
        if window.isVisible, (previousMode != presentationMode || resized) {
            positionWindowForCurrentState()
        }
        window.displayIfNeeded()
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func clearInput() {
        inputField.stringValue = ""
    }

    private func tintColor(for phase: CompanionPhase) -> NSColor {
        switch phase {
        case .listening:
            return NSColor.systemTeal
        case .thinking:
            return NSColor.systemIndigo
        case .acting, .success:
            return NSColor.systemGreen
        case .failure:
            return NSColor.systemOrange
        }
    }

    private func applyPresentationMode(using model: CompanionCardModel) {
        switch presentationMode {
        case .full:
            let anchoredCompact = anchorMode == .topTrailing
            titleField.font = NSFont.systemFont(ofSize: anchoredCompact ? 20 : 22, weight: .bold)
            subtitleField.font = NSFont.systemFont(ofSize: anchoredCompact ? 12 : 13, weight: .medium)
            footerField.maximumNumberOfLines = 2
            transcriptHeightConstraint.constant = anchoredCompact ? 124 : 176
            if anchoredCompact {
                let quickActionHeight = model.quickActions.isEmpty
                    ? CGFloat.zero
                    : (CGFloat(model.quickActions.count) * Self.quickActionMinHeight)
                        + (CGFloat(max(model.quickActions.count - 1, 0)) * actionsStack.spacing)
                        + 20
                let learningHeight: CGFloat = (model.learningNote ?? "").isEmpty ? 0 : 18
                let anchoredHeight = min(496, max(360, 286 + min(quickActionHeight, 136) + learningHeight))
                window.setContentSize(NSSize(width: 412, height: anchoredHeight))
            } else {
                window.setContentSize(NSSize(width: 476, height: 548))
            }
        case .compact:
            titleField.font = NSFont.systemFont(ofSize: 19, weight: .bold)
            subtitleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            footerField.maximumNumberOfLines = 2
            transcriptHeightConstraint.constant = 92
            let compactHeight: CGFloat = model.quickActions.isEmpty ? 276 : 340
            window.setContentSize(NSSize(width: 364, height: compactHeight))
        }
    }

    private func positionWindowForCurrentState() {
        switch anchorMode {
        case .center:
            centerPortalWindow(window)
        case .topTrailing:
            topTrailingPortalWindow(window)
        }
    }

    private func scrollTranscriptToBottom() {
        transcriptTextView.layoutManager?.ensureLayout(for: transcriptTextView.textContainer!)
        let endRange = NSRange(location: transcriptTextView.string.utf16.count, length: 0)
        transcriptTextView.scrollRangeToVisible(endRange)
    }

    private func layoutTranscriptDocument() {
        guard let textContainer = transcriptTextView.textContainer,
              let layoutManager = transcriptTextView.layoutManager else {
            return
        }

        let availableWidth = max(transcriptScrollView.contentSize.width, 240)
        textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true
        transcriptTextView.minSize = NSSize(width: availableWidth, height: transcriptScrollView.contentSize.height)
        transcriptTextView.maxSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        transcriptTextView.frame = NSRect(origin: .zero, size: NSSize(width: availableWidth, height: transcriptScrollView.contentSize.height))
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let desiredHeight = max(transcriptScrollView.contentSize.height, ceil(usedRect.height) + (transcriptTextView.textContainerInset.height * 2) + 8)
        transcriptTextView.frame = NSRect(origin: .zero, size: NSSize(width: availableWidth, height: desiredHeight))
    }

    func moveQuickActionSelection(by delta: Int) -> CompanionQuickAction? {
        guard let currentModel, !currentModel.quickActions.isEmpty else {
            return nil
        }

        let enabledStates = currentModel.quickActions.map(\.isEnabled)
        guard enabledStates.contains(true) else {
            return nil
        }

        var nextIndex = selectedActionIndex
        for _ in 0..<enabledStates.count {
            nextIndex = (nextIndex + delta + enabledStates.count) % enabledStates.count
            if enabledStates[nextIndex] {
                selectedActionIndex = nextIndex
                applyQuickActionSelection()
                return currentModel.quickActions[selectedActionIndex]
            }
        }

        return nil
    }

    func confirmQuickActionSelection() -> CompanionQuickAction? {
        guard let currentModel,
              currentModel.quickActions.indices.contains(selectedActionIndex) else {
            return nil
        }
        let action = currentModel.quickActions[selectedActionIndex]
        return action.isEnabled ? action : nil
    }

    private func rebuildQuickActions(_ actions: [CompanionQuickAction]) {
        for rowView in actionRowViews {
            actionsStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        let rowHeight = Self.quickActionMinHeight
        let stackSpacing = actionsStack.spacing
        actionsHeightConstraint.constant = actions.isEmpty
            ? 0
            : (CGFloat(actions.count) * rowHeight) + (CGFloat(max(actions.count - 1, 0)) * stackSpacing) + 20
        actionsSurface.isHidden = actions.isEmpty

        actionRowViews = actions.map { action in
            let rowView = CompanionQuickActionRowView(action: action)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: rowHeight).isActive = true
            rowView.widthAnchor.constraint(equalTo: actionsSurface.widthAnchor, constant: -20).isActive = true
            actionsStack.addArrangedSubview(rowView)
            return rowView
        }

        if actions.isEmpty {
            selectedActionIndex = 0
        } else if !actions.indices.contains(selectedActionIndex) || !actions[selectedActionIndex].isEnabled {
            selectedActionIndex = actions.firstIndex(where: \.isEnabled) ?? 0
        }
        applyQuickActionSelection()
    }

    private func applyQuickActionSelection() {
        for (index, rowView) in actionRowViews.enumerated() {
            rowView.isSelected = index == selectedActionIndex
        }
    }

    private func makeTranscriptAttributedString(from transcript: String, phase: CompanionPhase) -> NSAttributedString {
        let full = NSMutableAttributedString()
        let paragraphs = transcript.components(separatedBy: "\n\n")
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex > 0 {
                full.append(NSAttributedString(string: "\n\n"))
            }

            let isUserLine = paragraph.hasPrefix("You:")
            let isCompanionLine = paragraph.hasPrefix("Companion:")
            let isLiveUserLine = phase == .listening && paragraphIndex == paragraphs.count - 1 && isUserLine
            let color: NSColor
            if isLiveUserLine {
                color = NSColor.systemTeal
            } else if isUserLine {
                color = PortalHUDStyle.primaryTextColor
            } else if isCompanionLine {
                color = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.82)
            } else {
                color = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.78)
            }

            let fontWeight: NSFont.Weight = isUserLine ? .semibold : .medium
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 3
            full.append(
                NSAttributedString(
                    string: paragraph,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 14, weight: fontWeight),
                        .foregroundColor: color,
                        .paragraphStyle: paragraphStyle
                    ]
                )
            )
        }
        return full
    }
}

@MainActor
private final class CompanionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class CompanionQuickActionRowView: NSView {
    private let action: CompanionQuickAction
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let detailField: NSTextField

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(action: CompanionQuickAction) {
        self.action = action
        iconView = NSImageView()
        titleField = NSTextField(labelWithString: action.title)
        detailField = NSTextField(wrappingLabelWithString: action.detail)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(self, cornerRadius: 14)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: action.title)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        detailField.maximumNumberOfLines = 2
        detailField.lineBreakMode = .byWordWrapping

        addSubview(iconView)
        addSubview(titleField)
        addSubview(detailField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 9),
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

    private func updateAppearance() {
        let state = isSelected ? PortalRowSurfaceState.selected : (action.isEnabled ? PortalRowSurfaceState.idle : PortalRowSurfaceState.muted)
        applyPortalRowSurface(self, state: state)
        titleField.textColor = action.isEnabled
            ? PortalHUDStyle.primaryTextColor
            : PortalHUDStyle.secondaryTextColor
        detailField.textColor = action.isEnabled
            ? PortalHUDStyle.secondaryTextColor
            : PortalHUDStyle.secondaryTextColor.withAlphaComponent(0.72)
        iconView.contentTintColor = action.isEnabled
            ? (isSelected ? PortalHUDStyle.primaryTextColor : PortalHUDStyle.secondaryTextColor)
            : PortalHUDStyle.secondaryTextColor.withAlphaComponent(0.72)
    }
}

@MainActor
private final class CompanionInputField: NSTextField, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?
    var onTextDidBegin: (() -> Void)?

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
        placeholderString = "Reply or ask something and press Return"
        delegate = self
        target = self
        action = #selector(commitInput)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidChange(_ obj: Notification) {
        onTextDidBegin?()
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
