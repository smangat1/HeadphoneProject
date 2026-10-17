import AppKit
import Foundation

enum WorkQueueSelection {
    case listRow(WorkQueueListRow, Int)
    case detailAction(WorkQueueAction, Int)
}

@MainActor
final class WorkQueueCardController {
    private static let rowWidth: CGFloat = 360

    private enum Mode {
        case list(WorkQueueListModel)
        case detail(WorkQueueDetailModel)
    }

    private let window: WorkQueueWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let metadataField: NSTextField
    private let footerField: NSTextField
    private let rowsStack: NSStackView
    private var rowViews: [WorkQueueRowView] = []
    private var mode: Mode?
    private var selectedIndex = 0

    init() {
        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.11
        )

        self.titleField = NSTextField(labelWithString: "")
        self.subtitleField = NSTextField(wrappingLabelWithString: "")
        self.metadataField = NSTextField(wrappingLabelWithString: "")
        self.footerField = NSTextField(wrappingLabelWithString: "")
        self.rowsStack = NSStackView()

        stylePortalTitle(titleField)

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2

        metadataField.translatesAutoresizingMaskIntoConstraints = false
        metadataField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        metadataField.textColor = NSColor.systemIndigo.withAlphaComponent(0.92)
        metadataField.alignment = .center
        metadataField.maximumNumberOfLines = 3
        metadataField.lineBreakMode = .byTruncatingTail

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

        self.window = WorkQueueWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
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

    var isShowingDetail: Bool {
        if case .detail = mode {
            return true
        }
        return false
    }

    var currentDetailMode: WorkQueueDetailMode? {
        if case .detail(let model) = mode {
            return model.mode
        }
        return nil
    }

    var currentDetailItemID: String? {
        if case .detail(let model) = mode {
            return model.itemID
        }
        return nil
    }

    func currentSelection() -> WorkQueueSelection? {
        guard let mode else {
            return nil
        }

        switch mode {
        case .list(let model):
            guard !model.rows.isEmpty, model.rows.indices.contains(selectedIndex) else {
                return nil
            }
            return .listRow(model.rows[selectedIndex], selectedIndex)
        case .detail(let model):
            guard !model.actions.isEmpty, model.actions.indices.contains(selectedIndex) else {
                return nil
            }
            return .detailAction(model.actions[selectedIndex], selectedIndex)
        }
    }

    func showList(model: WorkQueueListModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        updateList(model: model, selectedIndex: explicitSelectedIndex)
        return revealWindow()
    }

    func updateList(model: WorkQueueListModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        mode = .list(model)
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        metadataField.stringValue = model.metadataText
        footerField.stringValue = model.footer
        rebuildRows(for: model.rows.map {
            WorkQueueDisplayRow(
                symbol: $0.symbol,
                title: $0.title,
                detail: $0.detail,
                isEnabled: $0.isEnabled,
                style: WorkQueueDisplayRow.Style($0.style),
                label: $0.label
            )
        })
        applySelection(explicitSelectedIndex)
    }

    func showDetail(model: WorkQueueDetailModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        updateDetail(model: model, selectedIndex: explicitSelectedIndex)
        return revealWindow()
    }

    func updateDetail(model: WorkQueueDetailModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        mode = .detail(model)
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        metadataField.stringValue = model.metadataText
        footerField.stringValue = model.footer
        rebuildRows(for: model.actions.map {
            WorkQueueDisplayRow(
                symbol: $0.symbol,
                title: $0.title,
                detail: $0.detail,
                isEnabled: $0.isEnabled,
                style: .action,
                label: nil
            )
        })
        applySelection(explicitSelectedIndex)
    }

    func reshowCurrentState() -> Bool {
        guard mode != nil else {
            return false
        }
        return revealWindow()
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> WorkQueueSelection? {
        let rows = selectableStates()
        guard !rows.isEmpty else {
            return nil
        }

        var nextIndex = selectedIndex
        for _ in 0..<rows.count {
            nextIndex = (nextIndex + delta + rows.count) % rows.count
            if rows[nextIndex] {
                selectedIndex = nextIndex
                updateSelection()
                return currentSelection()
            }
        }

        return nil
    }

    func confirmSelection() -> WorkQueueSelection? {
        guard let selection = currentSelection() else {
            return nil
        }

        switch selection {
        case .listRow(let row, _):
            guard row.isEnabled else { return nil }
        case .detailAction(let action, _):
            guard action.isEnabled else { return nil }
        }

        return selection
    }

    private func rebuildRows(for rows: [WorkQueueDisplayRow]) {
        for rowView in rowViews {
            rowsStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        rowViews = rows.map { row in
            let rowView = WorkQueueRowView(row: row)
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: row.minimumHeight).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            rowsStack.addArrangedSubview(rowView)
            return rowView
        }
    }

    private func applySelection(_ explicitSelectedIndex: Int?) {
        let states = selectableStates()
        if states.isEmpty {
            selectedIndex = 0
            updateSelection()
            return
        }

        if let explicitSelectedIndex, states.indices.contains(explicitSelectedIndex), states[explicitSelectedIndex] {
            selectedIndex = explicitSelectedIndex
        } else if !states.indices.contains(selectedIndex) || !states[selectedIndex] {
            selectedIndex = states.firstIndex(of: true) ?? 0
        }

        updateSelection()
    }

    private func updateSelection() {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }
    }

