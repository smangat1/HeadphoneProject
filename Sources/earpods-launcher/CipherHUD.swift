import AppKit

@MainActor
final class CipherCardController {
    private static let rowWidth: CGFloat = 352

    private let window: CipherWindow
    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let veilBadge: CipherStatusBadgeView
    private let sealBadge: CipherStatusBadgeView
    private let spellStack: NSStackView
    private var spellRowViews: [CipherSpellRowView] = []
    private var currentModel: CipherCardModel
    private var selectedIndex = 0

    init(model: CipherCardModel) {
        debugCipherHUD("init begin")
        self.currentModel = model
        self.titleField = NSTextField(labelWithString: model.title)
        self.subtitleField = NSTextField(wrappingLabelWithString: model.subtitle)
        self.veilBadge = CipherStatusBadgeView()
        self.sealBadge = CipherStatusBadgeView()
        self.spellStack = NSStackView()

        let chrome = makePortalHUDChrome(
            accentColor: .systemIndigo,
            tintOpacity: 0.13
        )

        stylePortalTitle(titleField)

        stylePortalSubtitle(subtitleField)
        subtitleField.maximumNumberOfLines = 2
        debugCipherHUD("title and subtitle ready")

        let badgeStack = NSStackView(views: [veilBadge, sealBadge])
        badgeStack.orientation = .horizontal
        badgeStack.alignment = .centerY
        badgeStack.spacing = 10
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        debugCipherHUD("badge stack ready")

        spellStack.orientation = .vertical
        spellStack.alignment = .leading
        spellStack.spacing = 9
        spellStack.translatesAutoresizingMaskIntoConstraints = false
        debugCipherHUD("spell stack ready")

        let contentStack = NSStackView(views: [titleField, subtitleField, badgeStack, spellStack])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        debugCipherHUD("content stack ready")

        chrome.chromeView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),

