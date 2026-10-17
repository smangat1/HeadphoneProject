import AppKit
import Foundation

@MainActor
final class NowPlayingCardController {
    private static let artworkCache = NSCache<NSURL, NSImage>()
    private static let expandedWindowSize = NSSize(width: 432, height: 724)
    private static let compactWindowSize = NSSize(width: 432, height: 646)
    private static let expandedArtworkSize: CGFloat = 262
    private static let compactArtworkSize: CGFloat = 220

    private let window: NowPlayingWindow
    private let badgeView: NowPlayingBadgeView
    private let stateField: NSTextField
    private let titleField: NSTextField
    private let artistField: NSTextField
    private let albumField: NSTextField
    private let sessionField: NSTextField
    private let artworkContainer: NSView
    private let artworkImageView: NSImageView
    private let actionStack: NSStackView
    private let artworkWidthConstraint: NSLayoutConstraint
    private let artworkHeightConstraint: NSLayoutConstraint
    private let actionStackHeightConstraint: NSLayoutConstraint
    private var actionRowViews: [NowPlayingActionRowView] = []
    private var currentModel: NowPlayingCardModel = .empty
    private var currentActionSignature: [String] = []
    private var currentLayoutSource: NowPlayingSource?
    private var selectedIndex = 0
    private var artworkTask: URLSessionDataTask?
    private var activeArtworkURL: URL?
    private var displayedArtworkURL: URL?

    init() {
        debugNowPlaying("init begin")
        let chrome = makePortalHUDChrome(
            accentColor: .systemMint,
            tintOpacity: 0.10
        )
        debugNowPlaying("chrome ready")

        self.badgeView = NowPlayingBadgeView()
        self.stateField = NSTextField(labelWithString: "")
        self.titleField = NSTextField(labelWithString: "")
        self.artistField = NSTextField(labelWithString: "")
        self.albumField = NSTextField(labelWithString: "")
        self.sessionField = NSTextField(labelWithString: "")
        self.artworkContainer = NSView()
        self.artworkImageView = NSImageView()
        self.actionStack = NSStackView()
        debugNowPlaying("views ready")

        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .centerX
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        debugNowPlaying("header stack ready")

        stateField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        stateField.textColor = NSColor.white.withAlphaComponent(0.70)
        stateField.alignment = .center

        titleField.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 2
        titleField.alignment = .center

        artistField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        artistField.textColor = NSColor.white.withAlphaComponent(0.88)
        artistField.lineBreakMode = .byTruncatingTail
        artistField.maximumNumberOfLines = 1
        artistField.alignment = .center

        albumField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        albumField.textColor = NSColor.white.withAlphaComponent(0.60)
        albumField.lineBreakMode = .byTruncatingTail
        albumField.maximumNumberOfLines = 1
        albumField.alignment = .center

        sessionField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sessionField.textColor = NSColor.systemMint.withAlphaComponent(0.95)
        sessionField.alignment = .center

        headerStack.addArrangedSubview(badgeView)
        headerStack.addArrangedSubview(stateField)
        headerStack.addArrangedSubview(titleField)
        headerStack.addArrangedSubview(artistField)
        headerStack.addArrangedSubview(albumField)
        headerStack.addArrangedSubview(sessionField)

        artworkContainer.translatesAutoresizingMaskIntoConstraints = false
        artworkContainer.wantsLayer = true
        artworkContainer.layer?.cornerRadius = 22
        artworkContainer.layer?.cornerCurve = .continuous
        artworkContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        artworkContainer.layer?.borderWidth = 1
        artworkContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.imageAlignment = .alignCenter
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkContainer.addSubview(artworkImageView)
        debugNowPlaying("artwork container ready")

        actionStack.orientation = .vertical
        actionStack.alignment = .centerX
        actionStack.distribution = .fill
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.setContentHuggingPriority(.required, for: .vertical)
        actionStack.setContentCompressionResistancePriority(.required, for: .vertical)
        debugNowPlaying("action stack ready")

        let contentStack = NSStackView(views: [artworkContainer, headerStack, actionStack])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        debugNowPlaying("content stack ready")

        chrome.chromeView.addSubview(contentStack)

        artworkWidthConstraint = artworkContainer.widthAnchor.constraint(equalToConstant: Self.expandedArtworkSize)
        artworkHeightConstraint = artworkContainer.heightAnchor.constraint(equalToConstant: Self.expandedArtworkSize)
        actionStackHeightConstraint = actionStack.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: chrome.chromeView.leadingAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: chrome.chromeView.trailingAnchor, constant: -PortalHUDStyle.contentInset),
            contentStack.topAnchor.constraint(equalTo: chrome.chromeView.topAnchor, constant: PortalHUDStyle.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: chrome.chromeView.bottomAnchor, constant: -PortalHUDStyle.contentInset),