    private func selectableStates() -> [Bool] {
        switch mode {
        case .list(let model):
            return model.rows.map(\.isEnabled)
        case .detail(let model):
            return model.actions.map(\.isEnabled)
        case .none:
            return []
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

private struct WorkQueueDisplayRow {
    enum Style {
        case featured
        case queued
        case utility
        case action
    }

    let symbol: String
    let title: String
    let detail: String
    let isEnabled: Bool
    let style: Style
    let label: WorkQueueLabel?

    var minimumHeight: CGFloat {
        switch style {
        case .featured:
            return 72
        case .queued:
            return 52
        case .utility, .action:
            return 48
        }
    }
}

private extension WorkQueueDisplayRow.Style {
    init(_ style: WorkQueueListRowStyle) {
        switch style {
        case .featured:
            self = .featured
        case .queued:
            self = .queued
        case .utility:
            self = .utility
        }
    }
}

@MainActor
private final class WorkQueueWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class WorkQueueRowView: NSView {
    private let eyebrowField: NSTextField
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let titleRow: NSStackView
    private let detailField: NSTextField
    private let labelBadgeView: WorkQueueLabelBadgeView
    private let isEnabled: Bool
    private let style: WorkQueueDisplayRow.Style

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(row: WorkQueueDisplayRow) {
        self.eyebrowField = NSTextField(labelWithString: WorkQueueRowView.eyebrowText(for: row.style))
        self.iconView = NSImageView()
        self.titleField = NSTextField(labelWithString: row.title)
        self.labelBadgeView = WorkQueueLabelBadgeView()
        self.titleRow = NSStackView()
        self.detailField = NSTextField(wrappingLabelWithString: row.detail)
        self.isEnabled = row.isEnabled
        self.style = row.style
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        configurePortalRowSurface(self, cornerRadius: row.style == .featured ? 18 : PortalHUDStyle.rowCornerRadius)

        eyebrowField.translatesAutoresizingMaskIntoConstraints = false
        eyebrowField.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        eyebrowField.textColor = NSColor.systemIndigo.withAlphaComponent(0.92)
        eyebrowField.alignment = .left
        eyebrowField.isHidden = eyebrowField.stringValue.isEmpty

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: row.style == .featured ? 16 : 14,
            weight: .semibold
        )
        iconView.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.title)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: row.title)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: row.style == .featured ? 15 : 14, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addArrangedSubview(titleField)
        titleRow.addArrangedSubview(labelBadgeView)

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        detailField.maximumNumberOfLines = row.style == .featured ? 3 : 2
        detailField.lineBreakMode = .byTruncatingTail

        addSubview(eyebrowField)
        addSubview(iconView)
        addSubview(titleRow)
        addSubview(detailField)

        let topInset: CGFloat = row.style == .featured ? 12 : 10
        let titleTopAnchor = eyebrowField.isHidden ? topAnchor : eyebrowField.bottomAnchor
        let titleTopConstant: CGFloat = eyebrowField.isHidden ? topInset : 2

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),

            eyebrowField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            eyebrowField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            eyebrowField.topAnchor.constraint(equalTo: topAnchor, constant: topInset),

            titleRow.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleRow.topAnchor.constraint(equalTo: titleTopAnchor, constant: titleTopConstant),

            detailField.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            detailField.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            detailField.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 2),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        if let label = row.label {
            labelBadgeView.configure(label: label)
            labelBadgeView.isHidden = false
        } else {
            labelBadgeView.isHidden = true
        }

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
            case .utility:
                state = isSelected ? .selected : .muted
            default:
                state = isSelected ? .selected : .idle
            }
        }

        applyPortalRowSurface(self, state: state)
        iconView.contentTintColor = colorForState(isSelected: isSelected, enabled: isEnabled, emphasis: .icon)
        titleField.textColor = colorForState(isSelected: isSelected, enabled: isEnabled, emphasis: .primary)
        detailField.textColor = colorForState(isSelected: isSelected, enabled: isEnabled, emphasis: .secondary)
        eyebrowField.textColor = isSelected
            ? PortalHUDStyle.secondaryTextColor
            : NSColor.systemIndigo.withAlphaComponent(isEnabled ? 0.92 : 0.35)
        labelBadgeView.applySelectionState(isSelected: isSelected, enabled: isEnabled)
    }

    private static func eyebrowText(for style: WorkQueueDisplayRow.Style) -> String {
        switch style {
        case .featured:
            return "CURRENT THREAD"
        case .queued:
            return "UP NEXT"
        case .utility:
            return "QUEUE TOOLS"
        case .action:
            return ""
        }
    }
}

@MainActor
private final class WorkQueueLabelBadgeView: NSView {
    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")
    private var accentColor: NSColor = .systemIndigo

    init() {
        super.init(frame: .zero)

        configurePortalBadgeSurface(self, cornerRadius: 10)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.systemFont(ofSize: 10, weight: .bold)

        addSubview(iconView)
        addSubview(textField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(label: WorkQueueLabel) {
        accentColor = label.tintColor
        iconView.image = NSImage(systemSymbolName: label.symbol, accessibilityDescription: label.title)
        textField.stringValue = label.title
        layer?.backgroundColor = label.tintColor.withAlphaComponent(0.10).cgColor
        layer?.borderColor = label.tintColor.withAlphaComponent(0.28).cgColor
        applySelectionState(isSelected: false, enabled: true)
    }

    func applySelectionState(isSelected: Bool, enabled: Bool) {
        let textAlpha: CGFloat = enabled ? (isSelected ? 0.98 : 0.92) : 0.45
        let iconAlpha: CGFloat = enabled ? (isSelected ? 1.0 : 0.96) : 0.45
        textField.textColor = NSColor.white.withAlphaComponent(textAlpha)
        iconView.contentTintColor = accentColor.withAlphaComponent(iconAlpha)
        alphaValue = enabled ? 1.0 : 0.75
    }
}