            subtitleField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            spellStack.widthAnchor.constraint(equalToConstant: Self.rowWidth),
        ])
        debugCipherHUD("constraints ready")

        self.window = CipherWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 342),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        debugCipherHUD("window init complete")
        applyPortalFloatingWindowStyle(self.window)
        self.window.contentView = chrome.rootView
        debugCipherHUD("window configured")

        update(model: model)
        debugCipherHUD("init complete")
    }

    var isVisible: Bool {
        window.isVisible
    }

    func currentSelection() -> (spell: CipherSpell, index: Int)? {
        guard !currentModel.spells.isEmpty else {
            return nil
        }
        let spell = currentModel.spells[selectedIndex]
        guard spell.isEnabled else {
            return nil
        }
        return (spell, selectedIndex)
    }

    func show(model: CipherCardModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        debugCipherHUD("show begin")
        update(model: model, selectedIndex: explicitSelectedIndex)
        centerPortalWindow(window)
        debugCipherHUD("show positioned")
        window.level = .statusBar
        window.ignoresMouseEvents = true
        showPortalWindow(window)
        debugCipherHUD("show displayIfNeeded visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow)")
        return window.isVisible
    }

    func update(model: CipherCardModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        debugCipherHUD("update begin")
        currentModel = model
        titleField.stringValue = model.title
        subtitleField.stringValue = model.subtitle
        veilBadge.configure(title: "Veil", isActive: model.isVeiled, accent: .systemMint)
        sealBadge.configure(title: "Seal", isActive: model.isSealed, accent: .systemOrange)
        rebuildSpells(spells: model.spells)

        if let explicitSelectedIndex {
            selectedIndex = selectableIndex(startingAt: explicitSelectedIndex, direction: 1) ?? 0
        } else if !(model.spells.indices.contains(selectedIndex) && model.spells[selectedIndex].isEnabled) {
            selectedIndex = selectableIndex(startingAt: 0, direction: 1) ?? 0
        }

        applySelection()
        debugCipherHUD("update complete selection=\(selectedIndex)")
    }

    func close() -> Bool {
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> (spell: CipherSpell, index: Int)? {
        guard !currentModel.spells.isEmpty else {
            return nil
        }
        let direction = delta >= 0 ? 1 : -1
        let nextStart = selectedIndex + delta
        guard let nextIndex = selectableIndex(startingAt: nextStart, direction: direction) else {
            return nil
        }
        selectedIndex = nextIndex
        applySelection()
        return currentSelection()
    }

    func confirmSelection() -> (spell: CipherSpell, index: Int)? {
        currentSelection()
    }

    private func rebuildSpells(spells: [CipherSpell]) {
        debugCipherHUD("rebuild begin count=\(spells.count)")
        for rowView in spellRowViews {
            spellStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        spellRowViews = spells.map { spell in
            debugCipherHUD("row init begin \(spell.kind.rawValue): \(spell.title)")
            let rowView = CipherSpellRowView(spell: spell)
            rowView.heightAnchor.constraint(equalToConstant: 54).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            spellStack.addArrangedSubview(rowView)
            debugCipherHUD("row attached \(spell.kind.rawValue): \(spell.title)")
            return rowView
        }
        debugCipherHUD("rebuild complete")
    }

    private func applySelection() {
        for (index, rowView) in spellRowViews.enumerated() {
            rowView.isSelected = index == selectedIndex && currentModel.spells[index].isEnabled
        }
    }

    private func selectableIndex(startingAt rawIndex: Int, direction: Int) -> Int? {
        guard !currentModel.spells.isEmpty else {
            return nil
        }

        var candidate = rawIndex
        let count = currentModel.spells.count
        for _ in 0..<count {
            let normalized = (candidate % count + count) % count
            if currentModel.spells[normalized].isEnabled {
                return normalized
            }
            candidate += direction
        }
        return nil
    }
}

@MainActor
private final class CipherWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CipherSpellRowView: NSView {
    private let iconView: NSImageView
    private let titleField: NSTextField
    private let detailField: NSTextField
    private let enabled: Bool

    var isSelected: Bool = false {
        didSet {
            applyStyle()
        }
    }

    init(spell: CipherSpell) {
        self.iconView = NSImageView()
        self.titleField = NSTextField(labelWithString: spell.title)
        self.detailField = NSTextField(labelWithString: spell.detail)
        self.enabled = spell.isEnabled
        super.init(frame: .zero)

        debugCipherHUD("row view configure surface \(spell.kind.rawValue)")
        configurePortalRowSurface(self, cornerRadius: 18)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        debugCipherHUD("row view symbol lookup begin \(spell.kind.rawValue) symbol=\(spell.symbol)")
        iconView.image = NSImage(systemSymbolName: spell.symbol, accessibilityDescription: spell.title)
        debugCipherHUD("row view symbol lookup complete \(spell.kind.rawValue) symbol=\(spell.symbol)")

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .bold)

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let textStack = NSStackView(views: [titleField, detailField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyStyle()
        debugCipherHUD("row view appearance ready \(spell.kind.rawValue)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyStyle() {
        if enabled {
            iconView.contentTintColor = isSelected ? NSColor.systemMint.withAlphaComponent(0.98) : NSColor.white.withAlphaComponent(0.82)
            titleField.textColor = isSelected ? .white : NSColor.white.withAlphaComponent(0.86)
            detailField.textColor = isSelected ? NSColor.white.withAlphaComponent(0.80) : NSColor.white.withAlphaComponent(0.54)
            applyPortalRowSurface(self, state: isSelected ? .selected : .idle)
        } else {
            iconView.contentTintColor = NSColor.white.withAlphaComponent(0.24)
            titleField.textColor = NSColor.white.withAlphaComponent(0.34)
            detailField.textColor = NSColor.white.withAlphaComponent(0.24)
            applyPortalRowSurface(self, state: .muted)
        }
    }
}

@MainActor
private func debugCipherHUD(_ message: String) {
    portalHUDDebugSink?("CIPHER \(message)")
}

@MainActor
private final class CipherStatusBadgeView: NSView {
    private let dotView: NSView
    private let titleField: NSTextField

    init() {
        self.dotView = NSView()
        self.titleField = NSTextField(labelWithString: "")
        super.init(frame: .zero)

        configurePortalBadgeSurface(self, cornerRadius: 13)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.cornerCurve = .continuous

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 11, weight: .bold)

        addSubview(dotView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),

            titleField.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 7),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isActive: Bool, accent: NSColor) {
        titleField.stringValue = "\(title) \(isActive ? "ON" : "OFF")"
        titleField.textColor = isActive ? .white : NSColor.white.withAlphaComponent(0.60)
        layer?.backgroundColor = isActive
            ? accent.withAlphaComponent(0.22).cgColor
            : PortalHUDStyle.rowIdleFillColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = isActive
            ? accent.withAlphaComponent(0.34).cgColor
            : PortalHUDStyle.surfaceBorderColor.cgColor
        dotView.layer?.backgroundColor = isActive
            ? accent.withAlphaComponent(0.96).cgColor
            : NSColor.white.withAlphaComponent(0.30).cgColor
    }
}
