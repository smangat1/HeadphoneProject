import AppKit
import Foundation

@MainActor
final class TimerCardController {
    private static let rowWidth: CGFloat = 360

    private let window: TimerWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let footerField: NSTextField
    private let setupSummaryField: NSTextField
    private let digitalField: NSTextField
    private let dialView: TimerDialView
    private let primaryTimeField: NSTextField
    private let dialContainer: NSView
    private let fieldsStack: NSStackView
    private let relatedTimersHeaderField: NSTextField
    private let relatedTimersStack: NSStackView
    private var fieldRowViews: [TimerFieldRowView] = []
    private var relatedTimerRowViews: [TimerRelatedTimerRowView] = []

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemMint,
            tintOpacity: 0.10
        )

        self.titleField = NSTextField(labelWithString: "")
        self.subtitleField = NSTextField(wrappingLabelWithString: "")
        self.footerField = NSTextField(wrappingLabelWithString: "")
        self.setupSummaryField = NSTextField(labelWithString: "")
        self.digitalField = NSTextField(labelWithString: "")
        self.dialView = TimerDialView()
        self.primaryTimeField = NSTextField(labelWithString: "")
        self.dialContainer = NSView()
        self.fieldsStack = NSStackView()
        self.relatedTimersHeaderField = NSTextField(labelWithString: "")
        self.relatedTimersStack = NSStackView()

        stylePortalTitle(titleField)

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        stylePortalFooter(footerField)
        footerField.maximumNumberOfLines = 2

        setupSummaryField.translatesAutoresizingMaskIntoConstraints = false
        setupSummaryField.font = NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .bold)
        setupSummaryField.textColor = NSColor.systemMint.withAlphaComponent(0.95)
        setupSummaryField.alignment = .center

        digitalField.translatesAutoresizingMaskIntoConstraints = false
        digitalField.font = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        digitalField.textColor = NSColor.systemMint.withAlphaComponent(0.95)
        digitalField.alignment = .center

        dialContainer.translatesAutoresizingMaskIntoConstraints = false
        dialContainer.wantsLayer = true
        dialContainer.layer?.cornerRadius = 28
        dialContainer.layer?.cornerCurve = .continuous
        dialContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
        dialContainer.layer?.borderWidth = 1
        dialContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor

        dialView.translatesAutoresizingMaskIntoConstraints = false
        primaryTimeField.translatesAutoresizingMaskIntoConstraints = false
        primaryTimeField.font = NSFont.monospacedDigitSystemFont(ofSize: 38, weight: .bold)
        primaryTimeField.textColor = .white
        primaryTimeField.alignment = .center

        dialContainer.addSubview(dialView)
        dialContainer.addSubview(primaryTimeField)

        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsStack.spacing = 8
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false

        relatedTimersHeaderField.translatesAutoresizingMaskIntoConstraints = false
        relatedTimersHeaderField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        relatedTimersHeaderField.textColor = NSColor.systemMint.withAlphaComponent(0.92)
        relatedTimersHeaderField.alignment = .center

        relatedTimersStack.orientation = .vertical
        relatedTimersStack.alignment = .leading
        relatedTimersStack.spacing = 8
        relatedTimersStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [titleField, subtitleField, setupSummaryField, dialContainer, digitalField, fieldsStack, relatedTimersHeaderField, relatedTimersStack, footerField])
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

            dialContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 0.62),
            dialContainer.heightAnchor.constraint(equalTo: dialContainer.widthAnchor),

            dialView.leadingAnchor.constraint(equalTo: dialContainer.leadingAnchor),
            dialView.trailingAnchor.constraint(equalTo: dialContainer.trailingAnchor),
            dialView.topAnchor.constraint(equalTo: dialContainer.topAnchor),
            dialView.bottomAnchor.constraint(equalTo: dialContainer.bottomAnchor),

            primaryTimeField.centerXAnchor.constraint(equalTo: dialContainer.centerXAnchor),
            primaryTimeField.centerYAnchor.constraint(equalTo: dialContainer.centerYAnchor),
            primaryTimeField.leadingAnchor.constraint(greaterThanOrEqualTo: dialContainer.leadingAnchor, constant: 24),
            primaryTimeField.trailingAnchor.constraint(lessThanOrEqualTo: dialContainer.trailingAnchor, constant: -24),

            fieldsStack.widthAnchor.constraint(equalToConstant: Self.rowWidth),
            relatedTimersHeaderField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            relatedTimersStack.widthAnchor.constraint(equalToConstant: Self.rowWidth),
            setupSummaryField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            subtitleField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            footerField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        self.window = TimerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(self.window)
        self.window.contentView = chrome.rootView
    }

    var isVisible: Bool {
        window.isVisible
    }

    func show(model: TimerCardModel) -> Bool {
        update(model: model)
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        showPortalWindow(window)
        return window.isVisible
    }

    func update(model: TimerCardModel) {
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        footerField.stringValue = model.footer
        primaryTimeField.stringValue = model.primaryTimeText
        setupSummaryField.stringValue = model.digitalTimeText
        digitalField.stringValue = model.digitalTimeText
        dialView.progress = model.ringProgress
        dialView.handProgress = model.handProgress
        dialView.stage = model.stage
        let showsDial = model.stage != .setting
        dialContainer.isHidden = !showsDial
        digitalField.isHidden = !showsDial
        setupSummaryField.isHidden = showsDial
        rebuildRows(model.fields, hidden: model.stage != .setting)
        rebuildRelatedTimerRows(model.relatedTimersTitle, rows: model.relatedTimers)
        resizeWindow(for: model.stage, relatedTimerCount: model.relatedTimers.count)
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    private func rebuildRows(_ fields: [TimerFieldDisplay], hidden: Bool) {
        for rowView in fieldRowViews {
            fieldsStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        fieldRowViews = fields.map { field in
            let rowView = TimerFieldRowView(field: field)
            rowView.heightAnchor.constraint(equalToConstant: 42).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            fieldsStack.addArrangedSubview(rowView)
            return rowView
        }

        fieldsStack.isHidden = hidden
    }

    private func rebuildRelatedTimerRows(_ title: String?, rows: [TimerRelatedTimerDisplay]) {
        for rowView in relatedTimerRowViews {
            relatedTimersStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }
        relatedTimerRowViews.removeAll()

        relatedTimersHeaderField.stringValue = title ?? ""
        relatedTimersHeaderField.isHidden = rows.isEmpty
        relatedTimersStack.isHidden = rows.isEmpty

        guard !rows.isEmpty else {
            return
        }

        relatedTimerRowViews = rows.map { row in
            let rowView = TimerRelatedTimerRowView(row: row)
            rowView.heightAnchor.constraint(equalToConstant: 50).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            relatedTimersStack.addArrangedSubview(rowView)
            return rowView
        }
    }

    private func resizeWindow(for stage: TimerStage, relatedTimerCount: Int) {
        let targetHeight: CGFloat
        switch stage {
        case .setting:
            targetHeight = relatedTimerCount > 0 ? 560 : 470
        case .running, .paused, .finished:
            targetHeight = relatedTimerCount > 0 ? 690 + CGFloat(max(0, min(relatedTimerCount, 4) - 1) * 58) : 640
        }

        if abs(window.frame.height - targetHeight) < 0.5 {
            return
        }

        let frame = window.frame
        let updatedFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - (targetHeight - frame.height) / 2,
            width: frame.width,
            height: targetHeight
        )
        window.setFrame(updatedFrame, display: true)
    }
}