            artworkWidthConstraint,
            artworkHeightConstraint,

            artworkImageView.leadingAnchor.constraint(equalTo: artworkContainer.leadingAnchor),
            artworkImageView.trailingAnchor.constraint(equalTo: artworkContainer.trailingAnchor),
            artworkImageView.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
            artworkImageView.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor),

            headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            actionStack.widthAnchor.constraint(equalToConstant: 340),
            actionStackHeightConstraint,
        ])
        debugNowPlaying("constraints ready")

        self.window = NowPlayingWindow(
            contentRect: NSRect(origin: .zero, size: Self.expandedWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        applyPortalFloatingWindowStyle(self.window)
        self.window.contentView = chrome.rootView
        debugNowPlaying("window ready")

        setArtworkPlaceholder(source: .none)
        debugNowPlaying("placeholder ready")
        rebuildActions(actions: currentModel.actions)
        debugNowPlaying("actions ready")
        applySelection()
        debugNowPlaying("selection ready")
    }

    var isVisible: Bool {
        window.isVisible
    }

    func currentSelection() -> (action: NowPlayingAction, index: Int)? {
        guard !currentModel.actions.isEmpty else {
            return nil
        }
        return (currentModel.actions[selectedIndex], selectedIndex)
    }

    func show(model: NowPlayingCardModel, selectedIndex explicitSelectedIndex: Int? = nil) -> Bool {
        update(model: model, selectedIndex: explicitSelectedIndex)
        centerPortalWindow(window)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        showPortalWindow(window)
        return window.isVisible
    }

    func update(model: NowPlayingCardModel, selectedIndex explicitSelectedIndex: Int? = nil) {
        currentModel = model
        if let explicitSelectedIndex {
            selectedIndex = min(max(explicitSelectedIndex, 0), max(model.actions.count - 1, 0))
        } else if !model.actions.isEmpty {
            selectedIndex = min(selectedIndex, model.actions.count - 1)
        } else {
            selectedIndex = 0
        }

        badgeView.configure(title: model.snapshot.source.displayName, symbolName: model.snapshot.source.badgeSymbol)
        applyLayoutIfNeeded(for: model.snapshot.source)
        if model.snapshot.source == .none {
            stateField.stringValue = "No active media yet."
            titleField.stringValue = model.snapshot.title
            artistField.stringValue = "Open Spotify, Music, or a browser video from here."
            albumField.stringValue = "Use the actions below to jump into a player."
            sessionField.stringValue = ""
            sessionField.isHidden = true
        } else {
            stateField.stringValue = "\(model.snapshot.playerState.displayName) in \(model.snapshot.source.displayName)"
            titleField.stringValue = model.snapshot.title
            artistField.stringValue = model.snapshot.artist
            albumField.stringValue = model.snapshot.album.isEmpty ? "Use the actions below to jump into a player." : model.snapshot.album
            sessionField.stringValue = model.sessionText
            sessionField.isHidden = false
        }

        let nextActionSignature = model.actions.map { "\($0.kind.rawValue)|\($0.title)|\($0.symbol)" }
        if nextActionSignature != currentActionSignature {
            rebuildActions(actions: model.actions)
            currentActionSignature = nextActionSignature
        }
        applySelection()
        loadArtwork(from: model.snapshot.artworkURL, source: model.snapshot.source)
    }

    func close() -> Bool {
        artworkTask?.cancel()
        artworkTask = nil
        window.orderOut(nil)
        return !window.isVisible
    }

    func moveSelection(by delta: Int) -> (action: NowPlayingAction, index: Int)? {
        guard !currentModel.actions.isEmpty else {
            return nil
        }
        selectedIndex = (selectedIndex + delta + currentModel.actions.count) % currentModel.actions.count
        applySelection()
        return currentSelection()
    }

    func confirmSelection() -> (action: NowPlayingAction, index: Int)? {
        currentSelection()
    }

    private func rebuildActions(actions: [NowPlayingAction]) {
        for rowView in actionRowViews {
            actionStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        let rowHeight: CGFloat = 40
        let stackSpacing = actionStack.spacing
        actionStackHeightConstraint.constant = actions.isEmpty
            ? 0
            : (CGFloat(actions.count) * rowHeight) + (CGFloat(max(actions.count - 1, 0)) * stackSpacing)

        actionRowViews = actions.map { action in
            debugNowPlaying("action row init begin \(action.kind.rawValue): \(action.title)")
            let rowView = NowPlayingActionRowView(action: action)
            rowView.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            rowView.widthAnchor.constraint(equalToConstant: 340).isActive = true
            actionStack.addArrangedSubview(rowView)
            debugNowPlaying("action row attached \(action.kind.rawValue): \(action.title)")
            return rowView
        }
    }

    private func applySelection() {
        for (index, rowView) in actionRowViews.enumerated() {
            rowView.isSelected = index == selectedIndex
        }
    }

    private func applyLayoutIfNeeded(for source: NowPlayingSource) {
        guard currentLayoutSource != source else {
            return
        }
        currentLayoutSource = source

        let isEmpty = source == .none
        artworkWidthConstraint.constant = isEmpty ? Self.compactArtworkSize : Self.expandedArtworkSize
        artworkHeightConstraint.constant = isEmpty ? Self.compactArtworkSize : Self.expandedArtworkSize
        let targetSize = isEmpty ? Self.compactWindowSize : Self.expandedWindowSize
        if window.frame.size != targetSize {
            window.setContentSize(targetSize)
        }
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func loadArtwork(from artworkURL: URL?, source: NowPlayingSource) {
        guard let artworkURL else {
            artworkTask?.cancel()
            artworkTask = nil
            activeArtworkURL = nil
            displayedArtworkURL = nil
            setArtworkPlaceholder(source: source)
            return
        }

        if displayedArtworkURL == artworkURL, artworkImageView.image != nil {
            activeArtworkURL = artworkURL
            return
        }

        if activeArtworkURL == artworkURL, artworkTask != nil {
            return
        }

        if let cachedImage = Self.artworkCache.object(forKey: artworkURL as NSURL) {
            artworkTask?.cancel()
            artworkTask = nil
            activeArtworkURL = artworkURL
            displayedArtworkURL = artworkURL
            artworkImageView.contentTintColor = nil
            artworkImageView.image = cachedImage
            return
        }

        artworkTask?.cancel()
        artworkTask = nil
        activeArtworkURL = artworkURL

        artworkTask = URLSession.shared.dataTask(with: artworkURL) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else {
                return
            }
            Task { @MainActor in
                guard self.activeArtworkURL == artworkURL else {
                    return
                }
                Self.artworkCache.setObject(image, forKey: artworkURL as NSURL)
                self.displayedArtworkURL = artworkURL
                self.artworkImageView.contentTintColor = nil
                self.artworkImageView.image = image
            }
        }
        artworkTask?.resume()
    }

    private func setArtworkPlaceholder(source: NowPlayingSource) {
        displayedArtworkURL = nil
        artworkImageView.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        artworkImageView.image = NSImage(
            systemSymbolName: source == .none ? "music.note.list" : "waveform.circle.fill",
            accessibilityDescription: "Now Playing artwork placeholder"
        )
    }
}

@MainActor
private func debugNowPlaying(_ message: String) {
    portalHUDDebugSink?("NOW_PLAYING \(message)")
    print("[NOW PLAYING INIT] \(message)")
    fflush(stdout)
}

@MainActor
private final class NowPlayingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class NowPlayingActionRowView: NSView {
    private let iconView: NSImageView
    private let titleField: NSTextField

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(action: NowPlayingAction) {
        debugNowPlaying("action row view init begin \(action.kind.rawValue)")
        self.iconView = NSImageView()
        self.titleField = NSTextField(labelWithString: action.title)
        super.init(frame: .zero)

        configurePortalRowSurface(self)
        debugNowPlaying("action row surface ready \(action.kind.rawValue)")

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: action.title)
        debugNowPlaying("action row symbol ready \(action.kind.rawValue)")

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail

        addSubview(iconView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
        debugNowPlaying("action row view init complete \(action.kind.rawValue)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        if isSelected {
            applyPortalRowSurface(self, state: .selected)
            layer?.borderWidth = 1
            layer?.borderColor = PortalHUDStyle.rowSelectedBorderColor.cgColor
            titleField.textColor = PortalHUDStyle.primaryTextColor
            iconView.contentTintColor = PortalHUDStyle.primaryTextColor
        } else {
            applyPortalRowSurface(self, state: .idle)
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.04).cgColor
            titleField.textColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.86)
            iconView.contentTintColor = PortalHUDStyle.primaryTextColor.withAlphaComponent(0.66)
        }

        layer?.actions = [
            "backgroundColor": NSNull(),
            "borderColor": NSNull(),
            "borderWidth": NSNull()
        ]
    }
}

@MainActor
private final class NowPlayingBadgeView: NSView {
    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)

        configurePortalBadgeSurface(self)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        iconView.contentTintColor = NSColor.systemMint.withAlphaComponent(0.98)

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