@MainActor
private final class TimerWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class TimerFieldRowView: NSView {
    private let titleField: NSTextField
    private let valueField: NSTextField

    init(field: TimerFieldDisplay) {
        self.titleField = NSTextField(labelWithString: field.title)
        self.valueField = NSTextField(labelWithString: field.valueText)
        super.init(frame: .zero)

        configurePortalRowSurface(self)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: field.isSelected ? .bold : .semibold)
        titleField.textColor = field.isSelected ? .white : NSColor.white.withAlphaComponent(0.78)

        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: field.isSelected ? 22 : 18, weight: .bold)
        valueField.textColor = .white

        addSubview(titleField)
        addSubview(valueField)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyPortalRowSurface(self, state: field.isSelected ? .selected : .idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class TimerRelatedTimerRowView: NSView {
    private let titleField: NSTextField
    private let detailField: NSTextField
    private let valueField: NSTextField
    private let symbolView: NSImageView

    init(row: TimerRelatedTimerDisplay) {
        self.titleField = NSTextField(labelWithString: row.title)
        self.detailField = NSTextField(labelWithString: row.detail)
        self.valueField = NSTextField(labelWithString: row.valueText)
        self.symbolView = NSImageView()
        super.init(frame: .zero)

        configurePortalRowSurface(self)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        symbolView.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.title)
        symbolView.contentTintColor = NSColor.systemMint.withAlphaComponent(0.88)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .white

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailField.textColor = NSColor.white.withAlphaComponent(0.64)
        detailField.maximumNumberOfLines = 2

        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .bold)
        valueField.textColor = NSColor.systemMint.withAlphaComponent(0.95)
        valueField.alignment = .right

        let textStack = NSStackView(views: [titleField, detailField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(symbolView)
        addSubview(textStack)
        addSubview(valueField)

        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: valueField.leadingAnchor, constant: -10),

            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyPortalRowSurface(self, state: .muted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class TimerDialView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    var handProgress: Double = 0 {
        didSet { needsDisplay = true }
    }

    var stage: TimerStage = .setting {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let bounds = self.bounds.insetBy(dx: 18, dy: 18)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        let ringWidth: CGFloat = 14

        context.setFillColor(NSColor.clear.cgColor)
        context.fill(bounds)

        let facePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 8, dy: 8))
        NSColor.white.withAlphaComponent(0.035).setFill()
        facePath.fill()

        let tickColor = NSColor.white.withAlphaComponent(0.14)
        for tick in 0..<60 {
            let angle = (Double(tick) / 60.0) * (.pi * 2) - (.pi / 2)
            let outer = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let innerDistance = tick.isMultiple(of: 5) ? radius - 18 : radius - 10
            let inner = CGPoint(x: center.x + cos(angle) * innerDistance, y: center.y + sin(angle) * innerDistance)
            let path = NSBezierPath()
            path.move(to: inner)
            path.line(to: outer)
            path.lineWidth = tick.isMultiple(of: 5) ? 2 : 1
            tickColor.setStroke()
            path.stroke()
        }

        let ringRect = NSRect(
            x: center.x - radius + (ringWidth / 2),
            y: center.y - radius + (ringWidth / 2),
            width: (radius * 2) - ringWidth,
            height: (radius * 2) - ringWidth
        )

        let baseRing = NSBezierPath(ovalIn: ringRect)
        baseRing.lineWidth = ringWidth
        NSColor.white.withAlphaComponent(0.10).setStroke()
        baseRing.stroke()

        let accentColor: NSColor
        switch stage {
        case .setting:
            accentColor = NSColor.systemMint.withAlphaComponent(0.82)
        case .running:
            accentColor = NSColor.systemMint.withAlphaComponent(0.98)
        case .paused:
            accentColor = NSColor.systemOrange.withAlphaComponent(0.96)
        case .finished:
            accentColor = NSColor.systemRed.withAlphaComponent(0.96)
        }

        if progress > 0 {
            let clamped = max(0.0, min(progress, 1.0))
            let startAngle = -90.0
            let endAngle = startAngle + (clamped * 360.0)

            let glowPath = NSBezierPath()
            glowPath.appendArc(withCenter: center, radius: radius - (ringWidth / 2), startAngle: startAngle, endAngle: endAngle, clockwise: false)
            glowPath.lineWidth = ringWidth + 6
            glowPath.lineCapStyle = .round
            accentColor.withAlphaComponent(0.18).setStroke()
            glowPath.stroke()

            let progressPath = NSBezierPath()
            progressPath.appendArc(withCenter: center, radius: radius - (ringWidth / 2), startAngle: startAngle, endAngle: endAngle, clockwise: false)
            progressPath.lineWidth = ringWidth
            progressPath.lineCapStyle = .round
            accentColor.setStroke()
            progressPath.stroke()
        }

        let handAngle = (handProgress * (.pi * 2)) - (.pi / 2)
        let handLength = radius - 30
        let handEnd = CGPoint(
            x: center.x + cos(handAngle) * handLength,
            y: center.y + sin(handAngle) * handLength
        )
        let handPath = NSBezierPath()
        handPath.move(to: center)
        handPath.line(to: handEnd)
        handPath.lineWidth = 4
        handPath.lineCapStyle = .round
        accentColor.setStroke()
        handPath.stroke()

        let endDot = NSBezierPath(ovalIn: NSRect(x: handEnd.x - 5, y: handEnd.y - 5, width: 10, height: 10))
        accentColor.setFill()
        endDot.fill()

        let centerDot = NSBezierPath(ovalIn: NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        accentColor.setFill()
        centerDot.fill()
    }
}
